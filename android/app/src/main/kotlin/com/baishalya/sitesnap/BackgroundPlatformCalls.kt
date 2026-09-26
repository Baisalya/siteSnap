package com.baishalya.surveycam

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Engine-scoped disk/Binder work. Closing never waits for a slow provider. */
internal class BackgroundPlatformCalls(
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "SurveyCam-PlatformIO")
    },
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    // Accessed only on the main thread, including delivery and close().
    private var closed = false

    fun submit(result: MethodChannel.Result, read: () -> Any?) {
        if (closed) return
        worker.execute {
            val outcome = runCatching(read)
            mainHandler.post {
                if (!closed) {
                    outcome.fold(
                        onSuccess = result::success,
                        onFailure = { result.error("local_environment_error", it.message, null) },
                    )
                }
            }
        }
    }

    fun close() {
        closed = true
        worker.shutdownNow()
        mainHandler.removeCallbacksAndMessages(null)
    }
}
