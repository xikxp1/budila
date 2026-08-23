# Budila

Budila is an iPhone alarm clock for iOS 26.1 and later. It uses AlarmKit for system alarms and VisionKit to verify a pre-enrolled QR code.

AlarmKit always performs its system stop action before Budila's intent runs. Budila works around that limit by scheduling a guard alarm 10 seconds later. A valid QR scan cancels the guard. This makes dismissal harder to skip, but iOS does not provide an unbypassable stop button.

## Build

The project needs Xcode 26.1 or later. This Mac has Xcode 16.2, so use the included GitHub Action or a newer Mac to compile it.

1. Open `Budila.xcodeproj`.
2. Select an Apple Developer team for both targets.
3. Run on an iPhone with iOS 26.1 or later. AlarmKit and camera behavior need a physical device for acceptance testing.

## TestFlight

Create the App Store Connect record for `dev.xikxp1.budila`, then add these GitHub Actions secrets:

- `APPLE_TEAM_ID`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY`

`ASC_PRIVATE_KEY` contains the raw contents of the `.p8` App Store Connect key. The API key must be allowed to use cloud-managed distribution certificates. Pull requests and pushes to `main` run tests. A manual workflow run archives without local signing, uses Xcode cloud signing to export the IPA, and uploads build `github.run_number` with `apple-actions/upload-testflight-build`.
