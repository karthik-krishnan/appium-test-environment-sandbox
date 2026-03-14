#!/usr/bin/env bash
# =============================================================================
# local-setup.sh
# Starts the Android emulator, iOS Simulator, and Appium on macOS.
# Safe to run multiple times — skips anything already running.
#
# Required installs (one-time, done manually):
#   • Android Studio  →  https://developer.android.com/studio
#   • Xcode           →  Mac App Store
#   • Node.js         →  https://nodejs.org  (click the LTS .pkg button)
# =============================================================================

set -euo pipefail

APPIUM_PORT="${APPIUM_PORT:-4723}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
PID_FILE="${LOG_DIR}/appium-local.pids"
AVD_NAME="AppiumTestDevice"
ANDROID_API="36"
ANDROID_SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;arm64-v8a"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✅  $*${NC}"; }
err()  { echo -e "\n${RED}  ❌  $*${NC}\n"; }
warn() { echo -e "${YELLOW}  ⚠️   $*${NC}"; }
info() { echo -e "      $*"; }
step() { echo -e "\n${CYAN}▶ $*${NC}"; }

# =============================================================================
# STOP MODE  —  bash local-setup.sh stop
# =============================================================================
if [[ "${1:-}" == "stop" ]]; then
  echo "Stopping Appium and emulators..."
  lsof -ti tcp:${APPIUM_PORT} | xargs kill -9 2>/dev/null && echo "  Stopped Appium" || true
  [ -f "${PID_FILE}" ] && xargs kill 2>/dev/null < "${PID_FILE}" || true
  rm -f "${PID_FILE}" /tmp/ios-udid.txt
  echo "Done."
  exit 0
fi

# =============================================================================
# HEADER
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Mobile Test Environment — Local Setup      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Starting: Android emulator · iOS Simulator · Appium"
echo "  Please wait — this may take 2–5 minutes."
echo ""

# =============================================================================
# STEP 1 — Check required tools
# =============================================================================
step "Step 1/4 — Checking required tools"

# --- Node.js (needed for Appium) ---
if ! command -v node &>/dev/null; then
  err "Node.js is not installed."
  info "Please download and install it (click the big LTS button):"
  info ""
  info "  👉  https://nodejs.org"
  info ""
  info "After installing, open a new Terminal window and re-run this script."
  exit 1
fi
ok "Node.js $(node --version)"

# --- Android Studio SDK ---
# Search the standard locations Android Studio installs its SDK to
for candidate in \
    "${ANDROID_HOME:-__unset__}" \
    "$HOME/Library/Android/sdk" \
    "$HOME/Android/Sdk"; do
  [[ "${candidate}" == "__unset__" ]] && continue
  if [ -d "${candidate}/platform-tools" ]; then
    export ANDROID_HOME="${candidate}"
    export PATH="${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}"
    break
  fi
done

if ! command -v adb &>/dev/null; then
  err "Android Studio is not installed (or hasn't been opened yet)."
  info "Please install Android Studio and open it once so it can finish setup:"
  info ""
  info "  👉  https://developer.android.com/studio"
  info ""
  info "After it finishes, re-run this script."
  exit 1
fi
ok "Android Studio SDK found"

# --- Xcode ---
if ! command -v xcrun &>/dev/null; then
  err "Xcode is not installed."
  info "Install Xcode from the Mac App Store:"
  info ""
  info "  👉  Open the App Store and search for 'Xcode'"
  info ""
  info "After installing, open Xcode once to finish setup, then re-run this script."
  exit 1
fi
ok "Xcode found"

# =============================================================================
# STEP 2 — Android emulator
# =============================================================================
step "Step 2/4 — Android emulator"

if adb devices 2>/dev/null | grep -qE "emulator.*device$"; then
  RUNNING=$(adb devices | grep -E "emulator.*device$" | awk '{print $1}' | head -1)
  ok "Already running (${RUNNING})"
else
  # ── Auto-create AVD if none exists ─────────────────────────────────────────
  AVDS=$(emulator -list-avds 2>/dev/null || true)

  if [ -z "${AVDS}" ]; then
    echo "      No emulator found — creating one automatically..."

    # Download the system image if needed
    if ! sdkmanager --list_installed 2>/dev/null | grep -q "${ANDROID_SYSTEM_IMAGE}"; then
      echo "      Downloading Android ${ANDROID_API} system image (~1 GB)..."
      yes | sdkmanager --sdk_root="${ANDROID_HOME}" "${ANDROID_SYSTEM_IMAGE}" > /dev/null
    fi

    # Accept any pending SDK licences
    yes | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses > /dev/null 2>&1 || true

    # Create the AVD
    echo "no" | avdmanager \
      --sdk_root="${ANDROID_HOME}" \
      create avd \
      --name "${AVD_NAME}" \
      --package "${ANDROID_SYSTEM_IMAGE}" \
      --device "pixel_6" \
      --force > /dev/null

    ok "Created emulator: ${AVD_NAME}"
    AVDS="${AVD_NAME}"
  fi

  # ── Start the emulator ─────────────────────────────────────────────────────
  AVD="${ANDROID_AVD:-$(echo "${AVDS}" | head -1)}"
  echo "      Starting emulator: ${AVD}  (first boot takes 1–3 min)"

  nohup emulator \
    -avd "${AVD}" \
    -no-audio \
    -no-boot-anim \
    -no-snapshot-save \
    -gpu host \
    > "${LOG_DIR}/android-emulator.log" 2>&1 &
  echo "$!" >> "${PID_FILE}"

  echo -n "      Waiting for boot"
  MAX=300; ELAPSED=0
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    if [ "${ELAPSED}" -ge "${MAX}" ]; then
      err "Android emulator did not boot within 5 minutes."
      info "Check logs/android-emulator.log for details."
      exit 1
    fi
    echo -n "."; sleep 5; ELAPSED=$((ELAPSED + 5))
  done
  echo ""

  # Disable animations (makes tests faster and more reliable)
  adb shell settings put global window_animation_scale 0.0 2>/dev/null || true
  adb shell settings put global transition_animation_scale 0.0 2>/dev/null || true
  adb shell settings put global animator_duration_scale 0.0 2>/dev/null || true
  adb shell input keyevent 82 2>/dev/null || true

  ok "Android emulator ready"
fi

# =============================================================================
# STEP 3 — iOS Simulator
# =============================================================================
step "Step 3/4 — iOS Simulator"

BOOTED_UDID=$(xcrun simctl list devices booted 2>/dev/null \
  | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1 || true)

if [ -n "${BOOTED_UDID}" ]; then
  BOOTED_NAME=$(xcrun simctl list devices booted 2>/dev/null \
    | grep "${BOOTED_UDID}" | sed 's/ (.*//' | xargs)
  echo "${BOOTED_UDID}" > /tmp/ios-udid.txt
  ok "Already running: ${BOOTED_NAME}"
else
  # Find the best available iPhone simulator — prefer recent models
  SIM_UDID=""
  for NAME in "iPhone 16" "iPhone 15 Pro" "iPhone 15" "iPhone 14" "iPhone 13"; do
    SIM_UDID=$(xcrun simctl list devices available 2>/dev/null \
      | grep "${NAME}" \
      | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' \
      | head -1 || true)
    [ -n "${SIM_UDID}" ] && { SIM_NAME="${NAME}"; break; }
  done

  if [ -z "${SIM_UDID}" ]; then
    # Last resort — any iPhone
    SIM_LINE=$(xcrun simctl list devices available 2>/dev/null | grep "iPhone" | tail -1)
    SIM_UDID=$(echo "${SIM_LINE}" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)
    SIM_NAME=$(echo "${SIM_LINE}" | sed 's/ (.*//' | xargs)
  fi

  if [ -z "${SIM_UDID}" ]; then
    warn "No iPhone simulator found — skipping iOS."
    info "To add one: open Xcode → Window → Devices and Simulators → + (bottom-left)"
  else
    echo "      Booting: ${SIM_NAME}"
    xcrun simctl boot "${SIM_UDID}" 2>/dev/null || true
    open -a Simulator 2>/dev/null || true

    echo -n "      Waiting for boot"
    MAX=90; ELAPSED=0
    until xcrun simctl list devices booted 2>/dev/null | grep -q "${SIM_UDID}"; do
      if [ "${ELAPSED}" -ge "${MAX}" ]; then warn "Boot timed out — continuing"; break; fi
      echo -n "."; sleep 3; ELAPSED=$((ELAPSED + 3))
    done
    echo ""

    echo "${SIM_UDID}" > /tmp/ios-udid.txt
    ok "iOS Simulator ready: ${SIM_NAME}"
  fi
fi

# =============================================================================
# STEP 4 — Appium
# =============================================================================
step "Step 4/4 — Appium"

if curl -sf "http://localhost:${APPIUM_PORT}/status" 2>/dev/null | grep -q '"ready":true'; then
  ok "Already running on port ${APPIUM_PORT}"
else
  # Install Appium if missing
  if ! command -v appium &>/dev/null; then
    echo "      Installing Appium (one-time, ~1 minute)..."
    npm install -g appium --silent
  fi

  # Install device drivers if missing.
  # Use 2>&1 so we capture Appium's output regardless of whether it goes to
  # stdout or stderr (varies by Appium version / TTY detection).
  # The || true guards against "already installed" non-zero exits that would
  # otherwise trip set -euo pipefail and kill the script prematurely.
  if ! appium driver list --installed 2>&1 | grep -qi "uiautomator2"; then
    echo "      Installing Android driver..."
    appium driver install uiautomator2 2>&1 || true
  fi
  if ! appium driver list --installed 2>&1 | grep -qi "xcuitest"; then
    echo "      Installing iOS driver..."
    appium driver install xcuitest 2>&1 || true
  fi

  # Export APPIUM_HOME so the nohup'd Appium server finds the installed drivers.
  # If APPIUM_HOME isn't set, Appium defaults to ~/.appium — make that explicit
  # so the background process inherits the same location the installs used.
  export APPIUM_HOME="${APPIUM_HOME:-$HOME/.appium}"

  nohup appium \
    --port "${APPIUM_PORT}" \
    --address 127.0.0.1 \
    --base-path / \
    --relaxed-security \
    --log-timestamp \
    > "${LOG_DIR}/appium.log" 2>&1 &
  echo "$!" >> "${PID_FILE}"

  echo -n "      Starting Appium"
  MAX=30; ELAPSED=0
  until curl -sf "http://localhost:${APPIUM_PORT}/status" 2>/dev/null | grep -q '"ready":true'; do
    if [ "${ELAPSED}" -ge "${MAX}" ]; then
      err "Appium failed to start."
      info "Check logs/appium.log for details."
      exit 1
    fi
    echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2))
  done
  echo ""
  ok "Appium ready"
fi

# =============================================================================
# DONE
# =============================================================================
IOS_UDID=$(cat /tmp/ios-udid.txt 2>/dev/null || echo "not started")
ANDROID_DEV=$(adb devices 2>/dev/null | grep -E "emulator.*device$" | awk '{print $1}' | head -1 || echo "not started")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅  Everything is ready!                   ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
printf "${GREEN}║   Appium:   http://localhost:%-16s║${NC}\n" "${APPIUM_PORT}"
printf "${GREEN}║   Android:  %-32s║${NC}\n" "${ANDROID_DEV}"
printf "${GREEN}║   iOS UDID: %-32s║${NC}\n" "${IOS_UDID:0:32}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  ▶  Run Android tests:   cd tests && npm run test:android"
echo "  ▶  Run iOS tests:       cd tests && npm run test:ios"
echo "  ■  Stop everything:     bash local-setup.sh stop"
echo ""
