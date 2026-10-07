# App Store submission checklist

## 1. Push metadata and screenshots (API)

`task appstore:push` sets the following through the App Store Connect API:

- name, subtitle and privacy policy URL;
- primary category (Health & Fitness) and secondary category (Navigation);
- copyright;
- description, keywords, promotional text and support URL;
- App Review contact and notes;
- the 6.9" iPhone screenshots.

The source files are in `metadata/en-US/` and `screenshots/iphone/`.

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

Re-running the push is safe. It updates fields that already exist and replaces the screenshots in the 6.9" set.
`--skip-screenshots` leaves the screenshots untouched.

To regenerate the screenshots, run `task appstore:screenshots`. It uses the Debug-only `-ScreenshotMode` demo data in the iPhone 17 Pro Max simulator.

## 2. Project settings (Xcode)

- [ ] `TARGETED_DEVICE_FAMILY = 1` (iPhone only). Without it, App Store Connect also requires 13" iPad screenshots.
- [ ] `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`. The app only uses AES via CommonCrypto for the bike protocol, plus HTTPS. With the key set, App Store Connect skips the export compliance question for every build.
- [ ] Bluetooth usage description: change "Giant Logger" to "Giant Buddy".
- [ ] Upload a build. Use Xcode Organizer: Archive, then Distribute App, then App Store Connect. Alternatively, use the `task testflight` flow that uses `ExportOptions-AppStore.plist`. It isn't on `main` yet. `task release` only exports ad-hoc builds.

## 3. Manual steps in App Store Connect (not available in the API)

- [ ] **App Privacy**: enter the answers from [`app-privacy.md`](app-privacy.md) and publish them.
- [ ] **Age rating**: answer "None" to every question in the questionnaire, which gives 4+.
- [ ] **Content rights**: "No, it does not contain, show, or access third-party content".
- [ ] **Pricing and availability**: Free, all territories.
- [ ] **EU Digital Services Act**: declare non-trader status.
- [ ] **Export compliance**: answer "No proprietary/non-exempt encryption", unless the Info.plist key above is set.
- [ ] **Build**: select the uploaded build on version 1.0.
- [ ] **Apple Watch**: the watch app ships inside the iOS build. Watch screenshots are optional and not included.
- [ ] **Submit for Review**.

## 4. Risks to be aware of

- **Trademark (guideline 5.2.1)**: "Giant" is a third-party trademark (Giant Manufacturing Co.).
  The description says the app is unofficial and not affiliated with Giant, but App Review
  may still reject an app name that contains "Giant". If they do, rename the app, e.g. "Buddy for Giant E-Bikes".
  Have a fallback ready before submitting.
- **Hardware dependency**: App Review has no bike. The review notes link to a demo video and explain
  which features work without a bike: history, routes and navigation.
