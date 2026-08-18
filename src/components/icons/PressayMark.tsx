import React, { useId } from "react";

interface PressayMarkProps extends React.SVGProps<SVGSVGElement> {
  size?: number | string;
}

/** Pressay's Signal Orb: voice enters as a pulse and leaves as a structured signal. */
const PressayMark: React.FC<PressayMarkProps> = ({
  size,
  width = size ?? 24,
  height = size ?? 24,
  className,
  ...props
}) => {
  const gradientId = `signal-orb-${useId().replace(/:/g, "")}`;

  return (
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
      <defs>
        <linearGradient id={gradientId} x1="5" y1="4" x2="27" y2="29">
          <stop stopColor="#22B7FF" />
          <stop offset="0.52" stopColor="#4868FF" />
          <stop offset="1" stopColor="#8A5CFF" />
        </linearGradient>
      </defs>
      <circle cx="16" cy="16" r="14" fill={`url(#${gradientId})`} />
      <path
        d="M8.4 11.4A8.8 8.8 0 0 1 23.6 11.4M8.4 20.6A8.8 8.8 0 0 0 23.6 20.6"
        stroke="white"
        strokeOpacity="0.52"
        strokeWidth="1.35"
        strokeLinecap="round"
      />
      <path
        d="M11 16h1.8m1.55-3.6v7.2M17.65 10v12M21.15 13.25v5.5M23.2 16H25"
        stroke="white"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
      <circle cx="16" cy="16" r="11.25" stroke="white" strokeOpacity="0.18" />
    </svg>
  );
};

export default PressayMark;
