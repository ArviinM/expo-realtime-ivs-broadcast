import { requireNativeModule, EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, ExpoRealtimeIvsBroadcastModuleEvents } from './ExpoRealtimeIvsBroadcast.types';

// This combines the module's method signatures with the event emitter's signatures.
// By defining `addListener` and `removeListeners` explicitly, we get strong type-checking
// for our event names and payloads, resolving the 'never' type error.
export type ExpoRealtimeIvsBroadcastModuleType = {
  initialize(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
  joinStage(token: string): Promise<void>;
  leaveStage(): Promise<void>;
  setStreamsPublished(published: boolean): Promise<void>;
  swapCamera(): Promise<void>;
  setMicrophoneMuted(muted: boolean): Promise<void>;
  requestPermissions(): Promise<PermissionStatusMap>;

  addListener<EventName extends keyof ExpoRealtimeIvsBroadcastModuleEvents>(
    eventName: EventName,
    listener: (event: Parameters<ExpoRealtimeIvsBroadcastModuleEvents[EventName]>[0]) => void
  ): EventSubscription;
  removeListeners(count: number): void;
};

const ExpoModule: ExpoRealtimeIvsBroadcastModuleType = requireNativeModule('ExpoRealtimeIvsBroadcast');

export default ExpoModule;
