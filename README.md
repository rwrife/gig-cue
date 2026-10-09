# Gig Cue

Offline iPhone gig companion for live musicians: glance setlists and key/tempo cues folded, then follow a stage-friendly set flow without accounts or cloud. **Status: planning scaffold only. No app, generated icon, build, or release exists yet.**

## Why and for whom

Solo performers and small bands need reliable, legible cues between songs while hands are occupied. Streaming charts, rehearsals and song libraries solve other jobs; this app keeps a performer-owned show order and short cues close at hand. It does not display copyrighted lyrics or licensed scores by default.

## Intended workflow

1. Create a show and manually enter songs, optional key/tempo, and one-line personal cues. Reorder songs and mark an optional break.
2. In performance mode, see the current song, next song and large next/back controls. A deliberate confirmation prevents accidental skips; the displayed position persists through app restarts.
3. After the show, export the ordered setlist as a local JSON backup or plain-text handout using the iOS share sheet. Restores preview changes before replacing data.

**MVP:** locally saved shows, reorderable song cards, break markers, stage-dimmed high-contrast performance mode, durable progress, JSON backup/restore preview, text export. Unknown key/tempo displays as unknown rather than a guessed value. No automatic tempo detection, backing-track playback, microphone listening, streaming integrations, remote band sync, lyrics scraping, AI, or cloud account.

## Platform and layout

Native Swift (SwiftUI/UIKit) for iPhone, iOS 26+ SDK, Xcode 26.0.1 (17A400), Swift 6. Bundle identifier `com.infinityball.gigcue` registered in App Store Connect. `PRODUCT_BUNDLE_IDENTIFIER = com.infinityball.gigcue`; `TARGETED_DEVICE_FAMILY = 1` in every app build configuration, with built `UIDeviceFamily == [1]` to be verified on an Apple runner. Native iPad support is disabled; iPhone compatibility mode on an iPad is not native support. Android and native iPad release work are out of scope. No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity.

Current build is a standard single-screen iPhone app, not a foldable implementation. Future iPhone Duo design target: full song/order detail on one screen, persistent high-contrast next-song controls on the other. A single `GigWorkspaceLayout` composition seam will accept future platform-provided display topology when APIs mature; no unavailable fold SDK APIs or iPad layout are MVP dependencies. Native iPad support requires explicit user opt-in.

## Data, privacy and access

Device-local shows and progress (Foundation Codable JSON with atomic writes in Application Support), zero network calls and no analytics. A user-initiated Files/share-sheet export is the only outward flow; exported cues can include personal notes, so preview destinations and avoid silent uploads. No permissions needed by default: no location, microphone, camera, contacts, HealthKit or notifications. Optional screen-awake behavior is user-visible and scoped to performance mode; stage-dim control never silently overrides system accessibility preferences. Dynamic Type, VoiceOver labels, large hit targets, reduced motion and high contrast are release gates.

## Milestones

See [PLAN.md](PLAN.md) and the seven linked GitHub issues: native skeleton, local domain, performance mode, edit flow, accessibility/layout, portable export/restore, then icon/release. `AppStore/description.txt` is a draft of the planned experience, not a shipping claim. A real `AppStore/icon.png` must be generated using `hermes-image-gen` after reading the repo and description, then wired into Xcode assets; no placeholder may count as completion.

## Development

This is documentation-only. Once the Xcode project lands, open it with pinned Xcode 26.0.1 and run its shared iPhone simulator scheme. Until then there is no app build or test suite to run on this Linux host. `toolchain.json` is a planning declaration, not verified CI evidence. Keep PRs in isolated worktrees; never commit to shared main from an executor.

## Distribution

The `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` GitHub Actions secrets are set by name only; never print their values. The release issue must port `rwrife/cook-console/.github/workflows/release.yml`: `v*` tag/manual dispatch, macos-26, iOS 26+ SDK check, signed IPA archive/export, App Store Connect API TestFlight upload and processing check, then GitHub release. That Action does not yet exist here. Store copy must be reviewed against implemented behavior before publishing.
