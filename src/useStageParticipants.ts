import { useState, useEffect } from 'react';
import {
  addOnParticipantJoinedListener,
  addOnParticipantLeftListener,
  addOnParticipantStreamsAddedListener,
  addOnParticipantStreamsRemovedListener,
} from './index';
import type {
  Participant,
  ParticipantPayload,
  ParticipantStreamsPayload,
  ParticipantStreamsRemovedPayload,
} from './ExpoRealtimeIvsBroadcast.types';

export const useStageParticipants = () => {
  const [participants, setParticipants] = useState<Participant[]>([]);

  useEffect(() => {
    const onParticipantJoined = (p: ParticipantPayload) => {
      setParticipants((prev) => [
        ...prev,
        { id: p.participantId, streams: [] },
      ]);
    };

    const onParticipantLeft = (p: ParticipantPayload) => {
      setParticipants((prev) => prev.filter((participant) => participant.id !== p.participantId));
    };

    const onParticipantStreamsAdded = (p: ParticipantStreamsPayload) => {
      setParticipants((prev) =>
        prev.map((participant) => {
          if (participant.id === p.participantId) {
            // Avoid adding duplicate streams
            const existingUrns = new Set(participant.streams.map(s => s.deviceUrn));
            const newStreams = p.streams.filter(s => !existingUrns.has(s.deviceUrn));
            return {
              ...participant,
              streams: [...participant.streams, ...newStreams],
            };
          }
          return participant;
        })
      );
    };

    const onParticipantStreamsRemoved = (p: ParticipantStreamsRemovedPayload) => {
      const removedUrns = new Set(p.streams.map((s) => s.deviceUrn));
      setParticipants((prev) =>
        prev.map((participant) => {
          if (participant.id === p.participantId) {
            return {
              ...participant,
              streams: participant.streams.filter(
                (stream) => !removedUrns.has(stream.deviceUrn)
              ),
            };
          }
          return participant;
        })
      );
    };

    const subscriptions = [
      addOnParticipantJoinedListener(onParticipantJoined),
      addOnParticipantLeftListener(onParticipantLeft),
      addOnParticipantStreamsAddedListener(onParticipantStreamsAdded),
      addOnParticipantStreamsRemovedListener(onParticipantStreamsRemoved),
    ];

    return () => {
      subscriptions.forEach((sub) => sub.remove());
    };
  }, []);

  return { participants };
}; 