package com.retrsoft.nuistaio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import android.content.Intent
import android.net.Uri
import android.webkit.CookieManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {
    private var pendingUpdate: File? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        savedInstanceState?.getString("pendingUpdate")?.let { path ->
            val file = File(path).canonicalFile
            if (file.parentFile == File(cacheDir, "updates").canonicalFile && file.isFile && file.extension == "apk") {
                pendingUpdate = file
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        pendingUpdate?.let { outState.putString("pendingUpdate", it.path) }
        super.onSaveInstanceState(outState)
    }

    private fun openInstaller(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }

    override fun onResume() {
        super.onResume()
        val file = pendingUpdate ?: return
        pendingUpdate = null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()) {
            runCatching { openInstaller(file) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nuistaio/updates")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") { result.notImplemented(); return@setMethodCallHandler }
                runCatching {
                    val file = File(call.arguments as? String ?: "").canonicalFile
                    val root = File(cacheDir, "updates").canonicalFile
                    require(file.parentFile == root && file.isFile && file.extension == "apk")
                    val archive = packageManager.getPackageArchiveInfo(file.path, 0)
                    require(archive?.packageName == packageName)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        pendingUpdate = file
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        "permissionRequired"
                    } else {
                        openInstaller(file)
                        "requested"
                    }
                }.onSuccess { result.success(it) }
                    .onFailure { pendingUpdate = null; result.error("update_install", "无法请求安装，请检查安装包和系统权限。", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nuistaio/chaoxing")
            .setMethodCallHandler { call, result ->
                if (call.method == "hasCourseCookies") {
                    result.success(!CookieManager.getInstance()
                        .getCookie("https://mooc1-api.chaoxing.com/mycourse/backclazzdata")
                        .isNullOrEmpty())
                    return@setMethodCallHandler
                }
                if (call.method == "flushCookies") {
                    runCatching { CookieManager.getInstance().flush() }
                        .onSuccess { result.success(null) }
                        .onFailure { result.error("cookie_store", "Cookie store unavailable", null) }
                    return@setMethodCallHandler
                }
                if (call.method != "openItem") { result.notImplemented(); return@setMethodCallHandler }
                val opened = runCatching {
                    val uri = Uri.parse(call.arguments as? String ?: "")
                    require(uri.scheme == "https" && uri.host in setOf("mooc1.chaoxing.com", "mooc1-api.chaoxing.com", "mooc2-ans.chaoxing.com") && uri.userInfo == null && (uri.port == -1 || uri.port == 443))
                    startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.chaoxing.mobile"))
                    true
                }.getOrDefault(false)
                result.success(opened)
            }
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
