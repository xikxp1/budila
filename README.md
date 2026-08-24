# Budila

Budila is an iPhone alarm clock for iOS 26.1 and later. It uses AlarmKit for system alarms and AVFoundation to verify a pre-enrolled QR code.

AlarmKit always performs its system stop action before Budila's intent runs. Budila works around that limit by scheduling a guard at the next three-minute snooze slot, or one minute later after both snoozes have passed. A valid QR scan cancels the guard. This makes dismissal harder to skip, but iOS does not provide an unbypassable stop button.

If the enrolled QR code is lost or unreachable, Emergency Recovery uses Face ID, Touch ID, or the iPhone passcode to stop all Budila alarms and clear the QR code. Recovery disables every alarm until you enroll a new QR code and turn the alarms back on.

## Install

[Download the latest IPA](https://github.com/xikxp1/budila/releases/latest/download/Budila.ipa) or use TestFlight.

## Build

The project needs Xcode 26.1 or later.

1. Open `Budila.xcodeproj`.
2. Select an Apple Developer team for both targets.
3. Run on an iPhone with iOS 26.1 or later. AlarmKit and camera behavior need a physical device for acceptance testing.
