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
            // If participantId changes, we must re-evaluate the stream.
            if oldValue != participantId {
                updateStream()
            }
        }
    }

    var deviceUrn: String? {
        didSet {
            // If deviceUrn changes, we must re-evaluate the stream.
            if oldValue != deviceUrn {
                updateStream()
            }
        }
    }

    var scaleMode: String = "fit" { // "fit" or "fill"
        didSet {
            updateScaleMode()
        }
    }

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        resolveStageManager()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        resolveStageManager()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func resolveStageManager() {
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
    }

    private func updateStream() {
        // Ensure we have the necessary identifiers and the manager
        guard let pId = self.participantId, let urn = self.deviceUrn, let manager = self.stageManager else {
            print("ExpoIVSRemoteStreamView: Missing participantId, deviceUrn, or stageManager. Cannot update stream.")
            cleanupStreamView()
            return
        }

        // 1. Check for Redundancy: If we are already rendering this specific stream, do nothing.
        if urn == self.currentRenderedDeviceUrn {
            print("ExpoIVSRemoteStreamView: Already rendering device URN \(urn). No change needed.")
            return
        }
        
        // 2. Clean Up Old View before creating a new one
        cleanupStreamView()

        // 3. Get Manager and Stream
        guard let stream = manager.findStream(forParticipantId: pId, deviceUrn: urn) else {
            print("ExpoIVSRemoteStreamView: Could not find stream for participant \(pId) with URN \(urn).")
            return
        }

        // 4. Get Device and Create Preview
        guard let imageDevice = stream.device as? IVSImageDevice else {
            print("ExpoIVSRemoteStreamView: Stream's device ('\(urn)') does not conform to IVSImageDevice.")
            return
        }

        do {
            let newPreview = try imageDevice.previewView()
            
            // 5. Add to Hierarchy and Configure
            newPreview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(newPreview)
            NSLayoutConstraint.activate([
                newPreview.topAnchor.constraint(equalTo: topAnchor),
                newPreview.bottomAnchor.constraint(equalTo: bottomAnchor),
                newPreview.leadingAnchor.constraint(equalTo: leadingAnchor),
                newPreview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            
            self.ivsImagePreviewView = newPreview
            self.currentRenderedDeviceUrn = urn
            
            updateScaleMode()

            print("ExpoIVSRemoteStreamView: Successfully created and configured preview for URN \(urn).")
        } catch {
            print("ExpoIVSRemoteStreamView: Failed to create IVSImagePreviewView from device \(urn): \(error)")
            cleanupStreamView() // Ensure we are clean after a failure
        }
    }

    private func cleanupStreamView() {
        if let oldPreview = self.ivsImagePreviewView {
            print("ExpoIVSRemoteStreamView: Removing old preview view for device URN: \(self.currentRenderedDeviceUrn ?? "nil").")
            oldPreview.removeFromSuperview()
            self.ivsImagePreviewView = nil
            self.currentRenderedDeviceUrn = nil
        }
    }

    private func updateScaleMode() {
        switch scaleMode.lowercased() {
        case "fill":
            ivsImagePreviewView?.contentMode = .scaleAspectFill
        case "fit":
            ivsImagePreviewView?.contentMode = .scaleAspectFit
        default:
            ivsImagePreviewView?.contentMode = .scaleAspectFit
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Auto Layout handles resizing.
    }
} 
