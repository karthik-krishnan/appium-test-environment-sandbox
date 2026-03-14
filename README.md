# Mobile Test Automation Starter

An end-to-end mobile test automation setup using **Appium** and **WebdriverIO**, covering local development on macOS and Windows, and a full CI pipeline with cloud infrastructure.

**What's included:**
- One-command local setup for Android emulator + iOS Simulator (macOS) or Android only (Windows)
- Sample Appium test suites for Android and iOS (placeholder specs — replace with your own)
- CI pipeline: Android on a self-hosted Linux runner, iOS on GitHub-hosted macOS runners
- Infrastructure-as-code scripts to provision and register an Android runner on GCP, AWS, or Azure

> **iOS Simulator is macOS only.** On Windows, only Android tests are supported.

> **Windows requires a native installation.** The Android Emulator needs hardware virtualisation (SVM/Hyper-V) which is not available inside virtual machines (UTM, VirtualBox, VMware, etc.). Run this on a physical Windows machine only.

---

## Get Started

Clone the repo:

```bash
git clone https://github.com/karthik-krishnan/mobile-test-automation-starter.git
cd mobile-test-automation-starter
```

Then install the prerequisites for your OS below.

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

**Windows (open PowerShell as Administrator, navigate to the repo folder first):**
```powershell
cd C:\Users\YourName\Documents\mobile-test-automation-starter
.\local-setup.ps1
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

The included tests are **sample / placeholder tests** — they exist to prove the environment is wired up correctly, not to test a real app. Replace them with your own test specs once the setup is working.

Each sample suite runs 3 checks:

1. Appium connects to the device and reports the correct platform
2. The Settings app launches successfully
3. A basic UI interaction works (Android: verifies app foreground state; iOS: taps a menu item and goes back)

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
cat logs/appium.log
```

**Android emulator won't boot:**
```bash
cat logs/android-emulator.log
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
    ├── Android job ──► Self-hosted Linux runner (GCP / AWS / Azure)
    │                   Starts emulator → Appium → tests
    │                   System image: google_apis;x86_64 (must match host arch)
    │
    └── iOS job ──────► GitHub-hosted macOS runner (macos-latest)
                        Free for public repos — Xcode + simulators pre-installed
```

iOS Simulator requires macOS. Since this repo is public, GitHub's hosted macOS runners are free and require zero infrastructure to manage.

The Android runner can be hosted on any cloud provider — setup scripts are provided for GCP, AWS, and Azure. All three register with the same runner labels so the CI workflow works without any changes.

### One-time setup

#### 1. Provision the Android runner VM

Choose your cloud provider and follow the steps below. The key requirement for all three is that the VM supports **nested virtualisation (KVM)** — this is what allows the Android emulator to run efficiently inside a cloud VM.

---

**Option A — GCP** (requires [Google Cloud CLI](https://cloud.google.com/sdk/docs/install))

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

SSH in: `gcloud compute ssh appium-android-runner --zone=us-central1-a`

Setup script: `ci/setup-android-runner-gcp.sh`

---

**Option B — AWS** (requires [AWS CLI](https://aws.amazon.com/cli/))

```bash
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type m5.xlarge \
  --key-name YOUR_KEY_PAIR_NAME \
  --security-group-ids YOUR_SECURITY_GROUP_ID \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":60,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=appium-android-runner}]' \
  --region us-east-1
```

> `ami-0c7217cdde317cfec` is Ubuntu 22.04 LTS in us-east-1. Find the right AMI for your region at [cloud-images.ubuntu.com](https://cloud-images.ubuntu.com/locator/ec2/).

SSH in: `ssh -i YOUR_KEY.pem ubuntu@<INSTANCE_PUBLIC_IP>`

Setup script: `ci/setup-android-runner-aws.sh`

---

**Option C — Azure** (requires [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli))

```bash
az group create --name appium-runner-rg --location eastus

az vm create \
  --resource-group appium-runner-rg \
  --name appium-android-runner \
  --image Ubuntu2204 \
  --size Standard_D4s_v3 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --os-disk-size-gb 60
```

SSH in: `ssh azureuser@$(az vm show -d -g appium-runner-rg -n appium-android-runner --query publicIps -o tsv)`

Setup script: `ci/setup-android-runner-azure.sh`

---

#### 2. Get a runner registration token

GitHub repo → **Settings** → **Actions** → **Runners** → **New self-hosted runner** → **Linux**

Copy the token shown (it expires after 1 hour).

#### 3. SSH into the VM and run the setup script

Once inside the VM, download and run the setup script for your provider:

```bash
# GCP
curl -O https://raw.githubusercontent.com/karthik-krishnan/mobile-test-automation-starter/main/ci/setup-android-runner-gcp.sh
bash setup-android-runner-gcp.sh <YOUR_RUNNER_TOKEN>

# AWS
curl -O https://raw.githubusercontent.com/karthik-krishnan/mobile-test-automation-starter/main/ci/setup-android-runner-aws.sh
bash setup-android-runner-aws.sh <YOUR_RUNNER_TOKEN>

# Azure
curl -O https://raw.githubusercontent.com/karthik-krishnan/mobile-test-automation-starter/main/ci/setup-android-runner-azure.sh
bash setup-android-runner-azure.sh <YOUR_RUNNER_TOKEN>
```

The script installs the Android SDK, emulator, Node.js, Appium, and the GitHub Actions runner agent — then registers it as a systemd service so it survives reboots. It takes about **10 minutes** to complete.

#### 4. Verify the runner is online

GitHub repo → **Settings** → **Actions** → **Runners**

You should see one runner with status **Idle** and labels: `self-hosted`, `linux`, `appium-android`.

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
| Android (GCP) | n2-standard-4 (~15 min @ ~$0.19/hr) | ~$0.01 |
| Android (AWS) | m5.xlarge (~15 min @ ~$0.19/hr) | ~$0.01 |
| Android (Azure) | Standard_D4s_v3 (~15 min @ ~$0.19/hr) | ~$0.01 |
| iOS | GitHub-hosted macOS (public repo) | **Free** |

> Stop the VM between runs to avoid idle charges:
> - GCP: `gcloud compute instances stop appium-android-runner --zone=us-central1-a`
> - AWS: `aws ec2 stop-instances --instance-ids YOUR_INSTANCE_ID`
> - Azure: `az vm deallocate -g appium-runner-rg -n appium-android-runner`

---

## Project Structure

```
mobile-test-automation-starter/
├── local-setup.sh                       # macOS: starts emulator, simulator, and Appium
├── local-setup.ps1                      # Windows: starts emulator and Appium (Android only)
├── ci/
│   ├── setup-android-runner-gcp.sh      # one-time GCP runner setup
│   ├── setup-android-runner-aws.sh      # one-time AWS runner setup
│   └── setup-android-runner-azure.sh    # one-time Azure runner setup
├── .github/
│   └── workflows/
│       └── ci.yml                       # GitHub Actions pipeline definition
├── tests/
│   ├── package.json
│   ├── wdio.android.conf.js
│   ├── wdio.ios.conf.js
│   ├── wdio.conf.js
│   ├── specs/
│   │   ├── android/setup-validation.spec.js
│   │   └── ios/setup-validation.spec.js
│   └── screenshots/                     # failure screenshots (auto-saved)
└── logs/
```
