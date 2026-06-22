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
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localEnvironmentChannel = "surveycam/local_environment"
    private val sensorReadTimeoutMs = 1200L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            localEnvironmentChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSensorAvailability" -> result.success(getSensorAvailability())
                "readEnvironment" -> readEnvironmentSensors(result)
                "listSurveyCamMedia" -> result.success(listSurveyCamMedia())
                "getLastAppExitInfo" -> result.success(getLastAppExitInfo())
                else -> result.notImplemented()
            }
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
        var finished = false

        fun finish() {
            if (finished) return
            finished = true
            listeners.values.forEach { sensorManager.unregisterListener(it) }
            listeners.clear()
            result.success(readings)
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
            }
        }

        if (listeners.isEmpty()) {
            finish()
            return
        }

        Handler(Looper.getMainLooper()).postDelayed({ finish() }, sensorReadTimeoutMs)
    }
}
