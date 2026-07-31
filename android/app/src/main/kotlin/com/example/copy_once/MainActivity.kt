package com.example.copy_once

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceName" -> result.success(resolveDeviceName())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The name this phone shows to the user, so synced items are labelled the
     * way they expect.
     *
     * Prefers the name set under Settings → About phone → Device name, which is
     * what the owner actually recognises ("Galaxy A34"). Falls back to the
     * manufacturer and model, which is at least specific.
     *
     * Dart cannot get this: Platform.localHostname returns "localhost" on
     * Android, and there is no plugin-free way to read the setting.
     */
    private fun resolveDeviceName(): String {
        // Read by key rather than Settings.Global.DEVICE_NAME, which only exists
        // from API 25.
        val userSetName = try {
            Settings.Global.getString(contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        if (!userSetName.isNullOrBlank()) return userSetName.trim()

        val manufacturer = Build.MANUFACTURER.orEmpty().trim()
        val model = Build.MODEL.orEmpty().trim()

        // Some models already include the brand; do not say "Samsung Samsung".
        val combined = if (model.startsWith(manufacturer, ignoreCase = true)) {
            model
        } else {
            listOf(manufacturer, model).filter { it.isNotBlank() }.joinToString(" ")
        }

        return combined.ifBlank { "Android device" }
            .replaceFirstChar { it.uppercase() }
    }

    private companion object {
        const val CHANNEL = "copyonce/device"
    }
}
