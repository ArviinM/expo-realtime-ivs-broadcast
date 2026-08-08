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
    Events(
      "onStageConnectionStateChanged",
      "onPublishStateChanged",
      "onStageError",
      "onCameraSwapped",
      "onCameraSwapError",
      "onParticipantJoined",
      "onParticipantLeft",
      "onParticipantStreamsAdded",
      "onParticipantStreamsRemoved",
      "onPiPStateChanged",
      "onPiPError",
      "onCameraMuteStateChanged",
      "onAudioRouteChanged",
      "onAudioInterruption",
      "onAudioLevel",
      "onRTCStats",
      "onRemoteMuteStateChanged",
      "onSubscribeStateChanged",
      "onThermalStateChanged",
      "onPiPSourceValidityChanged"
    )

    // Initialize the IVSStageManager when the module is created
    // and set self as its delegate.
    OnCreate {
      self.ivsStageManager = IVSStageManager()
      self.ivsStageManager?.delegate = self
    }

    // --- Methods Exposed to JS ---

    AsyncFunction("initializeStage") { (audioConfigMap: [String: Any]?, videoConfigMap: [String: Any]?) -> Void in
      self.ivsStageManager?.initializeStage(audioConfigMap: audioConfigMap, videoConfigMap: videoConfigMap)
    }

    // Pinned to main. Expo's AsyncFunction dispatches to a background queue by
    // default (AsyncFunctionDefinition.swift: `defaultQueue = DispatchQueue(...)`),
    // and this path builds an AVCaptureVideoPreviewLayer and mutates its
    // videoGravity/transform — CoreAnimation work that must not run off-main.
    AsyncFunction("initializeLocalStreams") { (audioConfigMap: [String: Any]?, videoConfigMap: [String: Any]?) -> Void in
        self.ivsStageManager?.initializeLocalStreams(audioConfigMap: audioConfigMap, videoConfigMap: videoConfigMap)
    }.runOnQueue(.main)

    // Pinned to main: tears down the capture session and its preview layer.
    AsyncFunction("destroyLocalStreams") {
        self.ivsStageManager?.destroyLocalStreams()
    }.runOnQueue(.main)

    AsyncFunction("joinStage") { (token: String, options: [String: Any]?) in
      let targetId = options?["targetParticipantId"] as? String
      self.ivsStageManager?.joinStage(token: token, targetParticipantId: targetId)
    }

    // Pinned to main. MINE-APP-3X was an EXC_BAD_ACCESS inside the SDK
    // (`-[IVSStage leave]` → `-[IVSStageSession logger]`) reached from a
    // dispatch worker thread — the default queue Expo hands AsyncFunction. The
    // stage APIs are not thread-safe, and tearing one down off-main races the
    // SDK's own callbacks onto a half-freed session.
    AsyncFunction("leaveStage") {
      self.ivsStageManager?.leaveStage()
    }.runOnQueue(.main)

    AsyncFunction("setStreamsPublished") { (published: Bool) in
      self.ivsStageManager?.setStreamsPublished(published: published)
    }

    // Pinned to main. This is the highest-risk off-main path in the module: it
    // re-runs setupCaptureSession() and rebuilds the preview layer, and it is
    // reachable MID-BROADCAST every time the seller flips to the back camera to
    // show a product. Off-main CoreAnimation there is a live crash.
    AsyncFunction("swapCamera") {
      self.ivsStageManager?.swapCamera()
    }.runOnQueue(.main)

    AsyncFunction("setMicrophoneMuted") { (muted: Bool) in
      self.ivsStageManager?.setMicrophoneMuted(muted: muted)
    }

    AsyncFunction("setCameraMuted") { (muted: Bool, placeholderText: String?) in
      self.ivsStageManager?.setCameraMuted(muted: muted, placeholderText: placeholderText)
    }

    AsyncFunction("isCameraMuted") { () -> Bool in
      return self.ivsStageManager?.isCameraMuted() ?? false
    }

    // MARK: - Audio API

    AsyncFunction("setAudioPreset") { (preset: String) in
      self.ivsStageManager?.setAudioPreset(preset)
    }

    AsyncFunction("listAudioInputs") { () -> [[String: Any]] in
      return self.ivsStageManager?.listAudioInputs() ?? []
    }

    AsyncFunction("setPreferredAudioInput") { (urn: String?) in
      self.ivsStageManager?.setPreferredAudioInput(urn: urn)
    }

    AsyncFunction("setInputGain") { (gain: Double) -> Bool in
      return self.ivsStageManager?.setInputGain(gain: Float(gain)) ?? false
    }

    // MARK: - Mock Mode

    AsyncFunction("setMockMode") { (enabled: Bool) in
      self.ivsStageManager?.setMockMode(enabled: enabled)
    }

    // MARK: - Observability / Background

    AsyncFunction("setBackgroundBehavior") { (options: [String: Any]?) in
      self.ivsStageManager?.setBackgroundBehavior(options: options)
    }

    AsyncFunction("requestRTCStats") { () -> [String: Any] in
      return self.ivsStageManager?.snapshotRTCStats() ?? [:]
    }

    // MARK: - Thermal Adaptation

    AsyncFunction("setThermalMitigation") { (options: [String: Any]?) in
      self.ivsStageManager?.setThermalMitigation(options: options)
    }

    AsyncFunction("getThermalState") { () -> String in
      return self.ivsStageManager?.currentThermalState() ?? "nominal"
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
    //
    // All six are pinned to main. Two reasons, both real:
    //
    //  1. AVPictureInPictureController is UIKit-adjacent and must be constructed
    //     and driven on the main thread. The lazy `pipController` getter in
    //     IVSStageManager is not thread-safe, so two of these arriving on the
    //     shared Expo async queue could race and build it twice.
    //  2. IVSPictureInPictureController has two `DispatchQueue.main.sync` calls
    //     guarded by `Thread.isMainThread`. Reaching those from a background
    //     queue while main is busy is a classic deadlock into a watchdog kill.
    //     Running here on main makes the guard short-circuit instead.

    AsyncFunction("enablePictureInPicture") { (options: [String: Any]?) -> Bool in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.enablePictureInPicture(options: options)
        return true
      } else {
        print("PiP requires iOS 15.0 or later")
        return false
      }
    }.runOnQueue(.main)

    AsyncFunction("disablePictureInPicture") { () -> Void in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.disablePictureInPicture()
      }
    }.runOnQueue(.main)

    AsyncFunction("startPictureInPicture") { () -> Void in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.startPictureInPicture()
      }
    }.runOnQueue(.main)

    AsyncFunction("stopPictureInPicture") { () -> Void in
      if #available(iOS 15.0, *) {
        self.ivsStageManager?.stopPictureInPicture()
      }
    }.runOnQueue(.main)

    AsyncFunction("isPictureInPictureActive") { () -> Bool in
      if #available(iOS 15.0, *) {
        return self.ivsStageManager?.isPictureInPictureActive() ?? false
      }
      return false
    }.runOnQueue(.main)

    AsyncFunction("isPictureInPictureSupported") { () -> Bool in
      if #available(iOS 15.0, *) {
        return AVPictureInPictureController.isPictureInPictureSupported()
      }
      return false
    }.runOnQueue(.main)

    AsyncFunction("isPiPRemoteSourceValid") { () -> Bool in
      return self.ivsStageManager?.isPiPRemoteSourceValid() ?? false
    }

    View(ExpoIVSStagePreviewView.self) {
      Prop("mirror") { (view: ExpoIVSStagePreviewView, mirror: Bool) in
        view.mirror = mirror
      }

      Prop("scaleMode") { (view: ExpoIVSStagePreviewView, scaleMode: String) in
        // Validate enum: only "fit" or "fill" are accepted; anything else falls back to "fit".
        let normalized = (scaleMode == "fit" || scaleMode == "fill") ? scaleMode : "fit"
        if normalized != scaleMode {
          print("⚠️ [ExpoRealtimeIvsBroadcast] Invalid scaleMode '\(scaleMode)' — defaulting to 'fit'. Valid: 'fit' | 'fill'.")
        }
        view.scaleMode = normalized
      }
    }

    // Expose the custom view for remote stream rendering
    View(ExpoIVSRemoteStreamView.self) {
      Prop("scaleMode") { (view: ExpoIVSRemoteStreamView, scaleMode: String?) in
        let raw = scaleMode ?? "fit"
        let normalized = (raw == "fit" || raw == "fill") ? raw : "fit"
        if normalized != raw {
          print("⚠️ [ExpoRealtimeIvsBroadcast] Invalid scaleMode '\(raw)' — defaulting to 'fit'.")
        }
        view.scaleMode = normalized
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
}
