package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import com.amazonaws.ivs.broadcast.BroadcastConfiguration.AspectMode
import com.amazonaws.ivs.broadcast.ImageDevice
import com.amazonaws.ivs.broadcast.ImagePreviewView
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.views.ExpoView

@RequiresApi(Build.VERSION_CODES.P)
class ExpoIVSStagePreviewView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private var ivsImagePreviewView: ImagePreviewView? = null
    private var stageManager: IVSStageManager? = null
    private var currentPreviewDeviceUrn: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Retry configuration
    private var retryCount = 0
    private val maxRetries = 15
    private val retryDelayMs = 300L

    // Props from React Native
    private var mirror: Boolean = false
    private var scaleMode: String = "fill"

    init {
        Log.i("ExpoIVSStagePreviewView", "Initializing Stage Preview View...")
        resolveStageManagerAndStreamWithRetry()
    }

    private fun resolveStageManagerAndStreamWithRetry() {
        Log.d("ExpoIVSStagePreviewView", "Attempting to resolve StageManager (attempt ${retryCount + 1})...")
        
        val manager = IVSStageManager.instance
        
        if (manager == null) {
            if (retryCount < maxRetries) {
                retryCount++
                Log.w("ExpoIVSStagePreviewView", "IVSStageManager not ready, retrying in ${retryDelayMs}ms...")
                mainHandler.postDelayed({ resolveStageManagerAndStreamWithRetry() }, retryDelayMs)
            } else {
                Log.e("ExpoIVSStagePreviewView", "IVSStageManager singleton is null after $maxRetries attempts.")
            }
            return
        }
        
        this.stageManager = manager
        Log.d("ExpoIVSStagePreviewView", "StageManager instance assigned. Registering view and attaching stream...")
        manager.registerPreviewView(this)
        attachStreamWithRetry()
    }

    private fun attachStreamWithRetry() {
        val cameraDevice = this.stageManager?.getLocalCameraDevice()

        if (cameraDevice == null) {
            // Camera not ready yet, retry
            if (retryCount < maxRetries) {
                retryCount++
                Log.w("ExpoIVSStagePreviewView", "Camera device not ready, retrying in ${retryDelayMs}ms...")
                mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
            } else {
                Log.e("ExpoIVSStagePreviewView", "Camera device not available after $maxRetries attempts.")
            }
            return
        }

        // Ensure we're on the main thread
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { attachStreamWithRetry() }
            return
        }

        val newDeviceUrn = cameraDevice.descriptor.urn

        // If preview exists for the same device, do nothing.
        if (ivsImagePreviewView != null && this.currentPreviewDeviceUrn == newDeviceUrn) {
            Log.d("ExpoIVSStagePreviewView", "Already showing preview for device: $newDeviceUrn")
            return
        }

        // Cleanup existing preview
        if (ivsImagePreviewView != null) {
            Log.d("ExpoIVSStagePreviewView", "Cleaning up existing preview")
            removeView(ivsImagePreviewView)
            ivsImagePreviewView = null
            this.currentPreviewDeviceUrn = null
        }

        try {
            Log.i("ExpoIVSStagePreviewView", "Attempting to create preview for camera: ${cameraDevice.descriptor.friendlyName}")
            
            val imageDevice = cameraDevice as? ImageDevice
            if (imageDevice == null) {
                Log.e("ExpoIVSStagePreviewView", "Camera device is not an ImageDevice")
                return
            }
            
            val newPreview = imageDevice.previewView
            if (newPreview == null) {
                // Preview view not ready yet, retry after delay
                if (retryCount < maxRetries) {
                    retryCount++
                    Log.w("ExpoIVSStagePreviewView", "Preview view is null, retrying in ${retryDelayMs}ms (attempt $retryCount)...")
                    mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
                } else {
                    Log.e("ExpoIVSStagePreviewView", "Failed to get preview view from camera after $maxRetries attempts")
                }
                return
            }
            
            // Check if preview is attached to another parent and detach it first
            if (newPreview.parent != null) {
                Log.w("ExpoIVSStagePreviewView", "Preview view already has a parent, detaching first...")
                (newPreview.parent as? android.view.ViewGroup)?.removeView(newPreview)
            }
            
            newPreview.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )

            addView(newPreview)
            this.ivsImagePreviewView = newPreview
            this.currentPreviewDeviceUrn = newDeviceUrn
            
            applyProps()
            Log.i("ExpoIVSStagePreviewView", "✅ Successfully attached camera preview for: ${cameraDevice.descriptor.friendlyName}")
        } catch (e: Exception) {
            Log.e("ExpoIVSStagePreviewView", "❌ Failed to attach camera preview: ${e.message}", e)
            this.ivsImagePreviewView = null
            this.currentPreviewDeviceUrn = null
            
            // Retry on exception as well
            if (retryCount < maxRetries) {
                retryCount++
                Log.w("ExpoIVSStagePreviewView", "Retrying after exception in ${retryDelayMs}ms (attempt $retryCount)...")
                mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
            }
        }
    }
    
    // Public method for manager to notify when camera changes (e.g., after swapCamera)
    fun refreshPreview() {
        Log.d("ExpoIVSStagePreviewView", "Refresh preview requested - clearing current preview and reattaching")
        
        // Ensure we're on the main thread
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { refreshPreview() }
            return
        }
        
        // Clear the current preview first
        if (ivsImagePreviewView != null) {
            try {
                removeView(ivsImagePreviewView)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error removing old preview view: ${e.message}")
            }
            ivsImagePreviewView = null
        }
        currentPreviewDeviceUrn = null
        
        retryCount = 0
        // Add a small delay to ensure the old preview is fully detached 
        // before attaching the new one (prevents green screen on camera swap)
        mainHandler.postDelayed({
            attachStreamWithRetry()
        }, 50)
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
            val method = ivsImagePreviewView?.javaClass?.getMethod("setPreviewAspectMode", AspectMode::class.java)
            method?.invoke(ivsImagePreviewView, aspectMode)
        } catch (e: Exception) {
            Log.w("ExpoIVSStagePreviewView", "Could not set aspect mode: ${e.message}")
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Log.d("ExpoIVSStagePreviewView", "View attached to window")
        // Re-attempt to attach if we don't have a preview yet
        if (ivsImagePreviewView == null) {
            retryCount = 0
            resolveStageManagerAndStreamWithRetry()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Log.d("ExpoIVSStagePreviewView", "View detached from window")
        // Remove any pending retries
        mainHandler.removeCallbacksAndMessages(null)
        // Unregister from manager
        stageManager?.unregisterPreviewView(this)
    }
}
