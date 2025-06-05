import type { StyleProp, ViewStyle } from 'react-native';

// Configuration types for the initialize method
export interface LocalAudioConfig {
  // Future properties: e.g., bitrate?: number;
}

export interface LocalVideoConfig {
  // Future properties: e.g., width?: number; height?: number; targetFramerate?: number; maxBitrate?: number;
}

// Permission status types for requestPermissions method
export type PermissionStatus = 'granted' | 'denied' | 'not-determined' | 'unavailable';
export interface PermissionStatusMap {
  camera: PermissionStatus;
  microphone: PermissionStatus;
}

// --- Event Payloads for Native Module Emitter ---
export interface StageConnectionStatePayload {
  state: 'connecting' | 'connected' | 'disconnected';
  error?: string;
}

export interface PublishStatePayload {
  state: 'not_published' | 'attempting' | 'published' | 'failed'; // Added 'failed' as a common case
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

// Defines the events that the native module can emit
export type ExpoRealtimeIvsBroadcastModuleEvents = {
  onStageConnectionStateChanged: (payload: StageConnectionStatePayload) => void;
  onPublishStateChanged: (payload: PublishStatePayload) => void;
  onStageError: (payload: StageErrorPayload) => void;
  onParticipantJoined: (payload: { participantId: string }) => void;
  onParticipantLeft: (payload: { participantId: string }) => void;
  onCameraSwapped: (payload: CameraSwappedPayload) => void;
  onCameraSwapError: (payload: CameraSwapErrorPayload) => void;
};

// Props for the ExpoIVSStagePreviewView component
export type ExpoRealtimeIvsBroadcastViewProps = {
  style?: StyleProp<ViewStyle>;
  mirror?: boolean;
  scaleMode?: 'fit' | 'fill'; // As per plan
  // Remove old: url: string;
  // Remove old: onLoad: (event: { nativeEvent: OnLoadEventPayload }) => void;
};

// Remove unused old types if any (OnLoadEventPayload, ChangeEventPayload)
// It's cleaner to just define what we need.
