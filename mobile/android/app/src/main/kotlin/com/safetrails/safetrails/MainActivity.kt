package com.safetrails.safetrails

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var peripheral: SafetrailsPeripheral? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val p = SafetrailsPeripheral(this)
        peripheral = p

        EventChannel(messenger, "safetrails/peripheral/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(messenger, "safetrails/peripheral").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "noop" -> result.success(true)
                    "start" -> {
                        val name = call.argument<String>("name") ?: "SAFETRAILS_RELAY"
                        val started = p.start(host, name)
                        result.success(started)
                    }
                    "stop" -> {
                        p.stop()
                        result.success(true)
                    }
                    "notify" -> {
                        val key = call.argument<String>("char") ?: ""
                        val data = call.argument<String>("data") ?: ""
                        result.success(p.notify(key, data))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("peripheral", e.message, null)
            }
        }
    }

    private val host = object : SafetrailsPeripheral.Host {
        override fun onEvent(name: String, payload: Map<String, Any?>) {
            if (name == "advertisingStopped" && payload["code"] == "permission") {
                // Runtime permission missing (Android 12+): ask for it directly
                // so the phone can still relay for peers even if the Dart-side
                // permission flow never surfaced it.
                runOnUiThread {
                    ActivityCompat.requestPermissions(
                        this@MainActivity,
                        arrayOf(Manifest.permission.BLUETOOTH_ADVERTISE),
                        0x5A1
                    )
                }
                return
            }
            runOnUiThread {
                eventSink?.success(mapOf("evt" to name).plus(payload))
            }
        }
    }

    override fun onDestroy() {
        peripheral?.stop()
        super.onDestroy()
    }
}