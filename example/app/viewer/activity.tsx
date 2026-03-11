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

// Sample activity data
const ACTIVITIES = [
  {
    id: '1',
    title: 'Activity One',
    timestamp: '2 min ago',
    status: 'completed',
    icon: 'Done',
  },
  {
    id: '2',
    title: 'Activity Two',
    timestamp: '5 min ago',
    status: 'in_progress',
    icon: 'Sync',
  },
  {
    id: '3',
    title: 'Activity Three',
    timestamp: '10 min ago',
    status: 'pending',
    icon: 'Wait',
  },
  {
    id: '4',
    title: 'Activity Four',
    timestamp: '15 min ago',
    status: 'completed',
    icon: 'Done',
  },
];

const getStatusColor = (status: string) => {
  switch (status) {
    case 'completed':
      return '#4CAF50';
    case 'in_progress':
      return '#2196F3';
    case 'pending':
      return '#FF9800';
    default:
      return '#666';
  }
};

export default function ActivityScreen() {
  const router = useRouter();
  const { isConnected } = useStream();
  const { isMini, expand } = useFloatingPlayer();

  const handleBackToStream = () => {
    router.back();
    expand();
  };

  const handleViewDetails = (activityId: string) => {
    console.log('View activity details:', activityId);
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
          Check your activity while watching the live stream!
        </Text>

        {ACTIVITIES.length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>No activity yet</Text>
            <Text style={styles.emptySubtext}>
              Your activity will appear here
            </Text>
          </View>
        ) : (
          <View style={styles.activityList}>
            {ACTIVITIES.map(activity => (
              <View key={activity.id} style={styles.activityCard}>
                <View style={styles.activityHeader}>
                  <View style={styles.activityIconContainer}>
                    <Text style={styles.activityIcon}>{activity.icon}</Text>
                  </View>
                  <View style={styles.activityInfo}>
                    <Text style={styles.activityTitle}>{activity.title}</Text>
                    <Text style={styles.activityTimestamp}>{activity.timestamp}</Text>
                  </View>
                  <View style={[styles.statusBadge, { backgroundColor: getStatusColor(activity.status) + '20' }]}>
                    <Text style={[styles.statusText, { color: getStatusColor(activity.status) }]}>
                      {activity.status.replace('_', ' ')}
                    </Text>
                  </View>
                </View>

                <TouchableOpacity
                  style={styles.detailsButton}
                  onPress={() => handleViewDetails(activity.id)}
                >
                  <Text style={styles.detailsButtonText}>View Details</Text>
                </TouchableOpacity>
              </View>
            ))}
          </View>
        )}
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
  emptyState: {
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 8,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
  activityList: {
    gap: 16,
  },
  activityCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
  activityHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  activityIconContainer: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#f5f5f5',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  activityIcon: {
    fontSize: 11,
    fontWeight: '700',
    color: '#4A90D9',
  },
  activityInfo: {
    flex: 1,
  },
  activityTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  activityTimestamp: {
    fontSize: 12,
    color: '#666',
    marginTop: 2,
  },
  statusBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusText: {
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  detailsButton: {
    backgroundColor: '#f0f0f0',
    paddingVertical: 10,
    borderRadius: 6,
    alignItems: 'center',
  },
  detailsButtonText: {
    color: '#333',
    fontSize: 13,
    fontWeight: '600',
  },
});
