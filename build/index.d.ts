import { EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, StageConnectionStatePayload, PublishStatePayload, StageErrorPayload, CameraSwappedPayload, CameraSwapErrorPayload, ParticipantPayload, ParticipantStreamsPayload, ParticipantStreamsRemovedPayload, PiPOptions, PiPStateChangedPayload, PiPErrorPayload, PiPSourceValidityPayload, AudioPreset, AudioInputDevice, AudioRouteChangedPayload, AudioInterruptionPayload, AudioLevelPayload, RTCStatsPayload, RemoteMuteStatePayload, SubscribeStatePayload, BackgroundBehaviorOptions, ThermalMitigationOptions, ThermalState, ThermalStateChangedPayload } from './ExpoRealtimeIvsBroadcast.types';
export * from './ExpoRealtimeIvsBroadcast.types';
export { ExpoIVSStagePreviewView } from './ExpoIVSStagePreviewView';
export { ExpoIVSRemoteStreamView } from './ExpoIVSRemoteStreamView';
export { useStageParticipants } from './useStageParticipants';
export declare function initializeStage(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
export declare function initializeLocalStreams(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
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
export declare function destroyLocalStreams(): Promise<void>;
export declare function joinStage(token: string, options?: {
    targetParticipantId?: string;
}): Promise<void>;
export declare function leaveStage(): Promise<void>;
export declare function setStreamsPublished(published: boolean): Promise<void>;
export declare function swapCamera(): Promise<void>;
/**
 * Rebuild the local capture stream on the CURRENT camera and re-publish it.
 *
 * Recovery for a capture that died while the host app was backgrounded: on
 * Android the OS takes the camera from a backgrounded app, and the existing
 * stream comes back dead — publishing continues but every frame is frozen.
 * Swapping cameras fixed it in the field precisely because it rebuilds the
 * stream; this does the same without changing which camera is in use.
 *
 * Android only today; resolves as a no-op elsewhere.
 */
export declare function refreshCameraStream(): Promise<void>;
export declare function setMicrophoneMuted(muted: boolean): Promise<void>;
/**
 * Mute or unmute the camera.
 * When muted, a placeholder frame with text is sent instead of camera video.
 * @param muted - Whether to mute the camera
 * @param placeholderText - Optional text to show on placeholder (default: "Host is away")
 */
export declare function setCameraMuted(muted: boolean, placeholderText?: string): Promise<void>;
/**
 * Check if the camera is currently muted
 */
export declare function isCameraMuted(): Promise<boolean>;
export declare function requestPermissions(): Promise<PermissionStatusMap>;
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
export declare function setAudioPreset(preset: AudioPreset): Promise<void>;
/**
 * List all audio input devices available for selection.
 * Updates dynamically as devices are connected/disconnected — subscribe to
 * `addOnAudioRouteChangedListener` to re-fetch on changes.
 */
export declare function listAudioInputs(): Promise<AudioInputDevice[]>;
/**
 * Set the preferred audio input device. Pass the `urn` returned from `listAudioInputs()`,
 * or `null` to revert to the system default.
 *
 * Note: the OS retains final say over routing — when AirPods connect mid-stream
 * the OS may auto-switch to them regardless of preference. The
 * `onAudioRouteChanged` event will tell you what actually became active.
 */
export declare function setPreferredAudioInput(urn: string | null): Promise<void>;
/**
 * Software gain boost on top of the OS hardware level. `1.0` = no boost,
 * range `0.0`–`5.0` (clamped). Useful when the built-in mic is too quiet and
 * the user is too far from the phone.
 *
 * @returns `true` if applied, `false` if the active input doesn't support gain
 *          (e.g., built-in iPhone mic on iOS — gain isn't settable for that input).
 */
export declare function setInputGain(gain: number): Promise<boolean>;
/**
 * Enable a debug-only mock camera that synthesizes frames without using the
 * physical camera. Lets you exercise the full IVS lifecycle on iOS Simulator
 * and Android Emulator without needing Continuity Camera or a connected webcam.
 *
 * Safe to call on release builds — it's a no-op outside DEBUG.
 */
export declare function setMockMode(enabled: boolean): Promise<void>;
export declare function addOnStageConnectionStateChangedListener(listener: (event: StageConnectionStatePayload) => void): EventSubscription;
export declare function addOnPublishStateChangedListener(listener: (event: PublishStatePayload) => void): EventSubscription;
export declare function addOnStageErrorListener(listener: (event: StageErrorPayload) => void): EventSubscription;
export declare function addOnCameraSwappedListener(listener: (event: CameraSwappedPayload) => void): EventSubscription;
export declare function addOnCameraSwapErrorListener(listener: (event: CameraSwapErrorPayload) => void): EventSubscription;
export declare function addOnCameraMuteStateChangedListener(listener: (event: {
    muted: boolean;
    placeholderActive: boolean;
}) => void): EventSubscription;
export declare function addOnParticipantJoinedListener(listener: (event: ParticipantPayload) => void): EventSubscription;
export declare function addOnParticipantLeftListener(listener: (event: ParticipantPayload) => void): EventSubscription;
export declare function addOnParticipantStreamsAddedListener(listener: (event: ParticipantStreamsPayload) => void): EventSubscription;
export declare function addOnParticipantStreamsRemovedListener(listener: (event: ParticipantStreamsRemovedPayload) => void): EventSubscription;
/**
 * Fires when the active audio input device changes (AirPods connect, headphones
 * unplug, user picks a different device).
 */
export declare function addOnAudioRouteChangedListener(listener: (event: AudioRouteChangedPayload) => void): EventSubscription;
/**
 * Fires on audio session interruption (incoming phone call, Siri, etc.) and resume.
 * iOS only — Android handles this automatically through the OS.
 */
export declare function addOnAudioInterruptionListener(listener: (event: AudioInterruptionPayload) => void): EventSubscription;
/**
 * Real-time mic audio level (peak + rms in dB). Fires ~10x/sec while a mic
 * stream is active. Plot the peak on a meter so the broadcaster can verify
 * their mic is actually hot before going live.
 */
export declare function addOnAudioLevelListener(listener: (event: AudioLevelPayload) => void): EventSubscription;
/**
 * Periodic WebRTC stats (bitrate, RTT, packet loss, jitter, fps). Fires every
 * ~2 seconds while a stream is publishing or subscribing.
 */
export declare function addOnRTCStatsListener(listener: (event: RTCStatsPayload) => void): EventSubscription;
/**
 * Fires when a remote participant mutes/unmutes a stream. Use to drive the
 * mic / camera muted icons on remote-participant tiles.
 */
export declare function addOnRemoteMuteStateChangedListener(listener: (event: RemoteMuteStatePayload) => void): EventSubscription;
/**
 * Fires when the local subscribe state changes. Android only — on iOS this
 * information is folded into the connection-state event.
 */
export declare function addOnSubscribeStateChangedListener(listener: (event: SubscribeStatePayload) => void): EventSubscription;
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
export declare function setBackgroundBehavior(options: BackgroundBehaviorOptions): Promise<void>;
/**
 * One-shot RTC stats fetch. Use when you want stats at a specific moment
 * (e.g., right after the user complains about quality) without subscribing to
 * the 2s polling event.
 */
export declare function requestRTCStats(): Promise<RTCStatsPayload>;
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
export declare function setThermalMitigation(options: ThermalMitigationOptions): Promise<void>;
/**
 * Read the current thermal state synchronously (well, via a promise).
 */
export declare function getThermalState(): Promise<ThermalState>;
/**
 * Fires when the device thermal state changes. Hook this to your network-stats
 * HUD or a "device hot" warning banner.
 */
export declare function addOnThermalStateChangedListener(listener: (event: ThermalStateChangedPayload) => void): EventSubscription;
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
export declare function enablePictureInPicture(options?: PiPOptions): Promise<boolean>;
/**
 * Disable Picture-in-Picture mode and clean up resources.
 */
export declare function disablePictureInPicture(): Promise<void>;
/**
 * Manually start Picture-in-Picture mode.
 * PiP must be enabled first via `enablePictureInPicture()`.
 */
export declare function startPictureInPicture(): Promise<void>;
/**
 * Stop Picture-in-Picture mode and return to full screen.
 *
 * @remarks
 * On Android, this is a hint to the system - PiP is typically exited by user interaction.
 */
export declare function stopPictureInPicture(): Promise<void>;
/**
 * Check if Picture-in-Picture is currently active.
 *
 * @returns Promise resolving to true if PiP is currently active
 */
export declare function isPictureInPictureActive(): Promise<boolean>;
/**
 * Check if Picture-in-Picture is supported on this device.
 *
 * @returns Promise resolving to true if PiP is supported
 *
 * @remarks
 * - iOS: Requires iOS 15.0+
 * - Android: Requires Android 8.0+ (API 26+) and device/activity support
 */
export declare function isPictureInPictureSupported(): Promise<boolean>;
/**
 * Whether the native PiP remote source is currently a real rendering view (true)
 * vs the device.previewView() fallback (false). Diagnostic only — prefer the
 * onPiPSourceValidityChanged event for the authoritative ready signal.
 */
export declare function isPiPRemoteSourceValid(): Promise<boolean>;
/**
 * Add a listener for PiP state changes.
 *
 * @param listener Callback function receiving state: 'started' | 'stopped' | 'restored'
 * @returns EventSubscription to remove the listener
 */
export declare function addOnPiPStateChangedListener(listener: (event: PiPStateChangedPayload) => void): EventSubscription;
/**
 * Add a listener for PiP errors.
 *
 * @param listener Callback function receiving error message
 * @returns EventSubscription to remove the listener
 */
export declare function addOnPiPErrorListener(listener: (event: PiPErrorPayload) => void): EventSubscription;
/**
 * Add a listener for PiP remote-source validity changes — fires true when the
 * native source becomes a real rendering view, false on the placeholder fallback.
 */
export declare function addOnPiPSourceValidityChangedListener(listener: (event: PiPSourceValidityPayload) => void): EventSubscription;
//# sourceMappingURL=index.d.ts.map