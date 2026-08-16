import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { BookOpen, Plus, Search, Trash2 } from "lucide-react";
import type {
  DictionaryEntry,
  DictionaryMatchKind,
  ProductivityConfig,
} from "@/bindings";
import { useProductivityStore } from "@/stores/productivityStore";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import { Select } from "@/components/ui/Select";
import { ProductivityPage } from "./ProductivityPage";

const blankEntry = (): DictionaryEntry => ({
  id: `term_${Date.now()}`,
  term: "",
  variants: [],
  replacement: null,
  match_kind: "exact",
  language: null,
  enabled: true,
});

interface DictionarySettingsViewProps {
  config: ProductivityConfig;
  saving?: boolean;
  error?: string | null;
  onReplace: (entries: DictionaryEntry[]) => Promise<boolean> | boolean;
}

export const DictionarySettingsView = ({
  config,
  saving = false,
  error,
  onReplace,
}: DictionarySettingsViewProps) => {
  const { t } = useTranslation();
  const [draft, setDraft] = useState<DictionaryEntry>(blankEntry);
  const [variants, setVariants] = useState("");
  const [query, setQuery] = useState("");
  const [showForm, setShowForm] = useState(false);

  const filteredEntries = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase();
    return config.dictionary.filter((entry) => {
      const haystack = [
        entry.term,
        entry.replacement,
        ...(entry.variants ?? []),
      ]
        .filter(Boolean)
        .join(" ")
        .toLocaleLowerCase();
      return haystack.includes(normalizedQuery);
    });
  }, [config.dictionary, query]);

  const addEntry = async () => {
    const entry: DictionaryEntry = {
      ...draft,
      term: draft.term.trim(),
      replacement: draft.replacement?.trim() || null,
      variants: variants
        .split(",")
        .map((variant) => variant.trim())
        .filter(Boolean),
    };
    const saved = await onReplace([...config.dictionary, entry]);
    if (saved) {
      setDraft(blankEntry());
      setVariants("");
      setShowForm(false);
    }
  };

  const updateEntry = (
    id: string,
    update: (entry: DictionaryEntry) => DictionaryEntry,
  ) =>
    onReplace(
      config.dictionary.map((entry) =>
        entry.id === id ? update(entry) : entry,
      ),
    );

  return (
    <ProductivityPage
      eyebrow={t("pressay.dictionary.eyebrow", { defaultValue: "VOCABULARY" })}
      title={t("pressay.dictionary.title", { defaultValue: "Dictionary" })}
      description={t("pressay.dictionary.description", {
        defaultValue:
          "Teach Pressay names, product terms and controlled replacements. Entries stay on this Mac.",
      })}
      action={
        <Button
          variant="secondary"
          onClick={() => setShowForm((visible) => !visible)}
        >
          <Plus size={14} />
          {t("pressay.dictionary.add", { defaultValue: "Add term" })}
        </Button>
      }
    >
      {error ? <p className="productivity-error">{error}</p> : null}

      {showForm ? (
        <section className="productivity-editor" aria-label="Dictionary editor">
          <div className="productivity-editor-grid">
            <label>
              <span>
                {t("pressay.dictionary.term", {
                  defaultValue: "Spoken or written term",
                })}
              </span>
              <Input
                value={draft.term}
                maxLength={200}
                placeholder="press say"
                onChange={(event) =>
                  setDraft((current) => ({
                    ...current,
                    term: event.target.value,
                  }))
                }
              />
            </label>
            <label>
              <span>
                {t("pressay.dictionary.replacement", {
                  defaultValue: "Final replacement",
                })}
              </span>
              <Input
                value={draft.replacement ?? ""}
                maxLength={500}
                placeholder="Pressay"
                onChange={(event) =>
                  setDraft((current) => ({
                    ...current,
                    replacement: event.target.value,
                  }))
                }
              />
            </label>
            <label>
              <span>
                {t("pressay.dictionary.variants", {
                  defaultValue: "Variants, comma separated",
                })}
              </span>
              <Input
                value={variants}
                placeholder="presser, pressé"
                onChange={(event) => setVariants(event.target.value)}
              />
            </label>
            <label>
              <span>
                {t("pressay.dictionary.matching", {
                  defaultValue: "Matching",
                })}
              </span>
              <Select
                value={draft.match_kind ?? "exact"}
                isClearable={false}
                options={[
                  { value: "exact", label: "Exact · safest" },
                  { value: "fuzzy", label: "Fuzzy · pronunciation" },
                ]}
                onChange={(value) =>
                  setDraft((current) => ({
                    ...current,
                    match_kind: (value ?? "exact") as DictionaryMatchKind,
                  }))
                }
              />
            </label>
          </div>
          <p className="editor-note">
            {t("pressay.dictionary.matchingNote", {
              defaultValue:
                "Exact matching ignores case and punctuation but never replaces part of another word. Fuzzy matching is best reserved for proper names.",
            })}
          </p>
          <div className="productivity-editor-actions">
            <Button variant="ghost" onClick={() => setShowForm(false)}>
              {t("common.cancel", { defaultValue: "Cancel" })}
            </Button>
            <Button disabled={saving || !draft.term.trim()} onClick={addEntry}>
              {t("pressay.dictionary.save", { defaultValue: "Save term" })}
            </Button>
          </div>
        </section>
      ) : null}

      <div className="dictionary-toolbar">
        <Search size={15} aria-hidden="true" />
        <input
          aria-label="Search dictionary"
          value={query}
          placeholder="Search terms and variants"
          onChange={(event) => setQuery(event.target.value)}
        />
        <span className="technical-label">
          {`${config.dictionary.length} / 5000`}
        </span>
      </div>

      <section className="dictionary-list" aria-label="Dictionary entries">
        {filteredEntries.length === 0 ? (
          <div className="productivity-empty is-large">
            <BookOpen size={21} />
            <h2>{query ? "No matching terms" : "Your dictionary is empty"}</h2>
            <p>
              {query
                ? "Try another search."
                : "Add the names and expressions that matter to your work."}
            </p>
          </div>
        ) : (
          filteredEntries.map((entry) => (
            <article
              key={entry.id}
              className={`dictionary-row ${entry.enabled === false ? "is-disabled" : ""}`}
            >
              <label className="dictionary-toggle">
                <input
                  type="checkbox"
                  aria-label={`Enable ${entry.term}`}
                  checked={entry.enabled !== false}
                  disabled={saving}
                  onChange={(event) =>
                    updateEntry(entry.id, (current) => ({
                      ...current,
                      enabled: event.target.checked,
                    }))
                  }
                />
                <span aria-hidden="true" />
              </label>
              <div className="dictionary-term">
                <strong>{entry.replacement || entry.term}</strong>
                <span>
                  {entry.replacement
                    ? `${entry.term} → ${entry.replacement}`
                    : entry.term}
                </span>
                {(entry.variants?.length ?? 0) > 0 ? (
                  <small>{entry.variants?.join(" · ")}</small>
                ) : null}
              </div>
              <span className="dictionary-kind">
                {entry.match_kind ?? "exact"}
              </span>
              <button
                type="button"
                className="icon-action is-danger"
                aria-label={`Delete ${entry.term}`}
                disabled={saving}
                onClick={() =>
                  onReplace(
                    config.dictionary.filter(
                      (candidate) => candidate.id !== entry.id,
                    ),
                  )
                }
              >
                <Trash2 size={14} />
              </button>
            </article>
          ))
        )}
      </section>
    </ProductivityPage>
  );
};

export const DictionarySettings = () => {
  const config = useProductivityStore((state) => state.config);
  const loading = useProductivityStore((state) => state.loading);
  const saving = useProductivityStore((state) => state.saving);
  const error = useProductivityStore((state) => state.error);
  const initialize = useProductivityStore((state) => state.initialize);
  const replaceDictionary = useProductivityStore(
    (state) => state.replaceDictionary,
  );

  useEffect(() => {
    void initialize();
  }, [initialize]);

  if (!config) {
    return (
      <div className="productivity-loading">
        {loading
          ? "Loading dictionary…"
          : (error ?? "Dictionary is unavailable.")}
      </div>
    );
  }

  return (
    <DictionarySettingsView
      config={config}
      saving={saving}
      error={error}
      onReplace={replaceDictionary}
    />
  );
};
