import { Check } from "lucide-react";

interface OnboardingProgressProps {
  current: number;
}

export const OnboardingProgress = ({ current }: OnboardingProgressProps) => (
  <ol className="onboarding-progress" aria-label="Onboarding progress">
    {[1, 2, 3, 4].map((step) => (
      <li
        key={step}
        className={step === current ? "is-current" : undefined}
        aria-current={step === current ? "step" : undefined}
      >
        <span>{step < current ? <Check size={11} /> : step}</span>
      </li>
    ))}
  </ol>
);
