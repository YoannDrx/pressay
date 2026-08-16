use crate::productivity::{frontmost_application, SelectionContext, TargetApplication};

const MAX_SELECTION_CHARS: usize = 20_000;

fn bounded_selection(text: &str) -> Option<String> {
    if text.trim().is_empty() {
        return None;
    }

    if text.chars().count() <= MAX_SELECTION_CHARS {
        return Some(text.to_string());
    }

    Some(text.chars().take(MAX_SELECTION_CHARS).collect())
}

fn value_matches_expected(value: &str, expected_text: &str) -> bool {
    !expected_text.trim().is_empty() && value.ends_with(expected_text)
}

#[cfg(target_os = "macos")]
pub fn capture_selected_text(target: &TargetApplication) -> Option<SelectionContext> {
    use objc2_core_foundation::{CFRetained, CFString, CFType};
    use std::ffi::c_void;
    use std::ptr::NonNull;

    type AXError = i32;
    const AX_ERROR_SUCCESS: AXError = 0;

    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        fn AXIsProcessTrusted() -> u8;
        fn AXUIElementCreateSystemWide() -> *mut c_void;
        fn AXUIElementCopyAttributeValue(
            element: *const c_void,
            attribute: *const CFString,
            value: *mut *mut c_void,
        ) -> AXError;
        fn AXUIElementGetPid(element: *const c_void, pid: *mut i32) -> AXError;
        fn AXUIElementSetMessagingTimeout(element: *const c_void, timeout: f32) -> AXError;
    }

    fn from_create_rule(pointer: *mut c_void) -> Option<CFRetained<CFType>> {
        let pointer = NonNull::new(pointer.cast::<CFType>())?;
        // SAFETY: The two AX functions used below follow Core Foundation's
        // Create/Copy rule and return a +1 reference on success.
        Some(unsafe { CFRetained::from_raw(pointer) })
    }

    fn copy_attribute(
        element: &CFRetained<CFType>,
        name: &'static str,
    ) -> Option<CFRetained<CFType>> {
        let attribute = CFString::from_static_str(name);
        let mut value = std::ptr::null_mut();
        // SAFETY: Both retained objects remain alive for the duration of the
        // call, and `value` is an initialized out pointer owned on success.
        let status = unsafe {
            AXUIElementCopyAttributeValue(
                CFRetained::as_ptr(element).as_ptr().cast(),
                CFRetained::as_ptr(&attribute).as_ptr(),
                &mut value,
            )
        };
        (status == AX_ERROR_SUCCESS)
            .then(|| from_create_rule(value))
            .flatten()
    }

    if target.process_id <= 0 {
        return None;
    }

    // SAFETY: This parameterless system query has no ownership side effects.
    if unsafe { AXIsProcessTrusted() } == 0 {
        return None;
    }

    // SAFETY: AXUIElementCreateSystemWide returns a retained CF object.
    let system = from_create_rule(unsafe { AXUIElementCreateSystemWide() })?;
    // Bound IPC with an unresponsive target. Failure to set the timeout merely
    // leaves the API default in place and must not expose any user content.
    unsafe {
        AXUIElementSetMessagingTimeout(CFRetained::as_ptr(&system).as_ptr().cast(), 0.25);
    }

    let focused = copy_attribute(&system, "AXFocusedUIElement")?;
    let mut focused_pid = 0;
    // SAFETY: `focused` is retained and `focused_pid` is a valid out pointer.
    let pid_status = unsafe {
        AXUIElementGetPid(
            CFRetained::as_ptr(&focused).as_ptr().cast(),
            &mut focused_pid,
        )
    };
    if pid_status != AX_ERROR_SUCCESS || focused_pid != target.process_id {
        return None;
    }

    let selected = copy_attribute(&focused, "AXSelectedText")?;
    let selected = selected.downcast::<CFString>().ok()?;
    let selected_text = bounded_selection(&selected.to_string())?;

    Some(SelectionContext {
        selected_text,
        source_bundle_id: target.bundle_id.clone(),
        source_app_name: target.app_name.clone(),
        available: true,
    })
}

/// Verifies that the original target still owns the focused accessibility
/// element and that its current value ends with the text Pressay inserted.
/// Failing closed is intentional: rich editors that do not expose `AXValue`
/// receive a copied correction instead of an automatic undo.
#[cfg(target_os = "macos")]
pub fn verify_correction_target(target: &TargetApplication, expected_text: &str) -> bool {
    use objc2_core_foundation::{CFRetained, CFString, CFType};
    use std::ffi::c_void;
    use std::ptr::NonNull;

    type AXError = i32;
    const AX_ERROR_SUCCESS: AXError = 0;

    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        fn AXIsProcessTrusted() -> u8;
        fn AXUIElementCreateSystemWide() -> *mut c_void;
        fn AXUIElementCopyAttributeValue(
            element: *const c_void,
            attribute: *const CFString,
            value: *mut *mut c_void,
        ) -> AXError;
        fn AXUIElementGetPid(element: *const c_void, pid: *mut i32) -> AXError;
        fn AXUIElementSetMessagingTimeout(element: *const c_void, timeout: f32) -> AXError;
    }

    fn retained(pointer: *mut c_void) -> Option<CFRetained<CFType>> {
        let pointer = NonNull::new(pointer.cast::<CFType>())?;
        // SAFETY: AX Create/Copy functions return a retained object on success.
        Some(unsafe { CFRetained::from_raw(pointer) })
    }

    fn attribute(element: &CFRetained<CFType>, name: &'static str) -> Option<CFRetained<CFType>> {
        let attribute = CFString::from_static_str(name);
        let mut value = std::ptr::null_mut();
        // SAFETY: `element` and `attribute` remain retained for this call and
        // the initialized out pointer is owned by the caller on success.
        let status = unsafe {
            AXUIElementCopyAttributeValue(
                CFRetained::as_ptr(element).as_ptr().cast(),
                CFRetained::as_ptr(&attribute).as_ptr(),
                &mut value,
            )
        };
        (status == AX_ERROR_SUCCESS)
            .then(|| retained(value))
            .flatten()
    }

    if target.process_id <= 0
        || expected_text.trim().is_empty()
        || frontmost_application().is_none_or(|frontmost| {
            frontmost.bundle_id != target.bundle_id || frontmost.process_id != target.process_id
        })
    {
        return false;
    }
    // SAFETY: This parameterless trust query has no ownership side effects.
    if unsafe { AXIsProcessTrusted() } == 0 {
        return false;
    }
    // SAFETY: The system-wide element follows the Create rule.
    let Some(system) = retained(unsafe { AXUIElementCreateSystemWide() }) else {
        return false;
    };
    // Bound cross-process messaging so a hung editor cannot stall correction.
    unsafe {
        AXUIElementSetMessagingTimeout(CFRetained::as_ptr(&system).as_ptr().cast(), 0.25);
    }
    let Some(focused) = attribute(&system, "AXFocusedUIElement") else {
        return false;
    };
    let mut focused_pid = 0;
    // SAFETY: `focused` is retained and the PID out pointer is valid.
    if unsafe {
        AXUIElementGetPid(
            CFRetained::as_ptr(&focused).as_ptr().cast(),
            &mut focused_pid,
        )
    } != AX_ERROR_SUCCESS
        || focused_pid != target.process_id
    {
        return false;
    }

    if attribute(&focused, "AXSubrole")
        .and_then(|value| value.downcast::<CFString>().ok())
        .is_some_and(|subrole| subrole.to_string() == "AXSecureTextField")
    {
        return false;
    }

    attribute(&focused, "AXValue")
        .and_then(|value| value.downcast::<CFString>().ok())
        .is_some_and(|value| value_matches_expected(&value.to_string(), expected_text))
}

#[cfg(not(target_os = "macos"))]
pub fn capture_selected_text(_target: &TargetApplication) -> Option<SelectionContext> {
    None
}

#[cfg(not(target_os = "macos"))]
pub fn verify_correction_target(_target: &TargetApplication, _expected_text: &str) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_selection_is_not_exposed() {
        assert_eq!(bounded_selection("  \n"), None);
    }

    #[test]
    fn oversized_selection_is_bounded_on_character_boundaries() {
        let text = "é".repeat(MAX_SELECTION_CHARS + 5);
        let bounded = bounded_selection(&text).unwrap();

        assert_eq!(bounded.chars().count(), MAX_SELECTION_CHARS);
        assert!(bounded.chars().all(|character| character == 'é'));
    }

    #[test]
    fn correction_verification_requires_the_inserted_text_at_the_end() {
        assert!(value_matches_expected(
            "Before. Corrected text",
            "Corrected text"
        ));
        assert!(!value_matches_expected(
            "Before. Corrected text ",
            "Corrected text"
        ));
        assert!(!value_matches_expected(
            "Corrected text then typed",
            "Corrected text"
        ));
        assert!(!value_matches_expected("Anything", "  "));
    }
}
