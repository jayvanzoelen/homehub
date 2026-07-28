# Home Hub for iPad

This is a native iPad shell for the existing Home Hub server. It keeps the
server-rendered Home, Board, and Pantry screens, while Scan and Guard use
AVFoundation so the camera works reliably when the server is an ordinary
`http://` address on the local network.

## Compatibility

- iPad (6th generation, 2018)
- iPadOS 15 through iPadOS 17
- Portrait and landscape orientations
- Xcode 15 or newer for building

The 6th-generation iPad cannot upgrade past iPadOS 17, so the deployment target
is intentionally iPadOS 15 rather than a current-only SDK target.

## Install on the iPad

1. On the computer that will stay on your Wi-Fi, start the server:

   ```bash
   uv sync
   uv run homehub
   ```

2. Find that computer's local IP address, such as `192.168.1.10`. Verify that
   `http://192.168.1.10:8787` opens from the iPad.
3. On a Mac, open `ios/HomeHub/HomeHub.xcodeproj` in Xcode.
4. Select the **HomeHub** target, then **Signing & Capabilities**:
   - choose your Apple development team;
   - change `com.homehub.ipad` if Xcode says the bundle identifier is unavailable.
5. Connect the iPad to the Mac, choose it as the run destination, and press Run.
6. On first launch, enter the server address from step 2 and allow **Local
   Network** and **Camera** access.
7. For a fridge kiosk, enable Guided Access in iPad Settings and triple-click
   the Home button while Home Hub is open.

A free Apple development team can install directly from Xcode, but that signing
typically expires after seven days. Persistent distribution requires a paid
Apple Developer account or managed-device deployment.

## Important behavior

- Guard detects motion only while the Guard tab is visible and the app is in
  the foreground. It disarms automatically when monitoring stops because
  iPadOS does not permit continuous background camera capture.
- The app prevents Auto-Lock while it is in the foreground. Guided Access is
  still recommended.
- Plain HTTP is allowed only to support a trusted local Home Hub server. Do not
  expose port 8787 to the public internet.
- The native app still requires the Python Home Hub server; it does not store a
  separate copy of household data.

## What is a PWA?

A Progressive Web App (PWA) is a website that can be added to the iPad Home
Screen and launched with an app-like icon. The original Home Hub remains
available as a PWA, but iPad WebKit requires a secure origin for browser camera
APIs. The native client avoids that limitation by using the iPad camera
directly.

## Tests

On macOS with an iOS Simulator installed:

```bash
xcodebuild test \
  -project ios/HomeHub/HomeHub.xcodeproj \
  -scheme HomeHub \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)'
```

The camera preview requires a physical iPad for meaningful testing.
