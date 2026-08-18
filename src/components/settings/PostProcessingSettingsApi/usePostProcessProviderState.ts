import { useCallback, useEffect, useMemo, useState } from "react";
import { useSettings } from "../../../hooks/useSettings";
import { commands, type PostProcessProvider } from "@/bindings";
import type { ModelOption } from "./types";
import type { DropdownOption } from "../../ui/Dropdown";
import { useTranslation } from "react-i18next";
import {
  isRecommendedProviderModel,
  providerModelLabel,
} from "@/lib/providerModels";

type PostProcessProviderState = {
  providerOptions: DropdownOption[];
  selectedProviderId: string;
  selectedProvider: PostProcessProvider | undefined;
  isCustomProvider: boolean;
  isAppleProvider: boolean;
  appleIntelligenceUnavailable: boolean;
  baseUrl: string;
  handleBaseUrlChange: (value: string) => void;
  isBaseUrlUpdating: boolean;
  apiKey: string;
  apiKeyConfigured: boolean;
  providerConnectionStatus:
    "not_configured" | "stored" | "checking" | "valid" | "error";
  providerConnectionError?: string;
  isProviderReady: boolean;
  handleApiKeyChange: (value: string) => void;
  handleApiKeyRemove: () => void;
  isApiKeyUpdating: boolean;
  model: string;
  handleModelChange: (value: string) => void;
  modelOptions: ModelOption[];
  isModelUpdating: boolean;
  isFetchingModels: boolean;
  handleProviderSelect: (providerId: string) => void;
  handleModelSelect: (value: string) => void;
  handleModelCreate: (value: string) => void;
  handleRefreshModels: () => void;
};

const APPLE_PROVIDER_ID = "apple_intelligence";

export const usePostProcessProviderState = (): PostProcessProviderState => {
  const { t } = useTranslation();
  const {
    settings,
    isUpdating,
    setPostProcessProvider,
    updatePostProcessBaseUrl,
    updatePostProcessApiKey,
    updatePostProcessModel,
    fetchPostProcessModels,
    postProcessModelOptions,
    postProcessProviderConnections,
  } = useSettings();

  // Settings are guaranteed to have providers after migration
  const providers = settings?.post_process_providers || [];

  const selectedProviderId = useMemo(() => {
    return settings?.post_process_provider_id || providers[0]?.id || "openai";
  }, [providers, settings?.post_process_provider_id]);

  const selectedProvider = useMemo(() => {
    return (
      providers.find((provider) => provider.id === selectedProviderId) ||
      providers[0]
    );
  }, [providers, selectedProviderId]);

  const isAppleProvider = selectedProvider?.id === APPLE_PROVIDER_ID;
  const isCustomProvider = selectedProvider?.id === "custom";
  const [appleIntelligenceUnavailable, setAppleIntelligenceUnavailable] =
    useState(false);

  // Use settings directly as single source of truth
  const baseUrl = selectedProvider?.base_url ?? "";
  // Secret values never leave the Rust process. The input is intentionally
  // blank and this boolean only controls configured-state UI.
  const apiKey = "";
  const apiKeyConfigured =
    settings?.post_process_api_keys_configured?.[selectedProviderId] ?? false;
  const model = settings?.post_process_models?.[selectedProviderId] ?? "";
  const providerConnection = postProcessProviderConnections[selectedProviderId];
  const hasConnectionConfiguration = isCustomProvider
    ? Boolean(baseUrl.trim())
    : apiKeyConfigured;
  const providerConnectionStatus = isAppleProvider
    ? "valid"
    : (providerConnection?.status ??
      (hasConnectionConfiguration ? "stored" : "not_configured"));
  const providerConnectionError = providerConnection?.error;
  const isProviderReady =
    providerConnectionStatus === "valid" && Boolean(model.trim());

  const providerOptions = useMemo<DropdownOption[]>(() => {
    return providers.map((provider) => ({
      value: provider.id,
      label: provider.label,
    }));
  }, [providers]);

  const handleProviderSelect = useCallback(
    async (providerId: string) => {
      // Clear error state on any selection attempt (allows dismissing the error)
      setAppleIntelligenceUnavailable(false);

      if (providerId === selectedProviderId) return;

      // Check Apple Intelligence availability before selecting
      if (providerId === APPLE_PROVIDER_ID) {
        const available = await commands.checkAppleIntelligenceAvailable();
        if (!available) {
          setAppleIntelligenceUnavailable(true);
          // Don't return - still set the provider so dropdown shows the selection
          // The backend gracefully handles unavailable Apple Intelligence
        }
      }

      await setPostProcessProvider(providerId);

      // Auto-fetch available models for the new provider so the model dropdown
      // reflects what's actually valid. Without this, a stale model value from
      // a previous provider/base_url can persist and silently 404 at runtime.
      // Skip when the provider isn't configured yet (no API key / empty base URL)
      // to avoid unnecessary backend errors.
      if (providerId !== APPLE_PROVIDER_ID) {
        const provider = providers.find((p) => p.id === providerId);
        const hasApiKey =
          settings?.post_process_api_keys_configured?.[providerId] ?? false;
        const hasBaseUrl = (provider?.base_url ?? "").trim() !== "";

        if (provider?.id === "custom" ? hasBaseUrl : hasApiKey) {
          void fetchPostProcessModels(providerId);
        }
      }
    },
    [
      selectedProviderId,
      setPostProcessProvider,
      fetchPostProcessModels,
      providers,
      settings,
    ],
  );

  const handleBaseUrlChange = useCallback(
    async (value: string) => {
      if (!selectedProvider || selectedProvider.id !== "custom") {
        return;
      }
      const trimmed = value.trim();
      if (trimmed && trimmed !== baseUrl) {
        await updatePostProcessBaseUrl(selectedProvider.id, trimmed);
        await fetchPostProcessModels(selectedProvider.id);
      }
    },
    [
      selectedProvider,
      baseUrl,
      updatePostProcessBaseUrl,
      fetchPostProcessModels,
    ],
  );

  const handleApiKeyChange = useCallback(
    async (value: string) => {
      const trimmed = value.trim();
      if (trimmed) {
        await updatePostProcessApiKey(selectedProviderId, trimmed);
      }
    },
    [selectedProviderId, updatePostProcessApiKey],
  );

  const handleApiKeyRemove = useCallback(() => {
    if (apiKeyConfigured) {
      void updatePostProcessApiKey(selectedProviderId, "");
    }
  }, [apiKeyConfigured, selectedProviderId, updatePostProcessApiKey]);

  const handleModelChange = useCallback(
    (value: string) => {
      const trimmed = value.trim();
      if (trimmed !== model) {
        void updatePostProcessModel(selectedProviderId, trimmed);
      }
    },
    [model, selectedProviderId, updatePostProcessModel],
  );

  const handleModelSelect = useCallback(
    (value: string) => {
      void updatePostProcessModel(selectedProviderId, value.trim());
    },
    [selectedProviderId, updatePostProcessModel],
  );

  const handleModelCreate = useCallback(
    (value: string) => {
      void updatePostProcessModel(selectedProviderId, value);
    },
    [selectedProviderId, updatePostProcessModel],
  );

  const handleRefreshModels = useCallback(() => {
    if (isAppleProvider) return;
    void fetchPostProcessModels(selectedProviderId);
  }, [fetchPostProcessModels, isAppleProvider, selectedProviderId]);

  const availableModelsRaw = postProcessModelOptions[selectedProviderId] || [];

  const modelOptions = useMemo<ModelOption[]>(() => {
    const seen = new Set<string>();
    const options: ModelOption[] = [];

    const upsert = (value: string | null | undefined) => {
      const trimmed = value?.trim();
      if (!trimmed || seen.has(trimmed)) return;
      seen.add(trimmed);
      const label = providerModelLabel(selectedProviderId, trimmed);
      options.push({
        value: trimmed,
        label: isRecommendedProviderModel(selectedProviderId, trimmed)
          ? `${label} · ${t("onboarding.recommended")}`
          : label,
      });
    };

    // Add available models from API
    for (const candidate of availableModelsRaw) {
      upsert(candidate);
    }

    // Ensure current model is in the list
    upsert(model);

    return options;
  }, [availableModelsRaw, model, selectedProviderId, t]);

  const isBaseUrlUpdating = isUpdating(
    `post_process_base_url:${selectedProviderId}`,
  );
  const isApiKeyUpdating = isUpdating(
    `post_process_api_key:${selectedProviderId}`,
  );
  const isModelUpdating = isUpdating(
    `post_process_model:${selectedProviderId}`,
  );
  const isFetchingModels = isUpdating(
    `post_process_models_fetch:${selectedProviderId}`,
  );

  useEffect(() => {
    if (
      isAppleProvider ||
      !hasConnectionConfiguration ||
      providerConnection ||
      isFetchingModels
    ) {
      return;
    }
    void fetchPostProcessModels(selectedProviderId);
  }, [
    fetchPostProcessModels,
    hasConnectionConfiguration,
    isAppleProvider,
    isFetchingModels,
    providerConnection,
    selectedProviderId,
  ]);

  return {
    providerOptions,
    selectedProviderId,
    selectedProvider,
    isCustomProvider,
    isAppleProvider,
    appleIntelligenceUnavailable,
    baseUrl,
    handleBaseUrlChange,
    isBaseUrlUpdating,
    apiKey,
    apiKeyConfigured,
    providerConnectionStatus,
    providerConnectionError,
    isProviderReady,
    handleApiKeyChange,
    handleApiKeyRemove,
    isApiKeyUpdating,
    model,
    handleModelChange,
    modelOptions,
    isModelUpdating,
    isFetchingModels,
    handleProviderSelect,
    handleModelSelect,
    handleModelCreate,
    handleRefreshModels,
  };
};
