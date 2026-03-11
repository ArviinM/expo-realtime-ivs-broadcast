# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Expo module wrapping Amazon IVS Real-Time Streaming SDK for iOS and Android. Enables live streaming with Picture-in-Picture support in React Native/Expo apps. Published to npm as `expo-realtime-ivs-broadcast`.

## Build & Development Commands

```bash
# Build TypeScript to /build
npm run build            # or: expo-module build

# Lint
npm run lint             # or: expo-module lint

# Run tests
npm run test             # or: expo-module test

# Clean build artifacts
npm run clean

# Open native projects
npm run open:ios         # Opens Xcode
npm run open:android     # Opens Android Studio
```

The example app lives in `example/` and uses Expo Router. Run it with `npx expo run:ios` or `npx expo run:android` from the example directory.

## Architecture

**Expo Module Bridge Pattern:** JS/TS → Native module (Swift/Kotlin) via `expo-modules-core`.

### TypeScript Layer (`src/`)

- **`index.ts`** — Public API. Wraps all native module methods as async functions, re-exports types, views, and hooks.
- **`ExpoRealtimeIvsBroadcastModule.ts`** — Typed native module interface using `requireNativeModule`.
- **`ExpoRealtimeIvsBroadcast.types.ts`** — All TypeScript type definitions (configs, events, participants, PiP).
- **`useStageParticipants.ts`** — React hook managing real-time participant list from native events. Tracks participants by ID, deduplicates streams by device URN.
- **`ExpoIVSStagePreviewView.tsx`** / **`ExpoIVSRemoteStreamView.tsx`** — Thin native view wrappers for local camera preview and remote participant video.

### iOS Native (`ios/`) — Swift, iOS 14+

- **`ExpoRealtimeIvsBroadcastModule.swift`** — Module entry point, delegates to `IVSStageManager` singleton.
- **`IVSStageManager.swift`** — Core logic. Contains `CustomCameraCapture` (custom AVFoundation wrapper, not IVS SDK's built-in camera). Camera discovery uses fallback chain. Camera mute generates placeholder frames rather than releasing hardware.
- **`IVSPictureInPictureController.swift`** — PiP via `AVPlayerViewController`. Custom video composition for local camera PiP. Multitasking camera on iOS 16+.
- Pod dependency: `AmazonIVSBroadcast/Stages ~> 1.36.0`

### Android Native (`android/`) — Kotlin, API 28+

- **`ExpoRealtimeIvsBroadcastModule.kt`** — Module entry point with singleton `IVSStageManager`.
- **`IVSStageManager.kt`** — Implements `Stage.Strategy` and `StageRenderer` interfaces. Device discovery via IVS SDK.
- **`PictureInPictureManager.kt`** — Activity-level PiP with auto-enter on background.
- Dependency: `com.amazonaws:ivs-broadcast:1.31.0:stages@aar`

### Key Design Decisions

- **Custom camera capture (iOS):** Uses AVFoundation directly instead of IVS SDK's camera to support back camera and multitasking.
- **Hardware lifecycle:** `initializeLocalStreams()` acquires camera/mic; `destroyLocalStreams()` fully releases them. Camera muting is separate (uses placeholder frames, keeps hardware).
- **Event-driven state:** 12 event types emitted from native to JS (connection, publish, participants, PiP). All prefixed with `on`.
- **Singleton managers:** Both platforms use a singleton `IVSStageManager` instance.

## Conventions

- Event names: camelCase with `on` prefix (e.g., `onParticipantJoined`, `onPiPStateChanged`)
- iOS view classes: `Expo` prefix + descriptive name (e.g., `ExpoIVSStagePreviewView`)
- Kotlin package: `expo.modules.realtimeivsbroadcast`
- ESLint: extends `universe/native` and `universe/web`
- TypeScript: strict mode, extends `expo/tsconfig.base`
- Build tooling: `expo-module-scripts` handles build, lint, test pipelines
