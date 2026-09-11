package io.flutter.plugins.camerax;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.ResolutionInfo;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import java.io.File;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * SiteSnap photo-focused patch of camera_android_camerax 0.7.1+2's ImageCapture proxy.
 *
 * <p>SiteSnap keeps ImageCapture on the Flutter controller's selected resolution contract so
 * Preview, zoom and still capture share a stable CameraX surface combination. The patch only
 * hardens capture latency/JPEG quality and executor reuse; it does not force a separate
 * highest-resolution surface that can stall the first shutter on some devices.</p>
 */
class ImageCaptureProxyApi extends PigeonApiImageCapture {
  static final String TEMPORARY_FILE_NAME = "CAP";
  static final String JPG_FILE_TYPE = ".jpg";

  // The stock plugin creates a new single-thread executor on every shutter press. Reuse a tiny
  // process-lifetime pool instead to avoid thread churn during repeated captures.
  private static final AtomicInteger THREAD_ID = new AtomicInteger(0);
  private static final ThreadFactory PHOTO_THREAD_FACTORY =
      runnable -> {
        final Thread thread =
            new Thread(runnable, "SiteSnap-Photo-" + THREAD_ID.incrementAndGet());
        thread.setPriority(Thread.NORM_PRIORITY);
        return thread;
      };
  private static final ExecutorService PHOTO_EXECUTOR =
      Executors.newFixedThreadPool(2, PHOTO_THREAD_FACTORY);

  ImageCaptureProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  @NonNull
  @Override
  public ImageCapture pigeon_defaultConstructor(
      @Nullable ResolutionSelector resolutionSelector,
      @Nullable Long targetRotation,
      @Nullable CameraXFlashMode flashMode) {
    final ImageCapture.Builder builder =
        new ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setJpegQuality(97)
            .setIoExecutor(PHOTO_EXECUTOR);

    // Keep ImageCapture on the same resolution contract selected by the Flutter
    // controller. Forcing HIGHEST_AVAILABLE while Preview is already bound can
    // create a much heavier surface combination, causing first-shutter stalls
    // and sluggish zoom on some CameraX devices. ResolutionPreset.veryHigh is
    // already the app's high-quality production profile; preserving that selector
    // keeps Preview/zoom/capture in one stable session while retaining detail.
    if (resolutionSelector != null) {
      builder.setResolutionSelector(resolutionSelector);
    }

    if (targetRotation != null) {
      builder.setTargetRotation(targetRotation.intValue());
    }
    if (flashMode != null) {
      switch (flashMode) {
        case AUTO:
          builder.setFlashMode(ImageCapture.FLASH_MODE_AUTO);
          break;
        case OFF:
          builder.setFlashMode(ImageCapture.FLASH_MODE_OFF);
          break;
        case ON:
          builder.setFlashMode(ImageCapture.FLASH_MODE_ON);
          break;
      }
    }

    return builder.build();
  }

  @Override
  public void setFlashMode(
      @NonNull ImageCapture pigeonInstance, @NonNull CameraXFlashMode flashMode) {
    int nativeFlashMode = -1;
    switch (flashMode) {
      case AUTO:
        nativeFlashMode = ImageCapture.FLASH_MODE_AUTO;
        break;
      case OFF:
        nativeFlashMode = ImageCapture.FLASH_MODE_OFF;
        break;
      case ON:
        nativeFlashMode = ImageCapture.FLASH_MODE_ON;
    }
    pigeonInstance.setFlashMode(nativeFlashMode);
  }

  @Override
  public void takePicture(
      @NonNull ImageCapture pigeonInstance,
      @NonNull SystemServicesManager systemServicesManager,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    final File outputDir = getPigeonRegistrar().getContext().getCacheDir();
    final File temporaryCaptureFile;
    try {
      temporaryCaptureFile = File.createTempFile(TEMPORARY_FILE_NAME, JPG_FILE_TYPE, outputDir);
    } catch (IOException | SecurityException e) {
      ResultCompat.failure(e, callback);
      return;
    }

    final ResolutionInfo resolutionInfo = pigeonInstance.getResolutionInfo();
    if (resolutionInfo != null) {
      Log.i(
          "SiteSnapPhoto",
          "Capture surface="
              + resolutionInfo.getResolution()
              + " crop="
              + resolutionInfo.getCropRect()
              + " jpegQuality=97 mode=minLatency");
    }

    final ImageCapture.OutputFileOptions outputFileOptions =
        createImageCaptureOutputFileOptions(temporaryCaptureFile);
    final ImageCapture.OnImageSavedCallback onImageSavedCallback =
        createOnImageSavedCallback(temporaryCaptureFile, systemServicesManager, callback);

    pigeonInstance.takePicture(outputFileOptions, PHOTO_EXECUTOR, onImageSavedCallback);
  }

  @Override
  public void setTargetRotation(ImageCapture pigeonInstance, long rotation) {
    pigeonInstance.setTargetRotation((int) rotation);
  }

  @Nullable
  @Override
  public ResolutionSelector resolutionSelector(@NonNull ImageCapture pigeonInstance) {
    return pigeonInstance.getResolutionSelector();
  }

  ImageCapture.OutputFileOptions createImageCaptureOutputFileOptions(@NonNull File file) {
    return new ImageCapture.OutputFileOptions.Builder(file).build();
  }

  @NonNull
  ImageCapture.OnImageSavedCallback createOnImageSavedCallback(
      @NonNull File file,
      @NonNull SystemServicesManager systemServicesManager,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    return new ImageCapture.OnImageSavedCallback() {
      @Override
      public void onImageSaved(@NonNull ImageCapture.OutputFileResults outputFileResults) {
        ResultCompat.success(file.getAbsolutePath(), callback);
      }

      @Override
      public void onError(@NonNull ImageCaptureException exception) {
        systemServicesManager.onCameraError(
            getImageCaptureExceptionDescription(exception.getImageCaptureError()));
        ResultCompat.failure(exception, callback);
      }
    };
  }

  String getImageCaptureExceptionDescription(int imageCaptureErrorCode) {
    switch (imageCaptureErrorCode) {
      case ImageCapture.ERROR_FILE_IO:
        return "An error occurred while attempting to save the captured image to a file.";
      case ImageCapture.ERROR_CAPTURE_FAILED:
        return "The camera framework failed to fulfill the image capture request.";
      case ImageCapture.ERROR_CAMERA_CLOSED:
        return "Image capture failed due to the camera being closed.";
      case ImageCapture.ERROR_INVALID_CAMERA:
        return "Image capture failed because the ImageCapture use case is bound to an invalid camera.";
      default:
        return "An unknown error has occurred while attempting to take a picture.";
    }
  }
}
