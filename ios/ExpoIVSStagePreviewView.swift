import ExpoModulesCore
import AmazonIVSBroadcast
import UIKit
import AVFoundation

class ExpoIVSStagePreviewView: ExpoView {
    private var ivsImagePreviewView: IVSImagePreviewView?
    private var customPreviewLayer: AVCaptureVideoPreviewLayer?
    private weak var stageManager: IVSStageManager?
    private var currentPreviewDeviceUrn: String?
    private var isUsingCustomPreview: Bool = false

    // Props from React Native
    var mirror: Bool = false {
        didSet {
            print("DEBUG: mirroring " + String(describing: mirror))
            if isUsingCustomPreview {
                // For custom preview, we mirror by transforming the layer
                updateCustomPreviewMirror()
            } else {
                ivsImagePreviewView?.setMirrored(mirror)
            }
        }
    }

    var scaleMode: String = "fill" {
        didSet {
            updateScaleMode()
        }
    }

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        resolveStageManagerAndStream()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        resolveStageManagerAndStream()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func resolveStageManagerAndStream() {
        guard let moduleRegistry = appContext?.moduleRegistry else {
            print("ExpoIVSStagePreviewView: Could not find moduleRegistry in app context.")
            return
        }
        guard let untypedModule = moduleRegistry.get(moduleWithName: "ExpoRealtimeIvsBroadcast"),
              let module = untypedModule as? ExpoRealtimeIvsBroadcastModule else {
            print("ExpoIVSStagePreviewView: Could not find or cast ExpoRealtimeIvsBroadcastModule.")
            return
        }
        self.stageManager = module.ivsStageManager
        attachStream()
    }
    
    func attachStream() {
        guard let manager = self.stageManager else {
            print("ExpoIVSStagePreviewView: StageManager not available.")
            return
        }
        
        // Check if we should use custom preview or native IVS preview
        if manager.isUsingCustomCameraCapture() {
            print("ExpoIVSStagePreviewView: Using CUSTOM camera preview layer")
            attachCustomPreview()
        } else {
            print("ExpoIVSStagePreviewView: Using NATIVE IVS preview")
            attachNativePreview()
        }
    }
    
    private func attachCustomPreview() {
        // Remove any existing previews
        removeAllPreviews()
        
        guard let previewLayer = stageManager?.getCustomCameraPreviewLayer() else {
            print("ExpoIVSStagePreviewView: Custom preview layer not available yet.")
            return
        }
        
        isUsingCustomPreview = true
        customPreviewLayer = previewLayer
        
        // Configure the preview layer
        previewLayer.frame = bounds
        previewLayer.videoGravity = scaleMode.lowercased() == "fill" ? .resizeAspectFill : .resizeAspect
        
        // Ensure the connection is enabled
        if let connection = previewLayer.connection {
            connection.isEnabled = true
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            print("ExpoIVSStagePreviewView: Preview layer connection enabled, orientation set")
        } else {
            print("ExpoIVSStagePreviewView: ⚠️ Preview layer has no connection yet")
        }
        
        // Add to view
        layer.addSublayer(previewLayer)
        
        // Apply mirror if needed
        updateCustomPreviewMirror()
        
        print("ExpoIVSStagePreviewView: ✅ Custom preview layer attached, frame: \(bounds)")
    }
    
    private func attachNativePreview() {
        guard let stream = self.stageManager?.getCameraStream() else {
            print("ExpoIVSStagePreviewView: Camera stream not yet available from StageManager.")
            if let oldPreview = self.ivsImagePreviewView {
                print("ExpoIVSStagePreviewView: Removing old preview.")
                oldPreview.removeFromSuperview()
                self.ivsImagePreviewView = nil
                self.currentPreviewDeviceUrn = nil
            }
            return
        }

        let newDeviceUrn = stream.device.descriptor().urn

        // If preview view exists and is for the same device, do nothing
        if let existingPreview = self.ivsImagePreviewView, self.currentPreviewDeviceUrn == newDeviceUrn {
            print("ExpoIVSStagePreviewView: Preview for the correct device already exists.")
            return
        }

        // Remove old preview if exists
        removeAllPreviews()

        guard let imageDevice = stream.device as? IVSImageDevice else {
            print("ExpoIVSStagePreviewView: Stream's device does not conform to IVSImageDevice.")
            return
        }

        do {
            print("ExpoIVSStagePreviewView: Creating IVSImagePreviewView for device: \(newDeviceUrn)")
            let newPreview = try imageDevice.previewView()
            newPreview.translatesAutoresizingMaskIntoConstraints = false
            
            addSubview(newPreview)
            NSLayoutConstraint.activate([
                newPreview.topAnchor.constraint(equalTo: topAnchor),
                newPreview.bottomAnchor.constraint(equalTo: bottomAnchor),
                newPreview.leadingAnchor.constraint(equalTo: leadingAnchor),
                newPreview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            
            isUsingCustomPreview = false
            self.ivsImagePreviewView = newPreview
            self.currentPreviewDeviceUrn = newDeviceUrn
            
            self.ivsImagePreviewView?.setMirrored(self.mirror)
            updateScaleMode()

            print("ExpoIVSStagePreviewView: ✅ Native IVS preview attached for \(newDeviceUrn)")

        } catch {
            print("ExpoIVSStagePreviewView: Failed to create IVSImagePreviewView: \(error)")
            self.ivsImagePreviewView = nil
            self.currentPreviewDeviceUrn = nil
        }
    }
    
    private func removeAllPreviews() {
        // Remove native preview
        if let oldPreview = self.ivsImagePreviewView {
            oldPreview.removeFromSuperview()
            self.ivsImagePreviewView = nil
            self.currentPreviewDeviceUrn = nil
        }
        
        // Remove custom preview layer
        if let oldLayer = self.customPreviewLayer {
            oldLayer.removeFromSuperlayer()
            self.customPreviewLayer = nil
        }
    }
    
    private func updateCustomPreviewMirror() {
        guard let previewLayer = customPreviewLayer else { return }
        
        if mirror {
            // Mirror horizontally
            previewLayer.transform = CATransform3DMakeScale(-1, 1, 1)
        } else {
            previewLayer.transform = CATransform3DIdentity
        }
    }

    private func updateScaleMode() {
        if isUsingCustomPreview {
            customPreviewLayer?.videoGravity = scaleMode.lowercased() == "fill" ? .resizeAspectFill : .resizeAspect
        } else {
            switch scaleMode.lowercased() {
            case "fill":
                ivsImagePreviewView?.contentMode = .scaleAspectFill
            case "fit":
                ivsImagePreviewView?.contentMode = .scaleAspectFit
            default:
                ivsImagePreviewView?.contentMode = .scaleAspectFill
            }
        }
    }
    
    func refreshStream() {
        print("ExpoIVSStagePreviewView: refreshStream() called.")
        attachStream()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update custom preview layer frame when view resizes
        if isUsingCustomPreview, let previewLayer = customPreviewLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            print("ExpoIVSStagePreviewView: layoutSubviews - updated preview frame to \(bounds)")
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // When the view is added to a window, try to attach stream if not already done
        if window != nil && customPreviewLayer == nil && ivsImagePreviewView == nil {
            print("ExpoIVSStagePreviewView: didMoveToWindow - attempting to attach stream")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.attachStream()
            }
        }
    }
}
