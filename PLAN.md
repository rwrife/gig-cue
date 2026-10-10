# Gig Cue Implementation Plan

Implementation and verification plan for `com.infinityball.gigcue`. **Status: native launch skeleton with package tests and exact-head CI landed; domain persistence, performance view, show builder, and release remain in progress.**

## Scope and architecture

- Target: iPhone-only native Swift iOS application.
- Frameworks: SwiftUI and UIKit with Swift Package Manager and Xcode 26.0.1 (17A400) targeting iOS 26+ SDK.
- Device family: `TARGETED_DEVICE_FAMILY = 1` across all targets. Native iPad support is disabled. Android and iPad are non-goals.
- Prohibited frameworks: No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity.
- Storage: Foundation Codable versioned JSON saved atomically in Application Support; one document per show, plus durable current-song ID. Start without a database dependency; add one only when measured scale requires it.
- Network policy: Zero network access. All features operate fully offline.
- Dual-screen posture: iPhone Duo is a planned target behind a clean `GigWorkspaceLayout` layout seam. The app will build and execute as a standard single-screen iPhone app with no unavailable fold SDK APIs.

## Milestones

1. **Skeleton and CI** — Xcode project with app and UI-test targets, bundle ID `com.infinityball.gigcue`, `TARGETED_DEVICE_FAMILY = 1`, and exact-head GitHub Actions workflow checking package tests, syntax, and platform declarations on Linux and building/testing on macOS.
2. **Local Domain & Storage** — Models for `Show`, `SongCard`, `StageCue`, `BreakMarker`, and performance progress. Zero-data bootstrap and migrations.
3. **Stage Performance View** — High-contrast, glanceable layout for live performance: current song, next song, tempo/key indicators, break banners, and low-latency navigation.
4. **Show Builder & Reordering** — List editing, drag-and-drop reordering, quick cue adjustments, break insertion, and set duplication.
5. **Stage Legibility, Accessibility & Layout Seam** — Dynamic Type support, VoiceOver labels, high-contrast dark palette, and the `GigWorkspaceLayout` abstraction separating stage controls from the set list.
6. **Local Backup, Restore Preview & Text Export** — User-facing JSON export/import with pre-flight validation, plus formatted plain-text setlist sharing for bandmates.
7. **Store Assets, Release Action & TestFlight Gate** — Port proven `rwrife/cook-console` `.github/workflows/release.yml`, generate real `AppStore/icon.png` using `hermes-image-gen`, wire into Xcode asset catalog, and verify App Store Connect distribution prerequisites.

## Testing strategy and dependency order

Implement #1, then #2; #3 and #4 build on persistence; #5 follows usable screens; #6 proves portability; #7 releases only after all earlier acceptance gates pass. Pure-Swift tests cover invalid inputs, stable identities, reorder/resume, break transitions, atomic write failures, migrations and malformed/unknown-version restore with original data preserved. Apple CI must build the exact PR head, check actual pinned Xcode/SDK and built UIDeviceFamily [1], then exercise create/edit/reorder/performance/restore journeys at standard and accessibility text sizes. A zero-network contract gate checks source and dependencies. Record actual run URLs and failures, never equate Linux syntax checks with native execution.

## Packaging and Release

Port the proven cook-console Action without inventing signing: v* tag or manual dispatch, macos-26, mode-600 API key, signed IPA archive/export, TestFlight upload, bounded processing poll and GitHub release. Store processing and native icon compilation require real Apple-runner evidence.

Packaging will use the four configured App Store Connect repository secrets:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and `ASC_TEAM_ID`.
The release workflow will enforce Xcode 26.0.1, the bundle identifier `com.infinityball.gigcue`, and `TARGETED_DEVICE_FAMILY = 1`.
`AppStore/description.txt` will be reviewed against actual features before release.
The final app icon will be generated at `AppStore/icon.png` and linked into Xcode assets without placeholders.

## Risks and Non-Goals

- Non-goal: Real-time audio pitch/tempo listening or tuner features.
- Non-goal: Cloud account sync or real-time remote bandmember collaboration.
- Non-goal: Web scraping or automated lookup of copyrighted lyrics and sheet music.
- Risk: Stage lighting glare and unexpected screen dimming. Mitigated via high-contrast performance theme and deliberate sleep-prevention toggle during active shows.
