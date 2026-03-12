# Mobile Test Environment

Local setup for running Appium tests against an **Android emulator** and **iOS Simulator**. A single script starts everything; two commands run the tests.

> **iOS Simulator is macOS only.** On Windows, only Android tests are supported.

---

## Prerequisites

Install these **once** before running anything. Each tool only needs to be installed one time.

### macOS prerequisites

#### 1. Android Studio
Downloads the Android SDK, emulator, and all required command-line tools.

👉 **Download:** https://developer.android.com/studio

After installing, open Android Studio once and let it finish its first-launch SDK setup before running `local-setup.sh`.

#### 2. Xcode
Required for the iOS Simulator and the `xcrun` command-line tools.

👉 **Install:** Open the **Mac App Store** and search for **Xcode**

After installing, open Xcode once to accept the licence agreement. You can quit it immediately after.

#### 3. Node.js (LTS)
Required to run the test runner (WebdriverIO).

👉 **Download:** https://nodejs.org — click the large **LTS** button

---

### Windows prerequisites

#### 1. Android Studio
Downloads the Android SDK, emulator, and all required command-line tools.

👉 **Download:** https://developer.android.com/studio

After installing, open Android Studio once and let it finish its first-launch SDK setup. This is what downloads the emulator and SDK tools the script needs.

#### 2. Node.js (LTS)
Required to run the test runner (WebdriverIO).

👉 **Download:** https://nodejs.org — click the large **LTS** button

During install, leave all default options checked.

#### 3. PowerShell (already installed on Windows 10/11)
PowerShell comes pre-installed on Windows 10 and 11 — you don't need to download anything. To open it:

- Press **Windows key**, type `PowerShell`, right-click **Windows PowerShell** and choose **Run as administrator**

#### 4. Allow PowerShell scripts to run (one-time)
Windows blocks `.ps1` scripts by default. Run this **once** in the PowerShell window you opened above:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

When prompted, type `Y` and press Enter. You only need to do this once — it allows locally created scripts to run while still blocking untrusted scripts from the internet.

> **Already have Git installed?** If you have [Git for Windows](https://git-scm.com/download/win) installed, you can skip steps 3 and 4 entirely. Right-click in the repo folder, choose **Git Bash Here**, and run `bash local-setup.sh` exactly like on macOS.

---

## Start the Environment

**macOS:**
```bash
bash local-setup.sh
```

**Windows (PowerShell — open as Administrator, navigate to the repo folder first):**
```powershell
.\local-setup.ps1
```

> Note: iOS Simulator is macOS only. The Windows script runs Android only.

To navigate to the repo folder in PowerShell, use `cd` followed by the path, for example:
```powershell
cd C:\Users\YourName\Documents\appium-test-environment-sandbox
```

This will:
- Start (or reuse) an Android emulator
- Start (or reuse) an iOS Simulator (macOS only)
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

**macOS:**
```bash
bash local-setup.sh stop
```

**Windows:**
```powershell
.\local-setup.ps1 stop
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

## CI Pipeline

The pipeline runs Android and iOS tests **in parallel** and is triggered manually. The workflow is defined in `.github/workflows/ci.yml`.

### Architecture

```
Manual trigger (workflow_dispatch)
    │
    ├── Android job ──► GCP Compute Engine (n2-standard-4, Ubuntu 22.04, KVM)
    │                   Self-hosted runner — starts emulator → Appium → tests
    │                   System image: google_apis;x86_64 (must match host arch)
    │
    └── iOS job ──────► GitHub-hosted macOS runner (macos-latest)
                        Free for public repos — Xcode + simulators pre-installed
```

iOS Simulator requires macOS. Since this repo is public, GitHub's hosted macOS runners are free and require zero infrastructure to manage.

### One-time setup

#### 1. Create the GCP instance for Android

Run this from your local machine (requires [Google Cloud CLI](https://cloud.google.com/sdk/docs/install)):

```bash
gcloud compute instances create appium-android-runner \
  --project=YOUR_GCP_PROJECT_ID \
  --zone=us-central1-a \
  --machine-type=n2-standard-4 \
  --enable-nested-virtualization \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=60GB \
  --boot-disk-type=pd-ssd \
  --tags=github-runner
```

The `--enable-nested-virtualization` flag is what allows the Android emulator to use KVM acceleration inside the VM. Without it the emulator will be extremely slow.

#### 2. Get a runner registration token

GitHub repo → **Settings** → **Actions** → **Runners** → **New self-hosted runner** → **Linux**

Copy the token shown (it expires after 1 hour).

#### 3. SSH into the GCP instance and run the setup script

```bash
gcloud compute ssh appium-android-runner --zone=us-central1-a

# Once inside the instance:
curl -O https://raw.githubusercontent.com/karthik-krishnan/appium-test-environment-sandbox/main/ci/setup-android-runner-gcp.sh
bash setup-android-runner-gcp.sh <YOUR_RUNNER_TOKEN>
```

The script installs the Android SDK, emulator, Node.js, Appium, and the GitHub Actions runner agent — then registers it as a systemd service so it survives reboots. It takes about **10 minutes** to complete.

#### 4. Verify the runner is online

GitHub repo → **Settings** → **Actions** → **Runners**

You should see one runner with status **Idle**:
- `appium-android-gcp-*` (labels: `self-hosted`, `linux`, `appium-android`)

If the runner shows **Offline**, SSH into the instance and check the service:

```bash
cd ~/actions-runner
sudo ./svc.sh status   # check current state
sudo ./svc.sh start    # start if stopped
```

No setup is needed for iOS — GitHub's macOS runners handle everything automatically.

### Triggering the pipeline

The workflow only runs on manual dispatch — it does **not** trigger automatically on push.

GitHub repo → **Actions** → **Appium Tests** → **Run workflow**

Select the platform to test: `android`, `ios`, or `both`.

### Estimated cost

| Job | Infrastructure | Cost/run |
|---|---|---|
| Android | GCP n2-standard-4 (~15 min) | ~$0.01 |
| iOS | GitHub-hosted macOS (public repo) | **Free** |
| **Total per run** | | **~$0.01** |

> The GCP instance costs ~$0.19/hr when running. Stop it between pipeline runs to avoid idle charges: `gcloud compute instances stop appium-android-runner --zone=us-central1-a`

---

## Project Structure

```
mobile_simulator_env/
├── local-setup.sh               # starts emulator, simulator, and Appium locally
├── ci/
│   └── setup-android-runner-gcp.sh  # one-time setup for GCP Compute Engine runner
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
