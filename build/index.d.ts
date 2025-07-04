import { EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, StageConnectionStatePayload, PublishStatePayload, StageErrorPayload, CameraSwappedPayload, CameraSwapErrorPayload, ParticipantPayload, ParticipantStreamsPayload, ParticipantStreamsRemovedPayload } from './ExpoRealtimeIvsBroadcast.types';
export * from './ExpoRealtimeIvsBroadcast.types';
export { ExpoIVSStagePreviewView } from './ExpoIVSStagePreviewView';
export { ExpoIVSRemoteStreamView } from './ExpoIVSRemoteStreamView';
export { useStageParticipants } from './useStageParticipants';
export declare function initializeStage(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
export declare function initializeLocalStreams(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
export declare function joinStage(token: string, options?: {
    targetParticipantId?: string;
}): Promise<void>;
export declare function leaveStage(): Promise<void>;
export declare function setStreamsPublished(published: boolean): Promise<void>;
export declare function swapCamera(): Promise<void>;
export declare function setMicrophoneMuted(muted: boolean): Promise<void>;
export declare function requestPermissions(): Promise<PermissionStatusMap>;
export declare function addOnStageConnectionStateChangedListener(listener: (event: StageConnectionStatePayload) => void): EventSubscription;
export declare function addOnPublishStateChangedListener(listener: (event: PublishStatePayload) => void): EventSubscription;
export declare function addOnStageErrorListener(listener: (event: StageErrorPayload) => void): EventSubscription;
export declare function addOnCameraSwappedListener(listener: (event: CameraSwappedPayload) => void): EventSubscription;
export declare function addOnCameraSwapErrorListener(listener: (event: CameraSwapErrorPayload) => void): EventSubscription;
export declare function addOnParticipantJoinedListener(listener: (event: ParticipantPayload) => void): EventSubscription;
export declare function addOnParticipantLeftListener(listener: (event: ParticipantPayload) => void): EventSubscription;
export declare function addOnParticipantStreamsAddedListener(listener: (event: ParticipantStreamsPayload) => void): EventSubscription;
export declare function addOnParticipantStreamsRemovedListener(listener: (event: ParticipantStreamsRemovedPayload) => void): EventSubscription;
//# sourceMappingURL=index.d.ts.map