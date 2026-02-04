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
  // PiP imports
  enablePictureInPicture,
  disablePictureInPicture,
  startPictureInPicture,
  stopPictureInPicture,
  isPictureInPictureActive,
  isPictureInPictureSupported,
  addOnPiPStateChangedListener,
  addOnPiPErrorListener,
  PiPStateChangedPayload,
  PiPErrorPayload,
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
  
  // PiP state
  const [isPiPSupported, setIsPiPSupported] = useState<boolean>(false);
  const [isPiPEnabled, setIsPiPEnabled] = useState<boolean>(false);
  const [isPiPActive, setIsPiPActive] = useState<boolean>(false);
  const [pipState, setPipState] = useState<string>('none');
  const [pipError, setPipError] = useState<string | null>(null);
  
  // Android PiP mode - hide UI to show only video
  const [isInPiPMode, setIsInPiPMode] = useState<boolean>(false);

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

    // PiP event listeners
    const pipStateSub = addOnPiPStateChangedListener((data) => {
      console.log('onPiPStateChanged', data);
      setPipState(data.state);
      setIsPiPActive(data.state === 'started');
      
      // On Android, hide UI when entering PiP to show only video
      if (Platform.OS === 'android') {
        if (data.state === 'started') {
          setIsInPiPMode(true);
        } else if (data.state === 'stopped' || data.state === 'restored') {
          setIsInPiPMode(false);
        }
      }
    });

    const pipErrorSub = addOnPiPErrorListener((data) => {
      console.error('onPiPError', data);
      setPipError(data.error);
    });
    
    // Call the stage configuration initializer on mount for everyone
    handleInitializeStage();
    
    // Check PiP support
    checkPiPSupport();

    return () => {
      connectionSub.remove();
      publishSub.remove();
      errorSub.remove();
      cameraSwapSub.remove();
      cameraSwapErrorSub.remove();
      pipStateSub.remove();
      pipErrorSub.remove();
      disablePictureInPicture(); // Cleanup PiP
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

  // PiP handlers
  const checkPiPSupport = async () => {
    try {
      const supported = await isPictureInPictureSupported();
      setIsPiPSupported(supported);
      console.log('PiP supported:', supported);
    } catch (e) {
      console.error('Check PiP support error:', e);
    }
  };

  const handleEnablePiP = async () => {
    try {
      setPipError(null);
      // Use 'local' for publisher (camera preview), 'remote' for viewer (remote stream)
      const sourceView = role === 'publisher' ? 'local' : 'remote';
      const success = await enablePictureInPicture({
        autoEnterOnBackground: true,
        sourceView,
        preferredAspectRatio: { width: 9, height: 16 },
      });
      setIsPiPEnabled(success);
      console.log('PiP enabled:', success);
    } catch (e) {
      console.error('Enable PiP error:', e);
    }
  };

  const handleDisablePiP = async () => {
    try {
      await disablePictureInPicture();
      setIsPiPEnabled(false);
      setIsPiPActive(false);
      setPipState('none');
      console.log('PiP disabled');
    } catch (e) {
      console.error('Disable PiP error:', e);
    }
  };

  const handleStartPiP = async () => {
    try {
      setPipError(null);
      await startPictureInPicture();
      console.log('PiP start requested');
    } catch (e) {
      console.error('Start PiP error:', e);
    }
  };

  const handleStopPiP = async () => {
    try {
      await stopPictureInPicture();
      console.log('PiP stop requested');
    } catch (e) {
      console.error('Stop PiP error:', e);
    }
  };

  const handleCheckPiPActive = async () => {
    try {
      const active = await isPictureInPictureActive();
      setIsPiPActive(active);
      console.log('PiP active:', active);
    } catch (e) {
      console.error('Check PiP active error:', e);
    }
  };

  const renderRoleSelection = () => (
    <View style={styles.centered}>
      <Text style={styles.header}>Choose Your Role</Text>
      <View style={styles.controlsRow}>
        <Button title="Join as a Viewer" onPress={() => setRole('viewer')} />
        <Button title="Join as a Publisher" onPress={() => setRole('publisher')} />
      </View>
    </View>
  );

  // Render PiP-only mode (Android) - fullscreen video only
  const renderPiPModeUI = () => {
    // For publisher, show local preview; for viewer, show remote stream
    if (role === 'publisher' && localStreamsInitialized) {
      return (
        <View style={styles.pipFullscreenContainer}>
          <ExpoIVSStagePreviewView 
            style={styles.pipFullscreenVideo} 
            mirror={mirrorView}
            scaleMode="fill"
          />
        </View>
      );
    }
    
    // For viewer, show first remote video stream
    const firstVideoParticipant = participants.find(p => 
      p.streams.some(s => s.mediaType === 'video')
    );
    
    if (firstVideoParticipant) {
      return (
        <View style={styles.pipFullscreenContainer}>
          <ExpoIVSRemoteStreamView style={styles.pipFullscreenVideo} />
        </View>
      );
    }
    
    // Fallback: show placeholder
    return (
      <View style={[styles.pipFullscreenContainer, styles.pipPlaceholder]}>
        <Text style={styles.pipPlaceholderText}>Waiting for video...</Text>
      </View>
    );
  };

  const renderSessionUI = () => {
    // On Android, when in PiP mode, show only the video fullscreen
    if (isInPiPMode && Platform.OS === 'android') {
      return renderPiPModeUI();
    }
    
    return (
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
                <View style={styles.controlsRow}>
                    <TouchableOpacity style={styles.flipButton} onPress={handleSwapCamera}>
                      <Text style={styles.flipButtonText}>🔄 FLIP CAMERA</Text>
                    </TouchableOpacity>
                </View>
                {lastSwapResult && (
                  <Text style={styles.swapStatus}>Last swap: {lastSwapResult}</Text>
                )}
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
               <Button title="Swap Cam" onPress={handleSwapCamera} />
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

        {/* PiP Controls */}
        <View style={styles.group}>
          <Text style={styles.groupHeader}>Picture-in-Picture</Text>
          <Text style={styles.pipStatus}>PiP Supported: {isPiPSupported ? '✅ Yes' : '❌ No'}</Text>
          <Text style={styles.pipStatus}>PiP Enabled: {isPiPEnabled ? '✅ Yes' : '❌ No'}</Text>
          <Text style={styles.pipStatus}>PiP Active: {isPiPActive ? '✅ Yes' : '❌ No'}</Text>
          <Text style={styles.pipStatus}>PiP State: {pipState}</Text>
          {pipError && <Text style={styles.pipError}>PiP Error: {pipError}</Text>}
          
          <View style={styles.controlsRow}>
            {!isPiPEnabled ? (
              <TouchableOpacity 
                style={[styles.pipButton, !isPiPSupported && styles.pipButtonDisabled]} 
                onPress={handleEnablePiP}
                disabled={!isPiPSupported}
              >
                <Text style={styles.pipButtonText}>Enable PiP</Text>
              </TouchableOpacity>
            ) : (
              <TouchableOpacity 
                style={[styles.pipButton, styles.pipButtonDanger]} 
                onPress={handleDisablePiP}
              >
                <Text style={styles.pipButtonText}>Disable PiP</Text>
              </TouchableOpacity>
            )}
          </View>
          
          {isPiPEnabled && (
            <View style={styles.controlsRow}>
              <TouchableOpacity 
                style={[styles.pipButton, isPiPActive && styles.pipButtonDisabled]} 
                onPress={handleStartPiP}
                disabled={isPiPActive}
              >
                <Text style={styles.pipButtonText}>Start PiP</Text>
              </TouchableOpacity>
              <TouchableOpacity 
                style={[styles.pipButton, !isPiPActive && styles.pipButtonDisabled]} 
                onPress={handleStopPiP}
                disabled={!isPiPActive}
              >
                <Text style={styles.pipButtonText}>Stop PiP</Text>
              </TouchableOpacity>
            </View>
          )}
          
          <Text style={styles.pipHint}>
            💡 Tip: {role === 'publisher' ? 'Local camera' : 'Remote stream'} will be shown in PiP.
            {'\n'}Press Home button to test auto-enter PiP!
          </Text>
        </View>
      </ScrollView>
    );
  };

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
  flipButton: {
    backgroundColor: '#007AFF',
    paddingHorizontal: 30,
    paddingVertical: 15,
    borderRadius: 10,
    elevation: 3,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
  },
  flipButtonText: {
    color: 'white',
    fontSize: 18,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  swapStatus: {
    textAlign: 'center',
    marginTop: 5,
    fontSize: 12,
    color: '#666',
  },
  // PiP styles
  pipStatus: {
    fontSize: 14,
    marginBottom: 4,
  },
  pipError: {
    color: 'red',
    fontSize: 12,
    marginBottom: 8,
  },
  pipButton: {
    backgroundColor: '#5856D6',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
    marginHorizontal: 5,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
  },
  pipButtonDisabled: {
    backgroundColor: '#ccc',
  },
  pipButtonDanger: {
    backgroundColor: '#FF3B30',
  },
  pipButtonText: {
    color: 'white',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
  pipHint: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    marginTop: 10,
    fontStyle: 'italic',
  },
  // Android PiP fullscreen mode styles
  pipFullscreenContainer: {
    flex: 1,
    backgroundColor: '#000',
  },
  pipFullscreenVideo: {
    flex: 1,
    width: '100%',
    height: '100%',
  },
  pipPlaceholder: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  pipPlaceholderText: {
    color: '#fff',
    fontSize: 16,
  },
});
