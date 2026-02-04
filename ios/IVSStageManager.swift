import ExpoModulesCore
import AmazonIVSBroadcast
import AVFoundation // For AVAudioSession
import AVKit

extension Notification.Name {
    static let remoteStreamAvailable = Notification.Name("remoteStreamAvailableNotification")
}

// MARK: - PiP Frame Source Protocol
protocol PiPFrameSource: AnyObject {
    func didReceiveFrame(_ pixelBuffer: CVPixelBuffer)
    func didReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}

// MARK: - Custom Camera Capture Manager
// This class captures video from AVCaptureDevice and feeds it to IVS custom image source
// Used to work around the IVS Stages SDK limitation where back camera isn't exposed

class CustomCameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var currentInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "com.ivs.camera.capture")
    
    var customImageSource: IVSCustomImageSource?
    var currentPosition: AVCaptureDevice.Position = .front
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    // PiP frame source delegate
    weak var pipFrameSource: PiPFrameSource?
    
    // Available cameras discovered via AVFoundation
    private(set) var availableCameras: [AVCaptureDevice] = []
    
    override init() {
        super.init()
        discoverCameras()
    }
    
    private func discoverCameras() {
        // Try to discover wide-angle cameras first (most common and best for streaming)
        var discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        availableCameras = discoverySession.devices
        
        // Fallback 1: If no wide-angle cameras, try dual/triple camera systems
        if availableCameras.isEmpty {
            print("📸 [CustomCameraCapture] No wide-angle cameras found, trying dual/triple cameras...")
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInDualCamera, .builtInTripleCamera, .builtInDualWideCamera],
                mediaType: .video,
                position: .unspecified
            )
            availableCameras = discoverySession.devices
        }
        
        // Fallback 2: If still empty, try telephoto and ultra-wide
        if availableCameras.isEmpty {
            print("📸 [CustomCameraCapture] No dual/triple cameras found, trying telephoto/ultra-wide...")
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTelephotoCamera, .builtInUltraWideCamera],
                mediaType: .video,
                position: .unspecified
            )
            availableCameras = discoverySession.devices
        }
        
        // Fallback 3: Last resort - try ANY video device
        if availableCameras.isEmpty {
            print("📸 [CustomCameraCapture] No built-in cameras found, trying any video device...")
            if let defaultCamera = AVCaptureDevice.default(for: .video) {
                availableCameras = [defaultCamera]
            }
        }
        
        print("📸 [CustomCameraCapture] Discovered \(availableCameras.count) cameras via AVFoundation")
        for camera in availableCameras {
            let posStr = camera.position == .front ? "FRONT" : (camera.position == .back ? "BACK" : "OTHER")
            print("📸 [CustomCameraCapture]   - \(posStr): \(camera.localizedName) (type: \(camera.deviceType.rawValue))")
        }
        
        if availableCameras.isEmpty {
            print("📸 [CustomCameraCapture] ⚠️ WARNING: No cameras found on this device!")
        }
    }
    
    func setupCaptureSession(for position: AVCaptureDevice.Position) -> Bool {
        print("📸 [CustomCameraCapture] Setting up capture session for position: \(position == .front ? "FRONT" : "BACK")")
        
        // Find the camera for the requested position
        guard let camera = availableCameras.first(where: { $0.position == position }) else {
            print("📸 [CustomCameraCapture] ❌ No camera found for position")
            return false
        }
        
        // Create or reuse capture session
        if captureSession == nil {
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .hd1280x720
            
            // iOS 16+: Enable multitasking camera access for PiP support
            // This allows camera to continue running when app is in PiP mode
            if #available(iOS 16.0, *) {
                if captureSession?.isMultitaskingCameraAccessSupported == true {
                    captureSession?.isMultitaskingCameraAccessEnabled = true
                    print("📸 [CustomCameraCapture] ✅ Multitasking camera access enabled (iOS 16+)")
                } else {
                    print("📸 [CustomCameraCapture] ⚠️ Multitasking camera access not supported on this device")
                }
            }
        }
        
        guard let session = captureSession else { return false }
        
        session.beginConfiguration()
        
        // Remove existing input if any
        if let existingInput = currentInput {
            session.removeInput(existingInput)
        }
        
        // Add new input
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
                currentPosition = position
                print("📸 [CustomCameraCapture] ✅ Added camera input: \(camera.localizedName)")
            } else {
                print("📸 [CustomCameraCapture] ❌ Cannot add camera input")
                session.commitConfiguration()
                return false
            }
        } catch {
            print("📸 [CustomCameraCapture] ❌ Error creating camera input: \(error)")
            session.commitConfiguration()
            return false
        }
        
        // Setup video output if not already done
        if videoOutput == nil {
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: captureQueue)
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                videoOutput = output
                print("📸 [CustomCameraCapture] ✅ Added video output")
            }
        }
        
        // Configure video orientation
        if let connection = videoOutput?.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // Mirror front camera
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (position == .front)
            }
            print("📸 [CustomCameraCapture] ✅ Configured video connection orientation")
        }
        
        session.commitConfiguration()
        
        // Create preview layer ONLY if it doesn't exist yet
        // The same preview layer will work when we swap cameras since it's connected to the session
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill
            print("📸 [CustomCameraCapture] ✅ Created preview layer")
        }
        
        return true
    }
    
    func startCapture() {
        captureQueue.async { [weak self] in
            if self?.captureSession?.isRunning == false {
                self?.captureSession?.startRunning()
                print("📸 [CustomCameraCapture] ✅ Capture session started")
            }
        }
    }
    
    func stopCapture() {
        captureQueue.async { [weak self] in
            if self?.captureSession?.isRunning == true {
                self?.captureSession?.stopRunning()
                print("📸 [CustomCameraCapture] Capture session stopped")
            }
        }
    }
    
    func swapCamera() -> Bool {
        let newPosition: AVCaptureDevice.Position = (currentPosition == .front) ? .back : .front
        print("📸 [CustomCameraCapture] Swapping camera from \(currentPosition == .front ? "FRONT" : "BACK") to \(newPosition == .front ? "FRONT" : "BACK")")
        
        // Setup capture session for new position (this will swap the input while keeping session)
        let success = setupCaptureSession(for: newPosition)
        
        if success {
            // Ensure capture is running
            if captureSession?.isRunning == false {
                captureQueue.async { [weak self] in
                    self?.captureSession?.startRunning()
                    print("📸 [CustomCameraCapture] ✅ Capture session restarted after swap")
                }
            }
        }
        
        return success
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    private var captureFrameCount: Int = 0
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        captureFrameCount += 1
        
        // Log periodically to track if capture is running
        if captureFrameCount == 1 || captureFrameCount % 300 == 0 {
            let isBackground = UIApplication.shared.applicationState == .background
            print("📸 [CustomCameraCapture] Frame #\(captureFrameCount), background: \(isBackground), hasPiPDelegate: \(pipFrameSource != nil)")
        }
        
        // Feed the sample buffer to IVS custom image source
        customImageSource?.onSampleBuffer(sampleBuffer)
        
        // Forward to PiP if enabled
        pipFrameSource?.didReceiveSampleBuffer(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame dropped - this is normal under heavy load
    }
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
    
    // Custom camera capture for back camera support (workaround for IVS Stages SDK limitation)
    private var customCameraCapture: CustomCameraCapture?
    private var customImageSource: IVSCustomImageSource?
    private var useCustomCameraCapture: Bool = false

    // Delegate for sending events back to the Module
    weak var delegate: IVSStageManagerDelegate?

    private var isPublishingActive: Bool = false // Added state for desired publishing status

    // To maintain a queryable list of participants using our custom class
    public var participants: [StageParticipant] = []

    // A list of all available remote view canvases.
    private var remoteViews: [Weak<ExpoIVSRemoteStreamView>] = []
    // The specific participant we should prioritize rendering.
    private var targetParticipantId: String?
    
    // MARK: - Picture-in-Picture Properties
    
    private var _pipController: AnyObject?
    private var _pipOptions: PiPOptions = PiPOptions()
    private var currentPiPSourceDeviceUrn: String?
    private weak var pipTargetView: UIView?
    // Store the current IVSImageDevice being used for PiP frame capture
    private var currentPiPDevice: IVSImageDevice?
    // Store the local preview view for broadcaster PiP
    private weak var localPreviewView: UIView?
    // Track whether we have a valid visible source view (not just device.previewView())
    private var pipHasValidSourceView: Bool = false
    
    @available(iOS 15.0, *)
    private var pipController: IVSPictureInPictureController {
        if _pipController == nil {
            let controller = IVSPictureInPictureController()
            controller.delegate = self
            _pipController = controller
        }
        return _pipController as! IVSPictureInPictureController
    }

    // MARK: - Initialization

    override init() {
        super.init()
        // Discover devices early if needed, or on demand
        setupAudioSession()
    }

    private func discoverDevices() {
        // Try multiple methods to discover cameras
        // Method 1: IVSBroadcastSession.listAvailableDevices() - recommended by AWS docs
        // Method 2: IVSDeviceDiscovery().listLocalDevices() - fallback
        
        print("📸 [iOS Camera Discovery] Starting device discovery...")
        
        // Log what AVFoundation sees (for debugging)
        let avSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        print("📸 [iOS Camera Discovery] AVFoundation sees \(avSession.devices.count) cameras:")
        for (index, avDevice) in avSession.devices.enumerated() {
            let posStr = avDevice.position == .front ? "FRONT" : (avDevice.position == .back ? "BACK" : "UNSPECIFIED")
            print("📸 [iOS Camera Discovery]   AVF \(index + 1): position=\(posStr), name=\(avDevice.localizedName)")
        }
        
        // Method 1: Try IVSBroadcastSession.listAvailableDevices() (AWS docs recommended)
        let broadcastDevices = IVSBroadcastSession.listAvailableDevices()
        print("📸 [iOS Camera Discovery] IVSBroadcastSession.listAvailableDevices() found \(broadcastDevices.count) devices:")
        for (index, descriptor) in broadcastDevices.enumerated() {
            let typeStr: String
            switch descriptor.type {
            case .camera: typeStr = "CAMERA"
            case .microphone: typeStr = "MICROPHONE"
            case .userAudio: typeStr = "USER_AUDIO"
            case .userImage: typeStr = "USER_IMAGE"
            @unknown default: typeStr = "UNKNOWN"
            }
            let posStr: String
            switch descriptor.position {
            case .front: posStr = "FRONT"
            case .back: posStr = "BACK"
            @unknown default: posStr = "OTHER"
            }
            print("📸 [iOS Camera Discovery]   Broadcast \(index + 1): type=\(typeStr), position=\(posStr), name=\(descriptor.friendlyName)")
        }
        
        // Method 2: Also try IVSDeviceDiscovery for comparison
        let discovery = IVSDeviceDiscovery()
        let localDevices = discovery.listLocalDevices()
        print("📸 [iOS Camera Discovery] IVSDeviceDiscovery.listLocalDevices() found \(localDevices.count) devices:")
        for (index, device) in localDevices.enumerated() {
            let descriptor = device.descriptor()
            let typeStr: String
            switch descriptor.type {
            case .camera: typeStr = "CAMERA"
            case .microphone: typeStr = "MICROPHONE"
            case .userAudio: typeStr = "USER_AUDIO"
            case .userImage: typeStr = "USER_IMAGE"
            @unknown default: typeStr = "UNKNOWN"
            }
            let posStr: String
            switch descriptor.position {
            case .front: posStr = "FRONT"
            case .back: posStr = "BACK"
            @unknown default: posStr = "OTHER"
            }
            print("📸 [iOS Camera Discovery]   Discovery \(index + 1): type=\(typeStr), position=\(posStr), name=\(descriptor.friendlyName)")
        }
        
        // Use IVSBroadcastSession descriptors to find cameras
        var discoveredCameras: [IVSCamera] = []
        
        // Get camera descriptors from BroadcastSession (which has both front & back)
        let cameraDescriptors = broadcastDevices.filter { $0.type == .camera }
        print("📸 [iOS Camera Discovery] Found \(cameraDescriptors.count) camera descriptors from BroadcastSession")
        
        for descriptor in cameraDescriptors {
            let posStr = descriptor.position == .front ? "FRONT" : (descriptor.position == .back ? "BACK" : "OTHER")
            
            // Method 1: Try matching from listLocalDevices by URN
            if let camera = localDevices.first(where: { $0.descriptor().urn == descriptor.urn }) as? IVSCamera {
                discoveredCameras.append(camera)
                print("📸 [iOS Camera Discovery]   ✅ Got IVSCamera via listLocalDevices: position=\(posStr), name=\(descriptor.friendlyName)")
                continue
            }
            
            // Method 2: Try getting AVCaptureDevice - if IVS SDK doesn't provide back camera,
            // we'll need to note this as a limitation
            let urnParts = descriptor.urn.split(separator: ":")
            if urnParts.count >= 2 {
                let uniqueID = String(urnParts.dropFirst().joined(separator: ":"))
                if let avDevice = AVCaptureDevice(uniqueID: uniqueID) {
                    print("📸 [iOS Camera Discovery]   📱 AVCaptureDevice exists: \(avDevice.localizedName) - but IVS SDK doesn't expose it")
                }
            }
            
            print("📸 [iOS Camera Discovery]   ❌ IVS Stages SDK limitation: Cannot get IVSCamera for: position=\(posStr), name=\(descriptor.friendlyName)")
        }
        
        // Fallback: If we couldn't match any, use what IVSDeviceDiscovery found directly
        if discoveredCameras.isEmpty {
            print("📸 [iOS Camera Discovery] ⚠️ Falling back to IVSDeviceDiscovery cameras only")
            discoveredCameras = localDevices.compactMap { device -> IVSCamera? in
                if device.descriptor().type == IVSDeviceType.camera {
                    return device as? IVSCamera
                }
                return nil
            }
        }
        
        self.availableCameras = discoveredCameras
        
        print("📸 [iOS Camera Discovery] Total CAMERAS available for use: \(self.availableCameras.count)")
        for (index, camera) in self.availableCameras.enumerated() {
            let descriptor = camera.descriptor()
            let posStr = descriptor.position == .front ? "FRONT" : (descriptor.position == .back ? "BACK" : "OTHER")
            print("📸 [iOS Camera Discovery]   Camera \(index + 1): position=\(posStr), name=\(descriptor.friendlyName), urn=\(descriptor.urn)")
        }

        // Select default camera (prefer front camera)
        if let defaultCamera = self.availableCameras.first(where: { $0.descriptor().position == .front }) ?? self.availableCameras.first {
            self.currentCameraDevice = defaultCamera
            let posStr = defaultCamera.descriptor().position == .front ? "FRONT" : (defaultCamera.descriptor().position == .back ? "BACK" : "OTHER")
            print("📸 [iOS Camera Discovery] ✅ Selected default camera: position=\(posStr), name=\(defaultCamera.descriptor().friendlyName)")
        } else {
            print("📸 [iOS Camera Discovery] ⚠️ No camera available to select as default!")
        }
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

    func initializeLocalStreams(audioConfig: IVSLocalStageStreamAudioConfiguration? = nil, videoConfig: IVSLocalStageStreamVideoConfiguration? = nil) {
        print("IVSStageManager: Initializing local streams.")

        discoverDevices()

        // Check if we need to use custom camera capture (IVS SDK limitation workaround)
        // We use custom capture if IVS SDK only provides front camera but AVFoundation has back camera
        let avSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        let hasBackCameraInAVFoundation = avSession.devices.contains { $0.position == .back }
        let hasBackCameraInIVS = self.availableCameras.contains { $0.descriptor().position == .back }
        
        self.useCustomCameraCapture = hasBackCameraInAVFoundation && !hasBackCameraInIVS
        
        if self.useCustomCameraCapture {
            print("📸 [IVSStageManager] Using CUSTOM camera capture (IVS SDK limitation workaround)")
            setupCustomCameraCapture(videoConfig: videoConfig)
        } else {
            print("📸 [IVSStageManager] Using NATIVE IVS camera")
            setupNativeCameraStream(videoConfig: videoConfig)
        }

        // Create microphone stream (same for both modes)
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
    
    private func setupNativeCameraStream(videoConfig: IVSLocalStageStreamVideoConfiguration?) {
        // Use native IVS camera (original approach)
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
            print("📸 [IVSStageManager] Native camera stream created.")
        } else {
            print("📸 [IVSStageManager] No native camera device available.")
        }
    }
    
    private func setupCustomCameraCapture(videoConfig: IVSLocalStageStreamVideoConfiguration?) {
        // Use custom AVCaptureSession -> IVSCustomImageSource approach
        print("📸 [IVSStageManager] Setting up custom camera capture...")
        
        // Initialize custom capture manager
        customCameraCapture = CustomCameraCapture()
        
        // Setup capture session for front camera initially
        guard customCameraCapture?.setupCaptureSession(for: .front) == true else {
            print("📸 [IVSStageManager] ❌ Failed to setup custom capture session")
            return
        }
        
        // Create a temporary broadcast session just to create the custom image source
        // The custom image source will be used with the stage
        let broadcastConfig = IVSBroadcastConfiguration()
        do {
            try broadcastConfig.video.setSize(CGSize(width: 720, height: 1280))
            try broadcastConfig.video.setTargetFramerate(30)
        } catch {
            print("📸 [IVSStageManager] Error configuring broadcast: \(error)")
        }
        
        // Create broadcast session to get custom image source
        do {
            let tempSession = try IVSBroadcastSession(configuration: broadcastConfig, descriptors: nil, delegate: nil)
            let imageSource = tempSession.createImageSource(withName: "customCamera")
            
            self.customImageSource = imageSource
            self.customCameraCapture?.customImageSource = imageSource
            
            // Create local stage stream with the custom image source
            let finalVideoConfig: IVSLocalStageStreamVideoConfiguration = videoConfig ?? {
                let config = IVSLocalStageStreamVideoConfiguration()
                do {
                    try config.setSize(CGSize(width: 720, height: 1280))
                } catch {
                    print("Error setting video config: \(error)")
                }
                return config
            }()
            
            let streamConfig = IVSLocalStageStreamConfiguration()
            streamConfig.video = finalVideoConfig
            
            self.cameraStream = IVSLocalStageStream(device: imageSource, config: streamConfig)
            self.cameraStream?.delegate = self
            
            // Start capturing
            customCameraCapture?.startCapture()
            
            print("📸 [IVSStageManager] ✅ Custom camera capture setup complete!")
        } catch {
            print("📸 [IVSStageManager] ❌ Error creating broadcast session for custom source: \(error)")
        }
    }

    func initializeStage(audioConfig: IVSLocalStageStreamAudioConfiguration? = nil, videoConfig: IVSLocalStageStreamVideoConfiguration? = nil) {
        // This method is now primarily for setting up non-device-related configurations if any were to be added.
        // For now, it's a placeholder to maintain API consistency.
        print("IVSStageManager: Stage initialized (configuration settings).")
    }

    func joinStage(token: String, targetParticipantId: String? = nil) {
        self.targetParticipantId = targetParticipantId

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
        print("📸 [iOS Camera Swap] swapCamera() called")
        print("📸 [iOS Camera Swap] Using custom camera capture: \(self.useCustomCameraCapture)")
        
        // If using custom camera capture, use that for swap
        if self.useCustomCameraCapture {
            swapCameraCustom()
            return
        }
        
        // Otherwise use native IVS camera swap
        swapCameraNative()
    }
    
    private func swapCameraCustom() {
        print("📸 [iOS Camera Swap] Using CUSTOM camera swap")
        
        guard let capture = self.customCameraCapture else {
            print("📸 [iOS Camera Swap] ❌ Custom camera capture not initialized")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "Custom camera capture not initialized."])
            return
        }
        
        let currentPos = capture.currentPosition == .front ? "FRONT" : "BACK"
        print("📸 [iOS Camera Swap] Current position: \(currentPos)")
        
        if capture.swapCamera() {
            let newPos = capture.currentPosition == .front ? "FRONT" : "BACK"
            print("📸 [iOS Camera Swap] ✅ Custom camera swapped to: \(newPos)")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapped", body: ["newCameraPosition": newPos])
        } else {
            print("📸 [iOS Camera Swap] ❌ Failed to swap custom camera")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "Failed to swap camera."])
        }
    }
    
    private func swapCameraNative() {
        print("📸 [iOS Camera Swap] Using NATIVE camera swap")
        print("📸 [iOS Camera Swap] Available cameras count: \(self.availableCameras.count)")
        
        // Log all available cameras for debugging
        for (index, camera) in self.availableCameras.enumerated() {
            let positionString = camera.descriptor().position == .front ? "FRONT" : (camera.descriptor().position == .back ? "BACK" : "UNSPECIFIED")
            print("📸 [iOS Camera Swap]   Available camera \(index + 1): position=\(positionString), name=\(camera.descriptor().friendlyName)")
        }
        
        guard self.cameraStream != nil else {
            print("📸 [iOS Camera Swap] ❌ Camera stream not initialized. Cannot swap camera.")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "Camera stream not initialized."])
            return
        }

        guard let currentCamDevice = self.currentCameraDevice as? IVSCamera else {
            print("📸 [iOS Camera Swap] ❌ Current camera device is not set or not an IVSCamera.")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "Current camera device not set."])
            return
        }
        
        let currentPositionString = currentCamDevice.descriptor().position == .front ? "FRONT" : (currentCamDevice.descriptor().position == .back ? "BACK" : "UNSPECIFIED")
        print("📸 [iOS Camera Swap] Current camera: position=\(currentPositionString), name=\(currentCamDevice.descriptor().friendlyName)")

        // Determine the new camera to switch to (e.g., front to back or vice-versa)
        let targetPosition: IVSDevicePosition = (currentCamDevice.descriptor().position == .front) ? .back : .front
        let targetPositionString = targetPosition == .front ? "FRONT" : (targetPosition == .back ? "BACK" : "UNSPECIFIED")
        print("📸 [iOS Camera Swap] Target position: \(targetPositionString)")
        
        guard let newCamera = self.availableCameras.first(where: { $0.descriptor().position == targetPosition }) ?? self.availableCameras.first(where: { $0.descriptor().urn != currentCamDevice.descriptor().urn }) else {
            print("📸 [iOS Camera Swap] ❌ No other camera available to swap to, or only one camera exists.")
            delegate?.stageManagerDidEmitEvent(eventName: "onCameraSwapError", body: ["reason": "No other camera available."])
            return
        }

        if newCamera.descriptor().urn == currentCamDevice.descriptor().urn {
            print("📸 [iOS Camera Swap] ⚠️ Selected new camera is the same as the current one. No swap needed.")
            return
        }
        
        let newPositionString = newCamera.descriptor().position == .front ? "FRONT" : (newCamera.descriptor().position == .back ? "BACK" : "UNSPECIFIED")
        print("📸 [iOS Camera Swap] Attempting to swap from \(currentPositionString) (\(currentCamDevice.descriptor().friendlyName)) to \(newPositionString) (\(newCamera.descriptor().friendlyName))")

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
    
    // MARK: - Picture-in-Picture Public API
    
    /// Enable PiP with the given options
    @available(iOS 15.0, *)
    func enablePictureInPicture(options: [String: Any]?) {
        var pipOpts = PiPOptions()
        
        if let autoEnter = options?["autoEnterOnBackground"] as? Bool {
            pipOpts.autoEnterOnBackground = autoEnter
        }
        
        if let sourceView = options?["sourceView"] as? String {
            pipOpts.sourceView = sourceView == "local" ? .local : .remote
        }
        
        if let aspectRatio = options?["preferredAspectRatio"] as? [String: Any],
           let width = aspectRatio["width"] as? CGFloat,
           let height = aspectRatio["height"] as? CGFloat {
            pipOpts.preferredAspectRatio = CGSize(width: width, height: height)
        }
        
        self._pipOptions = pipOpts
        
        let success = pipController.enable(options: pipOpts)
        
        if success {
            // Setup frame forwarding based on source view
            setupPiPFrameCapture()
        }
    }
    
    /// Disable PiP
    @available(iOS 15.0, *)
    func disablePictureInPicture() {
        pipController.disable()
        cleanupPiPFrameCapture()
    }
    
    /// Start PiP manually
    @available(iOS 15.0, *)
    func startPictureInPicture() {
        pipController.start()
    }
    
    /// Stop PiP manually
    @available(iOS 15.0, *)
    func stopPictureInPicture() {
        pipController.stop()
    }
    
    /// Check if PiP is currently active
    @available(iOS 15.0, *)
    func isPictureInPictureActive() -> Bool {
        return pipController.isActive
    }
    
    /// Check if PiP is enabled
    @available(iOS 15.0, *)
    func isPictureInPictureEnabled() -> Bool {
        return pipController.isEnabled
    }
    
    /// Set the target view for PiP (used for remote stream capture)
    @available(iOS 15.0, *)
    func setPiPTargetView(_ view: UIView?) {
        self.pipTargetView = view
        
        if let view = view, pipController.isEnabled, _pipOptions.sourceView == .remote {
            // Start view capture for remote stream
            pipController.startViewCapture(from: view)
            print("🖼️ [PiP] Set target view for remote stream capture")
        }
    }
    
    /// Register the local preview view (ExpoIVSStagePreviewView) for broadcaster PiP
    /// This should be called when the local preview view is set up
    func registerLocalPreviewView(_ view: UIView?) {
        self.localPreviewView = view
        print("🖼️ [PiP] Registered local preview view: \(view != nil ? "set" : "cleared")")
        
        // If PiP is already enabled for local source, set up the frame capture now
        if #available(iOS 15.0, *) {
            if pipController.isEnabled, _pipOptions.sourceView == .local, let view = view {
                setupLocalCameraPiP(sourceView: view)
            }
        }
    }
    
    // MARK: - PiP Frame Capture Setup
    
    @available(iOS 15.0, *)
    private func setupPiPFrameCapture() {
        if _pipOptions.sourceView == .local {
            // For local camera (broadcaster mode)
            if let sourceView = localPreviewView {
                setupLocalCameraPiP(sourceView: sourceView)
            } else {
                print("🖼️ [PiP] Warning: Local preview view not registered yet. PiP will be set up when view is registered.")
            }
        } else {
            // For remote streams, use IVSImageDevice frame callback
            updatePiPSourceIfNeeded()
        }
    }
    
    /// Set up PiP for local camera with the given source view
    @available(iOS 15.0, *)
    private func setupLocalCameraPiP(sourceView: UIView) {
        print("🖼️ [PiP] Setting up local camera PiP with source view")
        
        // First, set up the Video Call API source view
        pipController.setupWithSourceView(sourceView)
        pipTargetView = sourceView
        
        // IMPORTANT: Always use IVSImageDevice frame callback from the camera stream
        // This works better in background than relying on AVCaptureSession delegate
        // because the IVS SDK manages the frame pipeline internally
        guard let stream = cameraStream, let imageDevice = stream.device as? IVSImageDevice else {
            print("🖼️ [PiP] Warning: Camera stream not available for PiP frame callback")
            
            // Fallback to AVCaptureSession delegate for custom capture only
            if useCustomCameraCapture {
                customCameraCapture?.pipFrameSource = self
                print("🖼️ [PiP] Using fallback: AVCaptureSession delegate (may freeze in background)")
            }
            return
        }
        
        // Use IVSImageDevice frame callback - this works for both native IVS camera
        // and custom capture (where the device is IVSCustomImageSource)
        setupFrameCallbackOnDevice(imageDevice)
        
        let deviceType = useCustomCameraCapture ? "IVSCustomImageSource" : "native IVS camera"
        print("🖼️ [PiP] Setup local camera frame capture via IVSImageDevice (\(deviceType))")
    }
    
    /// Set up frame callback on an IVSImageDevice without changing the source view
    @available(iOS 15.0, *)
    private func setupFrameCallbackOnDevice(_ device: IVSImageDevice) {
        // If we are already attached to this device, do nothing
        if currentPiPDevice === device {
            print("🖼️ [PiP] Already attached to this device, skipping")
            return
        }
        
        // If attached to another device, detach first
        if let oldDevice = currentPiPDevice {
            oldDevice.setOnFrameCallback(nil)
            print("🖼️ [PiP] Detached from previous device")
        }
        
        currentPiPDevice = device
        currentPiPSourceDeviceUrn = device.descriptor().urn
        
        print("🖼️ [PiP] Setting up frame callback on device: \(device.descriptor().urn)")
        
        // Set frame callback to receive CVPixelBuffers
        // Use a dedicated queue for frame processing
        let frameQueue = DispatchQueue(label: "com.ivs.pip.frameCallback", qos: .userInteractive)
        
        // Track frame count for debugging
        var deviceFrameCount = 0
        
        device.setOnFrameCallbackQueue(frameQueue, includePixelBuffer: true) { [weak self] frame in
            guard let self = self else { return }
            
            deviceFrameCount += 1
            
            // Log periodically to track if frames are coming
            if deviceFrameCount == 1 || deviceFrameCount % 150 == 0 { // Log every 5 seconds at 30fps
                let isBackground = UIApplication.shared.applicationState == .background
                print("🖼️ [PiP] IVSImageDevice frame #\(deviceFrameCount), background: \(isBackground), hasPixelBuffer: \(frame.pixelBuffer != nil)")
            }
            
            if let pixelBuffer = frame.pixelBuffer {
                self.pipController.enqueueFrame(pixelBuffer)
            }
        }
        
        print("🖼️ [PiP] Frame callback registered on device")
    }
    
    @available(iOS 15.0, *)
    private func cleanupPiPFrameCapture() {
        // Clear custom camera capture delegate
        customCameraCapture?.pipFrameSource = nil
        
        // Clear IVS device callback
        if let device = currentPiPDevice {
            // Remove the callback
            device.setOnFrameCallback(nil)
            print("🖼️ [PiP] Removed frame callback from device: \(device.descriptor().urn)")
        }
        
        currentPiPDevice = nil
        currentPiPSourceDeviceUrn = nil
        pipTargetView = nil
        pipHasValidSourceView = false
    }
    
    /// Attach frame callback to an IVS Image Device
    @available(iOS 15.0, *)
    private func attachToDevice(_ device: IVSImageDevice, sourceView: UIView? = nil) {
        // If we are already attached to this device AND have a valid source view, do nothing
        if currentPiPDevice === device && pipHasValidSourceView {
            print("🖼️ [PiP] Already attached to device with valid source view, skipping")
            return
        }
        
        // If attached to another device, detach first
        if let oldDevice = currentPiPDevice, oldDevice !== device {
            oldDevice.setOnFrameCallback(nil)
            print("🖼️ [PiP] Detached from previous device")
        }
        
        currentPiPDevice = device
        currentPiPSourceDeviceUrn = device.descriptor().urn
        
        print("🖼️ [PiP] Attaching frame callback to device: \(device.descriptor().urn)")
        
        // IMPORTANT: Set up the Video Call API source view
        // This is required for the PiP window to appear correctly
        if let view = sourceView {
            pipController.setupWithSourceView(view)
            pipTargetView = view
            pipHasValidSourceView = true
            print("🖼️ [PiP] Set up with provided source view (VALID)")
        } else {
            // For remote streams, device.previewView() returns an internal view that's not visible
            // We should prefer finding a registered remote view first
            if let remoteView = remoteViews.compactMap({ $0.value }).first(where: { $0.currentRenderedDeviceUrn == device.descriptor().urn }) {
                pipController.setupWithSourceView(remoteView as UIView)
                pipTargetView = remoteView.previewViewForPiP ?? remoteView
                pipHasValidSourceView = true
                print("🖼️ [PiP] Set up with matching remote view container (VALID)")
            } else if let anyRenderingView = remoteViews.compactMap({ $0.value }).first(where: { $0.isRenderingVideo }) {
                pipController.setupWithSourceView(anyRenderingView as UIView)
                pipTargetView = anyRenderingView.previewViewForPiP ?? anyRenderingView
                pipHasValidSourceView = true
                print("🖼️ [PiP] Set up with fallback rendering view (VALID)")
            } else if let anyView = remoteViews.compactMap({ $0.value }).first {
                pipController.setupWithSourceView(anyView as UIView)
                pipTargetView = anyView
                pipHasValidSourceView = true
                print("🖼️ [PiP] Set up with any available view (VALID)")
            } else {
                // Last resort: try device.previewView() - but mark as NOT valid for remote streams
                // This allows frame capture to start, but we'll re-setup when a remote view becomes available
                do {
                    let previewView = try device.previewView()
                    pipController.setupWithSourceView(previewView)
                    pipTargetView = previewView
                    // Mark as NOT valid - we need to re-setup when remote view is available
                    pipHasValidSourceView = false
                    print("🖼️ [PiP] Set up with device preview view (NOT VALID - will re-setup when remote view available)")
                } catch {
                    print("🖼️ [PiP] ERROR: Could not get any preview view: \(error)")
                    pipHasValidSourceView = false
                }
            }
        }
        
        // For remote streams, the device frame callback may not work properly
        // Use ViewFrameCapture to capture frames from the actual UIView instead
        if _pipOptions.sourceView == .remote {
            // Use view capture for remote streams - more reliable than device callback
            if let targetView = pipTargetView {
                print("🖼️ [PiP] Using ViewFrameCapture for remote stream")
                pipController.startViewCapture(from: targetView)
            } else {
                print("🖼️ [PiP] Warning: No target view for ViewFrameCapture, trying device callback")
                // Fallback to device callback
                let frameQueue = DispatchQueue(label: "com.ivs.pip.frameCallback", qos: .userInteractive)
                device.setOnFrameCallbackQueue(frameQueue, includePixelBuffer: true) { [weak self] frame in
                    guard let self = self else { return }
                    if let pixelBuffer = frame.pixelBuffer {
                        self.pipController.enqueueFrame(pixelBuffer)
                    }
                }
            }
        } else {
            // For local streams (broadcaster), use device frame callback
            print("🖼️ [PiP] Using device frame callback for local stream")
            let frameQueue = DispatchQueue(label: "com.ivs.pip.frameCallback", qos: .userInteractive)
            device.setOnFrameCallbackQueue(frameQueue, includePixelBuffer: true) { [weak self] frame in
                guard let self = self else { return }
                if let pixelBuffer = frame.pixelBuffer {
                    self.pipController.enqueueFrame(pixelBuffer)
                }
            }
        }
    }
    
    /// Update PiP source when streams change
    @available(iOS 15.0, *)
    func updatePiPSourceIfNeeded() {
        guard pipController.isEnabled, _pipOptions.sourceView == .remote else { return }
        
        // We prioritize the target participant if set, otherwise any remote video
        var candidateStream: IVSStageStream?
        var candidateSourceView: UIView?
        
        // Strategy: Find the first available video stream from a remote participant
        // 1. If targetParticipantId is set, check them first
        if let targetId = self.targetParticipantId,
           let participant = self.participants.first(where: { $0.info.participantId == targetId }) {
            candidateStream = participant.streams.first(where: { $0.device.descriptor().type == IVSDeviceType(rawValue: 5) }) // 5 = Video
        }
        
        // 2. If no target or no stream, check all participants
        if candidateStream == nil {
            for participant in self.participants {
                if let stream = participant.streams.first(where: { $0.device.descriptor().type == IVSDeviceType(rawValue: 5) }) {
                    candidateStream = stream
                    break
                }
            }
        }
        
        if let stream = candidateStream, let imageDevice = stream.device as? IVSImageDevice {
            // Found a valid video stream
            // Re-attach if: 1) different device, OR 2) same device but we don't have a valid source view yet
            let needsSetup = currentPiPSourceDeviceUrn != imageDevice.descriptor().urn || !pipHasValidSourceView
            
            if needsSetup {
                let isNewDevice = currentPiPSourceDeviceUrn != imageDevice.descriptor().urn
                let reason = isNewDevice ? "new device" : "need valid source view"
                print("🖼️ [PiP] Setting up PiP for remote video stream (\(reason)): \(imageDevice.descriptor().urn)")
                print("🖼️ [PiP]   pipHasValidSourceView: \(pipHasValidSourceView)")
                
                // Debug: Log all registered remote views and their URNs
                print("🖼️ [PiP] Registered remote views: \(remoteViews.count)")
                for (index, viewWrapper) in remoteViews.enumerated() {
                    if let view = viewWrapper.value {
                        print("🖼️ [PiP]   View \(index): URN=\(view.currentRenderedDeviceUrn ?? "nil"), isRendering=\(view.isRenderingVideo)")
                    }
                }
                
                // Try to find the remote view that's rendering this stream
                if let remoteView = remoteViews.compactMap({ $0.value }).first(where: { $0.currentRenderedDeviceUrn == imageDevice.descriptor().urn }) {
                    candidateSourceView = remoteView as UIView
                    print("🖼️ [PiP] Found matching remote view for source")
                } else {
                    // Fallback: Use ANY remote view that's rendering video
                    if let anyRenderingView = remoteViews.compactMap({ $0.value }).first(where: { $0.isRenderingVideo }) {
                        candidateSourceView = anyRenderingView as UIView
                        print("🖼️ [PiP] Using fallback remote view (URN didn't match but view is rendering)")
                    } else if let anyView = remoteViews.compactMap({ $0.value }).first {
                        // Last resort: use any registered view
                        candidateSourceView = anyView as UIView
                        print("🖼️ [PiP] Using any available remote view as last resort")
                    } else {
                        print("🖼️ [PiP] No remote views available yet - will retry when view registers")
                    }
                }
                
                attachToDevice(imageDevice, sourceView: candidateSourceView)
            }
        } else {
            // No candidate stream found - log why
            if currentPiPDevice == nil {
                print("🖼️ [PiP] No active remote video stream found yet")
                print("🖼️ [PiP]   Total participants: \(participants.count)")
                for p in participants {
                    print("🖼️ [PiP]   Participant \(p.info.participantId ?? "nil"): \(p.streams.count) streams")
                    for s in p.streams {
                        print("🖼️ [PiP]     Stream type: \(s.device.descriptor().type.rawValue), URN: \(s.device.descriptor().urn)")
                    }
                }
            }
        }
    }
    
    /// Called by ExpoIVSRemoteStreamView when a stream finishes rendering
    func notifyRemoteStreamRendered() {
        if #available(iOS 15.0, *) {
            updatePiPSourceIfNeeded()
        }
    }
    
    // Public getter for the camera stream so the View can access it
    public func getCameraStream() -> IVSLocalStageStream? {
        return self.cameraStream
    }
    
    public func isUsingCustomCameraCapture() -> Bool {
        return self.useCustomCameraCapture
    }
    
    public func getCustomCameraPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return self.customCameraCapture?.previewLayer
    }
    
    public func getCurrentCameraPosition() -> String {
        if self.useCustomCameraCapture {
            return self.customCameraCapture?.currentPosition == .front ? "front" : "back"
        } else if let camera = self.currentCameraDevice as? IVSCamera {
            return camera.descriptor().position == .front ? "front" : "back"
        }
        return "unknown"
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

        if let leavingParticipant = self.participants.first(where: { $0.info.participantId == participant.participantId }) {
            let removedUrns = leavingParticipant.streams.map { $0.device.descriptor().urn }
            for viewWrapper in self.remoteViews {
                if let view = viewWrapper.value, let renderedUrn = view.currentRenderedDeviceUrn, removedUrns.contains(renderedUrn) {
                    print("🧠 [MANAGER] A participant left. Commanding their view to clear.")
                    view.clearStream()
                }
            }
        }

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
            
            // Update PiP source if needed
            if #available(iOS 15.0, *) {
                updatePiPSourceIfNeeded()
            }
        }
        
        delegate?.stageManagerDidEmitEvent(eventName: "onParticipantStreamsAdded", body: body)
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didRemove streams: [IVSStageStream]) {
        print("IVSStageManager Renderer: Participant \(participant.participantId ?? "N/A") removed \(streams.count) streams.")

        if participant.isLocal { return }
        
        let removedUrns = streams.map { $0.device.descriptor().urn }

        for viewWrapper in self.remoteViews {
            if let view = viewWrapper.value, let renderedUrn = view.currentRenderedDeviceUrn, removedUrns.contains(renderedUrn) {
                print("🧠 [MANAGER] A stream being rendered was removed. Commanding view to clear.")
                // Tell the view to clear itself.
                view.clearStream()
            }
        }

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
        
        // Update PiP source if the removed stream was being used
        if #available(iOS 15.0, *) {
            updatePiPSourceIfNeeded()
        }

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

// MARK: - PiPFrameSource Implementation
extension IVSStageManager: PiPFrameSource {
    private static var frameReceivedCount: Int = 0
    
    func didReceiveFrame(_ pixelBuffer: CVPixelBuffer) {
        if #available(iOS 15.0, *) {
            IVSStageManager.frameReceivedCount += 1
            // Log periodically to confirm frames are flowing
            if IVSStageManager.frameReceivedCount == 1 || IVSStageManager.frameReceivedCount % 300 == 0 {
                print("🖼️ [PiP] Received pixel buffer frame #\(IVSStageManager.frameReceivedCount)")
            }
            pipController.enqueueFrame(pixelBuffer)
        }
    }
    
    func didReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if #available(iOS 15.0, *) {
            IVSStageManager.frameReceivedCount += 1
            // Log periodically to confirm frames are flowing
            if IVSStageManager.frameReceivedCount == 1 || IVSStageManager.frameReceivedCount % 300 == 0 {
                print("🖼️ [PiP] Received sample buffer frame #\(IVSStageManager.frameReceivedCount)")
            }
            pipController.enqueueSampleBuffer(sampleBuffer)
        }
    }
}

// MARK: - IVSPictureInPictureControllerDelegate Implementation
@available(iOS 15.0, *)
extension IVSStageManager: IVSPictureInPictureControllerDelegate {
    func pictureInPictureDidStart() {
        delegate?.stageManagerDidEmitEvent(eventName: "onPiPStateChanged", body: ["state": "started"])
    }
    
    func pictureInPictureDidStop() {
        delegate?.stageManagerDidEmitEvent(eventName: "onPiPStateChanged", body: ["state": "stopped"])
    }
    
    func pictureInPictureWillRestore() {
        delegate?.stageManagerDidEmitEvent(eventName: "onPiPStateChanged", body: ["state": "restored"])
    }
    
    func pictureInPictureDidFail(with error: String) {
        delegate?.stageManagerDidEmitEvent(eventName: "onPiPError", body: ["error": error])
    }
}

