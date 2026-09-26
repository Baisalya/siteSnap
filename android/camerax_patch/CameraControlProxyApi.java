// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the camera_android_camerax package's LICENSE file.

package io.flutter.plugins.camerax;

import androidx.annotation.NonNull;
import androidx.camera.core.CameraControl;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.FocusMeteringResult;
import androidx.core.content.ContextCompat;
import com.google.common.util.concurrent.FutureCallback;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import java.util.function.Function;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/** CameraX 0.7.1+2 bridge with engine-lifetime-safe asynchronous replies. */
class CameraControlProxyApi extends PigeonApiCameraControl {
  CameraControlProxyApi(@NonNull ProxyApiRegistrar registrar) {
    super(registrar);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  private <T, R> void replyWhenAttached(
      ListenableFuture<T> future,
      Function<T, R> convert,
      boolean cancellationIsSuccess,
      Function1<? super Result<R>, Unit> callback) {
    final ProxyApiRegistrar registrar = getPigeonRegistrar();
    Futures.addCallback(
        future,
        new FutureCallback<T>() {
          @Override
          public void onSuccess(T value) {
            // Engine detach disables Pigeon's instance registration. Encoding a
            // late FocusMeteringResult would then throw "Unsupported value" on
            // the main thread (Play crash CameraXLibrary.g.kt:1219). Check on the
            // same main executor as detach, BEFORE attempting a codec reply.
            if (registrar.getIgnoreCallsToDart()) return;
            ResultCompat.success(convert.apply(value), callback);
          }

          @Override
          public void onFailure(@NonNull Throwable error) {
            if (registrar.getIgnoreCallsToDart()) return;
            if (cancellationIsSuccess && error instanceof CameraControl.OperationCanceledException) {
              ResultCompat.success(null, callback);
            } else {
              ResultCompat.failure(error, callback);
            }
          }
        },
        ContextCompat.getMainExecutor(registrar.getContext()));
  }

  @Override
  public void enableTorch(
      @NonNull CameraControl camera, boolean enabled,
      @NonNull Function1<? super Result<Unit>, Unit> callback) {
    replyWhenAttached(camera.enableTorch(enabled), value -> null, false, callback);
  }

  @Override
  public void setZoomRatio(
      @NonNull CameraControl camera, double ratio,
      @NonNull Function1<? super Result<Unit>, Unit> callback) {
    replyWhenAttached(camera.setZoomRatio((float) ratio), value -> null, true, callback);
  }

  @Override
  public void startFocusAndMetering(
      @NonNull CameraControl camera, @NonNull FocusMeteringAction action,
      @NonNull Function1<? super Result<FocusMeteringResult>, Unit> callback) {
    replyWhenAttached(camera.startFocusAndMetering(action), value -> value, true, callback);
  }

  @Override
  public void cancelFocusAndMetering(
      @NonNull CameraControl camera,
      @NonNull Function1<? super Result<Unit>, Unit> callback) {
    replyWhenAttached(camera.cancelFocusAndMetering(), value -> null, false, callback);
  }

  @Override
  public void setExposureCompensationIndex(
      @NonNull CameraControl camera, long index,
      @NonNull Function1<? super Result<Long>, Unit> callback) {
    replyWhenAttached(
        camera.setExposureCompensationIndex((int) index), Integer::longValue, true, callback);
  }
}
