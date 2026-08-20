import type { ReactNode } from "react";

interface AppPageHeaderProps {
  eyebrow: string;
  title: string;
  description: string;
  action?: ReactNode;
  aside?: ReactNode;
  className?: string;
}

export function AppPageHeader({
  eyebrow,
  title,
  description,
  action,
  aside,
  className,
}: AppPageHeaderProps) {
  return (
    <header className={`app-page-header ${className ?? ""}`.trim()}>
      <div className="app-page-header-copy">
        <p className="product-eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="app-page-description">{description}</p>
      </div>
      {action ? <div className="app-page-actions">{action}</div> : null}
      {aside ? <div className="app-page-aside">{aside}</div> : null}
    </header>
  );
}
