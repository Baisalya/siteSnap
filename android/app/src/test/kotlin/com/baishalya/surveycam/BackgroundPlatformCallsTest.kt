package com.baishalya.surveycam

import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.AbstractExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
// This worker uses Handler only; loading app resources would unnecessarily
// involve Flutter's generated assets and AndroidX/Ads startup providers.
@Config(sdk = [35], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class BackgroundPlatformCallsTest {
    private class Worker : AbstractExecutorService() {
        val tasks = mutableListOf<Runnable>()
        var stopped = false
        override fun execute(command: Runnable) { tasks.add(command) }
        override fun shutdown() { stopped = true }
        override fun shutdownNow(): MutableList<Runnable> {
            stopped = true
            return tasks.toMutableList().also { tasks.clear() }
        }
        override fun isShutdown() = stopped
        override fun isTerminated() = stopped
        override fun awaitTermination(timeout: Long, unit: TimeUnit) = stopped
        fun runNext() { tasks.removeAt(0).run() }
    }

    private class Reply : MethodChannel.Result {
        val values = mutableListOf<Any?>()
        var errorCode: String? = null
        override fun success(result: Any?) { values.add(result) }
        override fun error(code: String, message: String?, details: Any?) { errorCode = code }
        override fun notImplemented() { fail("Unexpected missing method") }
    }

    @Test fun diskReadIsQueuedAndReplyIsPostedToMain() {
        val worker = Worker()
        val calls = BackgroundPlatformCalls(worker)
        val reply = Reply()
        var reads = 0
        calls.submit(reply) { reads++; listOf("photo.jpg") }
        assertEquals(0, reads)
        worker.runNext()
        assertEquals(1, reads)
        assertTrue(reply.values.isEmpty())
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf(listOf("photo.jpg")), reply.values)
        calls.close()
    }

    @Test fun queuedReplyCannotReachDetachedEngine() {
        val worker = Worker()
        val calls = BackgroundPlatformCalls(worker)
        val reply = Reply()
        calls.submit(reply) { 123L }
        worker.runNext()
        calls.close()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(reply.values.isEmpty())
        assertTrue(worker.stopped)
    }

    @Test fun inFlightReadFinishingAfterDetachCannotReply() {
        val worker = Worker()
        val calls = BackgroundPlatformCalls(worker)
        val reply = Reply()
        calls.submit(reply) { 123L }
        val runningTask = worker.tasks.removeAt(0)
        calls.close()
        runningTask.run()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(reply.values.isEmpty())
    }

    @Test fun failuresReplyAsErrorsAndWorkerRemainsUsable() {
        val worker = Worker()
        val calls = BackgroundPlatformCalls(worker)
        val failed = Reply()
        val success = Reply()
        calls.submit(failed) { throw IllegalStateException("provider unavailable") }
        calls.submit(success) { 42L }
        worker.runNext()
        worker.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("local_environment_error", failed.errorCode)
        assertEquals(listOf(42L), success.values)
        calls.close()
    }
}
