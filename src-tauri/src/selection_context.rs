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

/// UI Automation, the Windows counterpart of the macOS AX queries above. The
/// same rules apply: the focused element must belong to the target process,
/// password fields are never read, and any failure exposes nothing.
#[cfg(target_os = "windows")]
mod uia {
    use windows::core::Interface;
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
    };
    use windows::Win32::UI::Accessibility::{
        CUIAutomation, IUIAutomation, IUIAutomationElement, IUIAutomationTextPattern,
        IUIAutomationValuePattern, UIA_TextPatternId, UIA_ValuePatternId,
    };

    /// Focused element of `process_id`, unless it is a password field.
    pub fn focused_element(process_id: i32) -> Option<IUIAutomationElement> {
        if process_id <= 0 {
            return None;
        }
        // SAFETY: COM calls on interfaces owned by this function. A thread that
        // already joined another apartment keeps it; UIA works from both.
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            let automation: IUIAutomation =
                CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER).ok()?;
            let focused = automation.GetFocusedElement().ok()?;
            if focused.CurrentProcessId().ok()? != process_id
                || focused.CurrentIsPassword().ok()?.as_bool()
            {
                return None;
            }
            Some(focused)
        }
    }

    fn pattern<T: Interface>(
        element: &IUIAutomationElement,
        id: windows::Win32::UI::Accessibility::UIA_PATTERN_ID,
    ) -> Option<T> {
        // SAFETY: `element` is a live UIA element.
        unsafe { element.GetCurrentPatternAs::<T>(id) }.ok()
    }

    pub fn selected_text(element: &IUIAutomationElement, max_chars: usize) -> Option<String> {
        let text_pattern: IUIAutomationTextPattern = pattern(element, UIA_TextPatternId)?;
        // SAFETY: COM calls on live interfaces.
        unsafe {
            let ranges = text_pattern.GetSelection().ok()?;
            let mut selected = String::new();
            for index in 0..ranges.Length().ok()? {
                let range = ranges.GetElement(index).ok()?;
                selected.push_str(&range.GetText(max_chars as i32).ok()?.to_string());
            }
            Some(selected)
        }
    }

    /// The element's whole value: ValuePattern for plain fields, else the
    /// TextPattern document for rich editors.
    pub fn current_value(element: &IUIAutomationElement) -> Option<String> {
        if let Some(value) = pattern::<IUIAutomationValuePattern>(element, UIA_ValuePatternId) {
            // SAFETY: COM call on a live interface.
            if let Ok(value) = unsafe { value.CurrentValue() } {
                return Some(value.to_string());
            }
        }
        let text_pattern: IUIAutomationTextPattern = pattern(element, UIA_TextPatternId)?;
        // SAFETY: COM calls on live interfaces.
        unsafe {
            Some(
                text_pattern
                    .DocumentRange()
                    .ok()?
                    .GetText(-1)
                    .ok()?
                    .to_string(),
            )
        }
    }
}

#[cfg(target_os = "windows")]
pub fn capture_selected_text(target: &TargetApplication) -> Option<SelectionContext> {
    let focused = uia::focused_element(target.process_id)?;
    let selected = uia::selected_text(&focused, MAX_SELECTION_CHARS)?;
    let selected_text = bounded_selection(&selected)?;
    Some(SelectionContext {
        selected_text,
        source_bundle_id: target.bundle_id.clone(),
        source_app_name: target.app_name.clone(),
        available: true,
    })
}

/// Same contract as macOS: fail closed unless the target still owns focus and
/// its value ends with the text Pressay inserted.
#[cfg(target_os = "windows")]
pub fn verify_correction_target(target: &TargetApplication, expected_text: &str) -> bool {
    if expected_text.trim().is_empty()
        || frontmost_application().is_none_or(|frontmost| {
            frontmost.bundle_id != target.bundle_id || frontmost.process_id != target.process_id
        })
    {
        return false;
    }
    uia::focused_element(target.process_id)
        .and_then(|focused| uia::current_value(&focused))
        .is_some_and(|value| value_matches_expected(&value, expected_text))
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn capture_selected_text(_target: &TargetApplication) -> Option<SelectionContext> {
    None
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
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
