import { EventSubscription } from 'expo-modules-core';
import ExpoRealtimeIvsBroadcastModule from './ExpoRealtimeIvsBroadcastModule';
import {
    LocalAudioConfig,
    LocalVideoConfig,
    PermissionStatusMap,
    StageConnectionStatePayload,
    PublishStatePayload,
    StageErrorPayload,
    CameraSwappedPayload,
    CameraSwapErrorPayload,
    ParticipantPayload,
    ParticipantStreamsPayload,
    ParticipantStreamsRemovedPayload,
    PiPOptions,
    PiPStateChangedPayload,
    PiPErrorPayload,
    PiPSourceValidityPayload,
    AudioPreset,
    AudioInputDevice,
    AudioRouteChangedPayload,
    AudioInterruptionPayload,
    AudioLevelPayload,
    RTCStatsPayload,
    RemoteMuteStatePayload,
    SubscribeStatePayload,
    BackgroundBehaviorOptions,
    ThermalMitigationOptions,
    ThermalState,
    ThermalStateChangedPayload,
} from './ExpoRealtimeIvsBroadcast.types';

// Re-export all type definitions
export * from './ExpoRealtimeIvsBroadcast.types';

// Export the native view components
export { ExpoIVSStagePreviewView } from './ExpoIVSStagePreviewView';
export { ExpoIVSRemoteStreamView } from './ExpoIVSRemoteStreamView';

// Export the custom hook
export { useStageParticipants } from './useStageParticipants';

// --- Native Module Methods ---
export async function initializeStage(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.initializeStage(audioConfig, videoConfig);
}

export async function initializeLocalStreams(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.initializeLocalStreams(audioConfig, videoConfig);
}

/**
 * Destroy local camera and microphone streams, fully releasing hardware resources.
 * This is the symmetric teardown counterpart to `initializeLocalStreams()`.
 *
 * Call this when the broadcast session is completely finished to turn off the
 * camera indicator and free hardware. After calling this, you must call
 * `initializeLocalStreams()` again before using the camera or microphone.
 *
 * @remarks
 * - On iOS, this stops the AVCaptureSession which turns off the green camera indicator.
 * - On Android, this releases the camera and microphone device streams.
 * - `setCameraMuted(true)` does NOT release hardware — it only stops sending frames.
 * - `leaveStage()` does NOT release hardware — it only disconnects from the IVS stage.
 */
export async function destroyLocalStreams(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.destroyLocalStreams();
}

export async function joinStage(token: string, options?: { targetParticipantId?: string }): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.joinStage(token, options);
}

export async function leaveStage(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.leaveStage();
}

export async function setStreamsPublished(published: boolean): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setStreamsPublished(published);
}

export async function swapCamera(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.swapCamera();
}

export async function setMicrophoneMuted(muted: boolean): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setMicrophoneMuted(muted);
}

/**
 * Mute or unmute the camera.
 * When muted, a placeholder frame with text is sent instead of camera video.
 * @param muted - Whether to mute the camera
 * @param placeholderText - Optional text to show on placeholder (default: "Host is away")
 */
export async function setCameraMuted(muted: boolean, placeholderText?: string): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setCameraMuted(muted, placeholderText ?? null);
}

/**
 * Check if the camera is currently muted
 */
export async function isCameraMuted(): Promise<boolean> {
  return await ExpoRealtimeIvsBroadcastModule.isCameraMuted();
}

export async function requestPermissions(): Promise<PermissionStatusMap> {
  return await ExpoRealtimeIvsBroadcastModule.requestPermissions();
}

// --- Audio API ---

/**
 * Set the audio session preset. Controls echo cancellation, noise suppression,
 * gain, and which speaker the audio plays out of.
 *
 * - **`videoChat`** (default): Two-way communication. AEC/NS/AGC ON. Lower input gain.
 *   Use when the host needs the speaker open and the mic open simultaneously.
 * - **`subscribeOnly`**: Viewer mode. Routes through media volume (loud).
 *   Use this for buyer/viewer screens — fixes the "audio comes out earpiece" bug.
 * - **`studio`**: Highest quality. AEC/NS/AGC OFF. Best perceived loudness on the
 *   built-in mic and proper level when an external mic is plugged in.
 *   **Use this for sellers / broadcasters** unless you need echo cancellation.
 *
 * Call this **before** `joinStage()` for cleanest results. Changing mid-stream
 * causes a brief audio glitch on iOS.
 *
 * @platform iOS — fully implemented via IVSStageAudioManager
 * @platform Android — implemented via StageAudioManager where supported
 */
export async function setAudioPreset(preset: AudioPreset): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setAudioPreset(preset);
}

/**
 * List all audio input devices available for selection.
 * Updates dynamically as devices are connected/disconnected — subscribe to
 * `addOnAudioRouteChangedListener` to re-fetch on changes.
 */
export async function listAudioInputs(): Promise<AudioInputDevice[]> {
  return await ExpoRealtimeIvsBroadcastModule.listAudioInputs();
}

/**
 * Set the preferred audio input device. Pass the `urn` returned from `listAudioInputs()`,
 * or `null` to revert to the system default.
 *
 * Note: the OS retains final say over routing — when AirPods connect mid-stream
 * the OS may auto-switch to them regardless of preference. The
 * `onAudioRouteChanged` event will tell you what actually became active.
 */
export async function setPreferredAudioInput(urn: string | null): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setPreferredAudioInput(urn);
}

/**
 * Software gain boost on top of the OS hardware level. `1.0` = no boost,
 * range `0.0`–`5.0` (clamped). Useful when the built-in mic is too quiet and
 * the user is too far from the phone.
 *
 * @returns `true` if applied, `false` if the active input doesn't support gain
 *          (e.g., built-in iPhone mic on iOS — gain isn't settable for that input).
 */
export async function setInputGain(gain: number): Promise<boolean> {
  return await ExpoRealtimeIvsBroadcastModule.setInputGain(gain);
}

// --- Mock Mode (DEBUG only) ---

/**
 * Enable a debug-only mock camera that synthesizes frames without using the
 * physical camera. Lets you exercise the full IVS lifecycle on iOS Simulator
 * and Android Emulator without needing Continuity Camera or a connected webcam.
 *
 * Safe to call on release builds — it's a no-op outside DEBUG.
 */
export async function setMockMode(enabled: boolean): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setMockMode(enabled);
}

// --- Event Emitter ---
export function addOnStageConnectionStateChangedListener(
  listener: (event: StageConnectionStatePayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onStageConnectionStateChanged', listener);
}

export function addOnPublishStateChangedListener(
  listener: (event: PublishStatePayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onPublishStateChanged', listener);
}

export function addOnStageErrorListener(
  listener: (event: StageErrorPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onStageError', listener);
}

export function addOnCameraSwappedListener(
  listener: (event: CameraSwappedPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onCameraSwapped', listener);
}

export function addOnCameraSwapErrorListener(
  listener: (event: CameraSwapErrorPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onCameraSwapError', listener);
}

export function addOnCameraMuteStateChangedListener(
  listener: (event: { muted: boolean; placeholderActive: boolean }) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onCameraMuteStateChanged', listener);
}

export function addOnParticipantJoinedListener(
  listener: (event: ParticipantPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantJoined', listener);
}

export function addOnParticipantLeftListener(
  listener: (event: ParticipantPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantLeft', listener);
}

export function addOnParticipantStreamsAddedListener(
  listener: (event: ParticipantStreamsPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantStreamsAdded', listener);
}

export function addOnParticipantStreamsRemovedListener(
  listener: (event: ParticipantStreamsRemovedPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantStreamsRemoved', listener);
}

/**
 * Fires when the active audio input device changes (AirPods connect, headphones
 * unplug, user picks a different device).
 */
export function addOnAudioRouteChangedListener(
  listener: (event: AudioRouteChangedPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onAudioRouteChanged', listener);
}

/**
 * Fires on audio session interruption (incoming phone call, Siri, etc.) and resume.
 * iOS only — Android handles this automatically through the OS.
 */
export function addOnAudioInterruptionListener(
  listener: (event: AudioInterruptionPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onAudioInterruption', listener);
}

/**
 * Real-time mic audio level (peak + rms in dB). Fires ~10x/sec while a mic
 * stream is active. Plot the peak on a meter so the broadcaster can verify
 * their mic is actually hot before going live.
 */
export function addOnAudioLevelListener(
  listener: (event: AudioLevelPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onAudioLevel', listener);
}

/**
 * Periodic WebRTC stats (bitrate, RTT, packet loss, jitter, fps). Fires every
 * ~2 seconds while a stream is publishing or subscribing.
 */
export function addOnRTCStatsListener(
  listener: (event: RTCStatsPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onRTCStats', listener);
}

/**
 * Fires when a remote participant mutes/unmutes a stream. Use to drive the
 * mic / camera muted icons on remote-participant tiles.
 */
export function addOnRemoteMuteStateChangedListener(
  listener: (event: RemoteMuteStatePayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onRemoteMuteStateChanged', listener);
}

/**
 * Fires when the local subscribe state changes. Android only — on iOS this
 * information is folded into the connection-state event.
 */
export function addOnSubscribeStateChangedListener(
  listener: (event: SubscribeStatePayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onSubscribeStateChanged', listener);
}

/**
 * Configure how the SDK should behave when the host app enters background.
 * Without this call, the SDK keeps publishing camera+audio — wasting battery
 * and bandwidth — and keeps subscribing to remote video.
 *
 * Recommended for broadcaster: `{ stopPublishing: true, subscribeMode: 'audioOnly' }`.
 *
 * Note: the host app must also declare the right background modes
 * (UIBackgroundModes=audio on iOS, foreground service on Android) — this
 * function only configures the SDK's strategy, not the OS-level entitlements.
 */
export async function setBackgroundBehavior(options: BackgroundBehaviorOptions): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setBackgroundBehavior(options);
}

/**
 * One-shot RTC stats fetch. Use when you want stats at a specific moment
 * (e.g., right after the user complains about quality) without subscribing to
 * the 2s polling event.
 */
export async function requestRTCStats(): Promise<RTCStatsPayload> {
  return await ExpoRealtimeIvsBroadcastModule.requestRTCStats();
}

// --- Thermal Adaptation ---

/**
 * Configure auto-downshift behavior under thermal pressure. When enabled, the
 * SDK observes `ProcessInfo.thermalState` (iOS) / `PowerManager` (Android
 * API 29+) and automatically drops to `reducedFramerate` when the device reaches
 * 'serious' or 'critical' state.
 *
 * @example
 * ```ts
 * await setThermalMitigation({ enabled: true, reducedFramerate: 15 });
 * ```
 *
 * Subscribe to `addOnThermalStateChangedListener` to surface the current state in your UI.
 */
export async function setThermalMitigation(options: ThermalMitigationOptions): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.setThermalMitigation(options);
}

/**
 * Read the current thermal state synchronously (well, via a promise).
 */
export async function getThermalState(): Promise<ThermalState> {
  return await ExpoRealtimeIvsBroadcastModule.getThermalState();
}

/**
 * Fires when the device thermal state changes. Hook this to your network-stats
 * HUD or a "device hot" warning banner.
 */
export function addOnThermalStateChangedListener(
  listener: (event: ThermalStateChangedPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onThermalStateChanged', listener);
}

// --- Picture-in-Picture Methods ---

/**
 * Enable Picture-in-Picture mode with the given options.
 *
 * @param options Configuration options for PiP behavior
 * @returns Promise resolving to true if PiP was enabled successfully
 *
 * @platform iOS 15.0+, Android 8.0+ (API 26+)
 *
 * @remarks
 * - iOS: Requires `UIBackgroundModes` with `audio` in Info.plist for background playback
 * - Android: The consuming app must add `android:supportsPictureInPicture="true"` to their Activity
 */
export async function enablePictureInPicture(options?: PiPOptions): Promise<boolean> {
  return await ExpoRealtimeIvsBroadcastModule.enablePictureInPicture(options);
}

/**
 * Disable Picture-in-Picture mode and clean up resources.
 */
export async function disablePictureInPicture(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.disablePictureInPicture();
}

/**
 * Manually start Picture-in-Picture mode.
 * PiP must be enabled first via `enablePictureInPicture()`.
 */
export async function startPictureInPicture(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.startPictureInPicture();
}

/**
 * Stop Picture-in-Picture mode and return to full screen.
 *
 * @remarks
 * On Android, this is a hint to the system - PiP is typically exited by user interaction.
 */
export async function stopPictureInPicture(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.stopPictureInPicture();
}

/**
 * Check if Picture-in-Picture is currently active.
 *
 * @returns Promise resolving to true if PiP is currently active
 */
export async function isPictureInPictureActive(): Promise<boolean> {
  return await ExpoRealtimeIvsBroadcastModule.isPictureInPictureActive();
}

/**
 * Check if Picture-in-Picture is supported on this device.
 *
 * @returns Promise resolving to true if PiP is supported
 *
 * @remarks
 * - iOS: Requires iOS 15.0+
 * - Android: Requires Android 8.0+ (API 26+) and device/activity support
 */
export async function isPictureInPictureSupported(): Promise<boolean> {
  return await ExpoRealtimeIvsBroadcastModule.isPictureInPictureSupported();
}

/**
 * Whether the native PiP remote source is currently a real rendering view (true)
 * vs the device.previewView() fallback (false). Diagnostic only — prefer the
 * onPiPSourceValidityChanged event for the authoritative ready signal.
 */
export async function isPiPRemoteSourceValid(): Promise<boolean> {
  return await ExpoRealtimeIvsBroadcastModule.isPiPRemoteSourceValid();
}

// --- PiP Event Listeners ---

/**
 * Add a listener for PiP state changes.
 *
 * @param listener Callback function receiving state: 'started' | 'stopped' | 'restored'
 * @returns EventSubscription to remove the listener
 */
export function addOnPiPStateChangedListener(
  listener: (event: PiPStateChangedPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onPiPStateChanged', listener);
}

/**
 * Add a listener for PiP errors.
 *
 * @param listener Callback function receiving error message
 * @returns EventSubscription to remove the listener
 */
export function addOnPiPErrorListener(
  listener: (event: PiPErrorPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onPiPError', listener);
}

/**
 * Add a listener for PiP remote-source validity changes — fires true when the
 * native source becomes a real rendering view, false on the placeholder fallback.
 */
export function addOnPiPSourceValidityChangedListener(
  listener: (event: PiPSourceValidityPayload) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onPiPSourceValidityChanged', listener);
}
