import { useCallback, useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  CheckCircle2,
  Copy,
  KeyRound,
  Laptop,
  LockKeyhole,
  LoaderCircle,
  RefreshCw,
  ShieldCheck,
  ShoppingBag,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import {
  commands,
  type CloudAccountSnapshot,
  type CloudAuthConfig,
  type CloudAuthProvider,
  type CloudSyncSnapshot,
  type StoreKitProduct,
} from "@/bindings";
import { Button } from "@/components/ui/Button";
import { SettingsGroup } from "@/components/ui/SettingsGroup";
import { AppPageHeader } from "@/components/layout";
import { useSettings } from "@/hooks/useSettings";

type CloudAuthEvent = {
  status: "exchanging" | "bootstrapping" | "connected" | "failed";
  errorCode: string | null;
};

type AuthPhase =
  "idle" | "opening" | "waiting" | "exchanging" | "bootstrapping" | "failed";

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
  const { settings } = useSettings();
  const [config, setConfig] = useState<CloudAuthConfig | null>(null);
  const [account, setAccount] = useState<CloudAccountSnapshot>(EMPTY_ACCOUNT);
  const [email, setEmail] = useState("");
  const [sync, setSync] = useState<CloudSyncSnapshot | null>(null);
  const [recoveryInput, setRecoveryInput] = useState("");
  const [generatedRecoveryCode, setGeneratedRecoveryCode] = useState<
    string | null
  >(null);
  const [loading, setLoading] = useState(true);
  const [pendingAction, setPendingAction] = useState<string | null>(null);
  const [authConfigError, setAuthConfigError] = useState<string | null>(null);
  const [authPhase, setAuthPhase] = useState<AuthPhase>("idle");
  const [authErrorCode, setAuthErrorCode] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [storeProducts, setStoreProducts] = useState<StoreKitProduct[]>([]);
  const [storeError, setStoreError] = useState<string | null>(null);

  const refresh = useCallback(
    async (silent = false) => {
      if (!silent) setLoading(true);
      const [configResult, accountResult] = await Promise.all([
        commands.getCloudAuthConfig(),
        commands.getCloudAccountSnapshot(),
      ]);
      if (configResult.status === "ok") {
        setConfig(configResult.data);
        setAuthConfigError(null);
      } else if (!silent) {
        setConfig(null);
        setAuthConfigError(configResult.error);
      }
      if (accountResult.status === "ok") {
        setAccount(accountResult.data);
        setLastRefresh(new Date());
        if (accountResult.data.connected) {
          const syncResult = await commands.getCloudSyncSnapshot();
          if (syncResult.status === "ok") setSync(syncResult.data);
        } else {
          setSync(null);
        }
      } else if (accountResult.error === "cloud_not_connected" && !silent) {
        setAccount(EMPTY_ACCOUNT);
      } else if (!silent) {
        toast.error(t("cloud.errors.load"));
      }
      if (!silent) setLoading(false);
    },
    [t],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!account.connected) {
      setStoreProducts([]);
      return;
    }
    let active = true;
    void commands.getAppStoreProducts().then(async (result) => {
      if (!active || result.status === "error") return;
      setStoreProducts(result.data);
      const reconciliation = await commands.reconcileAppStorePurchases();
      if (!active || reconciliation.status === "error") return;
      setAccount(reconciliation.data);
    });
    return () => {
      active = false;
    };
  }, [account.connected]);

  useEffect(() => {
    const interval = window.setInterval(() => void refresh(true), 30_000);
    const refreshOnFocus = () => void refresh(true);
    window.addEventListener("focus", refreshOnFocus);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener("focus", refreshOnFocus);
    };
  }, [refresh]);

  useEffect(() => {
    const unlisten = listen<CloudAuthEvent>(
      "cloud-auth-state-changed",
      (event) => {
        if (event.payload.status === "exchanging") {
          setAuthPhase("exchanging");
          return;
        }
        if (event.payload.status === "bootstrapping") {
          setAuthPhase("bootstrapping");
          return;
        }
        setPendingAction(null);
        if (event.payload.status === "connected") {
          setAuthPhase("idle");
          setAuthErrorCode(null);
          toast.success(t("cloud.status.connected"));
          void refresh();
        } else {
          setAuthPhase("failed");
          setAuthErrorCode(event.payload.errorCode);
          toast.error(t("cloud.errors.auth"));
        }
      },
    );
    return () => {
      void unlisten.then((stop) => stop());
    };
  }, [refresh, t]);

  useEffect(() => {
    if (
      !["opening", "waiting", "exchanging", "bootstrapping"].includes(authPhase)
    )
      return;
    const timeout = window.setTimeout(
      () => {
        void commands.cancelCloudSocialLogin();
        setPendingAction(null);
        setAuthPhase("failed");
        setAuthErrorCode("cloud_auth_timeout");
        toast.error(t("cloud.errors.auth"));
      },
      15 * 60 * 1000,
    );
    return () => window.clearTimeout(timeout);
  }, [authPhase, t]);

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
    setAuthPhase("opening");
    setAuthErrorCode(null);
    const result = await commands.beginCloudSocialLogin(provider);
    if (result.status === "error") {
      setPendingAction(null);
      setAuthPhase("failed");
      setAuthErrorCode(result.error);
      toast.error(t("cloud.errors.start"));
      return;
    }
    setAuthPhase("waiting");
  };

  const cancelSocialLogin = async () => {
    await commands.cancelCloudSocialLogin();
    setPendingAction(null);
    setAuthPhase("idle");
    setAuthErrorCode(null);
  };

  const disconnect = async () => {
    setPendingAction("disconnect");
    const result = await commands.disconnectCloudAccount();
    setPendingAction(null);
    if (result.status === "ok") {
      setAccount(EMPTY_ACCOUNT);
      setSync(null);
      setRecoveryInput("");
      setGeneratedRecoveryCode(null);
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
      setSync(null);
      setRecoveryInput("");
      setGeneratedRecoveryCode(null);
    } else {
      toast.error(t("cloud.errors.delete"));
    }
  };

  const initializeSync = async () => {
    setSyncError(null);
    setPendingAction("sync-initialize");
    const result = await commands.initializeCloudSync();
    setPendingAction(null);
    if (result.status === "ok") {
      setSync(result.data);
      toast.success(t("cloud.sync.updated"));
    } else {
      setSyncError(result.error);
      toast.error(t("cloud.sync.error"), { description: result.error });
    }
  };

  const approveSyncDevice = async (deviceId: string) => {
    setSyncError(null);
    setPendingAction(`sync-approve-${deviceId}`);
    const result = await commands.approveCloudSyncDevice(deviceId);
    setPendingAction(null);
    if (result.status === "ok") {
      setSync(result.data);
      toast.success(t("cloud.sync.approved"));
    } else {
      setSyncError(result.error);
      toast.error(t("cloud.sync.error"), { description: result.error });
    }
  };

  const runSync = async () => {
    setSyncError(null);
    setPendingAction("sync-run");
    const result = await commands.runCloudSync();
    setPendingAction(null);
    if (result.status === "ok") {
      toast.success(t("cloud.sync.updated"));
      await refresh();
    } else {
      setSyncError(result.error);
      toast.error(t("cloud.sync.error"), { description: result.error });
    }
  };

  const createRecoveryCode = async () => {
    if (!window.confirm(t("cloud.sync.recovery.confirmRotate"))) return;
    setPendingAction("sync-recovery-create");
    const result = await commands.createCloudSyncRecoveryCode();
    setPendingAction(null);
    if (result.status === "ok") {
      setGeneratedRecoveryCode(result.data.code);
      toast.success(t("cloud.sync.recovery.created"));
    } else {
      toast.error(t("cloud.sync.recovery.error"));
    }
  };

  const copyRecoveryCode = async () => {
    if (!generatedRecoveryCode) return;
    try {
      await navigator.clipboard.writeText(generatedRecoveryCode);
      toast.success(t("cloud.sync.recovery.copied"));
    } catch {
      toast.error(t("cloud.sync.recovery.copyError"));
    }
  };

  const recoverSync = async () => {
    setPendingAction("sync-recovery-use");
    const result = await commands.recoverCloudSync(recoveryInput.trim());
    setPendingAction(null);
    if (result.status === "ok") {
      setSync(result.data);
      setRecoveryInput("");
      toast.success(t("cloud.sync.recovery.recovered"));
    } else {
      toast.error(t("cloud.sync.recovery.invalid"));
    }
  };

  const purchaseAppStoreProduct = async (productId: string) => {
    setPendingAction(`store-purchase-${productId}`);
    setStoreError(null);
    const result = await commands.purchaseAppStoreProduct(productId);
    setPendingAction(null);
    if (result.status === "ok") {
      setAccount(result.data);
      toast.success(t("cloud.appStore.purchased"));
    } else if (result.error !== "storekit_cancelled") {
      setStoreError(result.error);
      toast.error(t("cloud.appStore.error"));
    }
  };

  const restoreAppStorePurchases = async () => {
    setPendingAction("store-restore");
    setStoreError(null);
    const result = await commands.restoreAppStorePurchases();
    setPendingAction(null);
    if (result.status === "ok") {
      setAccount(result.data);
      toast.success(t("cloud.appStore.restored"));
    } else {
      setStoreError(result.error);
      toast.error(t("cloud.appStore.error"));
    }
  };

  const providersAvailable =
    config?.magicLink || (config?.providers.length ?? 0) > 0;
  const currentPeriod = new Date().toISOString().slice(0, 7);
  const byokUsage = (settings?.byok_usage ?? []).filter(
    (summary) => summary.periodStart === currentPeriod,
  );
  const byokRequests = byokUsage.reduce(
    (total, summary) => total + summary.requests,
    0,
  );
  const byokTokens = byokUsage.reduce(
    (total, summary) => total + summary.inputTokens + summary.outputTokens,
    0,
  );
  const byokEstimatedCost = byokUsage.reduce(
    (total, summary) => total + (summary.estimatedCostMicrousd ?? 0),
    0,
  );
  const hasByokCostEstimate = byokUsage.some(
    (summary) => summary.estimatedCostMicrousd !== null,
  );

  return (
    <div className="account-page space-y-6">
      <AppPageHeader
        eyebrow={t("cloud.eyebrow")}
        title={t("cloud.title")}
        description={t("cloud.description")}
        aside={
          <div className="flex items-start gap-2 rounded-lg border border-accent/20 bg-accent/5 p-3 text-xs text-mid-gray">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
            <span>{t("cloud.privacy")}</span>
          </div>
        }
      />

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

          {storeProducts.length > 0 ? (
            <SettingsGroup title={t("cloud.appStore.title")}>
              <div className="space-y-3 p-4">
                <div className="flex items-start gap-3">
                  <ShoppingBag className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
                  <p className="text-xs leading-5 text-mid-gray">
                    {t("cloud.appStore.description")}
                  </p>
                </div>
                <div className="grid gap-3 sm:grid-cols-2">
                  {storeProducts.map((product) => (
                    <article
                      key={product.id}
                      className="rounded-xl border border-mid-gray/10 bg-white p-4 shadow-sm dark:bg-white/[0.04]"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <h3 className="text-sm font-medium text-text">
                            {product.displayName}
                          </h3>
                          <p className="mt-1 text-xs leading-5 text-mid-gray">
                            {product.description}
                          </p>
                        </div>
                        <strong className="shrink-0 font-mono text-sm text-text">
                          {product.displayPrice}
                        </strong>
                      </div>
                      <Button
                        className="mt-4 w-full"
                        size="sm"
                        onClick={() => void purchaseAppStoreProduct(product.id)}
                        disabled={pendingAction !== null}
                      >
                        {pendingAction === `store-purchase-${product.id}` ? (
                          <LoaderCircle className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                        ) : null}
                        {t("cloud.appStore.subscribe")}
                      </Button>
                    </article>
                  ))}
                </div>
                <div className="flex items-center justify-between gap-3 border-t border-mid-gray/10 pt-3">
                  <p className="text-[11px] leading-4 text-mid-gray">
                    {t("cloud.appStore.managedByApple")}
                  </p>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => void restoreAppStorePurchases()}
                    disabled={pendingAction !== null}
                  >
                    {t("cloud.appStore.restore")}
                  </Button>
                </div>
                {storeError ? (
                  <div className="rounded-lg border border-danger/20 bg-danger/5 px-3 py-2 text-xs text-danger">
                    {t("cloud.appStore.error")}{" "}
                    <code className="font-mono">{storeError}</code>
                  </div>
                ) : null}
              </div>
            </SettingsGroup>
          ) : null}

          {account.usage ? (
            <SettingsGroup title={t("cloud.usage.title")}>
              <div className="grid grid-cols-2 gap-4 p-4 text-sm">
                <div>
                  <p className="text-mid-gray">
                    {t("cloud.usage.transformations")}
                  </p>
                  <p className="mt-1 font-medium text-text">
                    {account.usage.transformations.used +
                      account.usage.transformations.reserved}{" "}
                    / {account.usage.transformations.limit}
                  </p>
                </div>
                <div>
                  <p className="text-mid-gray">
                    {t("cloud.usage.transcription")}
                  </p>
                  <p className="mt-1 font-medium text-text">
                    {t("cloud.usage.minutes", {
                      used: Math.ceil(
                        (account.usage.transcription.usedSeconds +
                          account.usage.transcription.reservedSeconds) /
                          60,
                      ),
                      limit: Math.ceil(
                        account.usage.transcription.limitSeconds / 60,
                      ),
                    })}
                  </p>
                </div>
              </div>
              <div className="flex items-center justify-between border-t border-mid-gray/10 px-4 py-2 text-[11px] text-mid-gray">
                <span>{account.usage.periodStart}</span>
                {lastRefresh ? (
                  <time dateTime={lastRefresh.toISOString()}>
                    {lastRefresh.toLocaleTimeString([], {
                      hour: "2-digit",
                      minute: "2-digit",
                      second: "2-digit",
                    })}
                  </time>
                ) : null}
              </div>
            </SettingsGroup>
          ) : null}

          {account.entitlement?.tier === "pro" ? (
            <SettingsGroup title={t("cloud.sync.title")}>
              <div className="space-y-3 p-4">
                <div className="flex items-start gap-3">
                  <LockKeyhole className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-text">
                      {sync?.status === "ready"
                        ? t("cloud.sync.ready")
                        : sync?.status === "pending_approval"
                          ? t("cloud.sync.pending")
                          : t("cloud.sync.notConfigured")}
                    </p>
                    <p className="mt-1 text-xs text-mid-gray">
                      {t("cloud.sync.privacy")}
                    </p>
                  </div>
                  {sync?.status !== "ready" ? (
                    <Button
                      size="sm"
                      onClick={() => void initializeSync()}
                      disabled={pendingAction !== null}
                    >
                      {t("cloud.sync.enable")}
                    </Button>
                  ) : (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => void runSync()}
                      disabled={pendingAction !== null}
                    >
                      {t("cloud.sync.syncNow")}
                    </Button>
                  )}
                </div>

                {syncError ? (
                  <div className="rounded-lg border border-danger/20 bg-danger/5 px-3 py-2 text-xs text-danger">
                    <span>{t("cloud.sync.error")}</span>{" "}
                    <code className="font-mono">{syncError}</code>
                  </div>
                ) : null}

                {sync?.status === "ready" && sync.devices.length > 0 ? (
                  <div className="space-y-2 border-t border-mid-gray/10 pt-3">
                    {sync.devices.map((device) => (
                      <div
                        key={device.id}
                        className="flex items-center justify-between gap-3 rounded-lg border border-mid-gray/10 px-3 py-2"
                      >
                        <div className="flex min-w-0 items-center gap-2">
                          <Laptop className="h-4 w-4 shrink-0 text-mid-gray" />
                          <span className="truncate text-sm text-text">
                            {device.displayName}
                            {device.current ? (
                              <span className="ml-1 text-mid-gray">
                                {t("cloud.sync.current")}
                              </span>
                            ) : null}
                          </span>
                        </div>
                        {device.status === "pending_approval" ? (
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => void approveSyncDevice(device.id)}
                            disabled={pendingAction !== null}
                          >
                            {t("cloud.sync.approve")}
                          </Button>
                        ) : (
                          <span className="text-xs text-success">
                            {t("cloud.sync.approvedStatus")}
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                ) : null}

                {sync?.status === "pending_approval" ? (
                  <div className="space-y-3 border-t border-mid-gray/10 pt-3">
                    <div className="flex items-start gap-2">
                      <KeyRound className="mt-0.5 h-4 w-4 shrink-0 text-mid-gray" />
                      <p className="text-xs text-mid-gray">
                        {t("cloud.sync.recovery.useDescription")}
                      </p>
                    </div>
                    <input
                      type="text"
                      value={recoveryInput}
                      onChange={(event) => setRecoveryInput(event.target.value)}
                      placeholder={t("cloud.sync.recovery.placeholder")}
                      autoCapitalize="none"
                      autoCorrect="off"
                      spellCheck={false}
                      className="signal-input is-default font-mono text-xs"
                    />
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => void recoverSync()}
                      disabled={
                        recoveryInput.trim().length < 40 ||
                        pendingAction !== null
                      }
                    >
                      {t("cloud.sync.recovery.use")}
                    </Button>
                  </div>
                ) : null}

                {sync?.status === "ready" ? (
                  <div className="space-y-3 border-t border-mid-gray/10 pt-3">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-xs font-medium text-text">
                          {t("cloud.sync.recovery.title")}
                        </p>
                        <p className="mt-1 text-xs text-mid-gray">
                          {t("cloud.sync.recovery.description")}
                        </p>
                      </div>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => void createRecoveryCode()}
                        disabled={pendingAction !== null}
                      >
                        {t("cloud.sync.recovery.create")}
                      </Button>
                    </div>
                    {generatedRecoveryCode ? (
                      <div className="space-y-2 rounded-lg border border-accent/20 bg-accent/5 p-3">
                        <p className="text-xs font-medium text-text">
                          {t("cloud.sync.recovery.saveNow")}
                        </p>
                        <code className="block select-all break-all font-mono text-xs leading-5 text-text">
                          {generatedRecoveryCode}
                        </code>
                        <div className="flex gap-2">
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => void copyRecoveryCode()}
                          >
                            <Copy className="mr-1.5 h-3.5 w-3.5" />
                            {t("cloud.sync.recovery.copy")}
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setGeneratedRecoveryCode(null)}
                          >
                            {t("cloud.sync.recovery.done")}
                          </Button>
                        </div>
                      </div>
                    ) : null}
                  </div>
                ) : null}
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
            {authPhase !== "idle" ? (
              <div
                className={`cloud-auth-progress is-${authPhase}`}
                role="status"
              >
                {authPhase === "failed" ? (
                  <ShieldCheck size={18} aria-hidden="true" />
                ) : (
                  <LoaderCircle
                    className="animate-spin"
                    size={18}
                    aria-hidden="true"
                  />
                )}
                <div>
                  <strong>
                    {authPhase === "failed"
                      ? t("cloud.errors.auth")
                      : t("cloud.actions.loading")}
                  </strong>
                  <p>
                    {authPhase === "failed"
                      ? t("cloud.errors.detail")
                      : t("cloud.privacy")}
                  </p>
                  {authErrorCode ? <code>{authErrorCode}</code> : null}
                </div>
                {authPhase === "failed" ? (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => {
                      setAuthPhase("idle");
                      setAuthErrorCode(null);
                    }}
                  >
                    {t("cloud.actions.retry")}
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => void cancelSocialLogin()}
                  >
                    {t("common.cancel")}
                  </Button>
                )}
              </div>
            ) : null}
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
                        className="signal-input is-default min-w-0 flex-1"
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

                <div
                  className={`grid gap-2 ${config && config.providers.length > 1 ? "grid-cols-2" : "grid-cols-1"}`}
                >
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
              <div className="account-unavailable">
                <div className="account-unavailable-icon">
                  <ShieldCheck size={18} aria-hidden="true" />
                </div>
                <div>
                  <p className="text-sm font-medium text-text">
                    {t("cloud.providers.unavailableTitle")}
                  </p>
                  <p className="mt-1 text-xs text-mid-gray">
                    {t("cloud.providers.unavailable")}
                  </p>
                  <code>
                    {authConfigError ?? "cloud_auth_provider_not_configured"}
                  </code>
                </div>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => void refresh()}
                  disabled={loading}
                >
                  <RefreshCw
                    className={`h-3.5 w-3.5 ${loading ? "animate-spin" : ""}`}
                  />
                  {t("cloud.actions.retry")}
                </Button>
              </div>
            )}
          </div>
        </SettingsGroup>
      )}

      <SettingsGroup title={t("cloud.usage.byok.title")}>
        <div className="space-y-4 p-4">
          <p className="text-xs leading-5 text-mid-gray">
            {t("cloud.usage.byok.description")}
          </p>
          {byokUsage.length > 0 ? (
            <>
              <div className="grid grid-cols-3 gap-3">
                <div className="rounded-lg border border-mid-gray/10 bg-white/70 p-3 dark:bg-white/[0.04]">
                  <p className="text-[11px] text-mid-gray">
                    {t("cloud.usage.byok.requests")}
                  </p>
                  <strong className="mt-1 block text-sm text-text">
                    {byokRequests.toLocaleString()}
                  </strong>
                </div>
                <div className="rounded-lg border border-mid-gray/10 bg-white/70 p-3 dark:bg-white/[0.04]">
                  <p className="text-[11px] text-mid-gray">
                    {t("cloud.usage.byok.tokens")}
                  </p>
                  <strong className="mt-1 block text-sm text-text">
                    {byokTokens.toLocaleString()}
                  </strong>
                </div>
                <div className="rounded-lg border border-mid-gray/10 bg-white/70 p-3 dark:bg-white/[0.04]">
                  <p className="text-[11px] text-mid-gray">
                    {t("cloud.usage.byok.estimatedCost")}
                  </p>
                  <strong className="mt-1 block text-sm text-text">
                    {hasByokCostEstimate
                      ? (byokEstimatedCost / 1_000_000).toLocaleString(
                          undefined,
                          {
                            style: "currency",
                            currency: "USD",
                            minimumFractionDigits: 2,
                            maximumFractionDigits: 4,
                          },
                        )
                      : "—"}
                  </strong>
                </div>
              </div>
              <div className="space-y-2 border-t border-mid-gray/10 pt-3">
                {byokUsage.map((summary) => (
                  <div
                    key={`${summary.providerId}:${summary.model}`}
                    className="flex items-center justify-between gap-3 text-xs"
                  >
                    <span className="truncate text-text">
                      {summary.providerId} · {summary.model}
                    </span>
                    <span className="shrink-0 font-mono text-mid-gray">
                      {(
                        summary.inputTokens + summary.outputTokens
                      ).toLocaleString()}
                    </span>
                  </div>
                ))}
              </div>
            </>
          ) : (
            <p className="rounded-lg border border-dashed border-mid-gray/15 px-3 py-4 text-center text-xs text-mid-gray">
              {t("cloud.usage.byok.empty")}
            </p>
          )}
          <p className="text-[10px] leading-4 text-mid-gray">
            {t("cloud.usage.byok.disclaimer")}
          </p>
        </div>
      </SettingsGroup>
    </div>
  );
}
