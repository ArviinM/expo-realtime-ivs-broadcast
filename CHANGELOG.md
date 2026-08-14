# Changelog

All notable changes to `expo-realtime-ivs-broadcast`.

## 0.3.0 — 2026-08-15

### Tooling

- **Expo SDK 57 / React Native 0.86 compatibility.** devDependencies bumped
  (expo ~57, react-native 0.86.2, expo-module-scripts 56, explicit typescript),
  and all type-only imports converted for the `verbatimModuleSyntax` tsconfig
  that new expo-module-scripts enables. No runtime behavior changes.
- Example app regenerated with `expo prebuild --clean` on SDK 57; Android
  example builds green. iOS requires Xcode 26.4+ (SDK 56+ minimum).

## 0.2.9 — 2026-05-13

### Broadcaster

- **Default framerate bumped from 15 fps to 30 fps** on both iOS and Android.
  The IVS Stages SDK defaults to 15 fps which is too choppy for product demos
  in live commerce contexts. Every code path (initial setup, native camera
  stream, custom camera capture, camera swap, mock streams) now lands on 30 fps
  unless JS explicitly overrides via `LocalVideoConfig.targetFramerate`.
- **Default video bitrate range tuned for quality**: 0.5–2.5 Mbps (was: SDK
  defaults of ~0.1–1.5 Mbps). WebRTC's adaptive bitrate scales freely within
  this range — on good networks the encoder pushes up to 2.5 Mbps for clean
  720p portrait detail; on poor networks it stays above the 500 kbps floor so
  the picture remains readable instead of collapsing into block artifacts.
- Added `IVSStageManager.defaultVideoConfig()` static helper on iOS to
  centralize the default video configuration. All fallback paths now share
  the same tuned settings instead of each setting frame size and inheriting
  SDK defaults for framerate and bitrate.

### Viewer

- **`tickRTCStats()` now falls back to a remote video stream** when no local
  camera exists (iOS + Android). Previously the timer early-returned for
  viewer-only sessions (no `cameraStream`), so subscribers received zero
  `onRTCStats` events — making any viewer-side stats HUD impossible. The
  fallback prefers the targeted participant (if `joinStage` was called with
  one) and otherwise picks the first remote participant with a VIDEO stream.
- **`leaveStage()` now proactively emits `onParticipantLeft` for each
  remote participant and clears its internal participants array.** This
  fixes the close→reopen black-screen race where stale participants from
  session A leaked into session B's `useStageParticipants` state and the
  viewer's remote stream view tried to attach to a participant that didn't
  exist on the new stage. The SDK's own disconnect event still fires
  asynchronously and could race the new session's `joinStage()`, wiping
  freshly-arrived state — proactive clearing here closes that window.

### Performance

- `ExpoIVSRemoteStreamView` JS wrapper is now wrapped in `React.memo`.
  The native view already guards against duplicate `participantId` /
  `deviceUrn` assignments, but every parent re-render still serialized a
  fresh props bundle across the JS bridge. With memo, identical props
  short-circuit at the JS layer.

### Notes

- Stages SDK does not support 60 fps. If you need higher framerates, switch to
  the IVS low-latency broadcast SDK (single-publisher only, different module).
- iPhone front cameras can still auto-drop to 15 fps in low light due to
  `AVCaptureDevice` exposure logic — this is an OS-level cap, not an SDK or
  module limit. Improve lighting to keep 30 fps.
- Android: the 1.31 SDK still doesn't expose a public stats-delivery callback,
  so `onRTCStats` continues to fire only on iOS. The Android RTC stats
  fallback is in place so viewers light up automatically when we adopt a
  newer SDK.

## 0.2.8 and earlier

See git history.
