// ExpoIVSRemoteStreamView.swift (Final Corrected Version)

import ExpoModulesCore
import AmazonIVSBroadcast
import UIKit

class ExpoIVSRemoteStreamView: ExpoView {
    private var ivsImagePreviewView: IVSImagePreviewView?
    private weak var stageManager: IVSStageManager?
    
    // This is the only state this view needs: what is it currently rendering?
    private(set) var currentRenderedDeviceUrn: String?

    // No more participantId or deviceUrn props!
    var scaleMode: String = "fill" {
        didSet { updateScaleMode() }
    }
    
    /// Returns the actual IVS preview view for PiP capture
    /// This is the view that actually displays the video content
    public var previewViewForPiP: UIView? {
        return ivsImagePreviewView
    }
    
    /// Returns whether this view is currently rendering video
    public var isRenderingVideo: Bool {
        return ivsImagePreviewView != nil && currentRenderedDeviceUrn != nil
    }

    // MARK: - Initializers

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        resolveStageManager()
    }

    deinit {
        print("📺 [REMOTE VIEW] deinit called, clearing stream and unregistering")
        // Clear the stream first so the URN is released before unregistering
        // This ensures the stream can be reclaimed by new views
        cleanupStreamView()
        // Then unregister from the manager
        stageManager?.unregisterRemoteView(self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // This initializer might be used by UIKit, but we ensure it also runs the setup.
        resolveStageManager()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup and Rendering

    private func resolveStageManager() {
        print("📺 [REMOTE VIEW] resolveStageManager called, appContext: \(appContext != nil)")
        
        guard let moduleRegistry = appContext?.moduleRegistry else {
            print("📺 [REMOTE VIEW] ERROR: Could not find moduleRegistry in app context.")
            return
        }

        guard let untypedModule = moduleRegistry.get(moduleWithName: "ExpoRealtimeIvsBroadcast"),
              let module = untypedModule as? ExpoRealtimeIvsBroadcastModule else {
            print("📺 [REMOTE VIEW] ERROR: Could not find or cast ExpoRealtimeIvsBroadcastModule.")
            return
        }

        self.stageManager = module.ivsStageManager
        print("📺 [REMOTE VIEW] Got stageManager: \(stageManager != nil)")
        self.stageManager?.registerRemoteView(self)
    }

    public func renderStream(participantId: String, deviceUrn: String) {
        guard let manager = self.stageManager else { return }
        if deviceUrn == self.currentRenderedDeviceUrn { return }

        print("--------------------------------------------------")
        print("✅ [REMOTE VIEW] renderStream called.")
        print("✅ [REMOTE VIEW] Current participantId: \(participantId)")
        print("✅ [REMOTE VIEW] Current deviceUrn: \(deviceUrn)")
        
        cleanupStreamView()

        guard let stream = manager.findStream(forParticipantId: participantId, deviceUrn: deviceUrn),
              let imageDevice = stream.device as? IVSImageDevice else {
            return
        }

        do {
            let newPreview = try imageDevice.previewView()
            
            self.ivsImagePreviewView = newPreview
            self.currentRenderedDeviceUrn = deviceUrn
            addSubview(newPreview)

            newPreview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                newPreview.topAnchor.constraint(equalTo: topAnchor),
                newPreview.bottomAnchor.constraint(equalTo: bottomAnchor),
                newPreview.leadingAnchor.constraint(equalTo: leadingAnchor),
                newPreview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])

            updateScaleMode()
            print("✅ [REMOTE VIEW] Manager commanded me to render URN: \(deviceUrn)")
            
            // Notify the stage manager that a stream started rendering (for PiP)
            // Use a longer delay to ensure the view hierarchy is fully set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                print("✅ [REMOTE VIEW] Notifying PiP system - view in window: \(self.window != nil), isRenderingVideo: \(self.isRenderingVideo)")
                self.stageManager?.notifyRemoteStreamRendered()
            }
            
            // Also notify immediately for faster setup if view is already ready
            if self.window != nil {
                print("✅ [REMOTE VIEW] View already in window, notifying PiP immediately")
                self.stageManager?.notifyRemoteStreamRendered()
            }
        } catch {
            print("❌ [REMOTE VIEW] Failed to create preview for URN \(deviceUrn): \(error)")
        }
    }

    public func clearStream() {
        cleanupStreamView()
    }

    private func cleanupStreamView() {
        if let oldPreview = self.ivsImagePreviewView {
            oldPreview.removeFromSuperview()
            self.ivsImagePreviewView = nil
            self.currentRenderedDeviceUrn = nil
        }
    }

    private func updateScaleMode() {
        // This method now safely uses optional chaining, applying mode only if view exists.
        switch scaleMode.lowercased() {
        case "fill":
            ivsImagePreviewView?.contentMode = .scaleAspectFill
        case "fit":
            ivsImagePreviewView?.contentMode = .scaleAspectFit
        default:
            ivsImagePreviewView?.contentMode = .scaleAspectFill // Default to fill
        }
    }
}
