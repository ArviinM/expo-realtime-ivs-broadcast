# Contributing to expo-realtime-ivs-broadcast

Thanks for your interest in contributing! This guide will help you get set up.

## Prerequisites

- Node.js 22+
- Xcode 15+ (for iOS development)
- Android Studio (for Android development)
- An [Amazon IVS](https://aws.amazon.com/ivs/) account with a Real-Time Stage set up (for testing)

## Development Setup

1. Fork and clone the repo:

```bash
git clone https://github.com/<your-username>/expo-realtime-ivs-broadcast.git
cd expo-realtime-ivs-broadcast
```

2. Install dependencies:

```bash
npm install
cd example && npm install
```

3. Build the TypeScript source:

```bash
npm run build
```

4. Run the example app:

```bash
cd example
npx expo prebuild
npx expo run:ios    # or npx expo run:android
```

## Project Structure

```
src/           → TypeScript source (public API, types, hooks, view wrappers)
ios/           → Swift native module (IVSStageManager, PiP controller)
android/       → Kotlin native module (IVSStageManager, PiP manager)
example/       → Example Expo app demonstrating the module
docs/          → Implementation guides and notes
```

## Common Commands

| Command | Description |
|---------|-------------|
| `npm run build` | Compile TypeScript to `build/` |
| `npm run test` | Run tests |
| `npm run clean` | Remove build artifacts |
| `npm run open:ios` | Open iOS project in Xcode |
| `npm run open:android` | Open Android project in Android Studio |

## Making Changes

### TypeScript changes (`src/`)

Run `npm run build` after changes and test with the example app.

### iOS native changes (`ios/`)

Open the example iOS workspace in Xcode (`npm run open:ios`) and build from there. Swift changes are compiled as part of the example app's build.

### Android native changes (`android/`)

Open the example Android project in Android Studio (`npm run open:android`). Kotlin changes are compiled as part of the example app's build.

### Adding a new native method

When adding a new method exposed to JS, you need to update:

1. `src/ExpoRealtimeIvsBroadcastModule.ts` — Add the method signature to the typed interface
2. `src/index.ts` — Add the async wrapper function and export it
3. `src/ExpoRealtimeIvsBroadcast.types.ts` — Add any new types
4. `ios/ExpoRealtimeIvsBroadcastModule.swift` — Implement the method in the iOS module
5. `android/src/main/java/.../ExpoRealtimeIvsBroadcastModule.kt` — Implement the method in the Android module

### Adding a new event

1. Add the event name and payload type in `src/ExpoRealtimeIvsBroadcast.types.ts`
2. Add the listener function in `src/index.ts`
3. Emit the event from both `ios/ExpoRealtimeIvsBroadcastModule.swift` and the Android module

## Pull Request Guidelines

- Create a feature branch from `main`
- Keep PRs focused — one feature or fix per PR
- If your change is platform-specific (iOS or Android only), mention it clearly
- Test on both platforms when possible, or note which platform you tested on
- Run `npm run build` before submitting
- Update the README if your change affects the public API

## Reporting Bugs

When filing a bug, please include:

- Library version and Expo SDK version
- Platform (iOS/Android) and OS version
- Device (physical or simulator)
- Steps to reproduce
- Any relevant error logs from Xcode/Android Studio/Metro

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
