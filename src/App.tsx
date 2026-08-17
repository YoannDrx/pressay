import { useEffect, useState, useRef, type ReactNode } from "react";
import { toast, Toaster } from "sonner";
import { useTranslation } from "react-i18next";
import { listen } from "@tauri-apps/api/event";
import { platform } from "@tauri-apps/plugin-os";
import {
  checkAccessibilityPermission,
  checkMicrophonePermission,
} from "tauri-plugin-macos-permissions-api";
import { ModelStateEvent, RecordingErrorEvent } from "./lib/types/events";
import "./App.css";
import AccessibilityPermissions from "./components/AccessibilityPermissions";
import SecureInputWarning from "./components/SecureInputWarning";
import Footer from "./components/footer";
import Onboarding, {
  AccessibilityOnboarding,
  OnboardingProgress,
  ShortcutOnboarding,
  WelcomeOnboarding,
} from "./components/onboarding";
import { ErrorBoundary } from "./components/ErrorBoundary";
import { Sidebar, SidebarSection, SECTIONS_CONFIG } from "./components/Sidebar";
import { WhatsNewGate } from "./components/whats-new";
import { useSettings } from "./hooks/useSettings";
import { useSettingsStore } from "./stores/settingsStore";
import { commands } from "@/bindings";
import { getLanguageDirection, initializeRTL } from "@/lib/utils/rtl";

type OnboardingStep =
  "welcome" | "accessibility" | "shortcut" | "model" | "done";

const renderSettingsContent = (section: SidebarSection) => {
  const ActiveComponent =
    SECTIONS_CONFIG[section]?.component || SECTIONS_CONFIG.general.component;
  return <ActiveComponent />;
};

function App() {
  const { t, i18n } = useTranslation();
  const [onboardingStep, setOnboardingStep] = useState<OnboardingStep | null>(
    null,
  );
  // Track if this is a returning user who just needs to grant permissions
  // (vs a new user who needs full onboarding including model selection)
  const [isReturningUser, setIsReturningUser] = useState(false);
  const [currentSection, setCurrentSection] = useState<SidebarSection>("home");
  const { settings, updateSetting } = useSettings();
  const direction = getLanguageDirection(i18n.language);
  const refreshAudioDevices = useSettingsStore(
    (state) => state.refreshAudioDevices,
  );
  const refreshOutputDevices = useSettingsStore(
    (state) => state.refreshOutputDevices,
  );
  const hasCompletedPostOnboardingInit = useRef(false);

  useEffect(() => {
    checkOnboardingStatus();
  }, []);

  // Initialize RTL direction when language changes
  useEffect(() => {
    initializeRTL(i18n.language);
  }, [i18n.language]);

  // Initialize Enigo, shortcuts, and refresh audio devices when main app loads
  useEffect(() => {
    if (onboardingStep === "done" && !hasCompletedPostOnboardingInit.current) {
      hasCompletedPostOnboardingInit.current = true;
      Promise.all([
        commands.initializeEnigo(),
        commands.initializeShortcuts(),
      ]).catch((e) => {
        console.warn("Failed to initialize:", e);
      });
      refreshAudioDevices();
      refreshOutputDevices();
    }
  }, [onboardingStep, refreshAudioDevices, refreshOutputDevices]);

  // Developer-only keyboard shortcut for the inherited debug panel. Production
  // builds expose only the redacted diagnostic export from Help.
  useEffect(() => {
    if (!import.meta.env.DEV) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      // Check for Ctrl+Shift+D (Windows/Linux) or Cmd+Shift+D (macOS)
      const isDebugShortcut =
        event.shiftKey &&
        event.key.toLowerCase() === "d" &&
        (event.ctrlKey || event.metaKey);

      if (isDebugShortcut) {
        event.preventDefault();
        const currentDebugMode = settings?.debug_mode ?? false;
        updateSetting("debug_mode", !currentDebugMode);
      }
    };

    // Add event listener when component mounts
    document.addEventListener("keydown", handleKeyDown);

    // Cleanup event listener when component unmounts
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [settings?.debug_mode, updateSetting]);

  // Listen for recording errors from the backend and show a toast
  useEffect(() => {
    const unlisten = listen<RecordingErrorEvent>("recording-error", (event) => {
      const { error_type, detail } = event.payload;

      if (error_type === "microphone_permission_denied") {
        const currentPlatform = platform();
        const platformKey = `errors.micPermissionDenied.${currentPlatform}`;
        const description = t(platformKey, {
          defaultValue: t("errors.micPermissionDenied.generic"),
        });
        toast.error(t("errors.micPermissionDeniedTitle"), { description });
      } else if (error_type === "no_input_device") {
        toast.error(t("errors.noInputDeviceTitle"), {
          description: t("errors.noInputDevice"),
        });
      } else if (error_type === "silent_input") {
        toast.warning(
          t("errors.silentInputTitle", { defaultValue: "No audio detected" }),
          {
            description: t("errors.silentInput", {
              defaultValue:
                "Check the selected microphone or input device and try again.",
            }),
          },
        );
      } else {
        toast.error(
          t("errors.recordingFailed", { error: detail ?? "Unknown error" }),
        );
      }
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  // Listen for paste failures and show a toast.
  // The technical error detail is logged to pressay.log on the Rust side
  // (see actions.rs `error!("Failed to paste transcription: ...")`),
  // so we show a localized, user-friendly message here instead of the raw error.
  useEffect(() => {
    const unlisten = listen<{ text: string }>("paste-error", (event) => {
      toast.error(t("errors.pasteFailedTitle"), {
        description: t("errors.pasteFailed"),
        action: {
          label: t("common.copy", { defaultValue: "Copy text" }),
          onClick: () => navigator.clipboard.writeText(event.payload.text),
        },
      });
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  useEffect(() => {
    const unlisten = listen<{ code: string; text: string }>(
      "transform-error",
      (event) => {
        toast.error(
          t("errors.transformFailedTitle", {
            defaultValue: "Transformation interrupted",
          }),
          {
            description: t("errors.transformFailed", {
              defaultValue:
                "Your local transcription is safe. You can copy it and try the transformation again.",
            }),
            action: {
              label: t("common.copy", { defaultValue: "Copy text" }),
              onClick: () => navigator.clipboard.writeText(event.payload.text),
            },
          },
        );
      },
    );
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  useEffect(() => {
    const unlisten = listen<{ code: string; text?: string }>(
      "correction-error",
      (event) => {
        const isFrench = i18n.resolvedLanguage?.startsWith("fr");
        const targetChanged =
          event.payload.code === "correction_target_changed";
        const expired = event.payload.code === "correction_session_expired";
        const description = targetChanged
          ? isFrench
            ? "Revenez dans l’application d’origine et placez le focus dans le champ dicté."
            : "Return to the original application and focus the field you dictated into."
          : expired
            ? isFrench
              ? "La fenêtre de correction privée de deux minutes a expiré."
              : "The private two-minute correction window has expired."
            : isFrench
              ? "L’insertion d’origine est restée intacte. Vérifiez votre fournisseur BYOK et réessayez."
              : "Your original insertion was left untouched. Check your BYOK provider and try again.";
        toast.error(
          isFrench ? "Correction non appliquée" : "Correction not applied",
          {
            description,
          },
        );
      },
    );
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [i18n.resolvedLanguage]);

  useEffect(() => {
    const unlisten = listen<{ code: string; text?: string }>(
      "correction-fallback",
      () => {
        const isFrench = i18n.resolvedLanguage?.startsWith("fr");
        toast.info(isFrench ? "Correction copiée" : "Correction copied", {
          description: isFrench
            ? "Pressay n’a pas pu vérifier le champ d’origine de façon sûre. La correction a été copiée sans modifier l’application."
            : "Pressay could not safely verify the original field, so it copied the correction without changing the app.",
        });
      },
    );
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [i18n.resolvedLanguage]);

  // Listen for transcription failures and show a toast.
  // The payload is the backend error message (also logged to pressay.log).
  useEffect(() => {
    const unlisten = listen<string>("transcription-error", (event) => {
      toast.error(t("errors.transcriptionFailedTitle"), {
        description: event.payload,
      });
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  useEffect(() => {
    const unlisten = listen<{
      requestId: string;
      durationSeconds: number;
    }>("cloud-transcription-available", (event) => {
      toast.info(t("cloud.transcription.availableTitle"), {
        description: t("cloud.transcription.availableDescription", {
          seconds: event.payload.durationSeconds,
        }),
        duration: 120_000,
        action: {
          label: t("cloud.transcription.send"),
          onClick: () => {
            void (async () => {
              const result = await commands.retryCloudTranscription(
                event.payload.requestId,
              );
              if (result.status === "error") {
                toast.error(t("cloud.transcription.error"));
                return;
              }
              toast.success(t("cloud.transcription.ready"), {
                description: t("cloud.transcription.readyDescription"),
                action: {
                  label: t("common.copy"),
                  onClick: () =>
                    navigator.clipboard.writeText(result.data.text),
                },
              });
            })();
          },
        },
      });
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  // Listen for model loading failures and show a toast
  useEffect(() => {
    const unlisten = listen<ModelStateEvent>("model-state-changed", (event) => {
      if (event.payload.event_type === "loading_failed") {
        toast.error(
          t("errors.modelLoadFailed", {
            model:
              event.payload.model_name || t("errors.modelLoadFailedUnknown"),
          }),
          {
            description: event.payload.error,
          },
        );
      }
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  const revealMainWindowForPermissions = async () => {
    try {
      await commands.showMainWindowCommand();
    } catch (e) {
      console.warn("Failed to show main window for permission onboarding:", e);
    }
  };

  const checkOnboardingStatus = async () => {
    try {
      const settingsResult = await commands.getAppSettings();
      const hasCompletedOnboarding =
        settingsResult.status === "ok" &&
        settingsResult.data.onboarding_completed === true;
      const currentPlatform = platform();

      if (hasCompletedOnboarding) {
        // Returning user - check if they need to grant permissions first
        setIsReturningUser(true);

        if (currentPlatform === "macos") {
          try {
            const [hasAccessibility, hasMicrophone] = await Promise.all([
              checkAccessibilityPermission(),
              checkMicrophonePermission(),
            ]);
            if (!hasAccessibility || !hasMicrophone) {
              await revealMainWindowForPermissions();
              setOnboardingStep("accessibility");
              return;
            }
          } catch (e) {
            console.warn("Failed to check macOS permissions:", e);
            // If we can't check, proceed to main app and let them fix it there
          }
        }

        if (currentPlatform === "windows") {
          try {
            const microphoneStatus =
              await commands.getWindowsMicrophonePermissionStatus();
            if (
              microphoneStatus.supported &&
              microphoneStatus.overall_access === "denied"
            ) {
              await revealMainWindowForPermissions();
              setOnboardingStep("accessibility");
              return;
            }
          } catch (e) {
            console.warn("Failed to check Windows microphone permissions:", e);
            // If we can't check, proceed to main app and let them fix it there
          }
        }

        setOnboardingStep("done");
      } else {
        // New user - start full onboarding
        setIsReturningUser(false);
        setOnboardingStep("welcome");
      }
    } catch (error) {
      console.error("Failed to check onboarding status:", error);
      setOnboardingStep("welcome");
    }
  };

  const handleAccessibilityComplete = () => {
    // Returning users already have models, skip to main app
    // New users need to select a model
    setOnboardingStep(isReturningUser ? "done" : "shortcut");
  };

  const onboardingProgress = {
    welcome: 1,
    accessibility: 2,
    shortcut: 3,
    model: 4,
  } as const;

  const handleModelSelected = () => {
    // Transition to main app - user has started a download
    setOnboardingStep("done");
  };

  // Rendered once around every step below (including onboarding) so
  // toast.error() calls surface to the user. sonner renders via a portal, so
  // its position in the tree doesn't affect layout. Without this, errors during
  // onboarding (e.g. a model download failing because models.press-say.app is
  // unreachable) are silently swallowed and the wizard just appears to "blink".
  const toaster = (
    <Toaster
      theme="system"
      toastOptions={{
        unstyled: true,
        classNames: {
          toast:
            "bg-background border border-mid-gray/20 rounded-lg shadow-lg px-4 py-3 flex items-center gap-3 text-sm",
          title: "font-medium",
          description: "text-mid-gray",
          actionButton:
            "px-2 py-1 text-xs font-medium rounded-lg border bg-mid-gray/10 border-mid-gray/20 hover:bg-background-ui/30 hover:border-logo-primary cursor-pointer whitespace-nowrap",
        },
      }}
    />
  );

  // Still checking onboarding status
  if (onboardingStep === null) {
    return null;
  }

  // Select the content for the current step. The Toaster is rendered once, in a
  // stable wrapper around this node, so crossing between onboarding steps and
  // the main app never remounts it (which would drop any in-flight toast).
  let content: ReactNode;
  if (onboardingStep === "welcome") {
    content = (
      <WelcomeOnboarding
        onComplete={() => setOnboardingStep("accessibility")}
      />
    );
  } else if (onboardingStep === "accessibility") {
    content = (
      <AccessibilityOnboarding onComplete={handleAccessibilityComplete} />
    );
  } else if (onboardingStep === "shortcut") {
    content = (
      <ShortcutOnboarding onComplete={() => setOnboardingStep("model")} />
    );
  } else if (onboardingStep === "model") {
    content = <Onboarding onModelSelected={handleModelSelected} />;
  } else {
    content = (
      <div dir={direction} className="product-shell select-none cursor-default">
        <ErrorBoundary context="What's New">
          <WhatsNewGate />
        </ErrorBoundary>
        {/* Main content area that takes remaining space */}
        <div className="product-shell-main">
          <Sidebar
            activeSection={currentSection}
            onSectionChange={setCurrentSection}
          />
          {/* Scrollable content area */}
          <main className="product-content">
            <div className="product-scroll-region">
              <div className="product-content-inner">
                <AccessibilityPermissions />
                <SecureInputWarning />
                {renderSettingsContent(currentSection)}
              </div>
            </div>
          </main>
        </div>
        {/* Fixed footer at bottom */}
        <Footer />
      </div>
    );
  }

  return (
    <>
      {toaster}
      {onboardingStep !== "done" ? (
        <OnboardingProgress current={onboardingProgress[onboardingStep]} />
      ) : null}
      {content}
    </>
  );
}

export default App;
