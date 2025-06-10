// ExpoIVSRemoteStreamView.swift (Final Corrected Version)

import ExpoModulesCore
import AmazonIVSBroadcast
import UIKit

class ExpoIVSRemoteStreamView: ExpoView {
    private var ivsImagePreviewView: IVSImagePreviewView?
    private weak var stageManager: IVSStageManager?
    private var currentRenderedDeviceUrn: String?

    // Props from React Native
    var participantId: String? {
        didSet {
            if oldValue != participantId {
                updateStream()
            }
        }
    }

    var deviceUrn: String? {
        didSet {
            if oldValue != deviceUrn {
                updateStream()
            }
        }
    }

    var scaleMode: String = "fit" {
        didSet {
            updateScaleMode()
        }
    }

    // MARK: - Initializers

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        // This is now the single point of entry for setup.
        resolveStageManager()
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
        // This function now acts as the main setup method.
        guard let moduleRegistry = appContext?.moduleRegistry else {
            print("ExpoIVSRemoteStreamView: Could not find moduleRegistry in app context.")
            return
        }
        guard let untypedModule = moduleRegistry.get(moduleWithName: "ExpoRealtimeIvsBroadcast"),
              let module = untypedModule as? ExpoRealtimeIvsBroadcastModule else {
            print("ExpoIVSRemoteStreamView: Could not find or cast ExpoRealtimeIvsBroadcastModule.")
            return
        }
        self.stageManager = module.ivsStageManager

        // --- THE FIX ---
        // Immediately try to render with the current props as soon as the view is created.
        // This mirrors the behavior of the working ExpoIVSStagePreviewView.
        updateStream()
    }

    public func updateStream() {
        // Put the logs at the top so we ALWAYS see them when the function is called.
        print("--------------------------------------------------")
        print("✅ [REMOTE VIEW] updateStream called.")
        print("✅ [REMOTE VIEW] Current participantId: \(self.participantId ?? "nil")")
        print("✅ [REMOTE VIEW] Current deviceUrn: \(self.deviceUrn ?? "nil")")

        // Ensure we have the necessary identifiers and the manager
        guard let pId = self.participantId, !pId.isEmpty,
              let urn = self.deviceUrn, !urn.isEmpty,
              let manager = self.stageManager else {
            print("❌ [REMOTE VIEW] Missing props or manager. Cleaning up.")
            cleanupStreamView()
            print("--------------------------------------------------")
            return
        }

        // Check for Redundancy
        if urn == self.currentRenderedDeviceUrn {
            print("🟡 [REMOTE VIEW] Already rendering this URN. No change needed.")
            print("--------------------------------------------------")
            return
        }
        
        cleanupStreamView()

        // Find the stream
        guard let stream = manager.findStream(forParticipantId: pId, deviceUrn: urn) else {
            print("❌ [REMOTE VIEW] Could not find stream in manager.")
            print("--------------------------------------------------")
            return
        }

        // Get the device and cast it
        guard let imageDevice = stream.device as? IVSImageDevice else {
            print("❌ [REMOTE VIEW] Stream's device is not an IVSImageDevice.")
            print("--------------------------------------------------")
            return
        }

        do {
            // Create the preview from the device
            let newPreview = try imageDevice.previewView()
            
            addSubview(newPreview)
            newPreview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                newPreview.topAnchor.constraint(equalTo: topAnchor),
                newPreview.bottomAnchor.constraint(equalTo: bottomAnchor),
                newPreview.leadingAnchor.constraint(equalTo: leadingAnchor),
                newPreview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            
            self.ivsImagePreviewView = newPreview
            self.currentRenderedDeviceUrn = urn
            updateScaleMode()

            print("✅ [REMOTE VIEW] Successfully created and configured preview for URN \(urn).")
        } catch {
            print("❌ [REMOTE VIEW] Failed to create previewView from device: \(error)")
            cleanupStreamView()
        }
        print("--------------------------------------------------")
    }

    private func cleanupStreamView() {
        if let oldPreview = self.ivsImagePreviewView {
            oldPreview.removeFromSuperview()
            self.ivsImagePreviewView = nil
            self.currentRenderedDeviceUrn = nil
        }
    }

    private func updateScaleMode() {
        ivsImagePreviewView?.contentMode = (scaleMode.lowercased() == "fill") ? .scaleAspectFill : .scaleAspectFit
    }
}
