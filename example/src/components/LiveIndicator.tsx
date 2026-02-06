import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Animated,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useStream } from '../contexts/StreamContext';

/**
 * A floating "LIVE" indicator that appears when a publisher navigates away
 * from the broadcast screen while still streaming.
 * 
 * Tapping it returns to the broadcast screen.
 */
export function LiveIndicator() {
  const router = useRouter();
  const {
    role,
    isConnected,
    isPublished,
    isCameraMuted,
  } = useStream();

  // Animation for the pulsing dot
  const pulseAnim = React.useRef(new Animated.Value(1)).current;

  React.useEffect(() => {
    if (!isConnected || !isPublished) return;

    const pulse = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, {
          toValue: 0.4,
          duration: 800,
          useNativeDriver: true,
        }),
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 800,
          useNativeDriver: true,
        }),
      ])
    );
    pulse.start();

    return () => pulse.stop();
  }, [isConnected, isPublished, pulseAnim]);

  // Only show for publishers who are connected and camera is muted (away mode)
  if (role !== 'publisher' || !isConnected || !isPublished || !isCameraMuted) {
    return null;
  }

  const handlePress = () => {
    router.navigate('/publisher/broadcast');
  };

  return (
    <TouchableOpacity
      style={styles.container}
      onPress={handlePress}
      activeOpacity={0.8}
    >
      <View style={styles.indicator}>
        <Animated.View style={[styles.dot, { opacity: pulseAnim }]} />
        <Text style={styles.liveText}>LIVE</Text>
        <Text style={styles.tapText}>Tap to return</Text>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 60,
    right: 16,
    zIndex: 1000,
    elevation: 10,
  },
  indicator: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#FF0000',
    marginRight: 8,
  },
  liveText: {
    color: '#FF0000',
    fontSize: 12,
    fontWeight: 'bold',
    letterSpacing: 1,
  },
  tapText: {
    color: '#FFFFFF',
    fontSize: 10,
    marginLeft: 8,
    opacity: 0.8,
  },
});
