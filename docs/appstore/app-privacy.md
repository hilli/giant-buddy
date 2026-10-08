# App Privacy answers (App Store Connect → App Privacy)

These answers can't be set through the App Store Connect API. Enter them manually
in **App Store Connect → Giant Buddy → App Privacy**. They follow the conservative
approach and match `GiantLogger/PrivacyInfo.xcprivacy` and `PRIVACY.md`.

## Privacy Policy URL

`https://github.com/hilli/giant-buddy/blob/main/PRIVACY.md`

## Data collection

**Do you or your third-party partners collect data from this app?** → **Yes**

Apple's definition of "collect" is "transmitted off the device". Several features
send data off the device: CloudKit sync, Strava upload, WeatherKit,
Open-Meteo elevation lookups and emergency SMS. The data goes to services
that the user has turned on, not to the developer, but declaring it is the
safe choice and it matches the privacy manifest.

## Data types to declare

For every type below the answers are the same:

| Question | Answer |
|---|---|
| Used for tracking? | **No** |
| Linked to the user's identity? | **No** |
| Purpose | **App Functionality** only |

| Category → Type | Why it's declared |
|---|---|
| **Location → Precise Location** | GPS is recorded into rides, synced through the user's private iCloud (CloudKit), uploaded to Strava when the user enables it, and sent to WeatherKit and Open-Meteo (elevation) as coordinates. |
| **Health & Fitness → Health** | Heart rate from Apple Watch is written to HealthKit workouts. The app writes to HealthKit but never reads from it. Ride samples with heart rate sync through the user's private iCloud. |
| **Health & Fitness → Fitness** | Ride metrics (distance, speed, power, cadence, calories) are written as HealthKit cycling workouts, synced through private iCloud and uploaded to Strava when the user enables it. |
| **Contacts → Contacts** | Up to three emergency contacts picked by the user. Their details leave the device only in an SMS that the user reviews and sends after a detected crash. |

### Not collected (do not tick)

- Identifiers, Usage Data, Diagnostics, Purchases, Financial Info, Browsing/Search History, Sensitive Info, Other Data
- Name, Email, Phone Number (of the user), User ID, Device ID
- Coarse Location (the app only uses Precise Location)
- Advertising Data, and anything used for **Tracking**

## Supporting facts (verified in code)

- No analytics, crash reporting, advertising SDKs or tracking domains. `NSPrivacyTracking = false`.
- HealthKit (`WorkoutManager.swift`) is write-only. `typesToRead` is empty and the app writes workouts, distanceCycling, activeEnergyBurned and heartRate.
- Strava OAuth tokens are stored in the Keychain (`StravaService.swift`). Uploads only happen after the user connects Strava and turns uploads on.
- CloudKit uses the user's **private** database. The developer has no access to it.
- Emergency contacts are stored in UserDefaults on the device. `CrashDetector` opens the `sms:` composer and the user has to tap Send.
- WeatherKit receives the current coordinates for weather. Open-Meteo receives route coordinates for elevation only.
- Bluetooth traffic to the bike stays on the device.
