use tauri::{AppHandle, Manager};
use tauri_plugin_opener::OpenerExt;

use crate::capabilities::{require_capability, ProductCapability};
use crate::cloud::{
    self, CloudAccountSnapshot, CloudAuthConfig, CloudAuthProvider, CloudAuthRuntime,
    CloudSyncRecoveryCode, CloudSyncSnapshot,
};
use crate::cloud_sync::CloudSyncRunReport;
use crate::settings::get_settings;
use crate::storekit::{self, StoreKitProduct, StoreKitTransaction};

fn public_error(error: cloud::CloudFailure) -> String {
    error.code
}

#[tauri::command]
#[specta::specta]
pub async fn get_cloud_auth_config(app: AppHandle) -> Result<CloudAuthConfig, String> {
    cloud::get_auth_config(&get_settings(&app))
        .await
        .map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn request_cloud_magic_link(app: AppHandle, email: String) -> Result<(), String> {
    let runtime = app.state::<CloudAuthRuntime>();
    let state = runtime.begin().map_err(public_error)?;
    if let Err(error) = cloud::request_magic_link(&get_settings(&app), email.trim(), &state).await {
        runtime.clear();
        return Err(public_error(error));
    }
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub async fn begin_cloud_social_login(
    app: AppHandle,
    provider: CloudAuthProvider,
) -> Result<(), String> {
    let runtime = app.state::<CloudAuthRuntime>();
    let (state, verifier) = runtime.begin_oauth().map_err(public_error)?;
    let authorization_url =
        match cloud::social_login_url(&get_settings(&app), provider, &state, &verifier).await {
            Ok(url) => url,
            Err(error) => {
                runtime.clear();
                return Err(public_error(error));
            }
        };
    if app
        .opener()
        .open_url(authorization_url, None::<String>)
        .is_err()
    {
        runtime.clear();
        return Err("cloud_browser_open_failed".to_string());
    }
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub async fn get_cloud_account_snapshot(app: AppHandle) -> Result<CloudAccountSnapshot, String> {
    let snapshot = cloud::account_snapshot(&app).await.map_err(|error| {
        log::warn!("Cloud account snapshot failed with code {}", error.code);
        public_error(error)
    })?;
    crate::tray::update_tray_menu(&app, None);
    Ok(snapshot)
}

#[tauri::command]
#[specta::specta]
pub async fn disconnect_cloud_account(app: AppHandle) -> Result<(), String> {
    cloud::sign_out(&app).await.map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn delete_cloud_account(app: AppHandle) -> Result<(), String> {
    cloud::delete_account(&app).await.map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn get_cloud_sync_snapshot(app: AppHandle) -> Result<CloudSyncSnapshot, String> {
    cloud::cloud_sync_snapshot(&app).await.map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn initialize_cloud_sync(app: AppHandle) -> Result<CloudSyncSnapshot, String> {
    require_capability(&app, ProductCapability::EncryptedSync)?;
    cloud::initialize_cloud_sync(&app).await.map_err(|error| {
        log::warn!("Cloud sync initialization failed: {}", error.code);
        public_error(error)
    })
}

#[tauri::command]
#[specta::specta]
pub async fn approve_cloud_sync_device(
    app: AppHandle,
    target_device_id: String,
) -> Result<CloudSyncSnapshot, String> {
    require_capability(&app, ProductCapability::EncryptedSync)?;
    cloud::approve_cloud_sync_device(&app, &target_device_id)
        .await
        .map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn create_cloud_sync_recovery_code(
    app: AppHandle,
) -> Result<CloudSyncRecoveryCode, String> {
    require_capability(&app, ProductCapability::EncryptedSync)?;
    cloud::create_cloud_sync_recovery_code(&app)
        .await
        .map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn recover_cloud_sync(
    app: AppHandle,
    recovery_code: String,
) -> Result<CloudSyncSnapshot, String> {
    require_capability(&app, ProductCapability::EncryptedSync)?;
    cloud::recover_cloud_sync(&app, recovery_code.trim())
        .await
        .map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn run_cloud_sync(app: AppHandle) -> Result<CloudSyncRunReport, String> {
    require_capability(&app, ProductCapability::EncryptedSync)?;
    crate::cloud_sync::run_cloud_sync(&app)
        .await
        .map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn retry_cloud_transcription(
    app: AppHandle,
    request_id: String,
) -> Result<crate::cloud::CloudTranscriptionResponse, String> {
    require_capability(&app, ProductCapability::PressayCloud)?;
    crate::cloud_transcription::retry_with_cloud(&app, &request_id)
        .await
        .map_err(public_error)
}

fn require_app_store_distribution() -> Result<(), String> {
    if cfg!(feature = "mas") {
        Ok(())
    } else {
        Err("storekit_distribution_unavailable".to_string())
    }
}

async fn reconcile_transaction(
    app: &AppHandle,
    transaction: StoreKitTransaction,
) -> Result<CloudAccountSnapshot, String> {
    if transaction.status != "purchased" {
        return Err(format!("storekit_{}", transaction.status));
    }
    let product_id = transaction
        .product_id
        .as_deref()
        .ok_or_else(|| "storekit_transaction_invalid".to_string())?;
    if !storekit::is_known_product(product_id) {
        return Err("storekit_product_invalid".to_string());
    }
    let transaction_id = transaction
        .transaction_id
        .as_deref()
        .ok_or_else(|| "storekit_transaction_invalid".to_string())?;
    let signed_transaction = transaction
        .signed_transaction
        .as_deref()
        .ok_or_else(|| "storekit_transaction_invalid".to_string())?;
    let snapshot = cloud::restore_app_store_transaction(app, signed_transaction, transaction_id)
        .await
        .map_err(public_error)?;
    tokio::task::spawn_blocking({
        let transaction_id = transaction_id.to_string();
        move || storekit::finish(&transaction_id)
    })
    .await
    .map_err(|_| "storekit_finish_failed".to_string())??;
    crate::tray::update_tray_menu(app, None);
    Ok(snapshot)
}

#[tauri::command]
#[specta::specta]
pub async fn get_app_store_products() -> Result<Vec<StoreKitProduct>, String> {
    require_app_store_distribution()?;
    tokio::task::spawn_blocking(storekit::products)
        .await
        .map_err(|_| "storekit_products_unavailable".to_string())?
}

#[tauri::command]
#[specta::specta]
pub async fn purchase_app_store_product(
    app: AppHandle,
    product_id: String,
) -> Result<CloudAccountSnapshot, String> {
    require_app_store_distribution()?;
    if !storekit::is_known_product(&product_id) {
        return Err("storekit_product_invalid".to_string());
    }
    let account_id = get_settings(&app)
        .pressay_cloud_account_id
        .ok_or_else(|| "cloud_account_required".to_string())?;
    uuid::Uuid::parse_str(&account_id).map_err(|_| "storekit_account_invalid".to_string())?;
    let transaction =
        tokio::task::spawn_blocking(move || storekit::purchase(&product_id, &account_id))
            .await
            .map_err(|_| "storekit_purchase_failed".to_string())??;
    reconcile_transaction(&app, transaction).await
}

async fn restore_or_reconcile(
    app: &AppHandle,
    force_sync: bool,
) -> Result<CloudAccountSnapshot, String> {
    require_app_store_distribution()?;
    if get_settings(app).pressay_cloud_account_id.is_none() {
        return Err("cloud_account_required".to_string());
    }
    let transactions =
        tokio::task::spawn_blocking(move || storekit::current_entitlements(force_sync))
            .await
            .map_err(|_| "storekit_restore_failed".to_string())??;
    let mut snapshot = None;
    for transaction in transactions {
        snapshot = Some(reconcile_transaction(app, transaction).await?);
    }
    match snapshot {
        Some(snapshot) => Ok(snapshot),
        None => cloud::account_snapshot(app).await.map_err(public_error),
    }
}

/// Reconcile StoreKit's locally verified current entitlements with Pressay
/// Cloud at launch and periodically while the MAS app is running. This never
/// presents the App Store sign-in sheet; only the explicit Restore command
/// calls `AppStore.sync()`.
pub fn start_app_store_reconciliation(app: AppHandle) {
    if !cfg!(feature = "mas") {
        return;
    }
    tauri::async_runtime::spawn(async move {
        loop {
            if get_settings(&app).pressay_cloud_account_id.is_some() {
                if let Err(error) = restore_or_reconcile(&app, false).await {
                    log::warn!("App Store entitlement reconciliation failed: {error}");
                }
            }
            tokio::time::sleep(std::time::Duration::from_secs(15 * 60)).await;
        }
    });
}

#[tauri::command]
#[specta::specta]
pub async fn restore_app_store_purchases(app: AppHandle) -> Result<CloudAccountSnapshot, String> {
    restore_or_reconcile(&app, true).await
}

#[tauri::command]
#[specta::specta]
pub async fn reconcile_app_store_purchases(app: AppHandle) -> Result<CloudAccountSnapshot, String> {
    restore_or_reconcile(&app, false).await
}
