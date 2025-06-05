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
} from './ExpoRealtimeIvsBroadcast.types';

// Re-export all type definitions
export * from './ExpoRealtimeIvsBroadcast.types';

// Export the native view component
export { IVSStagePreviewView } from './ExpoRealtimeIvsBroadcastView';

// --- Native Module Methods ---
export async function initialize(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.initialize(audioConfig, videoConfig);
}

export async function joinStage(token: string): Promise<void> {
  return await ExpoRealtimeIvsBroadcastModule.joinStage(token);
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
  listener: (event: { participantId: string }) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantJoined', listener);
}

export function addOnParticipantLeftListener(
  listener: (event: { participantId: string }) => void
): EventSubscription {
  return ExpoRealtimeIvsBroadcastModule.addListener('onParticipantLeft', listener);
}
