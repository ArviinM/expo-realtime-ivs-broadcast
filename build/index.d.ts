import { EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, StageConnectionStatePayload, PublishStatePayload, StageErrorPayload, CameraSwappedPayload, CameraSwapErrorPayload, ParticipantPayload, ParticipantStreamsPayload, ParticipantStreamsRemovedPayload, PiPOptions, PiPStateChangedPayload, PiPErrorPayload } from './ExpoRealtimeIvsBroadcast.types';
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
//# sourceMappingURL=index.d.ts.map