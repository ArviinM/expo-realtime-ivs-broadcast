"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.useStageParticipants = exports.ExpoIVSRemoteStreamView = exports.ExpoIVSStagePreviewView = void 0;
exports.initializeStage = initializeStage;
exports.initializeLocalStreams = initializeLocalStreams;
exports.joinStage = joinStage;
exports.leaveStage = leaveStage;
exports.setStreamsPublished = setStreamsPublished;
exports.swapCamera = swapCamera;
exports.setMicrophoneMuted = setMicrophoneMuted;
exports.requestPermissions = requestPermissions;
exports.addOnStageConnectionStateChangedListener = addOnStageConnectionStateChangedListener;
exports.addOnPublishStateChangedListener = addOnPublishStateChangedListener;
exports.addOnStageErrorListener = addOnStageErrorListener;
exports.addOnCameraSwappedListener = addOnCameraSwappedListener;
exports.addOnCameraSwapErrorListener = addOnCameraSwapErrorListener;
exports.addOnParticipantJoinedListener = addOnParticipantJoinedListener;
exports.addOnParticipantLeftListener = addOnParticipantLeftListener;
exports.addOnParticipantStreamsAddedListener = addOnParticipantStreamsAddedListener;
exports.addOnParticipantStreamsRemovedListener = addOnParticipantStreamsRemovedListener;
const ExpoRealtimeIvsBroadcastModule_1 = __importDefault(require("./ExpoRealtimeIvsBroadcastModule"));
// Re-export all type definitions
__exportStar(require("./ExpoRealtimeIvsBroadcast.types"), exports);
// Export the native view components
var ExpoIVSStagePreviewView_1 = require("./ExpoIVSStagePreviewView");
Object.defineProperty(exports, "ExpoIVSStagePreviewView", { enumerable: true, get: function () { return ExpoIVSStagePreviewView_1.ExpoIVSStagePreviewView; } });
var ExpoIVSRemoteStreamView_1 = require("./ExpoIVSRemoteStreamView");
Object.defineProperty(exports, "ExpoIVSRemoteStreamView", { enumerable: true, get: function () { return ExpoIVSRemoteStreamView_1.ExpoIVSRemoteStreamView; } });
// Export the custom hook
var useStageParticipants_1 = require("./useStageParticipants");
Object.defineProperty(exports, "useStageParticipants", { enumerable: true, get: function () { return useStageParticipants_1.useStageParticipants; } });
// --- Native Module Methods ---
async function initializeStage(audioConfig, videoConfig) {
    return await ExpoRealtimeIvsBroadcastModule_1.default.initializeStage(audioConfig, videoConfig);
}
async function initializeLocalStreams(audioConfig, videoConfig) {
    return await ExpoRealtimeIvsBroadcastModule_1.default.initializeLocalStreams(audioConfig, videoConfig);
}
async function joinStage(token, options) {
    return await ExpoRealtimeIvsBroadcastModule_1.default.joinStage(token, options);
}
async function leaveStage() {
    return await ExpoRealtimeIvsBroadcastModule_1.default.leaveStage();
}
async function setStreamsPublished(published) {
    return await ExpoRealtimeIvsBroadcastModule_1.default.setStreamsPublished(published);
}
async function swapCamera() {
    return await ExpoRealtimeIvsBroadcastModule_1.default.swapCamera();
}
async function setMicrophoneMuted(muted) {
    return await ExpoRealtimeIvsBroadcastModule_1.default.setMicrophoneMuted(muted);
}
async function requestPermissions() {
    return await ExpoRealtimeIvsBroadcastModule_1.default.requestPermissions();
}
// --- Event Emitter ---
function addOnStageConnectionStateChangedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onStageConnectionStateChanged', listener);
}
function addOnPublishStateChangedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onPublishStateChanged', listener);
}
function addOnStageErrorListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onStageError', listener);
}
function addOnCameraSwappedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onCameraSwapped', listener);
}
function addOnCameraSwapErrorListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onCameraSwapError', listener);
}
function addOnParticipantJoinedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onParticipantJoined', listener);
}
function addOnParticipantLeftListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onParticipantLeft', listener);
}
function addOnParticipantStreamsAddedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onParticipantStreamsAdded', listener);
}
function addOnParticipantStreamsRemovedListener(listener) {
    return ExpoRealtimeIvsBroadcastModule_1.default.addListener('onParticipantStreamsRemoved', listener);
}
//# sourceMappingURL=index.js.map