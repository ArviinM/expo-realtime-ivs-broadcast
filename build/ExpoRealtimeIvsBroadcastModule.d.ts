import { EventSubscription } from 'expo-modules-core';
import { LocalAudioConfig, LocalVideoConfig, PermissionStatusMap, ExpoRealtimeIvsBroadcastModuleEvents, PiPOptions, AudioPreset, AudioInputDevice, BackgroundBehaviorOptions, RTCStatsPayload, ThermalMitigationOptions, ThermalState } from './ExpoRealtimeIvsBroadcast.types';
export type ExpoRealtimeIvsBroadcastModuleType = {
    initializeStage(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
    initializeLocalStreams(audioConfig?: LocalAudioConfig, videoConfig?: LocalVideoConfig): Promise<void>;
    destroyLocalStreams(): Promise<void>;
    joinStage(token: string, options?: {
        targetParticipantId?: string;
    }): Promise<void>;
    leaveStage(): Promise<void>;
    setStreamsPublished(published: boolean): Promise<void>;
    swapCamera(): Promise<void>;
    /** Rebuild the capture stream on the current camera (Android recovery). */
    refreshCameraStream(): Promise<void>;
    setMicrophoneMuted(muted: boolean): Promise<void>;
    setCameraMuted(muted: boolean, placeholderText?: string | null): Promise<void>;
    isCameraMuted(): Promise<boolean>;
    requestPermissions(): Promise<PermissionStatusMap>;
    setAudioPreset(preset: AudioPreset): Promise<void>;
    listAudioInputs(): Promise<AudioInputDevice[]>;
    setPreferredAudioInput(urn: string | null): Promise<void>;
    setInputGain(gain: number): Promise<boolean>;
    setMockMode(enabled: boolean): Promise<void>;
    setBackgroundBehavior(options: BackgroundBehaviorOptions): Promise<void>;
    requestRTCStats(): Promise<RTCStatsPayload>;
    setThermalMitigation(options: ThermalMitigationOptions): Promise<void>;
    getThermalState(): Promise<ThermalState>;
    enablePictureInPicture(options?: PiPOptions): Promise<boolean>;
    disablePictureInPicture(): Promise<void>;
    startPictureInPicture(): Promise<void>;
    stopPictureInPicture(): Promise<void>;
    isPictureInPictureActive(): Promise<boolean>;
    isPictureInPictureSupported(): Promise<boolean>;
    isPiPRemoteSourceValid(): Promise<boolean>;
    addListener<EventName extends keyof ExpoRealtimeIvsBroadcastModuleEvents>(eventName: EventName, listener: (event: Parameters<ExpoRealtimeIvsBroadcastModuleEvents[EventName]>[0]) => void): EventSubscription;
    removeListeners(count: number): void;
};
declare const ExpoModule: ExpoRealtimeIvsBroadcastModuleType;
export default ExpoModule;
//# sourceMappingURL=ExpoRealtimeIvsBroadcastModule.d.ts.map