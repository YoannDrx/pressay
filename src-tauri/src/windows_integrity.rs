//! Windows integrity levels (UIPI). A process cannot send simulated input to a
//! window owned by a process at a higher integrity level, typically an app
//! started with "Run as administrator", and `SendInput` reports no error when
//! that happens. Callers use this check to avoid a silent lost paste.

use windows::Win32::Foundation::{CloseHandle, ERROR_ACCESS_DENIED, HANDLE};
use windows::Win32::Security::{
    GetSidSubAuthority, GetSidSubAuthorityCount, GetTokenInformation, TokenIntegrityLevel,
    TOKEN_MANDATORY_LABEL, TOKEN_QUERY,
};
use windows::Win32::System::Threading::{
    GetCurrentProcess, OpenProcess, OpenProcessToken, PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

enum Integrity {
    Level(u32),
    /// The token could not be opened for query: the process outranks us.
    Inaccessible,
}

/// Integrity RID of a process token (`SECURITY_MANDATORY_*_RID`).
unsafe fn token_integrity(process: HANDLE) -> Option<Integrity> {
    let mut token = HANDLE::default();
    if let Err(error) = OpenProcessToken(process, TOKEN_QUERY, &mut token) {
        return (error.code() == ERROR_ACCESS_DENIED.to_hresult())
            .then_some(Integrity::Inaccessible);
    }
    let mut needed = 0u32;
    let _ = GetTokenInformation(token, TokenIntegrityLevel, None, 0, &mut needed);
    let mut buffer = vec![0u8; needed.max(1) as usize];
    let queried = GetTokenInformation(
        token,
        TokenIntegrityLevel,
        Some(buffer.as_mut_ptr().cast()),
        buffer.len() as u32,
        &mut needed,
    );
    let _ = CloseHandle(token);
    queried.ok()?;
    let label = &*(buffer.as_ptr() as *const TOKEN_MANDATORY_LABEL);
    let sid = label.Label.Sid;
    let count = *GetSidSubAuthorityCount(sid);
    if count == 0 {
        return None;
    }
    Some(Integrity::Level(*GetSidSubAuthority(
        sid,
        u32::from(count) - 1,
    )))
}

/// True when the foreground window belongs to a process Pressay cannot send
/// keystrokes to. Unknown cases return false so a paste is still attempted.
pub fn foreground_is_elevated() -> bool {
    // SAFETY: Win32 queries on handles owned and closed by this function.
    unsafe {
        let window = GetForegroundWindow();
        if window.is_invalid() {
            return false;
        }
        let mut process_id = 0u32;
        GetWindowThreadProcessId(window, Some(&mut process_id as *mut u32));
        if process_id == 0 || process_id == std::process::id() {
            return false;
        }
        let Ok(target) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id) else {
            return false;
        };
        let target_integrity = token_integrity(target);
        let _ = CloseHandle(target);
        match (target_integrity, token_integrity(GetCurrentProcess())) {
            (Some(Integrity::Inaccessible), Some(Integrity::Level(own))) => {
                // High-integrity Pressay can open anything a user can start.
                own < 0x3000
            }
            (Some(Integrity::Level(target)), Some(Integrity::Level(own))) => target > own,
            _ => false,
        }
    }
}
