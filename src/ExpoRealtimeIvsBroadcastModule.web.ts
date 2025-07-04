import { registerWebModule, NativeModule } from 'expo';

import { ExpoRealtimeIvsBroadcastModuleEvents } from './ExpoRealtimeIvsBroadcast.types';

class ExpoRealtimeIvsBroadcastModule extends NativeModule<ExpoRealtimeIvsBroadcastModuleEvents> {
  // PI = Math.PI;
  // async setValueAsync(value: string): Promise<void> {
  //   this.emit('onChange', { value });
  // }
  // hello() {
  //   return 'Hello world! 👋';
  // }
}

export default registerWebModule(ExpoRealtimeIvsBroadcastModule, 'ExpoRealtimeIvsBroadcastModule');
