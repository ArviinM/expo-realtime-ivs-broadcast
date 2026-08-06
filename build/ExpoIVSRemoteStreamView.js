import * as React from 'react';
import { requireNativeViewManager } from 'expo-modules-core';
// The name of this React component MUST EXACTLY MATCH the Swift class name.
const NativeView = requireNativeViewManager('ExpoRealtimeIvsBroadcast_ExpoIVSRemoteStreamView');
function ExpoIVSRemoteStreamViewImpl(props) {
    return <NativeView {...props}/>;
}
// React.memo prevents JS-bridge churn from parent re-renders. The native
// view's setProps path already guards against duplicate participantId /
// deviceUrn assignments, but every parent re-render still serializes a fresh
// props bundle across the bridge. With memo, identical props short-circuit
// at the JS layer.
export const ExpoIVSRemoteStreamView = React.memo(ExpoIVSRemoteStreamViewImpl);
//# sourceMappingURL=ExpoIVSRemoteStreamView.js.map