import React from "react";

interface PressayMarkProps extends React.SVGProps<SVGSVGElement> {
  size?: number | string;
}

/** Pressay's compact P + waveform mark. Kept as vector code for crisp macOS rendering. */
const PressayMark: React.FC<PressayMarkProps> = ({
  size,
  width = size ?? 24,
  height = size ?? 24,
  className,
  ...props
}) => (
  <svg
    aria-hidden="true"
    viewBox="0 0 32 32"
    width={width}
    height={height}
    className={className}
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    {...props}
  >
    <rect x="2" y="2" width="28" height="28" rx="8" fill="#0A0B0D" />
    <path
      d="M10.5 23V9.25h6.15c3.35 0 5.35 1.79 5.35 4.52 0 2.74-2 4.55-5.35 4.55h-2.73"
      stroke="#F3F4F6"
      strokeWidth="2.35"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M15.7 14.15h1.3l1.05-2.05 1.25 4.15 1.2-2.1h1.65"
      stroke="#5668FF"
      strokeWidth="1.45"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

export default PressayMark;
