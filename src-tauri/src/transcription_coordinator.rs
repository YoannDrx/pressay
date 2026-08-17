use crate::actions::ACTION_MAP;
use crate::managers::audio::AudioRecordingManager;
use log::{debug, error, warn};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, RwLock};
use std::thread;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Manager};
use tauri_specta::Event;

const DEBOUNCE: Duration = Duration::from_millis(30);
const RELEASE_GRACE: Duration = Duration::from_millis(50);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PttAction {
    Passthrough,
    DeferRelease,
    CancelRelease,
}

struct PendingRelease {
    binding_id: String,
    hotkey_string: String,
    deadline: Instant,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, Type)]
#[serde(rename_all = "snake_case")]
pub enum PipelinePhase {
    Idle,
    Recording,
    Transcribing,
    Transforming,
    Pasting,
    Cancelled,
    Failed,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, Type)]
pub struct PipelineFailure {
    pub stage: PipelinePhase,
    pub code: String,
    pub recoverable: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, Type, tauri_specta::Event)]
pub struct PipelineState {
    pub phase: PipelinePhase,
    pub operation_id: u64,
    pub binding_id: Option<String>,
    pub failure: Option<PipelineFailure>,
}

impl Default for PipelineState {
    fn default() -> Self {
        Self {
            phase: PipelinePhase::Idle,
            operation_id: 0,
            binding_id: None,
            failure: None,
        }
    }
}

impl PipelineState {
    fn accepts_start(&self) -> bool {
        matches!(
            self.phase,
            PipelinePhase::Idle | PipelinePhase::Cancelled | PipelinePhase::Failed
        )
    }

    fn recording_binding(&self) -> Option<&str> {
        (self.phase == PipelinePhase::Recording)
            .then_some(self.binding_id.as_deref())
            .flatten()
    }
}

/// Commands processed sequentially by the coordinator thread.
enum Command {
    Input {
        binding_id: String,
        hotkey_string: String,
        is_pressed: bool,
        push_to_talk: bool,
    },
    Cancel {
        recording_was_active: bool,
    },
    Transition {
        operation_id: u64,
        phase: PipelinePhase,
        failure: Option<PipelineFailure>,
    },
    ProcessingFinished {
        operation_id: u64,
    },
}

fn classify_ptt_event(
    pending_release_binding: Option<&str>,
    is_pressed: bool,
    push_to_talk: bool,
    binding_id: &str,
    recording_binding: Option<&str>,
) -> PttAction {
    if !push_to_talk {
        return PttAction::Passthrough;
    }

    if is_pressed {
        if pending_release_binding == Some(binding_id) {
            PttAction::CancelRelease
        } else {
            PttAction::Passthrough
        }
    } else if recording_binding == Some(binding_id) && pending_release_binding.is_none() {
        PttAction::DeferRelease
    } else {
        PttAction::Passthrough
    }
}

/// Serialises all transcription lifecycle events through a single thread
/// to eliminate race conditions between keyboard shortcuts, signals, and
/// the async transcribe-paste pipeline.
pub struct TranscriptionCoordinator {
    tx: Sender<Command>,
    state: Arc<RwLock<PipelineState>>,
}

pub fn is_transcribe_binding(id: &str) -> bool {
    id == "transcribe" || id == "transcribe_with_post_process"
}

#[tauri::command]
#[specta::specta]
pub fn get_pipeline_state(
    coordinator: tauri::State<'_, TranscriptionCoordinator>,
) -> PipelineState {
    coordinator.current_state()
}

impl TranscriptionCoordinator {
    pub fn new(app: AppHandle) -> Self {
        let (tx, rx) = mpsc::channel();
        let state = Arc::new(RwLock::new(PipelineState::default()));
        let shared_state = Arc::clone(&state);

        thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let mut pipeline = PipelineState::default();
                let mut last_press: Option<Instant> = None;
                let mut pending_release: Option<PendingRelease> = None;

                loop {
                    let cmd = if let Some(pending) = &pending_release {
                        match rx.recv_timeout(
                            pending.deadline.saturating_duration_since(Instant::now()),
                        ) {
                            Ok(cmd) => cmd,
                            Err(mpsc::RecvTimeoutError::Timeout) => {
                                if let Some(pending) = pending_release.take() {
                                    if pipeline.recording_binding()
                                        == Some(pending.binding_id.as_str())
                                    {
                                        begin_stop(
                                            &app,
                                            &shared_state,
                                            &mut pipeline,
                                            &pending.binding_id,
                                            &pending.hotkey_string,
                                        );
                                    }
                                }
                                continue;
                            }
                            Err(mpsc::RecvTimeoutError::Disconnected) => break,
                        }
                    } else {
                        match rx.recv() {
                            Ok(cmd) => cmd,
                            Err(_) => break,
                        }
                    };

                    match cmd {
                        Command::Input {
                            binding_id,
                            hotkey_string,
                            is_pressed,
                            push_to_talk,
                        } => {
                            let pending_release_binding = pending_release
                                .as_ref()
                                .map(|pending| pending.binding_id.as_str());
                            let recording_binding = pipeline.recording_binding();

                            match classify_ptt_event(
                                pending_release_binding,
                                is_pressed,
                                push_to_talk,
                                &binding_id,
                                recording_binding,
                            ) {
                                PttAction::CancelRelease => {
                                    pending_release = None;
                                    continue;
                                }
                                PttAction::DeferRelease => {
                                    pending_release = Some(PendingRelease {
                                        binding_id,
                                        hotkey_string,
                                        deadline: Instant::now() + RELEASE_GRACE,
                                    });
                                    continue;
                                }
                                PttAction::Passthrough => {}
                            }

                            // Debounce rapid-fire press events (key repeat / double-tap).
                            // Push-to-talk releases may be deferred above to absorb X11 auto-repeat.
                            if is_pressed {
                                let now = Instant::now();
                                if last_press.is_some_and(|t| now.duration_since(t) < DEBOUNCE) {
                                    debug!("Debounced press for '{binding_id}'");
                                    continue;
                                }
                                last_press = Some(now);
                            }

                            if push_to_talk {
                                if is_pressed && pipeline.accepts_start() {
                                    begin_start(
                                        &app,
                                        &shared_state,
                                        &mut pipeline,
                                        &binding_id,
                                        &hotkey_string,
                                    );
                                } else if !is_pressed
                                    && pipeline.recording_binding() == Some(binding_id.as_str())
                                {
                                    begin_stop(
                                        &app,
                                        &shared_state,
                                        &mut pipeline,
                                        &binding_id,
                                        &hotkey_string,
                                    );
                                }
                            } else if is_pressed {
                                if pipeline.accepts_start() {
                                    begin_start(
                                        &app,
                                        &shared_state,
                                        &mut pipeline,
                                        &binding_id,
                                        &hotkey_string,
                                    );
                                } else if pipeline.recording_binding() == Some(binding_id.as_str())
                                {
                                    begin_stop(
                                        &app,
                                        &shared_state,
                                        &mut pipeline,
                                        &binding_id,
                                        &hotkey_string,
                                    );
                                } else {
                                    debug!("Ignoring press for '{binding_id}': pipeline busy")
                                }
                            }
                        }
                        Command::Cancel {
                            recording_was_active,
                        } => {
                            pending_release = None;
                            if recording_was_active
                                || !matches!(
                                    pipeline.phase,
                                    PipelinePhase::Idle
                                        | PipelinePhase::Cancelled
                                        | PipelinePhase::Failed
                                )
                            {
                                pipeline.phase = PipelinePhase::Cancelled;
                                pipeline.failure = None;
                                publish_state(&app, &shared_state, &pipeline);
                            }
                        }
                        Command::Transition {
                            operation_id,
                            phase,
                            failure,
                        } => {
                            if operation_id == pipeline.operation_id
                                && transition_allowed(pipeline.phase, phase)
                            {
                                pipeline.phase = phase;
                                pipeline.failure = failure;
                                publish_state(&app, &shared_state, &pipeline);
                            } else {
                                debug!(
                                    "Ignoring stale or invalid pipeline transition: op={} {:?}->{:?}",
                                    operation_id, pipeline.phase, phase
                                );
                            }
                        }
                        Command::ProcessingFinished { operation_id } => {
                            if operation_id == pipeline.operation_id
                                && !matches!(
                                    pipeline.phase,
                                    PipelinePhase::Cancelled | PipelinePhase::Failed
                                )
                            {
                                pipeline.phase = PipelinePhase::Idle;
                                pipeline.binding_id = None;
                                pipeline.failure = None;
                                publish_state(&app, &shared_state, &pipeline);
                            }
                        }
                    }
                }
                debug!("Transcription coordinator exited");
            }));
            if let Err(e) = result {
                error!("Transcription coordinator panicked: {e:?}");
            }
        });

        Self { tx, state }
    }

    /// Send a keyboard/signal input event for a transcribe binding.
    /// For signal-based toggles, use `is_pressed: true` and `push_to_talk: false`.
    pub fn send_input(
        &self,
        binding_id: &str,
        hotkey_string: &str,
        is_pressed: bool,
        push_to_talk: bool,
    ) {
        if self
            .tx
            .send(Command::Input {
                binding_id: binding_id.to_string(),
                hotkey_string: hotkey_string.to_string(),
                is_pressed,
                push_to_talk,
            })
            .is_err()
        {
            warn!("Transcription coordinator channel closed");
        }
    }

    pub fn notify_cancel(&self, recording_was_active: bool) {
        if self
            .tx
            .send(Command::Cancel {
                recording_was_active,
            })
            .is_err()
        {
            warn!("Transcription coordinator channel closed");
        }
    }

    pub fn current_state(&self) -> PipelineState {
        self.state
            .read()
            .map(|state| state.clone())
            .unwrap_or_default()
    }

    pub fn current_operation_id(&self) -> u64 {
        self.current_state().operation_id
    }

    pub fn transition(&self, operation_id: u64, phase: PipelinePhase) {
        if self
            .tx
            .send(Command::Transition {
                operation_id,
                phase,
                failure: None,
            })
            .is_err()
        {
            warn!("Transcription coordinator channel closed");
        }
    }

    pub fn fail(
        &self,
        operation_id: u64,
        stage: PipelinePhase,
        code: impl Into<String>,
        recoverable: bool,
    ) {
        let failure = PipelineFailure {
            stage,
            code: code.into(),
            recoverable,
        };
        if self
            .tx
            .send(Command::Transition {
                operation_id,
                phase: PipelinePhase::Failed,
                failure: Some(failure),
            })
            .is_err()
        {
            warn!("Transcription coordinator channel closed");
        }
    }

    pub fn notify_processing_finished(&self, operation_id: u64) {
        if self
            .tx
            .send(Command::ProcessingFinished { operation_id })
            .is_err()
        {
            warn!("Transcription coordinator channel closed");
        }
    }
}

fn publish_state(app: &AppHandle, shared: &RwLock<PipelineState>, state: &PipelineState) {
    if let Ok(mut snapshot) = shared.write() {
        *snapshot = state.clone();
    }
    if let Err(error) = state.clone().emit(app) {
        warn!("Failed to emit pipeline state: {error}");
    }
}

fn transition_allowed(current: PipelinePhase, next: PipelinePhase) -> bool {
    if current == next {
        return true;
    }
    match current {
        PipelinePhase::Recording => matches!(
            next,
            PipelinePhase::Transcribing | PipelinePhase::Cancelled | PipelinePhase::Failed
        ),
        PipelinePhase::Transcribing => matches!(
            next,
            PipelinePhase::Transforming
                | PipelinePhase::Pasting
                | PipelinePhase::Idle
                | PipelinePhase::Cancelled
                | PipelinePhase::Failed
        ),
        PipelinePhase::Transforming => matches!(
            next,
            PipelinePhase::Pasting
                | PipelinePhase::Idle
                | PipelinePhase::Cancelled
                | PipelinePhase::Failed
        ),
        PipelinePhase::Pasting => matches!(
            next,
            PipelinePhase::Idle | PipelinePhase::Cancelled | PipelinePhase::Failed
        ),
        // A receipt timeout is asynchronous and can arrive after the immediate
        // paste call completed. It may still fail the same operation while idle;
        // operation IDs prevent it from affecting a newer dictation.
        PipelinePhase::Idle => next == PipelinePhase::Failed,
        PipelinePhase::Cancelled | PipelinePhase::Failed => false,
    }
}

fn begin_start(
    app: &AppHandle,
    shared: &RwLock<PipelineState>,
    state: &mut PipelineState,
    binding_id: &str,
    hotkey_string: &str,
) {
    state.operation_id = state.operation_id.saturating_add(1);
    state.phase = PipelinePhase::Recording;
    state.binding_id = Some(binding_id.to_string());
    state.failure = None;
    publish_state(app, shared, state);

    let Some(action) = ACTION_MAP.get(binding_id) else {
        warn!("No action in ACTION_MAP for '{binding_id}'");
        state.phase = PipelinePhase::Failed;
        state.failure = Some(PipelineFailure {
            stage: PipelinePhase::Recording,
            code: "unknown_binding".to_string(),
            recoverable: true,
        });
        publish_state(app, shared, state);
        return;
    };
    action.start(app, binding_id, hotkey_string);
    if !app
        .try_state::<Arc<AudioRecordingManager>>()
        .is_some_and(|a| a.is_recording())
    {
        state.phase = PipelinePhase::Failed;
        state.failure = Some(PipelineFailure {
            stage: PipelinePhase::Recording,
            code: "recording_start_failed".to_string(),
            recoverable: true,
        });
        publish_state(app, shared, state);
    }
}

fn begin_stop(
    app: &AppHandle,
    shared: &RwLock<PipelineState>,
    state: &mut PipelineState,
    binding_id: &str,
    hotkey_string: &str,
) {
    let Some(action) = ACTION_MAP.get(binding_id) else {
        warn!("No action in ACTION_MAP for '{binding_id}'");
        return;
    };
    state.phase = PipelinePhase::Transcribing;
    publish_state(app, shared, state);
    action.stop(app, binding_id, hotkey_string);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn push_to_talk_release_while_recording_defers_release() {
        assert_eq!(
            classify_ptt_event(None, false, true, "transcribe", Some("transcribe")),
            PttAction::DeferRelease
        );
    }

    #[test]
    fn push_to_talk_press_matching_pending_release_cancels_release() {
        assert_eq!(
            classify_ptt_event(
                Some("transcribe"),
                true,
                true,
                "transcribe",
                Some("transcribe")
            ),
            PttAction::CancelRelease
        );
    }

    #[test]
    fn toggle_mode_press_and_release_pass_through() {
        assert_eq!(
            classify_ptt_event(
                Some("transcribe"),
                true,
                false,
                "transcribe",
                Some("transcribe")
            ),
            PttAction::Passthrough
        );
        assert_eq!(
            classify_ptt_event(None, false, false, "transcribe", Some("transcribe")),
            PttAction::Passthrough
        );
    }

    #[test]
    fn press_for_different_binding_than_pending_release_passes_through() {
        assert_eq!(
            classify_ptt_event(
                Some("transcribe"),
                true,
                true,
                "transcribe_with_post_process",
                Some("transcribe")
            ),
            PttAction::Passthrough
        );
    }

    #[test]
    fn press_matching_pending_release_cancels_without_recording_state() {
        assert_eq!(
            classify_ptt_event(Some("transcribe"), true, true, "transcribe", None),
            PttAction::CancelRelease
        );
    }

    #[test]
    fn pipeline_accepts_only_ordered_forward_transitions() {
        assert!(transition_allowed(
            PipelinePhase::Recording,
            PipelinePhase::Transcribing
        ));
        assert!(transition_allowed(
            PipelinePhase::Transcribing,
            PipelinePhase::Transforming
        ));
        assert!(transition_allowed(
            PipelinePhase::Transforming,
            PipelinePhase::Pasting
        ));
        assert!(transition_allowed(
            PipelinePhase::Pasting,
            PipelinePhase::Idle
        ));
        assert!(!transition_allowed(
            PipelinePhase::Pasting,
            PipelinePhase::Recording
        ));
        assert!(!transition_allowed(
            PipelinePhase::Idle,
            PipelinePhase::Pasting
        ));
        assert!(transition_allowed(
            PipelinePhase::Idle,
            PipelinePhase::Failed
        ));
    }

    #[test]
    fn failed_and_cancelled_states_allow_a_fresh_operation() {
        for phase in [
            PipelinePhase::Idle,
            PipelinePhase::Failed,
            PipelinePhase::Cancelled,
        ] {
            let state = PipelineState {
                phase,
                ..PipelineState::default()
            };
            assert!(state.accepts_start());
        }
        let busy = PipelineState {
            phase: PipelinePhase::Transforming,
            ..PipelineState::default()
        };
        assert!(!busy.accepts_start());
    }

    // ---------------------------------------------------------------------
    // Sequence-level regression coverage for issue #1539.
    //
    // Under X11 key auto-repeat, holding a push-to-talk key does not emit one
    // long press. It emits the initial press followed by a stream of
    // synthesized release/press pairs, then a single genuine release on key-up.
    // Before the fix, every synthesized release passed straight through and
    // stopped recording, so holding the key "rapidly toggled" recording on and
    // off. The fix defers each release for a short grace window and cancels it
    // when the matching auto-repeat press arrives.
    //
    // The unit tests above assert `classify_ptt_event` in isolation. The
    // simulator below threads that classifier through the same `pending_release`
    // / `stage` state transitions the coordinator loop performs (lines that
    // handle `Command::Input` and the `recv_timeout` grace expiry), so a whole
    // event burst can be exercised deterministically without a Tauri AppHandle
    // or real timers.
    // ---------------------------------------------------------------------

    const BINDING: &str = "transcribe";

    #[derive(Clone, Copy)]
    enum Ev {
        /// A key-down event (real initial press or a synthesized auto-repeat press).
        Press,
        /// A key-up event (synthesized auto-repeat release or the genuine key-up).
        Release,
        /// The `RELEASE_GRACE` window elapsed with no cancelling press arriving.
        Grace,
    }

    #[derive(Debug, PartialEq, Eq)]
    enum SimStage {
        Idle,
        Recording,
        Processing,
    }

    struct SimResult {
        starts: u32,
        stops: u32,
        stage: SimStage,
    }

    /// Mirror of the coordinator loop's decision logic for a single push-to-talk
    /// binding: it calls the real `classify_ptt_event` and applies the exact same
    /// Defer / Cancel / debounce / start / stop transitions.
    fn simulate(events: &[Ev]) -> SimResult {
        let mut stage = SimStage::Idle;
        let mut pending: Option<String> = None;
        let mut last_press_ms: Option<u64> = None;
        let mut clock_ms: u64 = 0;
        let mut starts = 0u32;
        let mut stops = 0u32;
        let debounce_ms = DEBOUNCE.as_millis() as u64;

        for ev in events {
            // Auto-repeat events arrive a few ms apart, well inside DEBOUNCE.
            clock_ms += 5;

            match ev {
                Ev::Grace => {
                    // Coordinator's `RecvTimeoutError::Timeout` arm: fire the
                    // deferred release iff we are still recording that binding.
                    if let Some(pending_binding) = pending.take() {
                        if stage == SimStage::Recording && pending_binding == BINDING {
                            stage = SimStage::Processing;
                            stops += 1;
                        }
                    }
                }
                Ev::Press | Ev::Release => {
                    let is_pressed = matches!(ev, Ev::Press);
                    let pending_binding = pending.as_deref();
                    let recording_binding = if stage == SimStage::Recording {
                        Some(BINDING)
                    } else {
                        None
                    };

                    match classify_ptt_event(
                        pending_binding,
                        is_pressed,
                        true, // push_to_talk
                        BINDING,
                        recording_binding,
                    ) {
                        PttAction::CancelRelease => {
                            pending = None;
                            continue;
                        }
                        PttAction::DeferRelease => {
                            pending = Some(BINDING.to_string());
                            continue;
                        }
                        PttAction::Passthrough => {}
                    }

                    if is_pressed {
                        if last_press_ms.is_some_and(|t| clock_ms - t < debounce_ms) {
                            continue;
                        }
                        last_press_ms = Some(clock_ms);
                    }

                    if is_pressed && stage == SimStage::Idle {
                        stage = SimStage::Recording;
                        starts += 1;
                    } else if !is_pressed && stage == SimStage::Recording {
                        stage = SimStage::Processing;
                        stops += 1;
                    }
                }
            }
        }

        SimResult {
            starts,
            stops,
            stage,
        }
    }

    /// Initial press plus several synthesized release/press pairs, as X11 emits
    /// while a push-to-talk key is held down.
    fn autorepeat_burst() -> Vec<Ev> {
        let mut events = vec![Ev::Press];
        for _ in 0..6 {
            events.push(Ev::Release);
            events.push(Ev::Press);
        }
        events
    }

    /// Regression for #1539: a burst of X11 auto-repeat release/press pairs must
    /// not stop recording. Before the fix the first synthesized release stopped
    /// recording immediately (stops == 1, stage left Recording), which produced
    /// the rapid on/off toggling. With the fix the releases are coalesced and
    /// recording stays continuously active for the whole burst.
    #[test]
    fn x11_autorepeat_burst_does_not_toggle_recording() {
        let result = simulate(&autorepeat_burst());
        assert_eq!(result.starts, 1, "recording should start exactly once");
        assert_eq!(
            result.stops, 0,
            "synthesized auto-repeat releases must not stop recording mid-burst"
        );
        assert_eq!(
            result.stage,
            SimStage::Recording,
            "recording must remain active across the entire auto-repeat burst"
        );
    }

    /// Complements the burst test: once the key is genuinely released and the
    /// grace window elapses with no re-press, recording stops exactly once. This
    /// proves the debounce only coalesces synthesized releases and does not wedge
    /// the coordinator or swallow the real key-up.
    #[test]
    fn genuine_release_after_grace_stops_recording_once() {
        let mut events = autorepeat_burst();
        events.push(Ev::Release); // genuine key-up
        events.push(Ev::Grace); // grace window elapses, no cancelling press
        let result = simulate(&events);
        assert_eq!(result.starts, 1, "recording should start exactly once");
        assert_eq!(
            result.stops, 1,
            "a genuine release should stop recording exactly once"
        );
        assert_eq!(result.stage, SimStage::Processing);
    }
}
