package expo.modules.realtimeivsbroadcast

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import android.util.Log
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.exception.Exceptions

class ExpoRealtimeIvsBroadcastModule : Module(), IVSStageManagerDelegate, PictureInPictureDelegate {
    
    // PiP Manager reference (lazy initialized)
    private val pipManager: PictureInPictureManager? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PictureInPictureManager.getInstance().also {
                it.delegate = this
            }
        } else null
    }
    
    @RequiresApi(Build.VERSION_CODES.P)
    override fun definition() = ModuleDefinition {
        Name("ExpoRealtimeIvsBroadcast")

        Events(
            "onStageConnectionStateChanged",
            "onParticipantJoined",
            "onParticipantLeft",
            "onParticipantStreamsAdded",
            "onParticipantStreamsRemoved",
            "onPublishStateChanged",
            "onStageError",
            "onPiPStateChanged",
            "onPiPError",
            "onCameraMuteStateChanged",
            "onCameraSwapped",
            "onCameraSwapError"
        )

        OnCreate {
            Log.i("ExpoRealtimeIvsBroadcast", "Module OnCreate - Initializing IVSStageManager...")
            if (IVSStageManager.instance == null) {
                val reactContext = appContext.reactContext ?: throw Exceptions.ReactContextLost()
                IVSStageManager(reactContext)
                Log.i("ExpoRealtimeIvsBroadcast", "IVSStageManager instance created")
            } else {
                Log.i("ExpoRealtimeIvsBroadcast", "IVSStageManager instance already exists")
            }
            IVSStageManager.instance?.delegate = this@ExpoRealtimeIvsBroadcastModule
        }

        // --- Module Functions ---

        AsyncFunction("requestPermissions") {
            val reactContext = appContext.reactContext ?: throw Exceptions.ReactContextLost()
            
            val cameraStatus = ContextCompat.checkSelfPermission(reactContext, Manifest.permission.CAMERA)
            val microphoneStatus = ContextCompat.checkSelfPermission(reactContext, Manifest.permission.RECORD_AUDIO)

            return@AsyncFunction mapOf(
                "camera" to if (cameraStatus == PackageManager.PERMISSION_GRANTED) "granted" else "denied",
                "microphone" to if (microphoneStatus == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
            )
        }

        AsyncFunction("initializeStage") { audioConfig: Map<String, Any>?, videoConfig: Map<String, Any>? ->
            // TODO: Add audioConfig and videoConfig
            IVSStageManager.instance?.initializeStage(audioConfig = null, videoConfig = null)
        }

        AsyncFunction("initializeLocalStreams") { audioConfig: Map<String, Any>?, videoConfig: Map<String, Any>? ->
            // TODO: Add audioConfig and videoConfig
            IVSStageManager.instance?.initializeLocalStreams()
        }

        AsyncFunction("joinStage") { token: String, options: Map<String, Any>? ->
            val targetId = options?.get("targetParticipantId") as? String
            IVSStageManager.instance?.joinStage(token, targetId)
        }

        AsyncFunction("leaveStage") {
            IVSStageManager.instance?.leaveStage()
        }

        AsyncFunction("setStreamsPublished") { published: Boolean ->
            IVSStageManager.instance?.setStreamsPublished(published)
        }

        AsyncFunction("swapCamera") {
            IVSStageManager.instance?.swapCamera()
        }

        AsyncFunction("setMicrophoneMuted") { muted: Boolean ->
            IVSStageManager.instance?.setMicrophoneMuted(muted)
        }

        AsyncFunction("setCameraMuted") { muted: Boolean, placeholderText: String? ->
            // TODO: Implement camera mute with placeholder frames on Android
            // For now, just emit the event so JS state stays in sync
            Log.d("ExpoRealtimeIvsBroadcast", "setCameraMuted called: muted=$muted, text=$placeholderText")
            sendEvent("onCameraMuteStateChanged", mapOf(
                "muted" to muted,
                "placeholderActive" to false // Placeholder not implemented on Android yet
            ))
        }

        AsyncFunction("isCameraMuted") {
            // TODO: Implement actual camera mute state tracking on Android
            return@AsyncFunction false
        }

        // --- Picture-in-Picture Methods ---
        
        AsyncFunction("enablePictureInPicture") { options: Map<String, Any>? ->
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                Log.w("ExpoRealtimeIvsBroadcast", "PiP requires Android O (API 26) or higher")
                return@AsyncFunction false
            }
            
            val activity = appContext.currentActivity
            if (activity == null) {
                Log.e("ExpoRealtimeIvsBroadcast", "No activity available for PiP")
                return@AsyncFunction false
            }
            
            val pipOptions = PiPOptions().apply {
                options?.let { opts ->
                    (opts["autoEnterOnBackground"] as? Boolean)?.let { autoEnterOnBackground = it }
                    (opts["sourceView"] as? String)?.let { 
                        sourceView = if (it == "local") PiPOptions.PiPSourceView.LOCAL else PiPOptions.PiPSourceView.REMOTE
                    }
                    (opts["preferredAspectRatio"] as? Map<*, *>)?.let { ratio ->
                        val width = (ratio["width"] as? Number)?.toInt() ?: 9
                        val height = (ratio["height"] as? Number)?.toInt() ?: 16
                        preferredAspectRatio = Rational(width, height)
                    }
                }
            }
            
            return@AsyncFunction pipManager?.enable(activity, pipOptions) ?: false
        }
        
        AsyncFunction("disablePictureInPicture") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                pipManager?.disable()
            }
        }
        
        AsyncFunction("startPictureInPicture") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                pipManager?.start()
            }
        }
        
        AsyncFunction("stopPictureInPicture") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                pipManager?.stop()
            }
        }
        
        AsyncFunction("isPictureInPictureActive") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                return@AsyncFunction pipManager?.isActive() ?: false
            }
            return@AsyncFunction false
        }
        
        AsyncFunction("isPictureInPictureSupported") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val activity = appContext.currentActivity
                return@AsyncFunction if (activity != null) {
                    pipManager?.isPiPSupported(activity) ?: false
                } else false
            }
            return@AsyncFunction false
        }

        // --- View Definitions ---
        
        View(ExpoIVSStagePreviewView::class) {
            Prop("mirror") { view: ExpoIVSStagePreviewView, mirror: Boolean ->
                view.setMirror(mirror)
            }
            Prop("scaleMode") { view: ExpoIVSStagePreviewView, scaleMode: String ->
                view.setScaleMode(scaleMode)
            }
        }

        View(ExpoIVSRemoteStreamView::class) {
            // This view is "dumb" and managed by the IVSStageManager.
            // It only needs a scaleMode prop for visual configuration.
            Prop("scaleMode") { view: ExpoIVSRemoteStreamView, scaleMode: String ->
                view.setScaleMode(scaleMode)
            }
        }
    }

    // --- IVSStageManagerDelegate Implementation ---

    override fun stageManagerDidEmitEvent(eventName: String, body: Map<String, Any?>) {
        sendEvent(eventName, body)
    }
    
    // --- PictureInPictureDelegate Implementation ---
    
    override fun onPiPStateChanged(state: String) {
        sendEvent("onPiPStateChanged", mapOf("state" to state))
    }
    
    override fun onPiPError(error: String) {
        sendEvent("onPiPError", mapOf("error" to error))
    }
}
