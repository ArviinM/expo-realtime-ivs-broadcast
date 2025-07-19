package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import com.amazonaws.ivs.broadcast.BroadcastConfiguration.AspectMode
import com.amazonaws.ivs.broadcast.ImageDevice
import com.amazonaws.ivs.broadcast.ImagePreviewView
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.views.ExpoView

@RequiresApi(Build.VERSION_CODES.P)
class ExpoIVSStagePreviewView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    // This will hold the native view created by the IVS SDK
    private var ivsImagePreviewView: ImagePreviewView? = null
    private var stageManager: IVSStageManager? = null
    private var currentPreviewDeviceUrn: String? = null

    // Props from React Native
    private var mirror: Boolean = false
    private var scaleMode: String = "fill"

    init {
        Log.i("ExpoIVSStagePreviewView", "Initializing Stage Preview View...")
        resolveStageManagerAndStream()
    }

    private fun resolveStageManagerAndStream() {
        Log.d("ExpoIVSStagePreviewView", "Attempting to resolve StageManager singleton...")
        this.stageManager = IVSStageManager.instance
        
        if (this.stageManager == null) {
            Log.e("ExpoIVSStagePreviewView", "IVSStageManager singleton instance is null.")
            return
        }
        Log.d("ExpoIVSStagePreviewView", "StageManager instance assigned. Attaching stream...")
        attachStream()
    }

    private fun attachStream() {
        // In Android SDK, we get the device and create a preview from it.
        // The logic here mirrors the Swift implementation.
        val cameraDevice = this.stageManager?.getLocalCameraDevice()

        if (cameraDevice == null) {
            if (ivsImagePreviewView != null) {
                removeView(ivsImagePreviewView)
                ivsImagePreviewView = null
                currentPreviewDeviceUrn = null
            }
            return
        }

        val newDeviceUrn = cameraDevice.descriptor.urn

        // If preview exists for the same device, do nothing.
        if (ivsImagePreviewView != null && this.currentPreviewDeviceUrn == newDeviceUrn) {
            return
        }

        // If preview exists for a different device, or if no preview exists, create it.
        if (ivsImagePreviewView != null) {
            removeView(ivsImagePreviewView)
            ivsImagePreviewView = null
            this.currentPreviewDeviceUrn = null
        }

        // The Android equivalent of Swift's `imageDevice.previewView()`
        try {
            val newPreview = (cameraDevice as ImageDevice).previewView
            newPreview.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )

            addView(newPreview)
            this.ivsImagePreviewView = newPreview
            this.currentPreviewDeviceUrn = newDeviceUrn
            
            // Apply props now that the view exists
            applyProps()
        } catch (e: Exception) {
            // This can happen if the device is not an ImageDevice or another SDK error occurs
            this.ivsImagePreviewView = null
            this.currentPreviewDeviceUrn = null
        }
    }
    
    private fun applyProps() {
        setMirror(this.mirror)
        setScaleMode(this.scaleMode)
    }

    // Prop setters
    fun setMirror(mirror: Boolean) {
        this.mirror = mirror
        (ivsImagePreviewView as? ImagePreviewView)?.setMirrored(this.mirror)
    }

    fun setScaleMode(mode: String) {
        this.scaleMode = mode
        val aspectMode = when (scaleMode.lowercase()) {
            "fill" -> AspectMode.FILL
            "fit" -> AspectMode.FIT
            else -> AspectMode.FIT
        }
        
        try {
            // The method `setPreviewAspectMode` is not public, so we use reflection.
            val method = ivsImagePreviewView?.javaClass?.getMethod("setPreviewAspectMode", AspectMode::class.java)
            method?.invoke(ivsImagePreviewView, aspectMode)
        } catch (e: Exception) {
            // If reflection fails, the view will use its default scaling.
        }
    }
} 