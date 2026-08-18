use anyhow::{anyhow, Result};
use chrono::{DateTime, Local, Utc};
use log::{debug, error, info};
use rusqlite::{params, Connection, OptionalExtension};
use rusqlite_migration::{Migrations, M};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::sync::Mutex;
use tauri::AppHandle;
use tauri_specta::Event;

/// Database migrations for transcription history.
/// Each migration is applied in order. The library tracks which migrations
/// have been applied using SQLite's user_version pragma.
///
/// Note: For users upgrading from tauri-plugin-sql, migrate_from_tauri_plugin_sql()
/// converts the old _sqlx_migrations table tracking to the user_version pragma,
/// ensuring migrations don't re-run on existing databases.
static MIGRATIONS: &[M] = &[
    M::up(
        "CREATE TABLE IF NOT EXISTS transcription_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            saved BOOLEAN NOT NULL DEFAULT 0,
            title TEXT NOT NULL,
            transcription_text TEXT NOT NULL
        );",
    ),
    M::up("ALTER TABLE transcription_history ADD COLUMN post_processed_text TEXT;"),
    M::up("ALTER TABLE transcription_history ADD COLUMN post_process_prompt TEXT;"),
    M::up("ALTER TABLE transcription_history ADD COLUMN post_process_requested BOOLEAN NOT NULL DEFAULT 0;"),
    M::up(
        "ALTER TABLE transcription_history ADD COLUMN transcription_ciphertext BLOB;
         ALTER TABLE transcription_history ADD COLUMN post_processed_ciphertext BLOB;
         ALTER TABLE transcription_history ADD COLUMN post_process_prompt_ciphertext BLOB;
         ALTER TABLE transcription_history ADD COLUMN encryption_version INTEGER NOT NULL DEFAULT 0;
         ALTER TABLE transcription_history ADD COLUMN audio_available BOOLEAN NOT NULL DEFAULT 1;
         ALTER TABLE transcription_history ADD COLUMN audio_saved BOOLEAN NOT NULL DEFAULT 0;",
    ),
    M::up(
        "ALTER TABLE transcription_history ADD COLUMN metadata_ciphertext BLOB;",
    ),
];

const ENCRYPTION_VERSION: i64 = 1;
const HISTORY_COLUMNS: &str = "id, file_name, timestamp, saved, title, post_process_requested, \
    transcription_ciphertext, post_processed_ciphertext, post_process_prompt_ciphertext, \
    encryption_version, audio_available, audio_saved, metadata_ciphertext";

fn is_safe_audio_identifier(file_name: &str, encrypted_only: bool) -> bool {
    let mut components = Path::new(file_name).components();
    let is_single_file =
        matches!(components.next(), Some(Component::Normal(_))) && components.next().is_none();
    is_single_file && (!encrypted_only || file_name.ends_with(".enc"))
}

#[derive(Clone, Debug, Serialize, Deserialize, Type)]
pub struct PaginatedHistory {
    pub entries: Vec<HistoryEntry>,
    pub has_more: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, Type, tauri_specta::Event)]
#[serde(tag = "action")]
pub enum HistoryUpdatePayload {
    #[serde(rename = "added")]
    Added { entry: HistoryEntry },
    #[serde(rename = "updated")]
    Updated { entry: HistoryEntry },
    #[serde(rename = "deleted")]
    Deleted { id: i64 },
    #[serde(rename = "toggled")]
    Toggled { id: i64 },
}

#[derive(Clone, Debug, Serialize, Deserialize, Type)]
pub struct HistoryEntry {
    pub id: i64,
    pub file_name: String,
    pub timestamp: i64,
    pub saved: bool,
    pub title: String,
    pub transcription_text: String,
    pub post_processed_text: Option<String>,
    pub post_process_prompt: Option<String>,
    pub post_process_requested: bool,
    pub audio_available: bool,
    pub audio_saved: bool,
    pub metadata: HistoryMetadata,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, Type, PartialEq, Eq)]
pub struct HistoryMetadata {
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub mode_id: Option<String>,
    #[serde(default)]
    pub processing_route: Option<String>,
    #[serde(default)]
    pub application_name: Option<String>,
    #[serde(default)]
    pub application_bundle_id: Option<String>,
    #[serde(default)]
    pub parent_entry_id: Option<i64>,
    #[serde(default)]
    pub status: HistoryEntryStatus,
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, Type, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HistoryEntryStatus {
    #[default]
    Completed,
    Failed,
}

struct StoredHistoryEntry {
    id: i64,
    file_name: String,
    timestamp: i64,
    saved: bool,
    title: String,
    post_process_requested: bool,
    transcription_ciphertext: Option<Vec<u8>>,
    post_processed_ciphertext: Option<Vec<u8>>,
    post_process_prompt_ciphertext: Option<Vec<u8>>,
    encryption_version: i64,
    audio_available: bool,
    audio_saved: bool,
    metadata_ciphertext: Option<Vec<u8>>,
}

pub struct HistoryManager {
    app_handle: AppHandle,
    recordings_dir: PathBuf,
    db_path: PathBuf,
    master_key: Mutex<Option<[u8; crate::history_crypto::MASTER_KEY_LEN]>>,
}

impl HistoryManager {
    pub fn new(app_handle: &AppHandle) -> Result<Self> {
        // Create recordings directory in app data dir
        let app_data_dir = crate::portable::app_data_dir(app_handle)?;
        let recordings_dir = app_data_dir.join("recordings");
        let db_path = app_data_dir.join("history.db");

        // Ensure recordings directory exists
        if !recordings_dir.exists() {
            fs::create_dir_all(&recordings_dir)?;
            debug!("Created recordings directory: {:?}", recordings_dir);
        }

        let manager = Self {
            app_handle: app_handle.clone(),
            recordings_dir,
            db_path,
            master_key: Mutex::new(None),
        };

        // Initialize database and run migrations synchronously
        manager.init_database()?;
        manager.cleanup_old_entries()?;

        Ok(manager)
    }

    fn init_database(&self) -> Result<()> {
        info!("Initializing database at {:?}", self.db_path);

        let mut conn = Connection::open(&self.db_path)?;
        conn.pragma_update(None, "secure_delete", "ON")?;

        // Handle migration from tauri-plugin-sql to rusqlite_migration
        // tauri-plugin-sql used _sqlx_migrations table, rusqlite_migration uses user_version pragma
        self.migrate_from_tauri_plugin_sql(&conn)?;

        // Create migrations object and run to latest version
        let migrations = Migrations::new(MIGRATIONS.to_vec());

        // Validate migrations in debug builds
        #[cfg(debug_assertions)]
        migrations.validate().expect("Invalid migrations");

        // Get current version before migration
        let version_before: i32 =
            conn.pragma_query_value(None, "user_version", |row| row.get(0))?;
        debug!("Database version before migration: {}", version_before);

        // Apply any pending migrations
        migrations.to_latest(&mut conn)?;

        // Get version after migration
        let version_after: i32 = conn.pragma_query_value(None, "user_version", |row| row.get(0))?;

        if version_after > version_before {
            info!(
                "Database migrated from version {} to {}",
                version_before, version_after
            );
        } else {
            debug!("Database already at latest version {}", version_after);
        }

        if self.migrate_plaintext_content(&mut conn)? {
            // Remove pages that may still contain values from the legacy
            // plaintext schema. VACUUM runs only once, during migration.
            conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")?;
        }
        self.migrate_plaintext_audio(&conn)?;

        self.apply_private_permissions()?;
        Ok(())
    }

    /// Migrate from tauri-plugin-sql's migration tracking to rusqlite_migration's.
    /// tauri-plugin-sql used a _sqlx_migrations table, while rusqlite_migration uses
    /// SQLite's user_version pragma. This function checks if the old system was in use
    /// and sets the user_version accordingly so migrations don't re-run.
    fn migrate_from_tauri_plugin_sql(&self, conn: &Connection) -> Result<()> {
        // Check if the old _sqlx_migrations table exists
        let has_sqlx_migrations: bool = conn
            .query_row(
                "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type='table' AND name='_sqlx_migrations'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(false);

        if !has_sqlx_migrations {
            return Ok(());
        }

        // Check current user_version
        let current_version: i32 =
            conn.pragma_query_value(None, "user_version", |row| row.get(0))?;

        if current_version > 0 {
            // Already migrated to rusqlite_migration system
            return Ok(());
        }

        // Get the highest version from the old migrations table
        let old_version: i32 = conn
            .query_row(
                "SELECT COALESCE(MAX(version), 0) FROM _sqlx_migrations WHERE success = 1",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        if old_version > 0 {
            info!(
                "Migrating from tauri-plugin-sql (version {}) to rusqlite_migration",
                old_version
            );

            // Set user_version to match the old migration state
            conn.pragma_update(None, "user_version", old_version)?;

            // Optionally drop the old migrations table (keeping it doesn't hurt)
            // conn.execute("DROP TABLE IF EXISTS _sqlx_migrations", [])?;

            info!(
                "Migration tracking converted: user_version set to {}",
                old_version
            );
        }

        Ok(())
    }

    fn get_connection(&self) -> Result<Connection> {
        Ok(Connection::open(&self.db_path)?)
    }

    fn master_key(&self) -> Result<[u8; crate::history_crypto::MASTER_KEY_LEN]> {
        let mut cached = self
            .master_key
            .lock()
            .map_err(|_| anyhow!("Unable to access history encryption"))?;
        if let Some(key) = *cached {
            return Ok(key);
        }

        let key = crate::secrets::get_or_create_history_master_key().map_err(anyhow::Error::msg)?;
        *cached = Some(key);
        Ok(key)
    }

    fn map_stored_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredHistoryEntry> {
        Ok(StoredHistoryEntry {
            id: row.get("id")?,
            file_name: row.get("file_name")?,
            timestamp: row.get("timestamp")?,
            saved: row.get("saved")?,
            title: row.get("title")?,
            post_process_requested: row.get("post_process_requested")?,
            transcription_ciphertext: row.get("transcription_ciphertext")?,
            post_processed_ciphertext: row.get("post_processed_ciphertext")?,
            post_process_prompt_ciphertext: row.get("post_process_prompt_ciphertext")?,
            encryption_version: row.get("encryption_version")?,
            audio_available: row.get("audio_available")?,
            audio_saved: row.get("audio_saved")?,
            metadata_ciphertext: row.get("metadata_ciphertext")?,
        })
    }

    fn text_aad(id: i64, field: &str) -> Vec<u8> {
        format!("pressay-history-v1:{id}:{field}").into_bytes()
    }

    fn encrypt_text(&self, id: i64, field: &str, value: &str) -> Result<Vec<u8>> {
        crate::history_crypto::encrypt(
            &self.master_key()?,
            value.as_bytes(),
            &Self::text_aad(id, field),
        )
    }

    fn decrypt_text(&self, id: i64, field: &str, value: &[u8]) -> Result<String> {
        let plaintext =
            crate::history_crypto::decrypt(&self.master_key()?, value, &Self::text_aad(id, field))?;
        String::from_utf8(plaintext).map_err(|_| anyhow!("History content is not valid UTF-8"))
    }

    fn decrypt_entry(&self, stored: StoredHistoryEntry) -> Result<HistoryEntry> {
        if stored.encryption_version != ENCRYPTION_VERSION {
            return Err(anyhow!("Unsupported history encryption version"));
        }

        let transcription_text = self.decrypt_text(
            stored.id,
            "transcription",
            stored
                .transcription_ciphertext
                .as_deref()
                .ok_or_else(|| anyhow!("Encrypted transcription is missing"))?,
        )?;
        let post_processed_text = stored
            .post_processed_ciphertext
            .as_deref()
            .map(|value| self.decrypt_text(stored.id, "post-processed", value))
            .transpose()?;
        let post_process_prompt = stored
            .post_process_prompt_ciphertext
            .as_deref()
            .map(|value| self.decrypt_text(stored.id, "prompt", value))
            .transpose()?;
        let metadata = stored
            .metadata_ciphertext
            .as_deref()
            .map(|value| self.decrypt_text(stored.id, "metadata", value))
            .transpose()?
            .map(|value| serde_json::from_str::<HistoryMetadata>(&value))
            .transpose()?
            .unwrap_or_else(|| HistoryMetadata {
                status: if transcription_text.trim().is_empty() {
                    HistoryEntryStatus::Failed
                } else {
                    HistoryEntryStatus::Completed
                },
                ..HistoryMetadata::default()
            });

        Ok(HistoryEntry {
            id: stored.id,
            file_name: stored.file_name,
            timestamp: stored.timestamp,
            saved: stored.saved,
            title: stored.title,
            transcription_text,
            post_processed_text,
            post_process_prompt,
            post_process_requested: stored.post_process_requested,
            audio_available: stored.audio_available,
            audio_saved: stored.audio_saved,
            metadata,
        })
    }

    fn migrate_plaintext_content(&self, conn: &mut Connection) -> Result<bool> {
        let legacy_rows = {
            let mut statement = conn.prepare(
                "SELECT id, transcription_text, post_processed_text, post_process_prompt
                 FROM transcription_history
                 WHERE encryption_version = 0",
            )?;
            let rows = statement
                .query_map([], |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, Option<String>>(2)?,
                        row.get::<_, Option<String>>(3)?,
                    ))
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            rows
        };

        if legacy_rows.is_empty() {
            return Ok(false);
        }

        let transaction = conn.transaction()?;
        for (id, transcription, processed, prompt) in legacy_rows {
            let transcription_ciphertext =
                self.encrypt_text(id, "transcription", &transcription)?;
            let processed_ciphertext = processed
                .as_deref()
                .map(|value| self.encrypt_text(id, "post-processed", value))
                .transpose()?;
            let prompt_ciphertext = prompt
                .as_deref()
                .map(|value| self.encrypt_text(id, "prompt", value))
                .transpose()?;

            transaction.execute(
                "UPDATE transcription_history
                 SET transcription_text = '',
                     post_processed_text = NULL,
                     post_process_prompt = NULL,
                     transcription_ciphertext = ?1,
                     post_processed_ciphertext = ?2,
                     post_process_prompt_ciphertext = ?3,
                     encryption_version = ?4
                 WHERE id = ?5",
                params![
                    transcription_ciphertext,
                    processed_ciphertext,
                    prompt_ciphertext,
                    ENCRYPTION_VERSION,
                    id
                ],
            )?;
        }
        transaction.commit()?;
        info!("Encrypted legacy history content in place");
        Ok(true)
    }

    fn migrate_plaintext_audio(&self, conn: &Connection) -> Result<()> {
        let legacy_files = {
            let mut statement = conn.prepare(
                "SELECT id, file_name FROM transcription_history
                 WHERE audio_available = 1 AND file_name != '' AND file_name NOT LIKE '%.enc'",
            )?;
            let rows = statement
                .query_map([], |row| {
                    Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            rows
        };

        for (id, old_name) in legacy_files {
            let old_path = self.safe_audio_path(&old_name, false)?;
            let new_name = format!("{old_name}.enc");
            let new_path = self.safe_audio_path(&new_name, true)?;
            if !old_path.exists() {
                if new_path.exists() && self.get_audio_bytes(&new_name).is_ok() {
                    conn.execute(
                        "UPDATE transcription_history SET file_name = ?1 WHERE id = ?2",
                        params![new_name, id],
                    )?;
                } else {
                    conn.execute(
                        "UPDATE transcription_history SET audio_available = 0 WHERE id = ?1",
                        params![id],
                    )?;
                }
                continue;
            }

            if new_path.exists() {
                self.get_audio_bytes(&new_name)?;
            } else {
                let wav_bytes = fs::read(&old_path)?;
                self.save_encrypted_audio_bytes(&new_name, &wav_bytes)?;
            }
            fs::remove_file(&old_path)?;
            conn.execute(
                "UPDATE transcription_history SET file_name = ?1 WHERE id = ?2",
                params![new_name, id],
            )?;
        }

        Ok(())
    }

    fn apply_private_permissions(&self) -> Result<()> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if self.recordings_dir.exists() {
                fs::set_permissions(&self.recordings_dir, fs::Permissions::from_mode(0o700))?;
            }
            if self.db_path.exists() {
                fs::set_permissions(&self.db_path, fs::Permissions::from_mode(0o600))?;
            }
        }
        Ok(())
    }

    fn safe_audio_path(&self, file_name: &str, encrypted_only: bool) -> Result<PathBuf> {
        if !is_safe_audio_identifier(file_name, encrypted_only) {
            return Err(anyhow!("Invalid history audio identifier"));
        }
        Ok(self.recordings_dir.join(file_name))
    }

    fn audio_aad(file_name: &str) -> Vec<u8> {
        format!("pressay-history-audio-v1:{file_name}").into_bytes()
    }

    fn write_private_file(&self, path: &Path, bytes: &[u8]) -> Result<()> {
        if path.exists() {
            return Err(anyhow!("History audio identifier already exists"));
        }
        static TEMP_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let counter = TEMP_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let temp_name = format!(".pressay-history-{}-{counter}.tmp", std::process::id());
        let temp_path = self.recordings_dir.join(temp_name);

        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }

        let write_result = (|| -> Result<()> {
            let mut file = options.open(&temp_path)?;
            file.write_all(bytes)?;
            file.sync_all()?;
            fs::rename(&temp_path, path)?;
            Ok(())
        })();
        if write_result.is_err() {
            let _ = fs::remove_file(&temp_path);
        }
        write_result
    }

    fn save_encrypted_audio_bytes(&self, file_name: &str, wav_bytes: &[u8]) -> Result<()> {
        let path = self.safe_audio_path(file_name, true)?;
        let envelope = crate::history_crypto::encrypt(
            &self.master_key()?,
            wav_bytes,
            &Self::audio_aad(file_name),
        )?;
        self.write_private_file(&path, &envelope)
    }

    pub fn save_audio(&self, file_name: &str, samples: &[f32]) -> Result<()> {
        let wav_bytes = crate::audio_toolkit::encode_wav_samples(samples)?;
        self.save_encrypted_audio_bytes(file_name, &wav_bytes)
    }

    pub fn get_audio_bytes(&self, file_name: &str) -> Result<Vec<u8>> {
        let path = self.safe_audio_path(file_name, true)?;
        let envelope = fs::read(path)?;
        crate::history_crypto::decrypt(&self.master_key()?, &envelope, &Self::audio_aad(file_name))
    }

    pub fn get_audio_samples(&self, file_name: &str) -> Result<Vec<f32>> {
        let wav_bytes = self.get_audio_bytes(file_name)?;
        crate::audio_toolkit::read_wav_samples_from_bytes(&wav_bytes)
    }

    pub fn discard_audio(&self, file_name: &str) -> Result<()> {
        let path = self.safe_audio_path(file_name, true)?;
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }

    /// Save a new history entry. User content is encrypted before the database
    /// transaction commits; the legacy plaintext columns remain empty.
    pub fn save_entry(
        &self,
        file_name: String,
        transcription_text: String,
        post_process_requested: bool,
        post_processed_text: Option<String>,
        post_process_prompt: Option<String>,
    ) -> Result<HistoryEntry> {
        let status = if transcription_text.trim().is_empty() {
            HistoryEntryStatus::Failed
        } else {
            HistoryEntryStatus::Completed
        };
        self.save_entry_with_metadata(
            file_name,
            transcription_text,
            post_process_requested,
            post_processed_text,
            post_process_prompt,
            true,
            HistoryMetadata {
                status,
                ..HistoryMetadata::default()
            },
        )
    }

    /// Save an entry with encrypted operational metadata. Tags and application
    /// context are user data, so they share the history master key and are never
    /// written to SQLite in plaintext.
    #[allow(clippy::too_many_arguments)]
    pub fn save_entry_with_metadata(
        &self,
        file_name: String,
        transcription_text: String,
        post_process_requested: bool,
        post_processed_text: Option<String>,
        post_process_prompt: Option<String>,
        audio_available: bool,
        metadata: HistoryMetadata,
    ) -> Result<HistoryEntry> {
        let timestamp = Utc::now().timestamp();
        let title = self.format_timestamp_title(timestamp);

        let mut conn = self.get_connection()?;
        let transaction = conn.transaction()?;
        transaction.execute(
            "INSERT INTO transcription_history (
                file_name,
                timestamp,
                saved,
                title,
                transcription_text,
                post_processed_text,
                post_process_prompt,
                post_process_requested,
                encryption_version,
                audio_available,
                audio_saved
            ) VALUES (?1, ?2, ?3, ?4, '', NULL, NULL, ?5, 0, 1, 0)",
            params![&file_name, timestamp, false, &title, post_process_requested,],
        )?;

        let id = transaction.last_insert_rowid();
        let transcription_ciphertext =
            self.encrypt_text(id, "transcription", &transcription_text)?;
        let post_processed_ciphertext = post_processed_text
            .as_deref()
            .map(|value| self.encrypt_text(id, "post-processed", value))
            .transpose()?;
        let post_process_prompt_ciphertext = post_process_prompt
            .as_deref()
            .map(|value| self.encrypt_text(id, "prompt", value))
            .transpose()?;
        let metadata_json = serde_json::to_string(&metadata)?;
        let metadata_ciphertext = self.encrypt_text(id, "metadata", &metadata_json)?;
        transaction.execute(
            "UPDATE transcription_history
             SET transcription_ciphertext = ?1,
                 post_processed_ciphertext = ?2,
                 post_process_prompt_ciphertext = ?3,
                 encryption_version = ?4,
                 audio_available = ?5,
                 metadata_ciphertext = ?6
             WHERE id = ?7",
            params![
                transcription_ciphertext,
                post_processed_ciphertext,
                post_process_prompt_ciphertext,
                ENCRYPTION_VERSION,
                audio_available,
                metadata_ciphertext,
                id
            ],
        )?;
        transaction.commit()?;

        let entry = HistoryEntry {
            id,
            file_name,
            timestamp,
            saved: false,
            title,
            transcription_text,
            post_processed_text,
            post_process_prompt,
            post_process_requested,
            audio_available,
            audio_saved: false,
            metadata,
        };

        debug!("Saved history entry with id {}", entry.id);

        self.cleanup_old_entries()?;

        // Emit typed event for real-time frontend updates
        if let Err(e) = (HistoryUpdatePayload::Added {
            entry: entry.clone(),
        })
        .emit(&self.app_handle)
        {
            error!("Failed to emit history-updated event: {}", e);
        }

        Ok(entry)
    }

    /// Update an existing history entry with new transcription results (used by retry).
    pub fn update_transcription(
        &self,
        id: i64,
        transcription_text: String,
        post_processed_text: Option<String>,
        post_process_prompt: Option<String>,
    ) -> Result<HistoryEntry> {
        let conn = self.get_connection()?;
        let transcription_ciphertext =
            self.encrypt_text(id, "transcription", &transcription_text)?;
        let post_processed_ciphertext = post_processed_text
            .as_deref()
            .map(|value| self.encrypt_text(id, "post-processed", value))
            .transpose()?;
        let post_process_prompt_ciphertext = post_process_prompt
            .as_deref()
            .map(|value| self.encrypt_text(id, "prompt", value))
            .transpose()?;
        let updated = conn.execute(
            "UPDATE transcription_history
             SET transcription_text = '',
                 post_processed_text = NULL,
                 post_process_prompt = NULL,
                 transcription_ciphertext = ?1,
                 post_processed_ciphertext = ?2,
                 post_process_prompt_ciphertext = ?3,
                 encryption_version = ?4
             WHERE id = ?5",
            params![
                transcription_ciphertext,
                post_processed_ciphertext,
                post_process_prompt_ciphertext,
                ENCRYPTION_VERSION,
                id
            ],
        )?;

        if updated == 0 {
            return Err(anyhow!("History entry {} not found", id));
        }

        let stored = conn.query_row(
            &format!("SELECT {HISTORY_COLUMNS} FROM transcription_history WHERE id = ?1"),
            params![id],
            Self::map_stored_entry,
        )?;
        let entry = self.decrypt_entry(stored)?;

        debug!("Updated transcription for history entry {}", id);

        if let Err(e) = (HistoryUpdatePayload::Updated {
            entry: entry.clone(),
        })
        .emit(&self.app_handle)
        {
            error!("Failed to emit history-updated event: {}", e);
        }

        Ok(entry)
    }

    pub fn cleanup_old_entries(&self) -> Result<()> {
        self.cleanup_expired_audio(crate::settings::get_history_audio_retention(
            &self.app_handle,
        ))?;
        self.cleanup_expired_text(crate::settings::get_history_text_retention(
            &self.app_handle,
        ))
    }

    fn retention_cutoff(period: crate::settings::HistoryRetentionPeriod) -> Option<i64> {
        let seconds = match period {
            crate::settings::HistoryRetentionPeriod::Hours24 => 24 * 60 * 60,
            crate::settings::HistoryRetentionPeriod::Days7 => 7 * 24 * 60 * 60,
            crate::settings::HistoryRetentionPeriod::Days30 => 30 * 24 * 60 * 60,
            crate::settings::HistoryRetentionPeriod::Forever => return None,
        };
        Some(Utc::now().timestamp() - seconds)
    }

    fn cleanup_expired_audio(&self, period: crate::settings::HistoryRetentionPeriod) -> Result<()> {
        let Some(cutoff) = Self::retention_cutoff(period) else {
            return Ok(());
        };
        let conn = self.get_connection()?;
        let files = {
            let mut statement = conn.prepare(
                "SELECT id, file_name FROM transcription_history
                 WHERE audio_available = 1 AND audio_saved = 0 AND timestamp < ?1",
            )?;
            let rows = statement
                .query_map(params![cutoff], |row| {
                    Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            rows
        };

        for (id, file_name) in files {
            if !file_name.is_empty() {
                self.discard_audio(&file_name)?;
            }
            conn.execute(
                "UPDATE transcription_history
                 SET file_name = '', audio_available = 0, audio_saved = 0
                 WHERE id = ?1",
                params![id],
            )?;
        }
        Ok(())
    }

    fn cleanup_expired_text(&self, period: crate::settings::HistoryRetentionPeriod) -> Result<()> {
        let Some(cutoff) = Self::retention_cutoff(period) else {
            return Ok(());
        };
        let conn = self.get_connection()?;
        let entries = {
            let mut statement = conn.prepare(
                "SELECT id, file_name, audio_available FROM transcription_history
                 WHERE saved = 0 AND timestamp < ?1",
            )?;
            let rows = statement
                .query_map(params![cutoff], |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, bool>(2)?,
                    ))
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            rows
        };

        for (id, file_name, audio_available) in entries {
            if audio_available && !file_name.is_empty() {
                self.discard_audio(&file_name)?;
            }
            conn.execute(
                "DELETE FROM transcription_history WHERE id = ?1",
                params![id],
            )?;
        }
        Ok(())
    }

    pub async fn get_history_entries(
        &self,
        cursor: Option<i64>,
        limit: Option<usize>,
    ) -> Result<PaginatedHistory> {
        let conn = self.get_connection()?;
        let limit = limit.map(|l| l.min(100));

        let stored_entries: Vec<StoredHistoryEntry> = match (cursor, limit) {
            (Some(cursor_id), Some(lim)) => {
                let fetch_count = (lim + 1) as i64;
                let sql = format!(
                    "SELECT {HISTORY_COLUMNS} FROM transcription_history
                     WHERE id < ?1 ORDER BY id DESC LIMIT ?2"
                );
                let mut stmt = conn.prepare(&sql)?;
                let result = stmt
                    .query_map(params![cursor_id, fetch_count], Self::map_stored_entry)?
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                result
            }
            (None, Some(lim)) => {
                let fetch_count = (lim + 1) as i64;
                let sql = format!(
                    "SELECT {HISTORY_COLUMNS} FROM transcription_history
                     ORDER BY id DESC LIMIT ?1"
                );
                let mut stmt = conn.prepare(&sql)?;
                let result = stmt
                    .query_map(params![fetch_count], Self::map_stored_entry)?
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                result
            }
            (_, None) => {
                let sql =
                    format!("SELECT {HISTORY_COLUMNS} FROM transcription_history ORDER BY id DESC");
                let mut stmt = conn.prepare(&sql)?;
                let result = stmt
                    .query_map([], Self::map_stored_entry)?
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                result
            }
        };

        let mut entries = stored_entries
            .into_iter()
            .map(|entry| self.decrypt_entry(entry))
            .collect::<Result<Vec<_>>>()?;

        let has_more = limit.is_some_and(|lim| entries.len() > lim);
        if has_more {
            entries.pop();
        }

        Ok(PaginatedHistory { entries, has_more })
    }

    /// Get the latest entry with non-empty transcription text.
    pub fn get_latest_completed_entry(&self) -> Result<Option<HistoryEntry>> {
        let conn = self.get_connection()?;
        let sql =
            format!("SELECT {HISTORY_COLUMNS} FROM transcription_history ORDER BY timestamp DESC");
        let mut statement = conn.prepare(&sql)?;
        let stored = statement
            .query_map([], Self::map_stored_entry)?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        for entry in stored {
            let entry = self.decrypt_entry(entry)?;
            if !entry.transcription_text.is_empty() {
                return Ok(Some(entry));
            }
        }
        Ok(None)
    }

    pub async fn toggle_saved_status(&self, id: i64) -> Result<()> {
        let conn = self.get_connection()?;

        // Get current saved status
        let current_saved: bool = conn.query_row(
            "SELECT saved FROM transcription_history WHERE id = ?1",
            params![id],
            |row| row.get("saved"),
        )?;

        let new_saved = !current_saved;

        conn.execute(
            "UPDATE transcription_history SET saved = ?1 WHERE id = ?2",
            params![new_saved, id],
        )?;

        debug!("Toggled saved status for entry {}: {}", id, new_saved);

        // Emit history updated event
        if let Err(e) = (HistoryUpdatePayload::Toggled { id }).emit(&self.app_handle) {
            error!("Failed to emit history-updated event: {}", e);
        }

        Ok(())
    }

    pub async fn update_tags(&self, id: i64, tags: Vec<String>) -> Result<HistoryEntry> {
        let mut entry = self
            .get_entry_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("History entry {} not found", id))?;
        let mut normalized = Vec::new();
        for tag in tags {
            let tag = tag.trim().trim_start_matches('#').trim().to_string();
            if tag.is_empty() || tag.chars().count() > 40 {
                continue;
            }
            if !normalized
                .iter()
                .any(|existing: &String| existing.eq_ignore_ascii_case(&tag))
            {
                normalized.push(tag);
            }
            if normalized.len() == 20 {
                break;
            }
        }
        entry.metadata.tags = normalized;
        self.update_metadata(id, &entry.metadata)?;
        if let Err(error) = (HistoryUpdatePayload::Updated {
            entry: entry.clone(),
        })
        .emit(&self.app_handle)
        {
            error!("Failed to emit history-updated event: {}", error);
        }
        Ok(entry)
    }

    fn update_metadata(&self, id: i64, metadata: &HistoryMetadata) -> Result<()> {
        let metadata_json = serde_json::to_string(metadata)?;
        let metadata_ciphertext = self.encrypt_text(id, "metadata", &metadata_json)?;
        let conn = self.get_connection()?;
        let updated = conn.execute(
            "UPDATE transcription_history SET metadata_ciphertext = ?1 WHERE id = ?2",
            params![metadata_ciphertext, id],
        )?;
        if updated == 0 {
            return Err(anyhow!("History entry {} not found", id));
        }
        Ok(())
    }

    pub async fn toggle_audio_saved_status(&self, id: i64) -> Result<HistoryEntry> {
        let conn = self.get_connection()?;
        let (current, available): (bool, bool) = conn.query_row(
            "SELECT audio_saved, audio_available FROM transcription_history WHERE id = ?1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        if !available {
            return Err(anyhow!("This recording is no longer available"));
        }

        conn.execute(
            "UPDATE transcription_history SET audio_saved = ?1 WHERE id = ?2",
            params![!current, id],
        )?;
        let stored = conn.query_row(
            &format!("SELECT {HISTORY_COLUMNS} FROM transcription_history WHERE id = ?1"),
            params![id],
            Self::map_stored_entry,
        )?;
        let entry = self.decrypt_entry(stored)?;
        if let Err(error) = (HistoryUpdatePayload::Updated {
            entry: entry.clone(),
        })
        .emit(&self.app_handle)
        {
            error!("Failed to emit history-updated event: {}", error);
        }
        Ok(entry)
    }

    pub async fn get_entry_by_id(&self, id: i64) -> Result<Option<HistoryEntry>> {
        let conn = self.get_connection()?;
        let sql = format!("SELECT {HISTORY_COLUMNS} FROM transcription_history WHERE id = ?1");
        let mut stmt = conn.prepare(&sql)?;

        let stored = stmt.query_row([id], Self::map_stored_entry).optional()?;

        stored.map(|entry| self.decrypt_entry(entry)).transpose()
    }

    pub async fn delete_entry(&self, id: i64) -> Result<()> {
        let conn = self.get_connection()?;

        // Get the entry to find the file name
        if let Some(entry) = self.get_entry_by_id(id).await? {
            // Delete the audio file first
            if entry.audio_available && !entry.file_name.is_empty() {
                let file_path = self.safe_audio_path(&entry.file_name, true)?;
                if file_path.exists() {
                    if let Err(e) = fs::remove_file(&file_path) {
                        error!("Failed to delete encrypted audio file: {}", e);
                        // Continue with database deletion even if file deletion fails
                    }
                }
            }
        }

        // Delete from database
        conn.execute(
            "DELETE FROM transcription_history WHERE id = ?1",
            params![id],
        )?;

        debug!("Deleted history entry with id: {}", id);

        // Emit history updated event
        if let Err(e) = (HistoryUpdatePayload::Deleted { id }).emit(&self.app_handle) {
            error!("Failed to emit history-updated event: {}", e);
        }

        Ok(())
    }

    pub fn delete_all_history(&self) -> Result<()> {
        let conn = self.get_connection()?;
        let files = {
            let mut statement = conn.prepare(
                "SELECT file_name FROM transcription_history
                 WHERE audio_available = 1 AND file_name != ''",
            )?;
            let rows = statement
                .query_map([], |row| row.get::<_, String>(0))?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            rows
        };

        for file_name in files {
            self.discard_audio(&file_name)?;
        }
        conn.execute("DELETE FROM transcription_history", [])?;
        conn.execute_batch("VACUUM;")?;
        crate::secrets::delete_history_master_key().map_err(anyhow::Error::msg)?;
        *self
            .master_key
            .lock()
            .map_err(|_| anyhow!("Unable to clear history encryption state"))? = None;
        Ok(())
    }

    fn format_timestamp_title(&self, timestamp: i64) -> String {
        if let Some(utc_datetime) = DateTime::from_timestamp(timestamp, 0) {
            // Convert UTC to local timezone
            let local_datetime = utc_datetime.with_timezone(&Local);
            local_datetime.format("%B %e, %Y - %l:%M%p").to_string()
        } else {
            format!("Recording {}", timestamp)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_create_encrypted_history_columns() {
        let mut connection = Connection::open_in_memory().unwrap();
        Migrations::new(MIGRATIONS.to_vec())
            .to_latest(&mut connection)
            .unwrap();

        let columns = connection
            .prepare("PRAGMA table_info(transcription_history)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<std::result::Result<Vec<_>, _>>()
            .unwrap();
        assert!(columns.contains(&"transcription_ciphertext".to_string()));
        assert!(columns.contains(&"encryption_version".to_string()));
        assert!(columns.contains(&"audio_available".to_string()));
        assert!(columns.contains(&"metadata_ciphertext".to_string()));
    }

    #[test]
    fn metadata_defaults_are_private_and_backward_compatible() {
        let metadata = HistoryMetadata::default();
        assert!(metadata.tags.is_empty());
        assert_eq!(metadata.status, HistoryEntryStatus::Completed);
        assert!(!serde_json::to_string(&metadata)
            .unwrap()
            .contains("transcription"));
    }

    #[test]
    fn encrypted_audio_identifiers_cannot_escape_recordings_directory() {
        assert!(is_safe_audio_identifier("pressay-1.wav.enc", true));
        for invalid in [
            "pressay-1.wav",
            "../pressay-1.wav.enc",
            "/tmp/pressay-1.wav.enc",
            "folder/pressay-1.wav.enc",
            "",
        ] {
            assert!(!is_safe_audio_identifier(invalid, true));
        }
    }
}
