package io.flutter.plugins.camerax;

import android.hardware.camera2.CaptureRequest;
import android.util.Range;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.camera.camera2.interop.Camera2Interop;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.video.VideoCapture;
import androidx.camera.video.VideoOutput;

/**
 * SiteSnap patch of camera_android_camerax 0.7.1+2's VideoCapture proxy.
 *
 * <p>The upstream implementation is preserved, with one addition: each newly
 * created VideoCapture is registered with SiteSnapRealtimeOverlayController so
 * the user-selected front-camera mirror mode is applied by CameraX at capture
 * time instead of by a later FFmpeg hflip.</p>
 */
class VideoCaptureProxyApi extends PigeonApiVideoCapture {
  VideoCaptureProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @SuppressWarnings("unchecked")
  @OptIn(markerClass = ExperimentalCamera2Interop.class)
  @NonNull
  @Override
  public VideoCapture<?> withOutput(
      @NonNull VideoOutput videoOutput, @Nullable Range<?> targetFpsRange) {
    VideoCapture.Builder<VideoOutput> builder = new VideoCapture.Builder<>(videoOutput);
    builder.setMirrorMode(SiteSnapRealtimeOverlayController.requestedVideoMirrorMode());

    if (targetFpsRange != null) {
      Camera2Interop.Extender<VideoCapture<VideoOutput>> extender =
          new Camera2Interop.Extender<>(builder);
      extender.setCaptureRequestOption(
          CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, (Range<Integer>) targetFpsRange);
    }

    VideoCapture<VideoOutput> videoCapture = builder.build();
    SiteSnapRealtimeOverlayController.registerVideoCapture(videoCapture);
    return videoCapture;
  }

  @NonNull
  @Override
  public VideoOutput getOutput(VideoCapture<?> pigeonInstance) {
    return pigeonInstance.getOutput();
  }

  @Override
  public void setTargetRotation(VideoCapture<?> pigeonInstance, long rotation) {
    pigeonInstance.setTargetRotation((int) rotation);
  }
}
