# Privacy Policy — Giant Buddy

**Last updated:** March 29, 2026

Giant Buddy is an open-source iOS app for Giant e-bikes with RideControl+ BLE connectivity. This privacy policy explains what data the app collects, how it is used, and your choices.

Source code: [github.com/hilli/giant-logger-ios](https://github.com/hilli/giant-logger-ios)

## Data We Collect

### Location (GPS)
- **What:** Precise GPS coordinates during rides.
- **Why:** To record ride tracks, display maps, calculate distance/speed, provide turn-by-turn navigation, and look up weather and elevation.
- **Storage:** Ride GPS data is stored on-device in SwiftData and synced to your private iCloud account via CloudKit. It is never sent to third-party servers unless you explicitly upload a ride to Strava.

### Health & Fitness (Apple HealthKit)
- **What:** Cycling workouts (distance, duration, calories, route) written to Apple Health. Heart rate read from Apple Watch during rides.
- **Why:** So your rides appear in Apple Fitness and contribute to your Activity rings.
- **Storage:** Managed by Apple HealthKit on your device. Giant Buddy does not export Health data to any external service.

### Bluetooth (BLE)
- **What:** Communication with your Giant e-bike via Bluetooth Low Energy — speed, cadence, torque, motor power, battery level, range, error codes.
- **Why:** To display live telemetry and record ride data.
- **Storage:** Telemetry is stored on-device as part of your ride history.

### Contacts
- **What:** Contact names and phone numbers you select as emergency contacts.
- **Why:** To send an SMS alert with your GPS location if the crash detection feature triggers.
- **Storage:** Emergency contact info is stored locally in UserDefaults on your device only.

### Motion (Accelerometer)
- **What:** Device accelerometer data while riding.
- **Why:** To detect potential crashes and trigger emergency alerts.
- **Storage:** Not stored. Processed in real-time only.

## Third-Party Services

### Strava (optional)
If you connect your Strava account, Giant Buddy can upload ride GPX files to Strava via their API. This is entirely opt-in and requires explicit OAuth authorization. Giant Buddy stores your Strava access token in the iOS Keychain. You can disconnect at any time in Settings.

### Open-Meteo (weather/elevation)
Giant Buddy sends your current GPS coordinates to the [Open-Meteo API](https://open-meteo.com) to fetch weather conditions and elevation data. Open-Meteo is a free, open-source weather API. No API key or account is required. No personal identifiers are sent.

### Apple CloudKit
Ride history and routes are synced to your private iCloud database via Apple CloudKit. This data is only accessible to your Apple ID and is governed by [Apple's privacy policy](https://www.apple.com/legal/privacy/).

## Data We Do NOT Collect

- **No analytics or crash reporting SDKs** — the app contains no third-party tracking code.
- **No advertising** — the app has no ads.
- **No user accounts** — there is no sign-up or login (Strava OAuth is optional and separate).
- **No server-side storage** — all data stays on your device and your private iCloud.

## Your Choices

- **Location:** You can change location permission to "While Using" or "Never" in iOS Settings. Background recording requires "Always" permission.
- **HealthKit:** You can revoke HealthKit access in iOS Settings → Health → Data Access.
- **Strava:** Disconnect in Giant Buddy Settings at any time.
- **Crash Detection:** Disable in Giant Buddy Settings.
- **Delete Data:** Delete individual rides by swiping in the History tab. Uninstalling the app removes all local data.

## Children's Privacy

Giant Buddy is not directed at children under 13 and does not knowingly collect data from children.

## Changes to This Policy

Updates will be posted to this file in the [source repository](https://github.com/hilli/giant-logger-ios/blob/main/PRIVACY.md). The "Last updated" date at the top will be revised accordingly.

## Contact

For questions about this privacy policy, open an issue at [github.com/hilli/giant-logger-ios/issues](https://github.com/hilli/giant-logger-ios/issues).
