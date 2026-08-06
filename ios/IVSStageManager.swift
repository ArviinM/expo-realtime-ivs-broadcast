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
    
    // Camera mute state (sends placeholder frames when muted)
    private(set) var isCameraMuted: Bool = false
    private var placeholderTimer: Timer?
    private var placeholderPixelBuffer: CVPixelBuffer?
    private var placeholderText: String = "Host is away"
    private let placeholderWidth: Int = 720
    private let placeholderHeight: Int = 1280
    
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
            print("📸 [CustomCameraCapture] Frame #\(captureFrameCount), background: \(isBackground), hasPiPDelegate: \(pipFrameSource != nil), muted: \(isCameraMuted)")
        }
        
        // When camera is muted, placeholder frames are sent by timer instead
        guard !isCameraMuted else { return }
        
        // Feed the sample buffer to IVS custom image source
        customImageSource?.onSampleBuffer(sampleBuffer)
        
        // Forward to PiP if enabled
        pipFrameSource?.didReceiveSampleBuffer(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame dropped - this is normal under heavy load
    }
    
    // MARK: - Camera Mute with Placeholder
    
    func setCameraMuted(_ muted: Bool, placeholderText: String? = nil) {
        guard isCameraMuted != muted else { return }
        
        isCameraMuted = muted
        
        if let text = placeholderText {
            self.placeholderText = text
            // Regenerate placeholder with new text
            placeholderPixelBuffer = nil
        }
        
        if muted {
            print("📸 [CustomCameraCapture] Camera MUTED - sending placeholder frames")
            startPlaceholderFrames()
        } else {
            print("📸 [CustomCameraCapture] Camera UNMUTED - resuming camera frames")
            stopPlaceholderFrames()
        }
    }
    
    private func startPlaceholderFrames() {
        stopPlaceholderFrames() // Clean up any existing timer
        
        // Generate placeholder if needed
        if placeholderPixelBuffer == nil {
            placeholderPixelBuffer = createPlaceholderPixelBuffer()
        }
        
        // Send placeholder frames at 15fps
        placeholderTimer = Timer.scheduledTimer(withTimeInterval: 1.0/15.0, repeats: true) { [weak self] _ in
            self?.sendPlaceholderFrame()
        }
        
        // Send one immediately
        sendPlaceholderFrame()
    }
    
    private func stopPlaceholderFrames() {
        placeholderTimer?.invalidate()
        placeholderTimer = nil
    }
    
    private func sendPlaceholderFrame() {
        guard let pixelBuffer = placeholderPixelBuffer else { return }
        
        // Create a CMSampleBuffer from the pixel buffer
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard let format = formatDescription else { return }
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        if let buffer = sampleBuffer {
            customImageSource?.onSampleBuffer(buffer)
        }
    }
    
    private func createPlaceholderPixelBuffer() -> CVPixelBuffer? {
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            placeholderWidth,
            placeholderHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("📸 [CustomCameraCapture] Failed to create placeholder pixel buffer")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: placeholderWidth,
            height: placeholderHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            print("📸 [CustomCameraCapture] Failed to create CGContext for placeholder")
            return nil
        }
        
        // Fill with dark gray background
        context.setFillColor(UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: placeholderWidth, height: placeholderHeight))
        
        // Draw text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 48, weight: .medium),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let textSize = (placeholderText as NSString).size(withAttributes: attributes)
        let textRect = CGRect(
            x: (CGFloat(placeholderWidth) - textSize.width) / 2,
            y: (CGFloat(placeholderHeight) - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        // Draw text using UIGraphics (CGContext text drawing is complex)
        UIGraphicsPushContext(context)
        // Flip context for text (CGContext has flipped Y)
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(placeholderHeight))
        context.scaleBy(x: 1, y: -1)
        (placeholderText as NSString).draw(in: textRect, withAttributes: attributes)
        context.restoreGState()
        UIGraphicsPopContext()
        
        print("📸 [CustomCameraCapture] Created placeholder frame with text: '\(placeholderText)'")
        return buffer
    }
    
    func updatePlaceholderText(_ text: String) {
        placeholderText = text
        placeholderPixelBuffer = nil // Will be regenerated on next frame
        if isCameraMuted {
            placeholderPixelBuffer = createPlaceholderPixelBuffer()
        }
    }
    
    deinit {
        stopPlaceholderFrames()
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

/// Per-tick state for computing outbound bitrate from bytesSent deltas.
/// WebRTC doesn't emit a precomputed "bitrate" key on outbound-rtp — we have
/// to delta the `bytesSent` counter between samples to derive a bitrate.
struct OutboundSnapshot {
    var bytesSent: Double
    var timestamp: TimeInterval
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

    // MARK: - Audio Device Picker / Mock Mode State

    /// JS-requested preferred input URN. Applied at stream-create time if the
    /// active session can honor it; remembered across mic re-init.
    fileprivate var preferredInputUrn: String?
    /// JS-requested software gain (0.0–5.0). 1.0 = no boost. Applied at next session activation.
    fileprivate var requestedInputGain: Float = 1.0
    /// DEBUG-only flag that swaps the camera path for a synthetic source.
    fileprivate var isMockMode: Bool = false
    /// Mock camera frame generator. Strong-held only while mock mode is active.
    fileprivate var mockCameraSource: MockCameraSource?
    /// Mock-mode custom image source on the broadcast session (created lazily).
    fileprivate var mockImageSource: IVSCustomImageSource?
    /// Holder for the throwaway broadcast session used to mint mock image sources.
    fileprivate var mockBroadcastSession: IVSBroadcastSession?

    // MARK: - Observability State

    /// 2-second timer that polls cameraStream + microphoneStream for RTC stats
    /// and emits them as onRTCStats. Lazily started when the first stream exists.
    fileprivate var rtcStatsTimer: Timer?
    /// Last-known RTC stats snapshot. Returned by snapshotRTCStats() for one-shot reads.
    fileprivate var lastRTCStats: [String: Any] = [:]
    /// Counters from the previous tick — used to compute outbound bitrate via delta.
    fileprivate var lastOutboundSnapshot: OutboundSnapshot?
    /// Print every report's key list exactly once at session start for debugging.
    fileprivate var didLogRTCKeysOnce: Bool = false
    /// Whether to stop publishing when the app goes to background.
    fileprivate var bgStopPublishing: Bool = true
    /// Subscribe mode when app is in background. Maps to IVSStageSubscribeType.
    fileprivate var bgSubscribeMode: String = "audioOnly" // 'none' | 'audioOnly' | 'audioVideo'
    /// Whether the app is currently in background (set by lifecycle observers).
    fileprivate var isAppInBackground: Bool = false

    // MARK: - Thermal Mitigation State

    /// Whether auto-downshift on thermal pressure is enabled. Opt-in from JS.
    fileprivate var thermalMitigationEnabled: Bool = false
    /// Framerate to drop to when thermal state hits .serious or .critical.
    fileprivate var thermalReducedFramerate: Int = 15
    /// Whether thermal observer is installed (idempotent).
    fileprivate var thermalObserverInstalled: Bool = false

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

    deinit {
        // Always remove the audio observers we installed in setupAudioSession()
        // to prevent leaks across module re-creates.
        NotificationCenter.default.removeObserver(self)
        mockCameraSource?.stop()
        mockCameraSource = nil
        mockImageSource = nil
        mockBroadcastSession = nil
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

    /// The currently-applied audio preset. Surfaced via setAudioPreset(_:) from JS.
    /// `videoChat` is the SDK's two-way-comms preset (AEC/NS/AGC on). Use `studio`
    /// for broadcaster mode — higher perceived loudness, no processing.
    private var currentAudioPreset: IVSStageAudioManager.UseCasePreset = .videoChat

    private func setupAudioSession() {
        // Apply the currently-stored preset. Default (videoChat) is two-way-call style;
        // setAudioPreset(.studio) from JS bumps perceived loudness and disables AEC/NS.
        stageAudioManager.setPreset(currentAudioPreset)
        print("📢 [Audio] IVSStageAudioManager preset = \(currentAudioPreset)")

        // Install audio route + interruption observers once.
        installAudioObservers()
    }

    // MARK: - Audio Observers

    private var audioObserversInstalled = false

    private func installAudioObservers() {
        guard !audioObserversInstalled else { return }
        audioObserversInstalled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        print("📢 [Audio] Installed route-change + interruption observers")
    }

    @objc private func handleAudioRouteChange(_ note: Notification) {
        let reasonRaw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) ?? .unknown
        let reasonStr: String
        switch reason {
        case .newDeviceAvailable: reasonStr = "newDeviceAvailable"
        case .oldDeviceUnavailable: reasonStr = "oldDeviceUnavailable"
        case .override: reasonStr = "override"
        case .categoryChange, .routeConfigurationChange: reasonStr = "override"
        default: reasonStr = "unknown"
        }
        var body: [String: Any] = ["reason": reasonStr]
        if let active = activeAudioInputDevice() {
            body["activeInput"] = active
        }
        delegate?.stageManagerDidEmitEvent(eventName: "onAudioRouteChanged", body: body)
        print("📢 [Audio] Route change: \(reasonStr)")
    }

    @objc private func handleAudioInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            delegate?.stageManagerDidEmitEvent(eventName: "onAudioInterruption", body: ["state": "began"])
            print("📢 [Audio] Interruption began")
        case .ended:
            var shouldResume = false
            if let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                shouldResume = opts.contains(.shouldResume)
            }
            delegate?.stageManagerDidEmitEvent(eventName: "onAudioInterruption", body: ["state": "ended", "shouldResume": shouldResume])
            print("📢 [Audio] Interruption ended, shouldResume=\(shouldResume)")
        @unknown default:
            break
        }
    }

    // MARK: - Public API (to be called from ExpoRealtimeIvsBroadcastModule)

    /// Map-based entry point called from JS. Parses dictionaries into IVS config objects.
    func initializeLocalStreams(audioConfigMap: [String: Any]?, videoConfigMap: [String: Any]?) {
        let audioCfg = parseAudioConfig(audioConfigMap)
        let videoCfg = parseVideoConfig(videoConfigMap)
        initializeLocalStreams(audioConfig: audioCfg, videoConfig: videoCfg)
    }

    /// Map-based entry point for initializeStage from JS.
    func initializeStage(audioConfigMap: [String: Any]?, videoConfigMap: [String: Any]?) {
        // Reserved for future configuration. Currently a no-op; configs are applied
        // in initializeLocalStreams() because that's when streams are constructed.
        print("IVSStageManager: initializeStage(configMaps:) — currently a no-op.")
    }

    /// Parse the JS audio config map into an IVSLocalStageStreamAudioConfiguration.
    /// Defaults: 96 kbps max bitrate (up from 64 kbps default) for clearer commerce audio.
    /// Note: the Stages SDK doesn't expose a `setChannels` API on the audio config
    /// — channel count is determined by the device. We accept the `channels` field
    /// in the JS schema for forward-compat but silently ignore it on iOS.
    private func parseAudioConfig(_ map: [String: Any]?) -> IVSLocalStageStreamAudioConfiguration {
        let cfg = IVSLocalStageStreamAudioConfiguration()
        let bitrate = (map?["maxBitrate"] as? NSNumber)?.intValue ?? 96_000
        do { try cfg.setMaxBitrate(bitrate) } catch {
            print("📢 [Audio] Failed to set audio bitrate to \(bitrate): \(error)")
        }
        return cfg
    }

    /// Default IVSLocalStageStreamVideoConfiguration when JS doesn't pass an explicit
    /// config. 720x1280 portrait, 30 fps, 0.5–2.5 Mbps. Used by every fallback path
    /// (initial setup, camera swap, mock streams) so the SDK's 15 fps default never
    /// leaks through. Keep parseVideoConfig() defaults in sync with this.
    fileprivate static func defaultVideoConfig() -> IVSLocalStageStreamVideoConfiguration {
        let cfg = IVSLocalStageStreamVideoConfiguration()
        do { try cfg.setSize(CGSize(width: 720, height: 1280)) } catch {
            print("🎥 [Video] defaultVideoConfig: failed to set size: \(error)")
        }
        do { try cfg.setTargetFramerate(30) } catch {
            print("🎥 [Video] defaultVideoConfig: failed to set framerate: \(error)")
        }
        do { try cfg.setMaxBitrate(2_500_000) } catch {
            print("🎥 [Video] defaultVideoConfig: failed to set max bitrate: \(error)")
        }
        do { try cfg.setMinBitrate(500_000) } catch {
            print("🎥 [Video] defaultVideoConfig: failed to set min bitrate: \(error)")
        }
        return cfg
    }

    /// Parse the JS video config map into an IVSLocalStageStreamVideoConfiguration.
    /// Defaults are tuned for live commerce: 720x1280 portrait, 30 fps, 0.5–2.5 Mbps.
    /// The Stages SDK ships with 15 fps as its default — too choppy for product demos —
    /// so we always set 30 fps unless JS explicitly overrides. Bitrate range gives the
    /// WebRTC adaptive encoder room to scale up on good networks and gracefully down on
    /// bad ones.
    private func parseVideoConfig(_ map: [String: Any]?) -> IVSLocalStageStreamVideoConfiguration {
        let cfg = IVSLocalStageStreamVideoConfiguration()
        let width = (map?["width"] as? NSNumber)?.intValue ?? 720
        let height = (map?["height"] as? NSNumber)?.intValue ?? 1280
        let fps = (map?["targetFramerate"] as? NSNumber)?.intValue ?? 30
        let maxBitrate = (map?["maxBitrate"] as? NSNumber)?.intValue ?? 2_500_000
        let minBitrate = (map?["minBitrate"] as? NSNumber)?.intValue ?? 500_000
        do { try cfg.setSize(CGSize(width: width, height: height)) } catch {
            print("🎥 [Video] Failed to set size \(width)x\(height): \(error)")
        }
        do { try cfg.setTargetFramerate(fps) } catch {
            print("🎥 [Video] Failed to set framerate \(fps): \(error)")
        }
        do { try cfg.setMaxBitrate(maxBitrate) } catch {
            print("🎥 [Video] Failed to set max bitrate \(maxBitrate): \(error)")
        }
        do { try cfg.setMinBitrate(minBitrate) } catch {
            print("🎥 [Video] Failed to set min bitrate \(minBitrate): \(error)")
        }
        print("🎥 [Video] Configured \(width)x\(height) @ \(fps) fps, \(minBitrate)-\(maxBitrate) bps")
        return cfg
    }

    func initializeLocalStreams(audioConfig: IVSLocalStageStreamAudioConfiguration? = nil, videoConfig: IVSLocalStageStreamVideoConfiguration? = nil) {
        print("IVSStageManager: Initializing local streams.")

        // Mock mode: short-circuit before touching AVCaptureDevice/IVSDeviceDiscovery.
        if isMockMode {
            setupMockStreams(videoConfig: videoConfig)
            return
        }

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
            // Default to 96 kbps for clearer commerce audio (SDK default is 64 kbps).
            let finalAudioConfig: IVSLocalStageStreamAudioConfiguration = audioConfig ?? {
                let cfg = IVSLocalStageStreamAudioConfiguration()
                do { try cfg.setMaxBitrate(96_000) } catch {
                    print("📢 [Audio] Failed to set default mic bitrate: \(error)")
                }
                return cfg
            }()

            let streamConfig = IVSLocalStageStreamConfiguration()
            streamConfig.audio = finalAudioConfig

            self.microphoneStream = IVSLocalStageStream(device: microphoneDevice, config: streamConfig)
            self.microphoneStream?.delegate = self
            print("Microphone stream created using discovered device.")

            // Audio level (peak/rms) is not exposed via a public API on the
            // current Stages SDK (1.36) — onAudioLevel will fire only on
            // Android. The picker UI degrades gracefully (shows "—" for Mic).

            // Apply pending preferred input now that the mic exists.
            applyPreferredAudioInputIfPossible()
        } else {
            print("No suitable microphone device found through descriptor method.")
        }
    }
    
    private func setupNativeCameraStream(videoConfig: IVSLocalStageStreamVideoConfiguration?) {
        // Use native IVS camera (original approach)
        if let camera = currentCameraDevice as? IVSCamera {
            let finalVideoConfig: IVSLocalStageStreamVideoConfiguration = videoConfig ?? Self.defaultVideoConfig()

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
            let finalVideoConfig: IVSLocalStageStreamVideoConfiguration = videoConfig ?? Self.defaultVideoConfig()
            
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
            // Begin polling RTC stats on a 2s interval for the duration of the session.
            startRTCStatsTimer()
        } catch {
            print("Error attempting to join IVSStage: \(error)")
            let nsError = error as NSError
            delegate?.stageManagerDidEmitEvent(eventName: "onStageError", body: ["code": nsError.code, "description": "Failed to join IVSStage: \(error.localizedDescription)", "source": "IVSStageManager.joinStage.joinCall", "isFatal": true])
            delegate?.stageManagerDidEmitEvent(eventName: "onStageConnectionStateChanged", body: ["state": "error", "error": "Failed to join IVSStage: \(error.localizedDescription)"])
        }
    }

    func leaveStage() {
        if self.stage != nil {
            print("IVSStageManager: Preparing to leave stage.")
            self.setStreamsPublished(published: false)

            // Emit onParticipantLeft for every non-local participant BEFORE
            // tearing the stage down. The JS-side useStageParticipants hook
            // accumulates participants via these events; if we don't emit
            // them here, the next stream's session inherits a stale list and
            // attempts to attach the remote stream view to a participant
            // that doesn't exist on the new stage → black screen.
            //
            // The SDK's own disconnected event also clears self.participants,
            // but it can fire AFTER the new joinStage() has populated stage
            // B's participants — at which point it wipes valid state. By
            // proactively emitting + clearing here, we close that race.
            for participant in self.participants where !participant.info.isLocal {
                // `participantId` is a non-optional String in the Swift
                // binding (matches the existing emit pattern in
                // `participantDidLeave` and the comparison in `removeAll`).
                let pid = participant.info.participantId
                delegate?.stageManagerDidEmitEvent(eventName: "onParticipantLeft", body: ["participantId": pid])
            }
            self.participants.removeAll()

            stage?.leave()
            stage = nil
            print("Left stage.")
        } else {
            print("IVSStageManager: Attempted to leave stage, but stage is already nil.")
        }
        // Stop polling — no point burning a 2s timer while disconnected.
        stopRTCStatsTimer()
    }

    // MARK: - Teardown Local Streams

    /// Fully releases camera and microphone hardware resources.
    /// This is the symmetric counterpart to `initializeLocalStreams()`.
    /// After calling this, `initializeLocalStreams()` must be called again
    /// before the camera or microphone can be used.
    func destroyLocalStreams() {
        print("IVSStageManager: Destroying local streams and releasing hardware.")

        // 1. Stop custom camera capture session (releases AVCaptureSession → camera hardware)
        if useCustomCameraCapture {
            customCameraCapture?.setCameraMuted(true) // Stop placeholder timer first
            customCameraCapture?.stopCapture()        // Stop AVCaptureSession
            customCameraCapture?.customImageSource = nil
            customCameraCapture = nil
            customImageSource = nil
            print("📸 [IVSStageManager] Custom camera capture destroyed.")
        }

        // 2. Mute and release native IVS camera stream
        cameraStream?.setMuted(true)
        cameraStream = nil

        // 3. Mute and release microphone stream
        microphoneStream?.setMuted(true)
        microphoneStream = nil

        // 4. Reset state so initializeLocalStreams() can be called again cleanly
        currentCameraDevice = nil
        availableCameras = []
        useCustomCameraCapture = false

        print("IVSStageManager: ✅ Local streams destroyed. Camera and microphone released.")
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
        let defaultVideoConfig: IVSLocalStageStreamVideoConfiguration = Self.defaultVideoConfig()

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
        print("📺 [MANAGER] ====== Remote view registered ======")
        print("📺 [MANAGER] Total view refs: \(self.remoteViews.count)")
        print("📺 [MANAGER] Participants count: \(self.participants.count)")
        for p in self.participants {
            print("📺 [MANAGER]   Participant: \(p.info.participantId ?? "nil"), streams: \(p.streams.count)")
            for s in p.streams {
                print("📺 [MANAGER]     Stream URN: \(s.device.descriptor().urn), type: \(s.device.descriptor().type.rawValue)")
            }
        }
        
        // A view was just added. It might be the canvas we were waiting for.
        // Immediately try to assign any streams that are waiting in our state.
        self.assignStreamsToAvailableViews()
        
        // Also schedule a delayed retry in case streams haven't arrived yet
        // This handles race conditions where view mounts before stream info
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // Check if the view still exists and needs assignment
            if view.currentRenderedDeviceUrn == nil && !self.participants.isEmpty {
                print("📺 [MANAGER] Delayed retry - view still needs stream assignment")
                self.assignStreamsToAvailableViews()
            }
        }
    }
    
    func unregisterRemoteView(_ view: ExpoIVSRemoteStreamView) {
        let previousUrn = view.currentRenderedDeviceUrn
        print("📺 [MANAGER] Unregistering view that was rendering: \(previousUrn ?? "nil")")
        
        // Check if this view was the PiP source view - if so, invalidate it
        if #available(iOS 15.0, *) {
            if pipTargetView === view || pipTargetView === view.previewViewForPiP {
                print("📺 [MANAGER] This view was the PiP source - invalidating PiP source state")
                setPiPSourceValidity(false)
                pipTargetView = nil
            }
        }
        
        // Remove the view from our list
        self.remoteViews.removeAll { $0.value === view }
        print("📺 [MANAGER] View unregistered. Remaining views: \(self.remoteViews.count)")
        
        // If this view was rendering a stream, that stream is now available
        // Schedule a reassignment in case other views are waiting
        if previousUrn != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("📺 [MANAGER] Stream released, checking for waiting views...")
                self.assignStreamsToAvailableViews()
            }
        }
    }

    private func assignStreamsToAvailableViews() {
        print("🧠 [MANAGER] ========== assignStreamsToAvailableViews called ==========")
        
        // Clean up dead weak references first
        let beforeCount = self.remoteViews.count
        self.remoteViews.removeAll { $0.value == nil }
        let removedCount = beforeCount - self.remoteViews.count
        if removedCount > 0 {
            print("🧠 [MANAGER] Cleaned up \(removedCount) dead weak references")
        }
        
        // Also check for views that are no longer in a window (orphaned)
        // These views should release their streams
        for viewWrapper in self.remoteViews {
            if let view = viewWrapper.value,
               view.currentRenderedDeviceUrn != nil,
               view.window == nil {
                print("🧠 [MANAGER] Found orphaned view (not in window), clearing its stream")
                view.clearStream()
            }
        }
        
        // Get a set of all streams that are already being rendered by VALID views
        let renderedUrns = Set(self.remoteViews.compactMap { wrapper -> String? in
            guard let view = wrapper.value,
                  view.window != nil,  // Only count views that are actually visible
                  let urn = view.currentRenderedDeviceUrn else {
                return nil
            }
            return urn
        })
        print("🧠 [MANAGER] Currently rendered URNs (by visible views): \(renderedUrns)")
        
        // Find all views that are not currently rendering anything AND are in a window
        let availableViews = self.remoteViews.compactMap { $0.value }.filter { 
            $0.currentRenderedDeviceUrn == nil && $0.window != nil 
        }
        
        // Log all views and their state
        print("🧠 [MANAGER] All registered views:")
        for (index, viewWrapper) in self.remoteViews.enumerated() {
            if let view = viewWrapper.value {
                let inWindow = view.window != nil
                print("🧠 [MANAGER]   View \(index): rendering=\(view.currentRenderedDeviceUrn ?? "nil"), inWindow=\(inWindow)")
            } else {
                print("🧠 [MANAGER]   View \(index): <deallocated>")
            }
        }
        
        // Find all video streams that are not currently being rendered.
        var availableStreams: [(participantId: String, stream: IVSStageStream)] = []
        print("🧠 [MANAGER] Participants and their streams:")
        for p in self.participants {
            print("🧠 [MANAGER]   Participant: \(p.info.participantId ?? "nil")")
            for s in p.streams {
                let urn = s.device.descriptor().urn
                let type = s.device.descriptor().type.rawValue
                let isVideo = type == 5
                let alreadyRendered = renderedUrns.contains(urn)
                print("🧠 [MANAGER]     Stream URN: \(urn), type: \(type), isVideo: \(isVideo), alreadyRendered: \(alreadyRendered)")
                
                if isVideo && !alreadyRendered {
                    availableStreams.append((p.info.participantId, s))
                }
            }
        }
        
        // If a target participant is specified, prioritize their stream.
        if let targetId = self.targetParticipantId {
            availableStreams.sort { a, _ in a.participantId == targetId }
        }
        
        print("🧠 [MANAGER] Summary: \(self.remoteViews.count) view refs, \(availableViews.count) available views (in window), \(availableStreams.count) available streams")

        // Assign each available stream to an available view.
        if availableViews.isEmpty && !availableStreams.isEmpty {
            print("🧠 [MANAGER] ⚠️ No available views but streams exist! Views might need to register.")
        } else if !availableViews.isEmpty && availableStreams.isEmpty && !self.participants.isEmpty {
            // Views want streams but all streams are "taken" - this might be a stale state
            // Force a cleanup and retry
            print("🧠 [MANAGER] ⚠️ Views available but streams appear taken. Checking for stale state...")
            
            // Check if any "rendering" view is actually orphaned
            var freedSomething = false
            for viewWrapper in self.remoteViews {
                if let view = viewWrapper.value,
                   view.currentRenderedDeviceUrn != nil,
                   view.window == nil {
                    print("🧠 [MANAGER] Freeing stream from orphaned view")
                    view.clearStream()
                    freedSomething = true
                }
            }
            
            // If we freed something, retry assignment
            if freedSomething {
                print("🧠 [MANAGER] Retrying assignment after cleanup...")
                // Recursive call but with cleaned state
                DispatchQueue.main.async { [weak self] in
                    self?.assignStreamsToAvailableViews()
                }
                return
            }
        }
        
        for (view, streamInfo) in zip(availableViews, availableStreams) {
            print("🧠 [MANAGER] ✅ Assigning stream \(streamInfo.stream.device.descriptor().urn) to view")
            view.renderStream(participantId: streamInfo.participantId, deviceUrn: streamInfo.stream.device.descriptor().urn)
        }
        print("🧠 [MANAGER] ========== assignStreamsToAvailableViews complete ==========")
    }
    // --- END NEW VIEW MANAGEMENT API ---


    func setMicrophoneMuted(muted: Bool) {
        microphoneStream?.setMuted(muted)
        print("Microphone muted: \(muted)")
    }
    
    func setCameraMuted(muted: Bool, placeholderText: String?) {
        // For custom camera capture, we send placeholder frames
        if useCustomCameraCapture, let customCapture = customCameraCapture {
            customCapture.setCameraMuted(muted, placeholderText: placeholderText)
        } else {
            // For native IVS camera, just mute the stream
            cameraStream?.setMuted(muted)
        }
        print("Camera muted: \(muted)")
        
        // Emit event for React Native
        delegate?.stageManagerDidEmitEvent(eventName: "onCameraMuteStateChanged", body: [
            "muted": muted,
            "placeholderActive": useCustomCameraCapture && muted
        ])
    }
    
    func isCameraMuted() -> Bool {
        if useCustomCameraCapture, let customCapture = customCameraCapture {
            return customCapture.isCameraMuted
        }
        return cameraStream?.isMuted ?? false
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

    /// Single chokepoint for `pipHasValidSourceView` writes so JS can observe
    /// when the remote PiP source becomes VALID (a real rendering remote view)
    /// vs the invalid `device.previewView()` placeholder fallback that produces
    /// a frozen/black PiP window. Emits `onPiPSourceValidityChanged` only on a
    /// true<->false change, and always on the main thread (writes can originate
    /// from background frame-callback queues).
    private func setPiPSourceValidity(_ valid: Bool) {
        let was = pipHasValidSourceView
        pipHasValidSourceView = valid
        guard was != valid else { return }
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.stageManagerDidEmitEvent(
                eventName: "onPiPSourceValidityChanged",
                body: ["valid": valid]
            )
        }
    }

    /// Whether the remote PiP source view is currently a real rendering view
    /// (true) vs the `device.previewView()` fallback (false). Diagnostic only —
    /// rely on the `onPiPSourceValidityChanged` event for the authoritative signal.
    func isPiPRemoteSourceValid() -> Bool {
        return pipHasValidSourceView
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
    //
    // PiP uses the Video Call API which requires:
    // 1. setupWithSourceView() - sets the visible view that shows video in the app
    // 2. enqueueFrame() - feeds video frames to the PiP display layer
    //
    // LOCAL (Broadcaster) PiP:
    // - Source view: ExpoIVSStagePreviewView (local camera preview)
    // - Frame source: IVSImageDevice from cameraStream (IVSCamera or IVSCustomImageSource)
    // - The device frame callback provides CVPixelBuffers directly
    //
    // REMOTE (Viewer) PiP:
    // - Source view: ExpoIVSRemoteStreamView (remote video preview)
    // - Frame source: IVSImageDevice from remote participant's video stream
    // - The device frame callback provides CVPixelBuffers from WebRTC
    //
    // Both use the SAME Video Call API approach - the only difference is:
    // - Which view is used as the source view
    // - Which IVSImageDevice provides the frames
    
    @available(iOS 15.0, *)
    private func setupPiPFrameCapture() {
        if _pipOptions.sourceView == .local {
            // LOCAL/BROADCASTER MODE
            // Use the local camera preview view and camera stream device
            if let sourceView = localPreviewView {
                setupLocalCameraPiP(sourceView: sourceView)
            } else {
                print("🖼️ [PiP] Warning: Local preview view not registered yet. PiP will be set up when view is registered.")
            }
        } else {
            // REMOTE/VIEWER MODE
            // Use the remote stream view and remote participant's video device
            updatePiPSourceIfNeeded()
        }
    }
    
    /// Set up PiP for local camera with the given source view
    @available(iOS 15.0, *)
    private func setupLocalCameraPiP(sourceView: UIView) {
        print("🖼️ [PiP] Setting up local camera PiP with source view")
        
        // Note: For custom camera capture, ExpoIVSStagePreviewView now adds a hidden
        // IVSImagePreviewView for better PiP compatibility. The sourceView should
        // already contain this when using custom capture.
        
        // Set up the Video Call API source view
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
        setPiPSourceValidity(false)
    }
    
    /// Attach frame callback to an IVS Image Device (primarily for REMOTE streams)
    ///
    /// This function is called for remote/viewer PiP:
    /// 1. Sets up the Video Call API source view (ExpoIVSRemoteStreamView)
    /// 2. Attaches frame callback to the remote participant's IVSImageDevice
    /// 3. The device callback provides frames from the WebRTC stream
    ///
    /// For local/broadcaster PiP, use setupLocalCameraPiP() instead.
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
            setPiPSourceValidity(true)
            print("🖼️ [PiP] Set up with provided source view (VALID)")
        } else {
            // For remote streams, device.previewView() returns an internal view that's not visible
            // We should prefer finding a registered remote view first
            if let remoteView = remoteViews.compactMap({ $0.value }).first(where: { $0.currentRenderedDeviceUrn == device.descriptor().urn }) {
                pipController.setupWithSourceView(remoteView as UIView)
                pipTargetView = remoteView.previewViewForPiP ?? remoteView
                setPiPSourceValidity(true)
                print("🖼️ [PiP] Set up with matching remote view container (VALID)")
            } else if let anyRenderingView = remoteViews.compactMap({ $0.value }).first(where: { $0.isRenderingVideo }) {
                pipController.setupWithSourceView(anyRenderingView as UIView)
                pipTargetView = anyRenderingView.previewViewForPiP ?? anyRenderingView
                setPiPSourceValidity(true)
                print("🖼️ [PiP] Set up with fallback rendering view (VALID)")
            } else if let anyView = remoteViews.compactMap({ $0.value }).first {
                pipController.setupWithSourceView(anyView as UIView)
                pipTargetView = anyView
                setPiPSourceValidity(true)
                print("🖼️ [PiP] Set up with any available view (VALID)")
            } else {
                // Last resort: try device.previewView() - but mark as NOT valid for remote streams
                // This allows frame capture to start, but we'll re-setup when a remote view becomes available
                do {
                    let previewView = try device.previewView()
                    pipController.setupWithSourceView(previewView)
                    pipTargetView = previewView
                    // Mark as NOT valid - we need to re-setup when remote view is available
                    setPiPSourceValidity(false)
                    print("🖼️ [PiP] Set up with device preview view (NOT VALID - will re-setup when remote view available)")
                } catch {
                    print("🖼️ [PiP] ERROR: Could not get any preview view: \(error)")
                    setPiPSourceValidity(false)
                }
            }
        }
        
        // Set frame callback to receive CVPixelBuffers (only if not already set on this device)
        let frameQueue = DispatchQueue(label: "com.ivs.pip.frameCallback", qos: .userInteractive)
        device.setOnFrameCallbackQueue(frameQueue, includePixelBuffer: true) { [weak self] frame in
            guard let self = self else { return }
            
            if let pixelBuffer = frame.pixelBuffer {
                self.pipController.enqueueFrame(pixelBuffer)
            }
        }
    }
    
    /// Update PiP source when streams change (REMOTE/VIEWER mode only)
    ///
    /// This function finds the appropriate remote video stream and view, then calls
    /// attachToDevice() to set up the Video Call API for viewer PiP.
    ///
    /// Called when:
    /// - PiP is enabled with sourceView = .remote
    /// - A remote participant adds video streams
    /// - ExpoIVSRemoteStreamView starts rendering a stream
    @available(iOS 15.0, *)
    func updatePiPSourceIfNeeded() {
        guard pipController.isEnabled, _pipOptions.sourceView == .remote else { return }
        
        // Safety check: If we think we have a valid source view but it's not in a window anymore,
        // invalidate it so we can set up with a new view
        if pipHasValidSourceView, let targetView = pipTargetView, targetView.window == nil {
            print("🖼️ [PiP] Current source view is no longer in window - invalidating")
            setPiPSourceValidity(false)
        }
        
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
    
    /// Get the IVS preview view for the custom image source
    /// This is useful for PiP as it's recognized by iOS as a valid video source
    public func getCustomImageSourcePreviewView() -> IVSImagePreviewView? {
        guard useCustomCameraCapture,
              let imageSource = self.customImageSource else {
            return nil
        }
        
        do {
            return try imageSource.previewView()
        } catch {
            print("📸 [IVSStageManager] Could not get preview view from custom image source: \(error)")
            return nil
        }
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
            // Background override: if setBackgroundBehavior({ stopPublishing: true })
            // is enabled and the app is in background, force an empty publish set.
            let effectivePublishing = isPublishingActiveOverride ?? self.isPublishingActive
            if effectivePublishing {
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
            let effective = isPublishingActiveOverride ?? self.isPublishingActive
            print("IVSStageManager Strategy: Local participant shouldPublish: \(effective)")
            return effective
        } else {
            // This delegate method is primarily for the local participant.
            // The stage handles publishing for remote participants based on their own client's strategy.
            print("IVSStageManager Strategy: Remote participant \(participant.participantId ?? "N/A") shouldPublish: false (from our perspective)")
            return false 
        }
    }

    func stage(_ stage: IVSStage, shouldSubscribeToParticipant participant: IVSParticipantInfo) -> IVSStageSubscribeType {
        if participant.isLocal {
            return .none
        }
        // Background override: when app is in background and the JS layer asked
        // for audio-only / none mode, honor it for remote participants.
        if isAppInBackground {
            switch bgSubscribeMode {
            case "none": return .none
            case "audioOnly": return .audioOnly
            default: return .audioVideo
            }
        }
        return .audioVideo
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

        // Fatality comes from the SDK's own userInfo key. Per IVSBroadcastErrors.h:
        // "For errors emitted by the SDK, they will all have a key of
        // IVSBroadcastErrorIsFatalKey in their userInfo ... (fatal means recovery
        // is impossible)."
        //
        // This was previously hardcoded `false` with the real check commented out,
        // so the `isFatal` branch below could never run: a fatal stage error never
        // produced a `disconnected` state, JS kept believing it was still
        // publishing, and the seller broadcast to nobody with a LIVE chip still lit.
        //
        // Note the earlier attempt referenced `IVSStageError`, which does not exist
        // in this SDK — uncommenting it would not have compiled.
        let isFatal = (nsError.userInfo[IVSBroadcastErrorIsFatalKey] as? NSNumber)?.boolValue ?? false

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
        // Build a JS-friendly per-stream mute snapshot. The SDK fires this for the
        // set of streams that changed; we forward all of them so UI can update icons.
        let streamDicts: [[String: Any]] = streams.map { s in
            let typeRaw = s.device.descriptor().type
            let mediaType: String
            switch typeRaw {
            case .microphone, .userAudio: mediaType = "audio"
            case .camera, .userImage: mediaType = "video"
            default: mediaType = "unknown"
            }
            return [
                "deviceUrn": s.device.descriptor().urn,
                "mediaType": mediaType,
                "muted": s.isMuted,
            ]
        }
        delegate?.stageManagerDidEmitEvent(
            eventName: "onRemoteMuteStateChanged",
            body: ["participantId": participant.participantId, "streams": streamDicts]
        )
    }
}

// Further delegate methods from IVSStage (if it has a primary delegate for connection/publish states beyond join)
// would be implemented here. The current IVS SDK for Stage might rely more on completion handlers
// and direct state checking for some of these, or specific delegates for participants/streams. 

// MARK: - IVSStageStreamDelegate
extension IVSStageManager {
    /// Called by the SDK in response to requestRTCStats(). Forwards a normalized
    /// snapshot to JS as onRTCStats. The dict layout is loosely standardized as
    /// `[reportName: [statKey: value]]`.
    func stream(_ stream: IVSStageStream, didGenerateRTCStats stats: [String: [String: String]]) {
        let normalized = normalizeRTCStats(stats)
        lastRTCStats = normalized
        delegate?.stageManagerDidEmitEvent(eventName: "onRTCStats", body: normalized)
    }

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

// MARK: - Audio Device Picker + Preset + Gain
//
// These methods address the "mic too quiet, host has to be inches from the phone"
// problem. The default IVSStageAudioManager preset is .videoChat — aggressive AGC
// pulls input gain *down* to make room for AEC math, and routes through the
// earpiece-class audio path. Switching to .studio fixes both: AGC off, full mic
// gain, media-volume routing. listAudioInputs() also lets the broadcaster pick
// AirPods / lavalier / wired mic explicitly.

extension IVSStageManager {

    /// Map the JS string preset onto the IVS SDK enum and apply it immediately.
    /// Safe to call at any time; on iOS the SDK reconfigures AVAudioSession atomically.
    func setAudioPreset(_ preset: String) {
        let mapped: IVSStageAudioManager.UseCasePreset
        switch preset {
        case "studio":         mapped = .studio
        case "subscribeOnly":  mapped = .subscribeOnly
        case "videoChat":      mapped = .videoChat
        default:
            print("⚠️ [Audio] Unknown preset '\(preset)' — falling back to .videoChat. Valid: 'videoChat' | 'subscribeOnly' | 'studio'.")
            mapped = .videoChat
        }
        self.currentAudioPreset = mapped
        stageAudioManager.setPreset(mapped)
        print("📢 [Audio] setAudioPreset → \(mapped)")
    }

    /// Snapshot of the audio inputs visible to AVAudioSession right now.
    /// Returns a stable URN (port UID), display name, type, and whether each is currently active.
    func listAudioInputs() -> [[String: Any]] {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.availableInputs ?? []
        let active = session.currentRoute.inputs.first

        return inputs.map { input -> [String: Any] in
            let typeStr = classifyPortType(input.portType)
            let isActive = (active?.uid == input.uid)
            return [
                "urn": input.uid,
                "name": input.portName,
                "type": typeStr,
                "isActive": isActive,
            ]
        }
    }

    /// Pick a preferred input. Pass nil to revert to system default.
    /// The OS retains final say — when AirPods connect mid-stream it may auto-switch
    /// regardless of preference. onAudioRouteChanged will tell you what actually became active.
    func setPreferredAudioInput(urn: String?) {
        preferredInputUrn = urn
        applyPreferredAudioInputIfPossible()
    }

    /// Apply the stored preferred input via AVAudioSession.setPreferredInput.
    /// Called after stream creation and again on route changes.
    fileprivate func applyPreferredAudioInputIfPossible() {
        let session = AVAudioSession.sharedInstance()
        do {
            if let target = preferredInputUrn,
               let port = session.availableInputs?.first(where: { $0.uid == target }) {
                try session.setPreferredInput(port)
                print("📢 [Audio] setPreferredInput → \(port.portName)")
            } else if preferredInputUrn == nil {
                try session.setPreferredInput(nil)
                print("📢 [Audio] setPreferredInput → system default")
            }
        } catch {
            print("📢 [Audio] setPreferredInput failed: \(error)")
        }
    }

    /// Best-effort software gain on the active input. Only some inputs support
    /// this on iOS (AVAudioSession.isInputGainSettable). Returns false if not supported.
    /// For the built-in iPhone mic this typically returns false — use .studio preset instead.
    func setInputGain(gain: Float) -> Bool {
        let clamped = max(0.0, min(gain, 5.0))
        requestedInputGain = clamped
        let session = AVAudioSession.sharedInstance()
        // AVAudioSession.inputGain only accepts 0.0–1.0.
        let normalized = min(clamped, 1.0)
        guard session.isInputGainSettable else {
            print("📢 [Audio] setInputGain: active input is not settable — returning false")
            return false
        }
        do {
            try session.setInputGain(normalized)
            print("📢 [Audio] setInputGain(\(normalized)) applied")
            return true
        } catch {
            print("📢 [Audio] setInputGain failed: \(error)")
            return false
        }
    }

    /// Build a JS-friendly dict describing whatever input is currently active.
    fileprivate func activeAudioInputDevice() -> [String: Any]? {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.currentRoute.inputs.first else { return nil }
        return [
            "urn": port.uid,
            "name": port.portName,
            "type": classifyPortType(port.portType),
            "isActive": true,
        ]
    }

    fileprivate func classifyPortType(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic: return "builtin"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "bluetooth"
        case .headsetMic, .headphones: return "wired"
        case .usbAudio: return "usb"
        default: return "unknown"
        }
    }
}

// MARK: - Mock Mode
//
// Lets the wrapper run on iOS Simulator (which has no real AVCaptureDevice) by
// synthesizing CMSampleBuffers and pushing them through an IVSCustomImageSource.
// Real IVS lifecycle (joinStage / publishState / participant events) still runs
// — only the camera vendor is faked. Gated to DEBUG builds so it can't ship.

extension IVSStageManager {

    /// Toggle mock mode at runtime. Must be called *before* initializeLocalStreams()
    /// to take effect for the current session. No-op in release builds.
    func setMockMode(enabled: Bool) {
        #if DEBUG
        isMockMode = enabled
        if !enabled {
            mockCameraSource?.stop()
            mockCameraSource = nil
        }
        print("🎭 [Mock] mock mode = \(enabled)")
        #else
        print("🎭 [Mock] setMockMode is a no-op in release builds")
        #endif
    }

    /// Build a synthetic camera stream by minting an IVSCustomImageSource from a
    /// throwaway IVSBroadcastSession and feeding it gradient frames at 30 fps.
    fileprivate func setupMockStreams(videoConfig: IVSLocalStageStreamVideoConfiguration?) {
        #if DEBUG
        print("🎭 [Mock] Initializing mock camera + mic streams.")

        // 1. Mint an IVSCustomImageSource via a throwaway broadcast session.
        do {
            let bcCfg = IVSBroadcastConfiguration()
            try bcCfg.video.setSize(CGSize(width: 720, height: 1280))
            try bcCfg.video.setTargetFramerate(30)
            let tempSession = try IVSBroadcastSession(configuration: bcCfg, descriptors: nil, delegate: nil)
            mockBroadcastSession = tempSession
            mockImageSource = tempSession.createImageSource(withName: "mockCamera")
        } catch {
            print("🎭 [Mock] Failed to mint mock image source: \(error)")
            return
        }

        // 2. Build the IVSLocalStageStream backed by the custom image source.
        let videoCfg: IVSLocalStageStreamVideoConfiguration = videoConfig ?? Self.defaultVideoConfig()

        if let imageSource = mockImageSource {
            let streamCfg = IVSLocalStageStreamConfiguration()
            streamCfg.video = videoCfg
            cameraStream = IVSLocalStageStream(device: imageSource, config: streamCfg)
            cameraStream?.delegate = self
        }

        // 3. Real microphone (so audio paths still work) — mic on simulator picks up Mac mic.
        let micDiscovery = IVSDeviceDiscovery()
        if let micDevice = micDiscovery.listLocalDevices().first(where: { $0.descriptor().type == .microphone }) as? IVSMicrophone {
            let audioCfg = IVSLocalStageStreamAudioConfiguration()
            do { try audioCfg.setMaxBitrate(96_000) } catch {}
            let streamCfg = IVSLocalStageStreamConfiguration()
            streamCfg.audio = audioCfg
            microphoneStream = IVSLocalStageStream(device: micDevice, config: streamCfg)
            microphoneStream?.delegate = self
        }

        // 4. Start the synthetic frame generator.
        let mock = MockCameraSource(imageSource: mockImageSource)
        mock.start()
        mockCameraSource = mock

        print("🎭 [Mock] ✅ Mock streams ready. Real IVS lifecycle still applies; only camera is fake.")
        #endif
    }
}

// MARK: - MockCameraSource
//
// Pushes a 30 fps animated gradient + on-screen timestamp into an
// IVSCustomImageSource so the simulator has something to "broadcast" without
// any AVCaptureDevice. Keeps a strong ref to the image source.
//
// The CLASS is defined unconditionally so the `mockCameraSource:
// MockCameraSource?` property on IVSStageManager can reference its type in
// every build configuration (Debug + Release). Production builds never
// instantiate it — `setMockMode()` and `setupMockStreams()` are still
// `#if DEBUG`-gated, so it stays dormant in release. Wrapping the type
// itself in `#if DEBUG` previously broke Release pod builds (EAS runs Pods
// in Release even on dev profiles), failing at the property declaration
// site with "cannot find type 'MockCameraSource' in scope".

final class MockCameraSource {
    private weak var imageSource: IVSCustomImageSource?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private let width = 720
    private let height = 1280
    private let ciContext = CIContext()

    init(imageSource: IVSCustomImageSource?) {
        self.imageSource = imageSource
    }

    func start() {
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { stop() }

    @objc private func tick() {
        guard let imageSource = imageSource else { return }
        let t = CACurrentMediaTime() - startTime

        // Animated sage-green gradient — easy to recognize as "this is the mock".
        let r: CGFloat = 0.15 + 0.08 * CGFloat(sin(t))
        let g: CGFloat = 0.35 + 0.10 * CGFloat(sin(t * 1.3))
        let b: CGFloat = 0.20 + 0.05 * CGFloat(sin(t * 0.7))
        let bg = CIImage(color: CIColor(red: r, green: g, blue: b))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        // Produce a CVPixelBuffer.
        var pb: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pb)
        guard let pixelBuffer = pb else { return }
        ciContext.render(bg, to: pixelBuffer)

        // Wrap in a CMSampleBuffer.
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDesc)
        guard let desc = formatDesc else { return }

        let now = CMTime(seconds: t, preferredTimescale: 600)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: now,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: desc,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sample)
        if let sb = sample {
            imageSource.onSampleBuffer(sb)
        }
    }
}

// MARK: - Observability: RTC stats + audio level + background behavior
//
// Polls outbound stream stats every 2 seconds and emits a normalized JS payload.
// Lifecycle observers tie publishing/subscribing to the app's fg/bg state when
// setBackgroundBehavior() has been called from JS.

extension IVSStageManager {

    /// Configure how the SDK behaves when the host app is backgrounded.
    /// Stores preferences and installs UIApplication lifecycle observers (idempotent).
    func setBackgroundBehavior(options: [String: Any]?) {
        if let stop = options?["stopPublishing"] as? Bool {
            bgStopPublishing = stop
        }
        if let mode = options?["subscribeMode"] as? String {
            bgSubscribeMode = mode
        }
        installLifecycleObservers()
        print("📢 [Background] setBackgroundBehavior stopPublishing=\(bgStopPublishing) subscribeMode=\(bgSubscribeMode)")
    }

    private func installLifecycleObservers() {
        // Idempotent — removeObserver is in deinit so re-adding is fine.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc fileprivate func handleDidEnterBackground() {
        isAppInBackground = true
        if bgStopPublishing { isPublishingActiveOverride = false }
        stage?.refreshStrategy()
        print("📢 [Background] entered background → publish=\(!bgStopPublishing) subscribe=\(bgSubscribeMode)")
    }

    @objc fileprivate func handleWillEnterForeground() {
        isAppInBackground = false
        isPublishingActiveOverride = nil
        stage?.refreshStrategy()
        print("📢 [Background] returned to foreground → defaults restored")
    }

    /// Start the 2-second RTC stats poller. Idempotent.
    func startRTCStatsTimer() {
        guard rtcStatsTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tickRTCStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        rtcStatsTimer = timer
        print("📊 [Stats] Started 2s RTC stats poller")
    }

    func stopRTCStatsTimer() {
        rtcStatsTimer?.invalidate()
        rtcStatsTimer = nil
    }

    private func tickRTCStats() {
        // Stages SDK delivers stats asynchronously via the stream's delegate:
        //   1. We call requestRTCStats() — no closure, may throw.
        //   2. SDK invokes IVSStageStreamDelegate.stream(_:didGenerateRTCStats:).
        //   3. That delegate method (below) normalizes and emits onRTCStats.
        //
        // Broadcaster path: poll the local camera stream (outbound stats).
        // Viewer path: no local cameraStream exists — fall back to the first
        // remote video stream we're rendering so viewers also receive
        // inbound stats (decoded fps, jitter, packet loss, bytesReceived).
        // Without this fallback, viewers see "—" for every stat row.
        let target: IVSStageStream? = cameraStream ?? firstRemoteVideoStream()
        guard let stream = target else { return }
        do {
            try stream.requestRTCStats()
        } catch {
            print("📊 [Stats] requestRTCStats threw: \(error)")
        }
    }

    /// Find a remote video stream to use as the stats source when no local
    /// camera exists (viewer/subscriber session). Picks the targeted
    /// participant first if set; otherwise the first remote video stream we
    /// know about. Returns nil if no remote video streams are available yet.
    private func firstRemoteVideoStream() -> IVSStageStream? {
        let preferred = targetParticipantId
        let participantsList = self.participants
        // Prefer the explicitly-targeted participant if one was set on
        // joinStage. Otherwise fall back to any participant with video.
        let sorted = participantsList.sorted { a, _ in
            guard let pid = preferred else { return false }
            return a.info.participantId == pid
        }
        for p in sorted {
            if p.info.isLocal { continue }
            if let video = p.streams.first(where: { $0.device.descriptor().type == IVSDeviceType(rawValue: 5) }) {
                return video
            }
        }
        return nil
    }

    /// Walk the WebRTC stats bag and surface a handful of high-value numbers.
    /// Keys vary by stat type (outbound-rtp / remote-inbound-rtp / candidate-pair),
    /// so we scan every group and pick whatever matches first.
    fileprivate func normalizeRTCStats(_ raw: [String: [String: String]]) -> [String: Any] {
        // One-time log of all keys so we can audit what the SDK is actually
        // emitting (helps when the wire format changes between SDK versions).
        if !didLogRTCKeysOnce {
            didLogRTCKeysOnce = true
            for (groupKey, group) in raw {
                print("📊 [Stats] report '\(groupKey)' keys: \(Array(group.keys))")
            }
        }

        var out: [String: Any] = ["raw": raw]

        // Sums across all outbound-rtp / remote-inbound-rtp groups so multi-layer
        // simulcast outputs all roll up.
        var totalBytesSent: Double = 0
        var totalPacketsSent: Double = 0
        var totalPacketsLost: Double = 0
        var foundOutbound = false
        var foundRemoteInbound = false

        for (_, group) in raw {
            let type = group["type"] ?? ""

            // ── outbound-rtp: counters for what we're sending ──
            if type == "outbound-rtp" || group["bytesSent"] != nil {
                foundOutbound = true
                if let b = group["bytesSent"].flatMap(Double.init) { totalBytesSent += b }
                if let p = group["packetsSent"].flatMap(Double.init) { totalPacketsSent += p }
                if let fps = group["framesPerSecond"].flatMap(Double.init) {
                    out["framesPerSecond"] = Int(fps)
                }
                if let reason = group["qualityLimitationReason"], !reason.isEmpty {
                    out["qualityLimitationReason"] = reason
                }
            }

            // ── remote-inbound-rtp: what the receiver reports back ──
            if type == "remote-inbound-rtp" || group["fractionLost"] != nil || group["packetsLost"] != nil {
                foundRemoteInbound = true
                if let loss = group["fractionLost"].flatMap(Double.init) {
                    out["packetLoss"] = loss
                } else if let lost = group["packetsLost"].flatMap(Double.init) {
                    totalPacketsLost += lost
                }
                if let rtt = group["roundTripTime"].flatMap(Double.init) {
                    // WebRTC reports RTT in seconds; we surface milliseconds for the UI.
                    out["roundTripTime"] = Int(rtt * 1000)
                }
                if let jitter = group["jitter"].flatMap(Double.init) {
                    out["jitter"] = jitter
                }
            }

            // ── candidate-pair: alternative source for RTT + bitrate ──
            if type == "candidate-pair" || group["availableOutgoingBitrate"] != nil {
                if out["roundTripTime"] == nil,
                   let rtt = group["currentRoundTripTime"].flatMap(Double.init) {
                    out["roundTripTime"] = Int(rtt * 1000)
                }
                if let bitrate = group["availableOutgoingBitrate"].flatMap(Double.init) {
                    out["outboundBitrate"] = Int(bitrate)
                }
            }
        }

        // Compute packet-loss fraction from counters if fractionLost wasn't given.
        if out["packetLoss"] == nil, totalPacketsSent > 0, foundRemoteInbound {
            out["packetLoss"] = totalPacketsLost / totalPacketsSent
        }

        // Compute outbound bitrate from bytesSent delta if availableOutgoingBitrate wasn't given.
        if out["outboundBitrate"] == nil, foundOutbound {
            let now = Date().timeIntervalSince1970
            if let prev = lastOutboundSnapshot {
                let dt = now - prev.timestamp
                let dBytes = totalBytesSent - prev.bytesSent
                if dt > 0, dBytes >= 0 {
                    let bps = (dBytes * 8.0) / dt
                    out["outboundBitrate"] = Int(bps)
                }
            }
            lastOutboundSnapshot = OutboundSnapshot(bytesSent: totalBytesSent, timestamp: now)
        }

        return out
    }

    /// One-shot snapshot — returns the most recent poll result. Returns empty
    /// dict if no poll has fired yet.
    func snapshotRTCStats() -> [String: Any] {
        return lastRTCStats
    }
}

// Override hook for background publishing: nil means "use isPublishingActive";
// false forces unpublish (set by handleDidEnterBackground). Declared as a free
// extension property via objc associations to avoid mutating the main class init.
private var _isPublishingActiveOverrideKey: UInt8 = 0
extension IVSStageManager {
    fileprivate var isPublishingActiveOverride: Bool? {
        get { objc_getAssociatedObject(self, &_isPublishingActiveOverrideKey) as? Bool }
        set { objc_setAssociatedObject(self, &_isPublishingActiveOverrideKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - Thermal Adaptation
//
// iOS exposes ProcessInfo.thermalState (.nominal/.fair/.serious/.critical). The
// SDK doesn't auto-respond to thermal pressure, so we install an observer that:
//   1. Emits onThermalStateChanged so the JS layer can show a warning.
//   2. If mitigation is enabled, recreates the camera stream at a reduced
//      framerate when state >= .serious, and restores normal framerate when
//      it falls back to .fair or .nominal.

extension IVSStageManager {

    /// Configure thermal mitigation behavior from JS.
    func setThermalMitigation(options: [String: Any]?) {
        if let enabled = options?["enabled"] as? Bool {
            thermalMitigationEnabled = enabled
        }
        if let fps = options?["reducedFramerate"] as? Int {
            thermalReducedFramerate = max(5, min(fps, 30))
        }
        installThermalObserver()
        print("🌡️ [Thermal] mitigation=\(thermalMitigationEnabled), reducedFps=\(thermalReducedFramerate)")
        // Emit an initial state so JS can render the current value without waiting.
        emitThermalState(didMitigate: false)
    }

    /// Returns the current thermal state as the normalized 4-level string.
    func currentThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    fileprivate func installThermalObserver() {
        guard !thermalObserverInstalled else { return }
        thermalObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    @objc fileprivate func handleThermalChange() {
        let state = ProcessInfo.processInfo.thermalState
        var didMitigate = false
        if thermalMitigationEnabled, state == .serious || state == .critical {
            didMitigate = applyReducedFramerate(thermalReducedFramerate)
            print("🌡️ [Thermal] state=\(currentThermalState()) — downshifted framerate to \(thermalReducedFramerate)")
        } else if thermalMitigationEnabled, state == .nominal || state == .fair {
            // Restore default framerate (30 fps) when device cools.
            didMitigate = applyReducedFramerate(30)
        }
        emitThermalState(didMitigate: didMitigate)
    }

    private func emitThermalState(didMitigate: Bool) {
        delegate?.stageManagerDidEmitEvent(
            eventName: "onThermalStateChanged",
            body: ["state": currentThermalState(), "didMitigate": didMitigate]
        )
    }

    /// Rebuild the camera stream with a new framerate and refresh the strategy.
    /// Returns true when the rebuild actually applied; false if there's nothing to mitigate yet.
    private func applyReducedFramerate(_ fps: Int) -> Bool {
        guard let camera = cameraStream?.device else { return false }
        do {
            let newVideoCfg = IVSLocalStageStreamVideoConfiguration()
            try newVideoCfg.setSize(CGSize(width: 720, height: 1280))
            try newVideoCfg.setTargetFramerate(fps)
            let streamCfg = IVSLocalStageStreamConfiguration()
            streamCfg.video = newVideoCfg
            cameraStream = IVSLocalStageStream(device: camera, config: streamCfg)
            cameraStream?.delegate = self
            stage?.refreshStrategy()
            return true
        } catch {
            print("🌡️ [Thermal] Failed to rebuild stream with fps=\(fps): \(error)")
            return false
        }
    }
}
