import React from "react";
import { Button } from "../ui/Button";
import { Dropdown, DropdownOption } from "../ui/Dropdown";
import { PlayIcon } from "lucide-react";
import { SettingContainer } from "../ui/SettingContainer";
import { useSettingsStore } from "../../stores/settingsStore";
import { useSettings } from "../../hooks/useSettings";
import { useTranslation } from "react-i18next";
import type { SoundTheme } from "../../bindings";

const BUNDLED_SOUND_THEME_LABELS: Record<
  Exclude<SoundTheme, "custom">,
  string
> = {
  marimba: "Marimba",
  pop: "Pop",
  minimal: "Minimal",
  soft: "Soft",
  glass: "Glass",
  mechanical: "Mechanical",
  dreamy: "Dreamy",
  scifi: "Sci-Fi",
  studio: "Studio",
  zen: "Zen",
};

interface SoundPickerProps {
  label: string;
  description: string;
}

export const SoundPicker: React.FC<SoundPickerProps> = ({
  label,
  description,
}) => {
  const { getSetting, updateSetting } = useSettings();
  const { t } = useTranslation();
  const playTestSound = useSettingsStore((state) => state.playTestSound);
  const customSounds = useSettingsStore((state) => state.customSounds);

  const selectedTheme = getSetting("sound_theme") ?? "marimba";

  // `SoundTheme` is generated from the Rust enum. The exhaustive Record makes
  // adding a backend theme a compile error here until the UI supplies its label.
  const options: DropdownOption[] = Object.entries(
    BUNDLED_SOUND_THEME_LABELS,
  ).map(([value, optionLabel]) => ({ value, label: optionLabel }));

  // Only add Custom option if both custom sound files exist
  if (customSounds.start && customSounds.stop) {
    options.push({ value: "custom", label: t("modelSelector.custom") });
  }

  const handlePlayBothSounds = async () => {
    await playTestSound("start");
    await new Promise((resolve) => window.setTimeout(resolve, 240));
    await playTestSound("stop");
  };

  return (
    <SettingContainer
      title={label}
      description={description}
      grouped
      layout="horizontal"
    >
      <div className="flex items-center gap-2">
        <Dropdown
          selectedValue={selectedTheme}
          onSelect={(value) =>
            updateSetting("sound_theme", value as SoundTheme)
          }
          options={options}
        />
        <Button
          variant="ghost"
          size="sm"
          onClick={handlePlayBothSounds}
          title={description}
          aria-label={description}
        >
          <PlayIcon className="h-4 w-4" />
        </Button>
      </div>
    </SettingContainer>
  );
};
