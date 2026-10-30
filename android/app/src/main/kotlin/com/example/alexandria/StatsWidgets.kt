package com.example.alexandria

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.io.File

/**
 * Home-screen stats. Flutter paints each widget to a PNG (so any font and colour
 * work); these just show the latest image and open the app when tapped.
 */
abstract class StatsWidget(private val kind: String) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { WidgetBridge.draw(context, manager, it, kind) }
        WidgetBridge.onChanged?.invoke()
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        WidgetBridge.draw(context, manager, id, kind)
        // Resized: have Flutter repaint at the new shape.
        WidgetBridge.onChanged?.invoke()
    }
}

class BooksStatsWidget : StatsWidget("books")
class AudioStatsWidget : StatsWidget("audio")
class PodcastsStatsWidget : StatsWidget("podcasts")
class AllStatsWidget : StatsWidget("all")

object WidgetBridge {
    /** Set while Flutter is running, so it can redraw when a widget is added or resized. */
    var onChanged: (() -> Unit)? = null

    private val providers = mapOf(
        "books" to BooksStatsWidget::class.java,
        "audio" to AudioStatsWidget::class.java,
        "podcasts" to PodcastsStatsWidget::class.java,
        "all" to AllStatsWidget::class.java,
    )

    private fun component(context: Context, kind: String) = ComponentName(context, providers.getValue(kind))

    fun draw(context: Context, manager: AppWidgetManager, id: Int, kind: String) {
        val views = RemoteViews(context.packageName, R.layout.stats_widget)
        val file = File(context.filesDir, "widgets/$kind.png")
        val bitmap = if (file.exists()) BitmapFactory.decodeFile(file.path) else null
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.widget_image, bitmap)
            views.setViewVisibility(R.id.widget_image, View.VISIBLE)
            views.setViewVisibility(R.id.widget_hint, View.GONE)
        }
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            val open = PendingIntent.getActivity(context, kind.hashCode(), it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, open)
        }
        manager.updateAppWidget(id, views)
    }

    /** Shows the newest image on every widget of [kind]. */
    fun refresh(context: Context, kind: String) {
        val manager = AppWidgetManager.getInstance(context)
        manager.getAppWidgetIds(component(context, kind)).forEach { draw(context, manager, it, kind) }
    }

    /** Placed widgets by kind, with the size to paint in dp. */
    fun sizes(context: Context): Map<String, List<Int>> {
        val manager = AppWidgetManager.getInstance(context)
        val out = mutableMapOf<String, List<Int>>()
        for (kind in providers.keys) {
            val id = manager.getAppWidgetIds(component(context, kind)).firstOrNull() ?: continue
            val o = manager.getAppWidgetOptions(id)
            out[kind] = listOf(o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH), o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT))
        }
        return out
    }

    /** Asks the launcher to add a widget; false if it doesn't support that. */
    fun pin(context: Context, kind: String): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        val manager = AppWidgetManager.getInstance(context)
        if (!manager.isRequestPinAppWidgetSupported) return false
        return manager.requestPinAppWidget(component(context, kind), null, null)
    }
}
