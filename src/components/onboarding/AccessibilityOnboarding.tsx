import { useEffect, useState, useCallback, useRef } from "react";
import { useTranslation } from "react-i18next";
import { platform } from "@tauri-apps/plugin-os";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
  checkAccessibilityPermission,
  requestAccessibilityPermission,
  checkMicrophonePermission,
  requestMicrophonePermission,
} from "tauri-plugin-macos-permissions-api";
import { toast } from "sonner";
import { commands } from "@/bindings";
import { useSettingsStore } from "@/stores/settingsStore";
import PressayMark from "../icons/PressayMark";
import { Keyboard, Mic, Check, Loader2 } from "lucide-react";

const MACOS_ACCESSIBILITY_SETTINGS_URL =
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";

interface AccessibilityOnboardingProps {
  onComplete: () => void;
}

type PermissionStatus = "checking" | "needed" | "waiting" | "granted";
type PermissionPlatform = "macos" | "windows" | "other";

interface PermissionsState {
  accessibility: PermissionStatus;
  microphone: PermissionStatus;
}

const AccessibilityOnboarding: React.FC<AccessibilityOnboardingProps> = ({
  onComplete,
}) => {
  const { t } = useTranslation();
  const refreshAudioDevices = useSettingsStore(
    (state) => state.refreshAudioDevices,
  );
  const refreshOutputDevices = useSettingsStore(
    (state) => state.refreshOutputDevices,
  );
  const [permissionPlatform, setPermissionPlatform] =
    useState<PermissionPlatform | null>(null);
  const [permissions, setPermissions] = useState<PermissionsState>({
    accessibility: "checking",
    microphone: "checking",
  });
  const pollingRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const errorCountRef = useRef<number>(0);
  const completionStartedRef = useRef(false);
  const MAX_POLLING_ERRORS = 3;
  const MAX_PERMISSION_WAIT_MS = 60_000;

  const isMacOS = permissionPlatform === "macos";
  const isWindows = permissionPlatform === "windows";
  const showMicrophonePermission = isMacOS || isWindows;
  const showAccessibilityPermission = isMacOS;

  const allGranted = isMacOS
    ? permissions.accessibility === "granted" &&
      permissions.microphone === "granted"
    : isWindows
      ? permissions.microphone === "granted"
      : true;

  const completeOnboarding = useCallback(async () => {
    if (completionStartedRef.current) return;
    completionStartedRef.current = true;

    await Promise.all([refreshAudioDevices(), refreshOutputDevices()]);
    timeoutRef.current = setTimeout(() => onComplete(), 300);
  }, [onComplete, refreshAudioDevices, refreshOutputDevices]);

  const refreshMacOSPermissions = useCallback(async () => {
    const [accessibilityGranted, microphoneGranted] = await Promise.all([
      checkAccessibilityPermission(),
      checkMicrophonePermission(),
    ]);

    if (accessibilityGranted) {
      try {
        await Promise.all([
          commands.initializeEnigo(),
          commands.initializeShortcuts(),
        ]);
      } catch (error) {
        console.warn("Failed to initialize after permission grant:", error);
      }
    }

    setPermissions({
      accessibility: accessibilityGranted ? "granted" : "needed",
      microphone: microphoneGranted ? "granted" : "needed",
    });

    if (accessibilityGranted && microphoneGranted) {
      await completeOnboarding();
    }

    return { accessibilityGranted, microphoneGranted };
  }, [completeOnboarding]);

  const hasWindowsMicrophoneAccess = useCallback(async (): Promise<boolean> => {
    const microphoneStatus =
      await commands.getWindowsMicrophonePermissionStatus();

    if (!microphoneStatus.supported) {
      return true;
    }

    return microphoneStatus.overall_access !== "denied";
  }, []);

  // Check platform and permission status on mount
  useEffect(() => {
    const currentPlatform = platform();
    const nextPlatform: PermissionPlatform =
      currentPlatform === "macos"
        ? "macos"
        : currentPlatform === "windows"
          ? "windows"
          : "other";

    setPermissionPlatform(nextPlatform);

    // Skip immediately on unsupported platforms
    if (nextPlatform === "other") {
      onComplete();
      return;
    }

    const checkInitial = async () => {
      if (nextPlatform === "macos") {
        try {
          await refreshMacOSPermissions();
        } catch (error) {
          console.error("Failed to check macOS permissions:", error);
          toast.error(t("onboarding.permissions.errors.checkFailed"));
          setPermissions({
            accessibility: "needed",
            microphone: "needed",
          });
        }

        return;
      }

      try {
        const microphoneGranted = await hasWindowsMicrophoneAccess();

        setPermissions({
          accessibility: "granted",
          microphone: microphoneGranted ? "granted" : "needed",
        });

        if (microphoneGranted) {
          await completeOnboarding();
        }
      } catch (error) {
        console.warn("Failed to check Windows microphone permissions:", error);
        setPermissions({
          accessibility: "granted",
          microphone: "granted",
        });
        await completeOnboarding();
      }
    };

    checkInitial();
  }, [
    completeOnboarding,
    hasWindowsMicrophoneAccess,
    onComplete,
    refreshMacOSPermissions,
    t,
  ]);

  // macOS does not notify the webview when a privacy setting changes. Recheck
  // as soon as the user returns from System Settings, even if polling timed out.
  useEffect(() => {
    if (!isMacOS) return;

    const handleWindowFocus = () => {
      refreshMacOSPermissions().catch((error) => {
        console.warn("Failed to recheck macOS permissions on focus:", error);
      });
    };

    window.addEventListener("focus", handleWindowFocus);
    return () => window.removeEventListener("focus", handleWindowFocus);
  }, [isMacOS, refreshMacOSPermissions]);

  // Polling for permissions after user clicks a button
  const startPolling = useCallback(() => {
    if (pollingRef.current || permissionPlatform === null) return;

    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }
    timeoutRef.current = setTimeout(() => {
      if (pollingRef.current) {
        clearInterval(pollingRef.current);
        pollingRef.current = null;
      }
      setPermissions((current) => ({
        accessibility:
          current.accessibility === "waiting"
            ? "needed"
            : current.accessibility,
        microphone:
          current.microphone === "waiting" ? "needed" : current.microphone,
      }));
      toast.error(t("onboarding.permissions.errors.checkFailed"));
    }, MAX_PERMISSION_WAIT_MS);

    pollingRef.current = setInterval(async () => {
      try {
        if (permissionPlatform === "windows") {
          const microphoneGranted = await hasWindowsMicrophoneAccess();

          if (microphoneGranted) {
            setPermissions((prev) => ({ ...prev, microphone: "granted" }));

            if (pollingRef.current) {
              clearInterval(pollingRef.current);
              pollingRef.current = null;
            }
            if (timeoutRef.current) {
              clearTimeout(timeoutRef.current);
              timeoutRef.current = null;
            }

            await completeOnboarding();
          }

          errorCountRef.current = 0;
          return;
        }

        const [accessibilityGranted, microphoneGranted] = await Promise.all([
          checkAccessibilityPermission(),
          checkMicrophonePermission(),
        ]);

        setPermissions((prev) => {
          const newState = { ...prev };

          if (accessibilityGranted && prev.accessibility !== "granted") {
            newState.accessibility = "granted";
            // Initialize Enigo and shortcuts when accessibility is granted
            Promise.all([
              commands.initializeEnigo(),
              commands.initializeShortcuts(),
            ]).catch((e) => {
              console.warn("Failed to initialize after permission grant:", e);
            });
          }

          if (microphoneGranted && prev.microphone !== "granted") {
            newState.microphone = "granted";
          }

          return newState;
        });

        // If both granted, stop polling, refresh audio devices, and proceed
        if (accessibilityGranted && microphoneGranted) {
          if (pollingRef.current) {
            clearInterval(pollingRef.current);
            pollingRef.current = null;
          }
          if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
            timeoutRef.current = null;
          }
          await completeOnboarding();
        }

        // Reset error count on success
        errorCountRef.current = 0;
      } catch (error) {
        console.error("Error checking permissions:", error);
        errorCountRef.current += 1;

        if (errorCountRef.current >= MAX_POLLING_ERRORS) {
          // Stop polling after too many consecutive errors
          if (pollingRef.current) {
            clearInterval(pollingRef.current);
            pollingRef.current = null;
          }
          if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
            timeoutRef.current = null;
          }
          toast.error(t("onboarding.permissions.errors.checkFailed"));
        }
      }
    }, 1000);
  }, [completeOnboarding, hasWindowsMicrophoneAccess, permissionPlatform, t]);

  // Cleanup polling and timeouts on unmount
  useEffect(() => {
    return () => {
      if (pollingRef.current) {
        clearInterval(pollingRef.current);
      }
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const handleGrantAccessibility = async () => {
    try {
      await requestAccessibilityPermission();
      setPermissions((prev) => ({ ...prev, accessibility: "waiting" }));
      startPolling();

      // AXIsProcessTrustedWithOptions only presents its explanatory prompt the
      // first time. Opening the pane explicitly also repairs denied or stale
      // entries and keeps repeat attempts actionable.
      await openUrl(MACOS_ACCESSIBILITY_SETTINGS_URL);
    } catch (error) {
      console.error("Failed to request accessibility permission:", error);
      toast.error(t("onboarding.permissions.errors.requestFailed"));
    }
  };

  const handleGrantMicrophone = async () => {
    try {
      if (isWindows) {
        await commands.openMicrophonePrivacySettings();
      } else {
        await requestMicrophonePermission();
      }

      setPermissions((prev) => ({ ...prev, microphone: "waiting" }));
      startPolling();
    } catch (error) {
      console.error("Failed to request microphone permission:", error);
      toast.error(t("onboarding.permissions.errors.requestFailed"));
    }
  };

  const isChecking =
    permissionPlatform === null ||
    (isMacOS &&
      permissions.accessibility === "checking" &&
      permissions.microphone === "checking") ||
    (isWindows && permissions.microphone === "checking");

  // Still checking platform/initial permissions
  if (isChecking) {
    return (
      <div className="onboarding-screen">
        <Loader2 className="onboarding-loader" />
      </div>
    );
  }

  // All permissions granted - show success briefly
  if (allGranted) {
    return (
      <div className="onboarding-screen">
        <div className="onboarding-panel permission-success-panel">
          <div className="permission-success-icon">
            <Check size={28} />
          </div>
          <h2>{t("onboarding.permissions.allGranted")}</h2>
        </div>
      </div>
    );
  }

  // Show permissions request screen
  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel permission-panel">
        <div className="onboarding-brand-lockup">
          <PressayMark size={34} />
          {/* Brand name is intentionally not translated. */}
          {/* eslint-disable-next-line i18next/no-literal-string */}
          <span>Pressay</span>
        </div>
        <div className="onboarding-heading">
          <p className="product-eyebrow">{t("signalOs.onboarding.progress")}</p>
          <h1>{t("onboarding.permissions.title")}</h1>
          <p>{t("onboarding.permissions.description")}</p>
        </div>

        <div className="permission-stack">
          {/* Microphone Permission Card */}
          {showMicrophonePermission && (
            <div className={`permission-row is-${permissions.microphone}`}>
              <div className="permission-row-icon">
                <Mic size={20} />
              </div>
              <div className="permission-row-copy">
                <h3>{t("onboarding.permissions.microphone.title")}</h3>
                <p>{t("onboarding.permissions.microphone.description")}</p>
              </div>
              {permissions.microphone === "granted" ? (
                <span className="permission-granted">
                  <Check size={15} />
                  {t("onboarding.permissions.granted")}
                </span>
              ) : permissions.microphone === "waiting" ? (
                <span className="permission-waiting">
                  <Loader2 size={15} />
                  {t("onboarding.permissions.waiting")}
                </span>
              ) : (
                <button
                  onClick={handleGrantMicrophone}
                  className="permission-action"
                >
                  {isWindows
                    ? t("accessibility.openSettings")
                    : t("onboarding.permissions.grant")}
                </button>
              )}
            </div>
          )}

          {/* Accessibility Permission Card */}
          {showAccessibilityPermission && (
            <div className={`permission-row is-${permissions.accessibility}`}>
              <div className="permission-row-icon">
                <Keyboard size={20} />
              </div>
              <div className="permission-row-copy">
                <h3>{t("onboarding.permissions.accessibility.title")}</h3>
                <p>{t("onboarding.permissions.accessibility.description")}</p>
              </div>
              {permissions.accessibility === "granted" ? (
                <span className="permission-granted">
                  <Check size={15} />
                  {t("onboarding.permissions.granted")}
                </span>
              ) : permissions.accessibility === "waiting" ? (
                <button
                  onClick={handleGrantAccessibility}
                  className="permission-action is-secondary"
                >
                  <Loader2 size={15} />
                  {t("accessibility.openSettings")}
                </button>
              ) : (
                <button
                  onClick={handleGrantAccessibility}
                  className="permission-action"
                >
                  {t("onboarding.permissions.grant")}
                </button>
              )}
            </div>
          )}
        </div>
        <p className="onboarding-footnote permission-footnote">
          {t("accessibility.permissionsDescription")}
        </p>
      </div>
    </div>
  );
};

export default AccessibilityOnboarding;
