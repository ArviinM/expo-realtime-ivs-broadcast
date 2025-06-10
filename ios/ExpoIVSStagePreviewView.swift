import ExpoModulesCore
import AmazonIVSBroadcast
import UIKit

class ExpoIVSStagePreviewView: ExpoView {
    private var ivsImagePreviewView: IVSImagePreviewView?
    private weak var stageManager: IVSStageManager? // Hold a weak reference
    private var currentPreviewDeviceUrn: String? // Store URN of the device for current preview

    // Props from React Native
    var mirror: Bool = false {
        didSet {
            // This will apply mirroring if/when ivsImagePreviewView is available
            ivsImagePreviewView?.setMirrored(mirror)
        }
    }

    var scaleMode: String = "fit" { // "fit" or "fill"
        didSet {
            // This will update scale mode if/when ivsImagePreviewView is available
            updateScaleMode()
        }
    }

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        // setupView() // Removed
        resolveStageManagerAndStream()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // This initializer might be used by UIKit, ensure setup is called.
        // However, ExpoView typically uses the appContext initializer.
        // setupView() // Removed
        resolveStageManagerAndStream()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // private func setupView() { ... } // Entire method removed

    private func resolveStageManagerAndStream() {
        guard let moduleRegistry = appContext?.moduleRegistry else {
            print("ExpoIVSStagePreviewView: Could not find moduleRegistry in app context.")
            return
        }
        // Try to get the module by its registered name from the ModuleRegistry
        guard let untypedModule = moduleRegistry.get(moduleWithName: "ExpoRealtimeIvsBroadcast"),
              let module = untypedModule as? ExpoRealtimeIvsBroadcastModule else {
            print("ExpoIVSStagePreviewView: Could not find or cast ExpoRealtimeIvsBroadcastModule from module registry using get(moduleWithName:).")
            return
        }
        self.stageManager = module.ivsStageManager
        attachStream()
    }
    
    func attachStream() {
        guard let stream = self.stageManager?.getCameraStream() else {
            print("ExpoIVSStagePreviewView: Camera stream not yet available from StageManager.")
            // If stream isn't available, and we have an old preview, remove it.
            if let oldPreview = self.ivsImagePreviewView {
                print("ExpoIVSStagePreviewView: Camera stream unavailable, removing old preview.")
                oldPreview.removeFromSuperview()
                self.ivsImagePreviewView = nil
                self.currentPreviewDeviceUrn = nil
            }
            return
        }

        let newDeviceUrn = stream.device.descriptor().urn

        // If preview view exists and is for the *same* device, do nothing.
        if let existingPreview = self.ivsImagePreviewView, self.currentPreviewDeviceUrn == newDeviceUrn {
            print("ExpoIVSStagePreviewView: Preview for the correct device (\(newDeviceUrn)) already exists.")
            return
        }

        // If preview exists but for a *different* device, or if no preview exists, create/recreate it.
        if let oldPreview = self.ivsImagePreviewView {
            print("ExpoIVSStagePreviewView: Stream device changed (or preview needs refresh). Removing old preview for \((self.currentPreviewDeviceUrn ?? "nil")) before creating new one for \(newDeviceUrn).")
            oldPreview.removeFromSuperview()
            self.ivsImagePreviewView = nil
            self.currentPreviewDeviceUrn = nil // Clear old URN
        }

        guard let imageDevice = stream.device as? IVSImageDevice else {
            print("ExpoIVSStagePreviewView: Stream's device ('\(newDeviceUrn)') does not conform to IVSImageDevice.")
            return
        }

        do {
            print("ExpoIVSStagePreviewView: Attempting to create IVSImagePreviewView from device: \(newDeviceUrn)")
            let newPreview = try imageDevice.previewView()
            newPreview.translatesAutoresizingMaskIntoConstraints = false
            
            addSubview(newPreview)
            NSLayoutConstraint.activate([
                newPreview.topAnchor.constraint(equalTo: topAnchor),
                newPreview.bottomAnchor.constraint(equalTo: bottomAnchor),
                newPreview.leadingAnchor.constraint(equalTo: leadingAnchor),
                newPreview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            
            self.ivsImagePreviewView = newPreview
            self.currentPreviewDeviceUrn = newDeviceUrn // Store the URN of the new device
            
            self.ivsImagePreviewView?.setMirrored(self.mirror)
            updateScaleMode()

            print("ExpoIVSStagePreviewView: Successfully created and configured IVSImagePreviewView for \(newDeviceUrn).")
            // No need to call setStream on IVSImagePreviewView as it's intrinsically linked to the device it was created from.

        } catch {
            print("ExpoIVSStagePreviewView: Failed to create IVSImagePreviewView from device \(newDeviceUrn): \(error)")
            self.ivsImagePreviewView = nil // Ensure it's nil on failure
            self.currentPreviewDeviceUrn = nil
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
            ivsImagePreviewView?.contentMode = .scaleAspectFit // Default to fit
        }
    }
    
    // Call this if the stream becomes available after the view is initialized
    // or if you suspect the stream needs to be re-attached.
    func refreshStream() {
        print("ExpoIVSStagePreviewView: refreshStream() called.")
        // If ivsImagePreviewView is nil, attachStream will try to create it.
        // If it exists, it will just re-set the stream.
        attachStream()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Auto Layout should handle subview resizing.
        // If specific manual frame adjustments were needed, they'd go here.
    }
} 
