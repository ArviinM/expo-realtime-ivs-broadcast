import * as React from 'react';
import { requireNativeViewManager } from 'expo-modules-core';
// The name of this React component MUST EXACTLY MATCH the Swift class name.
const NativeView = requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSRemoteStreamView');
export function ExpoIVSRemoteStreamView(props) {
    return <NativeView {...props}/>;
}
//# sourceMappingURL=ExpoIVSRemoteStreamView.js.map