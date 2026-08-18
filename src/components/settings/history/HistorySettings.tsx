import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  Archive,
  Check,
  Copy,
  FileJson,
  FileText,
  FolderOpen,
  RotateCcw,
  Search,
  ShieldCheck,
  Star,
  Tag,
  Trash2,
  WandSparkles,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { AppPageHeader } from "@/components/layout";
import {
  commands,
  events,
  type HistoryEntry,
  type HistoryUpdatePayload,
  type PressayMode,
} from "@/bindings";
import { formatDateTime } from "@/utils/dateFormat";
import { AudioPlayer, AudioPlayerGroup } from "../../ui/AudioPlayer";
import { Button } from "../../ui/Button";
import { Input } from "../../ui/Input";
import { useSettings } from "../../../hooks/useSettings";

type HistoryFilter = "all" | "saved" | "derived" | "failed";

const IconButton: React.FC<{
  onClick: () => void;
  title: string;
  disabled?: boolean;
  active?: boolean;
  children: React.ReactNode;
}> = ({ onClick, title, disabled, active, children }) => (
  <button
    onClick={onClick}
    disabled={disabled}
    className={`p-1.5 rounded-md flex items-center justify-center transition-colors cursor-pointer disabled:cursor-not-allowed disabled:text-text/20 ${
      active
        ? "text-logo-primary hover:text-logo-primary/80"
        : "text-text/50 hover:text-logo-primary"
    }`}
    title={title}
  >
    {children}
  </button>
);

const PAGE_SIZE = 30;
const HISTORY_LOAD_TIMEOUT_MS = 12_000;

const withTimeout = <T,>(promise: Promise<T>, timeoutMs: number) =>
  new Promise<T>((resolve, reject) => {
    const timeout = window.setTimeout(
      () => reject(new Error("history_keychain_timeout")),
      timeoutMs,
    );
    promise.then(
      (value) => {
        window.clearTimeout(timeout);
        resolve(value);
      },
      (error) => {
        window.clearTimeout(timeout);
        reject(error);
      },
    );
  });

interface OpenRecordingsButtonProps {
  onClick: () => void;
  label: string;
}

const OpenRecordingsButton: React.FC<OpenRecordingsButtonProps> = ({
  onClick,
  label,
}) => (
  <Button
    onClick={onClick}
    variant="secondary"
    size="sm"
    className="flex items-center gap-2"
    title={label}
  >
    <FolderOpen className="w-4 h-4" />
    <span>{label}</span>
  </Button>
);

export const HistorySettings: React.FC = () => {
  const { t } = useTranslation();
  const { getSetting, updateSetting, isUpdating } = useSettings();
  const historyEnabled = getSetting("history_enabled") ?? false;
  const [entries, setEntries] = useState<HistoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<HistoryFilter>("all");
  const [modes, setModes] = useState<PressayMode[]>([]);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const entriesRef = useRef<HistoryEntry[]>([]);
  const loadingRef = useRef(false);

  // Keep ref in sync for use in IntersectionObserver callback
  useEffect(() => {
    entriesRef.current = entries;
  }, [entries]);

  const loadPage = useCallback(
    async (cursor?: number) => {
      if (!historyEnabled) {
        setLoading(false);
        return;
      }
      const isFirstPage = cursor === undefined;
      if (!isFirstPage && loadingRef.current) return;
      loadingRef.current = true;

      if (isFirstPage) {
        setLoading(true);
        setLoadError(null);
      }

      try {
        const result = await withTimeout(
          commands.getHistoryEntries(cursor ?? null, PAGE_SIZE),
          HISTORY_LOAD_TIMEOUT_MS,
        );
        if (result.status === "ok") {
          const { entries: newEntries, has_more } = result.data;
          setEntries((prev) =>
            isFirstPage ? newEntries : [...prev, ...newEntries],
          );
          setHasMore(has_more);
        } else {
          setLoadError(result.error);
        }
      } catch (error) {
        console.error("Failed to load history entries:", error);
        setLoadError(
          error instanceof Error ? error.message : "history_load_failed",
        );
      } finally {
        setLoading(false);
        loadingRef.current = false;
      }
    },
    [historyEnabled],
  );

  // Initial load
  useEffect(() => {
    if (historyEnabled) void loadPage();
  }, [historyEnabled, loadPage]);

  useEffect(() => {
    if (!historyEnabled) return;
    void commands.getProductivityConfig().then((config) => {
      setModes(config.modes.filter((mode) => mode.id !== "faithful"));
    });
  }, [historyEnabled]);

  useEffect(() => {
    if (!historyEnabled || (!query.trim() && filter === "all")) return;
    const timeout = window.setTimeout(() => {
      void (async () => {
        try {
          const result = await withTimeout(
            commands.getHistoryEntries(null, null),
            HISTORY_LOAD_TIMEOUT_MS,
          );
          if (result.status === "ok") {
            setEntries(result.data.entries);
            setHasMore(false);
            setLoadError(null);
          } else {
            setLoadError(result.error);
          }
        } catch (error) {
          console.error("Failed to filter history entries:", error);
          setLoadError(
            error instanceof Error ? error.message : "history_load_failed",
          );
        }
      })();
    }, 180);
    return () => window.clearTimeout(timeout);
  }, [filter, historyEnabled, query]);

  // Infinite scroll via IntersectionObserver
  useEffect(() => {
    if (loading) return;

    const sentinel = sentinelRef.current;
    if (!sentinel || !hasMore) return;

    const observer = new IntersectionObserver(
      (observerEntries) => {
        const first = observerEntries[0];
        if (first.isIntersecting) {
          const lastEntry = entriesRef.current[entriesRef.current.length - 1];
          if (lastEntry) {
            loadPage(lastEntry.id);
          }
        }
      },
      { threshold: 0 },
    );

    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [loading, hasMore, loadPage]);

  // Listen for new entries added from the transcription pipeline
  useEffect(() => {
    const unlisten = events.historyUpdatePayload.listen((event) => {
      const payload: HistoryUpdatePayload = event.payload;
      if (payload.action === "added") {
        setEntries((prev) => [payload.entry, ...prev]);
      } else if (payload.action === "updated") {
        setEntries((prev) =>
          prev.map((e) => (e.id === payload.entry.id ? payload.entry : e)),
        );
      }
      // "deleted" and "toggled" are handled by optimistic updates only,
      // so we intentionally ignore them here to avoid double-mutation.
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  const toggleSaved = async (id: number) => {
    // Optimistic update
    setEntries((prev) =>
      prev.map((e) => (e.id === id ? { ...e, saved: !e.saved } : e)),
    );
    try {
      const result = await commands.toggleHistoryEntrySaved(id);
      if (result.status !== "ok") {
        // Revert on failure
        setEntries((prev) =>
          prev.map((e) => (e.id === id ? { ...e, saved: !e.saved } : e)),
        );
      }
    } catch (error) {
      console.error("Failed to toggle saved status:", error);
      // Revert on failure
      setEntries((prev) =>
        prev.map((e) => (e.id === id ? { ...e, saved: !e.saved } : e)),
      );
    }
  };

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch (error) {
      console.error("Failed to copy to clipboard:", error);
    }
  };

  const toggleAudioSaved = async (id: number) => {
    const result = await commands.toggleHistoryAudioSaved(id);
    if (result.status === "ok") {
      setEntries((current) =>
        current.map((entry) => (entry.id === id ? result.data : entry)),
      );
    }
  };

  const getAudioUrl = useCallback(async (fileName: string) => {
    try {
      const result = await commands.getHistoryAudio(fileName);
      if (result.status === "ok") {
        const blob = new Blob([new Uint8Array(result.data)], {
          type: "audio/wav",
        });
        return URL.createObjectURL(blob);
      }
      return null;
    } catch (error) {
      console.error("Failed to get audio file path:", error);
      return null;
    }
  }, []);

  const deleteAudioEntry = async (id: number) => {
    // Optimistically remove
    setEntries((prev) => prev.filter((e) => e.id !== id));
    try {
      const result = await commands.deleteHistoryEntry(id);
      if (result.status !== "ok") {
        // Reload on failure
        loadPage();
      }
    } catch (error) {
      console.error("Failed to delete entry:", error);
      loadPage();
    }
  };

  const retryHistoryEntry = async (id: number) => {
    const result = await commands.retryHistoryEntryTranscription(id);
    if (result.status !== "ok") {
      throw new Error(String(result.error));
    }
  };

  const updateTags = async (id: number, tags: string[]) => {
    const result = await commands.updateHistoryEntryTags(id, tags);
    if (result.status === "error") throw new Error(String(result.error));
    setEntries((current) =>
      current.map((entry) => (entry.id === id ? result.data : entry)),
    );
  };

  const reprocessEntry = async (id: number, modeId: string) => {
    const result = await commands.reprocessHistoryEntry(id, modeId);
    if (result.status === "error") throw new Error(String(result.error));
  };

  const openRecordingsFolder = async () => {
    try {
      const result = await commands.openRecordingsFolder();
      if (result.status !== "ok") {
        throw new Error(String(result.error));
      }
    } catch (error) {
      console.error("Failed to open recordings folder:", error);
    }
  };

  const deleteAllHistory = async () => {
    const confirmed = window.confirm(
      t("settings.history.deleteAllConfirmation", {
        defaultValue:
          "Delete all local history, encrypted recordings, and the history encryption key? This cannot be undone.",
      }),
    );
    if (!confirmed) return;

    const result = await commands.deleteAllHistory();
    if (result.status === "error") {
      toast.error(
        t("settings.history.deleteAllError", {
          defaultValue: "The local history could not be deleted.",
        }),
      );
      return;
    }
    setEntries([]);
    setHasMore(false);
  };

  const visibleEntries = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase();
    return entries.filter((entry) => {
      const matchesFilter =
        filter === "all" ||
        (filter === "saved" && entry.saved) ||
        (filter === "derived" && entry.metadata?.parent_entry_id != null) ||
        (filter === "failed" && entry.metadata?.status === "failed");
      if (!matchesFilter) return false;
      if (!normalizedQuery) return true;
      return [
        entry.title,
        entry.transcription_text,
        entry.post_processed_text,
        entry.metadata?.mode_id,
        entry.metadata?.application_name,
        ...(entry.metadata?.tags ?? []),
      ]
        .filter(Boolean)
        .some((value) =>
          String(value).toLocaleLowerCase().includes(normalizedQuery),
        );
    });
  }, [entries, filter, query]);

  const downloadExport = (format: "markdown" | "json") => {
    const safeEntries = visibleEntries.map((entry) => ({
      id: entry.id,
      timestamp: entry.timestamp,
      title: entry.title,
      saved: entry.saved,
      transcription: entry.transcription_text,
      result: entry.post_processed_text,
      tags: entry.metadata?.tags ?? [],
      mode: entry.metadata?.mode_id ?? null,
      parentId: entry.metadata?.parent_entry_id ?? null,
    }));
    const content =
      format === "json"
        ? JSON.stringify({ version: 1, entries: safeEntries }, null, 2)
        : safeEntries
            .map((entry) => {
              const date = new Date(entry.timestamp * 1000).toISOString();
              const result = entry.result || entry.transcription;
              return `## ${entry.title || date}\n\n${result}\n\n<small>${date}</small>`;
            })
            .join("\n\n---\n\n");
    const blob = new Blob([content], {
      type: format === "json" ? "application/json" : "text/markdown",
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `pressay-history.${format === "json" ? "json" : "md"}`;
    anchor.click();
    URL.revokeObjectURL(url);
  };

  if (!historyEnabled) {
    return (
      <div className="history-page settings-page signal-settings-page">
        <AppPageHeader
          eyebrow={t("settings.history.eyebrow")}
          title={t("settings.history.title")}
          description={t("settings.history.description")}
        />
        <section className="history-disabled-state">
          <div className="history-privacy-icon">
            <ShieldCheck size={22} aria-hidden="true" />
          </div>
          <p className="product-eyebrow">
            {t("settings.history.privateEyebrow")}
          </p>
          <h2>{t("settings.history.disabledTitle")}</h2>
          <p>{t("settings.history.disabledDescription")}</p>
          <ul>
            <li>{t("settings.history.privateText")}</li>
            <li>{t("settings.history.privateAudio")}</li>
            <li>{t("settings.history.privateControl")}</li>
          </ul>
          <Button
            disabled={isUpdating("history_enabled")}
            onClick={() => updateSetting("history_enabled", true)}
          >
            {t("settings.history.enable")}
          </Button>
        </section>
      </div>
    );
  }

  let content: React.ReactNode;

  if (loading) {
    content = (
      <div className="px-4 py-3 text-center text-text/60">
        {t("settings.history.loading")}
      </div>
    );
  } else if (loadError) {
    content = (
      <div className="history-load-error" role="alert">
        <p>{t("settings.history.loadError")}</p>
        <Button size="sm" variant="secondary" onClick={() => void loadPage()}>
          {t("cloud.actions.retry")}
        </Button>
      </div>
    );
  } else if (visibleEntries.length === 0) {
    content = (
      <div className="px-4 py-3 text-center text-text/60">
        {t("settings.history.empty")}
      </div>
    );
  } else {
    content = (
      <>
        <AudioPlayerGroup>
          <div className="divide-y divide-mid-gray/20">
            {visibleEntries.map((entry) => (
              <HistoryEntryComponent
                key={entry.id}
                entry={entry}
                onToggleSaved={() => toggleSaved(entry.id)}
                onToggleAudioSaved={() => toggleAudioSaved(entry.id)}
                onCopyText={() =>
                  copyToClipboard(
                    entry.post_processed_text ?? entry.transcription_text,
                  )
                }
                getAudioUrl={getAudioUrl}
                deleteAudio={deleteAudioEntry}
                retryTranscription={retryHistoryEntry}
                modes={modes}
                updateTags={updateTags}
                reprocessEntry={reprocessEntry}
              />
            ))}
          </div>
        </AudioPlayerGroup>
        {/* Sentinel for infinite scroll */}
        <div ref={sentinelRef} className="h-1" />
      </>
    );
  }

  return (
    <div className="history-page settings-page signal-settings-page">
      <AppPageHeader
        eyebrow={t("settings.history.eyebrow")}
        title={t("settings.history.title")}
        description={t("settings.history.description")}
        action={
          <div className="history-header-actions">
            <Button
              onClick={() => updateSetting("history_enabled", false)}
              variant="ghost"
              size="sm"
            >
              {t("settings.history.disable")}
            </Button>
            <OpenRecordingsButton
              onClick={openRecordingsFolder}
              label={t("settings.history.openFolder")}
            />
          </div>
        }
      />

      <div className="history-toolbar">
        <label className="history-search">
          <Search size={15} aria-hidden="true" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("settings.history.search")}
            aria-label={t("settings.history.search")}
          />
        </label>
        <div
          className="history-filters"
          role="group"
          aria-label={t("settings.history.filtersLabel")}
        >
          {(["all", "saved", "derived", "failed"] as const).map((value) => (
            <Button
              key={value}
              onClick={() => setFilter(value)}
              variant={filter === value ? "primary-soft" : "ghost"}
              size="sm"
              aria-pressed={filter === value}
            >
              {t(`settings.history.filters.${value}`)}
            </Button>
          ))}
        </div>
        <div className="history-export-actions">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => downloadExport("markdown")}
          >
            <FileText size={14} aria-hidden="true" />
            {t("settings.history.exportMarkdown")}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => downloadExport("json")}
          >
            <FileJson size={14} aria-hidden="true" />
            {t("settings.history.exportJson")}
          </Button>
          <Button onClick={deleteAllHistory} variant="danger-ghost" size="sm">
            {t("settings.history.deleteAll")}
          </Button>
        </div>
      </div>

      <div className="history-list">{content}</div>
    </div>
  );
};

interface HistoryEntryProps {
  entry: HistoryEntry;
  onToggleSaved: () => void;
  onToggleAudioSaved: () => void;
  onCopyText: () => void;
  getAudioUrl: (fileName: string) => Promise<string | null>;
  deleteAudio: (id: number) => Promise<void>;
  retryTranscription: (id: number) => Promise<void>;
  modes: PressayMode[];
  updateTags: (id: number, tags: string[]) => Promise<void>;
  reprocessEntry: (id: number, modeId: string) => Promise<void>;
}

const HistoryEntryComponent: React.FC<HistoryEntryProps> = ({
  entry,
  onToggleSaved,
  onToggleAudioSaved,
  onCopyText,
  getAudioUrl,
  deleteAudio,
  retryTranscription,
  modes,
  updateTags,
  reprocessEntry,
}) => {
  const { t, i18n } = useTranslation();
  const [showCopied, setShowCopied] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [editingTags, setEditingTags] = useState(false);
  const [tagDraft, setTagDraft] = useState(
    () => entry.metadata?.tags?.join(", ") ?? "",
  );
  const [selectedModeId, setSelectedModeId] = useState(
    () => modes[0]?.id ?? "clean",
  );
  const [reprocessing, setReprocessing] = useState(false);

  const hasTranscription = entry.transcription_text.trim().length > 0;
  const finalText =
    entry.post_processed_text?.trim() || entry.transcription_text;

  const handleLoadAudio = useCallback(
    () => getAudioUrl(entry.file_name),
    [getAudioUrl, entry.file_name],
  );

  const handleCopyText = () => {
    if (!hasTranscription) {
      return;
    }

    onCopyText();
    setShowCopied(true);
    setTimeout(() => setShowCopied(false), 2000);
  };

  const handleDeleteEntry = async () => {
    try {
      await deleteAudio(entry.id);
    } catch (error) {
      console.error("Failed to delete entry:", error);
      toast.error(t("settings.history.deleteError"));
    }
  };

  const handleRetranscribe = async () => {
    try {
      setRetrying(true);
      await retryTranscription(entry.id);
    } catch (error) {
      console.error("Failed to re-transcribe:", error);
      toast.error(t("settings.history.retranscribeError"));
    } finally {
      setRetrying(false);
    }
  };

  const formattedDate = formatDateTime(String(entry.timestamp), i18n.language);

  const handleSaveTags = async () => {
    try {
      const tags = tagDraft
        .split(",")
        .map((tag) => tag.trim())
        .filter(Boolean);
      await updateTags(entry.id, tags);
      setEditingTags(false);
    } catch (error) {
      console.error("Failed to update history tags:", error);
      toast.error(t("settings.history.tagsError"));
    }
  };

  const handleReprocess = async () => {
    if (!selectedModeId) return;
    try {
      setReprocessing(true);
      await reprocessEntry(entry.id, selectedModeId);
      toast.success(t("settings.history.reprocessSuccess"));
    } catch (error) {
      console.error("Failed to reprocess history entry:", error);
      toast.error(t("settings.history.reprocessError"));
    } finally {
      setReprocessing(false);
    }
  };

  return (
    <div className="px-4 py-2 pb-5 flex flex-col gap-3">
      <div className="flex justify-between items-center">
        <p className="text-sm font-medium">{formattedDate}</p>
        <div className="flex items-center">
          <IconButton
            onClick={handleCopyText}
            disabled={!hasTranscription || retrying}
            title={t("settings.history.copyToClipboard")}
          >
            {showCopied ? (
              <Check width={16} height={16} />
            ) : (
              <Copy width={16} height={16} />
            )}
          </IconButton>
          <IconButton
            onClick={onToggleSaved}
            disabled={retrying}
            active={entry.saved}
            title={
              entry.saved
                ? t("settings.history.unsave")
                : t("settings.history.save")
            }
          >
            <Star
              width={16}
              height={16}
              fill={entry.saved ? "currentColor" : "none"}
            />
          </IconButton>
          {entry.audio_available && (
            <IconButton
              onClick={onToggleAudioSaved}
              disabled={retrying}
              active={entry.audio_saved}
              title={t("settings.history.preserveAudio", {
                defaultValue: entry.audio_saved
                  ? "Use the normal audio retention"
                  : "Preserve this recording",
              })}
            >
              <Archive width={16} height={16} />
            </IconButton>
          )}
          <IconButton
            onClick={handleRetranscribe}
            disabled={retrying}
            title={t("settings.history.retranscribe")}
          >
            <RotateCcw
              width={16}
              height={16}
              style={
                retrying
                  ? { animation: "spin 1s linear infinite reverse" }
                  : undefined
              }
            />
          </IconButton>
          <IconButton
            onClick={handleDeleteEntry}
            disabled={retrying}
            title={t("settings.history.delete")}
          >
            <Trash2 width={16} height={16} />
          </IconButton>
        </div>
      </div>

      <p
        className={`italic text-sm pb-2 ${
          retrying
            ? ""
            : hasTranscription
              ? "text-text/90 select-text cursor-text whitespace-pre-wrap break-words"
              : "text-text/40"
        }`}
        style={
          retrying
            ? { animation: "transcribe-pulse 3s ease-in-out infinite" }
            : undefined
        }
      >
        {retrying && (
          <style>{`
            @keyframes transcribe-pulse {
              0%, 100% { color: color-mix(in srgb, var(--color-text) 40%, transparent); }
              50% { color: color-mix(in srgb, var(--color-text) 90%, transparent); }
            }
          `}</style>
        )}
        {retrying
          ? t("settings.history.transcribing")
          : hasTranscription
            ? finalText
            : t("settings.history.transcriptionFailed")}
      </p>

      {entry.post_processed_text?.trim() ? (
        <details className="history-source-text">
          <summary>{t("settings.history.showOriginal")}</summary>
          <p>{entry.transcription_text}</p>
        </details>
      ) : null}

      <div className="history-entry-context">
        {entry.metadata?.parent_entry_id != null ? (
          <span className="history-context-chip">
            <WandSparkles size={12} aria-hidden="true" />
            {t("settings.history.derived")}
          </span>
        ) : null}
        {entry.metadata?.mode_id ? (
          <span className="history-context-chip">{entry.metadata.mode_id}</span>
        ) : null}
        {entry.metadata?.processing_route ? (
          <span className="history-context-chip is-route">
            {entry.metadata.processing_route}
          </span>
        ) : null}
        {entry.metadata?.application_name ? (
          <span className="history-context-chip">
            {entry.metadata.application_name}
          </span>
        ) : null}
      </div>

      <div className="history-tags-row">
        <Tag size={13} aria-hidden="true" />
        {(entry.metadata?.tags ?? []).map((tag) => (
          <span key={tag} className="history-tag">
            #{tag}
          </span>
        ))}
        <Button variant="ghost" size="sm" onClick={() => setEditingTags(true)}>
          {t("settings.history.editTags")}
        </Button>
      </div>

      {editingTags ? (
        <div className="history-tag-editor">
          <Input
            value={tagDraft}
            onChange={(event) => setTagDraft(event.target.value)}
            placeholder={t("settings.history.tagsPlaceholder")}
            aria-label={t("settings.history.tagsLabel")}
            onKeyDown={(event) => {
              if (event.key === "Enter") void handleSaveTags();
              if (event.key === "Escape") setEditingTags(false);
            }}
          />
          <Button size="sm" onClick={() => void handleSaveTags()}>
            {t("common.save")}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setEditingTags(false)}
          >
            {t("common.cancel")}
          </Button>
        </div>
      ) : null}

      {hasTranscription && modes.length > 0 ? (
        <div className="history-reprocess-row">
          <select
            value={selectedModeId}
            onChange={(event) => setSelectedModeId(event.target.value)}
            aria-label={t("settings.history.reprocessMode")}
          >
            {modes.map((mode) => (
              <option key={mode.id} value={mode.id}>
                {mode.is_builtin
                  ? t(`pressay.modes.builtins.${mode.id}.name`)
                  : mode.name}
              </option>
            ))}
          </select>
          <Button
            variant="secondary"
            size="sm"
            disabled={reprocessing}
            onClick={() => void handleReprocess()}
          >
            <WandSparkles size={14} aria-hidden="true" />
            {reprocessing
              ? t("settings.history.reprocessing")
              : t("settings.history.reprocess")}
          </Button>
        </div>
      ) : null}

      {entry.audio_available && (
        <AudioPlayer onLoadRequest={handleLoadAudio} className="w-full" />
      )}
    </div>
  );
};
