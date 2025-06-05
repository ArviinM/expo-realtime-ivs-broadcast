import React, { useState, useEffect } from 'react';
import {
  StyleSheet,
  Text,
  View,
  Button,
  TextInput,
  ScrollView,
  SafeAreaView,
  Platform,
  PermissionsAndroid,
  Dimensions
} from 'react-native';
import {
  IVSStagePreviewView,
  initialize,
  joinStage,
  leaveStage,
  setStreamsPublished,
  swapCamera,
  setMicrophoneMuted,
  requestPermissions,
  StageConnectionStatePayload,
  PublishStatePayload,
  StageErrorPayload,
  PermissionStatusMap,
  ExpoRealtimeIvsBroadcastViewProps, // For scaleMode and mirror type
  addOnStageConnectionStateChangedListener,
  addOnPublishStateChangedListener,
  addOnStageErrorListener,
  addOnCameraSwappedListener,
  addOnCameraSwapErrorListener,
  CameraSwappedPayload,
  CameraSwapErrorPayload,
} from 'expo-realtime-ivs-broadcast'; // Assuming your library is correctly linked

const { width } = Dimensions.get('window');

export default function App() {
  const [token, setToken] = useState<string>(''); // Store your IVS Stage token here
  const [isPublished, setIsPublished] = useState<boolean>(false);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [mirrorView, setMirrorView] = useState<boolean>(false);
  const [scaleMode, setScaleMode] = useState<ExpoRealtimeIvsBroadcastViewProps['scaleMode']>('fill');

  const [connectionState, setConnectionState] = useState<StageConnectionStatePayload | null>(null);
  const [publishState, setPublishState] = useState<PublishStatePayload | null>(null);
  const [lastError, setLastError] = useState<StageErrorPayload | null>(null);
  const [permissionStatus, setPermissionStatus] = useState<PermissionStatusMap | null>(null);
  const [lastSwapResult, setLastSwapResult] = useState<string | null>(null);

  useEffect(() => {
    const connectionSub = addOnStageConnectionStateChangedListener((data) => {
      console.log('onStageConnectionStateChanged', data);
      setConnectionState(data);
      if (data.state === 'connected') {
        // setIsPublished(true); // Auto-publish on connect or wait for user action
      } else if (data.state === 'disconnected') {
        setIsPublished(false);
      }
    });

    const publishSub = addOnPublishStateChangedListener((data) => {
      console.log('onPublishStateChanged', data);
      setPublishState(data);
      if (data.state === 'published') {
        setIsPublished(true);
      } else if (data.state === 'not_published' || data.state === 'failed') {
        setIsPublished(false);
      }
    });

    const errorSub = addOnStageErrorListener((data) => {
      console.error('onStageError', data);
      setLastError(data);
    });

    const cameraSwapSub = addOnCameraSwappedListener((data) => {
      console.log('onCameraSwapped', data);
      setLastSwapResult(`Success: ${data.newCameraName}`);
    });

    const cameraSwapErrorSub = addOnCameraSwapErrorListener((data) => {
      console.error('onCameraSwapError', data);
      setLastSwapResult(`Error: ${data.reason}`);
    });

    // Request permissions on mount for iOS, for Android it's a bit different
    // but our requestPermissions() handles both within the native code for simplicity here.
    handleRequestPermissions();
    handleInitialize(); // Initialize on mount

    return () => {
      connectionSub.remove();
      publishSub.remove();
      errorSub.remove();
      cameraSwapSub.remove();
      cameraSwapErrorSub.remove();
      // Optional: leaveStage on unmount if connected
      // if (connectionState?.state === 'connected') {
      //   handleLeaveStage();
      // }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleInitialize = async () => {
    try {
      await initialize(); // Add audio/video configs if needed
      console.log('SDK Initialized');
    } catch (e) {
      console.error('Initialize error:', e);
    }
  };

  const handleRequestPermissions = async () => {
    try {
      const status = await requestPermissions();
      setPermissionStatus(status);
      console.log('Permissions:', status);
      if (Platform.OS === 'android') {
        if (status.camera !== 'granted' || status.microphone !== 'granted') {
            // On Android, native requestPermissions will pop system dialogs
            // For more complex scenarios, one might use PermissionsAndroid.requestMultiple
            console.warn("Android permissions not fully granted via native module call, system dialogs should have appeared.");
        }
      }
    } catch (e) {
      console.error('Request permissions error:', e);
    }
  };

  const handleJoinStage = async () => {
    if (!token) {
      alert('Please enter a token!');
      return;
    }
    try {
      await joinStage(token);
      console.log('Joining stage...');
    } catch (e) {
      console.error('Join stage error:', e);
    }
  };

  const handleLeaveStage = async () => {
    try {
      await leaveStage();
      console.log('Left stage');
    } catch (e) {
      console.error('Leave stage error:', e);
    }
  };

  const handleTogglePublish = async () => {
    try {
      await setStreamsPublished(!isPublished);
      // The actual state will be updated via onPublishStateChanged event
    } catch (e) {
      console.error('Toggle publish error:', e);
    }
  };

  const handleSwapCamera = async () => {
    try {
      await swapCamera();
      console.log('Swapped camera');
    } catch (e) {
      console.error('Swap camera error:', e);
    }
  };

  const handleToggleMute = async () => {
    try {
      await setMicrophoneMuted(!isMuted);
      setIsMuted(!isMuted); // Optimistic update, or wait for an event if the SDK provides one
      console.log('Toggled mute');
    } catch (e) {
      console.error('Toggle mute error:', e);
    }
  };
  
  const toggleMirror = () => setMirrorView(prev => !prev);
  const toggleScaleMode = () => setScaleMode(prev => prev === 'fill' ? 'fit' : 'fill');

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContentContainer}>
        <Text style={styles.header}>IVS Real-Time Broadcaster</Text>

        <View style={styles.previewContainer}>
          <IVSStagePreviewView 
            style={styles.preview} 
            mirror={mirrorView}
            scaleMode={scaleMode}
          />
        </View>
        <View style={styles.controlsRow}>
            <Button title={mirrorView ? "Unmirror" : "Mirror"} onPress={toggleMirror} />
            <Button title={`Scale: ${scaleMode}`} onPress={toggleScaleMode} />
        </View>

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Permissions</Text>
          <Button title="Request Cam/Mic Permissions" onPress={handleRequestPermissions} />
          <Text>Camera: {permissionStatus?.camera}</Text>
          <Text>Microphone: {permissionStatus?.microphone}</Text>
        </View>

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Stage Control</Text>
          <Button title="Initialize SDK" onPress={handleInitialize} />
          <TextInput
            style={styles.input}
            placeholder="Enter IVS Stage Token"
            value={token}
            onChangeText={setToken}
            secureTextEntry
          />
          <Button title="Join Stage" onPress={handleJoinStage} disabled={!token || connectionState?.state === 'connected'} />
          <Button title="Leave Stage" onPress={handleLeaveStage} disabled={connectionState?.state !== 'connected'} />
        </View>

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Stream Control</Text>
          <Button 
            title={isPublished ? "Unpublish Streams" : "Publish Streams"} 
            onPress={handleTogglePublish} 
            disabled={connectionState?.state !== 'connected'}
          />
          <Button 
            title={isMuted ? "Unmute Mic" : "Mute Mic"} 
            onPress={handleToggleMute} 
            disabled={connectionState?.state !== 'connected'} 
          />
          <Button title="Swap Camera" onPress={handleSwapCamera} disabled={connectionState?.state !== 'connected'} />
        </View>

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Event Status</Text>
          <Text>Connection: {connectionState?.state || '-'} {connectionState?.error ? `(Error: ${connectionState.error})`: ''}</Text>
          <Text>Publish: {publishState?.state || '-'} {publishState?.error ? `(Error: ${publishState.error})`: ''}</Text>
          <Text>Last Swap: {lastSwapResult || '-'}</Text>
          {lastError && (
            <Text style={{color: 'red'}}>
              Last Error: {lastError.description} (Code: {lastError.code}, Source: {lastError.source}, Fatal: {String(lastError.isFatal)})
            </Text>
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f0f0f0',
  },
  scrollContentContainer: {
    paddingBottom: 50, // Ensure scroll content isn't hidden by nav bars etc.
  },
  header: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginVertical: 20,
  },
  previewContainer: {
    width: width * 0.9,
    height: width * 0.9 * (16/9), // 16:9 aspect ratio
    alignSelf: 'center',
    backgroundColor: '#000',
    marginBottom: 10,
    borderWidth: 1,
    borderColor: 'grey'
  },
  preview: {
    flex: 1,
  },
  controlsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
    marginBottom: 20,
    paddingHorizontal: 10,
  },
  group: {
    marginHorizontal: 15,
    marginVertical: 10,
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 15,
    shadowColor: "#000",
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.22,
    shadowRadius: 2.22,
    elevation: 3,
  },
  groupHeader: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 5,
    padding: 10,
    marginBottom: 10,
    fontSize: 16,
  },
});
