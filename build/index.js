import ExpoRealtimeIvsBroadcastModule from './ExpoRealtimeIvsBroadcastModule';
// Re-export all type definitions
export * from './ExpoRealtimeIvsBroadcast.types';
// Export the native view components
export { ExpoIVSStagePreviewView } from './ExpoIVSStagePreviewView';
export { ExpoIVSRemoteStreamView } from './ExpoIVSRemoteStreamView';
// Export the custom hook
export { useStageParticipants } from './useStageParticipants';
// --- Native Module Methods ---
export async function initializeStage(audioConfig, videoConfig) {
    return await ExpoRealtimeIvsBroadcastModule.initializeStage(audioConfig, videoConfig);
}
export async function initializeLocalStreams(audioConfig, videoConfig) {
    return await ExpoRealtimeIvsBroadcastModule.initializeLocalStreams(audioConfig, videoConfig);
}
export async function joinStage(token, options) {
    return await ExpoRealtimeIvsBroadcastModule.joinStage(token, options);
}
export async function leaveStage() {
    return await ExpoRealtimeIvsBroadcastModule.leaveStage();
}
export async function setStreamsPublished(published) {
    return await ExpoRealtimeIvsBroadcastModule.setStreamsPublished(published);
}
export async function swapCamera() {
    return await ExpoRealtimeIvsBroadcastModule.swapCamera();
}
export async function setMicrophoneMuted(muted) {
    return await ExpoRealtimeIvsBroadcastModule.setMicrophoneMuted(muted);
}
export async function requestPermissions() {
    return await ExpoRealtimeIvsBroadcastModule.requestPermissions();
}
// --- Event Emitter ---
export function addOnStageConnectionStateChangedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onStageConnectionStateChanged', listener);
}
export function addOnPublishStateChangedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onPublishStateChanged', listener);
}
export function addOnStageErrorListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onStageError', listener);
}
export function addOnCameraSwappedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onCameraSwapped', listener);
}
export function addOnCameraSwapErrorListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onCameraSwapError', listener);
}
export function addOnParticipantJoinedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantJoined', listener);
}
export function addOnParticipantLeftListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantLeft', listener);
}
export function addOnParticipantStreamsAddedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantStreamsAdded', listener);
}
export function addOnParticipantStreamsRemovedListener(listener) {
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
export async function enablePictureInPicture(options) {
    return await ExpoRealtimeIvsBroadcastModule.enablePictureInPicture(options);
}
/**
 * Disable Picture-in-Picture mode and clean up resources.
 */
export async function disablePictureInPicture() {
    return await ExpoRealtimeIvsBroadcastModule.disablePictureInPicture();
}
/**
 * Manually start Picture-in-Picture mode.
 * PiP must be enabled first via `enablePictureInPicture()`.
 */
export async function startPictureInPicture() {
    return await ExpoRealtimeIvsBroadcastModule.startPictureInPicture();
}
/**
 * Stop Picture-in-Picture mode and return to full screen.
 *
 * @remarks
 * On Android, this is a hint to the system - PiP is typically exited by user interaction.
 */
export async function stopPictureInPicture() {
    return await ExpoRealtimeIvsBroadcastModule.stopPictureInPicture();
}
/**
 * Check if Picture-in-Picture is currently active.
 *
 * @returns Promise resolving to true if PiP is currently active
 */
export async function isPictureInPictureActive() {
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
export async function isPictureInPictureSupported() {
    return await ExpoRealtimeIvsBroadcastModule.isPictureInPictureSupported();
}
// --- PiP Event Listeners ---
/**
 * Add a listener for PiP state changes.
 *
 * @param listener Callback function receiving state: 'started' | 'stopped' | 'restored'
 * @returns EventSubscription to remove the listener
 */
export function addOnPiPStateChangedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onPiPStateChanged', listener);
}
/**
 * Add a listener for PiP errors.
 *
 * @param listener Callback function receiving error message
 * @returns EventSubscription to remove the listener
 */
export function addOnPiPErrorListener(listener) {
    return ExpoRealtimeIvsBroadcastModule.addListener('onPiPError', listener);
}
//# sourceMappingURL=index.js.map