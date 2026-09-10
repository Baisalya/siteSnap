package io.flutter.plugins.camerax;

import android.graphics.Rect;
import android.os.SystemClock;
import android.util.Log;
import android.util.Size;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.CameraEffect;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ResolutionInfo;
import androidx.camera.core.UseCase;
import androidx.camera.core.UseCaseGroup;
import androidx.camera.core.MirrorMode;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.VideoCapture;
import androidx.core.util.Consumer;
import androidx.lifecycle.LifecycleOwner;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Process-local bridge between SiteSnap's Flutter overlay raster and CameraX.
 *
 * <p>The overlay raster is authored by Flutter. CameraX routes VideoCapture
 * through a recording-only OpenGL SurfaceProcessor that preserves CameraX's
 * native camera transform and blends the raster before encoding. Flutter
 * CustomPaint remains the live preview source of truth. No second camera is
 * opened and PHOTO/ImageCapture are never targeted.</p>
 */
public final class SiteSnapRealtimeOverlayController {
  private static final Object LOCK = new Object();
  private static final Map<Integer, SiteSnapDynamicVideoEffect> EFFECTS = new HashMap<>();

  private static volatile boolean armed;
  private static volatile boolean enabled;
  private static volatile boolean handshakePending;
  private static volatile byte[] latestOverlayPng;
  private static volatile int overlayBitmapWidth;
  private static volatile int overlayBitmapHeight;
  private static volatile long renderedFramesSinceEnable;
  private static volatile long overlayGeneration;
  private static volatile long uploadedOverlayGeneration;
  private static volatile long renderedOverlayGeneration;
  private static volatile long lastFrameUptimeMs;
  private static volatile long lastRenderedUptimeMs;
  private static volatile long lastOverlaySetUptimeMs;
  private static volatile boolean errorSinceEnable;
  private static volatile FrameGeometry lastFrameGeometry;
  private static volatile String lastError;
  private static volatile boolean frontVideoMirrorEnabled;
  // Recording-only rotation. This value is applied only to VideoCapture and
  // never to Preview/ImageCapture, preserving the photo pipeline exactly.
  private static volatile int requestedVideoTargetRotation = Surface.ROTATION_0;
  private static volatile String requestedCaptureOrientation = "portraitUp";
  private static volatile String latestOverlayLayoutOrientation = "portraitUp";
  private static volatile String uploadedOverlayLayoutOrientation = "portraitUp";
  private static WeakReference<VideoCapture<?>> activeVideoCapture =
      new WeakReference<>(null);
  private static WeakReference<ProcessCameraProvider> activeCameraProvider =
      new WeakReference<>(null);
  private static WeakReference<LifecycleOwner> activeLifecycleOwner =
      new WeakReference<>(null);
  private static WeakReference<CameraSelector> activeCameraSelector =
      new WeakReference<>(null);
  private static List<UseCase> lastBoundUseCases = new ArrayList<>();

  private SiteSnapRealtimeOverlayController() {}

  /** Enables effect injection on the next CameraX bind/rebind. */
  public static void arm() {
    armed = true;
  }

  public static void disarm() {
    armed = false;
    enabled = false;
    handshakePending = false;
  }

  /**
   * Starts a recording handshake and pre-binds VideoCapture before Recorder.start().
   *
   * <p>Pre-binding makes CameraX ResolutionInfo available while no MP4 is being
   * written yet. Flutter can therefore prepare and enable the first WYSIWYG
   * raster before the recorder starts, eliminating the Phase 7 geometry race
   * without allowing clean/raw opening frames into the saved recording.</p>
   */
  public static boolean beginHandshake(@Nullable String captureOrientation) {
    if (!armed) return false;
    requestedCaptureOrientation = normalizeCaptureOrientation(captureOrientation);
    latestOverlayLayoutOrientation = "portraitUp";
    uploadedOverlayLayoutOrientation = "portraitUp";
    requestedVideoTargetRotation =
        surfaceRotationForCaptureOrientation(requestedCaptureOrientation);
    enabled = false;
    handshakePending = true;
    renderedFramesSinceEnable = 0;
    renderedOverlayGeneration = 0;
    lastFrameGeometry = null;
    lastFrameUptimeMs = 0;
    lastRenderedUptimeMs = 0;
    errorSinceEnable = false;
    lastError = null;
    clearOverlay();
    // clearOverlay intentionally only disables/recycles the bitmap; restore the
    // handshake flag after it so the first effect frame remains gated.
    handshakePending = true;
    final boolean prebound = prebindVideoCaptureForHandshake();
    if (!prebound) {
      handshakePending = false;
      lastError = "CameraX VideoCapture prebind was unavailable";
      Log.w("SiteSnapOverlay", lastError);
      return false;
    }
    Log.i(
        "SiteSnapOverlay",
        "Handshake prebound VideoCapture; captureOrientation="
            + requestedCaptureOrientation
            + " targetRotation="
            + requestedVideoTargetRotation
            + "; waiting for geometry");
    return true;
  }

  @NonNull
  private static String normalizeCaptureOrientation(@Nullable String orientation) {
    if ("landscapeLeft".equals(orientation)
        || "landscapeRight".equals(orientation)
        || "portraitDown".equals(orientation)) {
      return orientation;
    }
    return "portraitUp";
  }

  private static int surfaceRotationForCaptureOrientation(@NonNull String orientation) {
    switch (orientation) {
      case "landscapeLeft":
        return Surface.ROTATION_90;
      case "portraitDown":
        return Surface.ROTATION_180;
      case "landscapeRight":
        return Surface.ROTATION_270;
      default:
        return Surface.ROTATION_0;
    }
  }

  /**
   * Binds VideoCapture before Recorder.start() so ResolutionInfo and the
   * recording GPU effect are ready before the first encoded frame. ImageAnalysis is
   * temporarily removed, matching camera_android_camerax's own start path.
   */
  private static boolean prebindVideoCaptureForHandshake() {
    final ProcessCameraProvider provider;
    final LifecycleOwner lifecycleOwner;
    final CameraSelector cameraSelector;
    final VideoCapture<?> videoCapture;
    final List<UseCase> boundUseCases;
    synchronized (LOCK) {
      provider = activeCameraProvider.get();
      lifecycleOwner = activeLifecycleOwner.get();
      cameraSelector = activeCameraSelector.get();
      videoCapture = activeVideoCapture.get();
      boundUseCases = new ArrayList<>(lastBoundUseCases);
    }
    if (provider == null
        || lifecycleOwner == null
        || cameraSelector == null
        || videoCapture == null) {
      return false;
    }

    try {
      // Recording rotation is isolated to VideoCapture. Do not mutate Preview
      // or ImageCapture target rotation: PHOTO/idle preview own that contract.
      videoCapture.setTargetRotation(requestedVideoTargetRotation);
      for (UseCase useCase : boundUseCases) {
        if (useCase instanceof ImageAnalysis && provider.isBound(useCase)) {
          provider.unbind(useCase);
        }
      }
      if (provider.isBound(videoCapture)) return true;

      final CameraEffect effect = effectForTargets(CameraEffect.VIDEO_CAPTURE);
      if (effect == null) return false;
      final UseCaseGroup group = new UseCaseGroup.Builder()
          .addUseCase(videoCapture)
          .addEffect(effect)
          .build();
      provider.bindToLifecycle(lifecycleOwner, cameraSelector, group);
      return provider.isBound(videoCapture);
    } catch (RuntimeException error) {
      lastError = "CameraX VideoCapture prebind failed: " + error;
      Log.w("SiteSnapOverlay", lastError, error);
      return false;
    }
  }

  /**
   * Unbinds a VideoCapture that was attached only for the pre-record handshake.
   *
   * <p>This is used when Flutter falls back before Recorder.start(). Without
   * this cleanup, CameraX can keep the already-bound effect pipeline even after
   * SiteSnap is disarmed, preventing the pinned plugin from rebinding a clean
   * upstream VideoCapture path.</p>
   */
  public static void releaseHandshakePrebindForFallback() {
    final ProcessCameraProvider provider;
    final VideoCapture<?> videoCapture;
    synchronized (LOCK) {
      provider = activeCameraProvider.get();
      videoCapture = activeVideoCapture.get();
    }
    if (provider == null || videoCapture == null) return;
    try {
      if (provider.isBound(videoCapture)) {
        provider.unbind(videoCapture);
        Log.i("SiteSnapOverlay", "Released failed realtime VideoCapture prebind");
      }
    } catch (RuntimeException error) {
      Log.w("SiteSnapOverlay", "Unable to release failed VideoCapture prebind", error);
    } finally {
      synchronized (LOCK) {
        for (SiteSnapDynamicVideoEffect effect : EFFECTS.values()) {
          try {
            effect.releaseEffect();
          } catch (RuntimeException ignored) {
          }
        }
        EFFECTS.clear();
      }
    }
  }

  /** Resets post-start render verification without disabling the ready overlay. */
  public static void markRecordingStarted() {
    renderedFramesSinceEnable = 0;
    renderedOverlayGeneration = 0;
    lastRenderedUptimeMs = 0;
    errorSinceEnable = false;
  }

  /** Releases any frame hold and returns the bound effect to transparent pass-through. */
  public static void cancelHandshake() {
    handshakePending = false;
    enabled = false;
  }

  public static boolean isArmed() {
    return armed;
  }

  /**
   * Returns the builder-time mirror mode requested by Flutter.
   *
   * <p>CameraX exposes mirror configuration on VideoCapture.Builder, not as a
   * supported mutation of an already-built VideoCapture. The patched
   * VideoCaptureProxyApi reads this value before build().</p>
   */
  public static int requestedVideoMirrorMode() {
    return frontVideoMirrorEnabled
        ? MirrorMode.MIRROR_MODE_ON_FRONT_ONLY
        : MirrorMode.MIRROR_MODE_OFF;
  }

  /** Records the most recent lifecycle binding so record-time prebind is safe. */
  public static void registerBindingContext(
      @NonNull ProcessCameraProvider provider,
      @NonNull LifecycleOwner lifecycleOwner,
      @NonNull CameraSelector cameraSelector,
      @NonNull List<? extends UseCase> useCases) {
    synchronized (LOCK) {
      activeCameraProvider = new WeakReference<>(provider);
      activeLifecycleOwner = new WeakReference<>(lifecycleOwner);
      activeCameraSelector = new WeakReference<>(cameraSelector);
      lastBoundUseCases = new ArrayList<>(useCases);
    }
  }

  /** Registers the VideoCapture created by the pinned Flutter CameraX plugin. */
  public static void registerVideoCapture(@NonNull VideoCapture<?> videoCapture) {
    synchronized (LOCK) {
      activeVideoCapture = new WeakReference<>(videoCapture);
    }
  }

  /**
   * Stores the requested mirror mode and reports whether the current
   * VideoCapture was already built with that mode.
   *
   * <p>A false result with a registered VideoCapture means Flutter should
   * recreate/rebind the controller before recording. Unsupported platforms keep
   * the existing FFmpeg fallback.</p>
   */
  public static boolean setFrontVideoMirroring(boolean enabled) {
    frontVideoMirrorEnabled = enabled;
    VideoCapture<?> videoCapture;
    synchronized (LOCK) {
      videoCapture = activeVideoCapture.get();
    }
    if (videoCapture == null) return false;
    try {
      return videoCapture.getMirrorMode() == requestedVideoMirrorMode();
    } catch (RuntimeException error) {
      lastError = "CameraX video mirror status failed: " + error;
      return false;
    }
  }

  @NonNull
  public static Map<String, Object> captureTransformStatusMap() {
    Map<String, Object> map = new HashMap<>();
    map.put("frontVideoMirrorEnabled", frontVideoMirrorEnabled);
    map.put("requestedMirrorMode", requestedVideoMirrorMode());
    VideoCapture<?> videoCapture;
    synchronized (LOCK) {
      videoCapture = activeVideoCapture.get();
    }
    map.put("videoCaptureRegistered", videoCapture != null);
    if (videoCapture != null) {
      try {
        int mirrorMode = videoCapture.getMirrorMode();
        map.put("mirrorMode", mirrorMode);
        map.put("matchesRequestedMirrorMode", mirrorMode == requestedVideoMirrorMode());
      } catch (RuntimeException error) {
        map.put("mirrorMode", -1);
        map.put("matchesRequestedMirrorMode", false);
      }
    } else {
      map.put("matchesRequestedMirrorMode", false);
    }
    return map;
  }

  /** Returns SiteSnap's recording-only GPU effect for one CameraX UseCaseGroup. */
  @Nullable
  public static CameraEffect effectForTargets(int targets) {
    if (!armed || targets != CameraEffect.VIDEO_CAPTURE) return null;

    synchronized (LOCK) {
      SiteSnapDynamicVideoEffect existing = EFFECTS.get(targets);
      if (existing != null) {
        existing.setOverlayEnabled(enabled);
        if (latestOverlayPng != null && overlayGeneration > 0) {
          existing.setOverlayPng(
              latestOverlayPng, overlayGeneration, latestOverlayLayoutOrientation);
        }
        return existing;
      }

      Consumer<Throwable> errorListener = SiteSnapRealtimeOverlayController::reportGpuError;
      SiteSnapDynamicVideoEffect effect = new SiteSnapDynamicVideoEffect(targets, errorListener);
      if (latestOverlayPng != null && overlayGeneration > 0) {
        effect.setOverlayPng(
            latestOverlayPng, overlayGeneration, latestOverlayLayoutOrientation);
      }
      effect.setOverlayEnabled(enabled);
      EFFECTS.put(targets, effect);
      return effect;
    }
  }

  /**
   * Legacy compatibility hook. Ongoing Recorder camera pixels deliberately do
   * not rotate here; current physical orientation is expressed by the Flutter
   * overlay raster instead.
   */
  public static boolean setDynamicCaptureOrientation(@Nullable String orientation) {
    return armed;
  }

  /** Called when the latest Flutter raster is resident in the GL texture. */
  static void onGpuOverlayUploaded(long generation, @Nullable String orientation) {
    if (latestOverlayPng == null || generation <= 0 || generation > overlayGeneration) return;
    uploadedOverlayGeneration = Math.max(uploadedOverlayGeneration, generation);
    if (generation == uploadedOverlayGeneration && orientation != null) {
      uploadedOverlayLayoutOrientation = normalizeCaptureOrientation(orientation);
    }
  }

  /** Called by the GPU processor after an encoder-surface frame is presented. */
  static void onGpuFrameRendered(
      long generation, int outputWidth, int outputHeight, long timestampNs) {
    lastFrameUptimeMs = SystemClock.elapsedRealtime();
    if (enabled && generation > 0) {
      renderedFramesSinceEnable++;
      renderedOverlayGeneration = generation;
      lastRenderedUptimeMs = lastFrameUptimeMs;
      if (handshakePending) {
        handshakePending = false;
        Log.i(
            "SiteSnapOverlay",
            "First realtime GPU overlay frame rendered generation=" + generation);
      }
    }
  }

  static void reportOverlayUpdateWarning(@Nullable Throwable throwable) {
    lastError =
        throwable == null ? "Unknown realtime overlay update warning" : throwable.toString();
    Log.w("SiteSnapOverlay", "Realtime overlay update warning: " + lastError);
  }

  static void reportGpuError(@Nullable Throwable throwable) {
    lastError = throwable == null ? "Unknown CameraX GPU compositor error" : throwable.toString();
    errorSinceEnable = true;
    enabled = false;
    handshakePending = false;
    synchronized (LOCK) {
      for (SiteSnapDynamicVideoEffect effect : EFFECTS.values()) {
        effect.setOverlayEnabled(false);
      }
    }
    Log.e("SiteSnapOverlay", "CameraX GPU compositor error: " + lastError);
  }

  private static int normalizeRotation(int rotationDegrees) {
    int normalized = rotationDegrees % 360;
    if (normalized < 0) normalized += 360;
    if (normalized < 45 || normalized >= 315) return 0;
    if (normalized < 135) return 90;
    if (normalized < 225) return 180;
    return 270;
  }

  @Nullable
  private static int[] readPngSize(@NonNull byte[] pngBytes) {
    // PNG signature + IHDR length/type + width/height requires 24 bytes. This
    // avoids BitmapFactory work on the MethodChannel thread; full decode stays
    // on SiteSnap-Overlay-Decode inside the GPU processor.
    if (pngBytes.length < 24
        || (pngBytes[0] & 0xff) != 0x89
        || pngBytes[1] != 0x50
        || pngBytes[2] != 0x4e
        || pngBytes[3] != 0x47
        || pngBytes[4] != 0x0d
        || pngBytes[5] != 0x0a
        || pngBytes[6] != 0x1a
        || pngBytes[7] != 0x0a
        || pngBytes[12] != 0x49
        || pngBytes[13] != 0x48
        || pngBytes[14] != 0x44
        || pngBytes[15] != 0x52) {
      return null;
    }
    final int width = readBigEndianInt(pngBytes, 16);
    final int height = readBigEndianInt(pngBytes, 20);
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return null;
    return new int[] {width, height};
  }

  private static int readBigEndianInt(@NonNull byte[] bytes, int offset) {
    return ((bytes[offset] & 0xff) << 24)
        | ((bytes[offset + 1] & 0xff) << 16)
        | ((bytes[offset + 2] & 0xff) << 8)
        | (bytes[offset + 3] & 0xff);
  }

  public static boolean setOverlayPng(
      @Nullable byte[] pngBytes, @Nullable String orientation) {
    if (pngBytes != null && pngBytes.length > 8 * 1024 * 1024) {
      lastError = "Flutter overlay PNG exceeded 8 MiB safety limit";
      return false;
    }
    if (pngBytes == null || pngBytes.length == 0) {
      clearOverlay();
      return false;
    }

    final int[] pngSize = readPngSize(pngBytes);
    if (pngSize == null) {
      lastError = "Flutter overlay PNG header is invalid";
      return false;
    }

    final byte[] copy = pngBytes.clone();
    final String normalizedOrientation = normalizeCaptureOrientation(orientation);
    synchronized (LOCK) {
      latestOverlayPng = copy;
      latestOverlayLayoutOrientation = normalizedOrientation;
      overlayBitmapWidth = pngSize[0];
      overlayBitmapHeight = pngSize[1];
      overlayGeneration++;
      lastOverlaySetUptimeMs = SystemClock.elapsedRealtime();
      for (SiteSnapDynamicVideoEffect effect : EFFECTS.values()) {
        effect.setOverlayPng(copy, overlayGeneration, normalizedOrientation);
      }
    }
    return true;
  }

  public static void setEnabled(boolean value) {
    if (value) {
      renderedFramesSinceEnable = 0;
      errorSinceEnable = false;
    }
    enabled = value && latestOverlayPng != null;
    synchronized (LOCK) {
      for (SiteSnapDynamicVideoEffect effect : EFFECTS.values()) {
        effect.setOverlayEnabled(enabled);
      }
    }
  }

  public static boolean isEnabled() {
    return enabled;
  }

  public static void clearOverlay() {
    enabled = false;
    synchronized (LOCK) {
      latestOverlayPng = null;
      uploadedOverlayGeneration = 0;
      latestOverlayLayoutOrientation = "portraitUp";
      uploadedOverlayLayoutOrientation = "portraitUp";
      overlayBitmapWidth = 0;
      overlayBitmapHeight = 0;
      for (SiteSnapDynamicVideoEffect effect : EFFECTS.values()) {
        effect.setOverlayEnabled(false);
        effect.clearOverlay();
      }
    }
  }

  @Nullable
  public static Map<String, Object> frameGeometryMap() {
    FrameGeometry geometry = lastFrameGeometry;
    if (geometry == null) {
      final VideoCapture<?> videoCapture;
      synchronized (LOCK) {
        videoCapture = activeVideoCapture.get();
      }
      if (videoCapture != null) {
        try {
          final ResolutionInfo info = videoCapture.getResolutionInfo();
          if (info != null) {
            final Rect crop = info.getCropRect();
            final int rotation = normalizeRotation(info.getRotationDegrees());
            final int cropWidth = Math.max(1, crop.width());
            final int cropHeight = Math.max(1, crop.height());
            final int displayWidth =
                (rotation == 90 || rotation == 270) ? cropHeight : cropWidth;
            final int displayHeight =
                (rotation == 90 || rotation == 270) ? cropWidth : cropHeight;
            final Size resolution = info.getResolution();
            geometry = new FrameGeometry(
                displayWidth,
                displayHeight,
                rotation,
                false,
                crop.left,
                crop.top,
                crop.right,
                crop.bottom,
                resolution.getWidth(),
                resolution.getHeight());
          }
        } catch (RuntimeException ignored) {
          // ResolutionInfo is expected to become available shortly after prebind.
        }
      }
    }
    if (geometry == null) return null;
    Map<String, Object> map = new HashMap<>();
    map.put("width", geometry.width);
    map.put("height", geometry.height);
    map.put("rotationDegrees", geometry.rotationDegrees);
    map.put("mirrored", geometry.mirrored);
    map.put("cropLeft", geometry.cropLeft);
    map.put("cropTop", geometry.cropTop);
    map.put("cropRight", geometry.cropRight);
    map.put("cropBottom", geometry.cropBottom);
    map.put("bufferWidth", geometry.bufferWidth);
    map.put("bufferHeight", geometry.bufferHeight);
    return map;
  }


  @NonNull
  public static Map<String, Object> statusMap() {
    Map<String, Object> map = new HashMap<>();
    map.put("armed", armed);
    map.put("enabled", enabled);
    map.put("handshakePending", handshakePending);
    map.put("captureOrientation", requestedCaptureOrientation);
    map.put("targetRotation", requestedVideoTargetRotation);
    map.put("renderedFrames", renderedFramesSinceEnable);
    map.put("errorSinceEnable", errorSinceEnable);
    map.put("overlayGeneration", overlayGeneration);
    map.put("uploadedOverlayGeneration", uploadedOverlayGeneration);
    map.put("renderedOverlayGeneration", renderedOverlayGeneration);
    final long now = SystemClock.elapsedRealtime();
    if (lastFrameUptimeMs > 0) map.put("lastFrameAgeMs", Math.max(0L, now - lastFrameUptimeMs));
    if (lastRenderedUptimeMs > 0) map.put("lastRenderedAgeMs", Math.max(0L, now - lastRenderedUptimeMs));
    if (lastOverlaySetUptimeMs > 0) map.put("lastOverlaySetAgeMs", Math.max(0L, now - lastOverlaySetUptimeMs));
    if (overlayBitmapWidth > 0 && overlayBitmapHeight > 0) {
      map.put("bitmapWidth", overlayBitmapWidth);
      map.put("bitmapHeight", overlayBitmapHeight);
    }
    map.put("cameraTransformMode", "cameraxBasePassThrough");
    map.put("dynamicScaleMode", "none");
    map.put("overlayLayoutOrientation", latestOverlayLayoutOrientation);
    map.put("uploadedOverlayLayoutOrientation", uploadedOverlayLayoutOrientation);
    map.put("overlayFollowsPhysicalOrientation", true);
    map.put("dynamicRotationDegrees", 0);
    if (lastError != null) map.put("lastError", lastError);
    return map;
  }

  @Nullable
  public static String consumeLastError() {
    String error = lastError;
    lastError = null;
    return error;
  }

  public static void reset() {
    armed = false;
    enabled = false;
    handshakePending = false;
    clearOverlay();
    lastFrameGeometry = null;
    lastError = null;
    renderedFramesSinceEnable = 0;
    overlayGeneration = 0;
    uploadedOverlayGeneration = 0;
    renderedOverlayGeneration = 0;
    lastFrameUptimeMs = 0;
    lastRenderedUptimeMs = 0;
    lastOverlaySetUptimeMs = 0;
    errorSinceEnable = false;
    frontVideoMirrorEnabled = false;
    requestedVideoTargetRotation = Surface.ROTATION_0;
    requestedCaptureOrientation = "portraitUp";
    latestOverlayLayoutOrientation = "portraitUp";
    uploadedOverlayLayoutOrientation = "portraitUp";
    synchronized (LOCK) {
      activeVideoCapture.clear();
      activeVideoCapture = new WeakReference<>(null);
      activeCameraProvider.clear();
      activeCameraProvider = new WeakReference<>(null);
      activeLifecycleOwner.clear();
      activeLifecycleOwner = new WeakReference<>(null);
      activeCameraSelector.clear();
      activeCameraSelector = new WeakReference<>(null);
      lastBoundUseCases = new ArrayList<>();
      for (SiteSnapDynamicVideoEffect effect : EFFECTS.values()) {
        try {
          effect.releaseEffect();
        } catch (RuntimeException ignored) {
          // CameraX owns surface shutdown ordering; reset remains best effort.
        }
      }
      EFFECTS.clear();
    }
  }

  private static final class FrameGeometry {
    final int width;
    final int height;
    final int rotationDegrees;
    final boolean mirrored;
    final int cropLeft;
    final int cropTop;
    final int cropRight;
    final int cropBottom;
    final int bufferWidth;
    final int bufferHeight;

    FrameGeometry(
        int width,
        int height,
        int rotationDegrees,
        boolean mirrored,
        int cropLeft,
        int cropTop,
        int cropRight,
        int cropBottom,
        int bufferWidth,
        int bufferHeight) {
      this.width = width;
      this.height = height;
      this.rotationDegrees = rotationDegrees;
      this.mirrored = mirrored;
      this.cropLeft = cropLeft;
      this.cropTop = cropTop;
      this.cropRight = cropRight;
      this.cropBottom = cropBottom;
      this.bufferWidth = bufferWidth;
      this.bufferHeight = bufferHeight;
    }
  }
}
