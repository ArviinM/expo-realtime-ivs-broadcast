// IVSPictureInPictureController.swift
// Picture-in-Picture support for IVS Stages

import AVKit
import AVFoundation
import UIKit
import AmazonIVSBroadcast

// MARK: - PiP Types (Available to all iOS versions for type compatibility)

/// Options for configuring PiP behavior
public struct PiPOptions {
    public var autoEnterOnBackground: Bool = true
    public var sourceView: PiPSourceView = .remote
    public var preferredAspectRatio: CGSize = CGSize(width: 9, height: 16)
    
    public enum PiPSourceView: String {
        case local
        case remote
    }
    
    public init() {}
}

/// Delegate protocol for PiP state changes
public protocol IVSPictureInPictureControllerDelegate: AnyObject {
    func pictureInPictureDidStart()
    func pictureInPictureDidStop()
    func pictureInPictureWillRestore()
    func pictureInPictureDidFail(with error: String)
}

// MARK: - View Frame Capture
/// Captures frames from any UIView using CADisplayLink for PiP
/// This is the workaround for IVS SDK not exposing frame callbacks
/// ALL operations happen on the main thread to avoid threading issues

public class ViewFrameCapture {
    private var displayLink: CADisplayLink?
    private weak var targetView: UIView?
    private var frameCallback: ((CVPixelBuffer) -> Void)?
    
    // Throttle frame capture to 30fps
    private var lastCaptureTime: CFTimeInterval = 0
    private let targetFrameInterval: CFTimeInterval = 1.0 / 30.0
    
    // Fixed output size to prevent jittering - 9:16 portrait
    private let fixedOutputWidth: Int = 540
    private let fixedOutputHeight: Int = 960
    
    // Reusable pixel buffer pool for efficiency
    private var pixelBufferPool: CVPixelBufferPool?
    private var lastWidth: Int = 0
    private var lastHeight: Int = 0
    
    private var isCapturing: Bool = false
    
    public init() {}
    
    deinit {
        stop()
    }
    
    /// Start capturing frames from the target view
    public func start(view: UIView, callback: @escaping (CVPixelBuffer) -> Void) {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start(view: view, callback: callback)
            }
            return
        }
        
        stop() // Clean up any existing capture
        
        self.targetView = view
        self.frameCallback = callback
        self.isCapturing = true
        
        let displayLink = CADisplayLink(target: self, selector: #selector(self.captureFrame))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        
        print("🖼️ [ViewCapture] Started capturing frames from view")
    }
    
    /// Stop capturing frames
    public func stop() {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }
        
        isCapturing = false
        displayLink?.invalidate()
        displayLink = nil
        targetView = nil
        frameCallback = nil
        pixelBufferPool = nil
        lastWidth = 0
        lastHeight = 0
        frameCount = 0
        print("🖼️ [ViewCapture] Stopped capturing frames")
    }
    
    @objc private func captureFrame(_ displayLink: CADisplayLink) {
        // All of this runs on main thread (CADisplayLink callback)
        guard isCapturing else { return }
        
        // Throttle to target frame rate
        let currentTime = displayLink.timestamp
        guard currentTime - lastCaptureTime >= targetFrameInterval else { return }
        lastCaptureTime = currentTime
        
        guard let view = targetView, let callback = frameCallback else { return }
        
        let bounds = view.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Check if view has a window - if not, try to get superview bounds
        // IVS preview might not have window when app is in background
        let captureView: UIView
        let captureBounds: CGRect
        
        if view.window != nil {
            captureView = view
            captureBounds = bounds
        } else if let superview = view.superview, superview.window != nil {
            // Try capturing from superview instead
            captureView = superview
            captureBounds = superview.bounds
        } else {
            // Last resort: capture the view anyway with afterScreenUpdates
            captureView = view
            captureBounds = bounds
        }
        
        // Use UIGraphicsImageRenderer with drawHierarchy for Metal/OpenGL views
        // This is the only reliable way to capture IVS preview views
        // NOTE: afterScreenUpdates must be true when view is not in visible window (e.g., during PiP)
        let renderer = UIGraphicsImageRenderer(size: captureBounds.size)
        let image = renderer.image { rendererContext in
            // drawHierarchy captures Metal/OpenGL content unlike layer.render
            // afterScreenUpdates: true is required when view may not be visible
            captureView.drawHierarchy(in: captureBounds, afterScreenUpdates: true)
        }
        
        guard let cgImage = image.cgImage else { return }
        
        // Use FIXED output size to prevent jittering
        let width = fixedOutputWidth
        let height = fixedOutputHeight
        
        // Get pixel buffer from pool with fixed size
        guard let pixelBuffer = getPixelBuffer(width: width, height: height) else {
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        
        // Calculate scaling to fit the captured image into fixed output size
        // while maintaining aspect ratio (aspect fill)
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let targetWidth = CGFloat(width)
        let targetHeight = CGFloat(height)
        
        let sourceAspect = sourceWidth / sourceHeight
        let targetAspect = targetWidth / targetHeight
        
        var drawRect: CGRect
        if sourceAspect > targetAspect {
            // Source is wider - fit to height, crop sides
            let scaledWidth = targetHeight * sourceAspect
            let xOffset = (scaledWidth - targetWidth) / 2
            drawRect = CGRect(x: -xOffset, y: 0, width: scaledWidth, height: targetHeight)
        } else {
            // Source is taller - fit to width, crop top/bottom
            let scaledHeight = targetWidth / sourceAspect
            let yOffset = (scaledHeight - targetHeight) / 2
            drawRect = CGRect(x: 0, y: -yOffset, width: targetWidth, height: scaledHeight)
        }
        
        // CGContext has origin at bottom-left, so we need to flip
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        // Draw the image scaled to fit the fixed output size (aspect fill)
        context.draw(cgImage, in: drawRect)
        
        // Log first frame capture for debugging
        if frameCount == 0 {
            print("🖼️ [ViewCapture] First frame captured: \(width)x\(height)")
        }
        frameCount += 1
        
        // Call the callback with the captured frame
        callback(pixelBuffer)
    }
    
    private var frameCount: Int = 0
    
    private func getPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        // Create new pool if size changed
        if width != lastWidth || height != lastHeight || pixelBufferPool == nil {
            lastWidth = width
            lastHeight = height
            
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            pixelBufferPool = pool
        }
        
        guard let pool = pixelBufferPool else { return nil }
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        return pixelBuffer
    }
}

// MARK: - SampleBufferVideoCallView
/// A UIView that uses AVSampleBufferDisplayLayer as its layer class
/// This is required for Video Call PiP

@available(iOS 15.0, *)
class SampleBufferVideoCallView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }
    
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }
}

// MARK: - IVSPictureInPictureController

/// Controller for managing Picture-in-Picture functionality with IVS streams
/// Uses the Video Call PiP API for real-time video
@available(iOS 15.0, *)
public class IVSPictureInPictureController: NSObject {
    
    // MARK: - Properties
    
    private var pipController: AVPictureInPictureController?
    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var pipContentSource: AVPictureInPictureController.ContentSource?
    
    // Video Call PiP components
    private var pipVideoCallViewController: AVPictureInPictureVideoCallViewController?
    private var sampleBufferVideoCallView: SampleBufferVideoCallView?
    
    // Container/source view for PiP - this should be the ACTUAL visible view showing video
    private var pipContainerView: UIView?
    private weak var activeSourceView: UIView?
    
    // Configuration
    private var options: PiPOptions = PiPOptions()
    
    // State
    public private(set) var isActive: Bool = false
    public private(set) var isEnabled: Bool = false
    
    // Delegate
    public weak var delegate: IVSPictureInPictureControllerDelegate?
    
    // Frame timing for sample buffer creation
    private var frameCount: Int64 = 0
    private let timeScale: Int32 = 600
    
    // Queue for sample buffer operations
    private let sampleBufferQueue = DispatchQueue(label: "com.ivs.pip.sampleBuffer")
    
    // View frame capture for remote streams
    private var viewFrameCapture: ViewFrameCapture?
    private weak var captureTargetView: UIView?
    
    // Pending source view (when setup is deferred because view is not in window)
    private weak var pendingSourceView: UIView?
    
    // Placeholder frame generator for broadcaster PiP (when camera is unavailable in background)
    private var placeholderTimer: Timer?
    private var placeholderPixelBuffer: CVPixelBuffer?
    private var isUsingPlaceholder: Bool = false
    private var lastRealFrameTime: CFAbsoluteTime = 0
    private let placeholderTimeout: CFTimeInterval = 0.5 // Switch to placeholder after 0.5s without frames
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        setupNotifications()
        createPlaceholderPixelBuffer()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // Don't call cleanup() from deinit - it uses DispatchQueue.main.sync which
        // can cause deadlocks during JavaScript reload. Instead, do minimal cleanup:
        // Invalidate timer directly without the wrapper function to avoid any side effects
        placeholderTimer?.invalidate()
        placeholderTimer = nil
        // Stop PiP if possible, but don't force main thread
        pipController?.stopPictureInPicture()
        // Let ARC handle the rest - no UI operations or delegate callbacks in deinit
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    /// Enable PiP with the given options
    /// Uses the Video Call PiP API which is designed for real-time video
    public func enable(options: PiPOptions) -> Bool {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("🖼️ [PiP] Picture-in-Picture is not supported on this device (simulator?)")
            delegate?.pictureInPictureDidFail(with: "PiP not supported on this device")
            return false
        }
        
        // Ensure we're on the main thread for all UI operations
        guard Thread.isMainThread else {
            var result = false
            DispatchQueue.main.sync {
                result = self.enable(options: options)
            }
            return result
        }
        
        // If already enabled, clean up first to allow re-enabling
        if isEnabled {
            print("🖼️ [PiP] Already enabled, resetting state for re-enable")
            cleanupForReEnable()
        }
        
        self.options = options
        
        // Use fixed frame size matching our capture output (9:16 portrait)
        let frameWidth: CGFloat = 540
        let frameHeight: CGFloat = 960
        
        // Create SampleBufferVideoCallView - a UIView with AVSampleBufferDisplayLayer as its layer
        let sampleBufferView = SampleBufferVideoCallView(frame: CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
        sampleBufferView.sampleBufferDisplayLayer.videoGravity = .resizeAspectFill
        self.sampleBufferDisplayLayer = sampleBufferView.sampleBufferDisplayLayer
        self.sampleBufferVideoCallView = sampleBufferView
        
        // Create the PiP Video Call View Controller
        let pipVideoCallVC = AVPictureInPictureVideoCallViewController()
        pipVideoCallVC.preferredContentSize = CGSize(width: frameWidth, height: frameHeight)
        pipVideoCallVC.view.addSubview(sampleBufferView)
        self.pipVideoCallViewController = pipVideoCallVC
        
        // Set up constraints for the sample buffer view
        sampleBufferView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sampleBufferView.leadingAnchor.constraint(equalTo: pipVideoCallVC.view.leadingAnchor),
            sampleBufferView.trailingAnchor.constraint(equalTo: pipVideoCallVC.view.trailingAnchor),
            sampleBufferView.topAnchor.constraint(equalTo: pipVideoCallVC.view.topAnchor),
            sampleBufferView.bottomAnchor.constraint(equalTo: pipVideoCallVC.view.bottomAnchor)
        ])
        
        // NOTE: We'll set the activeSourceView later when setupWithSourceView is called
        // The activeVideoCallSourceView MUST be the actual visible view showing video
        self.isEnabled = true
        
        print("🖼️ [PiP] Enabled with Video Call API: autoEnter=\(options.autoEnterOnBackground), source=\(options.sourceView.rawValue)")
        print("🖼️ [PiP] Call setupWithSourceView() with the actual video view to complete setup")
        
        return true
    }
    
    /// Clean up state for re-enabling (without fully disabling)
    private func cleanupForReEnable() {
        // Stop any active PiP
        pipController?.stopPictureInPicture()
        pipController = nil
        pipContentSource = nil
        
        // Clean up Video Call components
        sampleBufferVideoCallView?.removeFromSuperview()
        sampleBufferVideoCallView = nil
        pipVideoCallViewController = nil
        
        sampleBufferDisplayLayer?.flush()
        sampleBufferDisplayLayer = nil
        
        // Reset state but keep isEnabled true (will be set again)
        frameCount = 0
        enqueuedFrameCount = 0
        startTime = nil
        isActive = false
        
        // Don't nil out activeSourceView - it might still be valid
        print("🖼️ [PiP] Cleaned up for re-enable")
    }
    
    /// Complete PiP setup with the actual source view
    /// This MUST be called with the visible view showing video content
    public func setupWithSourceView(_ sourceView: UIView) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setupWithSourceView(sourceView)
            }
            return
        }
        
        guard let pipVideoCallVC = pipVideoCallViewController else {
            print("🖼️ [PiP] Error: Must call enable() before setupWithSourceView()")
            return
        }
        
        // IMPORTANT: Check if the source view is in a window hierarchy
        // If not, defer setup until it is
        if sourceView.window == nil {
            print("🖼️ [PiP] Warning: Source view not in window hierarchy yet. Deferring setup...")
            self.pendingSourceView = sourceView
            
            // Observe when the view gets added to window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak sourceView] in
                guard let self = self, let view = sourceView else { return }
                if view.window != nil {
                    print("🖼️ [PiP] Source view now in window, completing setup")
                    self.pendingSourceView = nil
                    self.completeSetupWithSourceView(view, pipVideoCallVC: pipVideoCallVC)
                } else {
                    // Retry with increasing delays
                    self.retrySetupWithSourceView(view, pipVideoCallVC: pipVideoCallVC, attempt: 1)
                }
            }
            return
        }
        
        completeSetupWithSourceView(sourceView, pipVideoCallVC: pipVideoCallVC)
    }
    
    /// Retry setup with exponential backoff
    private func retrySetupWithSourceView(_ sourceView: UIView, pipVideoCallVC: AVPictureInPictureVideoCallViewController, attempt: Int) {
        let maxAttempts = 10
        let delay = min(0.1 * pow(1.5, Double(attempt)), 2.0) // Max 2 second delay
        
        guard attempt < maxAttempts else {
            print("🖼️ [PiP] Warning: Source view still not in window after \(maxAttempts) attempts. Setting up anyway...")
            completeSetupWithSourceView(sourceView, pipVideoCallVC: pipVideoCallVC)
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak sourceView] in
            guard let self = self, let view = sourceView else { return }
            
            if view.window != nil {
                print("🖼️ [PiP] Source view now in window (attempt \(attempt + 1)), completing setup")
                self.pendingSourceView = nil
                self.completeSetupWithSourceView(view, pipVideoCallVC: pipVideoCallVC)
            } else {
                print("🖼️ [PiP] Source view still not in window (attempt \(attempt + 1)), retrying...")
                self.retrySetupWithSourceView(view, pipVideoCallVC: pipVideoCallVC, attempt: attempt + 1)
            }
        }
    }
    
    /// Actually complete the PiP setup once we have a valid source view
    private func completeSetupWithSourceView(_ sourceView: UIView, pipVideoCallVC: AVPictureInPictureVideoCallViewController) {
        self.activeSourceView = sourceView
        self.pipContainerView = sourceView
        
        // Create PiP content source using Video Call API
        // The activeVideoCallSourceView is the ACTUAL view showing video in the app
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: pipVideoCallVC
        )
        self.pipContentSource = contentSource
        
        // Create PiP controller
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = options.autoEnterOnBackground
        
        self.pipController = controller
        
        // Pre-warm with more placeholder frames and longer delay to ensure PiP is possible
        print("🖼️ [PiP] Pre-warming display layer with placeholder frames...")
        aggressivePreWarm { [weak self, weak controller] in
            guard let self = self, let controller = controller else { return }
            print("🖼️ [PiP] Setup complete with source view: \(sourceView)")
            print("🖼️ [PiP] Source view frame: \(sourceView.frame)")
            print("🖼️ [PiP] Source view in window: \(sourceView.window != nil)")
            print("🖼️ [PiP] Source view subviews: \(sourceView.subviews.count)")
            for (index, subview) in sourceView.subviews.enumerated() {
                print("🖼️ [PiP]   - Subview \(index): \(type(of: subview)), alpha: \(subview.alpha), hidden: \(subview.isHidden)")
            }
            print("🖼️ [PiP] Source view sublayers: \(sourceView.layer.sublayers?.count ?? 0)")
            if let sublayers = sourceView.layer.sublayers {
                for (index, layer) in sublayers.enumerated() {
                    print("🖼️ [PiP]   - Layer \(index): \(type(of: layer))")
                }
            }
            print("🖼️ [PiP] isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")
        }
    }
    
    /// Aggressive pre-warming to ensure display layer is ready
    private func aggressivePreWarm(completion: @escaping () -> Void) {
        // Enqueue initial batch of frames immediately
        for _ in 0..<5 {
            enqueuePlaceholderFrame()
        }
        
        // Then enqueue more frames over time to ensure the layer is warm
        var framesEnqueued = 5
        let timer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.enqueuePlaceholderFrame()
            framesEnqueued += 1
            
            // After 15 frames (~0.5s), check if PiP is possible
            if framesEnqueued >= 15 {
                timer.invalidate()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
    
    /// Disable PiP
    public func disable() {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.disable()
            }
            return
        }
        
        if isActive {
            stop()
        }
        
        stopViewCapture()
        cleanup()
        isEnabled = false
        
        print("🖼️ [PiP] Disabled")
    }
    
    /// Start PiP manually
    public func start() {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }
        
        guard isEnabled else {
            print("🖼️ [PiP] Cannot start - PiP is not enabled")
            delegate?.pictureInPictureDidFail(with: "PiP is not enabled")
            return
        }
        
        guard let controller = pipController else {
            print("🖼️ [PiP] Cannot start - no PiP controller")
            delegate?.pictureInPictureDidFail(with: "PiP controller not initialized")
            return
        }
        
        // If PiP is not possible, try pre-warming with placeholder frames
        if !controller.isPictureInPicturePossible {
            print("🖼️ [PiP] PiP not possible, pre-warming with placeholder frames...")
            preWarmWithPlaceholder { [weak self, weak controller] success in
                guard let self = self, let controller = controller else { return }
                
                if success && controller.isPictureInPicturePossible {
                    controller.startPictureInPicture()
                    print("🖼️ [PiP] Start requested after pre-warming")
                } else {
                    print("🖼️ [PiP] Cannot start - PiP still not possible after pre-warming")
                    self.delegate?.pictureInPictureDidFail(with: "PiP is not possible at this time. Make sure video frames are being fed.")
                }
            }
            return
        }
        
        controller.startPictureInPicture()
        print("🖼️ [PiP] Start requested")
    }
    
    /// Pre-warm the display layer with placeholder frames to make PiP possible
    /// Uses aggressive pre-warming with retry logic
    private func preWarmWithPlaceholder(completion: @escaping (Bool) -> Void) {
        guard placeholderPixelBuffer != nil else {
            print("🖼️ [PiP] No placeholder buffer available")
            completion(false)
            return
        }
        
        // Check if source view is in window - if not, that's likely the issue
        if let sourceView = activeSourceView {
            print("🖼️ [PiP] Pre-warm: Source view in window: \(sourceView.window != nil)")
            if sourceView.window == nil {
                print("🖼️ [PiP] Warning: Source view not in window during pre-warm!")
            }
        }
        
        // Use aggressive pre-warming with polling
        var attemptCount = 0
        let maxAttempts = 5
        
        func tryPreWarm() {
            attemptCount += 1
            
            // Enqueue a batch of frames
            for _ in 0..<10 {
                enqueuePlaceholderFrame()
            }
            
            // Use increasing delays for each attempt
            let delay = 0.15 * Double(attemptCount)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                let isPossible = self.pipController?.isPictureInPicturePossible ?? false
                print("🖼️ [PiP] Pre-warm attempt \(attemptCount)/\(maxAttempts), isPictureInPicturePossible: \(isPossible)")
                
                if isPossible {
                    completion(true)
                } else if attemptCount < maxAttempts {
                    // Try again with more frames
                    tryPreWarm()
                } else {
                    // Final attempt - log diagnostic info
                    print("🖼️ [PiP] Pre-warm failed after \(maxAttempts) attempts")
                    if let sourceView = self.activeSourceView {
                        print("🖼️ [PiP] - Source view in window: \(sourceView.window != nil)")
                        print("🖼️ [PiP] - Source view frame: \(sourceView.frame)")
                        print("🖼️ [PiP] - Source view hidden: \(sourceView.isHidden)")
                    }
                    print("🖼️ [PiP] - Display layer status: \(self.sampleBufferDisplayLayer?.status.rawValue ?? -1)")
                    print("🖼️ [PiP] - Frames enqueued: \(self.enqueuedFrameCount)")
                    completion(false)
                }
            }
        }
        
        tryPreWarm()
    }
    
    /// Stop PiP manually
    public func stop() {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }
        
        guard let controller = pipController, isActive else {
            print("🖼️ [PiP] Cannot stop - PiP is not active")
            return
        }
        
        controller.stopPictureInPicture()
        print("🖼️ [PiP] Stop requested")
    }
    
    // MARK: - View Capture for Remote Streams (Fallback Method)
    
    /// Start capturing frames from a UIView (fallback method when IVSImageDevice is not available)
    /// This also sets up the Video Call API with the source view
    /// NOTE: For IVSImageDevice frame capture, the IVSStageManager handles the callback setup
    /// and calls enqueueFrame() directly. This method is kept as a fallback.
    public func startViewCapture(from view: UIView) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startViewCapture(from: view)
            }
            return
        }
        
        stopViewCapture()
        
        // IMPORTANT: Set up the Video Call API with this view as the source
        // This must be the actual visible view showing video content
        if let parentView = view.superview {
            // Use the parent container view (ExpoIVSRemoteStreamView) as the source
            setupWithSourceView(parentView)
        } else {
            // Use the view directly
            setupWithSourceView(view)
        }
        
        captureTargetView = view
        viewFrameCapture = ViewFrameCapture()
        viewFrameCapture?.start(view: view) { [weak self] pixelBuffer in
            self?.enqueueFrame(pixelBuffer)
        }
        
        print("🖼️ [PiP] Started view capture for remote stream (fallback method)")
    }
    
    /// Stop capturing frames from view
    public func stopViewCapture() {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopViewCapture()
            }
            return
        }
        
        viewFrameCapture?.stop()
        viewFrameCapture = nil
        captureTargetView = nil
    }
    
    // MARK: - Frame Handling
    
    /// Feed a video frame (CVPixelBuffer) to the PiP display
    public func enqueueFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isEnabled, let displayLayer = sampleBufferDisplayLayer else {
            return
        }
        
        // Track that we received a real frame
        lastRealFrameTime = CFAbsoluteTimeGetCurrent()
        
        // If we were using placeholder, switch back to real frames
        if isUsingPlaceholder {
            print("🖼️ [PiP] Real frames resumed, stopping placeholder")
            stopPlaceholderFrameGeneration()
        }
        
        // Log first few frames and periodically for debugging
        let shouldLog = enqueuedFrameCount < 3 || (enqueuedFrameCount % 300 == 0) // Log every 10 seconds at 30fps
        if shouldLog {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            print("🖼️ [PiP] Frame #\(enqueuedFrameCount): \(width)x\(height), layer status: \(displayLayer.status.rawValue), isActive: \(isActive)")
        }
        
        // Create CMSampleBuffer from CVPixelBuffer - do this synchronously
        // to ensure the pixel buffer is not released before we use it
        guard let sampleBuffer = self.createSampleBuffer(from: pixelBuffer) else {
            if enqueuedFrameCount < 3 {
                print("🖼️ [PiP] Failed to create sample buffer")
            }
            return
        }
        
        enqueuedFrameCount += 1
        
        // Enqueue on background queue for performance
        sampleBufferQueue.async { [weak displayLayer, weak self] in
            guard let displayLayer = displayLayer else { return }
            
            // Handle failed display layer
            if displayLayer.status == .failed {
                print("🖼️ [PiP] Display layer failed, flushing...")
                displayLayer.flush()
                // Reset start time for fresh timing after flush
                self?.startTime = nil
            }
            
            displayLayer.enqueue(sampleBuffer)
        }
        
        // Log first successful enqueue
        if enqueuedFrameCount == 1 {
            print("🖼️ [PiP] First frame enqueued successfully")
        }
    }
    
    private var enqueuedFrameCount: Int = 0
    
    /// Feed a CMSampleBuffer directly to the PiP display
    /// This extracts the pixel buffer and re-creates with proper timing for AVSampleBufferDisplayLayer
    public func enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isEnabled, let displayLayer = sampleBufferDisplayLayer else {
            return
        }
        
        // Extract pixel buffer from sample buffer and use our timing
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Use enqueueFrame which has proper timing handling
        enqueueFrame(pixelBuffer)
    }
    
    // MARK: - Private Helpers
    
    private var startTime: CMTime?
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let format = formatDescription else {
            print("🖼️ [PiP] Failed to create format description")
            return nil
        }
        
        // Use host time for live streaming - this ensures proper synchronization
        let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
        
        // Initialize start time on first frame
        if startTime == nil {
            startTime = currentTime
        }
        
        // Calculate presentation time relative to start
        let presentationTime = CMTimeSubtract(currentTime, startTime!)
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30), // 1/30th second duration
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard createStatus == noErr else {
            print("🖼️ [PiP] Failed to create sample buffer: \(createStatus)")
            return nil
        }
        
        // Increment frame count
        frameCount += 1
        
        return sampleBuffer
    }
    
    // MARK: - Placeholder Frame Generation
    
    /// Create a placeholder pixel buffer with "Broadcasting" text
    private func createPlaceholderPixelBuffer() {
        let width = 540
        let height = 960
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        
        guard let buffer = pixelBuffer else {
            print("🖼️ [PiP] Failed to create placeholder pixel buffer")
            return
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        
        // Fill with dark background
        context.setFillColor(UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw "Broadcasting" text
        UIGraphicsPushContext(context)
        
        // Flip context for proper text rendering
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        // Draw large red recording dot
        let circleSize: CGFloat = 50
        let circleRect = CGRect(x: (CGFloat(width) - circleSize) / 2, y: CGFloat(height) / 2 - 120, width: circleSize, height: circleSize)
        context.setFillColor(UIColor.red.cgColor)
        context.fillEllipse(in: circleRect)
        
        // Draw "LIVE" text - large and bold
        let liveText = "LIVE"
        let liveAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 72),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let liveRect = CGRect(x: 0, y: CGFloat(height) / 2 - 40, width: CGFloat(width), height: 90)
        liveText.draw(in: liveRect, withAttributes: liveAttributes)
        
        // Draw "Broadcasting in progress" text
        let subText = "Broadcasting in progress"
        let subAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28),
            .foregroundColor: UIColor.lightGray,
            .paragraphStyle: paragraphStyle
        ]
        let subRect = CGRect(x: 0, y: CGFloat(height) / 2 + 60, width: CGFloat(width), height: 40)
        subText.draw(in: subRect, withAttributes: subAttributes)
        
        UIGraphicsPopContext()
        
        self.placeholderPixelBuffer = buffer
        print("🖼️ [PiP] Placeholder pixel buffer created")
    }
    
    /// Start generating placeholder frames to keep PiP alive
    private func startPlaceholderFrameGeneration() {
        guard placeholderTimer == nil else { return }
        
        isUsingPlaceholder = true
        print("🖼️ [PiP] Starting placeholder frame generation")
        
        // Generate placeholder frames at 10fps to keep PiP alive
        placeholderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.enqueuePlaceholderFrame()
        }
        RunLoop.main.add(placeholderTimer!, forMode: .common)
    }
    
    /// Stop generating placeholder frames
    private func stopPlaceholderFrameGeneration() {
        placeholderTimer?.invalidate()
        placeholderTimer = nil
        isUsingPlaceholder = false
        print("🖼️ [PiP] Stopped placeholder frame generation")
    }
    
    /// Enqueue a placeholder frame
    private func enqueuePlaceholderFrame() {
        guard isEnabled, let pixelBuffer = placeholderPixelBuffer, let displayLayer = sampleBufferDisplayLayer else {
            return
        }
        
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer) else {
            return
        }
        
        sampleBufferQueue.async { [weak displayLayer] in
            guard let displayLayer = displayLayer else { return }
            
            if displayLayer.status == .failed {
                displayLayer.flush()
            }
            
            displayLayer.enqueue(sampleBuffer)
        }
    }
    
    /// Check if we should switch to placeholder (called when real frames stop coming)
    private func checkForPlaceholderSwitch() {
        let timeSinceLastFrame = CFAbsoluteTimeGetCurrent() - lastRealFrameTime
        
        if timeSinceLastFrame > placeholderTimeout && !isUsingPlaceholder && isActive {
            print("🖼️ [PiP] No real frames for \(timeSinceLastFrame)s, switching to placeholder")
            startPlaceholderFrameGeneration()
        }
    }
    
    private func cleanup() {
        // Ensure we're on the main thread for UI operations
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { [weak self] in
                self?.cleanup()
            }
            return
        }
        
        // Stop placeholder frame generation
        stopPlaceholderFrameGeneration()
        
        pipController?.stopPictureInPicture()
        pipController = nil
        pipContentSource = nil
        
        // Clean up Video Call components
        sampleBufferVideoCallView?.removeFromSuperview()
        sampleBufferVideoCallView = nil
        pipVideoCallViewController = nil
        
        sampleBufferDisplayLayer?.flush()
        sampleBufferDisplayLayer = nil
        
        // Don't remove pipContainerView if it's the actual source view (not owned by us)
        if pipContainerView != activeSourceView {
            pipContainerView?.removeFromSuperview()
        }
        pipContainerView = nil
        activeSourceView = nil
        
        frameCount = 0
        enqueuedFrameCount = 0
        startTime = nil
        isActive = false
    }
    
    // MARK: - App Lifecycle
    
    @objc private func applicationWillResignActive() {
        // NOTE: We no longer manually trigger PiP here because 
        // AVPictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = true
        // handles auto-entering PiP automatically when the app goes to background.
        // Manual triggering was causing "Failed to start" errors due to race conditions
        // with the system's built-in auto-enter mechanism.
        print("🖼️ [PiP] App going to background (system handles auto-enter)")
    }
    
    @objc private func applicationDidBecomeActive() {
        // Could be used for cleanup or state updates when app returns
        print("🖼️ [PiP] App became active")
    }
    
    // MARK: - Public Getters
    
    public var isPictureInPicturePossible: Bool {
        return pipController?.isPictureInPicturePossible ?? false
    }
    
    public var currentSourceView: PiPOptions.PiPSourceView {
        return options.sourceView
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 15.0, *)
extension IVSPictureInPictureController: AVPictureInPictureControllerDelegate {
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("🖼️ [PiP] Will start")
    }
    
    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        lastRealFrameTime = CFAbsoluteTimeGetCurrent() // Reset timer
        
        // Start monitoring for frame timeout to switch to placeholder
        startFrameMonitoring()
        
        print("🖼️ [PiP] Did start")
        delegate?.pictureInPictureDidStart()
    }
    
    /// Start monitoring for frame timeout
    private func startFrameMonitoring() {
        // Check every 0.5 seconds if we should switch to placeholder
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Stop monitoring if PiP is no longer active
            if !self.isActive {
                timer.invalidate()
                return
            }
            
            self.checkForPlaceholderSwitch()
        }
    }
    
    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("🖼️ [PiP] Will stop")
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        
        // Stop placeholder frame generation
        stopPlaceholderFrameGeneration()
        
        // Reset timing for next PiP session - this is crucial for re-enabling PiP
        startTime = nil
        frameCount = 0
        enqueuedFrameCount = 0
        
        // Flush the display layer to prepare for fresh frames
        sampleBufferDisplayLayer?.flush()
        
        // Pre-warm with a few placeholder frames so PiP can start again immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.enqueuePlaceholderFrame()
            self?.enqueuePlaceholderFrame()
            self?.enqueuePlaceholderFrame()
        }
        
        print("🖼️ [PiP] Did stop - state reset for next session")
        delegate?.pictureInPictureDidStop()
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        print("🖼️ [PiP] Failed to start: \(error.localizedDescription)")
        delegate?.pictureInPictureDidFail(with: error.localizedDescription)
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        print("🖼️ [PiP] Restore user interface requested")
        delegate?.pictureInPictureWillRestore()
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension IVSPictureInPictureController: AVPictureInPictureSampleBufferPlaybackDelegate {
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // For live streaming, we ignore play/pause requests - always playing
        print("🖼️ [PiP] setPlaying: \(playing) (ignored - live stream)")
    }
    
    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Return .invalid to indicate live streaming (no seek bar, no time display)
        // This tells the system there's no seekable content
        return .invalid
    }
    
    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        // Live streaming is never paused - always return false
        return false
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        print("🖼️ [PiP] Transitioned to render size: \(newRenderSize.width)x\(newRenderSize.height)")
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        // No seeking in live streams - this is a no-op for live content
    }
}
