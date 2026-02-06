import { useEffect, useRef, useCallback } from 'react';
import { useStream } from '../contexts/StreamContext';
import { useFocusEffect } from 'expo-router';

/**
 * Global hook to handle system PiP restore events and navigate to the stream screen.
 * This should be used at the ROOT level (_layout.tsx) to handle PiP restoration
 * from ANY screen in the app (when user taps the system PiP window).
 * 
 * Note: This handles SYSTEM PiP (background) restore only. In-app mini player
 * navigation is handled by FloatingPlayerContext.
 * 
 * @param navigateToStream - Callback to navigate to the appropriate stream screen
 */
export function useGlobalPiPRestore(navigateToStream: () => void) {
  const { pipState, isConnected } = useStream();
  const prevPipStateRef = useRef(pipState);

  useEffect(() => {
    // Check if PiP just transitioned to 'restored'
    if (pipState === 'restored' && prevPipStateRef.current !== 'restored') {
      console.log('[useGlobalPiPRestore] System PiP restored, navigating to stream');
      if (isConnected) {
        navigateToStream();
      }
    }

    prevPipStateRef.current = pipState;
  }, [pipState, isConnected, navigateToStream]);
}

/**
 * Hook to auto-enable system PiP when stream is ready.
 * Call this on the main stream screen after connecting.
 * 
 * System PiP is used when the app goes to background. The in-app
 * mini player handles navigation within the app.
 */
export function useAutoEnablePiP() {
  const {
    isConnected,
    isPiPSupported,
    isPiPEnabled,
    handleEnablePiP,
    role,
    participants,
    localStreamsInitialized,
  } = useStream();

  const hasEnabledRef = useRef(false);

  // For viewers: need at least one participant with video
  const hasViewerContent = role === 'viewer' && participants.some(p => p.streams.some(s => s.mediaType === 'video'));
  // For publishers: need local streams initialized
  const hasPublisherContent = role === 'publisher' && localStreamsInitialized;
  const hasContent = hasViewerContent || hasPublisherContent;

  useEffect(() => {
    // Auto-enable system PiP once we're connected and have content
    if (
      isConnected &&
      isPiPSupported &&
      !isPiPEnabled &&
      hasContent &&
      !hasEnabledRef.current
    ) {
      console.log('[useAutoEnablePiP] Auto-enabling system PiP for background transitions');
      hasEnabledRef.current = true;
      handleEnablePiP();
    }
  }, [isConnected, isPiPSupported, isPiPEnabled, hasContent, handleEnablePiP]);

  // Reset when disconnected
  useEffect(() => {
    if (!isConnected) {
      hasEnabledRef.current = false;
    }
  }, [isConnected]);
}

/**
 * Hook to manage publisher "away mode" - mutes camera when navigating away
 * from the broadcast screen, showing a placeholder to viewers.
 * 
 * This is used as a FALLBACK when the publisher dismisses the mini player
 * while still broadcasting. The camera gets muted so viewers see a placeholder.
 * 
 * @param isBroadcastScreen - Whether the current screen is the broadcast screen
 * @param placeholderText - Text to show on the placeholder (default: "Host is away")
 */
export function usePublisherAwayMode(
  isBroadcastScreen: boolean,
  placeholderText: string = 'Host is away'
) {
  const {
    role,
    isConnected,
    isPublished,
    handleSetCameraMuted,
    isCameraMuted,
  } = useStream();

  // Store values in refs to avoid dependency issues with useFocusEffect
  const stateRef = useRef({
    role,
    isConnected,
    isPublished,
    handleSetCameraMuted,
    placeholderText,
  });
  
  // Keep refs updated
  useEffect(() => {
    stateRef.current = {
      role,
      isConnected,
      isPublished,
      handleSetCameraMuted,
      placeholderText,
    };
  });

  // Handle unmuting when returning to broadcast screen
  useEffect(() => {
    if (!isBroadcastScreen) {
      return;
    }
    
    const isLivePublisher = role === 'publisher' && isConnected && isPublished;
    
    if (isLivePublisher && isCameraMuted) {
      console.log('[usePublisherAwayMode] On broadcast with muted camera - unmuting');
      handleSetCameraMuted(false);
    }
  }, [isBroadcastScreen, role, isConnected, isPublished, isCameraMuted, handleSetCameraMuted]);
}
