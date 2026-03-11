import ExpoModulesCore
import AVFoundation // For permissions
import AVKit // For PiP
import AmazonIVSBroadcast // For config types if passed directly

public class ExpoRealtimeIvsBroadcastModule: Module, IVSStageManagerDelegate {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.

  var ivsStageManager: IVSStageManager?

  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ExpoRealtimeIvsBroadcast')` in JavaScript.
    Name("ExpoRealtimeIvsBroadcast")
    // Defines event names that the module can send to JavaScript.
    Events("onStageConnectionStateChanged", "onPublishStateChanged", "onStageError", "onCameraSwapped", "onCameraSwapError", "onParticipantJoined", "onParticipantLeft", "onParticipantStreamsAdded", "onParticipantStreamsRemoved", "onPiPStateChanged", "onPiPError", "onCameraMuteStateChanged")

    // Initialize the IVSStageManager when the module is created
    // and set self as its delegate.
    OnCreate {
      self.ivsStageManager = IVSStageManager()
      self.ivsStageManager?.delegate = self
    }

    // --- Methods Exposed to JS ---

    AsyncFunction("initializeStage") { (audioConfigMap: [String: Any]?, videoConfigMap: [String: Any]?) -> Void in
      // For now, using nil, which will use default configurations in IVSStageManager
      self.ivsStageManager?.initializeStage(audioConfig: nil, videoConfig: nil)
    }

    AsyncFunction("initializeLocalStreams") { (audioConfigMap: [String: Any]?, videoConfigMap: [String: Any]?) -> Void in
        // For now, using nil, which will use default configurations in IVSStageManager
        self.ivsStageManager?.initializeLocalStreams(audioConfig: nil, videoConfig: nil)
    }

    AsyncFunction("destroyLocalStreams") {
        self.ivsStageManager?.destroyLocalStreams()
    }

    AsyncFunction("joinStage") { (token: String, options: [String: Any]?) in
      let targetId = options?["targetParticipantId"] as? String
      self.ivsStageManager?.joinStage(token: token, targetParticipantId: targetId)
    }

    AsyncFunction("leaveStage") { 
      self.ivsStageManager?.leaveStage()
    }

    AsyncFunction("setStreamsPublished") { (published: Bool) in
      self.ivsStageManager?.setStreamsPublished(published: published)
    }

    AsyncFunction("swapCamera") { 
      self.ivsStageManager?.swapCamera()
    }

    AsyncFunction("setMicrophoneMuted") { (muted: Bool) in
      self.ivsStageManager?.setMicrophoneMuted(muted: muted)
    }
    
    AsyncFunction("setCameraMuted") { (muted: Bool, placeholderText: String?) in
      self.ivsStageManager?.setCameraMuted(muted: muted, placeholderText: placeholderText)
    }
    
    AsyncFunction("isCameraMuted") { () -> Bool in
      return self.ivsStageManager?.isCameraMuted() ?? false
    }

    AsyncFunction("requestPermissions") { (promise: Promise) in
      var permissions: [String: String] = ["camera": "not-determined", "microphone": "not-determined"]
      let group = DispatchGroup()

      group.enter()
      AVCaptureDevice.requestAccess(for: .video) { granted in
        permissions["camera"] = granted ? "granted" : "denied"
        group.leave()
      }

      group.enter()
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        permissions["microphone"] = granted ? "granted" : "denied"
        group.leave()
      }

      group.notify(queue: .main) {
        promise.resolve(permissions)
      }
    }
    
    // MARK: - Picture-in-Picture Methods
    
    AsyncFunction("enablePictureInPicture") { (options: [String: Any]?) -> Bool in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.enablePictureInPicture(options: options)
        return true
      } else {
        print("PiP requires iOS 15.0 or later")
        return false
      }
    }
    
    AsyncFunction("disablePictureInPicture") { () -> Void in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.disablePictureInPicture()
      }
    }
    
    AsyncFunction("startPictureInPicture") { () -> Void in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.startPictureInPicture()
      }
    }
    
    AsyncFunction("stopPictureInPicture") { () -> Void in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.stopPictureInPicture()
      }
    }
    
    AsyncFunction("isPictureInPictureActive") { () -> Bool in
      if #available(iOS 15.0, *) {
        return self.ivsStageManager?.isPictureInPictureActive() ?? false
      }
      return false
    }
    
    AsyncFunction("isPictureInPictureSupported") { () -> Bool in
      if #available(iOS 15.0, *) {
        return AVPictureInPictureController.isPictureInPictureSupported()
      }
      return false
    }
    
    View(ExpoIVSStagePreviewView.self) {
      Prop("mirror") { (view: ExpoIVSStagePreviewView, mirror: Bool) in
        print("DEBUG: Setting stage preview mirror to \(mirror)")
        view.mirror = mirror
      }

      Prop("scaleMode") { (view: ExpoIVSStagePreviewView, scaleMode: String) in // "fit" or "fill"
        print("DEBUG: Setting stage preview sc›aleMode to \(scaleMode)")
        view.scaleMode = scaleMode
      }
    }

    // Expose the custom view for remote stream rendering
    View(ExpoIVSRemoteStreamView.self) {
      Prop("scaleMode") { (view: ExpoIVSRemoteStreamView, scaleMode: String?) in
          view.scaleMode = scaleMode ?? "fit"
      }
    }

    // Cleanup when the module is destroyed
    OnDestroy {
        self.ivsStageManager?.leaveStage()
        self.ivsStageManager?.destroyLocalStreams()
        self.ivsStageManager = nil
    }
  }

  // MARK: - IVSStageManagerDelegate Implementation
  func stageManagerDidEmitEvent(eventName: String, body: [String : Any]?) {
    self.sendEvent(eventName, body ?? [:])
  }

  private func find<T: UIView>(viewOfType: T.Type, in view: UIView) -> T? {
    if let foundView = view as? T {
        return foundView
    }
    for subview in view.subviews {
        if let foundView = find(viewOfType: T.self, in: subview) {
            return foundView
        }
    }
    return nil
}

  // TODO: Helper functions to parse config maps into IVS SDK specific configuration objects if needed.
  // func parseAudioConfig(_ map: [String: Any]?) -> IVSLocalStageStreamAudioConfiguration? { ... }
  // func parseVideoConfig(_ map: [String: Any]?) -> IVSLocalStageStreamVideoConfiguration? { ... }
}
