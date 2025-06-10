import { requireNativeViewManager } from 'expo-modules-core';
import * as React from 'react';

import { ExpoIVSRemoteStreamViewProps } from './ExpoRealtimeIvsBroadcast.types';

const NativeExpoIVSRemoteStreamView: React.ComponentType<ExpoIVSRemoteStreamViewProps> =
  requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSRemoteStreamView');

/**
 * A view that renders a remote participant's video stream from an IVS stage.
 */
export function IVSRemoteStreamView(props: ExpoIVSRemoteStreamViewProps) {
  return <NativeExpoIVSRemoteStreamView {...props} />;
} 

