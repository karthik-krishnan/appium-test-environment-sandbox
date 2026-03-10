#!/usr/bin/env bash
# =============================================================================
# ci/setup-android-runner.sh
# =============================================================================
# Run ONCE on a fresh EC2 Linux instance (Ubuntu 22.04, m5.large or larger).
# Installs: Android SDK, emulator, Node.js, Appium, and GitHub Actions runner.
#
# Usage:
#   1. Launch EC2 instance (see README — CI Setup section for instance config)
#   2. SSH into the instance
#   3. bash setup-android-runner.sh <GITHUB_RUNNER_TOKEN>
#
# Get the runner token from:
#   GitHub repo → Settings → Actions → Runners → New self-hosted runner → Linux
# =============================================================================

set -euo pipefail

RUNNER_TOKEN="${1:-}"
GITHUB_REPO="https://github.com/karthik-krishnan/appium-test-environment-sandbox"
ANDROID_API="36"
ANDROID_SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;arm64-v8a"
ANDROID_HOME="$HOME/android-sdk"
RUNNER_DIR="$HOME/actions-runner"

info() { echo -e "\n\033[0;36m▶ $*\033[0m"; }
ok()   { echo -e "\033[0;32m  ✅  $*\033[0m"; }

if [ -z "$RUNNER_TOKEN" ]; then
  echo "Usage: bash setup-android-runner.sh <GITHUB_RUNNER_TOKEN>"
  echo ""
  echo "Get the token from:"
  echo "  GitHub repo → Settings → Actions → Runners → New self-hosted runner → Linux"
  exit 1
fi

# =============================================================================
info "Step 1/6 — System packages"
# =============================================================================
sudo apt-get update -qq
sudo apt-get install -y \
  curl wget unzip git openjdk-17-jdk \
  qemu-kvm libvirt-daemon-system \
  xvfb  # virtual display (emulator needs a display even in headless mode)

sudo usermod -aG kvm "$USER"
ok "Packages installed"

# Verify KVM is available
if [ -e /dev/kvm ]; then
  ok "KVM available (/dev/kvm exists)"
else
  echo "  ⚠️  /dev/kvm not found — emulator will run slowly without KVM"
  echo "     Ensure you launched an instance type that supports nested virtualisation"
  echo "     (m5.metal, c5.metal, or bare-metal instances)"
fi

# =============================================================================
info "Step 2/6 — Node.js"
# =============================================================================
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -qq
sudo apt-get install -y nodejs -qq
ok "Node.js $(node --version)"

# =============================================================================
info "Step 3/6 — Android SDK + Emulator"
# =============================================================================
mkdir -p "$ANDROID_HOME/cmdline-tools"

# Download Android command-line tools
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
wget -q "$CMDLINE_TOOLS_URL" -O /tmp/cmdline-tools.zip
unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
mv /tmp/cmdline-tools-extract/cmdline-tools/* "$ANDROID_HOME/cmdline-tools/latest/"
rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract

# Set up environment (also written to .bashrc for future sessions)
{
  echo "export ANDROID_HOME=$ANDROID_HOME"
  echo "export PATH=\$ANDROID_HOME/emulator:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
} >> "$HOME/.bashrc"

export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# Accept licences and install components
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses > /dev/null 2>&1 || true
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" \
  "emulator" \
  "platforms;android-${ANDROID_API}" \
  "${ANDROID_SYSTEM_IMAGE}" \
  > /dev/null

ok "Android SDK installed at $ANDROID_HOME"

# Pre-create AVD
echo "no" | avdmanager \
  --sdk_root="$ANDROID_HOME" \
  create avd \
  --name "CIDevice" \
  --package "${ANDROID_SYSTEM_IMAGE}" \
  --device "pixel_6" \
  --force > /dev/null

ok "AVD 'CIDevice' created"

# =============================================================================
info "Step 4/6 — Appium + UIAutomator2 driver"
# =============================================================================
npm install -g appium --silent
export APPIUM_HOME="$HOME/.appium"
appium driver install uiautomator2 2>&1 | tail -3
ok "Appium $(appium --version) with uiautomator2 installed"

# =============================================================================
info "Step 5/6 — GitHub Actions runner"
# =============================================================================
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download latest runner release
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest \
  | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
RUNNER_ARCH="linux-arm64"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

wget -q "$RUNNER_URL" -O runner.tar.gz
tar xzf runner.tar.gz
rm runner.tar.gz

# Configure runner (labels: self-hosted, linux, appium-android)
./config.sh \
  --url "$GITHUB_REPO" \
  --token "$RUNNER_TOKEN" \
  --name "appium-android-$(hostname)" \
  --labels "self-hosted,linux,appium-android" \
  --runnergroup "Default" \
  --unattended

ok "Runner configured"

# =============================================================================
info "Step 6/6 — Install runner as a systemd service (starts on reboot)"
# =============================================================================
sudo ./svc.sh install
sudo ./svc.sh start
ok "Runner service started"

# =============================================================================
echo ""
echo -e "\033[0;32m╔══════════════════════════════════════════════╗\033[0m"
echo -e "\033[0;32m║   ✅  Android runner setup complete!         ║\033[0m"
echo -e "\033[0;32m╚══════════════════════════════════════════════╝\033[0m"
echo ""
echo "  The runner 'appium-android-$(hostname)' is now registered."
echo "  It will appear in:"
echo "  GitHub → Settings → Actions → Runners"
echo ""
echo "  Labels applied: self-hosted, linux, appium-android"
echo "  These must match the 'runs-on' in .github/workflows/ci.yml"
echo ""
