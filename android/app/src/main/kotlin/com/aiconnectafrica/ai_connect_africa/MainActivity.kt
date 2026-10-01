package com.aiconnectafrica.ai_connect_africa

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

/**
 * Streams large model files out of the APK's [assets] folder into app
 * storage. Flutter's rootBundle.load would hold the whole ~0.5–1 GB file in
 * the Dart heap; AssetManager streaming stays O(buffer) in RAM.
 *
 * Asset keys differ by how the file was packaged:
 *   - Gradle `src/main/assets/models/…` → `models/foo.gguf`
 *   - Flutter pubspec `assets/models/…` → `flutter_assets/assets/models/foo.gguf`
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ai_connect_africa/bundled_models"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Class sync: keep sharing alive in the background (ClassShareService).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_connect_africa/class_share")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            askForNotifications()
                            ClassShareService.start(this, call.argument<String>("text"))
                            result.success(true)
                        }
                        "stop" -> {
                            ClassShareService.stop(this)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // e.g. Android refusing a foreground start: sharing still
                    // works while the app stays on screen.
                    result.error("class_share_failed", e.message ?: e.toString(), null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasBundledAsset" -> {
                        val assetPath = call.argument<String>("assetPath")
                        if (assetPath.isNullOrBlank()) {
                            result.error("bad_args", "assetPath required", null)
                            return@setMethodCallHandler
                        }
                        result.success(resolveAsset(assetPath) != null)
                    }
                    "extractBundledAsset" -> {
                        val assetPath = call.argument<String>("assetPath")
                        val destPath = call.argument<String>("destPath")
                        if (assetPath.isNullOrBlank() || destPath.isNullOrBlank()) {
                            result.error(
                                "bad_args",
                                "assetPath and destPath required",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val channel = MethodChannel(
                            flutterEngine.dartExecutor.binaryMessenger,
                            channelName,
                        )
                        thread(name = "extract-$assetPath") {
                            try {
                                val resolved = resolveAsset(assetPath)
                                    ?: throw IllegalStateException(
                                        "Bundled asset not in APK: $assetPath",
                                    )
                                extractAsset(resolved, destPath) { progress ->
                                    runOnUiThread {
                                        channel.invokeMethod(
                                            "extractProgress",
                                            mapOf(
                                                "assetPath" to assetPath,
                                                "progress" to progress,
                                            ),
                                        )
                                    }
                                }
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "extract_failed",
                                        e.message ?: e.toString(),
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 13+: the sharing notification is hidden until the user allows
     * notifications. The service runs either way; this only asks once per
     * start, and Android stops asking after the user declines twice.
     */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4107)
        }
    }

    /** First APK asset key that actually opens, or null. */
    private fun resolveAsset(requested: String): String? {
        val trimmed = requested.trim().trimStart('/')
        val candidates = linkedSetOf(
            trimmed,
            if (trimmed.startsWith("assets/")) trimmed else "assets/$trimmed",
            "flutter_assets/$trimmed",
            "flutter_assets/assets/$trimmed",
        )
        for (key in candidates) {
            if (assetExists(key)) return key
        }
        return null
    }

    private fun assetExists(assetPath: String): Boolean {
        return try {
            assets.open(assetPath).use { true }
        } catch (_: Exception) {
            false
        }
    }

    private fun extractAsset(
        assetPath: String,
        destPath: String,
        onProgress: (Double) -> Unit,
    ) {
        val dest = File(destPath)
        dest.parentFile?.mkdirs()
        val partial = File("$destPath.part")
        if (partial.exists()) partial.delete()

        val total = try {
            assets.openFd(assetPath).use { it.length }
        } catch (_: Exception) {
            -1L
        }

        assets.open(assetPath).use { input ->
            FileOutputStream(partial).use { output ->
                val buffer = ByteArray(1024 * 256)
                var copied = 0L
                var lastReported = -1
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    copied += read
                    if (total > 0) {
                        val pct = ((copied * 100) / total).toInt().coerceIn(0, 100)
                        if (pct != lastReported) {
                            lastReported = pct
                            onProgress(pct / 100.0)
                        }
                    }
                }
                output.flush()
            }
        }

        if (dest.exists()) dest.delete()
        if (!partial.renameTo(dest)) {
            partial.copyTo(dest, overwrite = true)
            partial.delete()
        }
        onProgress(1.0)
    }
}
