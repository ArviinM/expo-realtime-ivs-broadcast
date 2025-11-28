package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // Retry configuration
    private var retryCount = 0
    private val maxRetries = 10
    private val retryDelayMs = 200L

    // The only state this view knows is what it's currently showing
    var currentRenderedDeviceUrn: String? = null
        private set

    // Props
    private var scaleMode: String = "fill"

    init {
        Log.i("ExpoIVSRemoteStreamView", "Initializing Remote Stream View...")
        resolveStageManagerWithRetry()
    }
    
    private fun resolveStageManagerWithRetry() {
        Log.d("ExpoIVSRemoteStreamView", "Attempting to resolve StageManager singleton (attempt ${retryCount + 1})...")
        
        val manager = IVSStageManager.instance
        
        if (manager == null) {
            if (retryCount < maxRetries) {
                retryCount++
                Log.w("ExpoIVSRemoteStreamView", "IVSStageManager not ready, retrying in ${retryDelayMs}ms...")
                mainHandler.postDelayed({ resolveStageManagerWithRetry() }, retryDelayMs)
            } else {
                Log.e("ExpoIVSRemoteStreamView", "IVSStageManager singleton is null after $maxRetries attempts.")
            }
            return
        }
        
        this.stageManager = manager
        Log.d("ExpoIVSRemoteStreamView", "StageManager instance assigned. Registering view...")
        manager.registerRemoteView(this)
    }

    // This is the command the manager will issue to this view
    fun renderStream(device: Device) {
        // Ensure we're on the main thread for UI operations
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { renderStream(device) }
            return
        }
        
        if (device.descriptor.urn == this.currentRenderedDeviceUrn) {
            Log.d("ExpoIVSRemoteStreamView", "Already rendering device: ${device.descriptor.urn}")
            return // Already rendering this device
        }

        cleanupStreamView()

        try {
            Log.i("ExpoIVSRemoteStreamView", "Attempting to render stream for device: ${device.descriptor.urn}")
            
            val imageDevice = device as? ImageDevice
            if (imageDevice == null) {
                Log.e("ExpoIVSRemoteStreamView", "Device is not an ImageDevice: ${device.descriptor.type}")
                return
            }
            
            val newPreview = imageDevice.previewView
            if (newPreview == null) {
                Log.e("ExpoIVSRemoteStreamView", "Failed to get preview view from ImageDevice")
                return
            }
            
            newPreview.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )

            this.ivsImagePreviewView = newPreview
            this.currentRenderedDeviceUrn = device.descriptor.urn
            addView(newPreview)
            
            applyProps()
            Log.i("ExpoIVSRemoteStreamView", "✅ Successfully rendering stream for device: ${device.descriptor.urn}")
        } catch (e: Exception) {
            Log.e("ExpoIVSRemoteStreamView", "❌ Failed to render stream: ${e.message}", e)
            cleanupStreamView()
        }
    }
    
    fun clearStream() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { clearStream() }
            return
        }
        cleanupStreamView()
    }

    private fun cleanupStreamView() {
        if (ivsImagePreviewView != null) {
            Log.d("ExpoIVSRemoteStreamView", "Cleaning up stream view")
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
            val method = ivsImagePreviewView?.javaClass?.getMethod("setPreviewAspectMode", AspectMode::class.java)
            method?.invoke(ivsImagePreviewView, aspectMode)
        } catch (e: Exception) {
            Log.w("ExpoIVSRemoteStreamView", "Could not set aspect mode: ${e.message}")
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Log.d("ExpoIVSRemoteStreamView", "View attached to window")
        // Re-register if we lost the manager reference
        if (stageManager == null) {
            retryCount = 0
            resolveStageManagerWithRetry()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Log.d("ExpoIVSRemoteStreamView", "View detached from window")
        // Remove any pending retries
        mainHandler.removeCallbacksAndMessages(null)
        stageManager?.unregisterRemoteView(this)
        cleanupStreamView()
    }
}
