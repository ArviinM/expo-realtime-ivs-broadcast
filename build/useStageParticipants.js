import { useState, useEffect } from 'react';
import { addOnParticipantJoinedListener, addOnParticipantLeftListener, addOnParticipantStreamsAddedListener, addOnParticipantStreamsRemovedListener, } from './index';
export const useStageParticipants = () => {
    const [participants, setParticipants] = useState([]);
    useEffect(() => {
        const onParticipantJoined = (p) => {
            setParticipants((prev) => [
                ...prev,
                { id: p.participantId, streams: [] },
            ]);
        };
        const onParticipantLeft = (p) => {
            setParticipants((prev) => prev.filter((participant) => participant.id !== p.participantId));
        };
        const onParticipantStreamsAdded = (p) => {
            setParticipants((prev) => prev.map((participant) => {
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
            }));
        };
        const onParticipantStreamsRemoved = (p) => {
            const removedUrns = new Set(p.streams.map((s) => s.deviceUrn));
            setParticipants((prev) => prev.map((participant) => {
                if (participant.id === p.participantId) {
                    return {
                        ...participant,
                        streams: participant.streams.filter((stream) => !removedUrns.has(stream.deviceUrn)),
                    };
                }
                return participant;
            }));
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
//# sourceMappingURL=useStageParticipants.js.map