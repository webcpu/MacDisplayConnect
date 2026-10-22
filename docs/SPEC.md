# Spec: Mac Display Connect

## Objective

Build a native Mac utility that performs the user’s working workaround, plus a
minimal visionOS companion that can request the same action while the user is
wearing Apple Vision Pro.

## Tech Stack

- Swift 6
- SwiftUI and Observation
- Network.framework with Bonjour on the local network
- AppKit Accessibility APIs for the Screen Mirroring control
- Swift Testing
- No third-party dependencies

## Commands

```sh
swift test
swift build
./scripts/build-app.sh
open ".build/products/Mac Display Connect.app"
./scripts/system-test.sh --cycles 20
xcodebuild test -workspace MacDisplayConnect.xcworkspace \
  -scheme MacDisplayConnectVision \
  -destination "platform=visionOS Simulator,name=Apple Vision Pro"
xcodebuild -workspace MacDisplayConnect.xcworkspace -scheme MacDisplayConnectVision \
  -destination "generic/platform=visionOS Simulator" build
```

## Project Structure

```text
Apps/Mac/          Mac app sources and focused tests
Apps/Vision/       visionOS app, Xcode project, and focused tests
Shared/Core/       Shared request protocol and pure planning logic
Shared/Transport/  Bonjour discovery, bounded TCP transport, and tests
scripts/           Mac app-bundle packaging
```

## Code Style

Prefer immutable value types and pure transformations. Isolate system effects
behind small adapters.

```swift
func action(for elements: [ControlCenterElement]) -> ControlCenterAction {
    visionProIdentifier(in: elements)
        .map { macVirtualDisplayAction(in: elements, identifier: $0) }
        ?? disclosureAction(in: elements)
}
```

## Testing Strategy

Unit-test the protocol, discovery mapping, state models, and all Control Center
decisions without invoking macOS UI. Test transport through a real loopback TCP
connection. Build and launch the companion on the Vision Pro simulator. The
final Mac Virtual Display connection requires an unlocked physical Vision Pro.
The opt-in system-test launcher exercises repeated connect/disconnect cycles on
that physical device and writes a per-run report. Selection requires exactly one
known device identifier among the actionable Screen Mirroring controls, without
using device names. The obsolete `--vision-pro-name` flag is rejected rather than
silently targeting a different headset.

## Boundaries

- Always: avoid selecting an unrelated AirPlay device; report actionable errors.
- Ask first: dependencies, signing/distribution changes, or private APIs.
- Never: silently disconnect displays or rely on hard-coded display identifiers.

## Success Criteria

- One button initiates the connection from the Mac.
- The visionOS app discovers the running Mac app and requests the same action.
- Mac Virtual Display is selected instead of Mirror Display.
- An already connected Mac Virtual Display is left unchanged.
- Ordinary AirPlay devices are ignored.
- Pure decision tests pass and the runnable `.app` bundle builds.
- The visionOS model tests pass and the companion launches in the simulator.

## Known Boundary

macOS requires Accessibility permission to operate Screen Mirroring. The app
prompts for it once and never automates unrelated applications. The companion
uses one bounded, versioned command on the local network; internet access is not
used. The Mac uses Apple's private SidecarCore framework for read-only device-type
and identifier discovery, matching current Sidecar and AirPlay identifiers to
Screen Mirroring. Connection and disconnection remain Accessibility operations.
Missing or ambiguous matches and unavailable discovery fail closed, with no
device-name fallback. The lookup has been verified on macOS 27; macOS 26 runtime
compatibility remains unverified, and private interfaces may change.
