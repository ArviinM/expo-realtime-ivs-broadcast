import React, { useEffect, useCallback } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
} from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { ExpoIVSStagePreviewView } from 'expo-realtime-ivs-broadcast';
import { useStream } from '../../src/contexts/StreamContext';
import { useFloatingPlayer } from '../../src/contexts/FloatingPlayerContext';
import { usePublisherAwayMode } from '../../src/hooks/usePiPNavigation';

export default function PublisherBroadcastScreen() {
  const router = useRouter();
  const {
    token,
    setToken,
    connectionState,
    isConnected,
    publishState,
    localStreamsInitialized,
    isPublished,
    isMuted,
    mirrorView,
    setMirrorView,
    lastError,
    lastSwapResult,
    permissionStatus,
    initializeLocalCamera,
    handleJoinStage,
    handleLeaveStage,
    handleTogglePublish,
    handleSwapCamera,
    handleToggleMute,
  } = useStream();

  const {
    activate,
    expand,
    minimize,
    playerState,
    isActive: isFloatingActive,
  } = useFloatingPlayer();

  // Handle publisher away mode - mute camera when mini player is dismissed while live
  usePublisherAwayMode(true, 'Host is away');

  // --- Floating player lifecycle ---

  // When camera is initialized and connected, activate the floating player
  useEffect(() => {
    if (localStreamsInitialized && isConnected && !isFloatingActive) {
      activate();
      console.log('[PublisherBroadcastScreen] Activated floating player (publisher)');
    }
  }, [localStreamsInitialized, isConnected, isFloatingActive]);

  // When this screen gains focus: expand the floating player
  useFocusEffect(
    useCallback(() => {
      console.log('[PublisherBroadcastScreen] Focused, localStreamsInitialized:', localStreamsInitialized);

      if (isFloatingActive) {
        expand();
      }

      // Cleanup: when this screen loses focus, minimize the floating player
      return () => {
        if (isFloatingActive) {
          console.log('[PublisherBroadcastScreen] Blurred, minimizing floating player');
          minimize();
        }
      };
    }, [isFloatingActive])
  );

  const handleNavigateToSettings = () => {
    router.push('/publisher/settings');
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      {/* Camera Preview -- rendered inline so it scrolls naturally with the page */}
      <View style={styles.previewSection}>
        <View style={styles.previewContainer}>
          {localStreamsInitialized && playerState !== 'MINI' ? (
            <ExpoIVSStagePreviewView
              style={styles.preview}
              mirror={mirrorView}
              scaleMode="fill"
            />
          ) : (
            <View style={[styles.preview, styles.placeholder]}>
              <Text style={styles.placeholderIcon}>Camera</Text>
              <Text style={styles.placeholderText}>Camera not initialized</Text>
            </View>
          )}

          {/* Live badge */}
          {isPublished && (
            <View style={styles.liveBadge}>
              <View style={styles.liveDot} />
              <Text style={styles.liveText}>LIVE</Text>
            </View>
          )}

          {/* Mute indicator */}
          {isMuted && localStreamsInitialized && (
            <View style={styles.muteBadge}>
              <Text style={styles.muteIcon}>Muted</Text>
            </View>
          )}
        </View>

        {/* Camera Controls */}
        {localStreamsInitialized ? (
          <View style={styles.cameraControls}>
            <TouchableOpacity
              style={styles.cameraButton}
              onPress={() => setMirrorView(!mirrorView)}
            >
              <Text style={styles.cameraButtonText}>
                {mirrorView ? 'Unmirror' : 'Mirror'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.cameraButton} onPress={handleSwapCamera}>
              <Text style={styles.cameraButtonText}>Flip</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.cameraButton, isMuted && styles.cameraButtonActive]}
              onPress={handleToggleMute}
            >
              <Text style={styles.cameraButtonText}>
                {isMuted ? 'Unmute' : 'Mute'}
              </Text>
            </TouchableOpacity>
          </View>
        ) : (
          <TouchableOpacity
            style={styles.initButton}
            onPress={initializeLocalCamera}
          >
            <Text style={styles.initButtonText}>Start Camera & Microphone</Text>
          </TouchableOpacity>
        )}

        {lastSwapResult && (
          <Text style={styles.swapStatus}>Camera: {lastSwapResult}</Text>
        )}
      </View>

      {/* Connection Controls */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Broadcast Settings</Text>
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
            <Text style={styles.buttonText}>Connect</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.button, styles.dangerButton, !isConnected && styles.buttonDisabled]}
            onPress={handleLeaveStage}
            disabled={!isConnected}
          >
            <Text style={styles.buttonText}>Disconnect</Text>
          </TouchableOpacity>
        </View>

        {/* Publish Control */}
        {isConnected && localStreamsInitialized && (
          <TouchableOpacity
            style={[
              styles.publishButton,
              isPublished ? styles.publishButtonLive : styles.publishButtonOff,
            ]}
            onPress={handleTogglePublish}
          >
            <Text style={styles.publishButtonText}>
              {isPublished ? 'Stop Broadcasting' : 'Go Live'}
            </Text>
          </TouchableOpacity>
        )}

        {/* Status */}
        <View style={styles.statusContainer}>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Connection:</Text>
            <Text style={styles.statusValue}>{connectionState}</Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Publish:</Text>
            <Text style={styles.statusValue}>{publishState}</Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Permissions:</Text>
            <Text style={styles.statusValue}>
              Camera: {permissionStatus?.camera ?? 'N/A'} | Mic: {permissionStatus?.microphone ?? 'N/A'}
            </Text>
          </View>
        </View>
        {lastError && <Text style={styles.errorText}>{lastError}</Text>}
      </View>

      {/* Navigate to Settings while broadcasting */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Navigate While Live</Text>
        <Text style={styles.hintText}>
          Navigate to other screens -- your camera preview continues as a floating mini player!
        </Text>
        <TouchableOpacity
          style={[styles.navButton, !isConnected && styles.navButtonDisabled]}
          onPress={handleNavigateToSettings}
        >
          <Text style={styles.navButtonText}>View Settings</Text>
          <Text style={styles.navButtonSubtext}>Manage preferences</Text>
        </TouchableOpacity>
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
  previewSection: {
    marginBottom: 16,
  },
  previewContainer: {
    width: '100%',
    aspectRatio: 9 / 16,
    backgroundColor: '#000',
    borderRadius: 12,
    overflow: 'hidden',
    position: 'relative',
  },
  preview: {
    flex: 1,
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
  placeholder: {
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#1a1a1a',
  },
  placeholderIcon: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
    marginBottom: 12,
  },
  placeholderText: {
    color: '#999',
    fontSize: 14,
  },
  muteBadge: {
    position: 'absolute',
    top: 12,
    right: 12,
    backgroundColor: 'rgba(0,0,0,0.7)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  muteIcon: {
    fontSize: 12,
    color: '#fff',
    fontWeight: '600',
  },
  cameraControls: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginTop: 12,
  },
  cameraButton: {
    alignItems: 'center',
    backgroundColor: '#fff',
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  cameraButtonActive: {
    backgroundColor: '#ffebee',
  },
  cameraButtonText: {
    fontSize: 12,
    color: '#333',
    fontWeight: '500',
  },
  initButton: {
    backgroundColor: '#D9534F',
    padding: 16,
    borderRadius: 8,
    marginTop: 12,
    alignItems: 'center',
  },
  initButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  swapStatus: {
    fontSize: 11,
    color: '#666',
    textAlign: 'center',
    marginTop: 8,
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
  dangerButton: {
    backgroundColor: '#dc3545',
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
  },
  buttonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  publishButton: {
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  publishButtonLive: {
    backgroundColor: '#dc3545',
  },
  publishButtonOff: {
    backgroundColor: '#28a745',
  },
  publishButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  statusContainer: {
    marginTop: 12,
    padding: 12,
    backgroundColor: '#f8f9fa',
    borderRadius: 8,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  statusLabel: {
    fontSize: 12,
    color: '#666',
  },
  statusValue: {
    fontSize: 12,
    color: '#333',
    fontWeight: '500',
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
    marginTop: 8,
  },
  hintText: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    fontStyle: 'italic',
    marginBottom: 12,
  },
  navButton: {
    backgroundColor: '#fff3e0',
    borderRadius: 12,
    padding: 20,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ffe0b2',
  },
  navButtonDisabled: {
    backgroundColor: '#f5f5f5',
    borderColor: '#e0e0e0',
  },
  navButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  navButtonSubtext: {
    fontSize: 12,
    color: '#666',
    marginTop: 4,
  },
});
