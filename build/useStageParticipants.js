"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.useStageParticipants = void 0;
const react_1 = require("react");
const index_1 = require("./index");
const useStageParticipants = () => {
    const [participants, setParticipants] = (0, react_1.useState)([]);
    (0, react_1.useEffect)(() => {
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
            (0, index_1.addOnParticipantJoinedListener)(onParticipantJoined),
            (0, index_1.addOnParticipantLeftListener)(onParticipantLeft),
            (0, index_1.addOnParticipantStreamsAddedListener)(onParticipantStreamsAdded),
            (0, index_1.addOnParticipantStreamsRemovedListener)(onParticipantStreamsRemoved),
        ];
        return () => {
            subscriptions.forEach((sub) => sub.remove());
        };
    }, []);
    return { participants };
};
exports.useStageParticipants = useStageParticipants;
//# sourceMappingURL=useStageParticipants.js.map