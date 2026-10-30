package com.example.alexandria

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.OpenableColumns
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * Receives PDF / EPUB / DOCX files from other apps ("Open with" and "Share")
 * and hands them to Flutter as local file paths.
 *
 * Extends audio_service's activity so playback (and its notification
 * controls) keeps running in the same engine when the app is in the background.
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var initial: List<Map<String, String>> = emptyList()
    private var readAloudLock: PowerManager.WakeLock? = null
    private var volumeKeys: MethodChannel? = null
    private var pagingWithVolume = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initial = extract(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alexandria/podcasts").setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    if (call.argument<Boolean>("enabled") == true) askForNotifications()
                    PodcastChecker.schedule(applicationContext, call.argument<Boolean>("enabled") == true, call.argument<Int>("hours") ?: 6)
                    result.success(null)
                }
                "checkNow" -> thread {
                    val found = try {
                        PodcastChecker.check(applicationContext)
                    } catch (e: Exception) {
                        -1
                    }
                    runOnUiThread { result.success(found) }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alexandria/power").setMethodCallHandler { call, result ->
            when (call.method) {
                "hold" -> {
                    if (readAloudLock == null) {
                        readAloudLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "alexandria:readaloud")
                    }
                    readAloudLock?.let { if (!it.isHeld) it.acquire(8 * 60 * 60 * 1000L) }
                    result.success(null)
                }
                "release" -> {
                    readAloudLock?.let { if (it.isHeld) it.release() }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        volumeKeys = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alexandria/volumekeys").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "capture" -> {
                        pagingWithVolume = call.arguments as Boolean
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        val widgets = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alexandria/widgets")
        WidgetBridge.onChanged = { runOnUiThread { widgets.invokeMethod("changed", null) } }
        widgets.setMethodCallHandler { call, result ->
            when (call.method) {
                "sizes" -> result.success(WidgetBridge.sizes(applicationContext))
                "refresh" -> {
                    WidgetBridge.refresh(applicationContext, call.argument<String>("kind") ?: "all")
                    result.success(null)
                }
                "pin" -> result.success(WidgetBridge.pin(applicationContext, call.argument<String>("kind") ?: "all"))
                else -> result.notImplemented()
            }
        }
        val downloads = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alexandria/downloads")
        DownloadService.onCancel = { runOnUiThread { downloads.invokeMethod("cancelAll", null) } }
        downloads.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    askForNotifications()
                    try {
                        DownloadService.update(applicationContext, call.argument<String>("title") ?: "", call.argument<String>("text") ?: "", call.argument<Int>("percent") ?: -1)
                    } catch (e: Exception) {
                        // Not allowed to start from the background: the download still runs while the app lives.
                    }
                    result.success(null)
                }
                "stop" -> {
                    DownloadService.stop(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alexandria/intent").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialFiles" -> {
                        result.success(initial)
                        initial = emptyList()
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** While reading, the volume buttons turn pages: one per press, and the volume stays put. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val dir = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> 1
            KeyEvent.KEYCODE_VOLUME_UP -> -1
            else -> 0
        }
        if (dir == 0 || !pagingWithVolume) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) volumeKeys?.invokeMethod("turn", dir)
        return true
    }

    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED && !isFinishing) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val files = extract(intent)
        if (files.isNotEmpty()) channel?.invokeMethod("files", files)
    }

    private fun extract(intent: Intent?): List<Map<String, String>> {
        if (intent == null) return emptyList()
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            Intent.ACTION_SEND -> streamExtra(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamListExtra(intent))
        }
        return uris.mapNotNull { copyToCache(it) }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0) c.getString(i)?.let { return it }
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "document"
    }

    private fun withExtension(name: String, uri: Uri): String {
        val lower = name.lowercase()
        if (lower.endsWith(".pdf") || lower.endsWith(".epub") || lower.endsWith(".docx")) return name
        val ext = when (contentResolver.getType(uri)) {
            "application/pdf" -> ".pdf"
            "application/epub+zip" -> ".epub"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> ".docx"
            else -> ""
        }
        return name + ext
    }

    private fun copyToCache(uri: Uri): Map<String, String>? = try {
        val name = withExtension(displayName(uri), uri).replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val dir = File(cacheDir, "incoming").apply { mkdirs() }
        val out = File(dir, "${System.currentTimeMillis()}_$name")
        contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
        if (out.exists() && out.length() > 0) mapOf("path" to out.absolutePath, "name" to name) else null
    } catch (e: Exception) {
        null
    }
}
