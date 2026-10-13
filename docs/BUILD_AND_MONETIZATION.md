# FocusHum build and monetization preparation

This branch is a local preparation build. No App Store products, prices, subscriptions, business account settings, or releases have been published. The intended seller is **Newton & Carter LLC**; updating the Apple account and signing are deferred at the owner’s request.

## Building

Open `FocusHum.xcodeproj` and select the `FocusHum` scheme. The tracked `Config/ServiceConfiguration.swift` supplies empty optional integration values, so a clean checkout builds without a credentials file. The original bundle identifier is preserved. The shared scheme uses a local StoreKit configuration for interactive debug purchases; archive/release uses App Store products. Run the unit tests with normal simulator signing (an ad hoc identity is sufficient); disabling code signing prevents local StoreKit product loading on this Xcode runtime.

Set public service identifiers through Info.plist only when the corresponding service is configured. Native StoreKit 2 is the purchase provider by default. A configured RevenueCat public client key selects the existing RevenueCat provider. No private keys belong in this app.

## Paid features

Free: standard 25/5/15 focus/break cycle with brown and white noise. Pro: pink, rain and café sounds, history/statistics, and custom timer durations.

Product identifiers are in `Secrets.storeProductIdentifiers`. Prices come from Apple's localized product data. The fixture `Tests/Fixtures/FocusHum.storekit` contains **unapproved test prices**, copied from pre-existing demo values only for local validation. They are not a pricing recommendation or evidence that any live product exists. FocusHum's app-specific product identifiers are proposed replacements for generic SwiftKit sample IDs and require App Store Connect setup before release.

The provider verifies transactions, observes updates, restores Apple purchases, and removes access after revocation. Missing products leave the free app usable. The paywall states recurring billing and presents restore and close controls.

## Release gates still open

- Choose and approve real pricing and create matching products in App Store Connect.
- Replace the existing placeholder terms and privacy URLs with published app-specific pages.
- Review the final privacy declarations for whichever optional integrations are enabled. The bundled manifest currently declares the app's private UserDefaults use; it does not replace App Store privacy answers.
- Verify sound quality, audio route changes, interruptions, and background playback on a physical iPhone.
- Sign the final build and perform a sandbox/TestFlight purchase and restore rehearsal before submission.

The app-specific icon prompt and provenance are in `AppIcon-Prompt.md`.

## Validation

- Xcode 27 / iOS 27 simulator: 17 unit and local StoreKit integration tests passed. Coverage includes timer suspension, pause/resume history, skipped sessions, long breaks, saved settings, and the free/Pro duration boundary.
- StoreKit tests exercise localized products, actual test purchases, restoring into a fresh service, asynchronous refund revocation, and unknown-product rejection.
- A generic iOS Release archive builds without a signing identity. Signing remains deferred.
- Generated icons are opaque 1024 × 1024 assets; in-app logos use the full-resolution source and respect Reduce Motion.

Local StoreKit success does not verify App Store Connect, Apple’s sandbox, or a production transaction. The RevenueCat path remains optional and needs its own configured-project validation if enabled.

The setup wizard now writes public runtime service values into `Resources/Info.plist`, which `Config/ServiceConfiguration.swift` reads. The legacy ignored `Secrets.swift` is not compiled. Do not enter server secrets or private signing keys. XcodeGen preserves the local StoreKit fixture through `project.yml`.
