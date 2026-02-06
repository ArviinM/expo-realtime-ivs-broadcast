import React, {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
  ReactNode,
} from 'react';
import { AppState, AppStateStatus } from 'react-native';
import { useStream } from './StreamContext';

// --- Types ---

export type PlayerState = 'IDLE' | 'EXPANDED' | 'MINI';

export interface StreamInfo {
  participantId: string | null;
  deviceUrn: string | null;
}

interface FloatingPlayerContextType {
  // State
  playerState: PlayerState;
  streamInfo: StreamInfo;

  // Actions
  expand: () => void;
  minimize: () => void;
  dismiss: () => void;
  activate: (info?: StreamInfo) => void;
  setStreamInfo: (info: StreamInfo) => void;

  // Derived helpers
  isActive: boolean;
  isExpanded: boolean;
  isMini: boolean;
}

const FloatingPlayerContext = createContext<FloatingPlayerContextType | null>(null);

export function useFloatingPlayer() {
  const context = useContext(FloatingPlayerContext);
  if (!context) {
    throw new Error('useFloatingPlayer must be used within a FloatingPlayerProvider');
  }
  return context;
}

// --- Provider ---

interface FloatingPlayerProviderProps {
  children: ReactNode;
}

export function FloatingPlayerProvider({ children }: FloatingPlayerProviderProps) {
  const { isConnected } = useStream();

  const [playerState, setPlayerState] = useState<PlayerState>('IDLE');
  const [streamInfo, setStreamInfoState] = useState<StreamInfo>({
    participantId: null,
    deviceUrn: null,
  });

  // Track the state before app went to background (for restoring)
  const stateBeforeBackgroundRef = useRef<PlayerState>('IDLE');
  const prevAppStateRef = useRef<AppStateStatus>(AppState.currentState);

  // --- AppState listener for system PiP coordination ---
  useEffect(() => {
    const handleAppStateChange = (nextAppState: AppStateStatus) => {
      const prev = prevAppStateRef.current;

      if (
        (prev === 'active') &&
        (nextAppState === 'inactive' || nextAppState === 'background')
      ) {
        // App going to background -- save current state
        setPlayerState((current) => {
          if (current !== 'IDLE') {
            stateBeforeBackgroundRef.current = current;
            console.log('[FloatingPlayer] App backgrounded, saved state:', current);
          }
          return current;
        });
      } else if (
        (prev === 'inactive' || prev === 'background') &&
        nextAppState === 'active'
      ) {
        // App returning to foreground -- restore state
        setPlayerState((current) => {
          if (current !== 'IDLE') {
            const restored = stateBeforeBackgroundRef.current;
            console.log('[FloatingPlayer] App foregrounded, restoring state:', restored);
            return restored;
          }
          return current;
        });
      }

      prevAppStateRef.current = nextAppState;
    };

    const subscription = AppState.addEventListener('change', handleAppStateChange);
    return () => subscription.remove();
  }, []); // No dependencies -- uses functional setState to read current state

  // --- Auto-dismiss when disconnected ---
  useEffect(() => {
    if (!isConnected) {
      setPlayerState((current) => {
        if (current !== 'IDLE') {
          console.log('[FloatingPlayer] Disconnected, dismissing player');
          return 'IDLE';
        }
        return current;
      });
      setStreamInfoState({ participantId: null, deviceUrn: null });
    }
  }, [isConnected]); // Only react to connection changes, not playerState

  // --- Actions (all use functional setState to avoid stale closures) ---

  const activate = useCallback((info?: StreamInfo) => {
    if (info) {
      setStreamInfoState(info);
    }
    setPlayerState('EXPANDED');
    console.log('[FloatingPlayer] Activated (EXPANDED)');
  }, []);

  const expand = useCallback(() => {
    setPlayerState((current) => {
      if (current !== 'IDLE') {
        console.log('[FloatingPlayer] Expanded');
        return 'EXPANDED';
      }
      return current;
    });
  }, []); // No dependency on playerState -- reads current via functional update

  const minimize = useCallback(() => {
    setPlayerState((current) => {
      if (current !== 'IDLE') {
        console.log('[FloatingPlayer] Minimized');
        return 'MINI';
      }
      return current;
    });
  }, []); // No dependency on playerState -- reads current via functional update

  const dismiss = useCallback(() => {
    setPlayerState('IDLE');
    setStreamInfoState({ participantId: null, deviceUrn: null });
    console.log('[FloatingPlayer] Dismissed');
  }, []);

  const setStreamInfo = useCallback((info: StreamInfo) => {
    setStreamInfoState(info);
  }, []);

  // --- Derived ---

  const value: FloatingPlayerContextType = {
    playerState,
    streamInfo,
    activate,
    expand,
    minimize,
    dismiss,
    setStreamInfo,
    isActive: playerState !== 'IDLE',
    isExpanded: playerState === 'EXPANDED',
    isMini: playerState === 'MINI',
  };

  return (
    <FloatingPlayerContext.Provider value={value}>
      {children}
    </FloatingPlayerContext.Provider>
  );
}
