package io.flutter.plugins.camerax;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraEffect;
import androidx.camera.core.CameraInfo;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.Preview;
import androidx.camera.core.UseCase;
import androidx.camera.core.UseCaseGroup;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.VideoCapture;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;
import com.google.common.util.concurrent.ListenableFuture;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutionException;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * SiteSnap patch of camera_android_camerax 0.7.1+2's provider binding.
 *
 * <p>When the realtime bridge is armed, effective use cases are put in a UseCaseGroup and the
 * recording-only SiteSnap GPU CameraEffect is attached. For the normal idle camera group only,
 * unused ImageAnalysis is left unbound as a thermal optimization; all on-demand binds remain
 * upstream-compatible.</p>
 */
class ProcessCameraProviderProxyApi extends PigeonApiProcessCameraProvider {
  ProcessCameraProviderProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  @Override
  public void getInstance(
      @NonNull Function1<? super Result<ProcessCameraProvider>, Unit> callback) {
    final ListenableFuture<ProcessCameraProvider> processCameraProviderFuture =
        ProcessCameraProvider.getInstance(getPigeonRegistrar().getContext());

    processCameraProviderFuture.addListener(
        () -> {
          try {
            ResultCompat.success(processCameraProviderFuture.get(), callback);
          } catch (InterruptedException | ExecutionException e) {
            ResultCompat.failure(e, callback);
          }
        },
        ContextCompat.getMainExecutor(getPigeonRegistrar().getContext()));
  }

  @NonNull
  @Override
  public List<CameraInfo> getAvailableCameraInfos(ProcessCameraProvider pigeonInstance) {
    return pigeonInstance.getAvailableCameraInfos();
  }

  @NonNull
  @Override
  public Camera bindToLifecycle(
      @NonNull ProcessCameraProvider pigeonInstance,
      @NonNull CameraSelector cameraSelector,
      @NonNull List<? extends UseCase> useCases) {
    final LifecycleOwner lifecycleOwner = getPigeonRegistrar().getLifecycleOwner();
    if (lifecycleOwner == null) {
      throw new IllegalStateException(
          "LifecycleOwner must be set to get ProcessCameraProvider instance.");
    }

    final List<UseCase> effectiveUseCases = withoutIdleImageAnalysis(useCases);

    SiteSnapRealtimeOverlayController.registerBindingContext(
        pigeonInstance, lifecycleOwner, cameraSelector, effectiveUseCases);

    if (!SiteSnapRealtimeOverlayController.isArmed()) {
      return pigeonInstance.bindToLifecycle(
          lifecycleOwner, cameraSelector, effectiveUseCases.toArray(new UseCase[0]));
    }

    int targets = 0;
    for (UseCase useCase : effectiveUseCases) {
      if (useCase instanceof VideoCapture) {
        targets = CameraEffect.VIDEO_CAPTURE;
        break;
      }
    }

    // Keep the Flutter CustomPaint overlay as the preview source of truth. The
    // native effect targets only VideoCapture, avoiding Preview duplication and
    // reducing CameraX surface-combination pressure on physical devices.
    if (targets == 0) {
      return pigeonInstance.bindToLifecycle(
          lifecycleOwner, cameraSelector, effectiveUseCases.toArray(new UseCase[0]));
    }

    Log.i("SiteSnapOverlay", "Binding CameraX dynamic GPU effect targets=" + targets);
    final CameraEffect videoEffect =
        SiteSnapRealtimeOverlayController.effectForTargets(targets);
    if (videoEffect == null) {
      return pigeonInstance.bindToLifecycle(
          lifecycleOwner, cameraSelector, effectiveUseCases.toArray(new UseCase[0]));
    }

    final UseCaseGroup.Builder groupBuilder = new UseCaseGroup.Builder();
    for (UseCase useCase : effectiveUseCases) {
      groupBuilder.addUseCase(useCase);
    }
    groupBuilder.addEffect(videoEffect);
    return pigeonInstance.bindToLifecycle(
        lifecycleOwner, cameraSelector, groupBuilder.build());
  }

  /**
   * The pinned Flutter plugin initially binds Preview + ImageCapture + ImageAnalysis even when
   * nobody consumes an image stream. Keep ImageAnalysis on-demand instead: its later one-use-case
   * bind path is left untouched. This removes one continuously configured 1080p surface from the
   * normal camera screen and lowers idle ISP/memory pressure without changing photo/video output.
   */
  @NonNull
  private static List<UseCase> withoutIdleImageAnalysis(
      @NonNull List<? extends UseCase> useCases) {
    boolean hasPreview = false;
    boolean hasImageCapture = false;
    boolean hasImageAnalysis = false;
    boolean hasVideoCapture = false;

    for (UseCase useCase : useCases) {
      hasPreview |= useCase instanceof Preview;
      hasImageCapture |= useCase instanceof ImageCapture;
      hasImageAnalysis |= useCase instanceof ImageAnalysis;
      hasVideoCapture |= useCase instanceof VideoCapture;
    }

    final boolean isInitialIdleCameraGroup =
        useCases.size() == 3
            && hasPreview
            && hasImageCapture
            && hasImageAnalysis
            && !hasVideoCapture;
    if (!isInitialIdleCameraGroup) {
      return new ArrayList<UseCase>(useCases);
    }

    final List<UseCase> result = new ArrayList<>();
    for (UseCase useCase : useCases) {
      if (!(useCase instanceof ImageAnalysis)) {
        result.add(useCase);
      }
    }
    Log.i("SiteSnapPhoto", "Thermal guard: idle ImageAnalysis left unbound");
    return result;
  }

  @Override
  public boolean isBound(ProcessCameraProvider pigeonInstance, @NonNull UseCase useCase) {
    return pigeonInstance.isBound(useCase);
  }

  @Override
  public void unbind(
      ProcessCameraProvider pigeonInstance, @NonNull List<? extends UseCase> useCases) {
    pigeonInstance.unbind(useCases.toArray(new UseCase[0]));
  }

  @Override
  public void unbindAll(ProcessCameraProvider pigeonInstance) {
    pigeonInstance.unbindAll();
  }
}
