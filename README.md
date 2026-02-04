# Expo Real-time IVS Broadcast

**Note on Stability:** This library is currently in an early and unstable development phase. While the core functionalities—such as connecting to an Amazon IVS stage, publishing your local camera/microphone, and subscribing to remote participant streams—are operational, many other features have not been thoroughly tested. Please use with caution in production environments. We welcome contributions and bug reports to help stabilize the module.

This module provides React Native components and a comprehensive API to integrate [Amazon IVS Real-Time Streaming](https://docs.aws.amazon.com/ivs/latest/RealTimeUserGuide/what-is.html) into your Expo application. It acts as a wrapper around the native Amazon IVS Broadcast SDK for both iOS and Android, allowing you to both publish your own camera/microphone and subscribe to remote participants' streams.

## Compatibility

| Library Version | Expo SDK | React Native | React   | Notes |
|-----------------|----------|--------------|---------|-------|
| 0.2.0           | 54       | 0.81.x       | 19.1.x  | **Added Picture-in-Picture support** |
| 0.1.7           | 54       | 0.81.x       | 19.1.x  | |
| 0.1.4           | 53       | 0.79.x       | 19.0.x  | |

## Installation

Install the package in your Expo project:

```bash
npx expo install expo-realtime-ivs-broadcast
```

## Configuration

### iOS

You must add the required camera and microphone usage descriptions to your `Info.plist` file. If you don't, your app will crash when requesting permissions.

Open your `ios/<Your-Project-Name>/Info.plist` and add the following keys:

```xml
<key>NSCameraUsageDescription</key>
<string>Allow $(PRODUCT_NAME) to use your camera to broadcast video.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Allow $(PRODUCT_NAME) to use your microphone to broadcast audio.</string>
```

#### Picture-in-Picture (iOS)

To enable Picture-in-Picture support for background video playback, add the background modes:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

**Notes:**
- PiP requires iOS 15.0 or later.
- The `voip` mode is recommended for broadcaster PiP to maintain better background performance.
- When the app is backgrounded, the camera may be paused by iOS. In this case, a "LIVE - Broadcasting in progress" placeholder will be displayed in the PiP window to indicate that the broadcast is still active.

After adding the permissions, you may need to prebuild your project: `npx expo prebuild --platform ios`.

### Android

The necessary permissions (`CAMERA`, `RECORD_AUDIO`, `INTERNET`) are already included in the library's `AndroidManifest.xml` and will be merged into your app's manifest automatically during the build process.

However, you are still responsible for requesting these permissions from the user at runtime before attempting to initialize local devices. This is standard Android behavior.

#### Picture-in-Picture (Android)

To enable Picture-in-Picture support, you must configure your Activity. Add the following to your main Activity in `android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"
    ... >
</activity>
```

**Notes:**
- PiP requires Android 8.0 (API 26) or later.
- On Android 12+, `autoEnterOnBackground` enables automatic PiP entry via `setAutoEnterEnabled()`.
- Android PiP is Activity-level, meaning the entire app UI shrinks into the PiP window (unlike iOS which shows only the video).
- The video stream view is automatically set as the source rect hint for smooth PiP transitions.

## Core Concepts

This library is designed for two primary use cases: joining a stage as a **Viewer** or as a **Publisher**. The key difference is that viewers can join and watch streams without granting camera or microphone permissions, providing a less intrusive user experience.

### Viewer Workflow

A viewer is a user who is only watching and listening to other participants. They are not prompted for any device permissions.

1.  `initializeStage()`: Prepares the SDK with base configurations.
2.  `joinStage(token)`: Joins the stage to begin receiving remote participant data.
3.  `useStageParticipants()`: A hook that provides a list of remote participants.
4.  `ExpoIVSRemoteStreamView`: A component to render a remote participant's video stream.

### Publisher Workflow

A publisher is a user who is actively sending their camera and microphone feed to the stage.

1.  `initializeStage()`: Prepares the SDK with base configurations.
2.  `initializeLocalStreams()`: **This is the key step.** This method prepares the user's camera and microphone for publishing. This is the method that will trigger system permission prompts. It must be called before using `ExpoIVSStagePreviewView` or publishing streams.
3.  `ExpoIVSStagePreviewView`: A component to render the publisher's own camera feed (optional, but recommended).
4.  `joinStage(token)`: Joins the stage.
5.  `setStreamsPublished(true)`: Starts sending the local streams to the other participants.


## API Reference

### Components

#### `ExpoIVSStagePreviewView`

A React Native component that renders the **local** camera preview for the publisher. This will only render a feed after `initializeLocalStreams()` has been successfully called.

**Props**

-   `style` (`StyleProp<ViewStyle>`): Standard view styling.
-   `mirror` (`boolean`): Toggles if the camera preview should be mirrored. Default is `false`.
-   `scaleMode` (`'fit' | 'fill'`): Determines how the video should be scaled within the view bounds. Default is `'fill'`.

#### `ExpoIVSRemoteStreamView`

A React Native component that renders the video stream of a single **remote** participant.

**Props**

-   `style` (`StyleProp<ViewStyle>`): Standard view styling.
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

-   `initializeStage(audioConfig?, videoConfig?)`: Initializes the broadcast SDK with non-device-related configurations. It does **not** trigger permission prompts. This should be called once before any other stage operations.
-   `initializeLocalStreams(audioConfig?, videoConfig?)`: Prepares the user's local camera and microphone for publishing. This is the method that will trigger system permission prompts. It must be called before using `ExpoIVSStagePreviewView` or publishing streams.
-   `joinStage(token, options?)`: Joins a stage using a participant token. Can be called without `initializeLocalStreams` for a viewer-only role.
    -   `token` (`string`): The participant token from your backend.
-   `leaveStage()`: Leaves the current stage.
-   `setStreamsPublished(published)`: Toggles the publishing of local streams. Requires `initializeLocalStreams` to have been called.
-   `swapCamera()`: Switches between the front and back cameras. Requires `initializeLocalStreams` to have been called.
-   `setMicrophoneMuted(muted)`: Mutes or unmutes the local microphone. Requires `initializeLocalStreams` to have been called.
-   `requestPermissions()`: Checks and returns the current status of camera and microphone permissions without prompting the user.

#### Picture-in-Picture Methods

These methods allow you to implement Picture-in-Picture functionality for continuous video playback when the app is in the background. PiP works for both **viewers** (watching a remote stream) and **broadcasters** (showing their own camera preview).

-   `enablePictureInPicture(options?)`: Enables PiP mode with optional configuration.
    -   `options.autoEnterOnBackground` (`boolean`, default: `true`): Automatically enter PiP when app goes to background.
    -   `options.sourceView` (`'local' | 'remote'`, default: `'remote'`): Which video stream to show in PiP.
        - Use `'remote'` for viewers watching a livestream.
        - Use `'local'` for broadcasters to see their own camera in PiP.
    -   `options.preferredAspectRatio` (`{ width: number, height: number }`): Preferred aspect ratio for the PiP window.
    -   Returns: `Promise<boolean>` - `true` if PiP was enabled successfully.
-   `disablePictureInPicture()`: Disables PiP mode and cleans up resources.
-   `startPictureInPicture()`: Manually starts PiP mode (must be enabled first).
-   `stopPictureInPicture()`: Stops PiP mode and returns to full screen.
-   `isPictureInPictureActive()`: Returns `true` if PiP is currently active.
-   `isPictureInPictureSupported()`: Returns `true` if PiP is supported on the device.

**Broadcaster PiP Behavior (iOS):** When using `sourceView: 'local'` for broadcasters, iOS may pause the camera when the app enters the background. In this case, the PiP window will automatically display a "LIVE - Broadcasting in progress" placeholder to reassure the broadcaster that their stream is still active. The camera preview will resume when the app returns to the foreground.

### Event Listeners

You can subscribe to events from the native module. Each listener function returns an `EventSubscription` object with a `remove()` method to unsubscribe.

-   `addOnStageConnectionStateChangedListener(listener)`: Listens for changes in the stage connection state.
    -   Payload: `{ state: 'connecting' | 'connected' | 'disconnected', error?: string }`
-   `addOnPublishStateChangedListener(listener)`: Listens for changes in the local participant's publish state.
    -   Payload: `{ state: 'not_published' | 'attempting' | 'published' | 'failed', error?: string }`
-   `addOnStageErrorListener(listener)`: Listens for fatal SDK errors.
-   `addOnParticipantJoinedListener(listener)`: Fired when a remote participant joins the stage.
-   `addOnParticipantLeftListener(listener)`: Fired when a remote participant leaves the stage.
-   `addOnParticipantStreamsAddedListener(listener)`: Fired when a remote participant adds streams.
-   `addOnParticipantStreamsRemovedListener(listener)`: Fired when a remote participant removes streams.
-   `addOnPiPStateChangedListener(listener)`: Fired when PiP state changes.
    -   Payload: `{ state: 'started' | 'stopped' | 'restored' }`
-   `addOnPiPErrorListener(listener)`: Fired when a PiP error occurs.
    -   Payload: `{ error: string }`

## Picture-in-Picture Examples

### Viewer PiP Example

This example demonstrates how to use PiP for a live shopping viewer experience:

```tsx
import React, { useEffect, useState } from 'react';
import { View, Button, StyleSheet, Text } from 'react-native';
import {
  ExpoIVSRemoteStreamView,
  enablePictureInPicture,
  disablePictureInPicture,
  startPictureInPicture,
  isPictureInPictureSupported,
  addOnPiPStateChangedListener,
  addOnPiPErrorListener,
} from 'expo-realtime-ivs-broadcast';

export default function LiveShoppingViewer() {
  const [isPiPSupported, setIsPiPSupported] = useState(false);
  const [isPiPActive, setIsPiPActive] = useState(false);

  useEffect(() => {
    // Check if PiP is supported
    isPictureInPictureSupported().then(setIsPiPSupported);

    // Listen for PiP state changes
    const stateSub = addOnPiPStateChangedListener((event) => {
      console.log('PiP state:', event.state);
      setIsPiPActive(event.state === 'started');
      
      if (event.state === 'restored') {
        // User tapped to return from PiP
        console.log('User returned from PiP');
      }
    });

    const errorSub = addOnPiPErrorListener((event) => {
      console.error('PiP error:', event.error);
    });

    return () => {
      stateSub.remove();
      errorSub.remove();
      disablePictureInPicture();
    };
  }, []);

  const handleEnablePiP = async () => {
    const success = await enablePictureInPicture({
      autoEnterOnBackground: true,    // Auto-enter when user presses home
      sourceView: 'remote',           // Show the livestream in PiP
      preferredAspectRatio: { width: 9, height: 16 },  // Portrait
    });
    
    if (success) {
      console.log('PiP enabled! Stream will continue in background.');
    }
  };

  const handleManualPiP = () => {
    // Manually trigger PiP (useful for a "minimize" button)
    startPictureInPicture();
  };

  return (
    <View style={styles.container}>
      <ExpoIVSRemoteStreamView style={styles.video} scaleMode="fill" />
      
      <View style={styles.controls}>
        {isPiPSupported && (
          <>
            <Button title="Enable PiP" onPress={handleEnablePiP} />
            <Button title="Minimize to PiP" onPress={handleManualPiP} />
          </>
        )}
        {!isPiPSupported && (
          <Text style={styles.text}>PiP not supported on this device</Text>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  video: { flex: 1 },
  controls: { padding: 20, flexDirection: 'row', justifyContent: 'space-evenly' },
  text: { color: '#888' },
});
```

### Broadcaster PiP Example

This example demonstrates how to use PiP for a broadcaster/seller experience, allowing them to see themselves while the app is in the background:

```tsx
import React, { useEffect, useState } from 'react';
import { View, Button, StyleSheet, Text } from 'react-native';
import {
  ExpoIVSStagePreviewView,
  enablePictureInPicture,
  disablePictureInPicture,
  startPictureInPicture,
  isPictureInPictureSupported,
  addOnPiPStateChangedListener,
  initializeLocalStreams,
  joinStage,
  setStreamsPublished,
} from 'expo-realtime-ivs-broadcast';

export default function BroadcasterScreen() {
  const [isPiPSupported, setIsPiPSupported] = useState(false);
  const [isLive, setIsLive] = useState(false);

  useEffect(() => {
    isPictureInPictureSupported().then(setIsPiPSupported);

    const stateSub = addOnPiPStateChangedListener((event) => {
      console.log('PiP state:', event.state);
      
      if (event.state === 'restored') {
        // Broadcaster returned from PiP to full screen
        console.log('Returned to app from PiP');
      }
    });

    return () => {
      stateSub.remove();
      disablePictureInPicture();
    };
  }, []);

  const handleGoLive = async () => {
    await initializeLocalStreams();
    await joinStage('YOUR_BROADCASTER_TOKEN');
    await setStreamsPublished(true);
    setIsLive(true);

    // Enable PiP with local camera view for broadcaster
    if (isPiPSupported) {
      await enablePictureInPicture({
        autoEnterOnBackground: true,
        sourceView: 'local',  // Show broadcaster's own camera in PiP
        preferredAspectRatio: { width: 9, height: 16 },
      });
    }
  };

  const handleMinimize = () => {
    // Manually enter PiP (e.g., when switching to another app feature)
    startPictureInPicture();
  };

  return (
    <View style={styles.container}>
      <ExpoIVSStagePreviewView style={styles.preview} mirror={true} />
      
      <View style={styles.controls}>
        {!isLive ? (
          <Button title="Go Live" onPress={handleGoLive} />
        ) : (
          <>
            <Text style={styles.liveIndicator}>● LIVE</Text>
            {isPiPSupported && (
              <Button title="Minimize" onPress={handleMinimize} />
            )}
          </>
        )}
      </View>
      
      {isPiPSupported && isLive && (
        <Text style={styles.hint}>
          Swipe up to go home - you'll see yourself in PiP while broadcasting
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  preview: { flex: 1 },
  controls: { 
    padding: 20, 
    flexDirection: 'row', 
    justifyContent: 'space-evenly',
    alignItems: 'center',
  },
  liveIndicator: { color: 'red', fontSize: 18, fontWeight: 'bold' },
  hint: { color: '#666', textAlign: 'center', padding: 10, fontSize: 12 },
});
```

**Note:** When the broadcaster backgrounds the app, iOS may pause camera access. The PiP window will automatically show a "LIVE - Broadcasting in progress" placeholder. The actual broadcast continues uninterrupted - only the local preview is paused.

## Usage Example

This example demonstrates how to build a UI that lets a user choose between being a "Viewer" or a "Publisher".

```tsx
import React, { useState, useEffect } from 'react';
import { View, Button, StyleSheet, Text, ScrollView, SafeAreaView } from 'react-native';
import {
  ExpoIVSStagePreviewView,
  ExpoIVSRemoteStreamView,
  useStageParticipants,
  initializeStage,
  initializeLocalStreams,
  joinStage,
  leaveStage,
  setStreamsPublished,
  swapCamera,
  addOnStageConnectionStateChangedListener,
} from 'expo-realtime-ivs-broadcast';

// In a real app, you would fetch this from a secure backend server!
const TOKEN = 'YOUR_PARTICIPANT_TOKEN';

type Role = 'viewer' | 'publisher';

export default function App() {
  const [role, setRole] = useState<Role | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [isPublished, setIsPublished] = useState(false);
  const [areLocalStreamsInitialized, setAreLocalStreamsInitialized] = useState(false);
  
  const { participants } = useStageParticipants();

  useEffect(() => {
    // Initialize non-device-related SDK parts on mount.
    initializeStage();

    const connectionSub = addOnStageConnectionStateChangedListener((data) => {
      const connected = data.state === 'connected';
      setIsConnected(connected);
      if (!connected) {
        setIsPublished(false);
        setAreLocalStreamsInitialized(false); // Reset on disconnect
      }
    });

    return () => {
      connectionSub.remove();
      leaveStage(); // Ensure we leave the stage on component unmount
    };
  }, []);

  const handleJoin = async () => {
    if (role === 'publisher' && !areLocalStreamsInitialized) {
      // For publishers, initialize devices first. This will trigger permission prompts.
      try {
        await initializeLocalStreams();
        setAreLocalStreamsInitialized(true);
      } catch (error) {
        console.error("Failed to initialize local streams:", error);
        return; // Don't join if permissions are denied.
      }
    }
    // For both roles, join the stage.
    joinStage(TOKEN);
  };

  const handleLeave = () => {
    leaveStage();
    setRole(null); // Go back to role selection
  }

  const handleTogglePublish = () => {
    const newPublishState = !isPublished;
    setStreamsPublished(newPublishState);
    setIsPublished(newPublishState); // Optimistic update
  };

  // UI for choosing a role
  if (!role) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centered}>
          <Text style={styles.header}>Choose Your Role</Text>
          <Button title="Join as a Viewer" onPress={() => setRole('viewer')} />
          <Button title="Join as a Publisher" onPress={() => setRole('publisher')} />
        </View>
      </SafeAreaView>
    );
  }

  // Main UI for viewers and publishers
  return (
    <SafeAreaView style={styles.container}>
      {/* Publisher-only view */}
      {role === 'publisher' && areLocalStreamsInitialized && (
        <View style={styles.halfScreen}>
          <Text style={styles.header}>My Preview</Text>
          <ExpoIVSStagePreviewView style={styles.preview} />
        </View>
      )}

      {/* View for remote participants */}
      <View style={styles.halfScreen}>
        <Text style={styles.header}>Remote Participants ({participants.length})</Text>
        <ScrollView horizontal style={styles.scrollView}>
          {participants.map(p => {
            const videoStream = p.streams.find(s => s.mediaType === 'video');
            return (
              <View key={p.id} style={styles.participantView}>
                {videoStream ? (
                  <ExpoIVSRemoteStreamView style={styles.remoteVideo} />
                ) : (
                  <View style={styles.noVideo}><Text style={styles.text}>No Video</Text></View>
                )}
                <Text style={styles.participantLabel}>{p.id.substring(0, 6)}</Text>
              </View>
            );
          })}
        </ScrollView>
      </View>

      {/* Controls */}
      <View style={styles.controls}>
        {!isConnected ? (
          <Button title={`Join as ${role}`} onPress={handleJoin} />
        ) : (
          <>
            <Button title="Leave" onPress={handleLeave} color="red" />
            {role === 'publisher' && (
              <>
                <Button title={isPublished ? 'Unpublish' : 'Publish'} onPress={handleTogglePublish} />
                <Button title="Swap Cam" onPress={swapCamera} />
              </>
            )}
          </>
        )}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#111' },
  centered: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  halfScreen: { flex: 1 },
  header: { fontSize: 18, color: 'white', padding: 10, textAlign: 'center' },
  preview: { flex: 1, backgroundColor: 'black' },
  scrollView: { flex: 1, paddingLeft: 10 },
  participantView: { width: 150, height: '90%', backgroundColor: 'black', marginRight: 10, borderRadius: 8, overflow: 'hidden' },
  remoteVideo: { width: '100%', height: '100%' },
  noVideo: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#222' },
  text: { color: '#888' },
  participantLabel: { position: 'absolute', bottom: 5, left: 5, color: 'white', backgroundColor: 'rgba(0,0,0,0.5)', padding: 3, borderRadius: 3, fontSize: 10 },
  controls: { paddingBottom: 40, paddingTop: 10, flexDirection: 'row', justifyContent: 'space-evenly', borderTopWidth: 1, borderTopColor: '#333' },
});
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the MIT License.