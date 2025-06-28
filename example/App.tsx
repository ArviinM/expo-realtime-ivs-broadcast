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
  Dimensions,
  TouchableOpacity,
} from 'react-native';
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
  setMicrophoneMuted,
  requestPermissions,
  StageConnectionStatePayload,
  PublishStatePayload,
  StageErrorPayload,
  PermissionStatusMap,
  ExpoIVSStagePreviewViewProps, // For scaleMode and mirror type
  addOnStageConnectionStateChangedListener,
  addOnPublishStateChangedListener,
  addOnStageErrorListener,
  addOnCameraSwappedListener,
  addOnCameraSwapErrorListener,
  CameraSwappedPayload,
  CameraSwapErrorPayload,
} from 'expo-realtime-ivs-broadcast';

const { width } = Dimensions.get('window');

type Role = 'viewer' | 'publisher';

export default function App() {
  const [token, setToken] = useState<string>('YOUR_TOKEN_HERE'); // Store your IVS Stage token here
  const [role, setRole] = useState<Role | null>(null);
  const [isPublished, setIsPublished] = useState<boolean>(false);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [mirrorView, setMirrorView] = useState<boolean>(false);
  const [scaleMode, setScaleMode] = useState<ExpoIVSStagePreviewViewProps['scaleMode']>('fill');

  const [connectionState, setConnectionState] = useState<StageConnectionStatePayload | null>(null);
  const [publishState, setPublishState] = useState<PublishStatePayload | null>(null);
  const [lastError, setLastError] = useState<StageErrorPayload | null>(null);
  const [permissionStatus, setPermissionStatus] = useState<PermissionStatusMap | null>(null);
  const [lastSwapResult, setLastSwapResult] = useState<string | null>(null);
  const [localStreamsInitialized, setLocalStreamsInitialized] = useState(false);

  // Use the new hook to get participant data
  const { participants } = useStageParticipants();

  useEffect(() => {
    // Log participant data whenever it changes, for debugging purposes.
    console.log('Participants updated:', JSON.stringify(participants, null, 2));
  }, [participants]);

  useEffect(() => {
    const connectionSub = addOnStageConnectionStateChangedListener((data) => {
      console.log('onStageConnectionStateChanged', data);
      setConnectionState(data);
      if (data.state === 'disconnected') {
        setIsPublished(false);
        setLocalStreamsInitialized(false); // Reset on disconnect
      }
    });

    const publishSub = addOnPublishStateChangedListener((data) => {
      console.log('onPublishStateChanged', data);
      setPublishState(data);
      setIsPublished(data.state === 'published');
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
    
    // Call the stage configuration initializer on mount for everyone
    handleInitializeStage();

    return () => {
      connectionSub.remove();
      publishSub.remove();
      errorSub.remove();
      cameraSwapSub.remove();
      cameraSwapErrorSub.remove();
      handleLeaveStage(); // Leave stage on unmount
    };
  }, []);

  const handleInitializeStage = async () => {
    try {
      await initializeStage(); // Add audio/video configs if needed
      console.log('SDK Initialized for Stage configuration');
    } catch (e) {
      console.error('Initialize stage error:', e);
    }
  };

  const handleInitializeLocalStreams = async () => {
    if (Platform.OS === 'android') {
        // Android requires explicit permission request *before* initializing devices
        try {
            const granted = await PermissionsAndroid.requestMultiple([
                PermissionsAndroid.PERMISSIONS.CAMERA,
                PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
            ]);
            if (granted[PermissionsAndroid.PERMISSIONS.CAMERA] !== 'granted' || granted[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] !== 'granted') {
                alert('Permissions required to go live.');
                return;
            }
        } catch (err) {
            console.warn(err);
            return;
        }
    }

    try {
      await initializeLocalStreams();
      console.log('Local streams initialized');
      setLocalStreamsInitialized(true);
      // On iOS, this is the first point where permission prompts will appear.
      // We can check the result after.
      const status = await requestPermissions();
      setPermissionStatus(status);
    } catch (e) {
      console.error('Initialize local streams error:', e);
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
      setRole(null); // Go back to role selection
    } catch (e) {
      console.error('Leave stage error:', e);
    }
  };

  const handleTogglePublish = async () => {
    try {
      await setStreamsPublished(!isPublished);
    } catch (e) {
      console.error('Toggle publish error:', e);
    }
  };

  const handleSwapCamera = async () => {
    try {
      await swapCamera();
    } catch (e) {
      console.error('Swap camera error:', e);
    }
  };

  const handleToggleMute = async () => {
    try {
      await setMicrophoneMuted(!isMuted);
      setIsMuted(!isMuted);
    } catch (e) {
      console.error('Toggle mute error:', e);
    }
  };
  
  const toggleMirror = () => setMirrorView(prev => !prev);
  const toggleScaleMode = () => setScaleMode(prev => prev === 'fill' ? 'fit' : 'fill');

  const renderRoleSelection = () => (
    <View style={styles.centered}>
      <Text style={styles.header}>Choose Your Role</Text>
      <View style={styles.controlsRow}>
        <Button title="Join as a Viewer" onPress={() => setRole('viewer')} />
        <Button title="Join as a Publisher" onPress={() => setRole('publisher')} />
      </View>
    </View>
  );

  const renderSessionUI = () => (
    <ScrollView contentContainerStyle={styles.scrollContentContainer}>
        <Text style={styles.header}>IVS Real-Time Demo ({role})</Text>

        {role === 'publisher' && (
          <View style={styles.group}>
            <Text style={styles.groupHeader}>My Preview</Text>
            {localStreamsInitialized ? (
              <>
                <View style={styles.previewContainer}>
                  <ExpoIVSStagePreviewView 
                    style={styles.preview} 
                    mirror={mirrorView}
                    scaleMode={scaleMode}
                  />
                </View>
                <View style={styles.controlsRow}>
                    <Button title={mirrorView ? "Unmirror" : "Mirror"} onPress={toggleMirror} />
                    <Button title={`Scale: ${scaleMode}`} onPress={toggleScaleMode} />
                </View>
              </>
            ) : (
              <Button title="Start Camera & Mic (Go Live)" onPress={handleInitializeLocalStreams} />
            )}
          </View>
        )}

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Remote Participants ({participants.length})</Text>
            <ScrollView horizontal style={styles.remoteStreamsContainer}>
              {participants.map(p => {
                const videoStream = p.streams.find(s => s.mediaType === 'video');
                const key = p.id + (videoStream?.deviceUrn ?? '');

                return (
                  <View key={key} style={styles.remoteStreamWrapper}>
                    {videoStream ? (
                      <ExpoIVSRemoteStreamView
                        style={styles.remoteStream}
                      />
                    ) : (
                      <View style={[styles.remoteStream, styles.placeholder]}>
                        <Text style={styles.placeholderText}>{p.id.substring(0, 8)} (Audio Only)</Text>
                      </View>
                    )}
                    <Text style={styles.participantLabel}>{p.id.substring(0, 8)}</Text>
                  </View>
                );
              })}
            </ScrollView>
        </View>

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Session Controls</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter Stage Token"
            value={token}
            onChangeText={setToken}
            secureTextEntry
          />
          <View style={styles.controlsRow}>
            <Button title="Join" onPress={handleJoinStage} disabled={connectionState?.state === 'connected'} />
            <Button title="Leave" onPress={handleLeaveStage} disabled={connectionState?.state !== 'connected'} />
          </View>
          {role === 'publisher' && (
             <View style={styles.controlsRow}>
               <Button title={isPublished ? 'Unpublish' : 'Publish'} onPress={handleTogglePublish} disabled={!localStreamsInitialized || connectionState?.state !== 'connected'} />
               <Button title="Swap Cam" onPress={handleSwapCamera} disabled={!localStreamsInitialized} />
               <Button title={isMuted ? 'Unmute' : 'Mute'} onPress={handleToggleMute} disabled={!localStreamsInitialized} />
             </View>
          )}
        </View>

        <View style={styles.group}>
          <Text style={styles.groupHeader}>Status</Text>
          <Text>Connection: {connectionState?.state ?? 'not connected'}</Text>
          <Text>Publish: {publishState?.state ?? 'not published'}</Text>
          <Text>Participants: {participants.length}</Text>
          <Text>Permissions: Camera - {permissionStatus?.camera}, Mic - {permissionStatus?.microphone}</Text>
          <Text>Last Swap: {lastSwapResult ?? 'N/A'}</Text>
          {lastError && <Text style={{ color: 'red' }}>Error: {lastError.description}</Text>}
        </View>
      </ScrollView>
  );

  return (
    <SafeAreaView style={styles.container}>
      {role ? renderSessionUI() : renderRoleSelection()}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F5FCFF',
  },
  scrollContentContainer: {
    padding: 16,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  group: {
    marginBottom: 20,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 10,
  },
  groupHeader: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  previewContainer: {
    width: '100%',
    aspectRatio: 9 / 16,
    backgroundColor: 'black',
    marginBottom: 10,
    borderRadius: 8,
    overflow: 'hidden',
  },
  preview: {
    flex: 1,
  },
  remoteStreamsContainer: {
    flexDirection: 'row',
  },
  remoteStreamWrapper: {
    width: width / 2.5,
    aspectRatio: 9 / 16,
    marginRight: 10,
    backgroundColor: 'black',
    borderRadius: 8,
    overflow: 'hidden',
    justifyContent: 'center',
    alignItems: 'center',
  },
  remoteStream: {
    flex: 1,
    width: '100%',
  },
  placeholder: {
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#222',
  },
  placeholderText: {
    color: 'white',
  },
  participantLabel: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    color: 'white',
    backgroundColor: 'rgba(0,0,0,0.5)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    fontSize: 12,
  },
  input: {
    height: 40,
    borderColor: 'gray',
    borderWidth: 1,
    marginBottom: 10,
    paddingHorizontal: 8,
    borderRadius: 4,
  },
  controlsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 10,
  },
});
