import { useCallback } from 'react';
import { View, StyleSheet } from 'react-native';
import { Stack, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { StreamProvider, useStream } from '../src/contexts/StreamContext';
import { FloatingPlayerProvider, useFloatingPlayer } from '../src/contexts/FloatingPlayerContext';
import { useGlobalPiPRestore } from '../src/hooks/usePiPNavigation';
import { FloatingStreamContainer } from '../src/components/FloatingStreamContainer';
import { LiveIndicator } from '../src/components/LiveIndicator';

// Inner component that handles global PiP restore navigation
function GlobalPiPHandler({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const segments = useSegments();
  const { role } = useStream();
  const { expand } = useFloatingPlayer();

  const navigateToStream = useCallback(() => {
    // Check what screen we're currently on
    const currentPath = '/' + segments.join('/');

    let targetPath: string;
    if (role === 'publisher') {
      targetPath = '/publisher/broadcast';
    } else {
      targetPath = '/viewer/stream';
    }

    console.log('[GlobalPiPHandler] PiP restore - current:', currentPath, 'target:', targetPath);

    // If we're already on the target screen, just expand
    if (currentPath === targetPath) {
      console.log('[GlobalPiPHandler] Already on stream screen, expanding');
      expand();
      return;
    }

    // If we're on a secondary screen, go back and expand
    const secondaryScreens = ['/viewer/browse', '/viewer/activity', '/publisher/settings'];
    if (secondaryScreens.includes(currentPath)) {
      console.log('[GlobalPiPHandler] On secondary screen, going back');
      router.back();
      expand();
      return;
    }

    // Otherwise (e.g., on home), navigate to stream
    console.log('[GlobalPiPHandler] Navigating to stream');
    router.navigate(targetPath);
    expand();
  }, [role, router, segments, expand]);

  // This hook listens for system PiP restore events and navigates globally
  useGlobalPiPRestore(navigateToStream);

  return (
    <View style={styles.container}>
      {children}
      <LiveIndicator />
      <FloatingStreamContainer />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={styles.container}>
      <StreamProvider>
        <FloatingPlayerProvider>
          <GlobalPiPHandler>
            <StatusBar style="dark" />
            <Stack
              screenOptions={{
                headerStyle: {
                  backgroundColor: '#f5f5f5',
                },
                headerTintColor: '#333',
                headerTitleStyle: {
                  fontWeight: '600',
                },
                contentStyle: {
                  backgroundColor: '#ffffff',
                },
              }}
            >
              <Stack.Screen
                name="index"
                options={{
                  title: 'IVS Broadcast Demo',
                  headerShown: true,
                }}
              />
              <Stack.Screen
                name="viewer/stream"
                options={{
                  title: 'Watch Stream',
                  headerBackTitle: 'Back',
                }}
              />
              <Stack.Screen
                name="viewer/browse"
                options={{
                  title: 'Browse',
                  headerBackTitle: 'Stream',
                }}
              />
              <Stack.Screen
                name="viewer/activity"
                options={{
                  title: 'Activity',
                  headerBackTitle: 'Back',
                }}
              />
              <Stack.Screen
                name="publisher/broadcast"
                options={{
                  title: 'Broadcast',
                  headerBackTitle: 'Back',
                }}
              />
              <Stack.Screen
                name="publisher/settings"
                options={{
                  title: 'Settings',
                  headerBackTitle: 'Broadcast',
                }}
              />
            </Stack>
          </GlobalPiPHandler>
        </FloatingPlayerProvider>
      </StreamProvider>
    </GestureHandlerRootView>
  );
}
