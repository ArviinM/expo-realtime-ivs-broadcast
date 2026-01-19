package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
        // Note: We don't start initialization here because isViewAttached is false
        // The initialization will happen in onAttachedToWindow when the view is ready
    }
    
    // Override onLayout to ensure child views are properly sized
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        
        // Manually layout children to fill the entire view
        val childWidth = right - left
        val childHeight = bottom - top
        
        // Use safe iteration - get count once and check for null children
        val count = childCount
        for (i in 0 until count) {
            val child = getChildAt(i) ?: continue // Skip null children
            try {
                child.layout(0, 0, childWidth, childHeight)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error laying out child $i: ${e.message}")
            }
        }
        
        Log.d("ExpoIVSStagePreviewView", "📐 onLayout: ${childWidth}x${childHeight}, children: $count")
    }
    
    // Override onMeasure to properly measure children
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        
        // Measure all children with exact dimensions
        val childWidthSpec = MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        
        // Use safe iteration - get count once and check for null children
        val count = childCount
        for (i in 0 until count) {
            val child = getChildAt(i) ?: continue // Skip null children
            try {
                child.measure(childWidthSpec, childHeightSpec)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error measuring child $i: ${e.message}")
            }
        }
        
        Log.d("ExpoIVSStagePreviewView", "📐 onMeasure: ${width}x${height}")
    }

    private fun resolveStageManagerAndStreamWithRetry() {
        // Guard: Don't proceed if view is not attached
        if (!isViewAttached) {
            Log.w("ExpoIVSStagePreviewView", "⚠️ View not attached, skipping resolveStageManagerAndStreamWithRetry")
            return
        }
        
        Log.d("ExpoIVSStagePreviewView", "Attempting to resolve StageManager (attempt ${retryCount + 1})...")
        
        val manager = IVSStageManager.instance
        
        if (manager == null) {
            if (retryCount < maxRetries && isViewAttached) {
                retryCount++
                Log.w("ExpoIVSStagePreviewView", "IVSStageManager not ready, retrying in ${retryDelayMs}ms...")
                mainHandler.postDelayed({ resolveStageManagerAndStreamWithRetry() }, retryDelayMs)
            } else {
                Log.e("ExpoIVSStagePreviewView", "IVSStageManager singleton is null after $maxRetries attempts or view detached.")
            }
            return
        }
        
        this.stageManager = manager
        Log.d("ExpoIVSStagePreviewView", "StageManager instance assigned. Registering view and attaching stream...")
        manager.registerPreviewView(this)
        attachStreamWithRetry()
    }

    private fun attachStreamWithRetry() {
        // Guard: Don't attach if view is not attached to window
        if (!isViewAttached) {
            Log.w("ExpoIVSStagePreviewView", "⚠️ View not attached to window, skipping attachStreamWithRetry")
            return
        }
        
        val cameraDevice = this.stageManager?.getLocalCameraDevice()

        if (cameraDevice == null) {
            if (retryCount < maxRetries && isViewAttached) {
                retryCount++
                Log.w("ExpoIVSStagePreviewView", "Camera device not ready, retrying in ${retryDelayMs}ms...")
                mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
            } else {
                Log.e("ExpoIVSStagePreviewView", "Camera device not available after $maxRetries attempts or view detached.")
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

        // Cleanup existing preview - clear references first, then remove view
        val oldPreview = ivsImagePreviewView
        if (oldPreview != null) {
            Log.d("ExpoIVSStagePreviewView", "Cleaning up existing preview")
            ivsImagePreviewView = null
            currentPreviewDeviceUrn = null
            if (oldPreview.parent == this) {
                try {
                    removeView(oldPreview)
                } catch (e: Exception) {
                    Log.w("ExpoIVSStagePreviewView", "Error removing old preview: ${e.message}")
                }
            }
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
                if (retryCount < maxRetries && isViewAttached) {
                    retryCount++
                    Log.w("ExpoIVSStagePreviewView", "Preview view is null, retrying in ${retryDelayMs}ms (attempt $retryCount)...")
                    mainHandler.postDelayed({ attachStreamWithRetry() }, retryDelayMs)
                } else {
                    Log.e("ExpoIVSStagePreviewView", "Failed to get preview view from camera after $maxRetries attempts or view detached")
                }
                return
            }
            
            Log.i("ExpoIVSStagePreviewView", "📷 Got preview view: ${newPreview.javaClass.simpleName}, hashCode: ${newPreview.hashCode()}")
            
            // Double-check we're still attached before modifying view hierarchy
            if (!isViewAttached) {
                Log.w("ExpoIVSStagePreviewView", "⚠️ View detached while getting preview, aborting")
                return
            }
            
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
            
            // Final check before adding view
            if (!isViewAttached) {
                Log.w("ExpoIVSStagePreviewView", "⚠️ View detached before addView, aborting")
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
                        // Guard: check if still attached and preview exists
                        if (!isViewAttached) {
                            Log.w("ExpoIVSStagePreviewView", "📐 Deferred layout skipped - view detached")
                            return
                        }
                        val preview = ivsImagePreviewView ?: return
                        if (this@ExpoIVSStagePreviewView.width > 0 && this@ExpoIVSStagePreviewView.height > 0) {
                            val w = this@ExpoIVSStagePreviewView.width
                            val h = this@ExpoIVSStagePreviewView.height
                            val wSpec = MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY)
                            val hSpec = MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY)
                            try {
                                preview.measure(wSpec, hSpec)
                                preview.layout(0, 0, w, h)
                                Log.i("ExpoIVSStagePreviewView", "📐 Deferred layout: preview now ${preview.measuredWidth}x${preview.measuredHeight}")
                            } catch (e: Exception) {
                                Log.w("ExpoIVSStagePreviewView", "📐 Deferred layout error: ${e.message}")
                            }
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
        
        // Don't refresh if view is no longer attached
        if (!isViewAttached) {
            Log.w("ExpoIVSStagePreviewView", "🔄 Skipping refresh - view not attached")
            return
        }
        
        // Capture and clear references BEFORE removing view
        val oldPreview = ivsImagePreviewView
        ivsImagePreviewView = null
        currentPreviewDeviceUrn = null
        
        // Now remove the old preview if it exists
        if (oldPreview != null && oldPreview.parent == this) {
            Log.i("ExpoIVSStagePreviewView", "🔄 Removing old preview view")
            try {
                removeView(oldPreview)
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error removing old preview view: ${e.message}")
            }
        }
        
        retryCount = 0
        // Add a delay to allow the new camera stream to initialize
        mainHandler.postDelayed({
            // Double-check we're still attached before trying to attach stream
            if (isViewAttached) {
                Log.i("ExpoIVSStagePreviewView", "🔄 Now attaching new preview after delay")
                attachStreamWithRetry()
            } else {
                Log.w("ExpoIVSStagePreviewView", "🔄 Skipping attach - view no longer attached")
            }
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
        
        // Remove pending callbacks FIRST to prevent any async operations
        mainHandler.removeCallbacksAndMessages(null)
        
        // Unregister from manager BEFORE touching views
        stageManager?.unregisterPreviewView(this)
        
        // Capture reference before clearing
        val preview = ivsImagePreviewView
        
        // Clear references BEFORE removing view to prevent race conditions
        // This ensures no other code can access the preview during removal
        ivsImagePreviewView = null
        currentPreviewDeviceUrn = null
        
        // Remove the preview view synchronously if it exists and is our child
        // We do this AFTER clearing references but BEFORE calling super
        // to ensure the view hierarchy is consistent
        if (preview != null && preview.parent == this) {
            try {
                removeView(preview)
                Log.d("ExpoIVSStagePreviewView", "Preview removed synchronously on detach")
            } catch (e: Exception) {
                Log.w("ExpoIVSStagePreviewView", "Error removing preview on detach: ${e.message}")
            }
        }
        
        super.onDetachedFromWindow()
    }
}
