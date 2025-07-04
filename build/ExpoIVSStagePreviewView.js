// In ExpoIVSStagePreviewView.tsx
import * as React from 'react';
import { requireNativeViewManager } from 'expo-modules-core';
// The name of this React component MUST EXACTLY MATCH the Swift class name.
const NativeView = requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSStagePreviewView');
export function ExpoIVSStagePreviewView(props) {
    return <NativeView {...props}/>;
}
//# sourceMappingURL=ExpoIVSStagePreviewView.js.map