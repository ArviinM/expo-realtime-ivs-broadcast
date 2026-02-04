import { NativeModule } from 'expo';
import { ExpoRealtimeIvsBroadcastModuleEvents, PiPOptions } from './ExpoRealtimeIvsBroadcast.types';
declare class ExpoRealtimeIvsBroadcastModule extends NativeModule<ExpoRealtimeIvsBroadcastModuleEvents> {
    enablePictureInPicture(_options?: PiPOptions): Promise<boolean>;
    disablePictureInPicture(): Promise<void>;
    startPictureInPicture(): Promise<void>;
    stopPictureInPicture(): Promise<void>;
    isPictureInPictureActive(): Promise<boolean>;
    isPictureInPictureSupported(): Promise<boolean>;
}
declare const _default: typeof ExpoRealtimeIvsBroadcastModule;
export default _default;
//# sourceMappingURL=ExpoRealtimeIvsBroadcastModule.web.d.ts.map