# App Store submission checklist

## 1. Push metadata and screenshots (API)

`task appstore:push` sets the following through the App Store Connect API:

- name, subtitle and privacy policy URL;
- primary category (Health & Fitness) and secondary category (Navigation);
- copyright;
- description, keywords, promotional text and support URL;
- App Review contact and notes;
- the 6.9" iPhone screenshots and the Apple Watch Ultra screenshots.

The source files are in `metadata/en-US/`, `screenshots/iphone/` and `screenshots/watch/`.

One-time setup:

1. In **App Store Connect → Users and Access → Integrations → App Store Connect API**,
   create a Team key with the **App Manager** role. Download `AuthKey_<KEY_ID>.p8`.
   Apple only lets you download it once.
2. Store the key **outside the repo**, e.g. `~/.appstoreconnect/private_keys/`.
3. Copy `review_contact.local.json.example` to `review_contact.local.json` and fill it in.
   The copy is git-ignored because the repo is public.

Push:

```sh
export ASC_ISSUER_ID=<issuer id>
export ASC_KEY_ID=<key id>
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8

task appstore:push -- --dry-run   # read-only preview
task appstore:push                # apply
```

Re-running the push is safe. It updates fields that already exist and replaces a screenshot set only when its files have changed.
`--skip-screenshots` leaves the screenshots untouched.

To regenerate the iPhone screenshots, run `task appstore:screenshots`. It uses the Debug-only `-ScreenshotMode` demo data in the iPhone 17 Pro Max simulator.

The watch screenshots were captured by hand in an Apple Watch Ultra simulator. Build the
`GiantLogger Watch App Watch App` scheme (Debug) and install it with `simctl install`. Then, for each tab N (0 = metrics, 1 = navigation, 2 = controls, 3 = bike status), run
`xcrun simctl launch <udid> dk.hilli.GiantLogger.watchkitapp -ScreenshotMode YES -ScreenshotTab N`
followed by `xcrun simctl io <udid> screenshot <file>.png`.

## 2. Project settings (Xcode)

- [x] `TARGETED_DEVICE_FAMILY = 1` (iPhone only), for the app and the iOS widget. Without it, App Store Connect also requires 13" iPad screenshots.
- [x] `ITSAppUsesNonExemptEncryption = NO` in `GiantLogger/Info.plist`. The app only uses AES via CommonCrypto for the bike protocol, plus HTTPS. With the key set, App Store Connect skips the export compliance question for every build.
- [ ] Bluetooth usage description: change "Giant Logger" to "Giant Buddy".
- [x] Upload a build. Build 3, the first iPhone-only build, has been uploaded. You can use Xcode Organizer (Archive, then Distribute App, then App Store Connect) or the `task testflight` flow that uses `ExportOptions-AppStore.plist`. `task release` only exports ad-hoc builds.

## 3. Done once via the API (version 1.0)

- [x] **Content rights**: "No, it does not contain, show, or access third-party content".
- [x] **Pricing and availability**: Free, all territories, including new ones.
- [x] **Export compliance**: build 3 is marked as using no non-exempt encryption. Later builds pick this up from the Info.plist key.
- [x] **Build**: build 3 is attached to version 1.0.
- [x] **Apple Watch**: App Store Connect requires watch screenshots because the watch app ships inside the iOS build. They are pushed from `screenshots/watch/`.
- [x] **Draft submission**: version 1.0 has been added to the draft review submission.

## 4. Manual steps in App Store Connect (not available in the API)

- [ ] **App Privacy**: enter the answers from [`app-privacy.md`](app-privacy.md) and publish them.
- [ ] **Age rating**: answer "None" to every question in the questionnaire, which gives 4+.
- [ ] **EU Digital Services Act**: declare non-trader status.
- [ ] **Submit for Review**.

## 5. Risks to be aware of

- **Trademark (guideline 5.2.1)**: "Giant" is a third-party trademark (Giant Manufacturing Co.).
  The description says the app is unofficial and not affiliated with Giant, but App Review
  may still reject an app name that contains "Giant". If they do, rename the app, e.g. "Buddy for Giant E-Bikes".
  Have a fallback ready before submitting.
- **Hardware dependency**: App Review has no bike. The review notes link to a demo video and explain
  which features work without a bike: history, routes and navigation.
