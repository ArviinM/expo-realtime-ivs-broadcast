import { registerWebModule, NativeModule } from 'expo';

import { ExpoRealtimeIvsBroadcastModuleEvents, PiPOptions } from './ExpoRealtimeIvsBroadcast.types';

class ExpoRealtimeIvsBroadcastModule extends NativeModule<ExpoRealtimeIvsBroadcastModuleEvents> {
  // Stub implementations for web (PiP not supported on web)
  async enablePictureInPicture(_options?: PiPOptions): Promise<boolean> {
    console.warn('Picture-in-Picture is not supported on web');
    return false;
  }

  async disablePictureInPicture(): Promise<void> {
    // No-op on web
  }

  async startPictureInPicture(): Promise<void> {
    console.warn('Picture-in-Picture is not supported on web');
  }

  async stopPictureInPicture(): Promise<void> {
    // No-op on web
  }

  async isPictureInPictureActive(): Promise<boolean> {
    return false;
  }

  async isPictureInPictureSupported(): Promise<boolean> {
    return false;
  }
}

export default registerWebModule(ExpoRealtimeIvsBroadcastModule, 'ExpoRealtimeIvsBroadcastModule');
