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
    var ivsStageManager: IVSStageManager? = null

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
            val reactContext = appContext.reactContext ?: throw Exceptions.ReactContextLost()
            ivsStageManager = IVSStageManager(reactContext)
            ivsStageManager?.delegate = this@ExpoRealtimeIvsBroadcastModule
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

        AsyncFunction("initialize") { audioConfig: Map<String, Any>?, videoConfig: Map<String, Any>? ->
            // In the current Android SDK, audio and video configurations are not passed during
            // the initial setup in the same way. They are configured on the LocalStageStream.
            // This function will primarily just call initializeStage on the manager.
            // We can extend this later to parse the config maps if needed.
            ivsStageManager?.initializeStage(audioConfig = null, videoConfig = null)
        }

        AsyncFunction("joinStage") { token: String, options: Map<String, Any>? ->
            val targetId = options?.get("targetParticipantId") as? String
            ivsStageManager?.joinStage(token, targetId)
        }

        AsyncFunction("leaveStage") {
            ivsStageManager?.leaveStage()
        }

        AsyncFunction("setStreamsPublished") { published: Boolean ->
            ivsStageManager?.setStreamsPublished(published)
        }

        AsyncFunction("swapCamera") {
            ivsStageManager?.swapCamera()
        }

        AsyncFunction("setMicrophoneMuted") { muted: Boolean ->
            ivsStageManager?.setMicrophoneMuted(muted)
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
