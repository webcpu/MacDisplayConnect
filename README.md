# Mac Display Connect

Start Mac Virtual Display from Apple Vision Pro, even when your Mac screen
isn’t in view.

Mac Display Connect includes two apps:

- The **Mac app** controls the existing Screen Mirroring interface.
- The **Apple Vision Pro app** finds your Mac and asks it to connect.

Both apps communicate directly over your local network. Keep the Mac app open
while using the Apple Vision Pro app.

## Before you begin

Make sure that:

- Your Mac is running macOS 26 or later.
- Your Mac and Apple Vision Pro are signed in to the same Apple Account using
  two-factor authentication.
- iCloud Keychain is turned on for both devices.
- Wi-Fi and Bluetooth are turned on for both devices.
- Both devices are connected to the same local network.
- The devices are within 10 meters (30 feet) of each other, and neither device
  is sharing its internet connection.
- Apple Vision Pro is unlocked, being worn, and isn’t using Guest User.
- Xcode 26 or later is installed and selected as the active developer
  directory.

The Mac app targets macOS 26. The included Xcode project targets visionOS 26.

To share the pointer between macOS and visionOS apps, turn on Handoff on both
devices. See [Apple’s Mac Virtual Display requirements][apple-requirements] for
more information.

## Build and run Mac Display Connect on your Mac

1. Open Terminal.
2. Go to the root of the project folder.
3. Build and run the Mac app:

   ```sh
   ./run.sh
   ```

The run script closes any existing Mac Display Connect instance, builds and
signs the app bundle, and opens the app. Use it rather than `swift run` so the
Accessibility and Local Network permission prompts are associated with the app
bundle.

## Create a Mac installer

Install the DMG layout tools once:

```sh
npm install --global create-dmg@7.1.0
brew install graphicsmagick imagemagick
```

Create and open a DMG for local installation:

```sh
./make-dmg.sh
```

Drag **Mac Display Connect** to the **Applications** shortcut in the opened
DMG. This local DMG is intended for your own Mac. Use the release script below
to create a signed and notarized build for distribution.

### Allow Accessibility access

Mac Display Connect needs Accessibility access to operate Screen Mirroring.

1. Open **Mac Display Connect** on your Mac.
2. Select **Connect**.
3. When macOS asks for permission, open **System Settings**.
4. Go to **Privacy & Security > Accessibility**.
5. Turn on **Mac Display Connect**.
6. Return to Mac Display Connect and leave the app open.

If macOS asks for Local Network access, select **Allow**.

## Install Mac Display Connect on Apple Vision Pro

1. Connect Apple Vision Pro to Xcode.
2. Open `MacDisplayConnect.xcworkspace`.
3. Select the **MacDisplayConnectVision** scheme.
4. Choose your Apple Vision Pro as the run destination.
5. In **Signing & Capabilities**, select your development team if Xcode asks.
6. Select **Run**.

The app is installed as **Mac Display Connect**. The first time you open it,
allow Local Network access so it can find your Mac.

## Connect from Apple Vision Pro

1. Open **Mac Display Connect** on your Mac and leave it running.
2. Wear and unlock Apple Vision Pro.
3. Open **Mac Display Connect** on Apple Vision Pro.
4. Wait for your Mac to appear.
5. Select **Connect** next to your Mac.

The connecting symbol rotates while your Mac opens Screen Mirroring and starts
Mac Virtual Display. Mac Display Connect selects the extended desktop option,
not screen mirroring. When the connection is ready, the app shows
**Connected**.

## Connect from your Mac

You can also start the same connection directly from the Mac app.

1. Wear and unlock Apple Vision Pro.
2. Open **Mac Display Connect** on your Mac.
3. Select **Connect**.

Mac Display Connect selects Mac Virtual Display as an extended desktop instead
of mirroring the Mac’s built-in display.

## If your Mac doesn’t appear

- Make sure Mac Display Connect is open on your Mac.
- Make sure both devices are on the same local network.
- Check that Local Network access is enabled for Mac Display Connect on both
  devices.
- Turn Wi-Fi and Bluetooth off and on, then reopen both apps.

## If Mac Display Connect can’t connect

- Make sure Apple Vision Pro is being worn and is unlocked.
- Confirm that both devices use the same Apple Account with two-factor
  authentication.
- Make sure iCloud Keychain is turned on for both devices.
- Make sure Apple Vision Pro isn’t using Guest User.
- Confirm that Screen Mirroring is available in Control Center on your Mac.
- Check **System Settings > Privacy & Security > Accessibility** and make sure
  Mac Display Connect is enabled.
- Try **Connect** again after a few seconds.

### View diagnostic information

Open the diagnostic log in Console:

```sh
open -a Console \
  "$HOME/Library/Logs/Mac Display Connect/Mac Display Connect.log"
```

The log is stored at
`~/Library/Logs/Mac Display Connect/Mac Display Connect.log`.

## Privacy and security

Mac Display Connect communicates only on your local network. The Apple Vision
Pro app can request two fixed actions: connect and check connection status.
Connect requests include the device name reported by visionOS so the Mac can
choose the matching Apple Vision Pro in Screen Mirroring.

Mac Display Connect doesn’t:

- Send data over the internet.
- Install a display driver.
- Replace Apple’s Mac Virtual Display protocol.
- Use private display APIs.
- Control unrelated applications.

## For developers

Open `MacDisplayConnect.xcworkspace` to access the Mac and Apple Vision Pro
schemes.

Run the Swift package tests:

```sh
swift test
```

Run the Apple Vision Pro app tests:

```sh
xcodebuild test -workspace MacDisplayConnect.xcworkspace \
  -scheme MacDisplayConnectVision \
  -destination "platform=visionOS Simulator,name=Apple Vision Pro"
```

### Run the physical-device system test

The system test repeatedly connects and disconnects a physical Apple Vision Pro
through macOS Control Center:

```sh
./scripts/system-test.sh --cycles 20 \
  --vision-pro-name "S’s Apple Vision Pro"
```

Before starting, quit **Mac Display Connect** and keep Apple Vision Pro worn,
unlocked, and within range for the entire run. Make sure Accessibility access is
already enabled for the signed Mac app bundle. The system-test script rebuilds
that app and refuses to start while another copy is running. System-test mode is
explicit: if Mac Virtual Display is already connected, its preflight disconnects
it before the counted cycles begin.

Every cycle confirms the disconnected state, connects, verifies a stable
connection, keeps it connected for five seconds, disconnects, and verifies a
stable disconnected state. A run passes only when every requested cycle passes.
Reports and failure logs are stored under
`~/Library/Logs/Mac Display Connect/System Tests/`.

This exercises the real Mac Virtual Display lifecycle on physical hardware. It
does not automate the native visionOS app interface.

Build and run the Mac app:

```sh
./run.sh
```

### Release the Mac app

Release a signed and notarized Mac build from a clean, synchronized `main`
branch:

```sh
./scripts/release.sh 1.0.0
```

The script runs the Swift package tests, builds and validates a Release app,
creates a notarized DMG, tags the release, and publishes it to GitHub. It uses
the `xdigest-notary` keychain profile by default. Set
`MAC_DISPLAY_CONNECT_NOTARY_PROFILE` to use a different profile. This releases
only the macOS app; distribute the Apple Vision Pro app separately through
Xcode or TestFlight.

### Project layout

```text
Apps/Mac/               Mac app sources and tests
Apps/Vision/            Apple Vision Pro app, Xcode project, and tests
Shared/Core/            Shared protocol and pure connection-planning logic
Shared/Transport/       Local Bonjour discovery and request transport
run.sh                  Build and open the Mac app
make-dmg.sh             Build and open a local drag-to-install DMG
scripts/build-app.sh    Shared app-bundle builder used by the other scripts
scripts/release.sh      Signed, notarized GitHub release workflow
scripts/system-test.sh  Optional physical-device regression test
docs/                   Design and testing documentation
```

For implementation details and testing boundaries, see the
[project specification](docs/SPEC.md).

[apple-requirements]: https://support.apple.com/guide/apple-vision-pro/use-mac-virtual-display-tan357ede966/visionos
