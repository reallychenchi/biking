# Codex Working Guide

## Scope

- This repository contains one iPhone app under `iOS/bike/` plus product documentation under `docs/`.
- Keep changes scoped. Preserve unrelated dirty or generated files; do not edit backups under `iOS/backups/` or `*.backup` files.
- Never expose or commit secrets. Treat telemetry identifiers and release configuration as sensitive even when already present in source.
- Do not claim a build, test, lint, simulator, device, or live-location check passed unless it was actually run.
- If a requested contract, privacy behavior, remote API, migration, or release setting is not established by code or docs, stop and mark it “需要人工确认”.

## Read First: Task Routing

- Architecture, ownership, dependency direction, startup, persistence, networking, or extension work: read `ARCHITECTURE.md`.
- Product behavior, metric definitions, permission copy, UI acceptance, or offline expectations: read `docs/iOS骑行App需求文档.md`, then verify it against current source because known drift is listed in `ARCHITECTURE.md`.
- App startup, dependency composition, SwiftData container, or telemetry initialization: inspect `iOS/bike/bike/bikeApp.swift` and `iOS/bike/bike/AppModel.swift`.
- Navigation or app lifecycle: inspect `iOS/bike/bike/ContentView.swift`.
- Ride state, timing, checkpoint, save/retry, or background behavior: inspect `iOS/bike/bike/Features/Ride/RideSessionController.swift`.
- Location permission/update behavior: inspect `iOS/bike/bike/Services/RideTrackingService.swift`.
- GPS filtering, distance, speed, or moving-time semantics: inspect `iOS/bike/bike/Domain/LocationSampleValidator.swift`, `iOS/bike/bike/Domain/MovementTimeAccumulator.swift`, and `iOS/bike/bike/Domain/RideModels.swift`.
- Storage schema, mapping, unfinished rides, or deletion: inspect `iOS/bike/bike/Persistence/RideRepository.swift`, `iOS/bike/bike/Persistence/SwiftDataRideRepository.swift`, and `iOS/bike/bike/Persistence/RideEntities.swift`.
- History/detail/route UI: inspect `iOS/bike/bike/Features/History/`.
- Dependencies or deployment settings: inspect `iOS/bike/Podfile`, `iOS/bike/Podfile.lock`, and `iOS/bike/bike.xcodeproj/project.pbxproj`.
- Unit and UI test coverage: inspect `iOS/bike/bikeTests/bikeTests.swift` and `iOS/bike/bikeUITests/`.

## Design and Change Rules

- Preserve the dependency direction documented in `ARCHITECTURE.md`: Views/features use domain types and protocols; concrete SwiftData stays in `Persistence/`.
- Keep ride persistence behind `RideRepository`; do not access SwiftData `ModelContext` from Views or feature controllers.
- Feed location samples through `LocationSampleValidator`; do not duplicate thresholds or fabricate fallback coordinates, distance, speed, or time.
- Put reusable metric rules in `Domain/` with named constants and targeted tests. Keep formatting separate from calculation.
- Keep mutable UI coordinators on `@MainActor`; keep persistence context isolated by the existing ModelActor repository.
- Use explicit dependency injection for replaceable side effects. Do not add global singletons when a protocol boundary already exists.
- Prefer high cohesion and low coupling, but do not introduce layers or abstractions without a current responsibility.
- Do not silently recover from invariant, persistence, permission, or SDK configuration failures. Surface errors in state/UI and logs according to existing patterns.
- Keep important operation success at info level, warnings at warning level, and failures at error level via `iOS/bike/bike/Services/AppLog.swift`.
- When changing `Podfile`, run dependency resolution intentionally and review `Podfile.lock`; do not perform unrelated dependency upgrades.

## Workspace and Dependencies

Open and build the CocoaPods workspace, not the project:

```bash
open iOS/bike/bike.xcworkspace
```

Install locked dependencies only when Pods are absent or dependency declarations changed:

```bash
cd iOS/bike && pod install
```

## Build

Use an available iPhone simulator; replace the example name if needed:

```bash
xcodebuild build \
  -workspace iOS/bike/bike.xcworkspace \
  -scheme bike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

List schemes or available simulators when the destination is unknown:

```bash
xcodebuild -list -workspace iOS/bike/bike.xcworkspace
xcrun simctl list devices available
```

## Tests

Run domain/repository/controller unit tests first:

```bash
xcodebuild test \
  -workspace iOS/bike/bike.xcworkspace \
  -scheme bike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:bikeTests
```

Run UI tests separately when navigation, launch, accessibility, or screenshots change:

```bash
xcodebuild test \
  -workspace iOS/bike/bike.xcworkspace \
  -scheme bike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:bikeUITests
```

Current known issue: after the Umeng analytics/APM integration, the unit-test target may fail to resolve `UMAPM` and `UMCommon`. Report this exact failure; do not claim tests passed or alter dependency wiring unless the task authorizes a fix. See `ARCHITECTURE.md`.

## Lint and Validation

No SwiftLint configuration or lint target exists. Do not invent a SwiftLint requirement. Always run whitespace/patch validation:

```bash
git diff --check
```

For Swift implementation changes, use Xcode static analysis in addition to build/tests:

```bash
xcodebuild analyze \
  -workspace iOS/bike/bike.xcworkspace \
  -scheme bike \
  -destination 'generic/platform=iOS Simulator'
```

For ride/location changes, add or update focused cases in `iOS/bike/bikeTests/bikeTests.swift`. State separately whether live GPS, background/lock-screen behavior, offline maps, simulator UI, and physical-device behavior were verified.

## Documentation

- Update `ARCHITECTURE.md` when modules, dependency direction, ownership, entry points, persistence, networking, or extension boundaries change.
- Update `docs/iOS骑行App需求文档.md` only for confirmed product decisions; do not use architecture docs to silently redefine product behavior.
- Use real repository paths and mark unresolved facts “需要人工确认”. Avoid copying detailed architecture into this file.
- Local `AGENTS.md` files are unnecessary unless a subtree gains materially different commands or rules.
