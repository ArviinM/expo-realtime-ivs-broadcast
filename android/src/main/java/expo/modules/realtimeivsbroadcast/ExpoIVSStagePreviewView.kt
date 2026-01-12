package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewTreeObserver
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
    
    // Track view attachment state
    @Volatile
    private var isViewAttached = false

    init {
        Log.i("ExpoIVSStagePreviewView", "Initializing Stage Preview View...")
        // Start initialization immediately - don't wait for onAttachedToWindow
        // This ensures the preview is ready when the view becomes visible
        resolveStageManagerAndStreamWithRetry()
    }
    
    // Override onLayout to ensure child views are properly sized
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        
        // Manually layout children to fill the entire view
        val childWidth = right - left
        val childHeight = bottom - top
        
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            child.layout(0, 0, childWidth, childHeight)
        }
        
        Log.d("ExpoIVSStagePreviewView", "📐 onLayout: ${childWidth}x${childHeight}, children: $childCount")
    }
    
    // Override onMeasure to properly measure children
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        
        // Measure all children with exact dimensions
        val childWidthSpec = MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            child.measure(childWidthSpec, childHeightSpec)
        }
        
        Log.d("ExpoIVSStagePreviewView", "📐 onMeasure: ${width}x${height}")
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
        Log.i("ExpoIVSStagePreviewView", "📷 attachStreamWithRetry - Camera: ${cameraDevice.descriptor.friendlyName}, URN: $newDeviceUrn")
        Log.i("ExpoIVSStagePreviewView", "📷 Current preview URN: $currentPreviewDeviceUrn, Has preview: ${ivsImagePreviewView != null}")

        if (ivsImagePreviewView != null && this.currentPreviewDeviceUrn == newDeviceUrn) {
            Log.d("ExpoIVSStagePreviewView", "Already showing preview for device: $newDeviceUrn")
            return
        }

        // Cleanup existing preview
        if (ivsImagePreviewView != null) {
            Log.d("ExpoIVSStagePreviewView", "Cleaning up existing preview")
            try {
                removeView(ivsImagePreviewView)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error removing old preview: ${e.message}")
            }
            ivsImagePreviewView = null
            currentPreviewDeviceUrn = null
        }

        try {
            Log.i("ExpoIVSStagePreviewView", "Attempting to create preview for camera: ${cameraDevice.descriptor.friendlyName}")
            
            val imageDevice = cameraDevice as? ImageDevice
            if (imageDevice == null) {
                Log.e("ExpoIVSStagePreviewView", "Camera device is not an ImageDevice")
                return
            }
            
            // Use getPreviewView() with aspect mode to get a fresh preview view
            // This is more reliable than using the previewView property after camera swap
            val newPreview = try {
                imageDevice.getPreviewView(AspectMode.FILL)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "getPreviewView(FILL) failed, trying previewView property: ${e.message}")
                imageDevice.previewView
            }
            
            if (newPreview == null) {
                if (retryCount < maxRetries) {
                    retryCount++
                    Log.w("ExpoIVSStagePreviewView", "Preview view is null, retrying in ${retryDelayMs}ms (attempt $retryCount)...")
                    mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
                } else {
                    Log.e("ExpoIVSStagePreviewView", "Failed to get preview view from camera after $maxRetries attempts")
                }
                return
            }
            
            Log.i("ExpoIVSStagePreviewView", "📷 Got preview view: ${newPreview.javaClass.simpleName}, hashCode: ${newPreview.hashCode()}")
            
            // IMPORTANT: Check if preview is attached to another parent and detach it first
            val existingParent = newPreview.parent
            if (existingParent != null && existingParent != this) {
                Log.w("ExpoIVSStagePreviewView", "Preview view has another parent, detaching first...")
                (existingParent as? android.view.ViewGroup)?.removeView(newPreview)
            }
            
            // If already attached to this view, no need to re-add
            if (newPreview.parent == this) {
                Log.d("ExpoIVSStagePreviewView", "Preview already attached to this view")
                this.ivsImagePreviewView = newPreview
                this.currentPreviewDeviceUrn = newDeviceUrn
                applyProps()
                return
            }
            
            newPreview.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )

            addView(newPreview)
            this.ivsImagePreviewView = newPreview
            this.currentPreviewDeviceUrn = newDeviceUrn
            
            applyProps()
            
            // Force layout update - measure and layout immediately with current dimensions
            if (width > 0 && height > 0) {
                val widthSpec = MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
                val heightSpec = MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
                newPreview.measure(widthSpec, heightSpec)
                newPreview.layout(0, 0, width, height)
                Log.i("ExpoIVSStagePreviewView", "📐 Forced layout: preview now ${newPreview.measuredWidth}x${newPreview.measuredHeight}")
            } else {
                // Parent not yet measured, use ViewTreeObserver to layout after measure
                viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
                    override fun onGlobalLayout() {
                        viewTreeObserver.removeOnGlobalLayoutListener(this)
                        val preview = ivsImagePreviewView ?: return
                        if (this@ExpoIVSStagePreviewView.width > 0 && this@ExpoIVSStagePreviewView.height > 0) {
                            val w = this@ExpoIVSStagePreviewView.width
                            val h = this@ExpoIVSStagePreviewView.height
                            val wSpec = MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY)
                            val hSpec = MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY)
                            preview.measure(wSpec, hSpec)
                            preview.layout(0, 0, w, h)
                            Log.i("ExpoIVSStagePreviewView", "📐 Deferred layout: preview now ${preview.measuredWidth}x${preview.measuredHeight}")
                        }
                    }
                })
            }
            
            // Also request layout for next frame
            newPreview.requestLayout()
            requestLayout()
            invalidate()
            
            Log.i("ExpoIVSStagePreviewView", "✅ Successfully attached camera preview for: ${cameraDevice.descriptor.friendlyName}")
            Log.i("ExpoIVSStagePreviewView", "📷 Preview dimensions: ${newPreview.width}x${newPreview.height}, visibility: ${newPreview.visibility}")
            Log.i("ExpoIVSStagePreviewView", "📷 Parent dimensions: ${this.width}x${this.height}, childCount: ${this.childCount}")
        } catch (e: Exception) {
            Log.e("ExpoIVSStagePreviewView", "❌ Failed to attach camera preview: ${e.message}", e)
            this.ivsImagePreviewView = null
            this.currentPreviewDeviceUrn = null
            
            if (retryCount < maxRetries) {
                retryCount++
                Log.w("ExpoIVSStagePreviewView", "Retrying after exception in ${retryDelayMs}ms (attempt $retryCount)...")
                mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
            }
        }
    }
    
    // Public method for manager to notify when camera changes (e.g., after swapCamera)
    fun refreshPreview() {
        Log.i("ExpoIVSStagePreviewView", "🔄 Refresh preview requested - clearing current preview and reattaching")
        Log.i("ExpoIVSStagePreviewView", "🔄 Current URN before refresh: $currentPreviewDeviceUrn")
        
        // Ensure we're on the main thread
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { refreshPreview() }
            return
        }
        
        // Clear the current preview first
        val oldPreview = ivsImagePreviewView
        if (oldPreview != null) {
            Log.i("ExpoIVSStagePreviewView", "🔄 Removing old preview view")
            try {
                removeView(oldPreview)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error removing old preview view: ${e.message}")
            }
            ivsImagePreviewView = null
        }
        
        // IMPORTANT: Clear the URN so attachStreamWithRetry will fetch a fresh preview
        currentPreviewDeviceUrn = null
        
        retryCount = 0
        // Add a delay to allow the new camera stream to initialize
        mainHandler.postDelayed({
            Log.i("ExpoIVSStagePreviewView", "🔄 Now attaching new preview after delay")
            attachStreamWithRetry()
        }, 200)
    }
    
    private fun applyProps() {
        setMirror(this.mirror)
        setScaleMode(this.scaleMode)
    }

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
        isViewAttached = true
        Log.d("ExpoIVSStagePreviewView", "View attached to window")
        
        // If we don't have a preview yet, try to attach one
        if (ivsImagePreviewView == null) {
            retryCount = 0
            resolveStageManagerAndStreamWithRetry()
        } else {
            // Re-add the preview if it was removed during detach
            val preview = ivsImagePreviewView
            if (preview != null && preview.parent == null) {
                Log.d("ExpoIVSStagePreviewView", "Re-adding preview on attach")
                try {
                    addView(preview)
                } catch (e: Exception) {
                    Log.w("ExpoIVSStagePreviewView", "Error re-adding preview: ${e.message}")
                    // Try fresh attach
                    ivsImagePreviewView = null
                    currentPreviewDeviceUrn = null
                    retryCount = 0
                    attachStreamWithRetry()
                }
            }
        }
    }

    override fun onDetachedFromWindow() {
        Log.d("ExpoIVSStagePreviewView", "View detached from window")
        isViewAttached = false
        
        // Remove pending callbacks
        mainHandler.removeCallbacksAndMessages(null)
        
        // Remove the preview view from this parent so it can be reused
        // Do this in a post to avoid conflicts with the current render cycle
        val preview = ivsImagePreviewView
        if (preview != null) {
            mainHandler.post {
                try {
                    if (preview.parent == this) {
                        removeView(preview)
                        Log.d("ExpoIVSStagePreviewView", "Preview removed in post")
                    }
                } catch (e: Exception) {
                    Log.w("ExpoIVSStagePreviewView", "Error removing preview in post: ${e.message}")
                }
            }
        }
        
        // Clear references
        ivsImagePreviewView = null
        currentPreviewDeviceUrn = null
        
        // Unregister from manager
        stageManager?.unregisterPreviewView(this)
        
        super.onDetachedFromWindow()
    }
}
