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
  public const uint KEYUP = 0x2;
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
[Keys]::SetForegroundWindow($notepad.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
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
