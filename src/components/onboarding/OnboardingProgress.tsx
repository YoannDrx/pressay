import { Check } from "lucide-react";
import { useTranslation } from "react-i18next";

interface OnboardingProgressProps {
  current: number;
  total?: number;
}

export const OnboardingProgress = ({
  current,
  total = 3,
}: OnboardingProgressProps) => {
  const { t } = useTranslation();
  return (
    <ol
      className="onboarding-progress"
      aria-label={t("signalOs.onboarding.progress")}
    >
      {Array.from({ length: total }, (_, index) => index + 1).map((step) => (
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
};
