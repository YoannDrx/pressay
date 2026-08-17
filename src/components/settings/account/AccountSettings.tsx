import { useCallback, useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { CheckCircle2, Cloud, RefreshCw, ShieldCheck } from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import {
  commands,
  type CloudAccountSnapshot,
  type CloudAuthConfig,
  type CloudAuthProvider,
} from "@/bindings";
import { Button } from "@/components/ui/Button";
import { SettingsGroup } from "@/components/ui/SettingsGroup";

type CloudAuthEvent = {
  status: "connected" | "failed";
  errorCode: string | null;
};

const EMPTY_ACCOUNT: CloudAccountSnapshot = {
  connected: false,
  accountId: null,
  email: null,
  deviceId: null,
  entitlement: null,
  usage: null,
};

export function AccountSettings() {
  const { t } = useTranslation();
  const [config, setConfig] = useState<CloudAuthConfig | null>(null);
  const [account, setAccount] = useState<CloudAccountSnapshot>(EMPTY_ACCOUNT);
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(true);
  const [pendingAction, setPendingAction] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    const [configResult, accountResult] = await Promise.all([
      commands.getCloudAuthConfig(),
      commands.getCloudAccountSnapshot(),
    ]);
    if (configResult.status === "ok") setConfig(configResult.data);
    if (accountResult.status === "ok") {
      setAccount(accountResult.data);
    } else if (accountResult.error === "cloud_not_connected") {
      setAccount(EMPTY_ACCOUNT);
    } else {
      toast.error(t("cloud.errors.load"));
    }
    setLoading(false);
  }, [t]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    const unlisten = listen<CloudAuthEvent>(
      "cloud-auth-state-changed",
      (event) => {
        setPendingAction(null);
        if (event.payload.status === "connected") {
          toast.success(t("cloud.status.connected"));
          void refresh();
        } else {
          toast.error(t("cloud.errors.auth"));
        }
      },
    );
    return () => {
      void unlisten.then((stop) => stop());
    };
  }, [refresh, t]);

  const requestMagicLink = async () => {
    setPendingAction("magic-link");
    const result = await commands.requestCloudMagicLink(email.trim());
    setPendingAction(null);
    if (result.status === "ok") {
      toast.success(t("cloud.email.sent"));
    } else {
      toast.error(t("cloud.errors.start"));
    }
  };

  const beginSocialLogin = async (provider: CloudAuthProvider) => {
    setPendingAction(provider);
    const result = await commands.beginCloudSocialLogin(provider);
    if (result.status === "error") {
      setPendingAction(null);
      toast.error(t("cloud.errors.start"));
    }
  };

  const disconnect = async () => {
    setPendingAction("disconnect");
    const result = await commands.disconnectCloudAccount();
    setPendingAction(null);
    if (result.status === "ok") {
      setAccount(EMPTY_ACCOUNT);
    } else {
      toast.error(t("cloud.errors.disconnect"));
    }
  };

  const deleteAccount = async () => {
    if (!window.confirm(t("cloud.actions.confirmDelete"))) return;
    setPendingAction("delete");
    const result = await commands.deleteCloudAccount();
    setPendingAction(null);
    if (result.status === "ok") {
      setAccount(EMPTY_ACCOUNT);
    } else {
      toast.error(t("cloud.errors.delete"));
    }
  };

  const providersAvailable =
    config?.magicLink || (config?.providers.length ?? 0) > 0;

  return (
    <div className="max-w-3xl w-full mx-auto space-y-6">
      <div className="px-4 space-y-2">
        <div className="flex items-center gap-2">
          <Cloud className="h-5 w-5 text-accent" />
          <h1 className="text-lg font-medium text-text">{t("cloud.title")}</h1>
        </div>
        <p className="text-sm text-mid-gray">{t("cloud.description")}</p>
        <div className="flex items-start gap-2 rounded-lg border border-accent/20 bg-accent/5 p-3 text-xs text-mid-gray">
          <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
          <span>{t("cloud.privacy")}</span>
        </div>
      </div>

      {account.connected ? (
        <>
          <SettingsGroup title={t("cloud.status.connected")}>
            <div className="flex items-center justify-between gap-4 p-4">
              <div className="min-w-0">
                <div className="flex items-center gap-2 text-sm font-medium text-text">
                  <CheckCircle2 className="h-4 w-4 text-success" />
                  <span className="truncate">
                    {account.email ?? t("cloud.status.offline")}
                  </span>
                </div>
                <p className="mt-1 text-xs text-mid-gray">
                  {account.entitlement?.tier === "pro"
                    ? t("cloud.tier.pro")
                    : t("cloud.tier.free")}
                </p>
              </div>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => void refresh()}
                disabled={loading}
                title={t("cloud.actions.refresh")}
              >
                <RefreshCw
                  className={`h-4 w-4 ${loading ? "animate-spin" : ""}`}
                />
              </Button>
            </div>
          </SettingsGroup>

          {account.usage ? (
            <SettingsGroup title={t("cloud.usage.title")}>
              <div className="grid grid-cols-2 gap-4 p-4 text-sm">
                <div>
                  <p className="text-mid-gray">
                    {t("cloud.usage.transformations")}
                  </p>
                  <p className="mt-1 font-medium text-text">
                    {account.usage.transformations.used} /{" "}
                    {account.usage.transformations.limit}
                  </p>
                </div>
                <div>
                  <p className="text-mid-gray">
                    {t("cloud.usage.transcription")}
                  </p>
                  <p className="mt-1 font-medium text-text">
                    {t("cloud.usage.minutes", {
                      used: Math.ceil(
                        account.usage.transcription.usedSeconds / 60,
                      ),
                      limit: Math.ceil(
                        account.usage.transcription.limitSeconds / 60,
                      ),
                    })}
                  </p>
                </div>
              </div>
            </SettingsGroup>
          ) : null}

          <div className="flex items-center justify-between gap-3 px-4">
            <Button
              variant="secondary"
              onClick={() => void disconnect()}
              disabled={pendingAction !== null}
            >
              {t("cloud.actions.disconnect")}
            </Button>
            <Button
              variant="danger-ghost"
              onClick={() => void deleteAccount()}
              disabled={pendingAction !== null}
            >
              {t("cloud.actions.delete")}
            </Button>
          </div>
        </>
      ) : (
        <SettingsGroup title={t("cloud.status.disconnected")}>
          <div className="space-y-4 p-4">
            {loading ? (
              <p className="text-sm text-mid-gray">
                {t("cloud.actions.loading")}
              </p>
            ) : providersAvailable ? (
              <>
                {config?.magicLink ? (
                  <div className="space-y-2">
                    <label
                      htmlFor="cloud-email"
                      className="text-xs font-medium text-mid-gray"
                    >
                      {t("cloud.email.label")}
                    </label>
                    <div className="flex gap-2">
                      <input
                        id="cloud-email"
                        type="email"
                        autoComplete="email"
                        value={email}
                        onChange={(event) => setEmail(event.target.value)}
                        placeholder={t("cloud.email.placeholder")}
                        className="min-w-0 flex-1 rounded-lg border border-mid-gray/20 bg-background-ui px-3 py-2 text-sm text-text outline-none focus:border-accent"
                      />
                      <Button
                        onClick={() => void requestMagicLink()}
                        disabled={
                          !email.includes("@") || pendingAction !== null
                        }
                      >
                        {t("cloud.email.send")}
                      </Button>
                    </div>
                  </div>
                ) : null}

                {config?.magicLink && config.providers.length > 0 ? (
                  <p className="text-center text-xs text-mid-gray">
                    {t("cloud.providers.or")}
                  </p>
                ) : null}

                <div className="grid grid-cols-2 gap-2">
                  {config?.providers.includes("google") ? (
                    <Button
                      variant="secondary"
                      onClick={() => void beginSocialLogin("google")}
                      disabled={pendingAction !== null}
                    >
                      {t("cloud.providers.google")}
                    </Button>
                  ) : null}
                  {config?.providers.includes("apple") ? (
                    <Button
                      variant="secondary"
                      onClick={() => void beginSocialLogin("apple")}
                      disabled={pendingAction !== null}
                    >
                      {t("cloud.providers.apple")}
                    </Button>
                  ) : null}
                </div>
              </>
            ) : (
              <p className="text-sm text-mid-gray">
                {t("cloud.providers.unavailable")}
              </p>
            )}
          </div>
        </SettingsGroup>
      )}
    </div>
  );
}
