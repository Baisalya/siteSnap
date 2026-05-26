package com.baishalya.surveycam

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
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
                else -> result.notImplemented()
            }
        }
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
