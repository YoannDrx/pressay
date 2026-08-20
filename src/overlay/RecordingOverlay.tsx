import { listen } from "@tauri-apps/api/event";
import React, { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import "./RecordingOverlay.css";
import { commands, events } from "@/bindings";
import type {
  StreamPhase,
  StreamPhaseEvent,
  StreamTextEvent,
  StreamWorkKind,
  VoiceSurfaceState,
} from "@/bindings";
import i18n, { syncLanguageFromSettings } from "@/i18n";
import { getLanguageDirection } from "@/lib/utils/rtl";
import { INITIAL_VOICE_SURFACE_STATE } from "@/lib/voiceSurface";

type OverlayState = "recording" | "streaming" | "transcribing" | "processing";

// Number of reactive bars in the waveform (the simple, smoothed style shared by
// every overlay form). Mic levels arrive as 16 FFT buckets; we take the first N.
const WAVE_BARS = 9;

const RecordingOverlay: React.FC = () => {
  const { t } = useTranslation();
  const [isVisible, setIsVisible] = useState(false);
  const [state, setState] = useState<OverlayState>("recording");
  const [voiceSurface, setVoiceSurface] = useState<VoiceSurfaceState>(
    INITIAL_VOICE_SURFACE_STATE,
  );
  // `Stream::play()` returning does not mean hardware callbacks are flowing.
  // Stay visually in an arming state until the backend processes the first
  // actual microphone sample chunk.
  const [captureReady, setCaptureReady] = useState(false);
  const [levels, setLevels] = useState<number[]>(Array(WAVE_BARS).fill(0));
  const [streamText, setStreamText] = useState<StreamTextEvent>({
    committed: "",
    tentative: "",
  });
  const [phase, setPhase] = useState<StreamPhase>("listening");
  const [workKind, setWorkKind] = useState<StreamWorkKind>("transcribing");
  const [elapsed, setElapsed] = useState(0);
  // Bumped on each new streaming session so the Live card remounts fresh (replays
  // the pop-in, and never animates in from the previous panel's open size).
  const [session, setSession] = useState(0);
  // Overlay placement (top vs bottom of the screen). The Live panel grows downward
  // from a top overlay (oldest line under the pill) and upward from a bottom one.
  const [position, setPosition] = useState<"top" | "bottom">("bottom");
  const [overlayStyle, setOverlayStyle] = useState<"minimal" | "live">("live");
  // True once live text overflows the cap. A top overlay fades its top edge only
  // while overflowing, so the resting first line stays crisp flush under the pill.
  const [overflowing, setOverflowing] = useState(false);

  const smoothedLevelsRef = useRef<number[]>(Array(16).fill(0));
  // Live-text scroll-back: the text region "sticks" to the newest line while the
  // user is at the bottom; if they scroll up to read history, auto-follow pauses
  // until they scroll back down.
  const capRef = useRef<HTMLDivElement>(null);
  const pinnedRef = useRef(true);
  const direction = getLanguageDirection(i18n.language);
  const routeLabel =
    voiceSurface.route === "byok" && voiceSurface.provider_id
      ? voiceSurface.provider_id
      : t(`signalOs.overlay.routes.${voiceSurface.route}`);

  useEffect(() => {
    void commands
      .getVoiceSurfaceState()
      .then(setVoiceSurface)
      .catch(() => undefined);
    const setupEventListeners = async () => {
      const unlistenShow = await listen("show-overlay", async (event) => {
        const overlayState = event.payload as OverlayState;
        // Reset synchronously before settings I/O. A fast microphone can emit
        // recording-ready while the awaits below are in flight; resetting after
        // them would overwrite that event and leave the overlay stuck arming.
        if (overlayState === "recording" || overlayState === "streaming") {
          setCaptureReady(false);
          smoothedLevelsRef.current = Array(16).fill(0);
          setLevels(Array(WAVE_BARS).fill(0));
          setStreamText({ committed: "", tentative: "" });
        }

        await syncLanguageFromSettings();
        // The Live panel flows downward from a top overlay and upward from a
        // bottom one; read the placement so the layout can flip to match.
        try {
          const settings = await commands.getAppSettings();
          if (settings.status === "ok") {
            setPosition(
              settings.data.overlay_position === "top" ? "top" : "bottom",
            );
            setOverlayStyle(
              settings.data.overlay_style === "minimal" ? "minimal" : "live",
            );
          }
        } catch {
          // Keep the previous/default placement if settings can't be read.
        }
        setState(overlayState);
        if (overlayState === "streaming") {
          setPhase("listening");
          setWorkKind("transcribing");
          setElapsed(0);
          setSession((s) => s + 1); // remount the card fresh for this session
        }
        setIsVisible(true);
      });

      const unlistenHide = await listen("hide-overlay", () => {
        setIsVisible(false);
        setCaptureReady(false);
      });

      const unlistenReady = await listen("recording-ready", () => {
        setElapsed(0);
        setCaptureReady(true);
      });

      const unlistenLevel = await listen<number[]>("mic-level", (event) => {
        const newLevels = event.payload as number[];
        // Exponential smoothing across the 16 buckets, then take the first N
        // bars for the shared waveform.
        const smoothed = smoothedLevelsRef.current.map((prev, i) => {
          const target = newLevels[i] || 0;
          return prev * 0.7 + target * 0.3;
        });
        smoothedLevelsRef.current = smoothed;
        setLevels(smoothed.slice(0, WAVE_BARS));
      });

      const unlistenStream = await events.streamTextEvent.listen((event) => {
        setStreamText(event.payload);
      });

      const unlistenPhase = await events.streamPhaseEvent.listen((event) => {
        const payload: StreamPhaseEvent = event.payload;
        setPhase(payload.phase);
        if (payload.kind) setWorkKind(payload.kind);
      });

      const unlistenVoiceSurface = await events.voiceSurfaceState.listen(
        (event) => {
          const surface = event.payload;
          setVoiceSurface(surface);
          if (surface.phase === "hidden") {
            setIsVisible(false);
            setCaptureReady(false);
            return;
          }
          if (surface.phase === "listening") setCaptureReady(true);
          if (surface.phase === "transcribing") {
            setPhase("working");
            setWorkKind("transcribing");
            setState((current) =>
              current === "streaming" ? current : "transcribing",
            );
          } else if (surface.phase === "transforming") {
            setPhase("working");
            setWorkKind("polishing");
            setState((current) =>
              current === "streaming" ? current : "processing",
            );
          }
        },
      );

      return () => {
        unlistenShow();
        unlistenHide();
        unlistenReady();
        unlistenLevel();
        unlistenStream();
        unlistenPhase();
        unlistenVoiceSurface();
      };
    };

    setupEventListeners();
  }, []);

  // Elapsed capture timer starts only once microphone samples are flowing.
  useEffect(() => {
    if (state !== "streaming" || !isVisible || !captureReady) return;
    const id = setInterval(() => setElapsed((e) => e + 1), 1000);
    return () => clearInterval(id);
  }, [state, isVisible, captureReady]);

  // Stick to the bottom as text streams in — but only while pinned, so a user who
  // has scrolled up to read history isn't yanked back down by the next chunk.
  useLayoutEffect(() => {
    const el = capRef.current;
    if (!el) return;
    // Fade the top edge only once text actually overflows the cap.
    setOverflowing(el.scrollHeight > el.clientHeight + 1);
    if (pinnedRef.current) el.scrollTop = el.scrollHeight;
  }, [streamText]);

  // Each fresh streaming session starts pinned to the bottom, fade cleared.
  useEffect(() => {
    pinnedRef.current = true;
    setOverflowing(false);
  }, [session]);

  if (!isVisible) return null;

  // Re-pin when the user is within ~a line of the bottom; unpin otherwise.
  const handleStreamScroll = () => {
    const el = capRef.current;
    if (!el) return;
    pinnedRef.current = el.scrollHeight - el.scrollTop - el.clientHeight <= 16;
  };

  const fmtTime = (s: number) =>
    `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

  // ---- Shared building blocks (one visual language for every overlay form) ----
  const waveform = (
    <div className={`swave ${captureReady ? "ready" : "arming"}`}>
      {levels.map((v, i) => (
        <i
          key={i}
          style={{
            height: `${Math.max(3, Math.min(18, 3 + Math.pow(v, 0.7) * 15))}px`,
          }}
        />
      ))}
    </div>
  );

  const cancelBtn = (
    <button
      className="sx"
      aria-label={t("tray.cancel")}
      onClick={() => commands.cancelOperation()}
    >
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path
          d="M4 4 L12 12 M12 4 L4 12"
          stroke="currentColor"
          strokeWidth="1.6"
          strokeLinecap="round"
        />
      </svg>
    </button>
  );

  const dismissBtn = (
    <button
      className="sx"
      aria-label={t("common.close")}
      onClick={() => commands.dismissVoiceSurface()}
    >
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path
          d="M4 4 L12 12 M12 4 L4 12"
          stroke="currentColor"
          strokeWidth="1.6"
          strokeLinecap="round"
        />
      </svg>
    </button>
  );

  // dot (left) | waveform (center) | timer + cancel (right) — same structure for
  // pill & panel, so the Live morph is a pure width change.
  const listeningRow = (
    showDetails: boolean,
    showTimer: boolean,
    showCancel: boolean,
  ) => (
    <div className="sbase">
      <div className="sbase-l">
        <span className={`sdot ${captureReady ? "ready" : "arming"}`} />
        {showDetails && (
          <span className={`sroute route-${voiceSurface.route}`}>
            {routeLabel}
          </span>
        )}
      </div>
      {waveform}
      <div className="sbase-r">
        {showTimer && <span className="stimer">{fmtTime(elapsed)}</span>}
        {showCancel && cancelBtn}
      </div>
    </div>
  );

  // spinner (left) | label (center) | cancel (right) — same 3-zone grid as the
  // listening row, so the label is centered.
  const workingRow = (label: string, showCancel: boolean) => (
    <div className="sbase">
      <div className="sbase-l">
        <span className="sspinner" />
      </div>
      <span className="swork-label">
        {label}
        <small className={`sroute route-${voiceSurface.route}`}>
          {routeLabel}
        </small>
      </span>
      <div className="sbase-r">{showCancel && cancelBtn}</div>
    </div>
  );

  if (["success", "cancelled", "failed"].includes(voiceSurface.phase)) {
    const errorCode = voiceSurface.error?.code;
    const knownErrors = [
      "no_audio",
      "silent_input",
      "microphone_permission_denied",
      "paste_failed",
      "transform_timeout",
    ];
    const errorLabel =
      errorCode && knownErrors.includes(errorCode)
        ? t(`signalOs.overlay.errors.${errorCode}`)
        : t("signalOs.overlay.errors.fallback");
    const canOpenMicrophone = voiceSurface.available_actions.includes(
      "open_microphone_settings",
    );
    const canOpenSettings = voiceSurface.available_actions.some((action) =>
      [
        "open_accessibility_settings",
        "open_model_settings",
        "open_provider_settings",
      ].includes(action),
    );
    const handleRecovery = async () => {
      if (canOpenMicrophone) {
        await commands.openMicrophonePrivacySettings();
      } else if (canOpenSettings) {
        await commands.showMainWindowCommand();
      }
      await commands.dismissVoiceSurface();
    };
    const label =
      voiceSurface.phase === "success"
        ? t("signalOs.overlay.success")
        : voiceSurface.phase === "cancelled"
          ? t("signalOs.overlay.cancelled")
          : errorLabel;

    return (
      <div dir={direction} className={`ov-stage ${position} ov-fade show`}>
        <div className={`scard compact voice-result is-${voiceSurface.phase}`}>
          <div className="sbase">
            <div className="sbase-l">
              <span className="result-glyph" aria-hidden="true" />
            </div>
            <span className="swork-label">
              {label}
              <small className={`sroute route-${voiceSurface.route}`}>
                {routeLabel}
              </small>
            </span>
            <div className="sbase-r">
              {voiceSurface.phase === "failed" ? (
                <button
                  type="button"
                  className="recovery-action"
                  aria-label={
                    canOpenMicrophone || canOpenSettings
                      ? t("signalOs.overlay.settings")
                      : t("signalOs.overlay.retry")
                  }
                  onClick={handleRecovery}
                >
                  <svg viewBox="0 0 16 16" aria-hidden="true">
                    <path
                      d="M13 5V2.5M13 2.5h-2.5M13 2.5A6 6 0 1 0 14 9"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1.4"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                </button>
              ) : null}
              {dismissBtn}
            </div>
          </div>
        </div>
      </div>
    );
  }

  // ---- Live overlay: a pill that sculpts open into a panel ----
  if (state === "streaming") {
    const hasText =
      streamText.committed.length > 0 || streamText.tentative.length > 0;
    const working = phase === "working";
    // Keep the panel open whenever there's text — even while finalizing — so the
    // transcript stays put under a working spinner instead of collapsing and
    // squishing the text mid-stream. Only fall back to the small working pill
    // when there was no text to preserve.
    const open = hasText;
    const collapsed = working && !hasText;

    return (
      <div dir={direction} className={`ov-stage ${position}`}>
        <div
          key={session}
          className={`scard ${open ? "open" : ""} ${collapsed ? "working" : ""} ${
            isVisible ? "" : "leaving"
          }`}
        >
          <div className="stext">
            <div className="stext-clip">
              <div
                className={`stext-cap ${overflowing ? "overflowing" : ""}`}
                ref={capRef}
                onScroll={handleStreamScroll}
              >
                <p>
                  <span className="committed">
                    {streamText.committed ? streamText.committed + " " : ""}
                  </span>
                  <span className="tentative">{streamText.tentative}</span>
                  {/* Drop the blinking caret once finalizing — it's no longer
                      capturing, and a static spinner conveys the work. */}
                  {!working && <span className="scaret" />}
                </p>
              </div>
            </div>
          </div>
          {working
            ? workingRow(
                workKind === "polishing"
                  ? t("overlay.processing")
                  : t("overlay.transcribing"),
                true,
              )
            : listeningRow(true, open, true)}
        </div>
      </div>
    );
  }

  // ---- Minimal overlay: exactly one row at a time — waveform (recording), or a
  // spinner + label (transcribing / processing). Never both. The pill animates its
  // width between them; the cancel button is in both rows so it stays put.
  const working =
    state === "transcribing" ||
    state === "processing" ||
    ["transcribing", "transforming", "inserting"].includes(voiceSurface.phase);
  const workLabel =
    state === "processing" || voiceSurface.phase === "transforming"
      ? t("overlay.processing")
      : voiceSurface.phase === "inserting"
        ? t("signalOs.overlay.inserting")
        : t("overlay.transcribing");

  return (
    <div
      dir={direction}
      className={`ov-stage ${position} ov-fade ${isVisible ? "show" : ""}`}
    >
      <div
        className={`scard compact ${working && isVisible ? "cworking" : ""}`}
      >
        {working
          ? workingRow(workLabel, true)
          : listeningRow(overlayStyle === "live", false, true)}
      </div>
    </div>
  );
};

export default RecordingOverlay;
