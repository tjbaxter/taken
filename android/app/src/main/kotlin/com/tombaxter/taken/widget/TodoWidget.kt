package com.tombaxter.taken.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.semantics.testTag
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import com.tombaxter.taken.R
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.surfaces.TodoWidgetFace
import com.tombaxter.taken.core.surfaces.TodoWidgetRow
import com.tombaxter.taken.core.surfaces.WidgetCopy
import com.tombaxter.taken.core.surfaces.WidgetTap
import com.tombaxter.taken.core.theme.Look
import com.tombaxter.taken.core.theme.Looks

/**
 * The to-do capture widget (SPEC-ANDROID 10.1), the iPhone's to-do Lock Screen widget on Android's home screen: a mic that
 * opens Taken already listening (`taken://todo/record`, the To-do tab's 90 s rule), "To-do · 4", and the open list in the
 * To-do tab's order, scrolling, as Google asks of a list widget at 4x2 and 4x4 (WL-5,
 * https://developer.android.com/docs/quality-guidelines/widget-quality). A task opens To-do scrolled to it; "Tap to see
 * your list" when nothing is open. Tap, speak, end: the widget adds no choice to the capture path.
 */
class TodoWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.SMALL, WidgetSizes.TALL, WidgetSizes.MEDIUM, WidgetSizes.LARGE))
    override val previewSizeMode = SizeMode.Responsive(setOf(WidgetSizes.TALL, WidgetSizes.MEDIUM))
    override val stateDefinition: GlanceStateDefinition<*>? = null

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val surfaces = (context.applicationContext as TakenApp).container.surfaces
        val initial = surfaces.read()
        provideContent {
            val inputs by surfaces.inputs.collectAsState(initial)
            TodoWidgetContent(surfaces.todoFace(inputs), Looks.look(inputs.stack.settings.theme))
        }
    }

    /** Android 15's generated preview: the demo to-dos in the person's look. */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val surfaces = (context.applicationContext as TakenApp).container.surfaces
        val (face, look) = surfaces.demoTodoFace()
        provideContent { TodoWidgetContent(face, Looks.look(look)) }
    }
}

/** Android's entry point for the to-do widget. */
class TodoWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodoWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        (context.applicationContext as TakenApp).container.surfaces.armSoon()
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        (context.applicationContext as TakenApp).container.surfaces.armSoon()
    }
}

/** Everything the to-do widget draws. */
@Composable
fun TodoWidgetContent(face: TodoWidgetFace, look: Look) {
    val palette = WidgetPalette(look)
    val context = LocalContext.current
    val size = LocalSize.current
    val list = WidgetTap.Open(face.listUrl).action(context)
    var root = GlanceModifier.widgetFrame(palette).padding(12.dp)
    if (list != null) root = root.clickable(list)
    Box(root.semantics { testTag = "todo-widget" }) {
        if (size.height < WidgetSizes.TALL.height) {
            // 2x1: the mic and the count.
            Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Mic(face, palette)
                Spacer(GlanceModifier.width(12.dp))
                Column {
                    Text(WidgetCopy.TODO, style = WidgetType.sans(15.sp, palette.fg, FontWeight.Bold), maxLines = 1)
                    Text(face.countLine, style = WidgetType.sans(13.sp, palette.fgMuted), maxLines = 1)
                }
            }
        } else {
            Column(GlanceModifier.fillMaxSize()) {
                Row(GlanceModifier.fillMaxWidth().height(WidgetSizes.TOUCH), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        face.header,
                        style = WidgetType.sans(15.sp, palette.fg, FontWeight.Bold),
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight(),
                    )
                    Mic(face, palette)
                }
                if (face.rows.isEmpty()) {
                    Box(GlanceModifier.fillMaxWidth().height(WidgetSizes.TOUCH), contentAlignment = Alignment.CenterStart) {
                        Text(WidgetCopy.TODO_EMPTY, style = WidgetType.sans(14.sp, palette.fgSubtle), maxLines = 2)
                    }
                } else {
                    LazyColumn(GlanceModifier.fillMaxWidth().defaultWeight()) {
                        // Stable ids keep the scroll position across updates; Glance reserves ids at or below -2^62.
                        items(face.rows, itemId = { (it.id.mostSignificantBits xor it.id.leastSignificantBits) and Long.MAX_VALUE }) { row ->
                            TodoLine(row, palette)
                        }
                    }
                }
            }
        }
    }
}

/** The mic: a 48 dp disc in the signal that opens Taken listening. */
@Composable
private fun Mic(face: TodoWidgetFace, palette: WidgetPalette) {
    val context = LocalContext.current
    var modifier = GlanceModifier.size(WidgetSizes.TOUCH)
        .background(ImageProvider(R.drawable.widget_dot), colorFilter = ColorFilter.tint(palette.signal))
    WidgetTap.Open(face.micUrl).action(context)?.let { modifier = modifier.clickable(it) }
    Box(
        modifier.semantics { contentDescription = WidgetCopy.NEW_VOICE_TODO; testTag = "widget-mic" },
        contentAlignment = Alignment.Center,
    ) {
        Glyph(R.drawable.ic_widget_mic, palette.onSignal, 22.dp)
    }
}

/** One open task: its words, and when it is due in mono (the signal's ink once it is overdue, as in the To-do tab). */
@Composable
private fun TodoLine(row: TodoWidgetRow, palette: WidgetPalette) {
    val context = LocalContext.current
    var modifier = GlanceModifier.fillMaxWidth().height(WidgetSizes.TOUCH)
    WidgetTap.Open(row.url).action(context)?.let { modifier = modifier.clickable(it) }
    Row(modifier.semantics { contentDescription = row.spoken }, verticalAlignment = Alignment.CenterVertically) {
        Text(row.title, style = WidgetType.sans(14.sp, palette.fg), maxLines = 1, modifier = GlanceModifier.defaultWeight())
        row.due?.let {
            Spacer(GlanceModifier.width(8.dp))
            Text(it, style = WidgetType.mono(12.sp, if (row.overdue) palette.signalInk else palette.fgSubtle), maxLines = 1)
        }
    }
}
