import React, { useState, useEffect } from "react";
import { useTranslation } from "react-i18next";
import { getVersion } from "@tauri-apps/api/app";
import { SettingsGroup } from "../../ui/SettingsGroup";
import { SettingContainer } from "../../ui/SettingContainer";
import { Button } from "../../ui/Button";
import { ShowWhatsNewOnUpdate } from "../ShowWhatsNewOnUpdate";
import { UpdateChecksToggle } from "../UpdateChecksToggle";
import { AppPageHeader } from "@/components/layout";
import PressayMark from "@/components/icons/PressayMark";
import { commands } from "@/bindings";
import { useDistribution } from "@/hooks/useDistribution";

export const AboutSettings: React.FC = () => {
  const { t } = useTranslation();
  const [version, setVersion] = useState("");
  const { updaterAvailable } = useDistribution();

  useEffect(() => {
    const fetchVersion = async () => {
      try {
        const appVersion = await getVersion();
        setVersion(appVersion);
      } catch (error) {
        console.error("Failed to get app version:", error);
        setVersion(__APP_VERSION__);
      }
    };

    fetchVersion();
  }, []);

  // The support page carries no prices or purchase links, so it is safe to
  // open from every channel, including the Mac App Store (3.1.1).
  const handleSupportClick = async () => {
    const result = await commands.openExternalPage("support");
    if (result.status === "error") {
      console.error("Failed to open the support page:", result.error);
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
        {updaterAvailable ? (
          <UpdateChecksToggle descriptionMode="tooltip" grouped={true} />
        ) : null}

        <SettingContainer
          title={t("settings.about.supportDevelopment.title")}
          description={t("settings.about.supportDevelopment.description")}
          grouped={true}
        >
          <Button variant="primary" size="md" onClick={handleSupportClick}>
            {t("settings.about.supportDevelopment.button")}
          </Button>
        </SettingContainer>
      </SettingsGroup>
    </div>
  );
};
