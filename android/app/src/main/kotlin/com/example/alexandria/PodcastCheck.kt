package com.example.alexandria

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Xml
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

/** Android runs this every few hours, whether or not the app is open. */
class PodcastCheckService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        thread {
            try {
                PodcastChecker.check(applicationContext)
            } catch (e: Exception) {
                // A bad night's network: the next run tries again.
            }
            jobFinished(params, false)
        }
        return true
    }

    override fun onStopJob(params: JobParameters) = true
}

/**
 * Looks for new episodes without starting Flutter. The app writes the shows to
 * check, and the newest episode it knows of for each, to files/podcast_check.json.
 */
object PodcastChecker {
    private const val JOB_ID = 4108
    private const val CHANNEL = "alexandria.episodes"
    private const val MAX_ITEMS = 300

    fun schedule(context: Context, enabled: Boolean, hours: Int) {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (!enabled) {
            scheduler.cancel(JOB_ID)
            return
        }
        val period = hours.coerceAtLeast(1) * 60 * 60 * 1000L
        val pending = scheduler.getPendingJob(JOB_ID)
        if (pending != null && pending.intervalMillis == period) return
        val job = JobInfo.Builder(JOB_ID, ComponentName(context, PodcastCheckService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true)
            .setPeriodic(period)
            .build()
        scheduler.schedule(job)
    }

    /** Checks every show and notifies; returns how many new episodes it found. */
    fun check(context: Context): Int {
        val file = File(context.filesDir, "podcast_check.json")
        if (!file.exists()) return 0
        val shows = JSONObject(file.readText()).optJSONArray("shows") ?: return 0
        val prefs = context.getSharedPreferences("podcast_check", Context.MODE_PRIVATE)
        var found = 0
        for (n in 0 until shows.length()) {
            val show = shows.getJSONObject(n)
            val feed = show.getString("feed")
            try {
                // Newest known: what the app has seen, or what an earlier check told you about.
                val known = maxOf(show.optLong("latestMs"), prefs.getLong(feed, 0))
                val fresh = readNewer(feed, known)
                if (fresh.isEmpty()) continue
                prefs.edit().putLong(feed, fresh.maxOf { it.second }).apply()
                // Nothing known yet means this is a first look, not news.
                if (known == 0L) continue
                found += fresh.size
                notify(context, feed, show.optString("title"), fresh)
            } catch (e: Exception) {
                // One broken feed shouldn't stop the others.
            }
        }
        return found
    }

    private val dateFormats = listOf("EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss z", "d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss z", "EEE, d MMM yyyy HH:mm Z")

    fun parseDate(s: String): Long {
        for (f in dateFormats) {
            try {
                return SimpleDateFormat(f, Locale.US).parse(s.trim())?.time ?: continue
            } catch (e: Exception) {
                // Try the next format.
            }
        }
        return 0
    }

    private fun open(url: String): HttpURLConnection {
        var address = url
        repeat(4) {
            val c = URL(address).openConnection() as HttpURLConnection
            c.connectTimeout = 20000
            c.readTimeout = 30000
            c.instanceFollowRedirects = false
            c.setRequestProperty("User-Agent", "Alexandria-Reader/1.0 (podcast player)")
            val code = c.responseCode
            if (code !in 300..399) return c
            address = URL(URL(address), c.getHeaderField("Location")).toString()
            c.disconnect()
        }
        throw IllegalStateException("too many redirects")
    }

    /** Episodes (title, date) newer than [known]. */
    private fun readNewer(feed: String, known: Long): List<Pair<String, Long>> {
        val conn = open(feed)
        val out = mutableListOf<Pair<String, Long>>()
        try {
            if (conn.responseCode != 200) return out
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(conn.inputStream, null)
            var inItem = false
            var title = ""
            var date = 0L
            var items = 0
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT && items < MAX_ITEMS) {
                if (event == XmlPullParser.START_TAG) {
                    when (parser.name) {
                        "item" -> {
                            inItem = true
                            title = ""
                            date = 0
                        }
                        "title" -> if (inItem && title.isEmpty()) title = parser.nextText()
                        "pubDate" -> if (inItem) date = parseDate(parser.nextText())
                    }
                } else if (event == XmlPullParser.END_TAG && parser.name == "item") {
                    inItem = false
                    items++
                    if (date > known) out.add(title to date)
                }
                event = parser.next()
            }
        } finally {
            conn.disconnect()
        }
        // Ignore dates in the future: some feeds schedule ahead.
        val now = Date().time + 86400000L
        return out.filter { it.second <= now }
    }

    private fun notify(context: Context, feed: String, show: String, fresh: List<Pair<String, Long>>) {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "New episodes", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, feed.hashCode(), it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val newest = fresh.maxByOrNull { it.second }!!
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        manager.notify(
            feed.hashCode(),
            builder
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(if (fresh.size == 1) show else "$show: ${fresh.size} new episodes")
                .setContentText(newest.first)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
    }
}
