import type { PipelineState, VoiceSurfaceState } from "@/bindings";

export const INITIAL_VOICE_SURFACE_STATE: VoiceSurfaceState = {
  operation_id: 0,
  phase: "hidden",
  route: "local_stt",
  provider_id: null,
  mode_id: null,
  target_application: null,
  progress: null,
  error: null,
  available_actions: [],
};

export const INITIAL_PIPELINE_STATE: PipelineState = {
  phase: "idle",
  operation_id: 0,
  binding_id: null,
  failure: null,
  voice: INITIAL_VOICE_SURFACE_STATE,
};
