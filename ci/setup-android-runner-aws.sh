#!/usr/bin/env bash
# =============================================================================
# ci/setup-android-runner-aws.sh
# =============================================================================
# Sets up an AWS EC2 instance as a GitHub Actions self-hosted runner
# for Android Appium tests.
#
# STEP 1 — Create the EC2 instance (run from your local machine, once):
#
#   aws ec2 run-instances \
#     --image-id ami-0c7217cdde317cfec \
#     --instance-type m5.xlarge \
#     --key-name YOUR_KEY_PAIR_NAME \
#     --security-group-ids YOUR_SECURITY_GROUP_ID \
#     --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":60,"VolumeType":"gp3"}}]' \
#     --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=appium-android-runner}]' \
#     --region us-east-1
#
#   Notes:
#   - Replace YOUR_KEY_PAIR_NAME with your EC2 key pair name
#   - Replace YOUR_SECURITY_GROUP_ID with a security group that allows SSH (port 22)
#   - ami-0c7217cdde317cfec is Ubuntu 22.04 LTS in us-east-1 — find the right
#     AMI for your region at: https://cloud-images.ubuntu.com/locator/ec2/
#   - m5.xlarge has /dev/kvm available for Android emulator acceleration
#
# STEP 2 — SSH in and run this script:
#
#   ssh -i YOUR_KEY.pem ubuntu@<INSTANCE_PUBLIC_IP>
#   bash setup-android-runner-aws.sh <GITHUB_RUNNER_TOKEN>
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
  echo "Usage: bash setup-android-runner-aws.sh <GITHUB_RUNNER_TOKEN>"
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

# Verify KVM — m5.xlarge and similar instance types expose /dev/kvm
if [ -e /dev/kvm ]; then
  ok "KVM available (/dev/kvm exists)"
else
  echo ""
  echo "  ❌  /dev/kvm not found."
  echo "      Try a different instance type — m5.xlarge, c5.xlarge, or r5.xlarge"
  echo "      are known to expose /dev/kvm on AWS."
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
  --name "aws-$(hostname -s)" \
  --labels "self-hosted,linux,appium-android" \
  --runnergroup "Default" \
  --replace \
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
echo -e "\033[0;32m║   ✅  AWS Android runner setup complete!         ║\033[0m"
echo -e "\033[0;32m╚══════════════════════════════════════════════════╝\033[0m"
echo ""
echo "  Runner registered: aws-$(hostname -s)"
echo "  Labels:            self-hosted, linux, appium-android"
echo ""
echo "  Verify it's online:"
echo "  GitHub → Settings → Actions → Runners (status should be Idle)"
echo ""
