# End-to-end dictation on Windows with the published installer: a virtual
# microphone (VB-CABLE) receives a spoken sentence while the global shortcut
# (held Ctrl+Win) records it, and the transcript must be pasted into Notepad.
# Runs in Windows PowerShell 5.1 for System.Speech and UI Automation.
param(
  [Parameter(Mandatory = $true)] [string] $Tag,
  [Parameter(Mandatory = $true)] [string] $OutDir
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$work = Join-Path $env:RUNNER_TEMP "pressay-dictation"
New-Item -ItemType Directory -Force $work | Out-Null

Add-Type -AssemblyName System.Speech, UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Keys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, System.Text.StringBuilder lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
  public const uint KEYUP = 0x2;
  // Windows only lets the foreground process hand focus over; a tapped Alt
  // key lifts that lock for the next SetForegroundWindow call.
  public static bool Focus(IntPtr window) {
    // An Alt tap in a window that already has focus would open its menu.
    if (GetForegroundWindow() == window) return true;
    keybd_event(0x12, 0, 0, UIntPtr.Zero);
    keybd_event(0x12, 0, KEYUP, UIntPtr.Zero);
    SetForegroundWindow(window);
    System.Threading.Thread.Sleep(300);
    return GetForegroundWindow() == window;
  }
  public static string EditText(IntPtr window) {
    IntPtr edit = FindWindowEx(window, IntPtr.Zero, "Edit", null);
    if (edit == IntPtr.Zero) edit = FindWindowEx(window, IntPtr.Zero, "RichEditD2DPT", null);
    if (edit == IntPtr.Zero) return null;
    int length = (int)SendMessage(edit, 0x000E, IntPtr.Zero, IntPtr.Zero);
    var text = new System.Text.StringBuilder(length + 1);
    SendMessage(edit, 0x000D, (IntPtr)(length + 1), text);
    return text.ToString();
  }
}
"@

function Save-Screenshot([string] $Name) {
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save((Join-Path $OutDir "$Name.png"))
  $graphics.Dispose(); $bitmap.Dispose()
}

# 1. The published installer, checked against its release checksum.
$ErrorActionPreference = 'Continue'
& gh release download $Tag --repo YoannDrx/pressay --pattern "Pressay-windows-x64.exe*" --dir $work --clobber
$ErrorActionPreference = 'Stop'
$installer = Join-Path $work "Pressay-windows-x64.exe"
$expected = ((Get-Content "$installer.sha256" -Raw).Trim() -split '\s+')[0]
if ((Get-FileHash $installer -Algorithm SHA256).Hash.ToLower() -ne $expected) { throw "Installer checksum mismatch" }

$dir = Join-Path $work "app"
$proc = Start-Process -FilePath $installer -ArgumentList @("/S", "/PORTABLE", "/D=$dir") -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "Install failed: $($proc.ExitCode)" }
$app = (Get-ChildItem $dir -Filter "pressay.exe" -Recurse | Select-Object -First 1).FullName
$data = Join-Path (Split-Path $app) "Data"

# 2. Parakeet V3, the Windows default, downloaded and hash-checked.
$catalog = Get-Content "src-tauri/src/catalog/catalog.json" -Raw | ConvertFrom-Json
$file = ($catalog.models | Where-Object { $_.id -eq "pressay/parakeet-v3" }).files[0]
$models = Join-Path $data "models"
New-Item -ItemType Directory -Force $models | Out-Null
$modelPath = Join-Path $models $file.filename
& curl.exe -sSL --fail --retry 3 -o $modelPath "https://models.press-say.app/pressay/parakeet-v3/v1/$($file.filename)"
if ($LASTEXITCODE -ne 0) { throw "Model download failed" }
if ((Get-FileHash $modelPath -Algorithm SHA256).Hash.ToLower() -ne $file.sha256) { throw "Model hash mismatch" }

# 3. A returning user: onboarding done, Parakeet selected, no feedback sound
#    (it would be recorded through the virtual cable).
$settings = @{ settings = @{
  onboarding_completed = $true
  selected_model = "pressay/parakeet-v3/$($file.filename)"
  selected_language = "en"
  audio_feedback = $false
  update_checks_enabled = $false
} }
# Windows PowerShell's UTF8 encoding writes a BOM, which the store rejects.
[System.IO.File]::WriteAllText((Join-Path $data "settings_store.json"), ($settings | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

# 4. The sentence, 16 kHz mono like a dictation.
$wav = Join-Path $work "sentence.wav"
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$voice.SetOutputToWaveFile($wav, $format)
$voice.Speak("Please send the quarterly report to the whole team before Friday morning.")
$voice.Dispose()

# 5. Start Pressay in the tray, then focus an empty Notepad.
$pressay = Start-Process -FilePath $app -ArgumentList "--start-hidden" -PassThru
Start-Sleep -Seconds 20
if ($pressay.HasExited) { throw "Pressay exited during startup ($($pressay.ExitCode))" }
$notepad = Start-Process notepad.exe -PassThru
Start-Sleep -Seconds 3
$notepad.Refresh()
if (-not [Keys]::Focus($notepad.MainWindowHandle)) { throw "Could not bring Notepad to the front" }
Save-Screenshot "before-dictation"

# 6. Hold Ctrl+Win, play the sentence into the virtual microphone, release.
$VK_LCONTROL = 0xA2; $VK_LWIN = 0x5B
[Keys]::keybd_event($VK_LCONTROL, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[Keys]::keybd_event($VK_LWIN, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 900
$player = New-Object System.Media.SoundPlayer $wav
$player.Play()
Start-Sleep -Seconds 1
Save-Screenshot "recording"
Start-Sleep -Seconds 4
Start-Sleep -Milliseconds 600
[Keys]::keybd_event($VK_LWIN, 0, [Keys]::KEYUP, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[Keys]::keybd_event($VK_LCONTROL, 0, [Keys]::KEYUP, [UIntPtr]::Zero)

# 7. Read Notepad through UI Automation until the transcript lands.
$root = [System.Windows.Automation.AutomationElement]::FromHandle($notepad.MainWindowHandle)
$isText = New-Object System.Windows.Automation.OrCondition(
  (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)),
  (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)))
$text = ""
for ($i = 0; $i -lt 30 -and $text.Trim() -eq ""; $i++) {
  Start-Sleep -Seconds 1
  # The classic Edit control answers WM_GETTEXT; UI Automation covers the rest.
  $direct = [Keys]::EditText($notepad.MainWindowHandle)
  if ($direct) { $text = $direct; break }
  $editor = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $isText)
  if ($editor) {
    try {
      $text = $editor.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    } catch {
      $text = $editor.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
    }
  }
}
Save-Screenshot "after-dictation"
Write-Host "Pasted into Notepad: $text"
Set-Content (Join-Path $OutDir "pasted.txt") $text

Stop-Process -Id $notepad.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $pressay.Id -Force -ErrorAction SilentlyContinue
$logs = Join-Path $data "logs"
if (Test-Path $logs) { Copy-Item $logs (Join-Path $OutDir "logs") -Recurse -Force }

foreach ($word in @("report", "team", "friday")) {
  if ($text -notmatch "(?i)\b$word\b") { throw "Notepad does not contain '$word' after the dictation" }
}
Write-Host "Dictation end to end: shortcut, microphone, transcription and paste all worked."

# 8. Administrator target: Pressay at normal (medium) integrity, Notepad
#    elevated like this runner shell. Windows would drop the simulated Ctrl+V,
#    so Pressay must leave the transcript on the clipboard instead. The
#    global hook cannot see keys aimed at an elevated window either, so the
#    dictation is driven by the --toggle-transcription remote control.
Start-Sleep -Seconds 2
Set-Clipboard -Value "clipboard before dictation"
$elevated = Start-Process notepad.exe -PassThru
Start-Sleep -Seconds 3
$elevated.Refresh()
# The folder was created by the elevated shell; a restricted token sees the
# Administrators group as deny-only, so grant the user itself.
& icacls.exe $dir /grant "$($env:USERDOMAIN)\$($env:USERNAME):(OI)(CI)F" /T /Q | Out-Null
# UAC is off on this runner, so runas /trustlevel keeps high integrity. A
# medium mandatory label on the executable starts Pressay at medium instead.
& icacls.exe $app /setintegritylevel medium | Out-Null
Start-Process -FilePath $app -ArgumentList "--start-hidden" | Out-Null
Start-Sleep -Seconds 20
$restricted = Get-Process pressay -ErrorAction SilentlyContinue
if (-not $restricted) {
  if (Test-Path $logs) { Get-Content (Get-ChildItem $logs -File | Select-Object -First 1).FullName -Tail 20 | Write-Host }
  throw "Pressay did not start at medium integrity"
}
Write-Host "Restricted Pressay running: pid $($restricted.Id)"
$label = & whoami.exe /groups | Select-String "Mandatory Label"
Write-Host "Shell integrity: $label"
& icacls.exe $app | Select-String "Mandatory" | ForEach-Object { Write-Host "Executable label: $_" }
Start-Process -FilePath $app -ArgumentList "--toggle-transcription" -Wait
Start-Sleep -Milliseconds 1500
(New-Object System.Media.SoundPlayer $wav).PlaySync()
Start-Sleep -Milliseconds 600
Start-Process -FilePath $app -ArgumentList "--toggle-transcription" -Wait
# Keep the elevated Notepad in front while the transcript is produced, and
# leave the clipboard alone until Pressay has had time to act.
for ($i = 0; $i -lt 8; $i++) {
  if (-not [Keys]::Focus($elevated.MainWindowHandle)) { Write-Host "Notepad not in front yet" }
  Start-Sleep -Milliseconds 500
}
if ([Keys]::GetForegroundWindow() -ne $elevated.MainWindowHandle) { throw "Could not bring the elevated Notepad to the front" }
Start-Sleep -Seconds 4
$clipboard = (Get-Clipboard -Raw) -as [string]
Save-Screenshot "administrator-target"
$elevatedText = [Keys]::EditText($elevated.MainWindowHandle)
Write-Host "Elevated Notepad: '$elevatedText'"
Write-Host "Clipboard: '$clipboard'"
Get-Process pressay -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Process -Id $elevated.Id -Force -ErrorAction SilentlyContinue
if (Test-Path $logs) { Copy-Item $logs (Join-Path $OutDir "logs-administrator") -Recurse -Force }
if ($clipboard -notmatch "(?i)\breport\b") { throw "The transcript was not left on the clipboard for the elevated window" }
if ($elevatedText -match "(?i)report") { throw "Pressay pasted into an elevated window it should not reach" }
Write-Host "Administrator target: transcript kept on the clipboard, nothing lost."
