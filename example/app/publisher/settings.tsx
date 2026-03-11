import React from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Switch,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useStream } from '../../src/contexts/StreamContext';
import { useFloatingPlayer } from '../../src/contexts/FloatingPlayerContext';

// Sample settings data
const SETTINGS_SECTIONS = [
  {
    title: 'Broadcast Settings',
    items: [
      { id: 'quality', label: 'Video Quality', value: 'High (1080p)', type: 'select' },
      { id: 'bitrate', label: 'Bitrate', value: '4.5 Mbps', type: 'select' },
      { id: 'framerate', label: 'Frame Rate', value: '30 fps', type: 'select' },
    ],
  },
  {
    title: 'Preferences',
    items: [
      { id: 'notifications', label: 'Notifications', value: true, type: 'toggle' },
      { id: 'auto_record', label: 'Auto-record streams', value: false, type: 'toggle' },
      { id: 'low_latency', label: 'Low latency mode', value: true, type: 'toggle' },
    ],
  },
];

export default function SettingsScreen() {
  const router = useRouter();
  const { isConnected, isPublished, isCameraMuted } = useStream();
  const { isMini, expand } = useFloatingPlayer();

  const handleBackToBroadcast = () => {
    router.back();
    expand();
  };

  const handleToggleSetting = (settingId: string) => {
    console.log('Toggle setting:', settingId);
  };

  const handleSelectSetting = (settingId: string) => {
    console.log('Select setting:', settingId);
  };

  return (
    <View style={styles.container}>
      {/* Mini player indicator */}
      {isConnected && isPublished && isMini && (
        <View style={styles.pipIndicator}>
          <View style={[styles.pipDot, styles.pipDotActive]} />
          <Text style={styles.pipIndicatorText}>
            {isCameraMuted
              ? 'LIVE - Preview in mini player'
              : 'LIVE - Broadcasting'}
          </Text>
          <TouchableOpacity onPress={handleBackToBroadcast}>
            <Text style={styles.returnLink}>Return to broadcast</Text>
          </TouchableOpacity>
        </View>
      )}

      <ScrollView contentContainerStyle={styles.scrollContent}>
        <Text style={styles.headerText}>
          Manage settings while your broadcast continues!
        </Text>

        {SETTINGS_SECTIONS.map(section => (
          <View key={section.title} style={styles.settingsSection}>
            <Text style={styles.sectionTitle}>{section.title}</Text>
            {section.items.map(item => (
              <View key={item.id} style={styles.settingItem}>
                <Text style={styles.settingLabel}>{item.label}</Text>
                {item.type === 'toggle' ? (
                  <Switch
                    value={item.value as boolean}
                    onValueChange={() => handleToggleSetting(item.id)}
                    trackColor={{ false: '#e0e0e0', true: '#81b0ff' }}
                    thumbColor={item.value ? '#4A90D9' : '#f4f3f4'}
                  />
                ) : (
                  <TouchableOpacity
                    style={styles.selectButton}
                    onPress={() => handleSelectSetting(item.id)}
                  >
                    <Text style={styles.selectValue}>{item.value as string}</Text>
                    <Text style={styles.selectArrow}>{'>'}</Text>
                  </TouchableOpacity>
                )}
              </View>
            ))}
          </View>
        ))}

        {/* Status Info */}
        <View style={styles.statusSection}>
          <Text style={styles.statusTitle}>Broadcast Status</Text>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Connection:</Text>
            <Text style={[styles.statusValue, isConnected && styles.statusConnected]}>
              {isConnected ? 'Connected' : 'Disconnected'}
            </Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Publishing:</Text>
            <Text style={[styles.statusValue, isPublished && styles.statusLive]}>
              {isPublished ? 'LIVE' : 'Not live'}
            </Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Camera:</Text>
            <Text style={[styles.statusValue, !isCameraMuted && styles.statusConnected]}>
              {isCameraMuted ? 'Muted (placeholder)' : 'Active'}
            </Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  pipIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff3cd',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#ffc107',
  },
  pipDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#ccc',
    marginRight: 8,
  },
  pipDotActive: {
    backgroundColor: '#dc3545',
  },
  pipIndicatorText: {
    fontSize: 12,
    color: '#555',
    flex: 1,
  },
  returnLink: {
    fontSize: 12,
    color: '#D9534F',
    fontWeight: '600',
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 40,
  },
  headerText: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    marginBottom: 20,
    fontStyle: 'italic',
  },
  settingsSection: {
    backgroundColor: '#fff',
    borderRadius: 12,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
    overflow: 'hidden',
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 8,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  settingItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderTopWidth: 1,
    borderTopColor: '#f0f0f0',
  },
  settingLabel: {
    fontSize: 15,
    color: '#333',
  },
  selectButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  selectValue: {
    fontSize: 14,
    color: '#888',
    marginRight: 4,
  },
  selectArrow: {
    fontSize: 18,
    color: '#ccc',
  },
  statusSection: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
  statusTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  statusLabel: {
    fontSize: 14,
    color: '#666',
  },
  statusValue: {
    fontSize: 14,
    fontWeight: '600',
    color: '#999',
  },
  statusConnected: {
    color: '#4CAF50',
  },
  statusLive: {
    color: '#dc3545',
  },
});
