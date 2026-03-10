# Mobile Test Environment

Local setup for running Appium tests against an **Android emulator** and **iOS Simulator** on macOS. A single script starts everything; two commands run the tests.

---

## Prerequisites

Install these **once** before running anything. Each tool only needs to be installed one time.

### 1. Android Studio
Downloads the Android SDK, emulator, and all required command-line tools.

👉 **Download:** https://developer.android.com/studio

After installing, open Android Studio once and let it finish its first-launch SDK setup before running `local-setup.sh`.

---

### 2. Xcode
Required for the iOS Simulator and the `xcrun` command-line tools.

👉 **Install:** Open the **Mac App Store** and search for **Xcode**

After installing, open Xcode once to accept the licence agreement. You can quit it immediately after.

---

### 3. Node.js (LTS)
Required to run the test runner (WebdriverIO).

👉 **Download:** https://nodejs.org — click the large **LTS** button

---

## Start the Environment

Run this from the root of the repo:

```bash
bash local-setup.sh
```

This will:
- Start (or reuse) an Android emulator
- Start (or reuse) an iOS Simulator
- Install Appium and its drivers if not already installed
- Start the Appium server on port 4723

**First run** takes 2–5 minutes — it downloads a ~1 GB Android system image. Every run after that is fast; the script skips anything already running.

When everything is ready you'll see:

```
╔══════════════════════════════════════════════╗
║   ✅  Everything is ready!                   ║
╠══════════════════════════════════════════════╣
║   Appium:   http://localhost:4723            ║
║   Android:  emulator-5554                   ║
║   iOS UDID: XXXXXXXX-XXXX-XXXX-XXXX-...    ║
╚══════════════════════════════════════════════╝
```

---

## Run the Tests

Install test dependencies first (one-time only):

```bash
cd tests && npm install
```

**Android tests:**

```bash
npm run test:android
```

**iOS tests:**

```bash
npm run test:ios
```

### What the tests validate

Each suite runs 3 checks:

1. Appium connects to the device and reports the correct platform
2. The Settings app launches successfully
3. The Home button works and the app returns to the foreground

---

## Stop Everything

```bash
bash local-setup.sh stop
```

This kills the Appium server and any emulator/simulator processes started by the setup script.

---

## Troubleshooting

**Appium won't start or tests can't connect:**
```bash
cat /tmp/appium.log
```

**Android emulator won't boot:**
```bash
cat /tmp/android-emulator.log
```

**Check what's currently running:**
```bash
adb devices                          # should show emulator-5554
curl http://localhost:4723/status    # should return {"ready":true,...}
appium driver list --installed       # should list uiautomator2 and xcuitest
```

**Change the Appium port** (if 4723 is in use):
```bash
APPIUM_PORT=4724 bash local-setup.sh
APPIUM_PORT=4724 npm run test:android
```

---

## CI Pipeline on AWS

The pipeline runs Android and iOS tests **in parallel** on every push to `main`. The workflow is defined in `.github/workflows/ci.yml`.

### Architecture

```
GitHub push
    │
    ├── Android job ──► EC2 Linux (m5.large, Ubuntu 22.04, KVM enabled)
    │                   Starts emulator → Appium → runs tests
    │
    └── iOS job ──────► EC2 Mac (mac2.metal, macOS 13+)
                        Starts simulator → Appium → runs tests
```

iOS Simulator **requires macOS** — it cannot run on Linux. AWS EC2 Mac instances (`mac2.metal`) are the AWS-native solution for this.

### One-time EC2 Setup

#### 1. Launch the EC2 instances

**Android runner** — launch from the AWS console:
- AMI: Ubuntu 22.04 LTS (64-bit ARM)
- Instance type: `m5.large` (needs KVM support for the emulator)
- Storage: 50 GB SSD
- Security group: allow SSH (port 22)

**iOS runner** — launch from the AWS console:
- AMI: macOS 13 Ventura (search "macOS" in Community AMIs)
- Instance type: `mac2.metal` (minimum for iOS Simulator)
- Storage: 100 GB SSD
- Security group: allow SSH (port 22)
- ⚠️ Mac instances have a **24-hour minimum billing period** — plan runs accordingly

#### 2. Get a runner registration token

GitHub repo → **Settings** → **Actions** → **Runners** → **New self-hosted runner**

Copy the token shown on screen (it expires after 1 hour).

#### 3. SSH into each instance and run the setup script

**On the Android (Linux) instance:**
```bash
curl -O https://raw.githubusercontent.com/karthik-krishnan/appium-test-environment-sandbox/main/ci/setup-android-runner.sh
bash setup-android-runner.sh <YOUR_RUNNER_TOKEN>
```

**On the iOS (Mac) instance:**
```bash
curl -O https://raw.githubusercontent.com/karthik-krishnan/appium-test-environment-sandbox/main/ci/setup-ios-runner.sh
bash setup-ios-runner.sh <YOUR_RUNNER_TOKEN>
```

Each script installs all dependencies, registers the instance as a GitHub Actions runner, and starts it as a system service so it survives reboots.

#### 4. Verify runners are online

GitHub repo → **Settings** → **Actions** → **Runners**

You should see two runners with status **Idle**:
- `appium-android-*` (labels: `self-hosted`, `linux`, `appium-android`)
- `appium-ios-*` (labels: `self-hosted`, `macos`, `appium-ios`)

### Triggering the pipeline

Push to `main` — the workflow starts automatically. You can also trigger it manually:

GitHub repo → **Actions** → **Appium Tests** → **Run workflow**

### Estimated AWS cost

| Instance | Type | Cost/hr | Typical job | Cost/run |
|---|---|---|---|---|
| Android runner | m5.large | $0.096 | ~15 min | ~$0.02 |
| iOS runner | mac2.metal | $1.21 | ~20 min | ~$0.40 |
| **Total per run** | | | | **~$0.42** |

> Mac instances have a 24-hour minimum charge on first allocation (~$29). After that, billing is per-hour so keeping the instance warm between runs (rather than stopping it) is usually cheaper if you run tests multiple times a day.

---

## Project Structure

```
mobile_simulator_env/
├── local-setup.sh               # starts emulator, simulator, and Appium locally
├── ci/
│   ├── setup-android-runner.sh  # one-time setup for EC2 Linux runner
│   └── setup-ios-runner.sh      # one-time setup for EC2 Mac runner
├── .github/
│   └── workflows/
│       └── ci.yml               # GitHub Actions pipeline definition
├── tests/
│   ├── package.json
│   ├── wdio.android.conf.js
│   ├── wdio.ios.conf.js
│   ├── wdio.conf.js
│   ├── specs/
│   │   ├── android/setup-validation.spec.js
│   │   └── ios/setup-validation.spec.js
│   └── screenshots/             # failure screenshots (auto-saved)
└── logs/
```
