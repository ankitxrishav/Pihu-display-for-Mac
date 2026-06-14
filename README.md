# Pihu Display for Mac

Pihu Display is a high-performance system tool that lets you use an Android device as a secondary monitor for your Mac over USB. It achieves sub-40ms latency by using hardware video encoding/decoding and USB socket tunneling.

This project consists of two parts:
1. A macOS host command-line app (`mac-host`) written in Swift that creates a virtual screen, encodes it using VideoToolbox, and streams it.
2. An Android client app (`android-client`) written in Kotlin that receives the H.264 stream and decodes it using MediaCodec directly to a SurfaceView.

For details on the internals and system pipelines, read [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Demo

Watch the demo video: [Pihu Display Demo (Google Drive)](https://drive.google.com/file/d/1aMLDORvqV8By20J1PEIvwi7CIceSUwD7/view?usp=sharing)

---

## Setup Guide

Follow these steps to prepare your Mac and Android device for building and running the project.

### 1. Prepare your macOS Host

You need compilation tools, JDK, and Android platform tools installed on your Mac.

#### Install Xcode Command Line Tools
Open your terminal and run:
```bash
xcode-select --install
```
This is required to compile the Swift macOS host app.

#### Install Homebrew (if not already installed)
If you do not have Homebrew, install it using:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### Install Java Development Kit (JDK 17)
The Android gradle build process requires JDK 17. Install it using Homebrew:
```bash
brew install openjdk@17
```
Ensure that Gradle can find it by verifying your path or letting the build script use `/opt/homebrew/opt/openjdk@17` (which is configured by default in `run.sh`).

#### Install Android Command Line Tools (ADB)
You need ADB to install the application on your Android device and forward the TCP port. Install it via Homebrew:
```bash
brew install android-platform-tools
```
Verify the installation by running:
```bash
adb --version
```

---

### 2. Prepare your Android Client Device

You need to enable Developer Options and USB Debugging so your Mac can communicate with your device.

1. Open **Settings** on your Android device.
2. Go to **About Phone**.
3. Tap **Build Number** 7 times until you see the message "You are now a developer!".
4. Go back to Settings -> System -> **Developer Options**.
5. Enable **USB Debugging**.
6. Connect your Android device to your Mac using a USB cable.
7. A prompt will appear on your Android device screen asking to "Allow USB debugging?". Check the box "Always allow from this computer" and tap **Allow**.

Verify that your device is connected and authorized:
```bash
adb devices
```
If your device is listed as `device`, it is ready. If it is listed as `unauthorized`, look at your phone screen and authorize the connection.

---

### 3. Build and Run Pihu Display

With your phone connected and authorized, you can compile and launch the entire stack using the orchestrator script.

1. Navigate to the project directory:
   ```bash
   cd "pihu display"
   ```
2. Make the orchestrator script executable:
   ```bash
   chmod +x run.sh
   ```
3. Run the script:
   ```bash
   ./run.sh
   ```

The script will automate the following operations:
* Check for connected Android devices via ADB.
* Compile the macOS host app using Swift Package Manager.
* Compile the Android client app using Gradle.
* Set up port forwarding: redirects Mac localhost port `27183` to the Android app listening port over USB.
* Install and launch the Android client app on the phone.
* Start the macOS host screen stream.

---

### 4. Configure the Secondary Monitor in macOS

When you run Pihu Display for the first time, macOS will ask you for Screen Recording permissions. This is necessary for `ScreenCaptureKit` to grab the virtual display's framebuffer.

1. Go to Mac **System Settings** -> **Privacy & Security** -> **Screen & System Audio Recording**.
2. Enable permission for `pihu-display-host` (or terminal if running from it).
3. Restart `./run.sh` if needed.
4. Go to **System Settings** -> **Displays**.
5. You will see a monitor named "Pihu Display".
6. You can arrange its layout relative to your main display, or change the configuration (e.g. choose whether to mirror your primary screen or extend it).

To stop the stream, press `Ctrl + C` in the macOS terminal window. The Android app will automatically return to the connection guide layout, waiting for your next session.

---

## Troubleshooting

### Android Screen is Black or Stays on "Waiting for connection"
* Ensure your phone is connected over USB and debugging is allowed.
* Check if port forwarding is active:
  ```bash
  adb forward --list
  ```
  It should show `tcp:27183 tcp:27183`. If not, set it up manually:
  ```bash
  adb forward tcp:27183 tcp:27183
  ```
* Relaunch the Android app. Sometimes the device OS suspends background servers during installation or USB selection dialogs.

### Build Failures
* **Swift Compiler Errors**: Make sure your macOS is version 14.0 or higher. The virtual display APIs are not present on older versions of macOS.
* **JDK/Gradle Errors**: Make sure JDK 17 is installed. If Gradle complains about Java version conflicts, verify that your active shell session points to JDK 17.

---

Created with love by Ankit Kumar for personal use feel free to use it.
