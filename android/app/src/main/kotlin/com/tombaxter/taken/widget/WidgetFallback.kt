package com.tombaxter.taken.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.widget.RemoteViews
import com.tombaxter.taken.R
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.surfaces.WidgetFallbackFace
import com.tombaxter.taken.core.theme.Look
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.ui.theme.TakenColors
import androidx.compose.ui.graphics.toArgb

/**
 * A Taken widget Android could not draw (SPEC-ANDROID 10.1, NEXT 7). Glance's own error card is stock ("Can't show
 * content" on Material's surface), so both widgets override `onCompositionError`, Glance's documented way to replace it
 * (Glance 1.1 and later, https://developer.android.com/develop/ui/compose/glance/error-handling), with this card in the
 * person's look: the mark, TAKEN, and a tap into Taken ([WidgetFallbackFace]), whose return to the front redraws every
 * widget. Plain RemoteViews: text and two vector marks, no bitmaps, as that page asks of the fallback from Android 17.
 */
object WidgetFallback {
    /** The card for one widget kind, in a look. */
    fun remoteViews(context: Context, face: WidgetFallbackFace, look: Look, requestCode: Int): RemoteViews {
        val c = TakenColors.of(look)
        val views = RemoteViews(context.packageName, R.layout.widget_fallback)
        val root = android.R.id.background
        views.setInt(root, "setBackgroundColor", c.bg.toArgb())
        if (Build.VERSION.SDK_INT >= 31) {
            // The widgets' frame: the system's corner radius from Android 12 (WS-2), as Glance's cornerRadius applies it.
            views.setViewOutlinePreferredRadiusDimen(root, android.R.dimen.system_app_widget_background_radius)
            views.setBoolean(root, "setClipToOutline", true)
        }
        views.setInt(R.id.widget_fallback_lit, "setColorFilter", c.signal.toArgb())
        views.setInt(R.id.widget_fallback_outline, "setColorFilter", c.fgMuted.toArgb())
        views.setTextViewText(R.id.widget_fallback_title, face.title)
        views.setTextColor(R.id.widget_fallback_title, c.fg.toArgb())
        views.setTextViewText(R.id.widget_fallback_hint, face.hint)
        views.setTextColor(R.id.widget_fallback_hint, c.fgMuted.toArgb())
        views.setContentDescription(root, face.spoken)
        val open = PendingIntent.getActivity(
            context,
            requestCode,
            takenIntent(context, face.link),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(root, open)
        return views
    }

    /**
     * Shows the card on one placed widget. The look is the one the surfaces last read, since the files may be what failed;
     * Signal before any read [Own choice].
     */
    fun show(context: Context, appWidgetId: Int, kind: String) {
        val look = runCatching { (context.applicationContext as TakenApp).container.surfaces.look }.getOrDefault(ThemeID.SIGNAL)
        val views = remoteViews(context, WidgetFallbackFace.of(kind), Looks.look(look), appWidgetId)
        AppWidgetManager.getInstance(context).updateAppWidget(appWidgetId, views)
    }
}
