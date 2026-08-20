import type { ReactNode } from "react";
import { AppPageHeader } from "@/components/layout";

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
    <AppPageHeader
      eyebrow={eyebrow}
      title={title}
      description={description}
      action={action}
    />
    {children}
  </div>
);
