// In ExpoIVSStagePreviewView.tsx

import * as React from 'react';
import { ExpoIVSStagePreviewViewProps } from './ExpoRealtimeIvsBroadcast.types';
import { requireNativeViewManager } from 'expo-modules-core';

// The name of this React component MUST EXACTLY MATCH the Swift class name.
const NativeView: React.ComponentType<ExpoIVSStagePreviewViewProps> =
  requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSStagePreviewView');

export function ExpoIVSStagePreviewView(props: ExpoIVSStagePreviewViewProps) {
  return <NativeView {...props} />;
}