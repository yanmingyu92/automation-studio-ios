# Workspace conventions

## Applications

- `Apps/FieldReport`: offline field-inspection voice reports.
- `Apps/BarbellLedger`: private strength-training log with FitNotes CSV migration.
- `Apps/DocKeeper`: local document and warranty manager with optional Paperless-ngx sync.

Each application is independent and owns only its directory. Use native Swift 6, SwiftUI, SwiftData where persistence is needed, async/await, StoreKit 2, and an iOS 17 minimum deployment target. Use an XcodeGen `project.yml` and keep the Xcode project generated. Do not add test targets or test files to a project that has none.

## Product requirements

- Core flows must work without an account or backend.
- Do not replace core product behavior with placeholders, simulated transcription, fake purchases, or hardcoded demo results.
- Use original names, icons, layouts, and code. Do not copy GPL/AGPL application code into closed-source products. Preserve MIT and other permissive-license notices.
- Handle permissions, offline states, empty states, errors, cancellation, data export, purchase restoration, Dynamic Type, and VoiceOver labels.
- Keep health, microphone, photo, document, and server data private by default. No third-party analytics or advertising SDKs.
- External model downloads and server connections must be explicit and recoverable. Secrets must come from user input or Keychain, never source control.
- Each app needs StoreKit 2 products appropriate to its pricing experiment, but purchases must remain unavailable until real App Store Connect products exist.

## Growth automation

- `Growth` contains public-data market intelligence and launch-experiment tooling only.
- Use public APIs and feeds with rate limits, caching, provenance, and UTC timestamps. Never fabricate reviews, survey respondents, installs, conversions, or revenue.
- Label inferred themes and synthetic copy as generated outputs, not customer evidence.
- Do not publish, upload, spend advertising money, or contact users automatically. External activation requires explicit credentials and authorization.

## Verification

- Run XcodeGen and available syntax/static checks after changes.
- When full Xcode is available, build every app for an iOS simulator and exercise its real primary flow.
- Do not create README files, research reports, logs, or generated output in source directories. Growth output belongs under ignored `Growth/Output`.
