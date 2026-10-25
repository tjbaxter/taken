package com.tombaxter.taken.ui.shell

import android.graphics.BitmapFactory
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.SnackbarData
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SnackbarVisuals
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.ui.NavDisplay
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.AppTab
import com.tombaxter.taken.Effect
import com.tombaxter.taken.Haptic
import com.tombaxter.taken.Route
import com.tombaxter.taken.Sheet
import com.tombaxter.taken.Toast
import com.tombaxter.taken.ui.add.AddSheet
import com.tombaxter.taken.ui.components.Announcement
import com.tombaxter.taken.ui.components.AvatarImage
import com.tombaxter.taken.ui.components.CloseButton
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.day.DaySheet
import com.tombaxter.taken.ui.history.HistoryScreen
import com.tombaxter.taken.ui.item.ItemEditorScreen
import com.tombaxter.taken.ui.item.ItemSheet
import com.tombaxter.taken.ui.item.SetTimeSheet
import com.tombaxter.taken.ui.paywall.PaywallHost
import com.tombaxter.taken.ui.profile.ProfileScreen
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenTheme
import com.tombaxter.taken.ui.theme.TakenType
import com.tombaxter.taken.ui.today.TakeAllButton
import com.tombaxter.taken.ui.today.TodayScreen

/** What the screen needs from Android beyond the model: TalkBack's state, sharing a file, picking a photo. */
interface Platform {
    /** TalkBack is on: the toast stays until it is dismissed, as VoiceOver keeps it on the iPhone. */
    val touchExploration: Boolean
    /** Shares taken-log.csv; `make` builds its text, off the main thread. */
    fun shareCsv(make: () -> String)
    fun pickPhoto()
    fun openUrl(url: String)
    val versionName: String

    /**
     * Notifications are turned off for Taken where Android lets the person turn them off (the app's notification
     * settings, or a refused prompt on Android 13+). The paywall then promises no reminder it knows cannot come. Not
     * asked yet counts as on: the ask may follow a trial.
     */
    val notificationsOff: Boolean

    companion object {
        /** For tests and captures: nothing leaves the screen. */
        val none: Platform = object : Platform {
            override val touchExploration = false
            override fun shareCsv(make: () -> String) = Unit
            override fun pickPhoto() = Unit
            override fun openUrl(url: String) = Unit
            override val versionName = "1.0.0"
            override val notificationsOff = false
        }
    }
}

/**
 * The app's one Compose tree (SPEC-ANDROID 7.1): Navigation 3's back stack (the tabs, Profile, an item from Profile),
 * one sheet at a time over it, the toast, the paywall, haptics and TalkBack's announcements.
 */
@Composable
fun TakenRoot(model: AppModel, platform: Platform) {
    TakenTheme(model.theme) {
        val view = LocalView.current
        var announcement by remember { mutableStateOf<String?>(null) }
        DisposableEffect(model, view) {
            model.onEffect = { effect ->
                when (effect) {
                    is Effect.Feel -> performHaptic(view, effect.haptic)
                    is Effect.Announce -> announcement = effect.text
                }
            }
            onDispose { model.onEffect = {} }
        }
        Box(Modifier.fillMaxSize().background(Taken.colors.bg)) {
            NavDisplay(
                backStack = model.backStack,
                onBack = { model.back() },
                entryProvider = { key ->
                    when (key) {
                        Route.Main -> NavEntry(key) { MainShell(model, platform) }
                        Route.Profile -> NavEntry(key) { ProfileScreen(model, platform) }
                        is Route.ProfileItem -> NavEntry(key) { ItemEditorScreen(model, key.itemId) }
                    }
                },
            )
            Announcement(announcement)
        }
        SheetsHost(model)
        PaywallHost(model, platform)
    }
}

/**
 * The tabs: a navigation bar at the bottom on phones, a rail at 600 dp and wider, content capped at a readable width
 * (SPEC-ANDROID 6.2). Back ends Today's edit mode, then brings Today forward, then leaves the app.
 */
@Composable
fun MainShell(model: AppModel, platform: Platform) {
    val colors = Taken.colors
    BackHandler(enabled = model.editingStack || model.tab != AppTab.TODAY) { model.backOnTabs() }
    BoxWithConstraints(Modifier.fillMaxSize().background(colors.bg)) {
        val wide = maxWidth >= 600.dp
        if (wide) {
            Row(Modifier.fillMaxSize()) {
                NavigationRail(containerColor = colors.bg, modifier = Modifier.fillMaxHeight()) {
                    Spacer(Modifier.height(12.dp))
                    for (tab in AppTab.entries) {
                        NavigationRailItem(
                            selected = model.tab == tab,
                            onClick = { model.tab = tab },
                            icon = { Icon(tabIcon(tab, model.tab == tab), contentDescription = null) },
                            label = { Text(tabTitle(tab), style = TakenType.sans(12, FontWeight.Medium)) },
                            colors = NavigationRailItemDefaults.colors(
                                selectedIconColor = colors.signalInk, selectedTextColor = colors.signalInk,
                                indicatorColor = colors.signalWash, unselectedIconColor = colors.fgSubtle,
                                unselectedTextColor = colors.fgSubtle,
                            ),
                        )
                    }
                }
                Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.TopCenter) {
                    Box(Modifier.widthIn(max = 640.dp).fillMaxSize()) { TabContent(model, platform, wide = true) }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).fillMaxWidth()) { TabContent(model, platform, wide = false) }
                Box(Modifier.fillMaxWidth().height(1.dp).background(colors.line))
                NavigationBar(containerColor = colors.bg, tonalElevation = 0.dp) {
                    for (tab in AppTab.entries) {
                        NavigationBarItem(
                            selected = model.tab == tab,
                            onClick = { model.tab = tab },
                            icon = { Icon(tabIcon(tab, model.tab == tab), contentDescription = null) },
                            label = { Text(tabTitle(tab), style = TakenType.sans(12, FontWeight.Medium)) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = colors.signalInk, selectedTextColor = colors.signalInk,
                                indicatorColor = colors.signalWash, unselectedIconColor = colors.fgSubtle,
                                unselectedTextColor = colors.fgSubtle,
                            ),
                            modifier = Modifier.testTag("tab-${tab.name.lowercase()}"),
                        )
                    }
                }
            }
        }
    }
}

private fun tabTitle(tab: AppTab): String = when (tab) {
    AppTab.TODAY -> "Today"
    AppTab.HISTORY -> "History"
}

private fun tabIcon(tab: AppTab, selected: Boolean) = when (tab) {
    AppTab.TODAY -> if (selected) Symbols.PillFill else Symbols.Pill
    AppTab.HISTORY -> if (selected) Symbols.CalendarMonthFill else Symbols.CalendarMonth
}

/**
 * A tab's content inside the system bars. On phones the NavigationBar below pads the bottom inset; beside the rail nothing
 * does, so the content pads it itself and Take all and the snackbar sit above the navigation bar or taskbar
 * (https://developer.android.com/develop/ui/compose/system/system-bars). The rail pads its own start side.
 */
@Composable
private fun TabContent(model: AppModel, platform: Platform, wide: Boolean) {
    val sides = if (wide) {
        WindowInsetsSides.Top + WindowInsetsSides.End + WindowInsetsSides.Bottom
    } else {
        WindowInsetsSides.Top + WindowInsetsSides.Horizontal
    }
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing.only(sides))) {
        when (model.tab) {
            AppTab.TODAY -> TodayScreen(model, openUrl = platform::openUrl) {
                Column {
                    ToastHost(model, platform)
                    TakeAllButton(model)
                }
            }
            AppTab.HISTORY -> Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { HistoryScreen(model) }
                ToastHost(model, platform)
            }
        }
    }
}

/**
 * The top of each tab: a large title, a line under it, and the profile avatar (48 dp target, TalkBack "Profile and
 * settings"). There is no gear: every setting lives in Profile.
 */
@Composable
fun TabHeader(model: AppModel, title: String, subtitle: String?) {
    val colors = Taken.colors
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f).padding(top = 4.dp).semantics(mergeDescendants = true) { heading() }) {
            Text(title, style = TakenType.sans(34, FontWeight.SemiBold), color = colors.fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) {
                Spacer(Modifier.height(4.dp))
                Text(subtitle, style = TakenType.sans(15), color = colors.fgSubtle)
            }
        }
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier
                .size(48.dp)
                .clip(CircleShape)
                .clickable(role = Role.Button) { model.openProfile() }
                .semantics {
                    contentDescription = if (model.profile.name.isEmpty()) "Profile and settings" else "${model.profile.name}, profile and settings"
                }
                .testTag("avatar"),
            contentAlignment = Alignment.Center,
        ) {
            AvatarImage(model.profile.initials, rememberPhoto(model.photo), 36.dp)
        }
    }
}

/** The profile photo, decoded once per change. */
@Composable
fun rememberPhoto(bytes: ByteArray?): ImageBitmap? = remember(bytes) {
    bytes?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }.getOrNull() }
}

/** One sheet at a time, over whatever is in front. */
@Composable
private fun SheetsHost(model: AppModel) {
    when (val sheet = model.sheet) {
        null -> Unit
        Sheet.Add -> AddSheet(model) { model.sheet = null }
        is Sheet.Day -> DaySheet(model, sheet.day) { model.sheet = null }
        is Sheet.SetTime -> SetTimeSheet(model, sheet.itemId) { model.sheet = null }
        is Sheet.EditItem -> ItemSheet(model, sheet.itemId) { model.sheet = null }
    }
}

/** The toast as a Material 3 snackbar in Taken's look: 4 s, lengthened for accessibility, kept while TalkBack runs. */
class ToastVisuals(val toast: Toast, keep: Boolean) : SnackbarVisuals {
    override val message: String = listOfNotNull(toast.message, toast.time).joinToString(" ")
    override val actionLabel: String? = if (toast.undo != null) "Undo" else null
    override val withDismissAction: Boolean = keep
    override val duration: SnackbarDuration = if (keep) SnackbarDuration.Indefinite else SnackbarDuration.Short
}

@Composable
fun ToastHost(model: AppModel, platform: Platform) {
    val host = remember { SnackbarHostState() }
    val toast = model.toast
    LaunchedEffect(toast?.id) {
        if (toast == null) {
            host.currentSnackbarData?.dismiss()
            return@LaunchedEffect
        }
        when (host.showSnackbar(ToastVisuals(toast, keep = platform.touchExploration))) {
            SnackbarResult.ActionPerformed -> model.undo(toast)
            SnackbarResult.Dismissed -> model.dismissToast(toast)
        }
    }
    SnackbarHost(host, modifier = Modifier.padding(horizontal = 20.dp)) { data -> TakenToast(data) }
}

@Composable
private fun TakenToast(data: SnackbarData) {
    val colors = Taken.colors
    val visuals = data.visuals as? ToastVisuals ?: return
    val toast = visuals.toast
    val shape = RoundedCornerShape(Taken.shapes.card)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 10.dp)
            .heightIn(min = 52.dp)
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.lineStrong, shape)
            .semantics {
                contentDescription = toast.spoken ?: visuals.message
                liveRegion = LiveRegionMode.Polite
                customActions = listOf(CustomAccessibilityAction("Dismiss") { data.dismiss(); true })
            }
            .padding(start = 16.dp, end = 4.dp)
            .testTag("toast"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f).clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically) {
            Text(toast.message, style = TakenType.sans(15), color = colors.fg, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (toast.time != null) {
                Spacer(Modifier.width(6.dp))
                Text(toast.time, style = TakenType.mono(15), color = colors.fg, maxLines = 1)
            }
        }
        if (visuals.actionLabel != null) {
            Box(
                Modifier.heightIn(min = 48.dp).widthIn(min = 64.dp).clip(RoundedCornerShape(Taken.shapes.cell))
                    .clickable(role = Role.Button) { data.performAction() }
                    .semantics { contentDescription = "Undo" }
                    .testTag("undo"),
                contentAlignment = Alignment.Center,
            ) { Text("Undo", style = TakenType.sans(15, FontWeight.SemiBold), color = colors.signalInk) }
        }
        if (visuals.withDismissAction) {
            CloseButton { data.dismiss() }
        }
    }
}

/**
 * Taken's haptics through the view, so the system's touch feedback setting always applies (SPEC-ANDROID 6.2): a take is
 * CONFIRM, choices a segment tick, undo and the times a soft key release. Older Androids get the nearest constant.
 */
fun performHaptic(view: View, haptic: Haptic) {
    val constant = when (haptic) {
        Haptic.CONFIRM -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK
        Haptic.TICK -> if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK
        Haptic.SOFT -> HapticFeedbackConstants.VIRTUAL_KEY_RELEASE
    }
    view.performHapticFeedback(constant)
}
