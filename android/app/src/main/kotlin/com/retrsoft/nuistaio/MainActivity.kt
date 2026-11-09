package com.retrsoft.nuistaio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nuistaio/sso_diagnostics")
            .setMethodCallHandler { call, result ->
                // Only the diagnostic Dart build invokes this private channel.
                // Accept the fixed metadata schema, never arbitrary payloads.
                val file = File(getExternalFilesDir(null), "sso-diagnostics.jsonl")
                when (call.method) {
                    "reset" -> {
                        runCatching { file.writeText("") }
                        result.success(null)
                    }
                    "append" -> {
                        runCatching {
                            val raw = call.arguments as? String ?: return@runCatching
                            val source = JSONObject(raw)
                            val output = JSONObject()
                            for (key in listOf("site", "event", "location", "task", "type", "ok", "ready", "status", "mainFrame")) {
                                if (source.has(key)) output.put(key, source.get(key))
                            }
                            if (file.length() > 262144) file.writeText("")
                            file.appendText(output.toString() + "\n")
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
