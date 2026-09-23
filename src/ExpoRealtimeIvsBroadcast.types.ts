import type { StyleProp, ViewStyle } from 'react-native';

// Configuration types for the initialize method
export interface LocalAudioConfig {
  /** Max audio bitrate in bps. Default 96000 (96 kbps). Range: 64000 - 128000 */
  maxBitrate?: number;
  /** Number of channels. 1 (mono) or 2 (stereo). Default 1. */
  channels?: 1 | 2;
}

export interface LocalVideoConfig {
  /** Frame width in pixels. Default 720. */
  width?: number;
  /** Frame height in pixels. Default 1280 (portrait). */
  height?: number;
  /**
   * Target frame rate. Default 30.
   *
   * The IVS Stages SDK ships with 15 fps as its internal default — too choppy for
   * product demos. This module overrides that to 30 fps on both iOS and Android.
   * 60 fps is not supported by Stages; if you need higher, switch to the IVS
   * low-latency broadcast SDK (different module, single-publisher only).
   */
  targetFramerate?: number;
  /**
   * Max video bitrate in bps. Default 2_500_000 (2.5 Mbps).
   *
   * Tuned for 720x1280 portrait @ 30 fps. WebRTC adaptive bitrate scales between
   * `minBitrate` and `maxBitrate` based on `availableOutgoingBitrate`, so this is
   * a ceiling rather than a target. AWS IVS Stages caps per-participant bitrate
   * — setting this higher won't push past the stage's allowance.
   */
  maxBitrate?: number;
  /**
   * Min video bitrate in bps. Default 500_000 (500 kbps).
   *
   * Floor below which the encoder won't drop, preserving readable picture quality
   * on bad networks at the cost of more frame drops. Lower this to 200_000 if you
   * need to support very poor uplinks (hotel Wi-Fi, congested cellular).
   */
  minBitrate?: number;
  /** Enable simulcast (multiple layers). Default true. */
  simulcast?: boolean;
  /** Degradation preference under network pressure. Default 'balanced'. */
  degradationPreference?: 'balanced' | 'maintainFramerate' | 'maintainResolution';
}

// Permission status types for requestPermissions method
export type PermissionStatus = 'granted' | 'denied' | 'not-determined' | 'unavailable';
export interface PermissionStatusMap {
  camera: PermissionStatus;
  microphone: PermissionStatus;
}

// --- Audio routing & device picker ---

/**
 * Audio session preset. Controls echo cancellation, noise suppression, gain,
 * and which speaker the audio plays out of.
 *
 * - 'videoChat': Two-way communication. AEC/NS/AGC on. Lower gain. Use when host has open mic + speaker.
 * - 'subscribeOnly': Viewer mode. No mic processing. Media-volume routing (loud).
 * - 'studio': Pro mode. AEC/NS/AGC OFF. Highest quality. Use with wired/external mic for content streaming.
 *             Studio gives the loudest perceived mic level on the built-in mic too.
 */
export type AudioPreset = 'videoChat' | 'subscribeOnly' | 'studio';

/**
 * An audio input device available for selection.
 */
export interface AudioInputDevice {
  /** Stable identifier for the device. Pass back to setPreferredAudioInput. */
  urn: string;
  /** Human-readable name (e.g., "iPhone Microphone", "AirPods Pro"). */
  name: string;
  /** Device type. */
  type: 'builtin' | 'bluetooth' | 'wired' | 'usb' | 'unknown';
  /** Whether this is currently the active input. */
  isActive: boolean;
}

/**
 * Emitted when the active audio input device changes (e.g., AirPods connect,
 * headphones unplug, user picks a different device).
 */
export interface AudioRouteChangedPayload {
  reason:
    | 'newDeviceAvailable'
    | 'oldDeviceUnavailable'
    | 'userSelected'
    | 'override'
    | 'unknown';
  activeInput?: AudioInputDevice;
}

/**
 * Emitted when the audio session is interrupted (incoming call, Siri, another
 * audio app taking over) or resumes. iOS only — Android handles this via OS.
 */
export interface AudioInterruptionPayload {
  state: 'began' | 'ended';
  /** When state==='ended', whether the SDK should resume audio. */
  shouldResume?: boolean;
}

/**
 * Real-time mic audio level. Emitted ~10x/sec while a microphone stream is active.
 * Values are in dB. Typical voice range: peak around -20 to 0, rms around -40 to -10.
 * Plot these on a meter so the broadcaster can verify their mic is hot before going live.
 */
export interface AudioLevelPayload {
  /** Peak level in dB (loudest sample in the window). */
  peak: number;
  /** RMS level in dB (average loudness). */
  rms: number;
}

/**
 * Periodic WebRTC stats snapshot. Emitted every ~2 seconds while a stream is
 * publishing or subscribing. Use for "is my upload bitrate dropping?" UX.
 */
export interface RTCStatsPayload {
  /** Outbound bitrate in bits per second. */
  outboundBitrate?: number;
  /** Average round-trip time in milliseconds. */
  roundTripTime?: number;
  /** Packet loss fraction 0.0–1.0. */
  packetLoss?: number;
  /** Audio jitter in seconds. */
  jitter?: number;
  /** Frames per second on the outbound video stream. */
  framesPerSecond?: number;
  /** Reason the encoder is throttling, if any. */
  qualityLimitationReason?: string;
  /** Raw vendor key/value bag for fallback access. */
  raw?: Record<string, Record<string, string>>;
}

/**
 * Emitted when a remote participant mutes/unmutes a stream.
 */
export interface RemoteMuteStatePayload {
  participantId: string;
  /** Per-stream mute state, keyed by deviceUrn. */
  streams: { deviceUrn: string; mediaType: 'audio' | 'video' | 'unknown'; muted: boolean }[];
}

/**
 * Local subscribe state changes (Android only fires this; iOS emits via the
 * existing connection event).
 */
export interface SubscribeStatePayload {
  participantId: string;
  state: 'not_subscribed' | 'attempting' | 'subscribed' | 'failed';
}

/**
 * Coordinated background behavior. When the host app enters background, the
 * IVS SDK does not automatically pause publishing or downshift subscribers —
 * call setBackgroundBehavior() to do both atomically.
 */
export interface BackgroundBehaviorOptions {
  /** Stop publishing video+audio when entering background. Default true. */
  stopPublishing?: boolean;
  /** Subscribe mode while backgrounded. Default 'audioOnly'. */
  subscribeMode?: 'none' | 'audioOnly' | 'audioVideo';
}

/**
 * Device thermal state. Mapped to a normalized 4-level scale across iOS and Android.
 *
 * - `nominal`: Cool, no throttling.
 * - `fair`: Warming up — soft warning.
 * - `serious`: OS is throttling CPU/GPU. Downshift to lower framerate to save battery and avoid stutter.
 * - `critical`: Risk of thermal shutdown. Drop to lowest sustainable rate.
 */
export type ThermalState = 'nominal' | 'fair' | 'serious' | 'critical';

export interface ThermalStateChangedPayload {
  state: ThermalState;
  /** True when auto-mitigation just downshifted streams in response. */
  didMitigate: boolean;
}

export interface ThermalMitigationOptions {
  /** Whether the SDK should automatically downshift framerate on thermal pressure. Default false. */
  enabled?: boolean;
  /** Framerate to use when state >= 'serious'. Default 15. */
  reducedFramerate?: number;
}

// --- Event Payloads for Native Module Emitter ---
export interface StageConnectionStatePayload {
  state: 'connecting' | 'connected' | 'disconnected';
  error?: string;
}

export interface PublishStatePayload {
  state: 'not_published' | 'attempting' | 'published' | 'failed'; // Added 'failed' as a common case
  error?: string;
}

export interface StageErrorPayload {
  code: number;
  description: string;
  source: string;
  isFatal: boolean;
}

export interface CameraSwappedPayload {
  newCameraURN: string;
  newCameraName: string;
}

export interface CameraSwapErrorPayload {
  reason: string;
}

export interface CameraMuteStatePayload {
  muted: boolean;
  placeholderActive: boolean;
}

// As per plan
export interface StageStream {
  deviceUrn: string;
  mediaType: 'video' | 'audio' | 'unknown';
}

export interface Participant {
  id: string;
  streams: StageStream[];
}

// Payloads for participant events
export interface ParticipantPayload {
  participantId: string;
}

export interface ParticipantStreamsPayload {
  participantId: string;
  streams: StageStream[];
}

export interface ParticipantStreamsRemovedPayload {
  participantId: string;
  // On removal, we only get the URNs back from the native side
  streams: { deviceUrn: string }[];
}

// --- Picture-in-Picture Types ---

/**
 * Options for configuring Picture-in-Picture behavior
 */
export interface PiPOptions {
  /**
   * Whether to automatically enter PiP when the app goes to background
   * @default true
   */
  autoEnterOnBackground?: boolean;

  /**
   * Which video stream to show in PiP
   * - 'local': Shows the local camera preview (for broadcasters)
   * - 'remote': Shows the remote participant stream (for viewers)
   * @default 'remote'
   */
  sourceView?: 'local' | 'remote';

  /**
   * Preferred aspect ratio for the PiP window
   * @default { width: 9, height: 16 } (portrait)
   */
  preferredAspectRatio?: {
    width: number;
    height: number;
  };
}

/**
 * PiP state change event payload
 */
export interface PiPStateChangedPayload {
  /**
   * Current PiP state:
   * - 'started': PiP mode has started
   * - 'stopped': PiP mode has stopped
   * - 'restored': User tapped to return from PiP to full screen
   */
  state: 'started' | 'stopped' | 'restored';
}

/**
 * PiP error event payload
 */
export interface PiPErrorPayload {
  error: string;
}

/**
 * PiP remote-source validity event payload. `valid` is true when the native PiP
 * source is a real rendering remote view, false when it falls back to the
 * device.previewView() placeholder (which yields a frozen/black PiP window).
 */
export interface PiPSourceValidityPayload {
  valid: boolean;
}

// Defines the events that the native module can emit
export type ExpoRealtimeIvsBroadcastModuleEvents = {
  onStageConnectionStateChanged: (payload: StageConnectionStatePayload) => void;
  onPublishStateChanged: (payload: PublishStatePayload) => void;
  onStageError: (payload: StageErrorPayload) => void;
  onParticipantJoined: (payload: ParticipantPayload) => void;
  onParticipantLeft: (payload: ParticipantPayload) => void;
  onParticipantStreamsAdded: (payload: ParticipantStreamsPayload) => void;
  onParticipantStreamsRemoved: (payload: ParticipantStreamsRemovedPayload) => void;
  onCameraSwapped: (payload: CameraSwappedPayload) => void;
  onCameraSwapError: (payload: CameraSwapErrorPayload) => void;
  onCameraMuteStateChanged: (payload: CameraMuteStatePayload) => void;
  // Audio events
  onAudioRouteChanged: (payload: AudioRouteChangedPayload) => void;
  onAudioInterruption: (payload: AudioInterruptionPayload) => void;
  onAudioLevel: (payload: AudioLevelPayload) => void;
  // Stats / observability
  onRTCStats: (payload: RTCStatsPayload) => void;
  // Remote participant state
  onRemoteMuteStateChanged: (payload: RemoteMuteStatePayload) => void;
  onSubscribeStateChanged: (payload: SubscribeStatePayload) => void;
  // Thermal state
  onThermalStateChanged: (payload: ThermalStateChangedPayload) => void;
  // PiP events
  onPiPStateChanged: (payload: PiPStateChangedPayload) => void;
  onPiPError: (payload: PiPErrorPayload) => void;
  onPiPSourceValidityChanged: (payload: PiPSourceValidityPayload) => void;
};

// Props for the ExpoIVSStagePreviewView component
export type ExpoIVSStagePreviewViewProps = {
  style?: StyleProp<ViewStyle>;
  mirror?: boolean;
  scaleMode?: 'fit' | 'fill'; // As per plan
};

// Props for the new remote stream view
export type ExpoIVSRemoteStreamViewProps = {
  style?: StyleProp<ViewStyle>;
  participantId?: string;
  deviceUrn?: string;
  scaleMode?: 'fit' | 'fill';
};
