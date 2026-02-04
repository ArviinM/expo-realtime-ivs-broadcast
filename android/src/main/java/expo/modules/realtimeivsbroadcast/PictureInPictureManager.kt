package expo.modules.realtimeivsbroadcast

import android.app.Activity
import android.app.Application
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import android.view.View
import androidx.annotation.RequiresApi

/**
 * Options for configuring PiP behavior
 */
data class PiPOptions(
    var autoEnterOnBackground: Boolean = true,
    var sourceView: PiPSourceView = PiPSourceView.REMOTE,
    var preferredAspectRatio: Rational = Rational(9, 16)
) {
    enum class PiPSourceView {
        LOCAL,
        REMOTE
    }
}

/**
 * Delegate for PiP state changes
 */
interface PictureInPictureDelegate {
    fun onPiPStateChanged(state: String)
    fun onPiPError(error: String)
}

/**
 * Listener for views that need to know about PiP state
 */
interface PiPStateListener {
    fun onEnterPiP()
    fun onExitPiP()
}

/**
 * Manager for Picture-in-Picture functionality on Android
 * 
 * Note: Android PiP is Activity-level, meaning the entire Activity enters PiP mode,
 * not just a specific view. The consuming app must configure their Activity with:
 * - android:supportsPictureInPicture="true"
 * - android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"
 */
@RequiresApi(Build.VERSION_CODES.O)
class PictureInPictureManager private constructor() : Application.ActivityLifecycleCallbacks {
    
    companion object {
        private const val TAG = "PiPManager"
        
        @Volatile
        private var instance: PictureInPictureManager? = null
        
        fun getInstance(): PictureInPictureManager {
            return instance ?: synchronized(this) {
                instance ?: PictureInPictureManager().also { instance = it }
            }
        }
    }
    
    // Configuration
    private var options: PiPOptions = PiPOptions()
    
    // State
    private var isEnabled: Boolean = false
    private var isActive: Boolean = false
    private var currentActivity: Activity? = null
    private var isRegisteredForLifecycle: Boolean = false
    
    // Source view for PiP (used for source rect hint)
    private var sourceView: View? = null
    
    // State listeners (views that need to know about PiP)
    private val stateListeners = mutableListOf<PiPStateListener>()
    
    // Delegate
    var delegate: PictureInPictureDelegate? = null
    
    // Handler for main thread operations
    private val mainHandler = Handler(Looper.getMainLooper())
    
    /**
     * Enable PiP with the given options
     * @param activity The current activity (needed for PiP support)
     * @param options Configuration options for PiP
     * @return true if PiP was enabled successfully
     */
    fun enable(activity: Activity, options: PiPOptions): Boolean {
        // Check if PiP is supported
        if (!isPiPSupported(activity)) {
            Log.e(TAG, "PiP is not supported on this device or Activity")
            delegate?.onPiPError("PiP not supported on this device")
            return false
        }
        
        this.options = options
        this.currentActivity = activity
        this.isEnabled = true
        
        // Register for activity lifecycle callbacks for auto-enter
        if (!isRegisteredForLifecycle && options.autoEnterOnBackground) {
            activity.application.registerActivityLifecycleCallbacks(this)
            isRegisteredForLifecycle = true
        }
        
        Log.i(TAG, "PiP enabled with options: autoEnter=${options.autoEnterOnBackground}, source=${options.sourceView}")
        return true
    }
    
    /**
     * Disable PiP
     */
    fun disable() {
        if (isActive) {
            stop()
        }
        
        currentActivity?.application?.let {
            if (isRegisteredForLifecycle) {
                it.unregisterActivityLifecycleCallbacks(this)
                isRegisteredForLifecycle = false
            }
        }
        
        isEnabled = false
        currentActivity = null
        
        Log.i(TAG, "PiP disabled")
    }
    
    /**
     * Start PiP mode manually
     */
    fun start() {
        if (!isEnabled) {
            Log.e(TAG, "Cannot start PiP - not enabled")
            delegate?.onPiPError("PiP is not enabled")
            return
        }
        
        val activity = currentActivity
        if (activity == null) {
            Log.e(TAG, "Cannot start PiP - no activity reference")
            delegate?.onPiPError("No activity available")
            return
        }
        
        if (!isPiPSupported(activity)) {
            Log.e(TAG, "Cannot start PiP - not supported")
            delegate?.onPiPError("PiP not supported on this device")
            return
        }
        
        try {
            val params = buildPiPParams()
            activity.enterPictureInPictureMode(params)
            Log.i(TAG, "PiP start requested")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enter PiP mode: ${e.message}")
            delegate?.onPiPError("Failed to enter PiP: ${e.message}")
        }
    }
    
    /**
     * Stop PiP mode manually
     * Note: On Android, PiP is stopped by the system when the user taps to expand
     * or by moving the app back to foreground. We can't programmatically exit PiP.
     */
    fun stop() {
        // On Android, we can't programmatically exit PiP
        // The user must tap the PiP window to expand it
        // or the app will exit PiP when brought back to foreground
        Log.i(TAG, "Stop requested - user must tap PiP window to exit")
    }
    
    /**
     * Check if PiP is currently active
     */
    fun isActive(): Boolean {
        return currentActivity?.isInPictureInPictureMode == true
    }
    
    /**
     * Check if PiP is supported on this device
     */
    fun isPiPSupported(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        
        // Check if the activity has declared PiP support
        val hasFeature = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        
        // Also check activity info for supportsPictureInPicture
        try {
            val activityInfo = activity.packageManager.getActivityInfo(
                activity.componentName,
                PackageManager.GET_META_DATA
            )
            // Note: We can't directly check supportsPictureInPicture flag, 
            // but if PiP fails, the error will be caught
        } catch (e: Exception) {
            Log.w(TAG, "Could not get activity info: ${e.message}")
        }
        
        return hasFeature
    }
    
    /**
     * Update the current activity reference
     * Call this when the activity changes
     */
    fun setCurrentActivity(activity: Activity?) {
        this.currentActivity = activity
    }
    
    /**
     * Set the source view for PiP
     * This view's bounds will be used as the source rect hint for smooth PiP transitions
     */
    fun setSourceView(view: View?) {
        this.sourceView = view
        Log.i(TAG, "Source view set: ${view?.javaClass?.simpleName ?: "null"}")
        // Update PiP params if already enabled
        if (isEnabled) {
            updatePiPParams()
        }
    }
    
    /**
     * Get the source rect for the current source view
     */
    private fun getSourceRect(): Rect? {
        val view = sourceView ?: return null
        
        // Get view location on screen
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        
        return Rect(
            location[0],
            location[1],
            location[0] + view.width,
            location[1] + view.height
        )
    }
    
    /**
     * Add a PiP state listener
     */
    fun addStateListener(listener: PiPStateListener) {
        if (!stateListeners.contains(listener)) {
            stateListeners.add(listener)
        }
    }
    
    /**
     * Remove a PiP state listener
     */
    fun removeStateListener(listener: PiPStateListener) {
        stateListeners.remove(listener)
    }
    
    /**
     * Notify all listeners about entering PiP
     */
    private fun notifyEnterPiP() {
        mainHandler.post {
            stateListeners.forEach { it.onEnterPiP() }
        }
    }
    
    /**
     * Notify all listeners about exiting PiP
     */
    private fun notifyExitPiP() {
        mainHandler.post {
            stateListeners.forEach { it.onExitPiP() }
        }
    }
    
    /**
     * Handle PiP mode changes
     * The activity should call this in onPictureInPictureModeChanged
     */
    fun onPictureInPictureModeChanged(isInPiPMode: Boolean, newConfig: Configuration?) {
        val wasActive = isActive
        isActive = isInPiPMode
        
        if (isInPiPMode && !wasActive) {
            Log.i(TAG, "Entered PiP mode")
            notifyEnterPiP()
            delegate?.onPiPStateChanged("started")
            
            // Ensure the source view stays visible in PiP
            sourceView?.let { view ->
                view.visibility = View.VISIBLE
                view.keepScreenOn = true
                Log.d(TAG, "Set source view to VISIBLE and keepScreenOn")
            }
        } else if (!isInPiPMode && wasActive) {
            Log.i(TAG, "Exited PiP mode")
            notifyExitPiP()
            delegate?.onPiPStateChanged("stopped")
            
            // Reset keepScreenOn when exiting PiP
            sourceView?.keepScreenOn = false
        }
    }
    
    /**
     * Handle user leaving hint (pressing home button)
     * The activity should call this in onUserLeaveHint
     */
    fun onUserLeaveHint() {
        if (isEnabled && options.autoEnterOnBackground && !isActive) {
            Log.i(TAG, "Auto-entering PiP (user leaving hint)")
            start()
        }
    }
    
    // MARK: - Private Helpers
    
    private fun buildPiPParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(options.preferredAspectRatio)
        
        // Set source rect hint for smooth transition animation
        getSourceRect()?.let { rect ->
            builder.setSourceRectHint(rect)
            Log.d(TAG, "Set source rect hint: $rect")
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(options.autoEnterOnBackground)
            builder.setSeamlessResizeEnabled(true)
        }
        
        return builder.build()
    }
    
    /**
     * Update PiP params (e.g., when aspect ratio changes)
     */
    fun updatePiPParams() {
        if (!isEnabled) return
        
        currentActivity?.let { activity ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    activity.setPictureInPictureParams(buildPiPParams())
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to update PiP params: ${e.message}")
                }
            }
        }
    }
    
    /**
     * Set the preferred aspect ratio for PiP
     */
    fun setAspectRatio(width: Int, height: Int) {
        options.preferredAspectRatio = Rational(width, height)
        updatePiPParams()
    }
    
    // MARK: - Application.ActivityLifecycleCallbacks
    
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    
    override fun onActivityStarted(activity: Activity) {
        if (activity == currentActivity) {
            // Check PiP mode when activity starts
            checkPiPModeChange(activity)
        }
    }
    
    override fun onActivityResumed(activity: Activity) {
        if (activity == currentActivity) {
            // Check if we exited PiP mode
            val isInPiP = activity.isInPictureInPictureMode
            if (!isInPiP && isActive) {
                // User returned from PiP to full screen
                Log.i(TAG, "User returned from PiP (restored)")
                onPictureInPictureModeChanged(false, null)
                delegate?.onPiPStateChanged("restored")
            }
        }
    }
    
    override fun onActivityPaused(activity: Activity) {
        if (activity == currentActivity) {
            // Check if we entered PiP mode
            mainHandler.postDelayed({
                checkPiPModeChange(activity)
            }, 100) // Small delay to allow system to update PiP state
        }
    }
    
    override fun onActivityStopped(activity: Activity) {}
    
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    
    override fun onActivityDestroyed(activity: Activity) {
        if (activity == currentActivity) {
            currentActivity = null
        }
    }
    
    /**
     * Check if PiP mode changed and trigger appropriate callbacks
     */
    private fun checkPiPModeChange(activity: Activity) {
        val isInPiP = activity.isInPictureInPictureMode
        if (isInPiP != isActive) {
            Log.d(TAG, "PiP mode changed: wasActive=$isActive, isNowInPiP=$isInPiP")
            onPictureInPictureModeChanged(isInPiP, null)
        }
    }
}
