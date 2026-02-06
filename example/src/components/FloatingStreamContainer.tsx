import React, { useEffect, useState, useRef } from 'react';
import {
  StyleSheet,
  View,
  Text,
  Platform,
  Dimensions,
} from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  Easing,
  runOnJS,
} from 'react-native-reanimated';
import {
  GestureDetector,
  Gesture,
} from 'react-native-gesture-handler';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import {
  ExpoIVSRemoteStreamView,
  ExpoIVSStagePreviewView,
} from 'expo-realtime-ivs-broadcast';
import { useFloatingPlayer } from '../contexts/FloatingPlayerContext';
import { useStream } from '../contexts/StreamContext';
import { MiniPlayerControls } from './MiniPlayerControls';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

// Header bar height (navigation header)
const HEADER_BAR_HEIGHT = Platform.OS === 'ios' ? 44 : 56;

// Mini player dimensions
const MINI_WIDTH = 150;
const MINI_HEIGHT = 250;
const MINI_MARGIN = 16;
const MINI_BORDER_RADIUS = 16;
const MINI_BOTTOM_OFFSET = 100; // Distance from bottom

// Spring config for natural animations
const SPRING_CONFIG = {
  damping: 20,
  stiffness: 200,
  mass: 0.8,
};

/**
 * Floating mini player overlay.
 *
 * ONLY renders when the player state is MINI (user navigated away from
 * the stream/broadcast screen). When EXPANDED or IDLE, this component
 * returns null -- the stream/broadcast screen renders its own inline
 * video view so the video scrolls naturally with the page content.
 */
export function FloatingStreamContainer() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { playerState, expand, dismiss, streamInfo } = useFloatingPlayer();
  const {
    role,
    isConnected,
    participants,
    selectedParticipantId,
    mirrorView,
    handleSetCameraMuted,
  } = useStream();

  // Mini player position
  const miniTop = SCREEN_HEIGHT - MINI_HEIGHT - MINI_BOTTOM_OFFSET - insets.bottom;
  const miniLeft = SCREEN_WIDTH - MINI_WIDTH - MINI_MARGIN;

  // Track whether the component should be mounted (stays true during fade-out)
  const [shouldRender, setShouldRender] = useState(false);
  const prevStateRef = useRef(playerState);

  // --- Shared values ---
  const posTop = useSharedValue(miniTop);
  const posLeft = useSharedValue(miniLeft);
  const opacity = useSharedValue(0);
  const scale = useSharedValue(0.85);

  // For pan gesture offset tracking
  const panOffsetX = useSharedValue(0);
  const panOffsetY = useSharedValue(0);
  const savedPanX = useSharedValue(0);
  const savedPanY = useSharedValue(0);

  // --- Animate on state changes ---
  useEffect(() => {
    const prev = prevStateRef.current;
    prevStateRef.current = playerState;

    if (playerState === 'MINI') {
      // Entering MINI: mount and animate in
      setShouldRender(true);
      opacity.value = withTiming(1, { duration: 250, easing: Easing.out(Easing.cubic) });
      scale.value = withSpring(1, SPRING_CONFIG);
      posTop.value = withSpring(miniTop, SPRING_CONFIG);
      posLeft.value = withSpring(miniLeft, SPRING_CONFIG);
      // Reset pan offset
      panOffsetX.value = 0;
      panOffsetY.value = 0;
      savedPanX.value = 0;
      savedPanY.value = 0;
    } else if (prev === 'MINI' && shouldRender) {
      // Leaving MINI (going to EXPANDED or IDLE): fade out, then unmount
      scale.value = withTiming(0.85, { duration: 200, easing: Easing.in(Easing.cubic) });
      opacity.value = withTiming(0, { duration: 200, easing: Easing.in(Easing.cubic) }, (finished) => {
        if (finished) {
          runOnJS(setShouldRender)(false);
        }
      });
    }
  }, [playerState, miniTop, miniLeft]);

  // --- Gestures ---

  const navigateToStream = () => {
    if (role === 'viewer') {
      router.navigate('/viewer/stream');
    } else if (role === 'publisher') {
      router.navigate('/publisher/broadcast');
    }
    expand();
  };

  const handleDismiss = () => {
    if (role === 'publisher') {
      handleSetCameraMuted(true, 'Host is away');
    }
    dismiss();
  };

  // Snap to nearest corner
  const snapToCorner = (currentX: number, currentY: number) => {
    'worklet';
    const centerX = currentX + MINI_WIDTH / 2;
    const centerY = currentY + MINI_HEIGHT / 2;
    const screenCenterX = SCREEN_WIDTH / 2;
    const screenCenterY = SCREEN_HEIGHT / 2;

    const snapL = centerX < screenCenterX ? MINI_MARGIN : SCREEN_WIDTH - MINI_WIDTH - MINI_MARGIN;
    const snapT = centerY < screenCenterY
      ? insets.top + HEADER_BAR_HEIGHT + MINI_MARGIN
      : SCREEN_HEIGHT - MINI_HEIGHT - MINI_BOTTOM_OFFSET - insets.bottom;

    return { snapL, snapT };
  };

  const panGesture = Gesture.Pan()
    .onStart(() => {
      savedPanX.value = panOffsetX.value;
      savedPanY.value = panOffsetY.value;
    })
    .onUpdate((event) => {
      panOffsetX.value = savedPanX.value + event.translationX;
      panOffsetY.value = savedPanY.value + event.translationY;
      posLeft.value = miniLeft + panOffsetX.value;
      posTop.value = miniTop + panOffsetY.value;
    })
    .onEnd((event) => {
      const currentLeft = miniLeft + panOffsetX.value;
      const currentTop = miniTop + panOffsetY.value;

      // Check for dismiss (swiped off edge)
      const velocity = Math.sqrt(event.velocityX ** 2 + event.velocityY ** 2);
      const isOffScreenLeft = currentLeft < -MINI_WIDTH / 2;
      const isOffScreenRight = currentLeft > SCREEN_WIDTH - MINI_WIDTH / 2;

      if (velocity > 1000 && (isOffScreenLeft || isOffScreenRight)) {
        opacity.value = withSpring(0, SPRING_CONFIG);
        runOnJS(handleDismiss)();
        return;
      }

      // Snap to nearest corner
      const { snapL, snapT } = snapToCorner(currentLeft, currentTop);
      posLeft.value = withSpring(snapL, SPRING_CONFIG);
      posTop.value = withSpring(snapT, SPRING_CONFIG);
      panOffsetX.value = snapL - miniLeft;
      panOffsetY.value = snapT - miniTop;
    });

  const tapGesture = Gesture.Tap()
    .onEnd(() => {
      runOnJS(navigateToStream)();
    });

  const composedGesture = Gesture.Race(panGesture, tapGesture);

  // --- Animated style ---
  const animatedStyle = useAnimatedStyle(() => ({
    position: 'absolute' as const,
    top: posTop.value,
    left: posLeft.value,
    width: MINI_WIDTH,
    height: MINI_HEIGHT,
    borderRadius: MINI_BORDER_RADIUS,
    opacity: opacity.value,
    transform: [{ scale: scale.value }],
    overflow: 'hidden' as const,
    ...(Platform.OS === 'android'
      ? { elevation: 10 }
      : {
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.3,
          shadowRadius: 8,
        }),
  }));

  // Only render while in MINI mode or during fade-out animation
  if (!shouldRender) {
    return null;
  }

  // Determine video content
  const selectedParticipant = participants.find(p => p.id === selectedParticipantId);
  const selectedVideoStream = selectedParticipant?.streams.find(s => s.mediaType === 'video');
  const viewerParticipantId = streamInfo.participantId || selectedParticipantId;
  const viewerDeviceUrn = streamInfo.deviceUrn || selectedVideoStream?.deviceUrn;
  const hasViewerContent = role === 'viewer' && viewerParticipantId && viewerDeviceUrn;
  const hasPublisherContent = role === 'publisher';

  if (!hasViewerContent && !hasPublisherContent) {
    return null;
  }

  return (
    <View style={styles.fullScreenOverlay} pointerEvents="box-none">
      <GestureDetector gesture={composedGesture}>
        <Animated.View style={animatedStyle}>
          <View style={styles.videoContainer}>
            {role === 'viewer' && hasViewerContent ? (
              <ExpoIVSRemoteStreamView
                style={styles.video}
                participantId={viewerParticipantId ?? undefined}
                deviceUrn={viewerDeviceUrn ?? undefined}
                scaleMode="fill"
              />
            ) : role === 'publisher' ? (
              <ExpoIVSStagePreviewView
                style={styles.video}
                mirror={mirrorView}
                scaleMode="fill"
              />
            ) : (
              <View style={[styles.video, styles.placeholder]}>
                <View style={styles.loadingDot} />
              </View>
            )}

            {/* Live badge */}
            {isConnected && (
              <View style={styles.liveBadge}>
                <View style={styles.liveDot} />
                <Text style={styles.liveText}>LIVE</Text>
              </View>
            )}
          </View>

          <MiniPlayerControls
            onExpand={navigateToStream}
            onDismiss={handleDismiss}
          />
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

const styles = StyleSheet.create({
  fullScreenOverlay: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 9999,
    elevation: 9999,
  },
  videoContainer: {
    flex: 1,
    backgroundColor: '#000',
    overflow: 'hidden',
  },
  video: {
    flex: 1,
  },
  placeholder: {
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#1a1a1a',
  },
  loadingDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#555',
  },
  liveBadge: {
    position: 'absolute',
    top: 8,
    left: 8,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(220, 53, 69, 0.9)',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 4,
  },
  liveDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: '#fff',
    marginRight: 4,
  },
  liveText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
  },
});
