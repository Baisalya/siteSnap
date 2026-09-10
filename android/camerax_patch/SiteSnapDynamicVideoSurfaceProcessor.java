package io.flutter.plugins.camerax;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.SurfaceTexture;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLExt;
import android.opengl.EGLSurface;
import android.opengl.GLES11Ext;
import android.opengl.GLES20;
import android.opengl.GLUtils;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.DynamicRange;
import androidx.camera.core.ProcessingException;
import androidx.camera.core.SurfaceOutput;
import androidx.camera.core.SurfaceProcessor;
import androidx.camera.core.SurfaceRequest;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Single-stream GPU compositor for SiteSnap video recording.
 *
 * <p>The encoder surface never changes while a clip is recording. CameraX's
 * base {@link SurfaceOutput} transform is preserved exactly for camera pixels:
 * SiteSnap never performs a mid-record zoom, crop, stretch, fit-center, or
 * artificial quarter-turn on the camera texture. Physical orientation changes
 * are represented only by a new transparent Flutter HUD raster, already laid
 * out in the fixed encoder canvas. This matches normal Recorder semantics while
 * still allowing the GPS card and SurveyCam branding to move with the phone.</p>
 */
final class SiteSnapDynamicVideoSurfaceProcessor
    implements SurfaceProcessor, SurfaceTexture.OnFrameAvailableListener {
  private static final String TAG = "SiteSnapVideoGpu";

  private static final int FLOAT_BYTES = 4;
  private static final float[] VERTICES = {
      -1f, -1f, 0f, 0f,
       1f, -1f, 1f, 0f,
      -1f,  1f, 0f, 1f,
       1f,  1f, 1f, 1f,
  };

  private static final String VERTEX_SHADER =
      "attribute vec2 aPosition;\n"
          + "attribute vec2 aTextureCoord;\n"
          + "uniform mat4 uCameraTexMatrix;\n"
          + "varying vec2 vCameraCoord;\n"
          + "varying vec2 vOutputCoord;\n"
          + "void main() {\n"
          + "  gl_Position = vec4(aPosition, 0.0, 1.0);\n"
          + "  vOutputCoord = aTextureCoord;\n"
          + "  vCameraCoord = (uCameraTexMatrix * vec4(aTextureCoord, 0.0, 1.0)).xy;\n"
          + "}\n";

  private static final String FRAGMENT_SHADER =
      "#extension GL_OES_EGL_image_external : require\n"
          + "precision mediump float;\n"
          + "varying vec2 vCameraCoord;\n"
          + "varying vec2 vOutputCoord;\n"
          + "uniform samplerExternalOES uCameraTexture;\n"
          + "uniform sampler2D uOverlayTexture;\n"
          + "uniform float uOverlayEnabled;\n"
          + "void main() {\n"
          + "  vec4 cameraColor = texture2D(uCameraTexture, vCameraCoord);\n"
          + "  vec2 overlayUv = vec2(vOutputCoord.x, 1.0 - vOutputCoord.y);\n"
          + "  vec4 overlayColor = texture2D(uOverlayTexture, overlayUv);\n"
          + "  float alpha = overlayColor.a * uOverlayEnabled;\n"
          + "  vec3 blended = overlayColor.rgb * alpha + cameraColor.rgb * (1.0 - alpha);\n"
          + "  gl_FragColor = vec4(blended, 1.0);\n"
          + "}\n";

  private final HandlerThread glThread = new HandlerThread("SiteSnap-Video-GPU");
  private final HandlerThread overlayDecodeThread =
      new HandlerThread("SiteSnap-Overlay-Decode");
  private final Handler glHandler;
  private final Handler overlayDecodeHandler;
  private final Executor glExecutor;
  private final AtomicBoolean releaseRequested = new AtomicBoolean(false);
  private final FloatBuffer vertexBuffer;
  private final Map<SurfaceOutput, OutputTarget> outputs = new LinkedHashMap<>();

  private EGLDisplay eglDisplay = EGL14.EGL_NO_DISPLAY;
  private EGLContext eglContext = EGL14.EGL_NO_CONTEXT;
  private EGLConfig eglConfig;
  private EGLSurface tempSurface = EGL14.EGL_NO_SURFACE;
  private boolean glInitialized;

  private int program = -1;
  private int overlayTextureId = -1;
  private int positionLoc = -1;
  private int textureCoordLoc = -1;
  private int cameraMatrixLoc = -1;
  private int cameraSamplerLoc = -1;
  private int overlaySamplerLoc = -1;
  private int overlayEnabledLoc = -1;

  private final Map<SurfaceTexture, InputTarget> inputs = new LinkedHashMap<>();
  @Nullable private InputTarget activeInput;
  private long nextInputSerial;

  private final float[] surfaceTextureMatrix = new float[16];
  private final float[] cameraXMatrix = new float[16];

  @Nullable private Bitmap pendingOverlayBitmap;
  private long pendingOverlayGeneration;
  @NonNull private String pendingOverlayOrientation = "portraitUp";
  private long uploadedOverlayGeneration;
  @NonNull private String uploadedOverlayOrientation = "portraitUp";
  private volatile long latestRequestedOverlayGeneration;
  private boolean overlayTextureReady;
  private volatile boolean overlayEnabled;
  private int consecutiveFrameErrors;
  private boolean runtimeFailureReported;

  SiteSnapDynamicVideoSurfaceProcessor() {
    glThread.start();
    overlayDecodeThread.start();
    glHandler = new Handler(glThread.getLooper());
    overlayDecodeHandler = new Handler(overlayDecodeThread.getLooper());
    glExecutor = command -> {
      if (Thread.currentThread() == glThread) {
        command.run();
      } else {
        glHandler.post(command);
      }
    };
    ByteBuffer bytes = ByteBuffer.allocateDirect(VERTICES.length * FLOAT_BYTES)
        .order(ByteOrder.nativeOrder());
    vertexBuffer = bytes.asFloatBuffer();
    vertexBuffer.put(VERTICES).position(0);
  }

  Executor getExecutor() {
    return glExecutor;
  }

  void setOverlayPng(
      @NonNull byte[] pngBytes, long generation, @NonNull String orientation) {
    if (releaseRequested.get()) return;
    final byte[] copy = pngBytes.clone();
    latestRequestedOverlayGeneration = generation;

    // PNG decoding is deliberately kept off the GL frame thread. Decoding a
    // 540x960 overlay on the render thread can block eglSwapBuffers long
    // enough to create the exact one-frame hitch the previous OverlayEffect
    // path showed during orientation/location updates.
    overlayDecodeHandler.post(() -> {
      if (releaseRequested.get() || generation != latestRequestedOverlayGeneration) return;
      final Bitmap decoded = BitmapFactory.decodeByteArray(copy, 0, copy.length);
      if (decoded == null) {
        SiteSnapRealtimeOverlayController.reportOverlayUpdateWarning(
            new IllegalArgumentException("Realtime overlay PNG could not be decoded"));
        return;
      }
      glExecutor.execute(() -> {
        if (releaseRequested.get() || generation != latestRequestedOverlayGeneration) {
          decoded.recycle();
          return;
        }
        if (pendingOverlayBitmap != null && pendingOverlayBitmap != decoded) {
          pendingOverlayBitmap.recycle();
        }
        pendingOverlayBitmap = decoded;
        pendingOverlayGeneration = generation;
        pendingOverlayOrientation = orientation;
        if (glInitialized) uploadPendingOverlay();
      });
    });
  }

  void clearOverlay() {
    overlayEnabled = false;
    latestRequestedOverlayGeneration = 0;
    glExecutor.execute(() -> {
      if (pendingOverlayBitmap != null) {
        pendingOverlayBitmap.recycle();
        pendingOverlayBitmap = null;
      }
      pendingOverlayGeneration = 0;
      pendingOverlayOrientation = "portraitUp";
      uploadedOverlayGeneration = 0;
      uploadedOverlayOrientation = "portraitUp";
      overlayTextureReady = false;
      if (glInitialized && overlayTextureId != -1) {
        makeCurrent(tempSurface);
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId);
        ByteBuffer transparent = ByteBuffer.allocateDirect(4);
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            1,
            1,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            transparent);
      }
    });
  }

  void setOverlayEnabled(boolean enabled) {
    overlayEnabled = enabled;
  }

  @Override
  public void onInputSurface(@NonNull SurfaceRequest surfaceRequest) throws ProcessingException {
    if (releaseRequested.get()) {
      surfaceRequest.willNotProvideSurface();
      return;
    }
    try {
      if (surfaceRequest.getDynamicRange().getBitDepth() == DynamicRange.BIT_DEPTH_10_BIT) {
        throw new IllegalStateException(
            "SiteSnap realtime video compositor currently requires SDR VideoCapture");
      }
      ensureGlInitialized();
      Size resolution = surfaceRequest.getResolution();
      int textureId = createTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES);
      SurfaceTexture texture = new SurfaceTexture(textureId);
      texture.setDefaultBufferSize(resolution.getWidth(), resolution.getHeight());
      Surface surface = new Surface(texture);
      InputTarget input =
          new InputTarget(surfaceRequest, texture, surface, textureId, ++nextInputSerial);
      inputs.put(texture, input);
      activeInput = input;
      texture.setOnFrameAvailableListener(this, glHandler);
      surfaceRequest.provideSurface(
          surface,
          glExecutor,
          result -> glExecutor.execute(() -> releaseInputSurface(input)));
      consecutiveFrameErrors = 0;
      runtimeFailureReported = false;
      Log.i(
          TAG,
          "Input ready " + resolution.getWidth() + "x" + resolution.getHeight()
              + " serial=" + input.serial);
    } catch (RuntimeException error) {
      surfaceRequest.willNotProvideSurface();
      SiteSnapRealtimeOverlayController.reportGpuError(error);
      ProcessingException processingException = new ProcessingException();
      processingException.initCause(error);
      throw processingException;
    }
  }

  @Override
  public void onOutputSurface(@NonNull SurfaceOutput surfaceOutput) throws ProcessingException {
    if (releaseRequested.get()) {
      surfaceOutput.close();
      return;
    }
    try {
      ensureGlInitialized();
      Surface surface = surfaceOutput.getSurface(
          glExecutor,
          event -> glExecutor.execute(() -> removeOutput(event.getSurfaceOutput())));
      Size size = surfaceOutput.getSize();
      EGLSurface eglSurface = EGL14.eglCreateWindowSurface(
          eglDisplay,
          eglConfig,
          surface,
          new int[] {EGL14.EGL_NONE},
          0);
      checkEgl("eglCreateWindowSurface");
      if (eglSurface == null || eglSurface == EGL14.EGL_NO_SURFACE) {
        throw new IllegalStateException("Unable to create encoder EGLSurface");
      }
      outputs.put(surfaceOutput, new OutputTarget(surfaceOutput, surface, eglSurface, size));
      Log.i(TAG, "Output ready " + size.getWidth() + "x" + size.getHeight()
          + " targets=" + surfaceOutput.getTargets());
    } catch (RuntimeException error) {
      surfaceOutput.close();
      SiteSnapRealtimeOverlayController.reportGpuError(error);
      ProcessingException processingException = new ProcessingException();
      processingException.initCause(error);
      throw processingException;
    }
  }

  @Override
  public void onFrameAvailable(@NonNull SurfaceTexture surfaceTexture) {
    if (releaseRequested.get() || !glInitialized) return;
    try {
      InputTarget input = inputs.get(surfaceTexture);
      if (input == null || activeInput != input) return;
      surfaceTexture.updateTexImage();
      surfaceTexture.getTransformMatrix(surfaceTextureMatrix);
      long timestampNs = surfaceTexture.getTimestamp();
      uploadPendingOverlay();

      for (OutputTarget target : outputs.values()) {
        renderToOutput(target, input.textureId, timestampNs);
      }
      consecutiveFrameErrors = 0;
    } catch (RuntimeException error) {
      handleRuntimeFrameFailure(error);
    }
  }

  private void renderToOutput(
      @NonNull OutputTarget target, int cameraTextureId, long timestampNs) {
    makeCurrent(target.eglSurface);
    GLES20.glViewport(0, 0, target.size.getWidth(), target.size.getHeight());
    GLES20.glClearColor(0f, 0f, 0f, 1f);
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);

    // CameraX owns the camera transform for the whole recording. Do not add a
    // physical-orientation matrix here: doing so either crops, stretches, or
    // letterboxes a fixed-size MP4 when the phone crosses 90 degrees.
    target.output.updateTransformMatrix(cameraXMatrix, surfaceTextureMatrix);

    GLES20.glUseProgram(program);
    vertexBuffer.position(0);
    GLES20.glVertexAttribPointer(positionLoc, 2, GLES20.GL_FLOAT, false, 4 * FLOAT_BYTES, vertexBuffer);
    GLES20.glEnableVertexAttribArray(positionLoc);
    vertexBuffer.position(2);
    GLES20.glVertexAttribPointer(textureCoordLoc, 2, GLES20.GL_FLOAT, false, 4 * FLOAT_BYTES, vertexBuffer);
    GLES20.glEnableVertexAttribArray(textureCoordLoc);
    GLES20.glUniformMatrix4fv(cameraMatrixLoc, 1, false, cameraXMatrix, 0);

    GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId);
    GLES20.glUniform1i(cameraSamplerLoc, 0);

    GLES20.glActiveTexture(GLES20.GL_TEXTURE1);
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId);
    GLES20.glUniform1i(overlaySamplerLoc, 1);
    final boolean drawOverlay = overlayEnabled && overlayTextureReady;
    GLES20.glUniform1f(overlayEnabledLoc, drawOverlay ? 1f : 0f);

    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
    checkGl("glDrawArrays");
    EGLExt.eglPresentationTimeANDROID(eglDisplay, target.eglSurface, timestampNs);
    if (!EGL14.eglSwapBuffers(eglDisplay, target.eglSurface)) {
      throw new IllegalStateException("eglSwapBuffers failed: 0x"
          + Integer.toHexString(EGL14.eglGetError()));
    }

    SiteSnapRealtimeOverlayController.onGpuFrameRendered(
        drawOverlay ? uploadedOverlayGeneration : 0,
        target.size.getWidth(),
        target.size.getHeight(),
        timestampNs);
  }

  private void handleRuntimeFrameFailure(@NonNull RuntimeException error) {
    consecutiveFrameErrors++;
    overlayEnabled = false;

    if (!runtimeFailureReported) {
      runtimeFailureReported = true;
      SiteSnapRealtimeOverlayController.reportGpuError(error);
      Log.e(
          TAG,
          "GPU overlay compositor disabled after runtime failure; CameraX base transform preserved",
          error);
    } else {
      Log.w(TAG, "GPU compositor frame retry failed (" + consecutiveFrameErrors + ")", error);
    }

    // CameraX documents SurfaceRequest.invalidate() as the recovery signal for
    // errors discovered after a SurfaceProcessor pipeline is already running.
    // Give the pass-through/base transform two chances first so a transient EGL
    // hiccup does not tear down an otherwise valid recording. Persistent GL/EGL
    // failure then asks CameraX for a fresh input surface rather than crashing the
    // process or spinning forever on the render thread.
    if (consecutiveFrameErrors >= 3) {
      final InputTarget input = activeInput;
      if (input != null && !input.invalidated) {
        input.invalidated = true;
        try {
          input.request.invalidate();
          Log.w(TAG, "Invalidated CameraX input surface after persistent GPU failure");
        } catch (RuntimeException invalidateError) {
          Log.w(TAG, "CameraX input surface invalidation failed", invalidateError);
        }
      }
    }
  }

  private void uploadPendingOverlay() {
    final Bitmap bitmap = pendingOverlayBitmap;
    if (bitmap == null || pendingOverlayGeneration == uploadedOverlayGeneration) return;
    if (releaseRequested.get()) {
      bitmap.recycle();
      pendingOverlayBitmap = null;
      return;
    }

    final long generation = pendingOverlayGeneration;
    final String orientation = pendingOverlayOrientation;
    makeCurrent(tempSurface);
    GLES20.glActiveTexture(GLES20.GL_TEXTURE1);
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId);
    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0);
    checkGl("overlay texImage2D");
    overlayTextureReady = true;
    uploadedOverlayGeneration = generation;
    uploadedOverlayOrientation = orientation;
    pendingOverlayBitmap = null;
    bitmap.recycle();
    SiteSnapRealtimeOverlayController.onGpuOverlayUploaded(
        uploadedOverlayGeneration, uploadedOverlayOrientation);
    Log.i(
        TAG,
        "Overlay layout uploaded generation=" + uploadedOverlayGeneration
            + " relativeOrientation=" + uploadedOverlayOrientation);
  }

  private void ensureGlInitialized() {
    if (glInitialized) return;
    if (Thread.currentThread() != glThread) {
      throw new IllegalStateException("OpenGL must initialize on SiteSnap GL thread");
    }

    eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
    if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
      throw new IllegalStateException("Unable to get EGL display");
    }
    int[] version = new int[2];
    if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
      throw new IllegalStateException("Unable to initialize EGL");
    }

    int[] configAttribs = {
        EGL14.EGL_RED_SIZE, 8,
        EGL14.EGL_GREEN_SIZE, 8,
        EGL14.EGL_BLUE_SIZE, 8,
        EGL14.EGL_ALPHA_SIZE, 8,
        EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
        EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT | EGL14.EGL_PBUFFER_BIT,
        EGL14.EGL_NONE
    };
    EGLConfig[] configs = new EGLConfig[1];
    int[] count = new int[1];
    if (!EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, count, 0)
        || count[0] <= 0) {
      throw new IllegalStateException("Unable to choose EGL config");
    }
    eglConfig = configs[0];

    eglContext = EGL14.eglCreateContext(
        eglDisplay,
        eglConfig,
        EGL14.EGL_NO_CONTEXT,
        new int[] {EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE},
        0);
    checkEgl("eglCreateContext");

    tempSurface = EGL14.eglCreatePbufferSurface(
        eglDisplay,
        eglConfig,
        new int[] {EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE},
        0);
    checkEgl("eglCreatePbufferSurface");
    makeCurrent(tempSurface);

    program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER);
    positionLoc = GLES20.glGetAttribLocation(program, "aPosition");
    textureCoordLoc = GLES20.glGetAttribLocation(program, "aTextureCoord");
    cameraMatrixLoc = GLES20.glGetUniformLocation(program, "uCameraTexMatrix");
    cameraSamplerLoc = GLES20.glGetUniformLocation(program, "uCameraTexture");
    overlaySamplerLoc = GLES20.glGetUniformLocation(program, "uOverlayTexture");
    overlayEnabledLoc = GLES20.glGetUniformLocation(program, "uOverlayEnabled");
    if (positionLoc < 0
        || textureCoordLoc < 0
        || cameraMatrixLoc < 0
        || cameraSamplerLoc < 0
        || overlaySamplerLoc < 0
        || overlayEnabledLoc < 0) {
      throw new IllegalStateException("SiteSnap GPU shader locations are incomplete");
    }

    overlayTextureId = createTexture(GLES20.GL_TEXTURE_2D);
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId);
    ByteBuffer transparent = ByteBuffer.allocateDirect(4);
    GLES20.glTexImage2D(
        GLES20.GL_TEXTURE_2D,
        0,
        GLES20.GL_RGBA,
        1,
        1,
        0,
        GLES20.GL_RGBA,
        GLES20.GL_UNSIGNED_BYTE,
        transparent);
    glInitialized = true;
    uploadPendingOverlay();
    Log.i(TAG, "OpenGL compositor initialized ES2");
  }

  private int createTexture(int target) {
    int[] ids = new int[1];
    GLES20.glGenTextures(1, ids, 0);
    if (ids[0] == 0) throw new IllegalStateException("glGenTextures returned 0");
    GLES20.glBindTexture(target, ids[0]);
    GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
    GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
    GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
    GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
    return ids[0];
  }

  private static int createProgram(String vertexSource, String fragmentSource) {
    int vertex = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource);
    int fragment = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
    int result = GLES20.glCreateProgram();
    GLES20.glAttachShader(result, vertex);
    GLES20.glAttachShader(result, fragment);
    GLES20.glLinkProgram(result);
    int[] linked = new int[1];
    GLES20.glGetProgramiv(result, GLES20.GL_LINK_STATUS, linked, 0);
    GLES20.glDeleteShader(vertex);
    GLES20.glDeleteShader(fragment);
    if (linked[0] != GLES20.GL_TRUE) {
      String log = GLES20.glGetProgramInfoLog(result);
      GLES20.glDeleteProgram(result);
      throw new IllegalStateException("Unable to link SiteSnap GPU program: " + log);
    }
    return result;
  }

  private static int compileShader(int type, String source) {
    int shader = GLES20.glCreateShader(type);
    GLES20.glShaderSource(shader, source);
    GLES20.glCompileShader(shader);
    int[] compiled = new int[1];
    GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0);
    if (compiled[0] != GLES20.GL_TRUE) {
      String log = GLES20.glGetShaderInfoLog(shader);
      GLES20.glDeleteShader(shader);
      throw new IllegalStateException("Unable to compile SiteSnap GPU shader: " + log);
    }
    return shader;
  }

  private void makeCurrent(EGLSurface surface) {
    if (!EGL14.eglMakeCurrent(eglDisplay, surface, surface, eglContext)) {
      throw new IllegalStateException("eglMakeCurrent failed: 0x"
          + Integer.toHexString(EGL14.eglGetError()));
    }
  }

  private void removeOutput(@NonNull SurfaceOutput output) {
    OutputTarget target = outputs.remove(output);
    if (target != null) {
      if (glInitialized && target.eglSurface != EGL14.EGL_NO_SURFACE) {
        EGL14.eglDestroySurface(eglDisplay, target.eglSurface);
      }
      output.close();
    }
  }

  private void releaseInputSurface(@NonNull InputTarget input) {
    input.texture.setOnFrameAvailableListener(null);
    inputs.remove(input.texture);
    if (activeInput == input) {
      activeInput = null;
      for (InputTarget remaining : inputs.values()) {
        activeInput = remaining;
      }
    }
    input.texture.release();
    input.surface.release();
    if (glInitialized && input.textureId != -1) {
      makeCurrent(tempSurface);
      GLES20.glDeleteTextures(1, new int[] {input.textureId}, 0);
    }
  }

  void release() {
    if (!releaseRequested.compareAndSet(false, true)) return;
    glExecutor.execute(this::releaseOnGlThread);
  }

  private void releaseOnGlThread() {
    for (OutputTarget target : outputs.values()) {
      try {
        if (glInitialized && target.eglSurface != EGL14.EGL_NO_SURFACE) {
          EGL14.eglDestroySurface(eglDisplay, target.eglSurface);
        }
        target.output.close();
      } catch (RuntimeException ignored) {
      }
    }
    outputs.clear();

    for (InputTarget input : inputs.values()) {
      input.texture.setOnFrameAvailableListener(null);
      input.texture.release();
      input.surface.release();
      if (glInitialized && input.textureId != -1) {
        makeCurrent(tempSurface);
        GLES20.glDeleteTextures(1, new int[] {input.textureId}, 0);
      }
    }
    inputs.clear();
    activeInput = null;

    if (pendingOverlayBitmap != null) {
      pendingOverlayBitmap.recycle();
      pendingOverlayBitmap = null;
    }

    if (glInitialized) {
      makeCurrent(tempSurface);
      if (program != -1) GLES20.glDeleteProgram(program);
      if (overlayTextureId != -1) {
        GLES20.glDeleteTextures(1, new int[] {overlayTextureId}, 0);
      }
      EGL14.eglMakeCurrent(
          eglDisplay,
          EGL14.EGL_NO_SURFACE,
          EGL14.EGL_NO_SURFACE,
          EGL14.EGL_NO_CONTEXT);
      if (tempSurface != EGL14.EGL_NO_SURFACE) {
        EGL14.eglDestroySurface(eglDisplay, tempSurface);
      }
      if (eglContext != EGL14.EGL_NO_CONTEXT) {
        EGL14.eglDestroyContext(eglDisplay, eglContext);
      }
      EGL14.eglTerminate(eglDisplay);
    }
    glInitialized = false;
    overlayDecodeThread.quitSafely();
    glThread.quitSafely();
  }

  private static void checkGl(String operation) {
    int error = GLES20.glGetError();
    if (error != GLES20.GL_NO_ERROR) {
      throw new IllegalStateException(operation + " failed: 0x" + Integer.toHexString(error));
    }
  }

  private static void checkEgl(String operation) {
    int error = EGL14.eglGetError();
    if (error != EGL14.EGL_SUCCESS) {
      throw new IllegalStateException(operation + " failed: 0x" + Integer.toHexString(error));
    }
  }

  private static final class InputTarget {
    final SurfaceRequest request;
    final SurfaceTexture texture;
    final Surface surface;
    final int textureId;
    final long serial;
    boolean invalidated;

    InputTarget(
        @NonNull SurfaceRequest request,
        @NonNull SurfaceTexture texture,
        @NonNull Surface surface,
        int textureId,
        long serial) {
      this.request = request;
      this.texture = texture;
      this.surface = surface;
      this.textureId = textureId;
      this.serial = serial;
    }
  }

  private static final class OutputTarget {
    final SurfaceOutput output;
    final Surface surface;
    final EGLSurface eglSurface;
    final Size size;

    OutputTarget(
        @NonNull SurfaceOutput output,
        @NonNull Surface surface,
        @NonNull EGLSurface eglSurface,
        @NonNull Size size) {
      this.output = output;
      this.surface = surface;
      this.eglSurface = eglSurface;
      this.size = size;
    }
  }
}
