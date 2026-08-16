import React from "react";
import PressayMark from "./PressayMark";

interface PressayWordmarkProps {
  width?: number;
  height?: number;
  className?: string;
}

const PressayWordmark: React.FC<PressayWordmarkProps> = ({
  width = 160,
  height,
  className,
}) => {
  const markSize = height ?? Math.max(24, Math.round(width * 0.24));

  return (
    <div
      className={`inline-flex items-center gap-2.5 text-text ${className ?? ""}`}
      style={{ width, height }}
      aria-label="Pressay"
    >
      <PressayMark
        width={markSize}
        height={markSize}
        className="shrink-0 text-logo-primary"
      />
      {/* Brand name is intentionally not translated. */}
      {/* eslint-disable-next-line i18next/no-literal-string */}
      <span className="text-[length:inherit] text-xl font-semibold tracking-[-0.035em]">
        Pressay
      </span>
    </div>
  );
};

export default PressayWordmark;
