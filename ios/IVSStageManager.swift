import ExpoModulesCore
import AmazonIVSBroadcast
import AVFoundation // For AVAudioSession

extension Notification.Name {
    static let remoteStreamAvailable = Notification.Name("remoteStreamAvailableNotification")
}

// A class to hold the combined state for a single participant
class StageParticipant {
    let info: IVSParticipantInfo
    var streams: [IVSStageStream]

    init(info: IVSParticipantInfo) {
        self.info = info
        self.streams = []
    }
}

// Define the delegate protocol for event emission
protocol IVSStageManagerDelegate: AnyObject {
    func stageManagerDidEmitEvent(eventName: String, body: [String: Any]?)
}

class IVSStageManager: NSObject, IVSStageStreamDelegate, IVSStageStrategy, IVSStageRenderer {
    // MARK: - Properties

    private var stage: IVSStage?
    private let stageAudioManager = IVSStageAudioManager.sharedInstance() // Recommended to setup before stage creation

    private var cameraStream: IVSLocalStageStream?
    private var microphoneStream: IVSLocalStageStream?

    // To keep track of the selected camera device (front/back)
    private var currentCameraDevice: IVSDevice? // Initially nil, can be set to default
    private var availableCameras: [IVSCamera] = []

    // Delegate for sending events back to the Module
    weak var delegate: IVSStageManagerDelegate?

    private var isPublishingActive: Bool = false // Added state for desired publishing status

    // To maintain a queryable list of participants using our custom class
    public var participants: [StageParticipant] = []

    // A list of all available remote view canvases.
    private var remoteViews: [Weak<ExpoIVSRemoteStreamView>] = []
    // The specific participant we should prioritize rendering.
    private var targetParticipantId: String?

    // MARK: - Initialization

    override init() {
        super.init()
        // Discover devices early if needed, or on demand
        discoverDevices()
        setupAudioSession()
    }

    private func discoverDevices() {
        // Discover cameras
        let discovery = IVSDeviceDiscovery() // Create an instance
        let localDevices = discovery.listLocalDevices() // This returns [any IVSDevice]

        self.availableCameras = localDevices.compactMap { device -> IVSCamera? in
            // Access the descriptor of the IVSDevice, then check its type
            if device.descriptor().type == IVSDeviceType.camera {
                // The device itself (which conforms to IVSDevice) needs to be cast to IVSCamera
                // The static IVSDeviceDiscovery.device(forURN:) is more for getting a device if you only have a URN.
                // Here, we already have the IVSDevice object.
                return device as? IVSCamera
            }
            return nil
        }

        if let defaultCamera = self.availableCameras.first(where: { $0.descriptor().position == .front }) ?? self.availableCameras.first {
            self.currentCameraDevice = defaultCamera
        }
        // Microphone discovery is now primarily handled in initializeStage
    }

    private func setupAudioSession() {
        // It's crucial to prepare the audio session *before* joining a stage.
        // The IVSStageAudioManager handles this.
        // We will set a preset suitable for video conferencing.
        stageAudioManager.setPreset(.videoChat)
        print("IVSStageAudioManager preset to .videoChat")
        // Note: Error handling for setPreset is not explicitly shown in the IVS SDK docs,
        // but you might want to wrap in do-catch if issues arise, though it's a void func.
    }

    // MARK: - Public API (to be called from ExpoRealtimeIvsBroadcastModule)

    func initializeStage(audioConfig: IVSLocalStageStreamAudioConfiguration? = nil, videoConfig: IVSLocalStageStreamVideoConfiguration? = nil) {
        // This method can be used to pre-configure stream settings if desired.
        // Create local streams here if not already created, or update their configurations.
        print("IVSStageManager: Initializing stage (pre-configuring streams).")

        // Ensure devices are discovered (or re-discovered if necessary)
        if availableCameras.isEmpty { // Or some other condition to re-discover
            discoverDevices()
        }

        // Create camera stream
        if let camera = currentCameraDevice as? IVSCamera {
            let finalVideoConfig: IVSLocalStageStreamVideoConfiguration = videoConfig ?? {
                let config = IVSLocalStageStreamVideoConfiguration()
                do {
                    try config.setSize(CGSize(width: 720, height: 1280)) // 720p Portrait
                } catch {
                    print("Error setting default video configuration size: \(error). Using IVS defaults for size.")
                }
                return config
            }()

            let streamConfig = IVSLocalStageStreamConfiguration()
            streamConfig.video = finalVideoConfig
            
            self.cameraStream = IVSLocalStageStream(device: camera, config: streamConfig)
            self.cameraStream?.delegate = self
            print("Camera stream created.")
        } else {
            print("No camera device available or selected to create stream.")
        }

        // Create microphone stream
        let discovery = IVSDeviceDiscovery()
        let localDevicesForMic = discovery.listLocalDevices()
        let micDevice = localDevicesForMic.first { $0.descriptor().type == IVSDeviceType.microphone }

        if let microphoneDevice = micDevice as? IVSMicrophone {
            let finalAudioConfig: IVSLocalStageStreamAudioConfiguration = audioConfig ?? IVSLocalStageStreamAudioConfiguration()
            
            let streamConfig = IVSLocalStageStreamConfiguration()
            streamConfig.audio = finalAudioConfig
            
            self.microphoneStream = IVSLocalStageStream(device: microphoneDevice, config: streamConfig)
            self.microphoneStream?.delegate = self
            print("Microphone stream created using discovered device.")
        } else {
            print("No suitable microphone device found through descriptor method.")
        }
    }

    func joinStage(token: String, targetParticipantId: String? = nil) {
        self.targetParticipantId = targetParticipantId
        guard cameraStream != nil, microphoneStream != nil else {
            print("Error: Streams not initialized. Call initializeStage first.")
            delegate?.stageManagerDidEmitEvent(eventName: "onStageError", body: ["code": -1, "description": "Streams not initialized. Call initializeStage first.", "source": "IVSStageManager.joinStage.guard", "isFatal": true])
            return
        }

        // The IVSStageManager itself will now be the strategy.
        do {
            self.stage = try IVSStage(token: token, strategy: self)
            print("IVSStage initialized successfully.")
        } catch {
            print("Error initializing IVSStage: \(error)")
            let nsError = error as NSError
            delegate?.stageManagerDidEmitEvent(eventName: "onStageError", body: ["code": nsError.code, "description": "Failed to initialize IVSStage: \(error.localizedDescription)", "source": "IVSStageManager.joinStage.init", "isFatal": true])
            // Potentially update a connection state to reflect this failure if you have such a state before joining
            delegate?.stageManagerDidEmitEvent(eventName: "onStageConnectionStateChanged", body: ["state": "error", "error": "Failed to initialize IVSStage: \(error.localizedDescription)"])
            return // Do not proceed if stage initialization fails
        }
        
        self.stage?.addRenderer(self)
        self.stage?.errorDelegate = self

        do {
            try self.stage?.join()
            print("IVSStage join() method called. Connection status will be updated via delegate methods.")
            // Successfully initiated join, now set publishing to active and refresh strategy
//            self.setStreamsPublished(published: true)
        } catch {
            print("Error attempting to join IVSStage: \(error)")
            let nsError = error as NSError
            delegate?.stageManagerDidEmitEvent(eventName: "onStageError", body: ["code": nsError.code, "description": "Failed to join IVSStage: \(error.localizedDescription)", "source": "IVSStageManager.joinStage.joinCall", "isFatal": true])
            delegate?.stageManagerDidEmitEvent(eventName: "onStageConnectionStateChanged", body: ["state": "error", "error": "Failed to join IVSStage: \(error.localizedDescription)"])
        }
    }

    func leaveStage() {
        if self.stage != nil {
            print("IVSStageManager: Preparing to leave stage. Setting publishing to false and refreshing strategy.")
            // Set publishing to false and refresh strategy before actually leaving
            self.setStreamsPublished(published: false)
            
            // It might be good practice to wait a very brief moment or ensure refreshStrategy
            // has been processed if there are race conditions, but typically it should be fine.
            // For robustness, one could use a short delay or a completion handler if refreshStrategy had one.

        stage?.leave()
        print("Left stage.")
            // Consider nil-ing out stage and streams here or in a disconnected delegate callback
            // self.stage = nil
            // self.cameraStream = nil
            // self.microphoneStream = nil
            // self.currentPreviewDeviceUrn = nil // From ExpoIVSStagePreviewView if it shares this manager directly
            // moduleEventEmitter?.sendEvent(withName: "onStageConnectionStateChanged", body: ["state": "disconnected"])
        } else {
            print("IVSStageManager: Attempted to leave stage, but stage is already nil.")
        }
    }

    func setStreamsPublished(published: Bool) {
        guard self.stage != nil else {
            print("IVSStageManager: Stage not initialized. Cannot set streams published state.")
            // Optionally send an error event back to JS
            return
        }

        self.isPublishingActive = published
        print("IVSStageManager: Desired publishing state set to \(published). Refreshing strategy.")
        self.stage?.refreshStrategy() // Tell the stage to re-evaluate its strategy
    }

    func swapCamera() {
        guard self.cameraStream != nil else {
            print("IVSStageManager: Camera stream not initialized. Cannot swap camera.")
            // Optionally, send an event to JS
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "Camera stream not initialized."])
            return
        }

        guard let currentCamDevice = self.currentCameraDevice as? IVSCamera else {
            print("IVSStageManager: Current camera device is not set or not an IVSCamera.")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "Current camera device not set."])
            return
        }

        // Determine the new camera to switch to (e.g., front to back or vice-versa)
        let targetPosition: IVSDevicePosition = (currentCamDevice.descriptor().position == .front) ? .back : .front
        guard let newCamera = self.availableCameras.first(where: { $0.descriptor().position == targetPosition }) ?? self.availableCameras.first(where: { $0.descriptor().urn != currentCamDevice.descriptor().urn }) else {
            print("IVSStageManager: No other camera available to swap to, or only one camera exists.")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "No other camera available."])
            return
        }

        if newCamera.descriptor().urn == currentCamDevice.descriptor().urn {
            print("IVSStageManager: Selected new camera is the same as the current one. No swap needed.")
            // Optionally inform JS if needed
            return
        }
        
        print("IVSStageManager: Attempting to swap from camera \(currentCamDevice.descriptor().friendlyName) to \(newCamera.descriptor().friendlyName)")

        // 1. Create a default video configuration (consistent with initializeStage)
        let defaultVideoConfig: IVSLocalStageStreamVideoConfiguration = {
            let config = IVSLocalStageStreamVideoConfiguration()
            do {
                try config.setSize(CGSize(width: 720, height: 1280)) // 720p Portrait
                // Add other default parameters like bitrate or framerate if desired
                // try config.setMaxBitrate(1_500_000)
                // try config.setTargetFramerate(30)
            } catch {
                print("IVSStageManager: Error setting default video config for camera swap: \\(error). Using IVS defaults for size.")
                // Consider emitting an error or using a fallback
            }
            return config
        }()

        // 2. Create the general stream configuration
        let streamConfig = IVSLocalStageStreamConfiguration()
        streamConfig.video = defaultVideoConfig
        // If your camera stream could potentially have audio, you'd set streamConfig.audio here as well.
        // For a typical setup, the camera stream is video-only and microphone is a separate stream.

        // 3. Create the new local camera stream
        let newLocalCameraStream = IVSLocalStageStream(device: newCamera, config: streamConfig)
        newLocalCameraStream.delegate = self // Don't forget to set the delegate

        // 4. Update the manager's properties
        self.cameraStream = newLocalCameraStream
        self.currentCameraDevice = newCamera // newCamera is already an IVSDevice, no need to cast from IVSCamera again here
        // 5. Tell the stage to re-evaluate its strategy with the new camera stream
        self.stage?.refreshStrategy()

        print("IVSStageManager: Camera swapped successfully to \(newCamera.descriptor().friendlyName).")
        delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapped", body: ["newCameraURN": newCamera.descriptor().urn, "newCameraName": newCamera.descriptor().friendlyName])
    }

     // --- NEW VIEW MANAGEMENT API ---
    func registerRemoteView(_ view: ExpoIVSRemoteStreamView) {
        // Add a weak reference to the view to avoid memory leaks.
        self.remoteViews.append(Weak(view))
        print("🧠 [MANAGER] A remote view has registered. Total views: \(self.remoteViews.count)")
        
        // --- THIS IS THE FIX ---
        // A view was just added. It might be the canvas we were waiting for.
        // Immediately try to assign any streams that are waiting in our state.
        self.assignStreamsToAvailableViews()
    }
    
    func unregisterRemoteView(_ view: ExpoIVSRemoteStreamView) {
        // Remove the view if it's destroyed.
        self.remoteViews.removeAll { $0.value === view }
        print("🧠 [MANAGER] A remote view has unregistered. Total views: \(self.remoteViews.count)")
    }

    private func assignStreamsToAvailableViews() {
        print("🧠 [MANAGER] Assigning streams to views...")
        
        // Get a set of all streams that are already being rendered.
        let renderedUrns = Set(self.remoteViews.compactMap { $0.value?.currentRenderedDeviceUrn })
        
        // Find all views that are not currently rendering anything.
        let availableViews = self.remoteViews.compactMap { $0.value }.filter { $0.currentRenderedDeviceUrn == nil }
        
        // Find all video streams that are not currently being rendered.
        var availableStreams: [(participantId: String, stream: IVSStageStream)] = []
        for p in self.participants {
            for s in p.streams {
                if s.device.descriptor().type == IVSDeviceType(rawValue: 5) && !renderedUrns.contains(s.device.descriptor().urn) {
                    availableStreams.append((p.info.participantId, s))
                }
            }
        }
        
        // If a target participant is specified, prioritize their stream.
        if let targetId = self.targetParticipantId {
            availableStreams.sort { a, _ in a.participantId == targetId }
        }

        print("🧠 [MANAGER] Found \(availableViews.count) available views and \(availableStreams.count) available streams.")

        // Assign each available stream to an available view.
        for (view, streamInfo) in zip(availableViews, availableStreams) {
            print("🧠 [MANAGER] Assigning stream \(streamInfo.stream.device.descriptor().urn) to a view.")
            view.renderStream(participantId: streamInfo.participantId, deviceUrn: streamInfo.stream.device.descriptor().urn)
        }
    }
    // --- END NEW VIEW MANAGEMENT API ---


    func setMicrophoneMuted(muted: Bool) {
        microphoneStream?.setMuted(muted)
        print("Microphone muted: \(muted)")
    }
    
    // Public getter for the camera stream so the View can access it
    public func getCameraStream() -> IVSLocalStageStream? {
        return self.cameraStream
    }
    
    public func findStream(forParticipantId participantId: String, deviceUrn: String) -> IVSStageStream? {
        guard let participant = self.participants.first(where: { $0.info.participantId == participantId }) else {
            print("IVSStageManager: findStream: Participant NOT FOUND.")
            return nil // Remote participant not found in our state.
        }
        print("IVSStageManager: findStream: Participant FOUND.")
        return participant.streams.first(where: { $0.device.descriptor().urn == deviceUrn })
    }

    func getCameraPreview() -> UIView? {
        // This is a simplified way, assuming the camera stream is available
        // and you have a way to render it directly or via the ExpoIVSStagePreviewView
        // For direct rendering (if IVSLocalStageStream can be rendered directly, check SDK docs):
        // if let cameraStream = self.cameraStream {
        //     let preview = IVSImagePreviewView() // Or appropriate IVS view for local stream
        //     preview.setStream(cameraStream) // This is hypothetical, check correct API
        //     return preview
        // }
        // More likely, ExpoIVSStagePreviewView will ask for the stream and render it.
        return nil // Placeholder
    }
    
    // MARK: - IVSLocalStageStreamDelegate

    func localStageStream(_ stream: IVSLocalStageStream, didChangeMuteState muted: Bool) {
        print("Stream: \(stream.device.descriptor().urn) didChangeMuteState: \(muted)")
        // Emit an event if needed, e.g., onMicrophoneMuteStateChanged
    }

    func localStageStream(_ stream: IVSLocalStageStream, didUpdateConfiguration configuration: IVSLocalStageStreamConfiguration) {
        print("Stream: \(stream.device.descriptor().urn) didUpdateConfiguration")
        // Handle configuration updates if necessary
    }

    // MARK: - IVSErrorSourceDelegate (Add conformance if stage.errorDelegate = self is used)
    // func source(_ source: IVSErrorSource, didFailWithError error: Error) {
    //     print("IVS SDK Error: \(error.localizedDescription) from source: \(source)")
    //     let nsError = error as NSError
    //     eventEmitter?.emit("onStageError", [
    //         "code": nsError.code,
    //         "description": nsError.localizedDescription,
    //         "source": "\(source)", // May need better representation of source
    //         "isFatal": (source as? IVSStage)?.isFatalError(error) ?? false // Example, check actual API
    //     ])
    // }
}

// MARK: - IVSStageStrategy Implementation
extension IVSStageManager {
    func stage(_ stage: IVSStage, streamsToPublishForParticipant participant: IVSParticipantInfo) -> [IVSLocalStageStream] {
        if participant.isLocal {
            if self.isPublishingActive {
                var streams: [IVSLocalStageStream] = []
                if let cameraStream = self.cameraStream {
                    streams.append(cameraStream)
                }
                if let microphoneStream = self.microphoneStream {
                    streams.append(microphoneStream)
                }
                print("IVSStageManager Strategy: Providing \(streams.count) streams to publish for local participant (publishing active).")
                return streams
            } else {
                print("IVSStageManager Strategy: Providing 0 streams to publish for local participant (publishing not active).")
                return [] // Not publishing, so return no streams
            }
        } else {
            // For remote participants, we don't provide streams to publish from our end.
            return []
        }
    }

    func stage(_ stage: IVSStage, shouldPublishParticipant participant: IVSParticipantInfo) -> Bool {
        if participant.isLocal {
            print("IVSStageManager Strategy: Local participant shouldPublish: \(self.isPublishingActive)")
            return self.isPublishingActive
        } else {
            // This delegate method is primarily for the local participant.
            // The stage handles publishing for remote participants based on their own client's strategy.
            print("IVSStageManager Strategy: Remote participant \(participant.participantId ?? "N/A") shouldPublish: false (from our perspective)")
            return false 
        }
    }

    func stage(_ stage: IVSStage, shouldSubscribeToParticipant participant: IVSParticipantInfo) -> IVSStageSubscribeType {
        // For remote participants, we usually want to subscribe to both audio and video.
        // For the local participant, we don't subscribe to ourselves.
        if participant.isLocal {
            print("IVSStageManager Strategy: Participant \(participant.participantId ?? "N/A") is local, subscribing with .none")
            return .none
        } else {
            print("IVSStageManager Strategy: Participant \(participant.participantId ?? "N/A") is remote, subscribing with .audioVideo")
            return .audioVideo
        }
    }
    
    // Optional IVSStageStrategy methods can be implemented here if needed, for example:
    // func stage(_ stage: IVSStage, subscribeConfigurationForParticipant participant: IVSParticipantInfo) -> IVSSubscribeConfiguration {
    //     return IVSSubscribeConfiguration() // Default configuration
    // }
}

// Extend IVSStage to conform to IVSErrorSource if needed for the delegate pattern above
// or ensure IVSStageManager conforms to the correct error delegate protocol from the SDK

// Extend IVSStageManager to conform to IVSStageRenderer for audio, as per documentation
// This might already be handled by IVSStageAudioManager, need to confirm exact SDK usage.
// If IVSStageAudioManager is already an IVSStageRenderer, then attaching it to the stage is sufficient.

// Conform to IVSErrorSourceDelegate if you set `stage.errorDelegate = self`
extension IVSStageManager: IVSErrorDelegate {
    func source(_ source: IVSErrorSource, didEmitError error: Error) {
        print("IVS SDK Error: \(error.localizedDescription) from source: \(source)")
        let nsError = error as NSError
        var isFatal = false

        // TODO: Get stage error
//        if let stageError = error as? IVSStageError, stageError.isFatal() {
//            isFatal = true
//        }
        // Or, if it's a generic error that you want to treat as fatal for the stage
        // if source is self.stage { isFatal = true } 

        delegate?.stageManagerDidEmitEvent(eventName: "onStageError", body: [
            "code": nsError.code,
            "description": nsError.localizedDescription,
            "source": String(describing: source), // A basic representation of the source
            "isFatal": isFatal
        ])

        // Handle stage lifecycle based on error, e.g., if fatal, update connection state
        if isFatal && source as? IVSStage === self.stage {
            self.stage = nil // Or some other cleanup
            delegate?.stageManagerDidEmitEvent(eventName: "onStageConnectionStateChanged", body: ["state": "disconnected", "error": nsError.localizedDescription])
        }
    }
}

// The plan mentions: Monitors stage connection state (IVSStageConnectionState) and stream publish state (IVSParticipantPublishState).
// These are typically handled via the IVSStage object itself or its delegates/callbacks.
// For example, the join callback gives initial connection success/failure.
// For publish state changes, the IVSStage provides `publishState(for:)` and might have delegate methods
// on IVSStageStreamDelegate or a specific participant delegate if available.
// We need to ensure these state changes are emitted to JS.

// MARK: - IVSStageRenderer Implementation
extension IVSStageManager {
    func stage(_ stage: IVSStage, didChange connectionState: IVSStageConnectionState, withError error: Error?) {
        var stateString = ""
        switch connectionState {
        case .connecting:
            stateString = "connecting"
        case .connected:
            stateString = "connected"
        case .disconnected:
            stateString = "disconnected"
        @unknown default:
            stateString = "unknown"
        }
        
        var body: [String: Any] = ["state": stateString]
        if let error = error {
            let nsError = error as NSError
            body["error"] = nsError.localizedDescription
        }
        
        delegate?.stageManagerDidEmitEvent(eventName: "onStageConnectionStateChanged", body: body)
        print("IVSStageManager Renderer: Connection state changed to \(stateString)")

        // If disconnected, we should clean up our local state
        if connectionState == .disconnected {
            self.isPublishingActive = false
            self.stage = nil
            self.participants.removeAll()
        }
    }
    
    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChange publishState: IVSParticipantPublishState) {
        if !participant.isLocal { return }
        
        var stateString = ""
        switch publishState {
        case .notPublished:
            stateString = "not_published"
        case .published:
            stateString = "published"
        @unknown default:
            stateString = "unknown_publish_state"
        }
        
        let body: [String: Any] = ["state": stateString]
        delegate?.stageManagerDidEmitEvent(eventName: "onPublishStateChanged", body: body)
        print("IVSStageManager Renderer: Local participant publish state changed to \(stateString)")
    }

    func stage(_ stage: IVSStage, participantDidJoin participant: IVSParticipantInfo) {
        print("✅ [DEBUG] Participant Joined - ID: \(participant.participantId ?? "N/A")")
        print("✅ [DEBUG] Participant Attributes: \(participant.attributes)")

        if participant.isLocal { return }
        
        let newParticipant = StageParticipant(info: participant)
        self.participants.append(newParticipant)

        delegate?.stageManagerDidEmitEvent(eventName: "onParticipantJoined", body: ["participantId": participant.participantId])
    }

    func stage(_ stage: IVSStage, participantDidLeave participant: IVSParticipantInfo) {
        print("IVSStageManager Renderer: Participant left: \(participant.participantId ?? "N/A")")
        if participant.isLocal { return }

        // Remove the participant from our state.
        self.participants.removeAll { $0.info.participantId == participant.participantId }

        // Emit event to JS
        delegate?.stageManagerDidEmitEvent(eventName: "onParticipantLeft", body: ["participantId": participant.participantId])
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didAdd streams: [IVSStageStream]) {
        print("IVSStageManager Renderer: Participant \(participant.participantId ?? "N/A") added \(streams.count) streams.")
        print("✅ [DEBUG] Participant \(participant.participantId ?? "N/A") added \(streams.count) streams.")

        // Loop through the streams to get each deviceUrn
        for stream in streams {
            print("✅ [DEBUG]   -> Stream Added - Device URN: \(stream.device.descriptor().urn)")
        }

        if participant.isLocal { return }

        guard let stageParticipant = self.participants.first(where: { $0.info.participantId == participant.participantId }) else {
            print("IVSStageManager: Received streams for a participant not in our list: \(participant.participantId ?? "N/A")")
            return
        }

        stageParticipant.streams.append(contentsOf: streams)

        let streamDicts = streams.map { stream -> [String: Any] in
            print("✅ [DEBUG] Steam Device Type: \(stream.device.descriptor().type)")
            var mediaType: String
            switch stream.device.descriptor().type {
            case IVSDeviceType(rawValue: 5):
                mediaType = "video"
            case IVSDeviceType(rawValue: 6):
                mediaType = "audio"
            default:
                mediaType = "unknown"
            }
            return [
                "deviceUrn": stream.device.descriptor().urn,
                "mediaType": mediaType
            ]
        }

        let body: [String: Any] = [
            "participantId": participant.participantId ?? "",
            "streams": streamDicts
        ]

        if streams.contains(where: { $0.device.descriptor().type == IVSDeviceType(rawValue: 5) }) {
            print("🧠 [MANAGER] Assigning streams to available views. didAddStreams")
            self.assignStreamsToAvailableViews()
        }
        
        delegate?.stageManagerDidEmitEvent(eventName: "onParticipantStreamsAdded", body: body)
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didRemove streams: [IVSStageStream]) {
        print("IVSStageManager Renderer: Participant \(participant.participantId ?? "N/A") removed \(streams.count) streams.")

        if participant.isLocal { return }

        // Find the participant and remove the streams from their list
        if let existingParticipant = self.participants.first(where: { $0.info.participantId == participant.participantId }) {
            let removedUrns = streams.map { $0.device.descriptor().urn }
            existingParticipant.streams.removeAll { removedUrns.contains($0.device.descriptor().urn) }
        }

        let streamDicts = streams.map { stream -> [String: Any] in
            return [
                "deviceUrn": stream.device.descriptor().urn
            ]
        }
        
        let body: [String: Any] = [
            "participantId": participant.participantId ?? "",
            "streams": streamDicts
        ]
        
        print("✅ [DEBUG] Body: \(body)")
        delegate?.stageManagerDidEmitEvent(eventName: "onParticipantStreamsRemoved", body: body)
    }
    
    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChangeMutedStreams streams: [IVSStageStream]) {
        if participant.isLocal { return }
        // This is useful for knowing if a remote participant muted.
        // We can emit an event for this if needed.
    }
}

// Further delegate methods from IVSStage (if it has a primary delegate for connection/publish states beyond join)
// would be implemented here. The current IVS SDK for Stage might rely more on completion handlers
// and direct state checking for some of these, or specific delegates for participants/streams. 

// MARK: - IVSStageStreamDelegate
extension IVSStageManager {
    func stream(_ stream: IVSStageStream, didChangeMuted muted: Bool) {
        // This is for local streams we manage.
        // We could emit an event if JS needs to know our own mute state changed.
        print("IVSStageManager: Stream \(stream.device.descriptor().urn) mute state changed to \(muted)")
    }
}

// A simple weak reference class to avoid memory leaks.
class Weak<T: AnyObject> {
  weak var value : T?
  init (_ value: T) {
    self.value = value
  }
}
