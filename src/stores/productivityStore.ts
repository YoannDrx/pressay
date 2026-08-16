import { create } from "zustand";
import {
  commands,
  type AppProfile,
  type DictionaryEntry,
  type PressayMode,
  type ProductivityConfig,
} from "@/bindings";

interface ProductivityStore {
  config: ProductivityConfig | null;
  loading: boolean;
  saving: boolean;
  error: string | null;
  initialize: () => Promise<void>;
  refresh: () => Promise<void>;
  setActiveMode: (modeId: string) => Promise<boolean>;
  saveMode: (mode: PressayMode) => Promise<boolean>;
  deleteMode: (modeId: string) => Promise<boolean>;
  replaceDictionary: (entries: DictionaryEntry[]) => Promise<boolean>;
  saveProfile: (profile: AppProfile) => Promise<boolean>;
  deleteProfile: (profileId: string) => Promise<boolean>;
}

const resultError = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

export const useProductivityStore = create<ProductivityStore>((set, get) => {
  const runMutation = async (
    mutation: () => Promise<
      { status: "ok"; data: null } | { status: "error"; error: string }
    >,
  ): Promise<boolean> => {
    set({ saving: true, error: null });
    try {
      const result = await mutation();
      if (result.status === "error") {
        set({ error: result.error });
        return false;
      }
      await get().refresh();
      return true;
    } catch (error) {
      set({ error: resultError(error) });
      return false;
    } finally {
      set({ saving: false });
    }
  };

  return {
    config: null,
    loading: false,
    saving: false,
    error: null,

    initialize: async () => {
      if (get().config || get().loading) return;
      await get().refresh();
    },

    refresh: async () => {
      set({ loading: true, error: null });
      try {
        const config = await commands.getProductivityConfig();
        set({ config });
      } catch (error) {
        set({ error: resultError(error) });
      } finally {
        set({ loading: false });
      }
    },

    setActiveMode: (modeId) =>
      runMutation(() => commands.setActivePressayMode(modeId)),
    saveMode: (mode) => runMutation(() => commands.upsertPressayMode(mode)),
    deleteMode: (modeId) =>
      runMutation(() => commands.deletePressayMode(modeId)),
    replaceDictionary: (entries) =>
      runMutation(() => commands.replaceDictionaryEntries(entries)),
    saveProfile: (profile) =>
      runMutation(() => commands.upsertAppProfile(profile)),
    deleteProfile: (profileId) =>
      runMutation(() => commands.deleteAppProfile(profileId)),
  };
});
