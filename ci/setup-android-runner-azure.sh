#!/usr/bin/env bash
# =============================================================================
# ci/setup-android-runner-azure.sh
# =============================================================================
# Sets up an Azure VM as a GitHub Actions self-hosted runner
# for Android Appium tests.
#
# STEP 1 — Create the Azure VM (run from your local machine, once):
#
#   az group create \
#     --name appium-runner-rg \
#     --location eastus
#
#   az vm create \
#     --resource-group appium-runner-rg \
#     --name appium-android-runner \
#     --image Ubuntu2204 \
#     --size Standard_D4s_v3 \
#     --admin-username azureuser \
#     --generate-ssh-keys \
#     --os-disk-size-gb 60
#
#   Notes:
#   - Standard_D4s_v3 and higher v3/v4/v5 series VMs support nested
#     virtualization, which is required for the Android emulator
#   - Requires Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
#
# STEP 2 — SSH in and run this script:
#
#   az vm show -d -g appium-runner-rg -n appium-android-runner --query publicIps -o tsv
#   ssh azureuser@<PUBLIC_IP>
#   bash setup-android-runner-azure.sh <GITHUB_RUNNER_TOKEN>
#
# Get the runner token from:
#   GitHub repo → Settings → Actions → Runners → New self-hosted runner → Linux
# =============================================================================

set -euo pipefail

RUNNER_TOKEN="${1:-}"
GITHUB_REPO="https://github.com/karthik-krishnan/mobile-test-automation-starter"
ANDROID_API="36"
ANDROID_SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;x86_64"
ANDROID_HOME="$HOME/android-sdk"
RUNNER_DIR="$HOME/actions-runner"

info() { echo -e "\n\033[0;36m▶ $*\033[0m"; }
ok()   { echo -e "\033[0;32m  ✅  $*\033[0m"; }

if [ -z "$RUNNER_TOKEN" ]; then
  echo "Usage: bash setup-android-runner-azure.sh <GITHUB_RUNNER_TOKEN>"
  echo ""
  echo "Get the token from:"
  echo "  GitHub → Settings → Actions → Runners → New self-hosted runner → Linux"
  exit 1
fi

# =============================================================================
info "Step 1/6 — System packages"
# =============================================================================
sudo apt-get update -qq
sudo apt-get install -y \
  curl wget unzip git \
  openjdk-17-jdk \
  qemu-kvm libvirt-daemon-system \
  xvfb

sudo usermod -aG kvm "$USER"

# Verify KVM — Standard_D4s_v3 and above support nested virtualisation on Azure
if [ -e /dev/kvm ]; then
  ok "KVM available (/dev/kvm exists)"
else
  echo ""
  echo "  ❌  /dev/kvm not found."
  echo "      Nested virtualisation is required. Use Standard_D4s_v3 or higher"
  echo "      (v3, v4, v5 series). Dav4 and Dasv4 series also support it."
  exit 1
fi

# =============================================================================
info "Step 2/6 — Node.js"
# =============================================================================
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs -q
ok "Node.js $(node --version)"

# =============================================================================
info "Step 3/6 — Android SDK + Emulator"
# =============================================================================
mkdir -p "$ANDROID_HOME/cmdline-tools"

wget -q \
  "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
  -O /tmp/cmdline-tools.zip
rm -rf /tmp/cmdline-tools-extract
unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
rm -rf "$ANDROID_HOME/cmdline-tools/latest"
mv /tmp/cmdline-tools-extract/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract

# Persist environment across sessions
{
  echo ""
  echo "# Android SDK"
  echo "export ANDROID_HOME=$ANDROID_HOME"
  echo "export APPIUM_HOME=\$HOME/.appium"
  echo "export PATH=\$ANDROID_HOME/emulator:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
} >> "$HOME/.bashrc"

export ANDROID_HOME="$ANDROID_HOME"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# Accept licences and install SDK components
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses > /dev/null 2>&1 || true
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" \
  "emulator" \
  "platforms;android-${ANDROID_API}" \
  "${ANDROID_SYSTEM_IMAGE}" \
  > /dev/null

ok "Android SDK installed at $ANDROID_HOME"

# Pre-create the AVD used by the CI workflow
export ANDROID_SDK_ROOT="$ANDROID_HOME"
echo "no" | avdmanager create avd \
  --name "CIDevice" \
  --package "${ANDROID_SYSTEM_IMAGE}" \
  --device "pixel_6" \
  --force > /dev/null

ok "AVD 'CIDevice' created"

# =============================================================================
info "Step 4/6 — Appium + UIAutomator2 driver"
# =============================================================================
sudo npm install -g appium --silent
export APPIUM_HOME="$HOME/.appium"
if appium driver list --installed 2>/dev/null | grep -q uiautomator2; then
  ok "uiautomator2 driver already installed — skipping"
else
  appium driver install uiautomator2 2>&1 | tail -3
fi
ok "Appium $(appium --version) with uiautomator2 driver installed"

# =============================================================================
info "Step 5/6 — GitHub Actions runner"
# =============================================================================
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
  RUNNER_ARCH="linux-arm64"
else
  RUNNER_ARCH="linux-x64"
fi

RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest \
  | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')

curl -sL \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
  -o runner.tar.gz
tar xzf runner.tar.gz
rm runner.tar.gz

./config.sh \
  --url "$GITHUB_REPO" \
  --token "$RUNNER_TOKEN" \
  --name "azure-$(hostname -s)" \
  --labels "self-hosted,linux,appium-android" \
  --replace \
  --runnergroup "Default" \
  --unattended

ok "Runner configured"

# =============================================================================
info "Step 6/6 — Install runner as a systemd service (auto-starts on reboot)"
# =============================================================================
sudo ./svc.sh install
sudo ./svc.sh start
ok "Runner service started"

# =============================================================================
echo ""
echo -e "\033[0;32m╔══════════════════════════════════════════════════╗\033[0m"
echo -e "\033[0;32m║   ✅  Azure Android runner setup complete!       ║\033[0m"
echo -e "\033[0;32m╚══════════════════════════════════════════════════╝\033[0m"
echo ""
echo "  Runner registered: azure-$(hostname -s)"
echo "  Labels:            self-hosted, linux, appium-android"
echo ""
echo "  Verify it's online:"
echo "  GitHub → Settings → Actions → Runners (status should be Idle)"
echo ""
