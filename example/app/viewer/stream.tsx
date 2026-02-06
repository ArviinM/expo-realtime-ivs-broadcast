import React, { useEffect, useCallback } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  Dimensions,
} from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { ExpoIVSRemoteStreamView } from 'expo-realtime-ivs-broadcast';
import { useStream } from '../../src/contexts/StreamContext';
import { useFloatingPlayer } from '../../src/contexts/FloatingPlayerContext';
import { useAutoEnablePiP } from '../../src/hooks/usePiPNavigation';

const { width } = Dimensions.get('window');

export default function ViewerStreamScreen() {
  const router = useRouter();
  const {
    token,
    setToken,
    connectionState,
    isConnected,
    participants,
    selectedParticipantId,
    setSelectedParticipantId,
    isPiPSupported,
    isPiPEnabled,
    isPiPActive,
    pipState,
    pipError,
    lastError,
    handleJoinStage,
    handleLeaveStage,
    handleEnablePiP,
    handleDisablePiP,
    handleStartPiP,
    handleStopPiP,
  } = useStream();

  const {
    activate,
    expand,
    minimize,
    setStreamInfo,
    playerState,
    isActive: isFloatingActive,
  } = useFloatingPlayer();

  // Auto-enable system PiP for background transitions
  useAutoEnablePiP();

  // Get selected participant or first with video
  const selectedParticipant = participants.find(p => p.id === selectedParticipantId);
  const selectedVideoStream = selectedParticipant?.streams.find(s => s.mediaType === 'video');

  // --- Floating player lifecycle ---

  // When this screen gains focus: expand the floating player
  useFocusEffect(
    useCallback(() => {
      console.log('[ViewerStreamScreen] Focused, isConnected:', isConnected);

      if (isConnected && selectedVideoStream) {
        // If the floating player is already active (e.g., returning from browse), expand it
        if (isFloatingActive) {
          expand();
        }
      }

      // Cleanup: when this screen loses focus, minimize the floating player
      return () => {
        if (isFloatingActive) {
          console.log('[ViewerStreamScreen] Blurred, minimizing floating player');
          minimize();
        }
      };
    }, [isConnected, isFloatingActive, selectedVideoStream])
  );

  // When a video stream becomes available, activate the floating player
  useEffect(() => {
    if (isConnected && selectedVideoStream && selectedParticipantId) {
      const info = {
        participantId: selectedParticipantId,
        deviceUrn: selectedVideoStream.deviceUrn,
      };

      if (!isFloatingActive) {
        // First time: activate with stream info
        activate(info);
      } else {
        // Already active: update stream info (e.g., participant changed)
        setStreamInfo(info);
      }
    }
  }, [isConnected, selectedParticipantId, selectedVideoStream?.deviceUrn]);

  // Debug logging
  useEffect(() => {
    console.log('[ViewerStreamScreen] Selected participant:', selectedParticipantId);
    console.log('[ViewerStreamScreen] Selected video stream:', selectedVideoStream?.deviceUrn);
  }, [selectedParticipantId, selectedVideoStream]);

  const handleNavigateToBrowse = () => {
    router.push('/viewer/browse');
  };

  const handleNavigateToActivity = () => {
    router.push('/viewer/activity');
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      {/* Main Video Stream -- rendered inline so it scrolls naturally with the page.
          Only render when NOT in MINI mode to avoid two native views competing
          for the same stream (the FloatingStreamContainer has one in MINI mode). */}
      <View style={styles.mainVideoContainer}>
        {selectedVideoStream && playerState !== 'MINI' ? (
          <ExpoIVSRemoteStreamView
            style={styles.mainVideo}
            participantId={selectedParticipantId ?? undefined}
            deviceUrn={selectedVideoStream.deviceUrn}
            scaleMode="fill"
          />
        ) : (
          <View style={[styles.mainVideo, styles.placeholder]}>
            <Text style={styles.placeholderText}>
              {isConnected ? 'Waiting for publisher...' : 'Join a stage to watch'}
            </Text>
          </View>
        )}

        {/* Live badge */}
        {isConnected && selectedVideoStream && (
          <View style={styles.liveBadge}>
            <View style={styles.liveDot} />
            <Text style={styles.liveText}>LIVE</Text>
          </View>
        )}
      </View>

      {/* Participant selector */}
      {participants.length > 1 && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Publishers ({participants.length})</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            {participants.map(p => {
              const hasVideo = p.streams.some(s => s.mediaType === 'video');
              const isSelected = p.id === selectedParticipantId;

              return (
                <TouchableOpacity
                  key={p.id}
                  style={[
                    styles.participantThumb,
                    isSelected && styles.participantThumbSelected,
                  ]}
                  onPress={() => setSelectedParticipantId(p.id)}
                >
                  {hasVideo ? (
                    <ExpoIVSRemoteStreamView
                      style={styles.thumbVideo}
                      participantId={p.id}
                      scaleMode="fill"
                    />
                  ) : (
                    <View style={[styles.thumbVideo, styles.placeholder]}>
                      <Text style={styles.thumbPlaceholder}>Audio</Text>
                    </View>
                  )}
                  <Text style={styles.thumbLabel}>{p.id.substring(0, 6)}</Text>
                </TouchableOpacity>
              );
            })}
          </ScrollView>
        </View>
      )}

      {/* Connection Controls */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Join Stream</Text>
        <TextInput
          style={styles.input}
          placeholder="Enter Stage Token"
          value={token}
          onChangeText={setToken}
          autoCapitalize="none"
          autoCorrect={false}
        />
        <View style={styles.buttonRow}>
          <TouchableOpacity
            style={[styles.button, styles.primaryButton, isConnected && styles.buttonDisabled]}
            onPress={handleJoinStage}
            disabled={isConnected}
          >
            <Text style={styles.buttonText}>Join</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.button, styles.dangerButton, !isConnected && styles.buttonDisabled]}
            onPress={handleLeaveStage}
            disabled={!isConnected}
          >
            <Text style={styles.buttonText}>Leave</Text>
          </TouchableOpacity>
        </View>
        <Text style={styles.statusText}>Status: {connectionState}</Text>
        {lastError && <Text style={styles.errorText}>{lastError}</Text>}
      </View>

      {/* Navigation - Navigate while watching */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Navigate While Watching</Text>
        <Text style={styles.hintText}>
          Navigate to other screens -- the stream continues as a floating mini player!
        </Text>
        <View style={styles.navButtonRow}>
          <TouchableOpacity
            style={[styles.navButton, !isConnected && styles.navButtonDisabled]}
            onPress={handleNavigateToBrowse}
          >
            <Text style={styles.navButtonIcon}>Products</Text>
            <Text style={styles.navButtonText}>Screen A</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.navButton, !isConnected && styles.navButtonDisabled]}
            onPress={handleNavigateToActivity}
          >
            <Text style={styles.navButtonIcon}>Activity</Text>
            <Text style={styles.navButtonText}>Screen B</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* PiP Controls (system PiP for background) */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>System PiP (Background)</Text>
        <View style={styles.pipStatusRow}>
          <Text style={styles.pipStatusItem}>
            Supported: {isPiPSupported ? 'Yes' : 'No'}
          </Text>
          <Text style={styles.pipStatusItem}>
            Enabled: {isPiPEnabled ? 'Yes' : 'No'}
          </Text>
          <Text style={styles.pipStatusItem}>
            Active: {isPiPActive ? 'Yes' : 'No'}
          </Text>
        </View>
        <Text style={styles.pipState}>State: {pipState}</Text>
        {pipError && <Text style={styles.errorText}>{pipError}</Text>}

        <View style={styles.buttonRow}>
          {!isPiPEnabled ? (
            <TouchableOpacity
              style={[styles.button, styles.pipButton, !isPiPSupported && styles.buttonDisabled]}
              onPress={handleEnablePiP}
              disabled={!isPiPSupported}
            >
              <Text style={styles.buttonText}>Enable PiP</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity
              style={[styles.button, styles.dangerButton]}
              onPress={handleDisablePiP}
            >
              <Text style={styles.buttonText}>Disable PiP</Text>
            </TouchableOpacity>
          )}
        </View>

        {isPiPEnabled && (
          <View style={styles.buttonRow}>
            <TouchableOpacity
              style={[styles.button, styles.pipButton, isPiPActive && styles.buttonDisabled]}
              onPress={() => handleStartPiP()}
              disabled={isPiPActive}
            >
              <Text style={styles.buttonText}>Start PiP</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.button, styles.secondaryButton, !isPiPActive && styles.buttonDisabled]}
              onPress={handleStopPiP}
              disabled={!isPiPActive}
            >
              <Text style={styles.buttonText}>Stop PiP</Text>
            </TouchableOpacity>
          </View>
        )}

        <Text style={styles.hintText}>
          System PiP activates when the app goes to background. The in-app mini player handles in-app navigation.
        </Text>
      </View>

      {/* Floating player debug info */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Floating Player</Text>
        <Text style={styles.statusText}>State: {playerState}</Text>
        <Text style={styles.statusText}>Active: {isFloatingActive ? 'Yes' : 'No'}</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  contentContainer: {
    padding: 16,
    paddingBottom: 40,
  },
  mainVideoContainer: {
    width: '100%',
    aspectRatio: 9 / 16,
    backgroundColor: '#000',
    borderRadius: 12,
    overflow: 'hidden',
    marginBottom: 16,
    position: 'relative',
  },
  mainVideo: {
    flex: 1,
  },
  placeholder: {
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#1a1a1a',
  },
  placeholderText: {
    color: '#999',
    fontSize: 14,
  },
  liveBadge: {
    position: 'absolute',
    top: 12,
    left: 12,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(220, 53, 69, 0.9)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 4,
  },
  liveDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#fff',
    marginRight: 6,
  },
  liveText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  section: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 12,
  },
  participantThumb: {
    width: width / 4,
    aspectRatio: 9 / 16,
    marginRight: 8,
    borderRadius: 8,
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  participantThumbSelected: {
    borderColor: '#4A90D9',
  },
  thumbVideo: {
    flex: 1,
  },
  thumbPlaceholder: {
    color: '#fff',
    fontSize: 10,
  },
  thumbLabel: {
    position: 'absolute',
    bottom: 4,
    left: 4,
    color: '#fff',
    fontSize: 10,
    backgroundColor: 'rgba(0,0,0,0.5)',
    paddingHorizontal: 4,
    paddingVertical: 2,
    borderRadius: 4,
  },
  input: {
    height: 44,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingHorizontal: 12,
    marginBottom: 12,
    fontSize: 14,
    backgroundColor: '#fafafa',
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
  },
  button: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: '#4A90D9',
  },
  secondaryButton: {
    backgroundColor: '#6c757d',
  },
  dangerButton: {
    backgroundColor: '#dc3545',
  },
  pipButton: {
    backgroundColor: '#5856D6',
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
  },
  buttonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  statusText: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
  },
  errorText: {
    fontSize: 12,
    color: '#dc3545',
    textAlign: 'center',
    marginTop: 4,
  },
  hintText: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    fontStyle: 'italic',
    marginBottom: 12,
  },
  navButtonRow: {
    flexDirection: 'row',
    gap: 12,
  },
  navButton: {
    flex: 1,
    backgroundColor: '#f0f7ff',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#d0e3ff',
  },
  navButtonDisabled: {
    backgroundColor: '#f5f5f5',
    borderColor: '#e0e0e0',
  },
  navButtonIcon: {
    fontSize: 14,
    fontWeight: '600',
    color: '#4A90D9',
    marginBottom: 4,
  },
  navButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  pipStatusRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 8,
  },
  pipStatusItem: {
    fontSize: 12,
    color: '#555',
  },
  pipState: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    marginBottom: 12,
  },
});
