import { registerWebModule, NativeModule } from 'expo';
class ExpoRealtimeIvsBroadcastModule extends NativeModule {
    // Stub implementations for web (PiP not supported on web)
    async enablePictureInPicture(_options) {
        console.warn('Picture-in-Picture is not supported on web');
        return false;
    }
    async disablePictureInPicture() {
        // No-op on web
    }
    async startPictureInPicture() {
        console.warn('Picture-in-Picture is not supported on web');
    }
    async stopPictureInPicture() {
        // No-op on web
    }
    async isPictureInPictureActive() {
        return false;
    }
    async isPictureInPictureSupported() {
        return false;
    }
}
export default registerWebModule(ExpoRealtimeIvsBroadcastModule, 'ExpoRealtimeIvsBroadcastModule');
//# sourceMappingURL=ExpoRealtimeIvsBroadcastModule.web.js.map