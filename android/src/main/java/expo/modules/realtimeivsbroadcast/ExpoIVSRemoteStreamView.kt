package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import com.amazonaws.ivs.broadcast.BroadcastConfiguration.AspectMode
import com.amazonaws.ivs.broadcast.Device
import com.amazonaws.ivs.broadcast.ImageDevice
import com.amazonaws.ivs.broadcast.ImagePreviewView
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.views.ExpoView

@RequiresApi(Build.VERSION_CODES.P)
class ExpoIVSRemoteStreamView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private var ivsImagePreviewView: ImagePreviewView? = null
    private var stageManager: IVSStageManager? = null

    // The only state this view knows is what it's currently showing
    var currentRenderedDeviceUrn: String? = null
        private set

    // Props
    private var scaleMode: String = "fit"

    init {
        resolveStageManager()
    }
    
    private fun resolveStageManager() {
        appContext.legacyModule<ExpoRealtimeIvsBroadcastModule>()?.let {
            this.stageManager = it.ivsStageManager
            // Announce its existence to the manager so it can be used as a canvas
            it.ivsStageManager?.registerRemoteView(this)
        }
    }

    // This is the command the manager will issue to this view
    fun renderStream(device: Device) {
        if (device.descriptor.urn == this.currentRenderedDeviceUrn) {
            return // Already rendering this device
        }

        cleanupStreamView()

        try {
            val newPreview = (device as ImageDevice).previewView
            newPreview.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )

            this.ivsImagePreviewView = newPreview
            this.currentRenderedDeviceUrn = device.descriptor.urn
            addView(newPreview)
            
            applyProps()
        } catch (e: Exception) {
            // Handle exceptions, e.g., if the device is not an ImageDevice
            cleanupStreamView()
        }
    }
    
    fun clearStream() {
        cleanupStreamView()
    }

    private fun cleanupStreamView() {
        if (ivsImagePreviewView != null) {
            removeView(ivsImagePreviewView)
            ivsImagePreviewView = null
        }
        currentRenderedDeviceUrn = null
    }

    private fun applyProps() {
        setScaleMode(this.scaleMode)
    }

    fun setScaleMode(mode: String) {
        this.scaleMode = mode
        val aspectMode = when (scaleMode.lowercase()) {
            "fill" -> AspectMode.FILL
            "fit" -> AspectMode.FIT
            else -> AspectMode.FIT
        }
        try {
            // Use reflection to set the aspect mode, as there is no public method.
            val method = ivsImagePreviewView?.javaClass?.getMethod("setPreviewAspectMode", AspectMode::class.java)
            method?.invoke(ivsImagePreviewView, aspectMode)
        } catch (e: Exception) {
            // If the method doesn't exist or fails, the default scale mode will be used.
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        // Clean up when the view is removed from the UI
        stageManager?.unregisterRemoteView(this)
        cleanupStreamView()
    }
} 