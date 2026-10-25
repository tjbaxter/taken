package com.tombaxter.taken

import android.app.Activity
import android.appwidget.AppWidgetHostView
import android.content.Context
import android.graphics.Color
import android.os.Looper
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureRoboImage
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.demo.TodoDemo
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.surfaces.StackWidgetFace
import com.tombaxter.taken.core.surfaces.TodoWidgetFace
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.widget.StackWidgetContent
import com.tombaxter.taken.widget.TodoWidgetContent
import com.tombaxter.taken.widget.WidgetSizes
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZonedDateTime
import java.util.Locale

/**
 * The widgets as a phone draws them, for Tom (SPEC-ANDROID 15.3): each Glance composition is turned into RemoteViews and
 * applied into an `AppWidgetHostView` on a launcher-like canvas, then saved by Roborazzi on Robolectric's native graphics,
 * the way Google's Glance screenshot tool does it (glance-experimental-tools `GlanceScreenshotTestActivity`,
 * https://github.com/google/glance-experimental-tools/tree/main/appwidget-testing, archived in May 2026; androidx's
 * glance-appwidget-testing tests content but draws nothing). The demo stack in London on Wednesday 21 October 2026 at
 * 21:41, as the app's screenshots.
 *
 * - `widgets_<look>`: every size of both widgets in every look (2x1, 2x2, 4x2, 4x4).
 * - `widgets-states_<look>`: locked, all taken, an item logged in the last hour, an empty stack, and an empty to-do list.
 * - `widgets_signal_font200`: the 4x2 and 2x2 widgets at 200% text.
 * - `widgets-picker`: the picker's preview layouts for Android 12 to 14 (Android 15 and later generate theirs from the
 *   same compositions as `widgets_<look>`).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = WidgetScreenshotTests.BOARD)
@OptIn(ExperimentalGlanceRemoteViewsApi::class, ExperimentalRoborazziApi::class)
class WidgetScreenshotTests {
    private val zone = DemoScreens.zone
    private val now = DemoScreens.now()

    private fun Context.px(dp: Float): Int = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, resources.displayMetrics).toInt()

    /** A launcher's widget host: synchronous, as Google's tool makes it, so the widget is drawn before the capture. */
    private class HostView(context: Context) : AppWidgetHostView(context) {
        init {
            setExecutor(null)
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        }
    }

    private class Placed(val size: DpSize, val content: @Composable () -> Unit)

    /** Draws rows of widgets on a plain wallpaper and saves the board. */
    private fun board(name: String, rows: List<List<Placed>>) {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val gap = activity.px(16f)
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(gap, gap, gap, gap)
            setBackgroundColor(WALLPAPER)
        }
        for (row in rows) {
            val line = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
            for ((index, placed) in row.withIndex()) {
                val remote = runBlocking { GlanceRemoteViews().compose(activity, placed.size, content = placed.content).remoteViews }
                val host = HostView(activity)
                val params = LinearLayout.LayoutParams(activity.px(placed.size.width.value), activity.px(placed.size.height.value))
                if (index > 0) params.marginStart = gap
                line.addView(host, params)
                host.addView(remote.apply(activity, host))
            }
            column.addView(
                line,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = gap },
            )
        }
        val frame = FrameLayout(activity)
        frame.addView(column, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        activity.setContentView(frame)
        shadowOf(Looper.getMainLooper()).idle()
        column.captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    private fun stackWidget(size: DpSize, state: StackState, look: ThemeID, locked: Boolean = false, at: java.time.Instant = now) =
        Placed(size) {
            StackWidgetContent(StackWidgetFace(WidgetSnapshot(state, at, zone, locked), Locale.US), Looks.look(look))
        }

    private fun todoWidget(size: DpSize, todos: TodoState, look: ThemeID, at: java.time.Instant = now) =
        Placed(size) {
            TodoWidgetContent(TodoWidgetFace(todos, at, DayClock(DemoData.settings.dayStartHour, zone), Locale.US), Looks.look(look))
        }

    private fun demoStack(allTaken: Boolean = false) = DemoData.state(now, allTaken = allTaken, zone = zone)

    private fun demoTodos() = TodoDemo.state(now, recording = false, zone = zone)

    /** Every size of both widgets, in every look. */
    @Test
    fun everyWidgetInEveryLook() {
        for (look in ThemeID.entries) {
            val state = demoStack()
            val todos = demoTodos()
            board(
                "widgets_${look.raw}",
                listOf(
                    listOf(stackWidget(WidgetSizes.SMALL, state, look), todoWidget(WidgetSizes.SMALL, todos, look)),
                    listOf(stackWidget(WidgetSizes.TALL, state, look), todoWidget(WidgetSizes.TALL, todos, look)),
                    listOf(stackWidget(WidgetSizes.MEDIUM, state, look)),
                    listOf(todoWidget(WidgetSizes.MEDIUM, todos, look)),
                    listOf(stackWidget(WidgetSizes.LARGE, state, look)),
                ),
            )
        }
    }

    /** Locked, all taken, logged in the last hour, empty; in every look. */
    @Test
    fun theWidgetsStates() {
        val morning = ZonedDateTime.of(2026, 10, 21, 7, 50, 0, 0, zone).toInstant()
        for (look in ThemeID.entries) {
            // This morning's doses at 07:42 to 07:45, and Magnesium at 07:46: only Fish Oil's second dose is left, and it
            // waits for the hour to end, so TAKE ALL steps aside for "LOGGED 07:46".
            val held = DemoData.state(morning, allTaken = false, zone = zone).also { s ->
                s.items.firstOrNull { it.name == "Magnesium" }?.let { s.logDose(it.id, ZonedDateTime.of(2026, 10, 21, 7, 46, 0, 0, zone).toInstant(), zone) }
            }
            board(
                "widgets-states_${look.raw}",
                listOf(
                    listOf(stackWidget(WidgetSizes.MEDIUM, demoStack(), look, locked = true)),
                    listOf(stackWidget(WidgetSizes.MEDIUM, demoStack(allTaken = true), look)),
                    listOf(stackWidget(WidgetSizes.MEDIUM, held, look, at = morning)),
                    listOf(stackWidget(WidgetSizes.TALL, StackState(), look), todoWidget(WidgetSizes.TALL, TodoState(), look)),
                ),
            )
        }
    }

    /** 200% text, Android 14's largest (https://developer.android.com/about/versions/14/features). */
    @Test
    @Config(qualifiers = BOARD, fontScale = 2f)
    fun theWidgetsAtLargerText() {
        val state = demoStack()
        val todos = demoTodos()
        board(
            "widgets_signal_font200",
            listOf(
                listOf(stackWidget(WidgetSizes.MEDIUM, state, ThemeID.SIGNAL)),
                listOf(stackWidget(WidgetSizes.TALL, state, ThemeID.SIGNAL), todoWidget(WidgetSizes.TALL, todos, ThemeID.SIGNAL)),
                listOf(stackWidget(WidgetSizes.SMALL, state, ThemeID.SIGNAL), todoWidget(WidgetSizes.SMALL, todos, ThemeID.SIGNAL)),
            ),
        )
    }

    /** The widget picker's previews on Android 12 to 14: the preview layouts, at the widgets' default sizes. */
    @Test
    fun thePickersPreviewLayouts() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val gap = activity.px(16f)
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(gap, gap, gap, gap)
            setBackgroundColor(WALLPAPER)
        }
        val inflater = LayoutInflater.from(activity)
        val previews = listOf("stack" to (R.layout.widget_preview_stack to WidgetSizes.MEDIUM), "todo" to (R.layout.widget_preview_todo to WidgetSizes.TALL))
        val views = previews.map { (name, layoutAndSize) ->
            val (layout, size) = layoutAndSize
            val view = inflater.inflate(layout, column, false)
            column.addView(
                view,
                LinearLayout.LayoutParams(activity.px(size.width.value), activity.px(size.height.value)).apply { bottomMargin = gap },
            )
            name to view
        }
        val frame = FrameLayout(activity)
        frame.addView(column, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        activity.setContentView(frame)
        shadowOf(Looper.getMainLooper()).idle()
        column.captureRoboImage("build/outputs/roborazzi/widgets-picker.png")
        // Each alone, as res/drawable-nodpi's `previewImage` for Android 9 to 11 is made from it.
        for ((name, view) in views) view.captureRoboImage("build/outputs/roborazzi/widget-preview-$name.png")
    }

    companion object {
        /** Tall enough for the board of every size: 340 x 1400 dp at 420 dpi. [Own choice] */
        const val BOARD = "w340dp-h1400dp-420dpi"

        /** A plain mid-grey wallpaper, so dark and light looks both read against it. [Own choice] */
        val WALLPAPER = Color.rgb(0x5A, 0x63, 0x6E)
    }
}
