import type { StyleProp, ViewStyle } from 'react-native';
export interface LocalAudioConfig {
}
export interface LocalVideoConfig {
}
export type PermissionStatus = 'granted' | 'denied' | 'not-determined' | 'unavailable';
export interface PermissionStatusMap {
    camera: PermissionStatus;
    microphone: PermissionStatus;
}
export interface StageConnectionStatePayload {
    state: 'connecting' | 'connected' | 'disconnected';
    error?: string;
}
export interface PublishStatePayload {
    state: 'not_published' | 'attempting' | 'published' | 'failed';
    error?: string;
}
export interface StageErrorPayload {
    code: number;
    description: string;
    source: string;
    isFatal: boolean;
}
export interface CameraSwappedPayload {
    newCameraURN: string;
    newCameraName: string;
}
export interface CameraSwapErrorPayload {
    reason: string;
}
export interface StageStream {
    deviceUrn: string;
    mediaType: 'video' | 'audio' | 'unknown';
}
export interface Participant {
    id: string;
    streams: StageStream[];
}
export interface ParticipantPayload {
    participantId: string;
}
export interface ParticipantStreamsPayload {
    participantId: string;
    streams: StageStream[];
}
export interface ParticipantStreamsRemovedPayload {
    participantId: string;
    streams: {
        deviceUrn: string;
    }[];
}
export type ExpoRealtimeIvsBroadcastModuleEvents = {
    onStageConnectionStateChanged: (payload: StageConnectionStatePayload) => void;
    onPublishStateChanged: (payload: PublishStatePayload) => void;
    onStageError: (payload: StageErrorPayload) => void;
    onParticipantJoined: (payload: ParticipantPayload) => void;
    onParticipantLeft: (payload: ParticipantPayload) => void;
    onParticipantStreamsAdded: (payload: ParticipantStreamsPayload) => void;
    onParticipantStreamsRemoved: (payload: ParticipantStreamsRemovedPayload) => void;
    onCameraSwapped: (payload: CameraSwappedPayload) => void;
    onCameraSwapError: (payload: CameraSwapErrorPayload) => void;
};
export type ExpoIVSStagePreviewViewProps = {
    style?: StyleProp<ViewStyle>;
    mirror?: boolean;
    scaleMode?: 'fit' | 'fill';
};
export type ExpoIVSRemoteStreamViewProps = {
    style?: StyleProp<ViewStyle>;
    participantId?: string;
    deviceUrn?: string;
    scaleMode?: 'fit' | 'fill';
};
//# sourceMappingURL=ExpoRealtimeIvsBroadcast.types.d.ts.map