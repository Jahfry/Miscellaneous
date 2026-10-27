# Sony Bravia A80J (VH21) Complete Debloat & De-Google Guide

A step-by-step procedure to remove advertisements, eliminate UI stutter, disable Samba TV Automatic Content Recognition (ACR) and telemetry, replace the Google TV launcher with a zero-network open-source launcher, and decouple the TV from Google Play Services.

CHANGELOG: 

* 2026-10-26 ... initial version created and tested on my Sony A80J using Google Gemini Flash 3.8 and the instructions on [cleanyourtv](https://github.com/Gathin23/cleanyourtv/) version 3.0 current as of this update. 

These instructions are specific to my TV (as in I install things like Key Mapper, Plex, Tidal, etc) and were done by hand since I don't use an agentic coding harness. 

---

## 1. Project Architecture & Requirements

* **Target Hardware:** Sony Bravia XR OLED (A80J / Platform `BRAVIA_VH21` / MediaTek MT5895 SoC, US Model).
* **Control Machine:** Linux Desktop (Bazzite / Fedora Silverblue / OSTree base).
* **Base Upstream Project:** [cleanyourtv](https://github.com/Gathin23/cleanyourtv/) (Release 3.0 baseline), found via [this Reddit post](https://www.reddit.com/r/GoogleTV/comments/1xbcawv/claude_made_my_sony_tv_90_faster/).
* **Primary Media Apps:** Plex, SmartTube, Tidal HiFi, Spotify, and an external PC/HTPC on HDMI 4 (VRR Gaming).
* **Target Result:**
  * Zero advertisements and no algorithmic content carousels.
  * Fast native home screen (`tvhome`) with **zero network permissions** declared in its manifest.
  * Preserved picture tuning, OLED panel maintenance routines, Acoustic Auto Calibration, VRR, ALLM, eARC, and Bravia Sync (HDMI-CEC).
  * Preserved IR Blaster setup (`com.uei.quicksetsdk.sony`) and local Home Assistant REST API IP control (`b2b.ipcontrolsettings` and `homenetwork`).
  * Dedicated remote buttons remapped without root or paid licenses using **Key Mapper** (v4.6.2 FOSS).

---

## 2. Directory Layout & Storage Paths

All files and source code on the control PC reside in these standard directories:

* **Workspace Directory:** `~/Projects/AndroidTV/`
* **Upstream Git Clone:** `~/Projects/AndroidTV/cleanyourtv/`
* **Android SDK Location:** `~/Android/Sdk/`
* **Output APK Repository:** `~/Projects/AndroidTV/*.apk`

---

## 3. Preparation: TV Physical & Network Sanitization

Perform these steps on the TV using the factory remote before executing ADB commands.

### A. Enable Developer Options & Network ADB
1. On the TV, go to **Settings $\rightarrow$ System $\rightarrow$ About**.
2. Highlight **Android TV OS build** and press the center **Enter/OK** button 7 times until the toast appears: *"You are now a developer!"*
3. Go back to **Settings $\rightarrow$ System $\rightarrow$ Developer options**.
4. Enable **USB debugging**. On the Sony VH21 platform, enabling USB debugging binds the internal ADB daemon to TCP port `5555` on your local network.

### B. Wi-Fi Credential Sanitization (Critical Trap Prevention)
On Google TV, if your Wi-Fi network was configured during initial setup, the Google Setup Wizard (`com.google.android.tungsten.setupwraith`) owns the credential profile. If `setupwraith` is disabled while owning this profile, Android scrubs the network configuration, disconnecting the TV from Wi-Fi and terminating your wireless ADB session.

1. On the TV, navigate to: **Settings $\rightarrow$ Network & Internet $\rightarrow$ [Your Current Wi-Fi SSID]**.
2. Select **Forget network** and confirm.
3. Select the SSID again and re-enter your Wi-Fi password manually.
4. *Result:* Ownership transfers from `com.google.android.tungsten.setupwraith` (UID `10152`) to `android.uid.system` / `com.android.tv.settings` (UID `1000`). Disabling `setupwraith` later will not drop network connectivity.

---

## 4. Workstation Toolchain Setup (Bazzite / Linux)

Run these commands on the control desktop to set up the Android SDK, OpenJDK 17, and the local maintenance workspace.

### A. Install Dependencies via Homebrew
```bash
# Install Android platform tools, command-line SDK, and JDK 17
brew install android-platform-tools
brew install --cask android-commandlinetools
brew install openjdk@17

# CRITICAL HYGIENE STEP FOR BAZZITE / FEDORA USERS:
# Homebrew's Python shadows system /usr/bin/python3, which strips PyGObject (gi)
# and breaks native desktop apps/AppImages (e.g. Faugus Launcher, Wine, GTK).
# Unlink Homebrew's Python immediately to preserve system stability:
brew unlink python@3.15 2>/dev/null || brew unlink python3 2>/dev/null || true
```

### B. Initialize Android SDK 34
```bash
mkdir -p "$HOME/Android/Sdk"
export ANDROID_HOME="$HOME/Android/Sdk"

# Accept Google licenses and install Platform 34 and Build Tools 34.0.0
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" "platforms;android-34" "build-tools;34.0.0"
```

### C. Clone Repository
```bash
mkdir -p ~/Projects/AndroidTV
cd ~/Projects/AndroidTV
git clone https://github.com/Gathin23/cleanyourtv.git
```

---

## 5. Build Automation Setup: `manage_launcher.sh`

Create a new file on your control PC at `~/Projects/AndroidTV/manage_launcher.sh` using your text editor (e.g. `nano ~/Projects/AndroidTV/manage_launcher.sh`) and paste the following content:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/Projects/AndroidTV/cleanyourtv"
LAUNCHER_DIR="$REPO_DIR/launcher"
OUTPUT_APK="$HOME/Projects/AndroidTV/tvhome.apk"
ACTION="${1:-help}"

show_help() {
  cat << 'HELP'
tvhome Build & Lifecycle Manager

Usage: ./manage_launcher.sh [command]

Commands:
  rebuild    Recompiles current local code, copies output to ~/Projects/AndroidTV/tvhome.apk,
             and automatically cleans intermediate build files & halts background daemons.
  upgrade    Cleans existing builds, fetches latest stable git release tag, and compiles tvhome.apk.
  clean      Purges prior compile files (app/build) and stops idle background Gradle Java daemons.
  -h, --help Show this help screen.
HELP
}

if [[ "$ACTION" == "-h" || "$ACTION" == "--help" || "$ACTION" == "help" ]]; then
  show_help
  exit 0
fi

# 1. Python Environment Guard
echo "==> [1/3] Checking System Python Integrity..."
SYS_PY="$(which python3)"
if [[ "$SYS_PY" == *linuxbrew* ]]; then
  echo "    WARNING: Homebrew Python detected on PATH! Unlinking to protect system apps..."
  brew unlink python@3.15 2>/dev/null || brew unlink python3 2>/dev/null || true
fi
python3 -c "import gi" 2>/dev/null && echo "    System Python & PyGObject OK (/usr/bin/python3)" || echo "    System Python active."

# 2. Isolated Toolchain Setup
export JAVA_HOME="/home/linuxbrew/.linuxbrew/opt/openjdk@17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
export PYTHON="/usr/bin/python3"

cd "$LAUNCHER_DIR"
echo "sdk.dir=$ANDROID_HOME" > local.properties

do_clean() {
  echo "==> Cleaning build artifacts & stopping background Gradle JVM..."
  ./gradlew clean --console=plain
  ./gradlew --stop >/dev/null 2>&1 || true
  rm -rf app/build .gradle
  echo "==> Workspace clean."
}

do_compile() {
  echo "==> Compiling tvhome Release APK..."
  ./gradlew assembleRelease --console=plain

  BUILT_APK="$LAUNCHER_DIR/app/build/outputs/apk/release/app-release.apk"
  if [ -f "$BUILT_APK" ]; then
    cp -f "$BUILT_APK" "$OUTPUT_APK"
    
    echo "==> Post-build cleanup (purging intermediate files & stopping JVM daemon)..."
    ./gradlew clean --console=plain
    ./gradlew --stop >/dev/null 2>&1 || true
    rm -rf .gradle

    echo "----------------------------------------------------------"
    echo "BUILD & CLEANUP SUCCESSFUL"
    ls -lh "$OUTPUT_APK"
    echo "Artifact: $OUTPUT_APK"
    echo "----------------------------------------------------------"
    echo "To install on your TV whenever ready, run:"
    echo "  adb connect {your TV IP address}:5555"
    echo "  adb install -r $OUTPUT_APK"
    echo "=========================================================="
  else
    echo "ERROR: Compilation failed to produce APK."
    exit 1
  fi
}

case "$ACTION" in
  clean)
    do_clean
    ;;
  rebuild)
    echo "==> Running local rebuild..."
    do_compile
    ;;
  upgrade)
    echo "==> [Upgrade] Step 1: Cleaning prior build artifacts..."
    do_clean
    echo "==> [Upgrade] Step 2: Fetching latest stable release from GitHub..."
    cd "$REPO_DIR"
    git fetch --tags origin
    LATEST_TAG=$(git tag -l 'v*' | grep -E '^v[0-9]+(\.[0-9]+)+' | sort -V | tail -n 1 || true)
    if [ -n "$LATEST_TAG" ]; then
      CURRENT_REF=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
      echo "    Current version: $CURRENT_REF"
      echo "    Latest release : $LATEST_TAG"
      if [ "$CURRENT_REF" != "$LATEST_TAG" ]; then
        echo "    Checking out $LATEST_TAG..."
        git checkout "$LATEST_TAG"
      else
        echo "    Already on the latest release ($LATEST_TAG)."
      fi
    else
      echo "    No release tags found; pulling latest main branch..."
      git checkout main
      git pull origin main
    fi
    cd "$LAUNCHER_DIR"
    echo "==> [Upgrade] Step 3: Compiling freshly pulled release..."
    do_compile
    ;;
  *)
    echo "Unknown command: $ACTION" >&2
    echo "" >&2
    show_help >&2
    exit 1
    ;;
esac
```

After saving the file, make it executable:
```bash
chmod +x ~/Projects/AndroidTV/manage_launcher.sh
```

### Compile `tvhome` for the First Time
Run `upgrade` for the first compilation. This fetches upstream Git tags, checks out the **latest verified stable release tag** instead of the rolling development `main` branch, cleans any stale artifacts, and compiles `tvhome.apk`:

```bash
~/Projects/AndroidTV/manage_launcher.sh upgrade
```
*Verification:* Confirm that `~/Projects/AndroidTV/tvhome.apk` exists (~520–540 KB).

---

## 6. Execution: Step-by-Step TV Configuration

### Step 1: Establish Persistent ADB Handshake
From your control PC:
```bash
adb connect {your TV IP address}:5555
```
**Action on TV Screen:** An authorization prompt will appear. Check **"Always allow from this computer"** and select **Allow**. The PC's RSA public key is now permanently saved to `/data/misc/adb/adb_keys` on the TV.

Confirm connection:
```bash
adb devices
# Output must state: {your TV IP address}:5555    device
```

### Step 2: Validate Wi-Fi Sanitization
Verify that `setupwraith` no longer owns the active Wi-Fi profile:
```bash
adb shell "dumpsys wifi | grep -i cname"
```
*Verification:* Ensure that `cname=com.google.android.tungsten.setupwraith` does **not** appear on lines marked `mostRecentlyConnected=true`. It should report `cname=android.uid.system` or `cname=com.android.tv.settings`.

### Step 3: Sideload Companion & Replacement Apps
Download and push the replacement application binaries from your PC:

```bash
cd ~/Projects/AndroidTV

# 1. Sideload the freshly compiled zero-network launcher
adb install -r ~/Projects/AndroidTV/tvhome.apk

# 2. Download and install Key Mapper (v4.6.2 FOSS)
curl -L -o keymapper.apk "https://github.com/keymapperorg/KeyMapper/releases/download/v4.6.2/keymapper-4.6.2-foss.apk"
adb install -r keymapper.apk

# 3. Download and install TV Bro Browser (geckoExcluded variant - uses system WebView)
curl -L -o tvbro.apk "https://github.com/truefedex/tv-bro/releases/download/v2.1.6/tvbro-2.1.6-generic-geckoExcluded.apk"
echo "d8634edfe8d94b4fb9a52005d68a090a7f1e85b7f39c2cf01a25dc9dd60942b2  tvbro.apk" | sha256sum -c
adb install -r tvbro.apk

# 4. Download and install Aurora Store (Anonymous Google Play client)
curl -L -o aurorastore.apk "https://auroraoss.com/downloads/AuroraStore/Release/AuroraStore-4.8.4.apk"
adb install -r aurorastore.apk
```

Grant required permissions for Key Mapper and Aurora Store:
```bash
# Key Mapper system event permission
adb shell pm grant io.github.sds100.keymapper android.permission.WRITE_SECURE_SETTINGS

# Aurora Store install and storage permissions
adb shell appops set com.aurora.store REQUEST_INSTALL_PACKAGES allow
adb shell appops set com.aurora.store MANAGE_EXTERNAL_STORAGE allow
adb shell pm grant com.aurora.store android.permission.MANAGE_EXTERNAL_STORAGE 2>/dev/null || true
adb shell dumpsys deviceidle whitelist +com.aurora.store
```

### Step 4: Sideload Clean Streaming Apps
Install your streaming clients using standalone TV APKs:

* **SmartTube:** Install via official GitHub release. (When logging in, use `youtube.com/activate`; SmartTube links directly via OAuth and never touches system Google accounts).
* **Tidal HiFi & Spotify:** Open Aurora Store on the TV, log in with an **Anonymous** session, verify Device Spoof is set to **Sony VH2** (Native), and install **TIDAL** and **Spotify on TV** (the 100M+ downloads TV version, `com.spotify.tv.android`).
* **Plex for Android TV:** Download the official split-bundle `.apkm` from APKMirror (`Plex: Stream Movies & TV (Android TV)`), extract it on your PC, and push using ADB:
  ```bash
  mkdir -p /tmp/plex_splits
  unzip -q ~/Downloads/com.plexapp.android_*.apkm -d /tmp/plex_splits/
  cd /tmp/plex_splits && adb install-multiple -r *.apk
  rm -rf /tmp/plex_splits
  ```

### Step 5: Test Launcher & Cutover Default Role
Test launching `tvhome` manually before disabling the stock launcher:
```bash
adb shell am start -n com.gathin.tvhome/.MainActivity
```
Verify on screen that the clean interface displays and responds to the remote D-pad.

Now permanently cut over to `tvhome`:
```bash
# 1. Disable the stock ad-filled launcher and setup recovery trap
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith

# 2. Designate tvhome as the OS-level default Home role
adb shell cmd role add-role-holder android.app.role.HOME com.gathin.tvhome

# 3. Enable accessibility listeners for tvhome and Key Mapper
adb shell settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService:com.gathin.tvhome/.InputKeyService:io.github.sds100.keymapper/.service.MyAccessibilityService
adb shell settings put secure accessibility_enabled 1
```

### Step 6: Execute Full Platform Debloat
Disable Samba TV ACR, telemetry, demo loops, and background daemons:

```bash
# Samba TV Automatic Content Recognition (ACR)
adb shell pm disable-user --user 0 tv.samba.ssm
adb shell pm disable-user --user 0 tv.samba.ssm.ui

# Sony & Partner Telemetry
adb shell pm disable-user --user 0 com.sonyericsson.idd.agent
adb shell pm disable-user --user 0 com.qterics.da.product
adb shell pm disable-user --user 0 com.sony.dtv.sonybugreportsys
adb shell pm disable-user --user 0 com.sony.dtv.sonyloglevelsettingsys
adb shell pm disable-user --user 0 com.sony.dtv.usercontext
adb shell pm disable-user --user 0 com.netflix.partner.ncm
adb shell pm disable-user --user 0 com.google.android.feedback

# Retail Demo Modes & Promotional Customizers
adb shell pm disable-user --user 0 com.sony.dtv.demosupport
adb shell pm disable-user --user 0 com.sony.dtv.demosystemsupport
adb shell pm disable-user --user 0 com.sony.dtv.multiscreendemo
adb shell pm disable-user --user 0 com.sony.dtv.launcherxcustomizer
adb shell pm disable-user --user 0 com.sony.dtv.sonyselect
adb shell pm disable-user --user 0 com.sony.dtv.notificationcenter
adb shell pm disable-user --user 0 com.sony.dtv.smarthelp
adb shell pm disable-user --user 0 com.sony.dtv.ecodashboard

# Vewd Browser Engine & Sony WebApp Runtimes
adb shell pm disable-user --user 0 com.vewd.core.service
adb shell pm disable-user --user 0 com.sony.dtv.browser.webappplatform
adb shell pm disable-user --user 0 com.sony.dtv.browser.webappruntime
adb shell pm disable-user --user 0 com.sony.dtv.browser.webappruntimeextension
adb shell pm disable-user --user 0 com.sony.dtv.browser.webappservice

# Sony B2B Hotel Mode & Embedded Node.js Engines (Keeps IP Control for Home Assistant)
adb shell pm disable-user --user 0 com.sony.dtv.b2b.adminpassword
adb shell pm disable-user --user 0 com.sony.dtv.b2b.deviceadminsettings
adb shell pm disable-user --user 0 com.sony.dtv.b2b.frameworkextension
adb shell pm disable-user --user 0 com.sony.dtv.b2b.hotelmode
adb shell pm disable-user --user 0 com.sony.dtv.b2b.importexport
adb shell pm disable-user --user 0 com.sony.dtv.b2b.noderuntimeextension.bpk
adb shell pm disable-user --user 0 com.sony.dtv.b2b.noderuntimeextension.node_20_11_1
adb shell pm disable-user --user 0 com.sony.dtv.b2b.noderuntime.normal
adb shell pm disable-user --user 0 com.sony.dtv.b2b.noderuntime.privilege
adb shell pm disable-user --user 0 com.sony.dtv.b2b.prosettings
adb shell pm disable-user --user 0 com.sony.dtv.b2b.rs232csupport
adb shell pm disable-user --user 0 com.sony.dtv.b2b.webappruntimedrm

# Unused Hardware Accessories (Bravia Cam & Gesture Controls)
adb shell pm disable-user --user 0 com.sony.dtv.sensingcamera.fwupdate
adb shell pm disable-user --user 0 com.sony.dtv.sensingcamera.settings
adb shell pm disable-user --user 0 com.sony.dtv.sensingfusionservice
adb shell pm disable-user --user 0 com.sony.dtv.gestureapp
adb shell pm disable-user --user 0 com.sony.dtv.distancealert

# Sony Cloud IoT (Preserves Local IP Control)
adb shell pm disable-user --user 0 com.sony.dtv.seeds.auth
adb shell pm disable-user --user 0 com.sony.dtv.seeds.iot.remotestart

# Obsolete Sync Adapters & Accessibility
adb shell pm disable-user --user 0 com.google.android.syncadapters.calendar
adb shell pm disable-user --user 0 com.google.android.marvin.talkback
adb shell pm disable-user --user 0 com.google.android.tts

# Factory Preloaded App Stubs (Clears Hardware Remote Keys for Key Mapper)
adb shell pm disable-user --user 0 com.google.android.youtube.tv
adb shell pm disable-user --user 0 com.google.android.youtube.tvmusic
adb shell pm disable-user --user 0 com.netflix.ninja
adb shell pm disable-user --user 0 com.amazon.amazonvideo.livingroom
adb shell pm disable-user --user 0 com.disney.disneyplus
```

### Step 7: Decouple Clock from Google Location Services
Force the TV to synchronize time strictly via standard NTP (Network Time Protocol) rather than Google Location Services / Geo-IP:

```bash
adb shell settings put global auto_time 1
adb shell settings put global ntp_server "pool.ntp.org"
adb shell settings put global auto_time_zone 0
adb shell settings put global time_zone "America/Los_Angeles"

# Verify clock
adb shell "date"
```

### Step 8: Remove Google Account & Neutralize Google Play Services
1. On the TV, go to: **Settings $\rightarrow$ Accounts & Sign-in $\rightarrow$ [Your Google Account] $\rightarrow$ Remove account**.
2. Run the disable commands for Google Play Services frameworks from your PC:
   ```bash
   adb shell pm disable-user --user 0 com.android.vending
   adb shell pm disable-user --user 0 com.google.android.gms
   adb shell pm disable-user --user 0 com.google.android.gsf
   adb shell pm disable-user --user 0 com.google.android.katniss
   adb shell pm disable-user --user 0 com.sony.dtv.assistantadapter
   adb shell pm disable-user --user 0 com.sony.dtv.voicesearch
   adb shell pm disable-user --user 0 com.sony.dtv.voicerecognitionconfirmation
   adb shell pm disable-user --user 0 com.google.android.partnersetup
   adb shell pm disable-user --user 0 com.google.android.onetimeinitializer
   ```

### Step 9: Configure Hardware Remote Buttons in Key Mapper
Open **Key Mapper** on the TV using the remote and configure your triggers:

1. **YouTube Button (Top Left):**
   * Trigger: Record $\rightarrow$ Press **YouTube** button.
   * Action: Add Action $\rightarrow$ **Launch App** $\rightarrow$ Select **SmartTube**.
2. **Netflix Button (Top Right):**
   * Trigger: Record $\rightarrow$ Press **Netflix** button.
   * Action: Add Action $\rightarrow$ **Launch App** $\rightarrow$ Select **Plex**.
3. **Prime Video Button (Bottom Right):**
   * Set to **No Action** (or map to **HTPC Input**):
   * *To map to HTPC (HDMI 4):* Add Action $\rightarrow$ Custom Component / Intent $\rightarrow$ Package: `com.sony.dtv.tvx`, Component: `com.sony.dtv.tvx.MainActivity`.
4. **Disney+ Button (Bottom Left):**
   * Leave unmapped / set to **No Action** (package is disabled; key drops silently).

---

## 7. Emergency Safeguards & Rollback Reference

### Emergency Key Mapper Disarm
If Key Mapper ever misbehaves or accidentally captures navigation buttons (D-pad/Back/Enter), run these commands from your desktop to instantly restore 100% native remote control:
```bash
adb shell am force-stop io.github.sds100.keymapper
adb shell settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService:com.gathin.tvhome/.InputKeyService
```

### Restoring Stock Google TV Launcher
If you ever need to revert to the factory Google TV interface:
```bash
adb shell pm enable com.google.android.apps.tv.launcherx
adb shell pm enable com.google.android.tungsten.setupwraith
adb shell cmd role add-role-holder android.app.role.HOME com.google.android.apps.tv.launcherx
```

### Restoring Google Play Services
If you ever need to restore Google Play Services:
```bash
adb shell pm enable com.android.vending
adb shell pm enable com.google.android.gms
adb shell pm enable com.google.android.gsf
```

---

## 8. Lifecycle Maintenance & Future Updates

### Updating the `tvhome` Launcher
When new upstream stable releases of `cleanyourtv` are tagged:
```bash
# 1. Fetch, clean, and rebuild latest release on PC
~/Projects/AndroidTV/manage_launcher.sh upgrade

# 2. Push in-place update to the TV (-r preserves settings)
adb connect {your TV IP address}:5555
adb install -r ~/Projects/AndroidTV/tvhome.apk
```

### Updating User Apps (Plex, Tidal, Spotify, TV Bro)
* **Plex, Tidal, Spotify, WebView:** Open **Aurora Store** on the TV $\rightarrow$ Go to **Updates** $\rightarrow$ Update apps directly. 
  *(Recommended: Long-press Google Play Services and LauncherX in Aurora's updates list and select "Add to Blacklist").*
* **SmartTube:** Updates automatically via its internal updater prompt.
* **TV Bro:** Updates via Aurora Store or by downloading newer release APKs from GitHub.

### Handling Post-OTA Sony Firmware Updates
If Sony pushes a major OTA system update that re-enables factory packages:
1. Verify Wi-Fi ownership: `adb shell "dumpsys wifi | grep -i cname"`.
2. Re-run the debloat command blocks from **Section 6 (Steps 5, 6, and 8)**.
