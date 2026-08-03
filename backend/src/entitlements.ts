export const plans = [
  "free",
  "pro_byok",
  "pro_cloud",
  "lifetime_byok",
  "team"
] as const;
export type PlanCode = (typeof plans)[number];

export type Limits = {
  cloudTranscriptionSecondsPerMonth: number;
  transformationsPerMonth: number;
  syncEnabled: boolean;
  teamSeats: number;
};

export const planFeatures = {
  free: [
    "dictation.local",
    "dictation.byok",
    "modes.faithful",
    "modes.clean",
    "modes.message",
    "history.24h",
    "data.export",
    "data.delete"
  ],
  pro_byok: [
    "dictation.local",
    "dictation.byok",
    "modes.all",
    "modes.custom",
    "profiles.app",
    "transformations.unlimited_byok",
    "history.30d",
    "history.search",
    "history.tags",
    "history.favorites",
    "history.reprocess",
    "voice_inbox",
    "voice_correction",
    "developer_modes",
    "data.export",
    "data.delete"
  ],
  lifetime_byok: [] as string[],
  pro_cloud: [] as string[],
  team: [] as string[]
} satisfies Record<PlanCode, string[]>;

planFeatures.lifetime_byok = [...planFeatures.pro_byok];

export const deviceLimits: Record<PlanCode, number> = {
  free: 1,
  pro_byok: 3,
  lifetime_byok: 3,
  pro_cloud: 3,
  team: 3
};

export const planLimits: Record<PlanCode, Limits> = {
  free: {
    cloudTranscriptionSecondsPerMonth: 0,
    transformationsPerMonth: 0,
    syncEnabled: false,
    teamSeats: 1
  },
  pro_byok: {
    cloudTranscriptionSecondsPerMonth: 0,
    transformationsPerMonth: 0,
    syncEnabled: true,
    teamSeats: 1
  },
  pro_cloud: {
    cloudTranscriptionSecondsPerMonth: 36_000,
    transformationsPerMonth: 2_000,
    syncEnabled: true,
    teamSeats: 1
  },
  lifetime_byok: {
    cloudTranscriptionSecondsPerMonth: 0,
    transformationsPerMonth: 0,
    syncEnabled: false,
    teamSeats: 1
  },
  team: {
    cloudTranscriptionSecondsPerMonth: 54_000,
    transformationsPerMonth: 3_000,
    syncEnabled: true,
    teamSeats: 1
  }
};

export function isWithinCloudAllowance(
  plan: PlanCode,
  currentSeconds: number,
  requestedSeconds: number
): boolean {
  const allowance = planLimits[plan].cloudTranscriptionSecondsPerMonth;
  return allowance > 0 && currentSeconds + requestedSeconds <= allowance;
}
