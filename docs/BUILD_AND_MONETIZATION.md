# FocusHum build and monetization preparation

This repository contains the prepared app source. The intended seller is **Newton & Carter LLC**. Store records and products are configured separately in App Store Connect; a local build or fixture does not establish that they are live. Signing, sandbox verification, and submission remain release gates.

## Building

Open `FocusHum.xcodeproj` and select the `FocusHum` scheme. The tracked `Config/ServiceConfiguration.swift` supplies empty optional integration values, so a clean checkout builds without a credentials file. The original bundle identifier is preserved. The shared scheme uses a local StoreKit configuration for interactive debug purchases; archive/release uses App Store products. Run the unit tests with normal simulator signing (an ad hoc identity is sufficient); disabling code signing prevents local StoreKit product loading on this Xcode runtime.

Set public service identifiers through Info.plist only when the corresponding service is configured. Native StoreKit 2 is the purchase provider by default. A configured RevenueCat public client key selects the existing RevenueCat provider. No private keys belong in this app.

## Paid features

Free: standard 25/5/15 focus/break cycle with brown and white noise. Pro: pink, rain and café sounds, history/statistics, and custom timer durations.

Product identifiers are in `Secrets.storeProductIdentifiers` and remain unchanged. The owner approved **US $2.99 per month or $19.99 per year** for continued access to FocusHum Pro tools. The fixture `Tests/Fixtures/FocusHum.storekit` now reflects those approved amounts for local testing. Runtime prices come only from Apple's localized product data; the app has no hardcoded live-price fallback. App Store Connect configuration and actual sandbox transactions still require verification.

The provider verifies transactions, observes updates, restores Apple purchases, and removes access after revocation. Missing products leave the free app usable. The paywall states recurring billing and presents restore and close controls.

## Release gates still open

- Confirm the approved monthly/yearly products, prices, US availability, and subscription group in App Store Connect.
- Review the final privacy declarations for whichever optional integrations are enabled. The bundled manifest currently declares the app's private UserDefaults use; it does not replace App Store privacy answers.
- Verify sound quality, audio route changes, interruptions, and background playback on a physical iPhone.
- Sign the final build and perform a sandbox/TestFlight purchase and restore rehearsal before submission.

The app-specific icon prompt and provenance are in `AppIcon-Prompt.md`.

## Accessibility

Home text and sound labels use semantic Dynamic Type styles. The timer scales relative to the system text setting and separates its ring/readout at accessibility sizes. History statistics and rows switch to vertical layouts for larger text.

## Validation

- Accessibility follow-up: native simulator build passed, with normal and largest-text phone/iPad layouts visually inspected. The home screen scrolls to keep controls reachable.

- Xcode 27 / iOS 27 simulator: 20 unit and local StoreKit integration tests passed. Coverage includes timer suspension, pause/resume history, skipped sessions, long breaks, saved settings, and the free/Pro duration boundary.
- StoreKit tests exercise localized products, actual test purchases, restoring into a fresh service, asynchronous refund revocation, and unknown-product rejection.
- A generic iOS Release archive builds without a signing identity. Signing remains deferred.
- Generated icons are opaque 1024 × 1024 assets; in-app logos use the full-resolution source and respect Reduce Motion.

Local StoreKit success does not verify App Store Connect, Apple’s sandbox, or a production transaction. The RevenueCat path remains optional and needs its own configured-project validation if enabled.

The setup wizard now writes public runtime service values into `Resources/Info.plist`, which `Config/ServiceConfiguration.swift` reads. The legacy ignored `Secrets.swift` is not compiled. Do not enter server secrets or private signing keys. XcodeGen preserves the local StoreKit fixture through `project.yml`.

## Published support and privacy

The app links to the [privacy policy](https://howdycarter.com/apps/focushum/privacy) and [Apple standard terms](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/). The [support page](https://howdycarter.com/apps/focushum/support) is ready for App Store Connect metadata. The privacy and support routes were checked live on October 13, 2026. These pages describe the default local build; enabling an optional service requires reviewing the policy and App Store declarations again.

Business support and App Review contact: [chris@newtonandcarter.com](mailto:chris@newtonandcarter.com), Newton & Carter LLC.

## Encryption declaration

`project.yml` and the generated `Resources/Info.plist` set `ITSAppUsesNonExemptEncryption` to `false`. This describes the reviewed iOS Release configuration, including linked libraries. Apple permits this value when encryption is absent or exempt; OS-provided encryption such as URLSession HTTPS is generally exempt from documentation upload. [Apple encryption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) · [Info.plist key definition](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

The October 13, 2026 dependency audit covered Supabase 2.55.3, TelemetryDeck 1.5.1, RevenueCat 5.95.0 and their actual iOS Release target graph. Network transport uses Foundation URLSession. Hashing, nonce generation, signature checks and keychain access use Apple CryptoKit, CommonCrypto or Security. Supabase’s Swift Crypto 4.5.2 `Crypto` target re-exports CryptoKit on iOS; its BoringSSL, CryptoExtras and CXKCP implementations are excluded from this build graph. The archive links Apple CryptoKit/Security and has no matching BoringSSL/OpenSSL symbols. No app-defined encryption implementation was found. Empty optional service configuration is not the basis for this declaration: linked code was inspected too.

Reassess this declaration when dependencies, platform flags or cryptography change. It does not settle privacy answers, distribution signing or any separate developer export obligations. Final archive verification must confirm the value is a Boolean `false` in the built app.


## Lifecycle regression follow-up (October 13, 2026)

The lifecycle patch adds deterministic tests for audio interruption policy, headphone disconnection, engine/media reset, start failure and retry, adaptive break volume, running/paused session recovery, overdue completion exactly once, legacy unfinished sessions, save failure/retry, and reset cleanup.

These new tests have **not been compiled or executed** in the Linux review environment, which has neither Swift nor Apple SDKs. A whitespace/diff check is not an XCTest or end-to-end pass. Run the full FocusHum scheme tests on an authorized Mac and retain the xcresult before merging.

Recovery behavior: a reopened active session is restored paused with elapsed wall time applied; a session that expired while closed is completed once and its next phase stays stopped. No automatic audio playback starts on relaunch. Headphone removal pauses sound without automatically moving it to a speaker. Interruption resume requires both previous playback intent and the system's should-resume option; manual pause cancels that intent. Audio/start and history-save failures now expose a retry action.

Still required on a physical iPhone: fresh install and onboarding; wired/Bluetooth unplug and reconnect; call/Siri interruption; screen lock and background audio; kill/reopen a running or paused session; auto-start breaks on and off; large text/VoiceOver through new notices; signed sandbox purchase/restore. Injected playback tests are policy tests, not proof that AVAudioEngine or hardware notifications behave correctly on a device.
