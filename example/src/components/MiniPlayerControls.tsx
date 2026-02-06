import React from 'react';
import { StyleSheet, View, TouchableOpacity, Text } from 'react-native';

interface MiniPlayerControlsProps {
  onExpand: () => void;
  onDismiss: () => void;
}

/**
 * Overlay controls shown on top of the mini player.
 * - Close (X) button to dismiss the mini player
 * - Expand button to return to full stream screen
 */
export function MiniPlayerControls({ onExpand, onDismiss }: MiniPlayerControlsProps) {
  return (
    <View style={styles.overlay} pointerEvents="box-none">
      {/* Top-right close button */}
      <TouchableOpacity
        style={styles.closeButton}
        onPress={onDismiss}
        hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
        activeOpacity={0.7}
      >
        <Text style={styles.closeIcon}>X</Text>
      </TouchableOpacity>

      {/* Bottom expand bar */}
      <TouchableOpacity
        style={styles.expandButton}
        onPress={onExpand}
        activeOpacity={0.7}
      >
        <Text style={styles.expandIcon}>^</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    padding: 6,
  },
  closeButton: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeIcon: {
    color: '#fff',
    fontSize: 11,
    fontWeight: 'bold',
  },
  expandButton: {
    width: '100%',
    height: 28,
    borderRadius: 8,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    alignSelf: 'center',
  },
  expandIcon: {
    color: '#fff',
    fontSize: 14,
    fontWeight: 'bold',
  },
});
