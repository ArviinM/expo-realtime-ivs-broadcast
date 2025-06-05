import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoRealtimeIvsBroadcastViewProps } from './ExpoRealtimeIvsBroadcast.types';

const NativeView: React.ComponentType<ExpoRealtimeIvsBroadcastViewProps> =
  requireNativeView('ExpoRealtimeIvsBroadcast');

export default function ExpoRealtimeIvsBroadcastView(props: ExpoRealtimeIvsBroadcastViewProps) {
  return <NativeView {...props} />;
}
