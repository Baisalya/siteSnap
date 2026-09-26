package io.flutter.plugins.camerax;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.*;

import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import java.io.File;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;

public class SiteSnapImageCaptureLifecycleTest {
  @Test public void captureCallbacksAreSuppressedAfterDetach() {
    final TestProxyApiRegistrar registrar = new TestProxyApiRegistrar();
    final ImageCaptureProxyApi api = new ImageCaptureProxyApi(registrar);
    final SystemServicesManager manager = mock(SystemServicesManager.class);
    final AtomicInteger replies = new AtomicInteger();
    final ImageCapture.OnImageSavedCallback callback = api.createOnImageSavedCallback(
        new File("photo.jpg"), manager, ResultCompat.<String>asCompatCallback(reply -> {
          replies.incrementAndGet();
          return null;
        }));
    registrar.setIgnoreCallsToDart(true);
    callback.onImageSaved(mock(ImageCapture.OutputFileResults.class));
    callback.onError(new ImageCaptureException(ImageCapture.ERROR_CAMERA_CLOSED, "closed", null));
    assertEquals(0, replies.get());
    verifyNoInteractions(manager);
  }
}
