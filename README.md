# Expo Real-time IVS Broadcast

This module provides a React Native component and API to integrate [Amazon IVS Real-Time Streaming](https://docs.aws.amazon.com/ivs/latest/RealTimeUserGuide/what-is.html) into your Expo application. It acts as a wrapper around the native Amazon IVS Broadcast SDK.

> [!IMPORTANT]  
> This module currently supports **iOS only**. Android support is not yet implemented.

## Installation

Install the package in your Expo project:

```bash
npx expo install expo-realtime-ivs-broadcast
```

## Configuration

You must add the required camera and microphone usage descriptions to your `Info.plist` file. If you don't, your app will crash when requesting permissions.

Open your `ios/<Your-Project-Name>/Info.plist` and add the following keys:

```xml
<key>NSCameraUsageDescription</key>
<string>Allow $(PRODUCT_NAME) to use your camera to broadcast video.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Allow $(PRODUCT_NAME) to use your microphone to broadcast audio.</string>
```

After adding the permissions, run `npx expo prebuild --platform ios` to apply the changes.

## API Reference

### `IVSStagePreviewView`

A React Native component that renders the local camera preview.

**Props**

-   `style` (`StyleProp<ViewStyle>`): Standard view styling.
-   `mirror` (`boolean`): Toggles if the camera preview should be mirrored. Default is `false`.
-   `scaleMode` (`'fit' | 'fill'`): Determines how the video should be scaled within the view bounds. Default is `'fill'`.

### Methods

All methods are asynchronous and return a `Promise`.

-   `initialize(audioConfig?, videoConfig?)`: Initializes the broadcast SDK. Must be called before any other stage operations.
-   `joinStage(token)`: Joins a stage using a participant token.
-   `leaveStage()`: Leaves the current stage.
-   `setStreamsPublished(published)`: Toggles the publishing of local video and audio streams.
-   `swapCamera()`: Switches between the front and back cameras.
-   `setMicrophoneMuted(muted)`: Mutes or unmutes the local microphone.
-   `requestPermissions()`: Requests camera and microphone permissions from the user. Returns a `PermissionStatusMap`.

### Event Listeners

You can subscribe to events from the native module. Each listener function returns an `EventSubscription` object with a `remove()` method to unsubscribe.

-   `addOnStageConnectionStateChangedListener(listener)`: Listens for changes in the stage connection state.
    -   Payload: `{ state: 'connecting' | 'connected' | 'disconnected', error?: string }`
-   `addOnPublishStateChangedListener(listener)`: Listens for changes in the local participant's publish state.
    -   Payload: `{ state: 'not_published' | 'attempting' | 'published' | 'failed', error?: string }`
-   `addOnStageErrorListener(listener)`: Listens for fatal SDK errors.
    -   Payload: `{ code: number, description: string, source: string, isFatal: boolean }`
-   `addOnParticipantJoinedListener(listener)`: Fired when a remote participant joins the stage.
    -   Payload: `{ participantId: string }`
-   `addOnParticipantLeftListener(listener)`: Fired when a remote participant leaves the stage.
    -   Payload: `{ participantId: string }`
-   `addOnCameraSwappedListener(listener)`: Fired on a successful camera swap.
    -   Payload: `{ newCameraURN: string, newCameraName: string }`
-   `addOnCameraSwapErrorListener(listener)`: Fired if a camera swap fails.
    -   Payload: `{ reason: string }`

## Usage Example

Here is a basic example of how to use the module in a component.

```tsx
import React, { useState, useEffect } from 'react';
import { View, Button, StyleSheet } from 'react-native';
import {
  IVSStagePreviewView,
  initialize,
  joinStage,
  leaveStage,
  setStreamsPublished,
  addOnStageConnectionStateChangedListener,
  addOnPublishStateChangedListener,
} from 'expo-realtime-ivs-broadcast';

export default function BroadcastScreen() {
  const [isConnected, setIsConnected] = useState(false);
  const [isPublished, setIsPublished] = useState(false);

  useEffect(() => {
    initialize();

    const connectionSub = addOnStageConnectionStateChangedListener((data) => {
      console.log('Connection state:', data.state);
      setIsConnected(data.state === 'connected');
    });

    const publishSub = addOnPublishStateChangedListener((data) => {
      console.log('Publish state:', data.state);
      setIsPublished(data.state === 'published');
    });

    return () => {
      connectionSub.remove();
      publishSub.remove();
      leaveStage();
    };
  }, []);

  const handleJoin = () => {
    // Fetch your token from a secure backend server
    const token = 'YOUR_PARTICIPANT_TOKEN';
    joinStage(token);
  };

  const handleTogglePublish = () => {
    setStreamsPublished(!isPublished);
  };

  return (
    <View style={styles.container}>
      <IVSStagePreviewView style={styles.preview} />
      <View style={styles.controls}>
        {!isConnected ? (
          <Button title="Join Stage" onPress={handleJoin} />
        ) : (
          <>
            <Button title={isPublished ? 'Unpublish' : 'Publish'} onPress={handleTogglePublish} />
            <Button title="Leave Stage" onPress={() => leaveStage()} />
          </>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  preview: {
    flex: 1,
  },
  controls: {
    position: 'absolute',
    bottom: 40,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-evenly',
  },
});
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the MIT License. 