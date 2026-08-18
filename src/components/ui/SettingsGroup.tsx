import React from "react";

interface SettingsGroupProps {
  title?: string;
  description?: string;
  children: React.ReactNode;
}

export const SettingsGroup: React.FC<SettingsGroupProps> = ({
  title,
  description,
  children,
}) => {
  return (
    <section className="settings-section">
      {title && (
        <header className="settings-section-header">
          <h2>{title}</h2>
          {description && <p>{description}</p>}
        </header>
      )}
      <div className="settings-section-surface">
        <div className="settings-section-rows">{children}</div>
      </div>
    </section>
  );
};
