package com.lingora.lingora

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The API level, so Android 7–9 get emoji they can draw (lib/core/legacy_emoji.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dilmac/device").setMethodCallHandler { call, result ->
            if (call.method == "sdkInt") result.success(Build.VERSION.SDK_INT) else result.notImplemented()
        }
    }
}
