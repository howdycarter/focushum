# FocusHum

A native iPhone and iPad focus timer with generated ambient sound.

## Features

- Use the standard 25-minute focus session, short break, and long break cycle.
- Listen to brown or white noise for free.
- Pro unlocks pink, rain, and café sounds, custom durations, and session history.
- Paused and backgrounded sessions retain accurate remaining time.

No app account is required in the default build. Optional service integrations are disabled until configured.

## Build and run

Open `FocusHum.xcodeproj` and choose the `FocusHum` scheme. Dependencies resolve through Swift Package Manager. The default build does not require a credentials file.

The checked-in scheme includes a local StoreKit fixture. Use normal simulator signing (an ad hoc identity is sufficient) when running the tests; local StoreKit products do not load in an unsigned app on the tested Xcode runtime. The current suite has 20 passing unit and local StoreKit integration tests.

The optional `./setup.sh --config setup-config.json` workflow writes public runtime service values to `Resources/Info.plist` and `project.yml`, then regenerates the project with XcodeGen. `Config/ServiceConfiguration.swift` reads those values. The legacy ignored `Config/Secrets.swift` is not compiled. Never put server secrets or private signing keys in the app.

## Purchases and release

Native StoreKit 2 supplies localized monthly/yearly plans, verified purchases, restore, and revocation handling. Configuring a RevenueCat public client key selects the optional RevenueCat provider. The local fixture prices are unapproved test data, and live App Store products still require verification.

See [build and monetization preparation](docs/BUILD_AND_MONETIZATION.md) for feature boundaries, validation evidence, and remaining physical-device and App Store release gates. The intended seller is Newton & Carter LLC; Apple account changes and signing are deferred.

The app-specific icon is documented in [icon provenance](docs/AppIcon-Prompt.md).

## Support

For FocusHum support, contact [chris@newtonandcarter.com](mailto:chris@newtonandcarter.com) or visit the [support page](https://howdycarter.com/apps/focushum/support). App Review contact: chris@newtonandcarter.com.
