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
