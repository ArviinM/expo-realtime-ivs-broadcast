import React from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useStream } from '../../src/contexts/StreamContext';
import { useFloatingPlayer } from '../../src/contexts/FloatingPlayerContext';

// Sample content items
const ITEMS = [
  { id: '1', title: 'Item One', description: 'Description for item one', icon: 'A' },
  { id: '2', title: 'Item Two', description: 'Description for item two', icon: 'B' },
  { id: '3', title: 'Item Three', description: 'Description for item three', icon: 'C' },
  { id: '4', title: 'Item Four', description: 'Description for item four', icon: 'D' },
  { id: '5', title: 'Item Five', description: 'Description for item five', icon: 'E' },
  { id: '6', title: 'Item Six', description: 'Description for item six', icon: 'F' },
];

export default function BrowseScreen() {
  const router = useRouter();
  const { isConnected } = useStream();
  const { isMini, expand } = useFloatingPlayer();

  const handleBackToStream = () => {
    router.back();
    expand();
  };

  const handleItemPress = (itemId: string) => {
    console.log('Item pressed:', itemId);
  };

  return (
    <View style={styles.container}>
      {/* Mini player indicator */}
      {isConnected && isMini && (
        <View style={styles.pipIndicator}>
          <View style={[styles.pipDot, styles.pipDotActive]} />
          <Text style={styles.pipIndicatorText}>
            Stream playing in mini player
          </Text>
          <TouchableOpacity onPress={handleBackToStream}>
            <Text style={styles.returnLink}>Return to stream</Text>
          </TouchableOpacity>
        </View>
      )}

      <ScrollView contentContainerStyle={styles.scrollContent}>
        <Text style={styles.headerText}>
          Browse content while watching the live stream!
        </Text>

        <View style={styles.itemsGrid}>
          {ITEMS.map(item => (
            <TouchableOpacity
              key={item.id}
              style={styles.itemCard}
              onPress={() => handleItemPress(item.id)}
            >
              <View style={styles.itemIconContainer}>
                <Text style={styles.itemIcon}>{item.icon}</Text>
              </View>
              <View style={styles.itemInfo}>
                <Text style={styles.itemTitle}>{item.title}</Text>
                <Text style={styles.itemDescription} numberOfLines={2}>
                  {item.description}
                </Text>
                <TouchableOpacity style={styles.actionButton}>
                  <Text style={styles.actionButtonText}>View Details</Text>
                </TouchableOpacity>
              </View>
            </TouchableOpacity>
          ))}
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
    backgroundColor: '#e8f4f8',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#d0e3f0',
  },
  pipDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#ccc',
    marginRight: 8,
  },
  pipDotActive: {
    backgroundColor: '#4CAF50',
  },
  pipIndicatorText: {
    fontSize: 12,
    color: '#555',
    flex: 1,
  },
  returnLink: {
    fontSize: 12,
    color: '#4A90D9',
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
  itemsGrid: {
    gap: 16,
  },
  itemCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
    flexDirection: 'row',
  },
  itemIconContainer: {
    width: 80,
    backgroundColor: '#f5f5f5',
    justifyContent: 'center',
    alignItems: 'center',
  },
  itemIcon: {
    fontSize: 32,
    fontWeight: '700',
    color: '#4A90D9',
  },
  itemInfo: {
    flex: 1,
    padding: 16,
  },
  itemTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  itemDescription: {
    fontSize: 13,
    color: '#666',
    marginBottom: 12,
    lineHeight: 18,
  },
  actionButton: {
    backgroundColor: '#4A90D9',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 6,
    alignSelf: 'flex-start',
  },
  actionButtonText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
});
