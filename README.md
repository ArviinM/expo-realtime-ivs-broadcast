# Expo Real-time IVS Broadcast

This module provides React Native components and a comprehensive API to integrate [Amazon IVS Real-Time Streaming](https://docs.aws.amazon.com/ivs/latest/RealTimeUserGuide/what-is.html) into your Expo application. It acts as a wrapper around the native Amazon IVS Broadcast SDK, allowing you to both publish your own camera/microphone and subscribe to remote participants' streams.

> [!IMPORTANT]  
> This module currently supports **iOS only**. Android support is not yet implemented.

## Installation

Install the package in your Expo project:

```bash
npx expo install github:ArviinM/expo-realtime-ivs-broadcast
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

After adding the permissions, you may need to prebuild your project: `npx expo prebuild --platform ios`.

## Core Concepts

This library supports two primary roles within an IVS Stage: the **Publisher** and the **Viewer**.

### Publisher (Broadcasting)

A publisher is a user who is actively sending their camera and microphone feed to the stage.
-   **Key Component:** `ExpoIVSStagePreviewView` is used to render the publisher's own local camera feed so they can see themselves.

### Viewer (Subscribing)

A viewer is a user who is watching and listening to other participants on the stage.
-   **Key Hook:** `useStageParticipants` is the primary hook to get a live-updated list of all remote participants and their active streams.
-   **Key Component:** `ExpoIVSRemoteStreamView` is used to render the video stream of a single remote participant.

## API Reference

### Components

#### `ExpoIVSStagePreviewView`

A React Native component that renders the **local** camera preview for the publisher.

**Props**

-   `style` (`StyleProp<ViewStyle>`): Standard view styling.
-   `mirror` (`boolean`): Toggles if the camera preview should be mirrored. Default is `false`.
-   `scaleMode` (`'fit' | 'fill'`): Determines how the video should be scaled within the view bounds. Default is `'fill'`.

#### `ExpoIVSRemoteStreamView`

A React Native component that renders the video stream of a single **remote** participant.

**Props**

-   `style` (`StyleProp<ViewStyle>`): Standard view styling.
-   `participantId` (`string`): The unique ID of the remote participant you want to render.
-   `deviceUrn` (`string`): The unique URN of the participant's video stream you want to render.
-   `scaleMode` (`'fit' | 'fill'`): Determines how the video should be scaled within the view bounds. Default is `'fill'`.

### Hooks

#### `useStageParticipants()`

The primary hook for building a viewer experience. It listens to all stage events and provides a real-time list of remote participants.

**Returns**

An object containing:
-   `participants` (`Participant[]`): An array of participant objects. Each object has the shape:
    ```typescript
    {
      id: string;
      streams: {
        deviceUrn: string;
        mediaType: 'video' | 'audio' | 'unknown';
      }[];
    }
    ```

### Methods

All methods are asynchronous and return a `Promise`.

-   `initialize(audioConfig?, videoConfig?)`: Initializes the broadcast SDK. Must be called before any other stage operations.
-   `joinStage(token, options?)`: Joins a stage using a participant token.
    -   `token` (`string`): The participant token from your backend.
    -   `options` (`object`, optional): An object for extra options.
        -   `targetParticipantId` (`string`, optional): If using the automatic rendering mode, this pins a specific participant's stream to the first available view.
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
-   `addOnParticipantStreamsAddedListener(listener)`: Fired when a remote participant adds streams.
    -   Payload: `{ participantId: string, streams: StageStream[] }`
-   `addOnParticipantStreamsRemovedListener(listener)`: Fired when a remote participant removes streams.
    -   Payload: `{ participantId: string, streams: { deviceUrn: string }[] }`
-   `addOnCameraSwappedListener(listener)`: Fired on a successful camera swap.
    -   Payload: `{ newCameraURN: string, newCameraName: string }`
-   `addOnCameraSwapErrorListener(listener)`: Fired if a camera swap fails.
    -   Payload: `{ reason: string }`

## Usage Example

Here is a comprehensive example showing both publisher and viewer functionality.

```tsx
import React, { useState, useEffect } from 'react';
import { View, Button, StyleSheet, Text, ScrollView, SafeAreaView } from 'react-native';
import {
  ExpoIVSStagePreviewView,
  ExpoIVSRemoteStreamView,
  useStageParticipants,
  initialize,
  joinStage,
  leaveStage,
  setStreamsPublished,
  swapCamera,
  addOnStageConnectionStateChangedListener,
} from 'expo-realtime-ivs-broadcast';

export default function BroadcastScreen() {
  const [isConnected, setIsConnected] = useState(false);
  const [isPublished, setIsPublished] = useState(false);
  const { participants } = useStageParticipants();

  useEffect(() => {
    initialize();

    const connectionSub = addOnStageConnectionStateChangedListener((data) => {
      console.log('Connection state:', data.state);
      setIsConnected(data.state === 'connected');
      if (data.state !== 'connected') {
        setIsPublished(false);
      }
    });

    return () => {
      connectionSub.remove();
      leaveStage(); // Ensure we leave the stage on component unmount
    };
  }, []);

  const handleJoin = () => {
    // In a real app, fetch this from a secure backend server!
    const token = 'YOUR_PARTICIPANT_TOKEN';
    joinStage(token);
  };

  const handleTogglePublish = () => {
    const newPublishState = !isPublished;
    setStreamsPublished(newPublishState);
    setIsPublished(newPublishState); // Optimistic update
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.topContainer}>
        <Text style={styles.header}>My Preview</Text>
        <ExpoIVSStagePreviewView style={styles.localPreview} />
      </View>

      <View style={styles.bottomContainer}>
        <Text style={styles.header}>Remote Participants ({participants.length})</Text>
        {participants.length === 0 ? (
          <View style={styles.centered}>
            <Text style={styles.emptyText}>No one else is here.</Text>
          </View>
        ) : (
          <ScrollView horizontal style={styles.remoteScrollView}>
            {participants.map(p => {
              const videoStream = p.streams.find(s => s.mediaType === 'video');
              // We use a key that changes when the video stream appears to ensure React creates a new component
              return (
                <View key={p.id + (videoStream?.deviceUrn ?? '')} style={styles.remoteViewWrapper}>
                  {videoStream ? (
                    <ExpoIVSRemoteStreamView
                      style={styles.remoteView}
                      participantId={p.id}
                      deviceUrn={videoStream.deviceUrn}
                    />
                  ) : (
                    <View style={styles.noVideoPlaceholder}>
                      <Text style={styles.emptyText}>No Video</Text>
                    </View>
                  )}
                  <Text style={styles.participantLabel}>{p.id.substring(0, 6)}</Text>
                </View>
              );
            })}
          </ScrollView>
        )}
      </View>

      <View style={styles.controls}>
        {!isConnected ? (
          <Button title="Join Stage" onPress={handleJoin} />
        ) : (
          <>
            <Button title={isPublished ? 'Unpublish' : 'Publish'} onPress={handleTogglePublish} />
            <Button title="Swap Cam" onPress={swapCamera} />
            <Button title="Leave" onPress={leaveStage} color="red" />
          </>
        )}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#111' },
  topContainer: { flex: 1, margin: 10 },
  bottomContainer: { flex: 1, borderTopWidth: 2, borderTopColor: '#333' },
  header: { fontSize: 20, fontWeight: 'bold', color: 'white', padding: 10, textAlign: 'center' },
  localPreview: { flex: 1, backgroundColor: 'black', borderRadius: 8 },
  remoteScrollView: { flex: 1, paddingLeft: 10, paddingTop: 10 },
  remoteViewWrapper: { width: 150, height: '90%', backgroundColor: 'black', marginRight: 10, borderRadius: 8, overflow: 'hidden' },
  remoteView: { width: '100%', height: '100%' },
  participantLabel: { position: 'absolute', bottom: 5, left: 5, color: 'white', backgroundColor: 'rgba(0,0,0,0.5)', padding: 3, borderRadius: 3, fontSize: 10 },
  controls: { paddingBottom: 40, paddingTop: 10, flexDirection: 'row', justifyContent: 'space-evenly', borderTopWidth: 1, borderTopColor: '#333' },
  centered: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  emptyText: { color: '#888', fontSize: 16 },
  noVideoPlaceholder: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#222' },
});
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the MIT License.