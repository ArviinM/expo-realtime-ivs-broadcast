package expo.modules.realtimeivsbroadcast

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.exception.Exceptions

class ExpoRealtimeIvsBroadcastModule : Module(), IVSStageManagerDelegate {
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
            "onStageError"
        )

        OnCreate {
            if (IVSStageManager.instance == null) {
                val reactContext = appContext.reactContext ?: throw Exceptions.ReactContextLost()
                IVSStageManager(reactContext)
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
}
