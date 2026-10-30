package com.example.alexandria

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app's process (and so the Dart code doing the transfer) alive while
 * downloads run, and shows their progress. The downloading itself stays in Dart.
 */
class DownloadService : Service() {
    companion object {
        private const val CHANNEL = "alexandria.downloads"
        private const val ID = 4107
        private const val ACTION_CANCEL = "alexandria.downloads.CANCEL"

        /** Tells Dart the notification's Cancel button was pressed. */
        var onCancel: (() -> Unit)? = null

        private var running: DownloadService? = null

        fun update(context: Context, title: String, text: String, percent: Int) {
            val service = running
            if (service != null) {
                // Starting a foreground service from the background is forbidden on
                // Android 12+, so once it runs only its notification is updated.
                service.show(title, text, percent)
                return
            }
            val intent = Intent(context, DownloadService::class.java)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("percent", percent)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Audiobook and podcast downloads"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        // Keeps transfers going with the screen off; the timeout is a safety net.
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "alexandria:downloads")
            .apply { acquire(6 * 60 * 60 * 1000L) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            onCancel?.invoke()
            return START_NOT_STICKY
        }
        val notification = build(
            intent?.getStringExtra("title") ?: "Downloading",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("percent", -1) ?: -1,
        )
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        return START_NOT_STICKY
    }

    fun show(title: String, text: String, percent: Int) {
        getSystemService(NotificationManager::class.java).notify(ID, build(title, text, percent))
    }

    private fun build(title: String, text: String, percent: Int): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val cancel = PendingIntent.getService(this, 1, Intent(this, DownloadService::class.java).setAction(ACTION_CANCEL), flags)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let { PendingIntent.getActivity(this, 2, it, flags) }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent.coerceAtLeast(0), percent < 0)
            .addAction(Notification.Action.Builder(null, "Cancel", cancel).build())
            .build()
    }

    override fun onDestroy() {
        running = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
