import type { ReactNode } from "react";

interface ProductivityPageProps {
  eyebrow: string;
  title: string;
  description: string;
  action?: ReactNode;
  children: ReactNode;
}

export const ProductivityPage = ({
  eyebrow,
  title,
  description,
  action,
  children,
}: ProductivityPageProps) => (
  <div className="product-page productivity-page">
    <header className="productivity-header">
      <div>
        <p className="product-eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action}
    </header>
    {children}
  </div>
);
