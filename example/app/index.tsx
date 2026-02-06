import React, { useEffect, useRef } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  SafeAreaView,
} from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { useStream } from '../src/contexts/StreamContext';

export default function HomeScreen() {
  const router = useRouter();
  const { setRole, cleanupStream, isConnected } = useStream();

  // Track connection state with a ref to avoid stale closures
  const isConnectedRef = useRef(isConnected);
  useEffect(() => {
    isConnectedRef.current = isConnected;
  }, [isConnected]);

  // Only cleanup when the home screen is truly focused AND user explicitly wants to end session
  // Removing auto-cleanup to allow PiP to continue while browsing
  // The user should explicitly press "Leave" on the stream screen to disconnect
  useFocusEffect(
    React.useCallback(() => {
      // Log when home is focused
      console.log('[HomeScreen] Focused, isConnected:', isConnectedRef.current);
      // Don't auto-cleanup - let the user control when to leave
    }, [])
  );

  const handleViewerPress = () => {
    setRole('viewer');
    router.push('/viewer/stream');
  };

  const handlePublisherPress = () => {
    setRole('publisher');
    router.push('/publisher/broadcast');
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <View style={styles.header}>
          <Text style={styles.title}>IVS Real-Time</Text>
          <Text style={styles.subtitle}>Multi-Screen PiP Demo</Text>
        </View>

        <View style={styles.description}>
          <Text style={styles.descriptionText}>
            This demo showcases Picture-in-Picture functionality with
            multi-screen navigation. Choose your role to begin:
          </Text>
        </View>

        <View style={styles.buttonContainer}>
          <TouchableOpacity
            style={[styles.roleButton, styles.viewerButton]}
            onPress={handleViewerPress}
            activeOpacity={0.8}
          >
            <Text style={styles.roleIcon}>👁️</Text>
            <Text style={styles.roleButtonTitle}>Join as Viewer</Text>
            <Text style={styles.roleButtonDescription}>
              Watch live streams and navigate to other screens while keeping
              the stream in PiP
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.roleButton, styles.publisherButton]}
            onPress={handlePublisherPress}
            activeOpacity={0.8}
          >
            <Text style={styles.roleIcon}>📹</Text>
            <Text style={styles.roleButtonTitle}>Join as Publisher</Text>
            <Text style={styles.roleButtonDescription}>
              Broadcast live and navigate to settings while your stream
              continues in PiP
            </Text>
          </TouchableOpacity>
        </View>

        <View style={styles.features}>
          <Text style={styles.featuresTitle}>PiP Features:</Text>
          <View style={styles.featureItem}>
            <Text style={styles.featureIcon}>✓</Text>
            <Text style={styles.featureText}>
              Auto-activate when navigating away
            </Text>
          </View>
          <View style={styles.featureItem}>
            <Text style={styles.featureIcon}>✓</Text>
            <Text style={styles.featureText}>
              Continue streaming in background
            </Text>
          </View>
          <View style={styles.featureItem}>
            <Text style={styles.featureIcon}>✓</Text>
            <Text style={styles.featureText}>
              Seamless return to fullscreen
            </Text>
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  content: {
    flex: 1,
    padding: 20,
  },
  header: {
    alignItems: 'center',
    marginBottom: 24,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#1a1a1a',
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginTop: 4,
  },
  description: {
    backgroundColor: '#e8f4f8',
    padding: 16,
    borderRadius: 12,
    marginBottom: 24,
  },
  descriptionText: {
    fontSize: 14,
    color: '#333',
    textAlign: 'center',
    lineHeight: 20,
  },
  buttonContainer: {
    gap: 16,
    marginBottom: 24,
  },
  roleButton: {
    padding: 20,
    borderRadius: 16,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  viewerButton: {
    backgroundColor: '#4A90D9',
  },
  publisherButton: {
    backgroundColor: '#D9534F',
  },
  roleIcon: {
    fontSize: 40,
    marginBottom: 8,
  },
  roleButtonTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#fff',
    marginBottom: 8,
  },
  roleButtonDescription: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.9)',
    textAlign: 'center',
    lineHeight: 18,
  },
  features: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  featuresTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 12,
  },
  featureItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  featureIcon: {
    fontSize: 14,
    color: '#4CAF50',
    marginRight: 8,
    fontWeight: 'bold',
  },
  featureText: {
    fontSize: 14,
    color: '#555',
  },
});
