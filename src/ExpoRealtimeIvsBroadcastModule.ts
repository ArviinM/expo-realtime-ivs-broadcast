import { requireNativeModule, EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, ExpoRealtimeIvsBroadcastModuleEvents, PiPOptions } from './ExpoRealtimeIvsBroadcast.types';

// This combines the module's method signatures with the event emitter's signatures.
// By defining `addListener` and `removeListeners` explicitly, we get strong type-checking
// for our event names and payloads, resolving the 'never' type error.
export type ExpoRealtimeIvsBroadcastModuleType = {
  initializeStage(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
  initializeLocalStreams(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
  joinStage(token: string, options?: { targetParticipantId?: string }): Promise<void>;
  leaveStage(): Promise<void>;
  setStreamsPublished(published: boolean): Promise<void>;
  swapCamera(): Promise<void>;
  setMicrophoneMuted(muted: boolean): Promise<void>;
  setCameraMuted(muted: boolean, placeholderText?: string | null): Promise<void>;
  isCameraMuted(): Promise<boolean>;
  requestPermissions(): Promise<PermissionStatusMap>;
  
  // Picture-in-Picture methods
  enablePictureInPicture(options?: PiPOptions): Promise<boolean>;
  disablePictureInPicture(): Promise<void>;
  startPictureInPicture(): Promise<void>;
  stopPictureInPicture(): Promise<void>;
  isPictureInPictureActive(): Promise<boolean>;
  isPictureInPictureSupported(): Promise<boolean>;

  addListener<EventName extends keyof ExpoRealtimeIvsBroadcastModuleEvents>(
    eventName: EventName,
    listener: (event: Parameters<ExpoRealtimeIvsBroadcastModuleEvents[EventName]>[0]) => void
  ): EventSubscription;
  removeListeners(count: number): void;
};

const ExpoModule: ExpoRealtimeIvsBroadcastModuleType = requireNativeModule('ExpoRealtimeIvsBroadcast');

export default ExpoModule;
