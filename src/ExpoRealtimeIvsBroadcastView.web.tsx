import * as React from 'react';

import { ExpoRealtimeIvsBroadcastViewProps } from './ExpoRealtimeIvsBroadcast.types';

export default function ExpoRealtimeIvsBroadcastView(props: ExpoRealtimeIvsBroadcastViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
