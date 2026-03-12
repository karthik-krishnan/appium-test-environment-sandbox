# =============================================================================
# local-setup.ps1
# Starts the Android emulator and Appium on Windows.
# Safe to run multiple times - skips anything already running.
#
# Required installs (one-time, done manually):
#   - Android Studio  ->  https://developer.android.com/studio
#   - Node.js         ->  https://nodejs.org  (click the LTS button)
#
# Note: iOS Simulator is macOS only and is not supported on Windows.
#
# Usage:
#   .\local-setup.ps1           # start everything
#   .\local-setup.ps1 stop      # stop Appium and emulator
# =============================================================================

param(
    [string]$Command = ""
)

$ErrorActionPreference = "Stop"

$APPIUM_PORT  = if ($env:APPIUM_PORT) { $env:APPIUM_PORT } else { "4723" }
$PID_FILE     = "$env:TEMP\appium-local-pids.txt"
$AVD_NAME     = "AppiumTestDevice"
$ANDROID_API  = "36"
$SYSTEM_IMAGE = "system-images;android-${ANDROID_API};google_apis;x86_64"

# -- Colours ------------------------------------------------------------------
function Write-Ok   { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Err  { param($msg) Write-Host "`n  [ERR]  $msg`n" -ForegroundColor Red }
function Write-Warn { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "         $msg" }
function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }

# =============================================================================
# STOP MODE  -  .\local-setup.ps1 stop
# =============================================================================
if ($Command -eq "stop") {
    Write-Host "Stopping Appium and emulator..."

    # Kill Appium by port
    $conn = Get-NetTCPConnection -LocalPort ([int]$APPIUM_PORT) -ErrorAction SilentlyContinue
    if ($conn) {
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped Appium"
    }

    # Kill processes from PID file
    if (Test-Path $PID_FILE) {
        Get-Content $PID_FILE | ForEach-Object {
            Stop-Process -Id ([int]$_) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $PID_FILE -Force
    }

    # Kill any lingering emulator process
    Get-Process -Name "qemu-system-x86_64", "emulator" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "Done."
    exit 0
}

# =============================================================================
# HEADER
# =============================================================================
Clear-Host
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Mobile Test Environment - Local Setup        " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Starting: Android emulator + Appium"
Write-Host "  Please wait - this may take 2-5 minutes."
Write-Host ""

# =============================================================================
# STEP 1 - Check required tools
# =============================================================================
Write-Step "Step 1/3 - Checking required tools"

# -- Node.js --
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Err "Node.js is not installed."
    Write-Info "Please download and install it (click the big LTS button):"
    Write-Info ""
    Write-Info "  https://nodejs.org"
    Write-Info ""
    Write-Info "After installing, open a new PowerShell window and re-run this script."
    exit 1
}
Write-Ok "Node.js $(node --version)"

# -- Android SDK --
# Search standard locations Android Studio installs to on Windows
$sdkCandidates = @(
    $env:ANDROID_HOME,
    "$env:LOCALAPPDATA\Android\Sdk",
    "$env:USERPROFILE\AppData\Local\Android\Sdk",
    "C:\sdk",
    "C:\Android\Sdk",
    "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk"
)

$ANDROID_HOME = $null
foreach ($candidate in $sdkCandidates) {
    if ($candidate -and (Test-Path (Join-Path $candidate "platform-tools"))) {
        $ANDROID_HOME = $candidate
        break
    }
}

if (-not $ANDROID_HOME) {
    Write-Err "Android Studio SDK not found."
    Write-Info "Please install Android Studio and open it once so it can finish setup:"
    Write-Info ""
    Write-Info "  https://developer.android.com/studio"
    Write-Info ""
    Write-Info "After it finishes, re-run this script."
    exit 1
}

$env:ANDROID_HOME     = $ANDROID_HOME
$env:ANDROID_SDK_ROOT = $ANDROID_HOME
$emulatorDir          = Join-Path $ANDROID_HOME "emulator"
$platformToolsDir     = Join-Path $ANDROID_HOME "platform-tools"
$cmdlineToolsDir      = Join-Path $ANDROID_HOME "cmdline-tools\latest\bin"
$env:Path             = "$emulatorDir;$platformToolsDir;$cmdlineToolsDir;$env:Path"

Write-Ok "Android Studio SDK found at $ANDROID_HOME"

# =============================================================================
# STEP 2 - Android emulator
# =============================================================================
Write-Step "Step 2/3 - Android emulator"

$adbDevices     = & adb devices 2>$null
$alreadyRunning = $adbDevices | Select-String "emulator.*device$"

if ($alreadyRunning) {
    $runningDevice = (($alreadyRunning | Select-Object -First 1) -split "`t")[0].Trim()
    Write-Ok "Already running ($runningDevice)"
} else {
    # -- Auto-create AVD if none exists ---------------------------------------
    $avds = & emulator -list-avds 2>$null

    if (-not $avds) {
        Write-Info "No emulator found - creating one automatically..."

        # Download the system image if needed
        $installed = & sdkmanager --list_installed 2>$null
        if (-not ($installed | Select-String ([regex]::Escape($SYSTEM_IMAGE)))) {
            Write-Info "Downloading Android $ANDROID_API system image (~1 GB)..."
            "y" | & sdkmanager --sdk_root="$ANDROID_HOME" $SYSTEM_IMAGE | Out-Null
        }

        # Accept any pending SDK licences
        "y" * 20 | & sdkmanager --sdk_root="$ANDROID_HOME" --licenses 2>$null | Out-Null

        # Create the AVD
        "no" | & avdmanager create avd `
            --name $AVD_NAME `
            --package $SYSTEM_IMAGE `
            --device "pixel_6" `
            --force | Out-Null

        Write-Ok "Created emulator: $AVD_NAME"
        $avds = $AVD_NAME
    }

    # -- Start the emulator ---------------------------------------------------
    $avd         = if ($env:ANDROID_AVD) { $env:ANDROID_AVD } else { ($avds | Select-Object -First 1).Trim() }
    $emulatorExe = Join-Path $ANDROID_HOME "emulator\emulator.exe"
    $emulatorLog = "$env:TEMP\android-emulator.log"
    $emulatorErr = "$env:TEMP\android-emulator-err.log"

    Write-Info "Starting emulator: $avd  (first boot takes 1-3 min)"

    $emulatorProc = Start-Process `
        -FilePath $emulatorExe `
        -ArgumentList "-avd", $avd, "-no-audio", "-no-boot-anim", "-no-snapshot-save", "-gpu", "host" `
        -RedirectStandardOutput $emulatorLog `
        -RedirectStandardError  $emulatorErr `
        -PassThru `
        -WindowStyle Hidden

    Add-Content -Path $PID_FILE -Value $emulatorProc.Id

    Write-Host -NoNewline "         Waiting for boot"
    $max = 300; $elapsed = 0
    while ($true) {
        $booted = & adb shell getprop sys.boot_completed 2>$null
        if ($booted -match "1") { break }
        if ($elapsed -ge $max) {
            Write-Err "Android emulator did not boot within 5 minutes."
            Write-Info "Check $emulatorLog for details."
            exit 1
        }
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    Write-Host ""

    # Disable animations (makes tests faster and more reliable)
    & adb shell settings put global window_animation_scale    0.0 2>$null | Out-Null
    & adb shell settings put global transition_animation_scale 0.0 2>$null | Out-Null
    & adb shell settings put global animator_duration_scale   0.0 2>$null | Out-Null
    & adb shell input keyevent 82 2>$null | Out-Null

    Write-Ok "Android emulator ready"
}

# =============================================================================
# STEP 3 - Appium
# =============================================================================
Write-Step "Step 3/3 - Appium"

$appiumReady = $false
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:${APPIUM_PORT}/status" `
        -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
    if ($resp.Content -match '"ready":true') { $appiumReady = $true }
} catch {}

if ($appiumReady) {
    Write-Ok "Already running on port $APPIUM_PORT"
} else {
    # Install Appium if missing
    if (-not (Get-Command appium -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Appium (one-time, ~1 minute)..."
        & npm install -g appium --silent
    }

    # Set APPIUM_HOME so the server finds installed drivers
    if (-not $env:APPIUM_HOME) {
        $env:APPIUM_HOME = Join-Path $env:USERPROFILE ".appium"
    }

    # Install UIAutomator2 driver if missing
    $driverList = & appium driver list --installed 2>&1
    if (-not ($driverList | Select-String "uiautomator2")) {
        Write-Info "Installing Android driver..."
        & appium driver install uiautomator2 2>&1 | Out-Null
    }

    # Start Appium
    $appiumLog = "$env:TEMP\appium.log"
    $appiumErr = "$env:TEMP\appium-err.log"

    $appiumProc = Start-Process `
        -FilePath "appium" `
        -ArgumentList "--port", $APPIUM_PORT, "--address", "127.0.0.1", `
                      "--base-path", "/", "--relaxed-security", "--log-timestamp" `
        -RedirectStandardOutput $appiumLog `
        -RedirectStandardError  $appiumErr `
        -PassThru `
        -WindowStyle Hidden

    Add-Content -Path $PID_FILE -Value $appiumProc.Id

    Write-Host -NoNewline "         Starting Appium"
    $max = 30; $elapsed = 0
    while ($true) {
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:${APPIUM_PORT}/status" `
                -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($resp.Content -match '"ready":true') { break }
        } catch {}
        if ($elapsed -ge $max) {
            Write-Err "Appium failed to start."
            Write-Info "Check $appiumLog for details."
            exit 1
        }
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host ""
    Write-Ok "Appium ready"
}

# =============================================================================
# DONE
# =============================================================================
$androidDev = (& adb devices 2>$null |
    Select-String "emulator.*device$" |
    Select-Object -First 1) -replace "`t.*", ""
if (-not $androidDev) { $androidDev = "not started" }

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   [OK]  Everything is ready!                   " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ("   Appium:   http://localhost:{0}" -f $APPIUM_PORT) -ForegroundColor Green
Write-Host ("   Android:  {0}" -f $androidDev) -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Run Android tests:  cd tests; npm run test:android"
Write-Host "  Stop everything:    .\local-setup.ps1 stop"
Write-Host ""
