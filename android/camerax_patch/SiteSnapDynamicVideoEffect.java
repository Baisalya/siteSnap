package io.flutter.plugins.camerax;

import androidx.annotation.NonNull;
import androidx.camera.core.CameraEffect;
import androidx.core.util.Consumer;

/**
 * Recording-only CameraX effect used by SiteSnap's realtime HUD compositor.
 *
 * <p>The effect targets VideoCapture only. Preview and ImageCapture never pass
 * through this processor, which keeps the established PHOTO/idle-preview
 * pipeline isolated from video orientation work.</p>
 */
final class SiteSnapDynamicVideoEffect extends CameraEffect {
  private final SiteSnapDynamicVideoSurfaceProcessor processor;

  SiteSnapDynamicVideoEffect(
      int targets,
      @NonNull Consumer<Throwable> errorListener) {
    this(new SiteSnapDynamicVideoSurfaceProcessor(), targets, errorListener);
  }

  private SiteSnapDynamicVideoEffect(
      @NonNull SiteSnapDynamicVideoSurfaceProcessor processor,
      int targets,
      @NonNull Consumer<Throwable> errorListener) {
    super(targets, processor.getExecutor(), processor, errorListener);
    this.processor = processor;
  }

  void setOverlayPng(
      byte[] pngBytes, long generation, @NonNull String orientation) {
    processor.setOverlayPng(pngBytes, generation, orientation);
  }

  void clearOverlay() {
    processor.clearOverlay();
  }

  void setOverlayEnabled(boolean enabled) {
    processor.setOverlayEnabled(enabled);
  }

  void releaseEffect() {
    processor.release();
  }
}
