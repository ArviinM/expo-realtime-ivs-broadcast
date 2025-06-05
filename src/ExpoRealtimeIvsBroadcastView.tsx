import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoRealtimeIvsBroadcastViewProps } from './ExpoRealtimeIvsBroadcast.types';

// This name should match the name used in the native module's view manager registration.
// By default, create-expo-module might register the view under the module name.
// The Swift class is ExpoIVSStagePreviewView.
const NativeExpoIVSStagePreviewView: React.ComponentType<ExpoRealtimeIvsBroadcastViewProps> =
  requireNativeView('ExpoRealtimeIvsBroadcast');

/**
 * React component for rendering the camera preview from the IVS Stage.
 */
export function IVSStagePreviewView(props: ExpoRealtimeIvsBroadcastViewProps) {
  return <NativeExpoIVSStagePreviewView {...props} />;
}
