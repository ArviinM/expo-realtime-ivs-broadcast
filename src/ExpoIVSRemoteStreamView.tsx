import * as React from 'react';
import { ExpoIVSRemoteStreamViewProps } from './ExpoRealtimeIvsBroadcast.types';
import { requireNativeViewManager } from 'expo-modules-core';

// The name of this React component MUST EXACTLY MATCH the Swift class name.
const NativeView: React.ComponentType<ExpoIVSRemoteStreamViewProps> =
  requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSRemoteStreamView');

export function ExpoIVSRemoteStreamView(props: ExpoIVSRemoteStreamViewProps) {
  return <NativeView {...props} />;
}