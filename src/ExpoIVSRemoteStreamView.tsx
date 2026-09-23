import * as React from 'react';
import type { ExpoIVSRemoteStreamViewProps } from './ExpoRealtimeIvsBroadcast.types';
import { requireNativeViewManager } from 'expo-modules-core';

// The name of this React component MUST EXACTLY MATCH the Swift class name.
const NativeView: React.ComponentType<ExpoIVSRemoteStreamViewProps> =
  requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSRemoteStreamView');

function ExpoIVSRemoteStreamViewImpl(props: ExpoIVSRemoteStreamViewProps) {
  return <NativeView {...props} />;
}

// React.memo prevents JS-bridge churn from parent re-renders. The native
// view's setProps path already guards against duplicate participantId /
// deviceUrn assignments, but every parent re-render still serializes a fresh
// props bundle across the bridge. With memo, identical props short-circuit
// at the JS layer.
export const ExpoIVSRemoteStreamView = React.memo(ExpoIVSRemoteStreamViewImpl);
