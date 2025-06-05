import { NativeModule, requireNativeModule } from 'expo';

import { ExpoRealtimeIvsBroadcastModuleEvents } from './ExpoRealtimeIvsBroadcast.types';

declare class ExpoRealtimeIvsBroadcastModule extends NativeModule<ExpoRealtimeIvsBroadcastModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoRealtimeIvsBroadcastModule>('ExpoRealtimeIvsBroadcast');
