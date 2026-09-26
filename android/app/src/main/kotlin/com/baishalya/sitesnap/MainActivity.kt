package com.baishalya.surveycam

import android.app.ActivityManager
import android.content.Context
import android.database.Cursor
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import io.flutter.plugins.camerax.SiteSnapRealtimeOverlayController

class MainActivity : FlutterActivity() {
    private val localEnvironmentChannel = "surveycam/local_environment"
    private val realtimeOverlayChannelName = "surveycam/realtime_video_overlay"
    private val sensorReadTimeoutMs = 1200L
    private val sensorHandler = Handler(Looper.getMainLooper())
    private val activeSensorListeners = mutableSetOf<SensorEventListener>()
    private var engineGeneration = 0
    private var engineAttached = false
    private var methodChannel: MethodChannel? = null
    private var realtimeOverlayChannel: MethodChannel? = null
    private var backgroundCalls: BackgroundPlatformCalls? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineAttached = true
        engineGeneration++
        backgroundCalls?.close()
        val ioCalls = BackgroundPlatformCalls()
        backgroundCalls = ioCalls
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            localEnvironmentChannel
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSensorAvailability" -> result.success(getSensorAvailability())
                    "readEnvironment" -> readEnvironmentSensors(result)
                    "listSurveyCamMedia" -> ioCalls.submit(result) { listSurveyCamMedia() }
                    "getLastAppExitInfo" -> ioCalls.submit(result) { getLastAppExitInfo() }
                    "getUsableStorageBytes" -> ioCalls.submit(result) { getUsableStorageBytes() }
                    else -> result.notImplemented()
                }
            }
        }

        realtimeOverlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            realtimeOverlayChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                        "arm" -> {
                            SiteSnapRealtimeOverlayController.arm()
                            result.success(true)
                        }
                        "disarm" -> {
                            SiteSnapRealtimeOverlayController.disarm()
                            result.success(null)
                        }
                        "beginHandshake" -> {
                            val captureOrientation =
                                call.argument<String>("captureOrientation")
                            result.success(
                                SiteSnapRealtimeOverlayController.beginHandshake(
                                    captureOrientation
                                )
                            )
                        }
                        "cancelHandshake" -> {
                            SiteSnapRealtimeOverlayController.cancelHandshake()
                            result.success(null)
                        }
                        "releaseHandshakePrebind" -> {
                            SiteSnapRealtimeOverlayController.releaseHandshakePrebindForFallback()
                            result.success(null)
                        }
                        "markRecordingStarted" -> {
                            SiteSnapRealtimeOverlayController.markRecordingStarted()
                            result.success(null)
                        }
                        "getFrameGeometry" ->
                            result.success(SiteSnapRealtimeOverlayController.frameGeometryMap())
                        "getStatus" ->
                            result.success(SiteSnapRealtimeOverlayController.statusMap())
                        "setFrontVideoMirroring" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            result.success(
                                SiteSnapRealtimeOverlayController.setFrontVideoMirroring(enabled)
                            )
                        }
                        "getCaptureTransformStatus" ->
                            result.success(
                                SiteSnapRealtimeOverlayController.captureTransformStatusMap()
                            )
                        "setOverlayPng" -> {
                            val bytes = call.argument<ByteArray>("bytes")
                            val orientation = call.argument<String>("orientation")
                            result.success(
                                SiteSnapRealtimeOverlayController.setOverlayPng(
                                    bytes,
                                    orientation
                                )
                            )
                        }
                        "setEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            SiteSnapRealtimeOverlayController.setEnabled(enabled)
                            result.success(SiteSnapRealtimeOverlayController.isEnabled())
                        }
                        "setDynamicOrientation" -> {
                            val orientation = call.argument<String>("orientation")
                            result.success(
                                SiteSnapRealtimeOverlayController.setDynamicCaptureOrientation(
                                    orientation
                                )
                            )
                        }
                        "clear" -> {
                            SiteSnapRealtimeOverlayController.clearOverlay()
                            result.success(null)
                        }
                        "consumeLastError" ->
                            result.success(SiteSnapRealtimeOverlayController.consumeLastError())
                        else -> result.notImplemented()
                    }
                } catch (error: RuntimeException) {
                    result.error(
                        "realtime_overlay_error",
                        error.message ?: "Realtime CameraX overlay failed",
                        null,
                    )
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Flutter engine issue #188300: ImageReader-backed SurfaceProducers can
        // deliver one final frame after FlutterEngine.destroy() detaches JNI.
        // Release them while JNI is still attached so their queued callbacks
        // observe released=true and close the image without scheduling a frame.
        releaseFlutterSurfaceProducers(flutterEngine)

        // Sensor reads complete asynchronously. Do not let their delayed result
        // reply through a BinaryMessenger after FlutterJNI has detached.
        engineAttached = false
        engineGeneration++
        backgroundCalls?.close()
        backgroundCalls = null
        sensorHandler.removeCallbacksAndMessages(null)

        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        activeSensorListeners.forEach(sensorManager::unregisterListener)
        activeSensorListeners.clear()

        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        realtimeOverlayChannel?.setMethodCallHandler(null)
        realtimeOverlayChannel = null
        SiteSnapRealtimeOverlayController.reset()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun releaseFlutterSurfaceProducers(flutterEngine: FlutterEngine) {
        try {
            val renderer = flutterEngine.renderer
            val producersField = renderer.javaClass.getDeclaredField("imageReaderProducers")
            producersField.isAccessible = true
            val producers = (producersField.get(renderer) as? Collection<*>)
                ?.filterIsInstance<TextureRegistry.SurfaceProducer>()
                ?.toList()
                .orEmpty()

            producers.forEach { producer ->
                try {
                    producer.release()
                } catch (error: RuntimeException) {
                    Log.w(
                        "SurveyCam",
                        "Unable to release a Flutter surface producer during teardown",
                        error,
                    )
                }
            }

            if (producers.isNotEmpty()) {
                Log.i(
                    "SurveyCam",
                    "Released ${producers.size} Flutter surface producer(s) before engine teardown",
                )
            }
        } catch (error: ReflectiveOperationException) {
            // Keep teardown safe if a future Flutter version changes the private
            // renderer field. Remove this workaround once the engine fix ships.
            Log.w(
                "SurveyCam",
                "Flutter surface producer teardown workaround was unavailable",
                error,
            )
        }
    }


    private fun getUsableStorageBytes(): Long? {
        return try {
            StatFs(filesDir.absolutePath).availableBytes
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun getLastAppExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null

        return try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val exitInfo = activityManager
                .getHistoricalProcessExitReasons(packageName, 0, 1)
                .firstOrNull()
                ?: return null

            mapOf(
                "reason" to exitInfo.reason,
                "reasonName" to appExitReasonName(exitInfo.reason),
                "timestampMs" to exitInfo.timestamp,
                "importance" to exitInfo.importance,
                "description" to (exitInfo.description ?: ""),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun appExitReasonName(reason: Int): String {
        return when (reason) {
            1 -> "exit_self"
            2 -> "signaled"
            3 -> "low_memory"
            4 -> "crash"
            5 -> "crash_native"
            6 -> "anr"
            7 -> "initialization_failure"
            8 -> "permission_change"
            9 -> "excessive_resource_usage"
            10 -> "user_requested"
            11 -> "user_stopped"
            12 -> "dependency_died"
            13 -> "other"
            14 -> "freezer"
            else -> "unknown"
        }
    }

    private fun listSurveyCamMedia(): List<Map<String, Any>> {
        return try {
            val media = mutableListOf<Map<String, Any>>()
            media.addAll(querySurveyCamMedia(MediaStore.Images.Media.EXTERNAL_CONTENT_URI))
            media.addAll(querySurveyCamMedia(MediaStore.Video.Media.EXTERNAL_CONTENT_URI))
            media.sortedByDescending { it["modifiedMs"] as? Long ?: 0L }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun querySurveyCamMedia(uri: Uri): List<Map<String, Any>> {
        val projection = mutableListOf(
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        val selection: String
        val selectionArgs: Array<String>

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
            selection = "LOWER(${MediaStore.MediaColumns.DISPLAY_NAME}) LIKE ? OR " +
                "LOWER(${MediaStore.MediaColumns.RELATIVE_PATH}) LIKE ?"
            selectionArgs = arrayOf("%surveycam%", "%surveycam%")
        } else {
            selection = "LOWER(${MediaStore.MediaColumns.DISPLAY_NAME}) LIKE ? OR " +
                "LOWER(${MediaStore.MediaColumns.DATA}) LIKE ?"
            selectionArgs = arrayOf("%surveycam%", "%surveycam%")
        }

        val sortOrder = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
        val rows = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            uri,
            projection.toTypedArray(),
            selection,
            selectionArgs,
            sortOrder,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val path = cursor.stringOrNull(MediaStore.MediaColumns.DATA)
                if (path.isNullOrBlank()) continue

                val modifiedSeconds =
                    cursor.longOrNull(MediaStore.MediaColumns.DATE_MODIFIED)
                        ?: cursor.longOrNull(MediaStore.MediaColumns.DATE_ADDED)
                        ?: 0L
                rows.add(
                    mapOf(
                        "path" to path,
                        "name" to (cursor.stringOrNull(MediaStore.MediaColumns.DISPLAY_NAME) ?: ""),
                        "mimeType" to (cursor.stringOrNull(MediaStore.MediaColumns.MIME_TYPE) ?: ""),
                        "size" to (cursor.longOrNull(MediaStore.MediaColumns.SIZE) ?: 0L),
                        "modifiedMs" to modifiedSeconds * 1000L,
                    )
                )
            }
        }
        return rows
    }

    private fun Cursor.stringOrNull(columnName: String): String? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getString(index) else null
    }

    private fun Cursor.longOrNull(columnName: String): Long? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getLong(index) else null
    }

    private fun getSensorAvailability(): Map<String, Boolean> {
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        return mapOf(
            "temperature" to (sensorManager.getDefaultSensor(Sensor.TYPE_AMBIENT_TEMPERATURE) != null),
            "humidity" to (sensorManager.getDefaultSensor(Sensor.TYPE_RELATIVE_HUMIDITY) != null),
            "pressure" to (sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE) != null),
            "airQuality" to false,
        )
    }

    private fun readEnvironmentSensors(result: MethodChannel.Result) {
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val readings = mutableMapOf<String, Double>()
        val listeners = mutableMapOf<Sensor, SensorEventListener>()
        val generation = engineGeneration
        var finished = false

        fun finish() {
            if (finished) return
            finished = true
            listeners.values.forEach {
                sensorManager.unregisterListener(it)
                activeSensorListeners.remove(it)
            }
            listeners.clear()
            if (engineAttached && generation == engineGeneration) {
                result.success(readings)
            }
        }

        val sensorRequests = listOf(
            "pressureHpa" to Sensor.TYPE_PRESSURE,
            "humidityPercent" to Sensor.TYPE_RELATIVE_HUMIDITY,
            "temperatureCelsius" to Sensor.TYPE_AMBIENT_TEMPERATURE,
        )

        for ((key, sensorType) in sensorRequests) {
            val sensor = sensorManager.getDefaultSensor(sensorType) ?: continue
            val listener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    if (finished || event.values.isEmpty()) return
                    readings[key] = event.values[0].toDouble()
                    sensorManager.unregisterListener(this)
                    activeSensorListeners.remove(this)
                    listeners.remove(sensor)
                    if (listeners.isEmpty()) finish()
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
            }

            if (sensorManager.registerListener(
                    listener,
                    sensor,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
            ) {
                listeners[sensor] = listener
                activeSensorListeners.add(listener)
            }
        }

        if (listeners.isEmpty()) {
            finish()
            return
        }

        sensorHandler.postDelayed({ finish() }, sensorReadTimeoutMs)
    }
}
