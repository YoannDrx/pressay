import React, { useState, useEffect } from "react";
import { useTranslation } from "react-i18next";
import { getVersion } from "@tauri-apps/api/app";
import { openUrl } from "@tauri-apps/plugin-opener";
import { SettingsGroup } from "../../ui/SettingsGroup";
import { SettingContainer } from "../../ui/SettingContainer";
import { Button } from "../../ui/Button";
import { ShowWhatsNewOnUpdate } from "../ShowWhatsNewOnUpdate";
import { UpdateChecksToggle } from "../UpdateChecksToggle";
import { AppPageHeader } from "@/components/layout";
import PressayMark from "@/components/icons/PressayMark";

export const AboutSettings: React.FC = () => {
  const { t } = useTranslation();
  const [version, setVersion] = useState("");

  useEffect(() => {
    const fetchVersion = async () => {
      try {
        const appVersion = await getVersion();
        setVersion(appVersion);
      } catch (error) {
        console.error("Failed to get app version:", error);
        setVersion("2.0.0-beta.2");
      }
    };

    fetchVersion();
  }, []);

  const handleDonateClick = async () => {
    try {
      await openUrl("https://press-say.app");
    } catch (error) {
      console.error("Failed to open donate link:", error);
    }
  };

  return (
    <div className="settings-page signal-settings-page space-y-6">
      <AppPageHeader
        eyebrow={t("sidebar.about")}
        title={t("settings.about.title")}
        description={t("settings.about.supportDevelopment.description")}
      />
      <section className="about-identity-card">
        <div className="about-identity-mark">
          <PressayMark size={44} />
        </div>
        <div>
          {/* Pressay and YoDev are product names, not translatable copy. */}
          {/* eslint-disable-next-line i18next/no-literal-string */}
          <h2>Pressay</h2>
          <p>{t("settings.about.developer")}</p>
        </div>
        {/* eslint-disable-next-line i18next/no-literal-string */}
        <span className="about-version-pill">v{version}</span>
      </section>

      <SettingsGroup title={t("settings.about.title")}>
        <SettingContainer
          title={t("settings.about.version.title")}
          description={t("settings.about.version.description")}
          grouped={true}
        >
          {/* eslint-disable-next-line i18next/no-literal-string */}
          <span className="text-sm font-mono">v{version}</span>
        </SettingContainer>

        <ShowWhatsNewOnUpdate descriptionMode="tooltip" grouped={true} />
        <UpdateChecksToggle descriptionMode="tooltip" grouped={true} />

        <SettingContainer
          title={t("settings.about.supportDevelopment.title")}
          description={t("settings.about.supportDevelopment.description")}
          grouped={true}
        >
          <Button variant="primary" size="md" onClick={handleDonateClick}>
            {t("settings.about.supportDevelopment.button")}
          </Button>
        </SettingContainer>
      </SettingsGroup>
    </div>
  );
};
