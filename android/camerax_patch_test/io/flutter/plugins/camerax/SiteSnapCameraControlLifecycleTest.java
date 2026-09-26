package io.flutter.plugins.camerax;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

import androidx.camera.core.CameraControl;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.FocusMeteringResult;
import com.google.common.util.concurrent.FutureCallback;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.Collections;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

public class SiteSnapCameraControlLifecycleTest {
  @Test public void detachedCodecReproducesTheReportedUnsupportedFocusValue() {
    final TestProxyApiRegistrar registrar = new TestProxyApiRegistrar();
    registrar.setIgnoreCallsToDart(true);
    final FocusMeteringResult result = mock(FocusMeteringResult.class);
    assertThrows(IllegalArgumentException.class,
        () -> registrar.getCodec().encodeMessage(Collections.singletonList(result)));
  }

  @SuppressWarnings("unchecked")
  private void focusReply(boolean detach, Throwable failure) {
    final TestProxyApiRegistrar registrar = new TestProxyApiRegistrar();
    final CameraControlProxyApi api = new CameraControlProxyApi(registrar);
    final CameraControl camera = mock(CameraControl.class);
    final FocusMeteringAction action = mock(FocusMeteringAction.class);
    final ListenableFuture<FocusMeteringResult> future = mock(ListenableFuture.class);
    when(camera.startFocusAndMetering(action)).thenReturn(future);
    final AtomicInteger replies = new AtomicInteger();
    final FocusMeteringResult result = mock(FocusMeteringResult.class);

    try (MockedStatic<Futures> mocked = mockStatic(Futures.class)) {
      final ArgumentCaptor<FutureCallback<FocusMeteringResult>> callback =
          ArgumentCaptor.forClass(FutureCallback.class);
      api.startFocusAndMetering(camera, action, ResultCompat.<FocusMeteringResult>asCompatCallback(reply -> {
        replies.incrementAndGet();
        if (failure instanceof CameraControl.OperationCanceledException) {
          assertTrue(reply.isSuccess());
          assertNull(reply.getOrNull());
        } else if (failure != null) {
          assertSame(failure, reply.exceptionOrNull());
        } else {
          assertSame(result, reply.getOrNull());
        }
        return null;
      }));
      mocked.verify(() -> Futures.addCallback(eq(future), callback.capture(), any()));
      // Simulate detach AFTER a focus request, BEFORE its native future completes.
      registrar.setIgnoreCallsToDart(detach);
      if (failure == null) callback.getValue().onSuccess(result);
      else callback.getValue().onFailure(failure);
      assertEquals(detach ? 0 : 1, replies.get());
    }
  }

  @Test public void activeFocusStillReplies() { focusReply(false, null); }
  @Test public void focusSuccessAfterDetachDoesNotEnterCodec() { focusReply(true, null); }
  @Test public void focusFailureAfterDetachDoesNotReply() {
    focusReply(true, new IllegalStateException("closed"));
  }
  @Test public void activeFailureIsNotSwallowed() {
    focusReply(false, new IllegalStateException("camera failure"));
  }
  @Test public void cancellationRetainsUpstreamNullSuccess() {
    focusReply(false, new CameraControl.OperationCanceledException("superseded"));
  }
}
