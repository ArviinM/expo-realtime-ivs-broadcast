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
//# sourceMappingURL=index.js.map