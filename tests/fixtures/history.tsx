import React from "react";
import { createRoot } from "react-dom/client";
import { mockIPC } from "@tauri-apps/api/mocks";
import { HistorySettings } from "../../src/components/settings/history/HistorySettings";
import { useSettingsStore } from "../../src/stores/settingsStore";
import type { HistoryEntry, AppSettings } from "../../src/bindings";
import "../../src/i18n";
import "../../src/App.css";

const scenario = new URLSearchParams(location.search).get("scenario");
const calls: { command: string; args: unknown }[] = [];
Object.assign(window, { historyTestCalls: calls });
let attempts = 0;
const entry = (id: number, text: string): HistoryEntry => ({
  id,
  file_name: "synthetic.wav.enc",
  timestamp: 1_780_000_000,
  saved: false,
  title: "Synthetic entry",
  transcription_text: text,
  post_processed_text: null,
  post_process_prompt: null,
  post_process_requested: false,
  audio_available: false,
  audio_saved: false,
  metadata: {
    tags: [],
    mode_id: null,
    processing_route: null,
    application_name: null,
    application_bundle_id: null,
    parent_entry_id: null,
    status: "completed",
  },
});
mockIPC(
  async (command, payload) => {
    calls.push({ command, args: payload });
    const args = payload as { cursor?: number | null; query?: string };
    if (command === "get_productivity_config") return { modes: [] };
    if (command === "get_history_entries") {
      if (scenario === "recovery" && attempts++ === 0)
        return Promise.reject("history_unavailable");
      return { entries: [entry(200, "initial transcript")], has_more: false };
    }
    if (command === "search_history_entries") {
      if (args.query === "old") {
        await new Promise((resolve) => setTimeout(resolve, 700));
        return {
          entries: [entry(99, "old result")],
          next_cursor: 99,
          has_more: false,
        };
      }
      if (args.query === "new")
        return {
          entries: [entry(98, "new result")],
          next_cursor: 98,
          has_more: false,
        };
      if (!args.cursor)
        return { entries: [], next_cursor: 100, has_more: true };
      return {
        entries: [entry(42, "needle transcript")],
        next_cursor: 42,
        has_more: false,
      };
    }
    throw new Error(`Unexpected test IPC: ${command}`);
  },
  { shouldMockEvents: true },
);
// Only the history preference is read by this fixture's production component.
useSettingsStore.setState({
  isLoading: false,
  settings: { history_enabled: true } as AppSettings,
});
createRoot(document.getElementById("root")!).render(<HistorySettings />);
