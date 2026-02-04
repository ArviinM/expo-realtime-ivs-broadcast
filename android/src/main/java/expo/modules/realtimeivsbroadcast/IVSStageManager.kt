package expo.modules.realtimeivsbroadcast

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    // To keep track of available cameras for swapping
    private var availableCameras: List<Device> = emptyList()

    var delegate: IVSStageManagerDelegate? = null

    private var isPublishingActive: Boolean = false

    // State management properties
    val participants = mutableListOf<StageParticipant>()
    private val remoteViews = mutableListOf<WeakReference<ExpoIVSRemoteStreamView>>()
    private val previewViews = mutableListOf<WeakReference<ExpoIVSStagePreviewView>>()
    private var targetParticipantId: String? = null

    companion object {
        @JvmStatic
        var instance: IVSStageManager? = null
            private set
    }

    init {
        instance = this
        Log.i("ExpoIVSStageManager", "✅ IVSStageManager singleton instance created")
    }

    private fun discoverDevices() {
        val deviceDiscovery = DeviceDiscovery(context)
        val devices = deviceDiscovery.listLocalDevices()
        Log.i("ExpoIVSStageManager", "Discovered devices: ${devices.joinToString { it.descriptor.friendlyName }}")

        availableCameras = devices.filter { it.descriptor.type == Device.Descriptor.DeviceType.CAMERA }

        if (localCamera == null) {
            localCamera = availableCameras.firstOrNull { it.descriptor.position == Device.Descriptor.Position.FRONT } ?: availableCameras.firstOrNull()
            Log.i("ExpoIVSStageManager", "Selected camera: ${localCamera?.descriptor?.friendlyName ?: "None"}")
            Log.i("ExpoIVSStageManager", "Selected camera: ${localCamera?.descriptor?.urn ?: "None"}")
        }
        if (localMicrophone == null) {
            localMicrophone = devices.firstOrNull { it.descriptor.type == Device.Descriptor.DeviceType.MICROPHONE }
            Log.i("ExpoIVSStageManager", "Selected microphone: ${localMicrophone?.descriptor?.friendlyName ?: "None"}")
            Log.i("ExpoIVSStageManager", "Selected microphone: ${localMicrophone?.descriptor?.urn ?: "None"}")
        }
    }

    // MARK: - Public API (called by the module)

    fun getLocalCameraDevice(): Device? {
        return localCamera
    }

    fun isFrontCameraActive(): Boolean {
        return localCamera?.descriptor?.position == Device.Descriptor.Position.FRONT
    }

    fun initializeLocalStreams() {
        discoverDevices()

        if (cameraStream == null && localCamera != null) {
            cameraStream = ImageLocalStageStream(localCamera!!, this.stageConfiguration.videoConfiguration)
        }
        if (microphoneStream == null && localMicrophone != null) {
            microphoneStream = AudioLocalStageStream(localMicrophone!!, this.stageConfiguration.audioConfiguration)
        }

        Log.i("ExpoIVSStageManager", "✅ IVSStageManager: Local streams initialized.")
    }

    fun initializeStage(audioConfig: StageAudioConfiguration? = null, videoConfig: StageVideoConfiguration? = null) {
        // Setup audio configuration
        val audioConfiguration = StageAudioConfiguration()
        val finalAudioConfig = audioConfig ?: audioConfiguration
        finalAudioConfig.maxBitrate?.let { (it as? Number)?.toInt()?.let { br -> finalAudioConfig.maxBitrate = br } }

        // Setup video configuration
        val videoConfiguration = StageVideoConfiguration()
        val finalVideoConfig = videoConfig ?: videoConfiguration
        finalVideoConfig.targetFramerate?.let { (it as? Number)?.toInt()?.let { fr -> finalVideoConfig.targetFramerate = fr } }
        finalVideoConfig.maxBitrate?.let { (it as? Number)?.toInt()?.let { br -> finalVideoConfig.maxBitrate = br } }
        finalVideoConfig.minBitrate?.let { (it as? Number)?.toInt()?.let { br -> finalVideoConfig.minBitrate = br } }
        finalVideoConfig.setSize(
            BroadcastConfiguration.Vec2(
                720F, 1280F
            )
        )

        this.stageConfiguration.audioConfiguration = finalAudioConfig
        this.stageConfiguration.videoConfiguration = finalVideoConfig

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
            } catch (e: BroadcastException) {
                Log.e("ExpoIVSStageManager", "❌ Error joining stage: ${e.message}")
                delegate?.stageManagerDidEmitEvent("onStageError", mapOf("description" to "Failed to join stage: ${e.message}"))
            }
        }
    }

    fun leaveStage() {
        setStreamsPublished(false)
        stage?.leave()
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
        
        // First, notify preview views to clear their current preview
        // This releases the old camera's preview before we switch
        previewViews.mapNotNull { it.get() }.forEach { view ->
            mainHandler.post {
                try {
                    // Force clear the preview by calling refreshPreview which removes the old one
                    Log.i("ExpoIVSStageManager", "🔄 Clearing preview before swap")
                } catch (e: Exception) {
                    Log.w("ExpoIVSStageManager", "Error clearing preview: ${e.message}")
                }
            }
        }
        
        // Update the local camera reference
        localCamera = newCamera
        
        // Create new stream with video configuration
        val oldStream = cameraStream
        cameraStream = ImageLocalStageStream(newCamera, this.stageConfiguration.videoConfiguration)
        
        // Refresh the stage strategy to use the new stream
        stage?.refreshStrategy()
        
        Log.i("ExpoIVSStageManager", "✅ Camera swapped to: ${newCamera.descriptor.friendlyName}, URN: ${newCamera.descriptor.urn}")
        
        // Delay the preview refresh to allow the new camera stream to fully initialize
        // The back camera especially needs more time to warm up
        mainHandler.postDelayed({
            Log.i("ExpoIVSStageManager", "🔄 Triggering preview refresh after camera swap")
            notifyPreviewViewsToRefresh()
        }, 500) // 500ms delay for camera to fully initialize
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
            // Still call assignStreamsToAvailableViews in case the view needs a stream
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
    }

    private fun assignStreamsToAvailableViews() {
        // Ensure we're on the main thread for UI operations
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { assignStreamsToAvailableViews() }
            return
        }

        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Assigning streams to views...")
        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Total participants: ${participants.size}")
        
        // Clean up null weak references
        remoteViews.removeAll { it.get() == null }
        
        val renderedUrns = remoteViews.mapNotNull { it.get()?.currentRenderedDeviceUrn }.toSet()
        val availableViews = remoteViews.mapNotNull { it.get() }.filter { it.currentRenderedDeviceUrn == null }

        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Rendered URNs: $renderedUrns")
        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Available views count: ${availableViews.size}")

        val availableStreams = participants.flatMap { p ->
            Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Participant ${p.info.participantId} has ${p.streams.size} streams")
            p.streams
                .filter { 
                    val isVideo = it.streamType == StageStream.Type.VIDEO
                    val notRendered = !renderedUrns.contains(it.device.descriptor.urn)
                    Log.i("ExpoIVSStageManager", "🧠 [MANAGER]   Stream URN: ${it.device.descriptor.urn}, isVideo: $isVideo, notRendered: $notRendered")
                    isVideo && notRendered
                }
                .map { stream -> Pair(p.info.participantId, stream) }
        }

        Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Found ${availableViews.size} available views and ${availableStreams.size} available streams.")

        if (availableViews.isEmpty() && availableStreams.isNotEmpty()) {
            Log.w("ExpoIVSStageManager", "🧠 [MANAGER] ⚠️ Streams available but no views to render them!")
        }
        
        if (availableStreams.isEmpty() && availableViews.isNotEmpty()) {
            Log.w("ExpoIVSStageManager", "🧠 [MANAGER] ⚠️ Views available but no streams to render!")
        }

        availableViews.zip(availableStreams).forEach { (view, streamInfo) ->
            Log.i("ExpoIVSStageManager", "🧠 [MANAGER] Assigning stream ${streamInfo.second.device.descriptor.urn} to a view.")
            view.renderStream(device = streamInfo.second.device)
        }
    }

    // MARK: - Stage.Strategy Implementation
    override fun stageStreamsToPublishForParticipant(stage: Stage, participantInfo: ParticipantInfo): MutableList<LocalStageStream> {
        if (!isPublishingActive) return mutableListOf()

        val streams = mutableListOf<LocalStageStream>()
        cameraStream?.let { streams.add(it) }
        microphoneStream?.let { streams.add(it) }
        return streams
    }

    override fun shouldPublishFromParticipant(stage: Stage, participantInfo: ParticipantInfo): Boolean {
        return isPublishingActive
    }

    override fun shouldSubscribeToParticipant(stage: Stage, participantInfo: ParticipantInfo): Stage.SubscribeType {
        return if (participantInfo.isLocal) Stage.SubscribeType.NONE else Stage.SubscribeType.AUDIO_VIDEO
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
        // Not implemented in a meaningful way in iOS version, but can be added here if needed
    }
    
    override fun onError(exception: BroadcastException) {
        delegate?.stageManagerDidEmitEvent("onStageError", mapOf("description" to exception.localizedMessage))
        Log.e("ExpoIVSStageManager", "❌ Renderer: Received error: ${exception.localizedMessage}")
    }
}
