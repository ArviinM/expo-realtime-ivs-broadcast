package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import com.amazonaws.ivs.broadcast.*
import android.util.Log
import androidx.annotation.RequiresApi
import java.lang.ref.WeakReference

// Custom class to hold combined state, mirroring the Swift version
class StageParticipant(val info: ParticipantInfo, var streams: MutableList<StageStream> = mutableListOf())

// Delegate for emitting events back to the module
interface IVSStageManagerDelegate {
    fun stageManagerDidEmitEvent(eventName: String, body: Map<String, Any?>)
}

@RequiresApi(Build.VERSION_CODES.P)
class IVSStageManager(private val context: Context) : Stage.Strategy, StageRenderer {
    // MARK: - Properties
    private var stage: Stage? = null
    private var localCamera: Device? = null
    private var localMicrophone: Device? = null
    private var cameraStream: ImageLocalStageStream? = null
    private var microphoneStream: AudioLocalStageStream? = null
    private var stageConfiguration: StageConfiguration = StageConfiguration()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager: AudioManager by lazy {
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    // To keep track of available cameras for swapping
    private var availableCameras: List<Device> = emptyList()

    var delegate: IVSStageManagerDelegate? = null

    private var isPublishingActive: Boolean = false

    // State management properties
    val participants = mutableListOf<StageParticipant>()
    private val remoteViews = mutableListOf<WeakReference<ExpoIVSRemoteStreamView>>()
    private val previewViews = mutableListOf<WeakReference<ExpoIVSStagePreviewView>>()
    private var targetParticipantId: String? = null

    // Camera mute state — Android now matches iOS feature parity.
    private var isCameraMutedState: Boolean = false
    private var cameraMutePlaceholderText: String = "Host is away"

    // Audio picker / preset state
    private var preferredAudioInputUrn: String? = null
    private var currentAudioPreset: String = "videoChat"
    private var audioDeviceCallback: AudioDeviceCallback? = null

    // Mock mode (DEBUG only)
    private var isMockMode: Boolean = false

    // Observability state
    private var rtcStatsRunnable: Runnable? = null
    private var lastRTCStats: Map<String, Any?> = emptyMap()
    private var bgStopPublishing: Boolean = true
    private var bgSubscribeMode: String = "audioOnly" // 'none' | 'audioOnly' | 'audioVideo'
    private var isAppInBackground: Boolean = false

    // Thermal mitigation state
    private var thermalMitigationEnabled: Boolean = false
    private var thermalReducedFramerate: Int = 15
    private var thermalListenerInstalled: Boolean = false
    private val powerManager: PowerManager? by lazy {
        context.applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
    }

    companion object {
        @JvmStatic
        @Volatile
        var instance: IVSStageManager? = null
            private set
    }

    init {
        synchronized(IVSStageManager::class.java) {
            instance = this
        }
        installAudioDeviceCallback()
        Log.i("ExpoIVSStageManager", "✅ IVSStageManager singleton instance created")
    }

    private fun installAudioDeviceCallback() {
        if (audioDeviceCallback != null) return
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                delegate?.stageManagerDidEmitEvent(
                    "onAudioRouteChanged",
                    mapOf("reason" to "newDeviceAvailable", "activeInput" to activeInputAsMap())
                )
            }
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                delegate?.stageManagerDidEmitEvent(
                    "onAudioRouteChanged",
                    mapOf("reason" to "oldDeviceUnavailable", "activeInput" to activeInputAsMap())
                )
            }
        }
        audioManager.registerAudioDeviceCallback(cb, mainHandler)
        audioDeviceCallback = cb
    }

    private fun discoverDevices() {
        val deviceDiscovery = DeviceDiscovery(context)
        val devices = deviceDiscovery.listLocalDevices()
        Log.i("ExpoIVSStageManager", "Discovered devices: ${devices.joinToString { it.descriptor.friendlyName }}")

        availableCameras = devices.filter { it.descriptor.type == Device.Descriptor.DeviceType.CAMERA }

        if (localCamera == null) {
            localCamera = availableCameras.firstOrNull { it.descriptor.position == Device.Descriptor.Position.FRONT } ?: availableCameras.firstOrNull()
            Log.i("ExpoIVSStageManager", "Selected camera: ${localCamera?.descriptor?.friendlyName ?: "None"}")
        }
        if (localMicrophone == null) {
            localMicrophone = devices.firstOrNull { it.descriptor.type == Device.Descriptor.DeviceType.MICROPHONE }
            Log.i("ExpoIVSStageManager", "Selected microphone: ${localMicrophone?.descriptor?.friendlyName ?: "None"}")
        }
    }

    // MARK: - Public API (called by the module)

    fun getLocalCameraDevice(): Device? {
        return localCamera
    }

    fun isFrontCameraActive(): Boolean {
        return localCamera?.descriptor?.position == Device.Descriptor.Position.FRONT
    }

    /// Map-based entry point called from JS. Currently the SDK doesn't expose
    /// fine-grained audio knobs the same way as iOS, but we keep the signature
    /// symmetric and apply what we can (bitrate).
    fun initializeLocalStreams(audioConfigMap: Map<String, Any>?, videoConfigMap: Map<String, Any>?) {
        applyAudioConfigMap(audioConfigMap)
        applyVideoConfigMap(videoConfigMap)
        initializeLocalStreams()
    }

    fun initializeStage(audioConfigMap: Map<String, Any>?, videoConfigMap: Map<String, Any>?) {
        applyAudioConfigMap(audioConfigMap)
        applyVideoConfigMap(videoConfigMap)
        Log.i("ExpoIVSStageManager", "✅ Stage initialized with custom configurations.")
    }

    private fun applyAudioConfigMap(map: Map<String, Any>?) {
        try {
            val ac = stageConfiguration.audioConfiguration
            (map?.get("maxBitrate") as? Number)?.toInt()?.let { ac.maxBitrate = it }
            // Default bump: 96 kbps if nothing was passed.
            if (map?.get("maxBitrate") == null) {
                ac.maxBitrate = 96_000
            }
            // Note: StageAudioConfiguration doesn't expose a channels setter on
            // the Android SDK (same situation as iOS). The JS-side `channels`
            // field is silently ignored on both platforms.
        } catch (e: Throwable) {
            Log.w("ExpoIVSStageManager", "applyAudioConfigMap failed: ${e.message}")
        }
    }

    private fun applyVideoConfigMap(map: Map<String, Any>?) {
        try {
            val vc = stageConfiguration.videoConfiguration
            val width = (map?.get("width") as? Number)?.toFloat() ?: 720f
            val height = (map?.get("height") as? Number)?.toFloat() ?: 1280f
            // Defaults are tuned for live commerce: 30 fps + 0.5–2.5 Mbps. The Stages
            // SDK defaults to 15 fps which is too choppy for product demos. Set the
            // floor here so callers always get the good defaults unless they override.
            val fps = (map?.get("targetFramerate") as? Number)?.toInt() ?: 30
            val maxB = (map?.get("maxBitrate") as? Number)?.toInt() ?: 2_500_000
            val minB = (map?.get("minBitrate") as? Number)?.toInt() ?: 500_000
            vc.setSize(BroadcastConfiguration.Vec2(width, height))
            vc.targetFramerate = fps
            vc.maxBitrate = maxB
            vc.minBitrate = minB
            Log.i("ExpoIVSStageManager", "🎥 Video configured ${width.toInt()}x${height.toInt()} @ $fps fps, $minB-$maxB bps")
        } catch (e: Throwable) {
            Log.w("ExpoIVSStageManager", "applyVideoConfigMap failed: ${e.message}")
        }
    }

    fun initializeLocalStreams() {
        if (isMockMode) {
            Log.i("ExpoIVSStageManager", "🎭 Mock mode — skipping real device discovery")
            return
        }
        discoverDevices()

        if (cameraStream == null && localCamera != null) {
            cameraStream = ImageLocalStageStream(localCamera!!, this.stageConfiguration.videoConfiguration)
        }
        if (microphoneStream == null && localMicrophone != null) {
            microphoneStream = AudioLocalStageStream(localMicrophone!!, this.stageConfiguration.audioConfiguration)
        }

        // Re-apply preferred input now that the mic exists.
        applyPreferredAudioInputIfPossible()

        Log.i("ExpoIVSStageManager", "✅ IVSStageManager: Local streams initialized.")
    }

    fun initializeStage(audioConfig: StageAudioConfiguration? = null, videoConfig: StageVideoConfiguration? = null) {
        // Legacy entry — kept for back-compat with anything calling the typed overload.
        val ac = audioConfig ?: stageConfiguration.audioConfiguration
        if (ac.maxBitrate == 0) ac.maxBitrate = 96_000
        val vc = videoConfig ?: stageConfiguration.videoConfiguration
        vc.setSize(BroadcastConfiguration.Vec2(720f, 1280f))
        // Match the JS-side defaults: 30 fps + 0.5–2.5 Mbps for live commerce quality.
        if (vc.targetFramerate <= 0 || vc.targetFramerate == 15) vc.targetFramerate = 30
        if (vc.maxBitrate <= 0) vc.maxBitrate = 2_500_000
        if (vc.minBitrate <= 0) vc.minBitrate = 500_000
        stageConfiguration.audioConfiguration = ac
        stageConfiguration.videoConfiguration = vc
        Log.i("ExpoIVSStageManager", "✅ IVSStageManager: Stage Initialized with custom configurations.")
    }

    fun joinStage(token: String, targetId: String?) {
        this.targetParticipantId = targetId

        // The stage must be joined on the main thread.
        Handler(Looper.getMainLooper()).post {
            try {
                stage = Stage(context, token, this)
                stage?.addRenderer(this)
                stage?.join()
                Log.i("ExpoIVSStageManager", "✅ IVSStageManager: Stage join() method called on main thread.")
                startRTCStatsTimer()
            } catch (e: Throwable) {
                // Deliberately Throwable, not BroadcastException. This block runs
                // inside a main-thread Handler.post, so anything the SDK throws that
                // isn't a BroadcastException — an IllegalArgumentException from a
                // malformed or expired JWT, for instance — escapes on the main thread
                // and kills the app outright rather than surfacing an error to JS.
                // Realistic trigger: the seller idles on the pre-live screen past the
                // token TTL, then taps Go Live.
                Log.e("ExpoIVSStageManager", "❌ Error joining stage: ${e.message}")
                delegate?.stageManagerDidEmitEvent(
                    "onStageError",
                    mapOf(
                        "description" to "Failed to join stage: ${e.message}",
                        // Join failure is terminal for this attempt — tell JS so it can
                        // clear its busy flags and offer a retry instead of hanging.
                        "isFatal" to true
                    )
                )
            }
        }
    }

    fun leaveStage() {
        setStreamsPublished(false)
        // Emit onParticipantLeft for every non-local participant BEFORE
        // tearing the stage down. The JS-side useStageParticipants hook
        // accumulates participants via these events; if we don't emit them
        // here, the next stream's session inherits a stale list and
        // attempts to attach the remote stream view to a participant that
        // doesn't exist on the new stage → black screen until they finally
        // emerge in the participant list (or never, if the SDK skipped a
        // late join callback).
        //
        // The SDK's own disconnected event also clears `participants`, but
        // it can fire AFTER the new joinStage() has populated stage B's
        // participants — wiping valid state. Proactively emitting + clearing
        // here closes that race.
        for (p in participants) {
            if (p.info.isLocal) continue
            delegate?.stageManagerDidEmitEvent(
                "onParticipantLeft",
                mapOf("participantId" to p.info.participantId),
            )
        }
        participants.clear()
        stage?.leave()
        stage = null
        stopRTCStatsTimer()
    }

    // MARK: - Observability: stats timer + background behavior

    fun setBackgroundBehavior(options: Map<String, Any>?) {
        (options?.get("stopPublishing") as? Boolean)?.let { bgStopPublishing = it }
        (options?.get("subscribeMode") as? String)?.let { bgSubscribeMode = it }
        Log.i("ExpoIVSStageManager", "📢 [Background] stopPublishing=$bgStopPublishing subscribeMode=$bgSubscribeMode")
    }

    private fun startRTCStatsTimer() {
        if (rtcStatsRunnable != null) return
        val r = object : Runnable {
            override fun run() {
                tickRTCStats()
                mainHandler.postDelayed(this, 2_000)
            }
        }
        rtcStatsRunnable = r
        mainHandler.postDelayed(r, 2_000)
        Log.i("ExpoIVSStageManager", "📊 [Stats] Started 2s RTC stats poller")
    }

    private fun stopRTCStatsTimer() {
        rtcStatsRunnable?.let { mainHandler.removeCallbacks(it) }
        rtcStatsRunnable = null
    }

    private fun tickRTCStats() {
        // Android Stages SDK signature: `fun requestRTCStats(): Unit`. Stats are
        // delivered out-of-band; the current 1.31 SDK doesn't expose a public
        // delivery callback we can wire to here. We still trigger the request
        // so the SDK can update internal metrics, but onRTCStats will not fire
        // on Android until we adopt a newer SDK version that surfaces stats.
        // The mine-app stats HUD degrades to "—" gracefully when no event arrives.
        //
        // Broadcaster path: poll the local camera stream. Viewer path: no local
        // cameraStream — fall back to the first remote video stream so viewers
        // also drive the SDK's internal stats refresh (and benefit immediately
        // once a future SDK exposes the delivery callback).
        val stream: StageStream? = cameraStream ?: firstRemoteVideoStream()
        if (stream == null) return
        try {
            stream.requestRTCStats()
        } catch (t: Throwable) {
            Log.w("ExpoIVSStageManager", "📊 [Stats] requestRTCStats threw: ${t.message}")
        }
    }

    /// Find a remote video stream to use as the stats source when no local
    /// camera exists (viewer/subscriber session). Prefers the explicitly-
    /// targeted participant if set, else any remote with a VIDEO stream.
    private fun firstRemoteVideoStream(): StageStream? {
        val preferred = targetParticipantId
        val ordered = if (preferred != null) {
            participants.sortedByDescending { it.info.participantId == preferred }
        } else {
            participants
        }
        for (p in ordered) {
            if (p.info.isLocal) continue
            val video = p.streams.firstOrNull { it.streamType == StageStream.Type.VIDEO }
            if (video != null) return video
        }
        return null
    }

    private fun normalizeRTCStats(raw: Map<String, Map<String, String>>): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["raw"] = raw
        for ((_, group) in raw) {
            group["bitrate"]?.toDoubleOrNull()?.let { out["outboundBitrate"] = it.toInt() }
            group["rtt"]?.toDoubleOrNull()?.let { out["roundTripTime"] = (it * 1000).toInt() }
            group["packetsLostFraction"]?.toDoubleOrNull()?.let { out["packetLoss"] = it }
            group["jitter"]?.toDoubleOrNull()?.let { out["jitter"] = it }
            group["framesPerSecond"]?.toDoubleOrNull()?.let { out["framesPerSecond"] = it.toInt() }
            group["qualityLimitationReason"]?.takeIf { it.isNotEmpty() }?.let { out["qualityLimitationReason"] = it }
        }
        return out
    }

    fun snapshotRTCStats(): Map<String, Any?> = lastRTCStats

    // MARK: - Thermal Adaptation

    /// Configure thermal mitigation from JS. Installs the thermal listener once.
    fun setThermalMitigation(options: Map<String, Any>?) {
        (options?.get("enabled") as? Boolean)?.let { thermalMitigationEnabled = it }
        (options?.get("reducedFramerate") as? Number)?.toInt()?.let {
            thermalReducedFramerate = it.coerceIn(5, 30)
        }
        installThermalListener()
        Log.i("ExpoIVSStageManager", "🌡️ [Thermal] mitigation=$thermalMitigationEnabled, reducedFps=$thermalReducedFramerate")
        emitThermalState(didMitigate = false)
    }

    /// Returns the current thermal state normalized to the 4-level scale.
    fun currentThermalState(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "nominal"
        val status = powerManager?.currentThermalStatus ?: return "nominal"
        return mapThermalStatus(status)
    }

    private fun mapThermalStatus(status: Int): String {
        return when (status) {
            PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT -> "nominal"
            PowerManager.THERMAL_STATUS_MODERATE -> "fair"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
            else -> "nominal"
        }
    }

    private fun installThermalListener() {
        if (thermalListenerInstalled || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val pm = powerManager ?: return
        try {
            pm.addThermalStatusListener(mainHandler::post, PowerManager.OnThermalStatusChangedListener { status ->
                handleThermalChange(status)
            })
            thermalListenerInstalled = true
            Log.i("ExpoIVSStageManager", "🌡️ [Thermal] Installed PowerManager thermal listener")
        } catch (t: Throwable) {
            Log.w("ExpoIVSStageManager", "🌡️ [Thermal] Failed to install listener: ${t.message}")
        }
    }

    private fun handleThermalChange(status: Int) {
        val state = mapThermalStatus(status)
        var didMitigate = false
        if (thermalMitigationEnabled) {
            didMitigate = when (state) {
                "serious", "critical" -> applyReducedFramerate(thermalReducedFramerate)
                "nominal", "fair" -> applyReducedFramerate(30)
                else -> false
            }
        }
        emitThermalState(didMitigate = didMitigate)
    }

    private fun emitThermalState(didMitigate: Boolean) {
        delegate?.stageManagerDidEmitEvent(
            "onThermalStateChanged",
            mapOf("state" to currentThermalState(), "didMitigate" to didMitigate)
        )
    }

    private fun applyReducedFramerate(fps: Int): Boolean {
        val camera = localCamera ?: return false
        try {
            stageConfiguration.videoConfiguration.targetFramerate = fps
            cameraStream = ImageLocalStageStream(camera, stageConfiguration.videoConfiguration)
            stage?.refreshStrategy()
            Log.i("ExpoIVSStageManager", "🌡️ [Thermal] Rebuilt camera stream at $fps fps")
            return true
        } catch (t: Throwable) {
            Log.w("ExpoIVSStageManager", "🌡️ [Thermal] applyReducedFramerate($fps) failed: ${t.message}")
            return false
        }
    }

    /// Fully releases camera and microphone hardware resources.
    fun destroyLocalStreams() {
        Log.i("ExpoIVSStageManager", "Destroying local streams and releasing hardware.")

        // Release camera stream
        cameraStream?.muted = true
        cameraStream = null

        // Release microphone stream
        microphoneStream?.muted = true
        microphoneStream = null

        // Reset device references so initializeLocalStreams() can re-discover
        localCamera = null
        localMicrophone = null
        availableCameras = emptyList()

        Log.i("ExpoIVSStageManager", "✅ Local streams destroyed. Camera and microphone released.")
    }

    fun setStreamsPublished(published: Boolean) {
        if (stage == null) {
            Log.w("ExpoIVSStageManager", "⚠️ Stage not initialized. Cannot set streams published state.")
            return
        }
        isPublishingActive = published
        stage?.refreshStrategy()
        Log.i("ExpoIVSStageManager", "✅ IVSStageManager: Publishing state set to $published. Refreshing strategy.")
    }

    fun setMicrophoneMuted(muted: Boolean) {
        microphoneStream?.muted = muted
        Log.i("ExpoIVSStageManager", "✅ Microphone muted: $muted")
    }

    /// Camera mute — feature parity with iOS. Mutes the IVS stream so peers see a frozen frame.
    /// Placeholder text is stored but not yet drawn as a custom frame (real placeholder generation
    /// requires switching to ImageInputSource path).
    fun setCameraMuted(muted: Boolean, placeholderText: String?) {
        isCameraMutedState = muted
        placeholderText?.let { cameraMutePlaceholderText = it }
        cameraStream?.muted = muted

        Log.i("ExpoIVSStageManager", "✅ Camera muted: $muted (placeholder: '$cameraMutePlaceholderText')")

        delegate?.stageManagerDidEmitEvent(
            "onCameraMuteStateChanged",
            mapOf("muted" to muted, "placeholderActive" to false)
        )
    }

    fun isCameraMuted(): Boolean = isCameraMutedState

    fun swapCamera() {
        if (cameraStream == null) {
            Log.e("ExpoIVSStageManager", "❌ Cannot swap camera, stream not initialized.")
            return
        }

        val currentDevice = localCamera ?: return
        val newCamera = availableCameras.firstOrNull { it.descriptor.urn != currentDevice.descriptor.urn }

        if (newCamera == null) {
            Log.w("ExpoIVSStageManager", "⚠️ No other camera available to swap to.")
            return
        }

        Log.i("ExpoIVSStageManager", "🔄 Swapping camera from ${currentDevice.descriptor.friendlyName} to ${newCamera.descriptor.friendlyName}")

        // Update the local camera reference
        localCamera = newCamera

        // Create new stream with video configuration
        cameraStream = ImageLocalStageStream(newCamera, this.stageConfiguration.videoConfiguration)

        // Refresh the stage strategy to use the new stream
        stage?.refreshStrategy()

        Log.i("ExpoIVSStageManager", "✅ Camera swapped to: ${newCamera.descriptor.friendlyName}, URN: ${newCamera.descriptor.urn}")

        // Delay the preview refresh to allow the new camera stream to fully initialize
        mainHandler.postDelayed({
            Log.i("ExpoIVSStageManager", "🔄 Triggering preview refresh after camera swap")
            notifyPreviewViewsToRefresh()
        }, 500)

        delegate?.stageManagerDidEmitEvent(
            "onCameraSwapped",
            mapOf("newCameraURN" to newCamera.descriptor.urn, "newCameraName" to newCamera.descriptor.friendlyName)
        )
    }

    /**
     * Rebuild the capture stream on the SAME camera and re-publish it.
     *
     * After the app is backgrounded, Android takes the camera away (there is
     * no foreground service, by design) and the existing ImageLocalStageStream
     * comes back dead: the seller and every viewer see a frozen frame while the
     * UI still says LIVE. Device QA found that swapping cameras revived it —
     * because swapCamera() builds a NEW stream and refreshes the stage
     * strategy. This does exactly that without changing camera, so recovery
     * doesn't flip the seller to the selfie camera and still works on devices
     * with only one camera (QA 2026-08-07 O1.1).
     */
    fun refreshCameraStream() {
        val device = localCamera
        if (device == null || cameraStream == null) {
            Log.w("ExpoIVSStageManager", "⚠️ refreshCameraStream: no camera stream to refresh")
            return
        }

        Log.i("ExpoIVSStageManager", "🔄 Rebuilding camera stream on ${device.descriptor.friendlyName}")
        cameraStream = ImageLocalStageStream(device, this.stageConfiguration.videoConfiguration)
        stage?.refreshStrategy()

        mainHandler.postDelayed({ notifyPreviewViewsToRefresh() }, 500)
    }

    private fun notifyPreviewViewsToRefresh() {
        // Clean up null weak references
        previewViews.removeAll { it.get() == null }

        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Notifying ${previewViews.count { it.get() != null }} preview views to refresh")

        mainHandler.post {
            previewViews.mapNotNull { it.get() }.forEach { view ->
                view.refreshPreview()
            }
        }
    }

    // MARK: - Audio Preset / Device Picker / Gain

    /// Map a JS string preset onto Android's AudioManager mode.
    /// - 'subscribeOnly' / 'studio' → MODE_NORMAL (loud media-volume path, no AEC)
    /// - 'videoChat' → MODE_IN_COMMUNICATION (echo cancellation + lower gain)
    fun setAudioPreset(preset: String) {
        currentAudioPreset = preset
        val newMode = when (preset) {
            "subscribeOnly", "studio" -> AudioManager.MODE_NORMAL
            "videoChat" -> AudioManager.MODE_IN_COMMUNICATION
            else -> {
                Log.w("ExpoIVSStageManager", "⚠️ Unknown audio preset '$preset' — using videoChat default")
                AudioManager.MODE_IN_COMMUNICATION
            }
        }
        try {
            audioManager.mode = newMode
            Log.i("ExpoIVSStageManager", "📢 [Audio] setAudioPreset → $preset (mode=$newMode)")
        } catch (e: Throwable) {
            Log.w("ExpoIVSStageManager", "📢 [Audio] setAudioPreset failed: ${e.message}")
        }
    }

    /// Enumerate input audio devices. Stable across reboots; identifier is the
    /// device's product name + addr concatenated (Android doesn't have a single
    /// UID like iOS, so we synthesize one).
    fun listAudioInputs(): List<Map<String, Any>> {
        val inputs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).toList()
        } else emptyList()

        val activeUrn = activeInputUrn()
        return inputs.map { dev ->
            val urn = audioDeviceUrn(dev)
            mapOf(
                "urn" to urn,
                "name" to (dev.productName?.toString() ?: "Audio Input"),
                "type" to classifyAudioDeviceType(dev.type),
                "isActive" to (urn == activeUrn)
            )
        }
    }

    fun setPreferredAudioInput(urn: String?) {
        preferredAudioInputUrn = urn
        applyPreferredAudioInputIfPossible()
    }

    private fun applyPreferredAudioInputIfPossible() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            Log.w("ExpoIVSStageManager", "📢 [Audio] setPreferredAudioInput requires API 31+ — ignored")
            return
        }
        try {
            if (preferredAudioInputUrn == null) {
                audioManager.clearCommunicationDevice()
                Log.i("ExpoIVSStageManager", "📢 [Audio] Cleared communication device → system default")
                return
            }
            val target = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                .firstOrNull { audioDeviceUrn(it) == preferredAudioInputUrn }
            if (target == null) {
                Log.w("ExpoIVSStageManager", "📢 [Audio] Preferred input '$preferredAudioInputUrn' not found")
                return
            }
            val ok = audioManager.setCommunicationDevice(target)
            Log.i("ExpoIVSStageManager", "📢 [Audio] setCommunicationDevice(${target.productName}) → $ok")
            delegate?.stageManagerDidEmitEvent(
                "onAudioRouteChanged",
                mapOf("reason" to "userSelected", "activeInput" to activeInputAsMap())
            )
        } catch (e: Throwable) {
            Log.w("ExpoIVSStageManager", "📢 [Audio] applyPreferredAudioInputIfPossible failed: ${e.message}")
        }
    }

    /// Android doesn't expose per-input gain like iOS. We honor the call by toggling
    /// `audioManager.mode` more aggressively, but always return false to signal
    /// "no real gain knob available" — callers should fall back to `setAudioPreset('studio')`.
    fun setInputGain(gain: Float): Boolean {
        Log.i("ExpoIVSStageManager", "📢 [Audio] setInputGain($gain) — not supported on Android, returning false")
        return false
    }

    private fun audioDeviceUrn(dev: AudioDeviceInfo): String {
        // Build a stable identifier. id() is process-local on older APIs but stable per session.
        return "android:input:${dev.id}"
    }

    private fun activeInputUrn(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val active = audioManager.communicationDevice ?: return null
        return audioDeviceUrn(active)
    }

    private fun activeInputAsMap(): Map<String, Any>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val active = audioManager.communicationDevice ?: return null
        return mapOf(
            "urn" to audioDeviceUrn(active),
            "name" to (active.productName?.toString() ?: "Audio Input"),
            "type" to classifyAudioDeviceType(active.type),
            "isActive" to true
        )
    }

    private fun classifyAudioDeviceType(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtin"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
            else -> "unknown"
        }
    }

    // MARK: - Mock Mode (DEBUG-only no-op fallback for release)

    fun setMockMode(enabled: Boolean) {
        if (BuildConfig.DEBUG) {
            isMockMode = enabled
            Log.i("ExpoIVSStageManager", "🎭 [Mock] mock mode = $enabled")
        } else {
            Log.i("ExpoIVSStageManager", "🎭 [Mock] setMockMode is a no-op in release builds")
        }
    }

    // MARK: - Preview View Management

    fun registerPreviewView(view: ExpoIVSStagePreviewView) {
        // Clean up any null references first
        previewViews.removeAll { it.get() == null }

        // Check if this view is already registered
        if (previewViews.any { it.get() === view }) {
            Log.w("ExpoIVSStageManager", "🧠 [MANAGER] Preview view already registered, skipping...")
            return
        }

        previewViews.add(WeakReference(view))
        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] A preview view has registered. Total preview views: ${previewViews.count { it.get() != null }}")
    }

    fun unregisterPreviewView(view: ExpoIVSStagePreviewView) {
        previewViews.removeAll { it.get() == view }
        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] A preview view has unregistered. Total preview views: ${previewViews.count { it.get() != null }}")
    }

    // MARK: - View Management

    fun registerRemoteView(view: ExpoIVSRemoteStreamView) {
        // Clean up any null references first
        remoteViews.removeAll { it.get() == null }

        // Check if this view is already registered
        val existingView = remoteViews.find { it.get() === view }
        if (existingView != null) {
            Log.i("ExpoIVSStageManager", "🧠 [MANAGER] View already registered, triggering stream assignment anyway...")
            assignStreamsToAvailableViews()
            return
        }

        remoteViews.add(WeakReference(view))
        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] A remote view has registered. Total views: ${remoteViews.count { it.get() != null }}")
        assignStreamsToAvailableViews()
    }

    fun unregisterRemoteView(view: ExpoIVSRemoteStreamView) {
        remoteViews.removeAll { it.get() == view }
        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] A remote view has unregistered. Total views: ${remoteViews.count { it.get() != null }}")

        // Trigger reassignment after a short delay to handle view recreation during navigation
        mainHandler.postDelayed({
            Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Delayed reassignment after view unregistered")
            assignStreamsToAvailableViews()
        }, 50)
    }

    private fun assignStreamsToAvailableViews() {
        // Ensure we're on the main thread for UI operations
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { assignStreamsToAvailableViews() }
            return
        }

        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Assigning streams to views...")

        // Clean up null weak references
        remoteViews.removeAll { it.get() == null }

        val renderedUrns = remoteViews.mapNotNull { it.get()?.currentRenderedDeviceUrn }.toSet()
        val availableViews = remoteViews.mapNotNull { it.get() }.filter { it.currentRenderedDeviceUrn == null }

        val availableStreams = participants.flatMap { p ->
            p.streams
                .filter {
                    val isVideo = it.streamType == StageStream.Type.VIDEO
                    val notRendered = !renderedUrns.contains(it.device.descriptor.urn)
                    isVideo && notRendered
                }
                .map { stream -> Pair(p.info.participantId, stream) }
        }

        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Found ${availableViews.size} available views and ${availableStreams.size} available streams.")

        availableViews.zip(availableStreams).forEach { (view, streamInfo) ->
            Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Assigning stream ${streamInfo.second.device.descriptor.urn} to a view.")
            view.renderStream(device = streamInfo.second.device)
        }
    }

    // MARK: - Stage.Strategy Implementation
    override fun stageStreamsToPublishForParticipant(stage: Stage, participantInfo: ParticipantInfo): MutableList<LocalStageStream> {
        // Background override: if app is in background and stopPublishing was opted-in, return no streams.
        if (isAppInBackground && bgStopPublishing) return mutableListOf()
        if (!isPublishingActive) return mutableListOf()

        val streams = mutableListOf<LocalStageStream>()
        cameraStream?.let { streams.add(it) }
        microphoneStream?.let { streams.add(it) }
        return streams
    }

    override fun shouldPublishFromParticipant(stage: Stage, participantInfo: ParticipantInfo): Boolean {
        if (isAppInBackground && bgStopPublishing) return false
        return isPublishingActive
    }

    override fun shouldSubscribeToParticipant(stage: Stage, participantInfo: ParticipantInfo): Stage.SubscribeType {
        if (participantInfo.isLocal) return Stage.SubscribeType.NONE
        // Honor background subscribe mode if app is in background.
        if (isAppInBackground) {
            return when (bgSubscribeMode) {
                "none" -> Stage.SubscribeType.NONE
                "audioOnly" -> Stage.SubscribeType.AUDIO_ONLY
                else -> Stage.SubscribeType.AUDIO_VIDEO
            }
        }
        return Stage.SubscribeType.AUDIO_VIDEO
    }

    // MARK: - Stage.Renderer Implementation
    override fun onConnectionStateChanged(stage: Stage, state: Stage.ConnectionState, exception: BroadcastException?) {
        val stateStr = state.name.lowercase()
        val body = mutableMapOf<String, Any?>("state" to stateStr)
        exception?.let {
            body["error"] = it.localizedMessage
        }
        delegate?.stageManagerDidEmitEvent("onStageConnectionStateChanged", body)
        Log.i("ExpoIVSStageManager", "✅ Renderer: Connection state changed to $stateStr")

        if (state == Stage.ConnectionState.DISCONNECTED) {
            this.isPublishingActive = false
            this.stage = null
            this.participants.clear()
        }
    }

    override fun onParticipantJoined(stage: Stage, participantInfo: ParticipantInfo) {
        if (participantInfo.isLocal) return
        participants.add(StageParticipant(info = participantInfo))
        delegate?.stageManagerDidEmitEvent("onParticipantJoined", mapOf("participantId" to participantInfo.participantId))
        Log.i("ExpoIVSStageManager", "✅ Renderer: Participant joined: ${participantInfo.participantId}")
    }

    override fun onParticipantLeft(stage: Stage, participantInfo: ParticipantInfo) {
        if (participantInfo.isLocal) return

        val leavingParticipant = participants.firstOrNull { it.info.participantId == participantInfo.participantId }
        if (leavingParticipant != null) {
            val removedUrns = leavingParticipant.streams.map { it.device.descriptor.urn }
            remoteViews.mapNotNull { it.get() }.forEach { view ->
                if (removedUrns.contains(view.currentRenderedDeviceUrn)) {
                    view.clearStream()
                    Log.i("ExpoIVSStageManager", "🧠 [MANAGER] A participant left. Commanding their view to clear.")
                }
            }
        }

        participants.removeAll { it.info.participantId == participantInfo.participantId }
        delegate?.stageManagerDidEmitEvent("onParticipantLeft", mapOf("participantId" to participantInfo.participantId))
        Log.i("ExpoIVSStageManager", "✅ Renderer: Participant left: ${participantInfo.participantId}")
    }

    override fun onStreamsAdded(stage: Stage, participantInfo: ParticipantInfo, streams: MutableList<StageStream>) {
        if (participantInfo.isLocal) return

        val participant = participants.firstOrNull { it.info.participantId == participantInfo.participantId }
        participant?.streams?.addAll(streams)

        val streamDicts = streams.map { stream ->
            val mediaType = when (stream.streamType) {
                StageStream.Type.AUDIO -> "audio"
                StageStream.Type.VIDEO -> "video"
                else -> "unknown"
            }
            mapOf("deviceUrn" to stream.device.descriptor.urn, "mediaType" to mediaType)
        }
        delegate?.stageManagerDidEmitEvent("onParticipantStreamsAdded", mapOf("participantId" to participantInfo.participantId, "streams" to streamDicts))

        if (streams.any { it.streamType == StageStream.Type.VIDEO }) {
            assignStreamsToAvailableViews()
        }
        Log.i("ExpoIVSStageManager", "✅ Renderer: ${streams.size} streams added for ${participantInfo.participantId}")
    }

    override fun onStreamsRemoved(stage: Stage, participantInfo: ParticipantInfo, streams: MutableList<StageStream>) {
        if (participantInfo.isLocal) return

        val removedUrns = streams.map { it.device.descriptor.urn }
        remoteViews.mapNotNull { it.get() }.forEach { view ->
            if (removedUrns.contains(view.currentRenderedDeviceUrn)) {
                view.clearStream()
                Log.i("ExpoIVSStageManager", "🧠 [MANAGER] A stream being rendered was removed. Commanding view to clear.")
            }
        }

        val participant = participants.firstOrNull { it.info.participantId == participantInfo.participantId }
        participant?.streams?.removeAll { removedUrns.contains(it.device.descriptor.urn) }

        val streamDicts = streams.map { mapOf("deviceUrn" to it.device.descriptor.urn) }
        delegate?.stageManagerDidEmitEvent("onParticipantStreamsRemoved", mapOf("participantId" to participantInfo.participantId, "streams" to streamDicts))
        Log.i("ExpoIVSStageManager", "✅ Renderer: ${streams.size} streams removed for ${participantInfo.participantId}")
    }

    override fun onParticipantPublishStateChanged(stage: Stage, participantInfo: ParticipantInfo, state: Stage.PublishState) {
        if (!participantInfo.isLocal) return
        val stateStr = state.name.lowercase()
        delegate?.stageManagerDidEmitEvent("onPublishStateChanged", mapOf("state" to stateStr))
        Log.i("ExpoIVSStageManager", "✅ Renderer: Local participant publish state changed to $stateStr")
    }

    override fun onStreamsMutedChanged(stage: Stage, participantInfo: ParticipantInfo, streams: MutableList<StageStream>) {
        if (participantInfo.isLocal) return
        // Forward per-stream mute state so JS can update remote-tile icons.
        val streamDicts = streams.map { s ->
            val mediaType = when (s.streamType) {
                StageStream.Type.AUDIO -> "audio"
                StageStream.Type.VIDEO -> "video"
                else -> "unknown"
            }
            mapOf(
                "deviceUrn" to s.device.descriptor.urn,
                "mediaType" to mediaType,
                "muted" to s.muted
            )
        }
        delegate?.stageManagerDidEmitEvent(
            "onRemoteMuteStateChanged",
            mapOf("participantId" to participantInfo.participantId, "streams" to streamDicts)
        )
    }

    override fun onParticipantSubscribeStateChanged(stage: Stage, participantInfo: ParticipantInfo, state: Stage.SubscribeState) {
        if (participantInfo.isLocal) return
        delegate?.stageManagerDidEmitEvent(
            "onSubscribeStateChanged",
            mapOf("participantId" to participantInfo.participantId, "state" to state.name.lowercase())
        )
    }

    override fun onError(exception: BroadcastException) {
        delegate?.stageManagerDidEmitEvent("onStageError", mapOf("description" to exception.localizedMessage))
        Log.e("ExpoIVSStageManager", "❌ Renderer: Received error: ${exception.localizedMessage}")
    }
}
