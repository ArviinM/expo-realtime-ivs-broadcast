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
} from './ExpoRealtimeIvsBroadcast.types';

// Re-export all type definitions
export * from './ExpoRealtimeIvsBroadcast.types';

// Export the native view components
export { ExpoIVSStagePreviewView } from './ExpoIVSStagePreviewView';
export { ExpoIVSRemoteStreamView } from './ExpoIVSRemoteStreamView';

// Export the custom hook
export { useStageParticipants } from './useStageParticipants';

// --- Native Module Methods ---
export async function initialize(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.initialize(audioConfig, videoConfig);
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

export async function requestPermissions(): Promise<PermissionStatusMap> {
  return await ExpoRealtimeIvsBroadcastModule.requestPermissions();
}

export async function triggerRemoteStreamTest(): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.triggerRemoteStreamTest();
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
