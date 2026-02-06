import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useRef,
  ReactNode,
} from 'react';
import { Platform, PermissionsAndroid } from 'react-native';
import {
  initializeStage,
  initializeLocalStreams,
  joinStage,
  leaveStage,
  setStreamsPublished,
  swapCamera,
  setMicrophoneMuted,
  setCameraMuted,
  isCameraMuted as nativeIsCameraMuted,
  requestPermissions,
  enablePictureInPicture,
  disablePictureInPicture,
  startPictureInPicture,
  stopPictureInPicture,
  isPictureInPictureActive,
  isPictureInPictureSupported,
  useStageParticipants,
  addOnStageConnectionStateChangedListener,
  addOnPublishStateChangedListener,
  addOnStageErrorListener,
  addOnCameraSwappedListener,
  addOnCameraSwapErrorListener,
  addOnCameraMuteStateChangedListener,
  addOnPiPStateChangedListener,
  addOnPiPErrorListener,
  Participant,
  PermissionStatusMap,
} from 'expo-realtime-ivs-broadcast';

export type Role = 'viewer' | 'publisher' | null;
export type ConnectionState = 'disconnected' | 'connecting' | 'connected';
export type PublishState = 'not_published' | 'attempting' | 'published' | 'failed';
export type PiPState = 'none' | 'started' | 'stopped' | 'restored';

interface StreamContextType {
  // Role
  role: Role;
  setRole: (role: Role) => void;

  // Connection
  isConnected: boolean;
  connectionState: ConnectionState;
  publishState: PublishState;
  
  // Token
  token: string;
  setToken: (token: string) => void;

  // Local streams (publisher)
  localStreamsInitialized: boolean;
  isPublished: boolean;
  isMuted: boolean;
  isCameraMuted: boolean;
  isPlaceholderActive: boolean;
  mirrorView: boolean;
  setMirrorView: (mirror: boolean) => void;

  // Participants
  participants: Participant[];
  selectedParticipantId: string | null;
  setSelectedParticipantId: (id: string | null) => void;

  // PiP
  isPiPSupported: boolean;
  isPiPEnabled: boolean;
  isPiPActive: boolean;
  pipState: PiPState;
  pipError: string | null;
  isInPiPMode: boolean;
  isPiPAutoStarted: boolean; // Track if PiP was started by navigation vs manual

  // Permissions
  permissionStatus: PermissionStatusMap | null;

  // Errors
  lastError: string | null;
  lastSwapResult: string | null;

  // Actions
  initializeLocalCamera: () => Promise<void>;
  handleJoinStage: () => Promise<void>;
  handleLeaveStage: () => Promise<void>;
  handleTogglePublish: () => Promise<void>;
  handleSwapCamera: () => Promise<void>;
  handleToggleMute: () => Promise<void>;
  handleSetCameraMuted: (muted: boolean, placeholderText?: string) => Promise<void>;
  handleEnablePiP: () => Promise<void>;
  handleDisablePiP: () => Promise<void>;
  handleStartPiP: (isAutoStart?: boolean) => Promise<void>;
  handleStopPiP: () => Promise<void>;
  clearPiPAutoStartFlag: () => void;
  cleanupStream: () => Promise<void>;
}

const StreamContext = createContext<StreamContextType | null>(null);

export function useStream() {
  const context = useContext(StreamContext);
  if (!context) {
    throw new Error('useStream must be used within a StreamProvider');
  }
  return context;
}

interface StreamProviderProps {
  children: ReactNode;
}

export function StreamProvider({ children }: StreamProviderProps) {
  // Role state
  const [role, setRole] = useState<Role>(null);

  // Token
  const [token, setToken] = useState<string>('');

  // Connection state
  const [connectionState, setConnectionState] = useState<ConnectionState>('disconnected');
  const [publishState, setPublishState] = useState<PublishState>('not_published');

  // Local streams state
  const [localStreamsInitialized, setLocalStreamsInitialized] = useState(false);
  const [isPublished, setIsPublished] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [isCameraMutedState, setIsCameraMuted] = useState(false);
  const [isPlaceholderActive, setIsPlaceholderActive] = useState(false);
  const [mirrorView, setMirrorView] = useState(false);

  // Participant selection (for PiP)
  const [selectedParticipantId, setSelectedParticipantId] = useState<string | null>(null);

  // PiP state
  const [isPiPSupportedState, setIsPiPSupported] = useState(false);
  const [isPiPEnabled, setIsPiPEnabled] = useState(false);
  const [isPiPActive, setIsPiPActive] = useState(false);
  const [pipState, setPipState] = useState<PiPState>('none');
  const [pipError, setPipError] = useState<string | null>(null);
  const [isInPiPMode, setIsInPiPMode] = useState(false);
  const [isPiPAutoStarted, setIsPiPAutoStarted] = useState(false);

  // Permissions
  const [permissionStatus, setPermissionStatus] = useState<PermissionStatusMap | null>(null);

  // Errors
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastSwapResult, setLastSwapResult] = useState<string | null>(null);

  // Use the participants hook
  const { participants } = useStageParticipants();

  // Track if we've initialized
  const isInitializedRef = useRef(false);

  // Initialize stage and check PiP support on mount
  useEffect(() => {
    if (isInitializedRef.current) return;
    isInitializedRef.current = true;

    const initialize = async () => {
      try {
        await initializeStage();
        console.log('[StreamContext] Stage initialized');

        const supported = await isPictureInPictureSupported();
        setIsPiPSupported(supported);
        console.log('[StreamContext] PiP supported:', supported);
      } catch (e) {
        console.error('[StreamContext] Initialize error:', e);
      }
    };

    initialize();
  }, []);

  // Set up event listeners
  useEffect(() => {
    const connectionSub = addOnStageConnectionStateChangedListener((data) => {
      console.log('[StreamContext] Connection state:', data.state);
      setConnectionState(data.state as ConnectionState);
      if (data.state === 'disconnected') {
        setIsPublished(false);
        setLocalStreamsInitialized(false);
      }
    });

    const publishSub = addOnPublishStateChangedListener((data) => {
      console.log('[StreamContext] Publish state:', data.state);
      setPublishState(data.state as PublishState);
      setIsPublished(data.state === 'published');
    });

    const errorSub = addOnStageErrorListener((data) => {
      console.error('[StreamContext] Stage error:', data);
      setLastError(data.description);
    });

    const cameraSwapSub = addOnCameraSwappedListener((data) => {
      console.log('[StreamContext] Camera swapped:', data);
      setLastSwapResult(`Success: ${data.newCameraName}`);
    });

    const cameraSwapErrorSub = addOnCameraSwapErrorListener((data) => {
      console.error('[StreamContext] Camera swap error:', data);
      setLastSwapResult(`Error: ${data.reason}`);
    });

    const cameraMuteSub = addOnCameraMuteStateChangedListener((data) => {
      console.log('[StreamContext] Camera mute state:', data);
      setIsCameraMuted(data.muted);
      setIsPlaceholderActive(data.placeholderActive);
    });

    const pipStateSub = addOnPiPStateChangedListener((data) => {
      console.log('[StreamContext] PiP state:', data.state);
      setPipState(data.state as PiPState);
      setIsPiPActive(data.state === 'started');

      if (Platform.OS === 'android') {
        if (data.state === 'started') {
          setIsInPiPMode(true);
        } else if (data.state === 'stopped' || data.state === 'restored') {
          setIsInPiPMode(false);
        }
      }
    });

    const pipErrorSub = addOnPiPErrorListener((data) => {
      console.error('[StreamContext] PiP error:', data);
      setPipError(data.error);
    });

    return () => {
      connectionSub.remove();
      publishSub.remove();
      errorSub.remove();
      cameraSwapSub.remove();
      cameraSwapErrorSub.remove();
      cameraMuteSub.remove();
      pipStateSub.remove();
      pipErrorSub.remove();
    };
  }, []);

  // Auto-select first participant when participants change (for viewer)
  useEffect(() => {
    if (role === 'viewer' && participants.length > 0 && !selectedParticipantId) {
      const firstWithVideo = participants.find((p) =>
        p.streams.some((s) => s.mediaType === 'video')
      );
      if (firstWithVideo) {
        setSelectedParticipantId(firstWithVideo.id);
      }
    }
  }, [role, participants, selectedParticipantId]);

  // Initialize local camera (publisher only)
  const initializeLocalCamera = useCallback(async () => {
    if (Platform.OS === 'android') {
      try {
        const granted = await PermissionsAndroid.requestMultiple([
          PermissionsAndroid.PERMISSIONS.CAMERA,
          PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        ]);
        if (
          granted[PermissionsAndroid.PERMISSIONS.CAMERA] !== 'granted' ||
          granted[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] !== 'granted'
        ) {
          setLastError('Permissions required to go live.');
          return;
        }
      } catch (err) {
        console.warn('[StreamContext] Permission error:', err);
        return;
      }
    }

    try {
      await initializeLocalStreams();
      console.log('[StreamContext] Local streams initialized');
      setLocalStreamsInitialized(true);

      const status = await requestPermissions();
      setPermissionStatus(status);
    } catch (e) {
      console.error('[StreamContext] Initialize local streams error:', e);
      setLastError('Failed to initialize camera');
    }
  }, []);

  // Join stage
  const handleJoinStage = useCallback(async () => {
    if (!token) {
      setLastError('Please enter a token!');
      return;
    }
    try {
      await joinStage(token);
      console.log('[StreamContext] Joining stage...');
    } catch (e) {
      console.error('[StreamContext] Join stage error:', e);
      setLastError('Failed to join stage');
    }
  }, [token]);

  // Leave stage
  const handleLeaveStage = useCallback(async () => {
    try {
      // Disable PiP first
      if (isPiPEnabled) {
        await disablePictureInPicture();
        setIsPiPEnabled(false);
        setIsPiPActive(false);
        setPipState('none');
      }

      await leaveStage();
      console.log('[StreamContext] Left stage');
      setSelectedParticipantId(null);
    } catch (e) {
      console.error('[StreamContext] Leave stage error:', e);
    }
  }, [isPiPEnabled]);

  // Toggle publish
  const handleTogglePublish = useCallback(async () => {
    try {
      await setStreamsPublished(!isPublished);
    } catch (e) {
      console.error('[StreamContext] Toggle publish error:', e);
    }
  }, [isPublished]);

  // Swap camera
  const handleSwapCamera = useCallback(async () => {
    try {
      await swapCamera();
    } catch (e) {
      console.error('[StreamContext] Swap camera error:', e);
    }
  }, []);

  // Toggle mute
  const handleToggleMute = useCallback(async () => {
    try {
      await setMicrophoneMuted(!isMuted);
      setIsMuted(!isMuted);
    } catch (e) {
      console.error('[StreamContext] Toggle mute error:', e);
    }
  }, [isMuted]);

  // Set camera muted (for publisher away mode)
  const handleSetCameraMuted = useCallback(async (muted: boolean, placeholderText?: string) => {
    try {
      await setCameraMuted(muted, placeholderText);
      console.log('[StreamContext] Camera muted:', muted, placeholderText ? `(${placeholderText})` : '');
    } catch (e) {
      console.error('[StreamContext] Set camera muted error:', e);
    }
  }, []);

  // Enable PiP
  const handleEnablePiP = useCallback(async () => {
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
      console.log('[StreamContext] PiP enabled:', success);
    } catch (e) {
      console.error('[StreamContext] Enable PiP error:', e);
      setPipError('Failed to enable PiP');
    }
  }, [role]);

  // Disable PiP
  const handleDisablePiP = useCallback(async () => {
    try {
      await disablePictureInPicture();
      setIsPiPEnabled(false);
      setIsPiPActive(false);
      setPipState('none');
      console.log('[StreamContext] PiP disabled');
    } catch (e) {
      console.error('[StreamContext] Disable PiP error:', e);
    }
  }, []);

  // Start PiP
  const handleStartPiP = useCallback(async (isAutoStart: boolean = false) => {
    try {
      setPipError(null);
      setIsPiPAutoStarted(isAutoStart);
      await startPictureInPicture();
      console.log('[StreamContext] PiP start requested (auto:', isAutoStart, ')');
    } catch (e) {
      console.error('[StreamContext] Start PiP error:', e);
      setIsPiPAutoStarted(false);
    }
  }, []);

  // Stop PiP
  const handleStopPiP = useCallback(async () => {
    try {
      await stopPictureInPicture();
      setIsPiPAutoStarted(false);
      console.log('[StreamContext] PiP stop requested');
    } catch (e) {
      console.error('[StreamContext] Stop PiP error:', e);
    }
  }, []);

  // Clear the auto-start flag (used when returning to stream screen)
  const clearPiPAutoStartFlag = useCallback(() => {
    setIsPiPAutoStarted(false);
  }, []);

  // Full cleanup function for navigation/unmount
  const cleanupStream = useCallback(async () => {
    try {
      console.log('[StreamContext] Cleaning up stream...');
      
      // Always try to disable PiP first
      await disablePictureInPicture().catch(() => {});
      setIsPiPEnabled(false);
      setIsPiPActive(false);
      setPipState('none');

      // Leave stage if connected
      if (connectionState === 'connected') {
        await leaveStage().catch(() => {});
      }

      // Reset state
      setLocalStreamsInitialized(false);
      setIsPublished(false);
      setSelectedParticipantId(null);
      
      console.log('[StreamContext] Cleanup complete');
    } catch (e) {
      console.error('[StreamContext] Cleanup error:', e);
    }
  }, [connectionState]);

  const value: StreamContextType = {
    // Role
    role,
    setRole,

    // Connection
    isConnected: connectionState === 'connected',
    connectionState,
    publishState,

    // Token
    token,
    setToken,

    // Local streams
    localStreamsInitialized,
    isPublished,
    isMuted,
    isCameraMuted: isCameraMutedState,
    isPlaceholderActive,
    mirrorView,
    setMirrorView,

    // Participants
    participants,
    selectedParticipantId,
    setSelectedParticipantId,

    // PiP
    isPiPSupported: isPiPSupportedState,
    isPiPEnabled,
    isPiPActive,
    pipState,
    pipError,
    isInPiPMode,
    isPiPAutoStarted,

    // Permissions
    permissionStatus,

    // Errors
    lastError,
    lastSwapResult,

    // Actions
    initializeLocalCamera,
    handleJoinStage,
    handleLeaveStage,
    handleTogglePublish,
    handleSwapCamera,
    handleToggleMute,
    handleSetCameraMuted,
    handleEnablePiP,
    handleDisablePiP,
    handleStartPiP,
    handleStopPiP,
    clearPiPAutoStartFlag,
    cleanupStream,
  };

  return <StreamContext.Provider value={value}>{children}</StreamContext.Provider>;
}
