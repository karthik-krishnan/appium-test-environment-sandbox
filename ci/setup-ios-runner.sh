#!/usr/bin/env bash
# =============================================================================
# ci/setup-ios-runner.sh
# =============================================================================
# Run ONCE on a fresh EC2 Mac instance (mac2.metal, macOS 13+).
# Installs: Xcode CLT, Homebrew, Node.js, Appium, and GitHub Actions runner.
#
# Usage:
#   1. Launch EC2 Mac instance (see README — CI Setup section for instance config)
#   2. SSH into the instance
#   3. bash setup-ios-runner.sh <GITHUB_RUNNER_TOKEN>
#
# Get the runner token from:
#   GitHub repo → Settings → Actions → Runners → New self-hosted runner → macOS
# =============================================================================

set -euo pipefail

RUNNER_TOKEN="${1:-}"
GITHUB_REPO="https://github.com/karthik-krishnan/appium-test-environment-sandbox"
RUNNER_DIR="$HOME/actions-runner"

info() { echo -e "\n\033[0;36m▶ $*\033[0m"; }
ok()   { echo -e "\033[0;32m  ✅  $*\033[0m"; }

if [ -z "$RUNNER_TOKEN" ]; then
  echo "Usage: bash setup-ios-runner.sh <GITHUB_RUNNER_TOKEN>"
  echo ""
  echo "Get the token from:"
  echo "  GitHub repo → Settings → Actions → Runners → New self-hosted runner → macOS"
  exit 1
fi

# =============================================================================
info "Step 1/5 — Xcode command-line tools"
# =============================================================================
if ! xcode-select -p &>/dev/null; then
  xcode-select --install
  # Wait for CLT installation to complete
  echo "  Waiting for Xcode CLT to install (may take a few minutes)..."
  until xcode-select -p &>/dev/null; do sleep 5; done
fi

# Accept licence (required for xcrun to work)
sudo xcodebuild -license accept 2>/dev/null || true
ok "Xcode CLT $(xcode-select -p)"

# List available simulators so we can verify runtimes are present
echo "  Available iOS runtimes:"
xcrun simctl list runtimes 2>/dev/null | grep iOS | sed 's/^/    /'

# =============================================================================
info "Step 2/5 — Homebrew + Node.js"
# =============================================================================
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH for Apple Silicon Macs
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
ok "Homebrew $(brew --version | head -1)"

brew install node
ok "Node.js $(node --version)"

# =============================================================================
info "Step 3/5 — Appium + XCUITest driver"
# =============================================================================
npm install -g appium --silent
export APPIUM_HOME="${APPIUM_HOME:-$HOME/.appium}"
echo "export APPIUM_HOME=$APPIUM_HOME" >> "$HOME/.zprofile"

appium driver install xcuitest 2>&1 | tail -3
ok "Appium $(appium --version) with xcuitest installed"

# Also install uiautomator2 so a single runner can do both if needed
appium driver install uiautomator2 2>&1 | tail -3
ok "uiautomator2 installed (optional Android fallback)"

# =============================================================================
info "Step 4/5 — Pre-warm iOS Simulator"
# =============================================================================
# Boot a simulator now so it's fast on first CI run
SIM_UDID=""
for MODEL in "iPhone 16" "iPhone 15 Pro" "iPhone 15" "iPhone 14"; do
  SIM_UDID=$(xcrun simctl list devices available 2>/dev/null \
    | grep "$MODEL" \
    | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' \
    | head -1 || true)
  [ -n "$SIM_UDID" ] && { echo "  Booting: $MODEL ($SIM_UDID)"; break; }
done

if [ -n "$SIM_UDID" ]; then
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  ok "Simulator pre-warmed: $SIM_UDID"
else
  echo "  ⚠️  No iPhone simulator found. Install via Xcode → Settings → Platforms"
fi

# =============================================================================
info "Step 5/5 — GitHub Actions runner"
# =============================================================================
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download latest runner release for macOS arm64
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest \
  | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
RUNNER_ARCH="osx-arm64"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

curl -sL "$RUNNER_URL" -o runner.tar.gz
tar xzf runner.tar.gz
rm runner.tar.gz

# Configure runner (labels: self-hosted, macos, appium-ios)
./config.sh \
  --url "$GITHUB_REPO" \
  --token "$RUNNER_TOKEN" \
  --name "appium-ios-$(hostname -s)" \
  --labels "self-hosted,macos,appium-ios" \
  --runnergroup "Default" \
  --unattended

ok "Runner configured"

# Install as a launch daemon so it survives reboots
./svc.sh install
./svc.sh start
ok "Runner service started"

# =============================================================================
echo ""
echo -e "\033[0;32m╔══════════════════════════════════════════════╗\033[0m"
echo -e "\033[0;32m║   ✅  iOS runner setup complete!             ║\033[0m"
echo -e "\033[0;32m╚══════════════════════════════════════════════╝\033[0m"
echo ""
echo "  The runner 'appium-ios-$(hostname -s)' is now registered."
echo "  It will appear in:"
echo "  GitHub → Settings → Actions → Runners"
echo ""
echo "  Labels applied: self-hosted, macos, appium-ios"
echo "  These must match the 'runs-on' in .github/workflows/ci.yml"
echo ""
