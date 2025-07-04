import { EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, ExpoRealtimeIvsBroadcastModuleEvents } from './ExpoRealtimeIvsBroadcast.types';
export type ExpoRealtimeIvsBroadcastModuleType = {
    initializeStage(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
    initializeLocalStreams(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
    joinStage(token: string, options?: {
        targetParticipantId?: string;
    }): Promise<void>;
    leaveStage(): Promise<void>;
    setStreamsPublished(published: boolean): Promise<void>;
    swapCamera(): Promise<void>;
    setMicrophoneMuted(muted: boolean): Promise<void>;
    requestPermissions(): Promise<PermissionStatusMap>;
    addListener<EventName extends keyof ExpoRealtimeIvsBroadcastModuleEvents>(eventName: EventName, listener: (event: Parameters<ExpoRealtimeIvsBroadcastModuleEvents[EventName]>[0]) => void): EventSubscription;
    removeListeners(count: number): void;
};
declare const ExpoModule: ExpoRealtimeIvsBroadcastModuleType;
export default ExpoModule;
//# sourceMappingURL=ExpoRealtimeIvsBroadcastModule.d.ts.map