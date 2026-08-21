#[cfg(target_os = "macos")]
use std::process::Command;

#[cfg(target_os = "macos")]
const IOREG_PATH: &str = "/usr/sbin/ioreg";
#[cfg(target_os = "macos")]
const PMSET_PATH: &str = "/usr/bin/pmset";

#[cfg(target_os = "macos")]
fn output_reports_closed_lid(output: &str) -> bool {
    output.contains("\"AppleClamshellState\" = Yes")
}

#[cfg(target_os = "macos")]
fn output_reports_internal_battery(output: &str) -> bool {
    output.contains("InternalBattery")
}

/// Checks if the MacBook is in clamshell mode (lid closed with external display)
///
/// This queries the macOS IORegistry for the AppleClamshellState key.
/// Returns true if the lid is closed, false if open.
#[cfg(target_os = "macos")]
pub fn is_clamshell() -> Result<bool, String> {
    // GUI applications do not inherit an interactive shell PATH. Resolve the
    // macOS system tool explicitly so clamshell detection works in signed apps
    // as well as a developer terminal.
    let output = Command::new(IOREG_PATH)
        .args(["-r", "-k", "AppleClamshellState", "-d", "4"])
        .output()
        .map_err(|e| format!("Failed to execute ioreg: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "ioreg command failed with status: {}",
            output.status
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    Ok(output_reports_closed_lid(&stdout))
}

/// Checks if the Mac is a laptop by detecting battery presence
///
/// This uses pmset to check for battery information.
/// Returns true if a battery is detected (laptop), false otherwise (desktop)
#[cfg(target_os = "macos")]
#[tauri::command]
#[specta::specta]
pub fn is_laptop() -> Result<bool, String> {
    let output = Command::new(PMSET_PATH)
        .arg("-g")
        .arg("batt")
        .output()
        .map_err(|e| e.to_string())?;

    if !output.status.success() {
        return Err(format!(
            "pmset command failed with status: {}",
            output.status
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Check if InternalBattery is present (laptops have batteries, desktops typically don't)
    Ok(output_reports_internal_battery(&stdout))
}

/// Stub implementation for non-macOS platforms
/// Always returns false since clamshell mode is macOS-specific
#[cfg(not(target_os = "macos"))]
pub fn is_clamshell() -> Result<bool, String> {
    Ok(false)
}

/// Stub implementation for non-macOS platforms
/// Always returns false since laptop detection is macOS-specific
#[cfg(not(target_os = "macos"))]
#[tauri::command]
#[specta::specta]
pub fn is_laptop() -> Result<bool, String> {
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_os = "macos")]
    fn parses_clamshell_state_without_relying_on_machine_state() {
        assert!(output_reports_closed_lid(
            "| |   \"AppleClamshellState\" = Yes"
        ));
        assert!(!output_reports_closed_lid(
            "| |   \"AppleClamshellState\" = No"
        ));
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn parses_internal_battery_without_relying_on_machine_state() {
        assert!(output_reports_internal_battery(
            "Now drawing from 'Battery Power'\n -InternalBattery-0"
        ));
        assert!(!output_reports_internal_battery("AC Power"));
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn macos_power_tools_use_stable_system_paths() {
        assert!(std::path::Path::new(IOREG_PATH).is_file());
        assert!(std::path::Path::new(PMSET_PATH).is_file());
    }
}
