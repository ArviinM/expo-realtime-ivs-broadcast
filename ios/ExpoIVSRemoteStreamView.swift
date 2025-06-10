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
    var scaleMode: String = "fit" {
        didSet { updateScaleMode() }
    }

    // MARK: - Initializers

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        resolveStageManager()
    }

    deinit {
        // When the view is destroyed, unregister from the manager.
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
        // guard let module = appContext?.legacyModule(implementing: ExpoRealtimeIvsBroadcastModule.self) else { return }
        guard let moduleRegistry = appContext?.moduleRegistry else {
            print("ExpoRealtimeIvsBroadcastModule: Could not find moduleRegistry in app context.")
            return
        }

        guard let untypedModule = moduleRegistry.get(moduleWithName: "ExpoRealtimeIvsBroadcast"),
              let module = untypedModule as? ExpoRealtimeIvsBroadcastModule else {
            print("ExpoIVSStagePreviewView: Could not find or cast ExpoRealtimeIvsBroadcastModule from module registry using get(moduleWithName:).")
            return
        }

        self.stageManager = module.ivsStageManager
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
        ivsImagePreviewView?.contentMode = (scaleMode.lowercased() == "fill") ? .scaleAspectFill : .scaleAspectFit
    }
}
