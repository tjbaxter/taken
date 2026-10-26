package com.tombaxter.taken

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.SpeechRecognizer
import android.view.accessibility.AccessibilityManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.notify.AndroidNotifications
import com.tombaxter.taken.notify.NotificationHost
import com.tombaxter.taken.notify.ReminderChannels
import com.tombaxter.taken.ui.shell.LaunchVeil
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import com.tombaxter.taken.voice.OnDeviceSpeechCapture
import com.tombaxter.taken.voice.VoiceCapture
import com.tombaxter.taken.voice.VoiceHost
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/**
 * The one activity: edge to edge with the look's system bar icons, Taken's Compose tree, `taken://` links, and the
 * Android pieces the screens ask for (the Sharesheet, the photo picker, the browser).
 */
class MainActivity : ComponentActivity(), Platform {
    private val viewModel: AppViewModel by viewModels { AppViewModel.factory((application as TakenApp).container) }
    private var pendingLink: String? = null

    /** The pending link came through Taken's own way in ([INTERNAL_LINK]), so its Take all or log may run. */
    private var pendingFromTaken = false

    /** The screen's model once the files are read (the tests reach it here). */
    internal val model: AppModel? get() = viewModel.model

    /** The system photo picker: no media permission (https://developer.android.com/training/data-storage/shared/photopicker). */
    private val photoPicker = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@registerForActivityResult
        lifecycleScope.launch {
            val jpeg = withContext(Dispatchers.Default) { ProfilePhotos.prepare(contentResolver, uri) } ?: return@launch
            viewModel.model?.setProfilePhoto(jpeg)
        }
    }

    /**
     * Import weight CSV: Android's document picker for a CSV, TSV or plain text file, no storage permission
     * (https://developer.android.com/training/data-storage/shared/documents-files). The bytes are read off the main thread,
     * and the result goes to the model, so a picker that outlives a rotation still lands.
     */
    private val weightPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@registerForActivityResult
        lifecycleScope.launch {
            val bytes = withContext(Dispatchers.IO) {
                try {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (e: IOException) {
                    null
                } catch (e: SecurityException) {
                    null
                }
            }
            val text = bytes?.let { withContext(Dispatchers.Default) { com.tombaxter.taken.core.weight.WeightImport.text(it) } }
            viewModel.model?.importWeights(text)
        }
    }

    /**
     * RECORD_AUDIO, asked in context at the first mic tap (SPEC-ANDROID 11,
     * https://developer.android.com/training/permissions/requesting). Registered here, before the activity starts, so the
     * answer reaches the To-do tab after a rotation too.
     */
    private val microphonePermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        viewModel.model?.todo?.microphoneAnswered(granted)
    }

    /**
     * POST_NOTIFICATIONS on Android 13 and later, asked in context from the nudge's Turn on and Profile's Nudge switch
     * (SPEC-ANDROID 10.4, https://developer.android.com/develop/ui/views/notifications/notification-permission).
     * Registered here, before the activity starts, so the answer reaches the model after a rotation too.
     */
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        viewModel.model?.notifications?.answered(granted)
    }

    /**
     * Whether the splash screen stays: until Taken has read its files, a few milliseconds, so the first frame is the real
     * screen and never a blank canvas (SPEC-ANDROID 6.1). Google's own case for keeping it: "loading in-app settings from
     * a local disk asynchronously" (https://developer.android.com/develop/ui/views/launch/splash-screen).
     */
    internal val keepsSplash: Boolean get() = viewModel.model == null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The splash screen on every API level, installed before super.onCreate as core-splashscreen requires
        // (https://developer.android.com/develop/ui/views/launch/splash-screen/migrate): Signal's canvas and the capsule,
        // then Theme.Taken.
        val splash = installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        splash.setKeepOnScreenCondition { keepsSplash }
        // A link is handled once. A recreated activity (rotation, fold, resize, a return after process death) gets its
        // launch intent again, and so does a task relaunched from Recents: neither replays the link. Navigation does the
        // same with the deep-link-handled flag it keeps in saved state (NavController's KEY_DEEP_LINK_HANDLED).
        // A link that came before the files were read is carried across in the saved state instead.
        if (savedInstanceState == null) {
            pendingLink = launchLink(intent)
            pendingFromTaken = fromTaken(intent)
        } else {
            pendingLink = savedInstanceState.getString(PENDING_LINK)
            pendingFromTaken = savedInstanceState.getBoolean(PENDING_FROM_TAKEN)
        }
        setContent {
            val model = viewModel.model
            if (model == null) {
                Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color(0xFF08090A)))
                return@setContent
            }
            LaunchedEffect(model) {
                pendingLink?.let { model.handle(it, fromTaken = pendingFromTaken) }
                pendingLink = null
            }
            // Light or dark system bar icons follow the look, not the system (SPEC-ANDROID 6.1).
            LaunchedEffect(model.theme) {
                val light = com.tombaxter.taken.core.theme.Looks.look(model.theme).isLight
                enableEdgeToEdge(
                    statusBarStyle = if (light) SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT) else SystemBarStyle.dark(Color.TRANSPARENT),
                    navigationBarStyle = if (light) SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT) else SystemBarStyle.dark(Color.TRANSPARENT),
                )
            }
            // Android's notification answers come from this activity, set before ON_START reads them (an observer added
            // to a started lifecycle hears ON_START at once, so this effect comes first).
            DisposableEffect(model) {
                model.notifications.host = this@MainActivity
                onDispose { model.notifications.host = NotificationHost.none }
            }
            LifecycleEventEffect(Lifecycle.Event.ON_START) { model.didBecomeActive() }
            // A configuration change (rotation, fold, resize, dark mode, font size) stops the activity too; only a real
            // trip to the background ends edit mode
            // (https://developer.android.com/reference/android/app/Activity#isChangingConfigurations()).
            LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
                if (!isChangingConfigurations) model.didEnterBackground()
            }
            // A 20 s ticker while Taken is in front keeps the time and the day current.
            LaunchedEffect(model) {
                repeatOnLifecycle(Lifecycle.State.STARTED) {
                    while (true) {
                        delay(20_000)
                        model.tick()
                    }
                }
            }
            // A light look fades in from the splash screen's canvas, as on the iPhone (SPEC-ANDROID 6.1).
            LaunchVeil(com.tombaxter.taken.core.theme.Looks.look(model.theme)) { TakenRoot(model, this) }
        }
    }

    private val pro: ProSource get() = (application as TakenApp).container.pro

    override fun onStart() {
        super.onStart()
        // Google: connect the BillingClient "when your app is launched or comes to the foreground"
        // (https://developer.android.com/google/play/billing/integrate). Taken Pro asks Play for the account's purchases.
        pro.attach(this)
        pro.foreground()
    }

    override fun onResume() {
        super.onResume()
        // Google: "call queryPurchasesAsync() in your app's onResume() method to handle purchases that have transitioned to
        // the PURCHASED state while your app was not running" (same page).
        pro.resumed()
    }

    override fun onDestroy() {
        // Play's purchase screen needs a live activity; a destroyed one is never handed to it.
        pro.attach(null)
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        pendingLink?.let {
            outState.putString(PENDING_LINK, it)
            outState.putBoolean(PENDING_FROM_TAKEN, pendingFromTaken)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The newest intent is the activity's from now on, so a later recreation reads this one, not the first.
        setIntent(intent)
        receiveLink(intent)
    }

    /** A link for the running activity: handled now, or once the files are read; it acts only when it came from Taken. */
    internal fun receiveLink(intent: Intent) {
        val link = intent.data?.toString() ?: return
        val trusted = fromTaken(intent)
        val model = viewModel.model
        if (model == null) {
            pendingLink = link
            pendingFromTaken = trusted
        } else {
            model.handle(link, fromTaken = trusted)
        }
    }

    // MARK: Platform

    override val touchExploration: Boolean
        get() = getSystemService(AccessibilityManager::class.java)?.isTouchExplorationEnabled == true

    /**
     * taken-log.csv through the Android Sharesheet with a FileProvider URI (https://developer.android.com/training/sharing/send).
     * The log is built and written off the main thread, where disk work never belongs
     * (https://developer.android.com/topic/performance/vitals/anr); the Sharesheet opens back on it.
     */
    override fun shareCsv(make: () -> String) = share(com.tombaxter.taken.core.stack.CsvExport.FILE_NAME, make)

    /** taken-weight.csv, the same way. */
    override fun shareWeightCsv(make: () -> String) = share(com.tombaxter.taken.core.weight.WeightCSV.FILE_NAME, make)

    override fun importWeightCsv() {
        try {
            weightPicker.launch(arrayOf("text/csv", "text/comma-separated-values", "text/tab-separated-values", "text/plain"))
        } catch (e: ActivityNotFoundException) {
            viewModel.model?.importWeights(null)
        }
    }

    private fun share(fileName: String, make: () -> String) {
        lifecycleScope.launch {
            val uri = withContext(Dispatchers.IO) {
                try {
                    val folder = (application as TakenApp).container.stores.exportsDir.apply { mkdirs() }
                    val file = File(folder, fileName)
                    file.writeText(make())
                    FileProvider.getUriForFile(this@MainActivity, "$packageName.files", file)
                } catch (e: IOException) {
                    null
                }
            } ?: return@launch
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/csv"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, null))
        }
    }

    override fun pickPhoto() {
        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    override fun openUrl(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: ActivityNotFoundException) {
            // No browser on this phone: nothing to open.
        }
    }

    /**
     * Notifications are off for Taken where Android lets the person turn them off: for the whole app (Settings, or a
     * refused prompt Android will not show again), or the "Trial reminder" channel alone. The paywall then promises no
     * reminder it knows cannot come. Not asked yet counts as on: the ask follows a trial (SPEC-ANDROID 10.4).
     */
    override val notificationsOff: Boolean
        get() = if (notificationsAllowed) trialChannelOff else !notificationsAskable

    // MARK: VoiceHost

    /** Android 12 and later with on-device recognition: the only recognizer Taken uses (SPEC-ANDROID 11). No permission needed. */
    override val voiceAvailable: Boolean
        get() {
            if (Build.VERSION.SDK_INT < 31) return false
            return try {
                SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            } catch (e: RuntimeException) {
                false
            }
        }

    override val microphoneGranted: Boolean
        get() = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    override val microphoneRationaleDue: Boolean
        get() = shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)

    override fun requestMicrophone() {
        microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
    }

    /** The app's details page, where the microphone is turned back on (SPEC-ANDROID 6.3). */
    override fun openAppSettings() {
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
        try {
            startActivity(details)
        } catch (e: ActivityNotFoundException) {
            // No Settings app to open: the blocker still offers typing.
        }
    }

    // MARK: NotificationHost

    override val notificationsAllowed: Boolean
        get() = AndroidNotifications.allowed(this)

    override val notificationsAskable: Boolean
        get() = Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    override val notificationRationaleDue: Boolean
        get() = Build.VERSION.SDK_INT >= 33 && shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)

    override val nudgeChannelOff: Boolean
        get() = ReminderChannels.isOff(this, ReminderKind.NUDGE)

    override val trialChannelOff: Boolean
        get() = ReminderChannels.isOff(this, ReminderKind.TRIAL)

    override fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            // No runtime prompt before Android 13: notifications are on unless turned off in Settings.
            viewModel.model?.notifications?.answered(AndroidNotifications.allowed(this))
        }
    }

    /**
     * Taken's notification settings (`ACTION_APP_NOTIFICATION_SETTINGS`, SPEC-ANDROID 6.3), or one channel's page
     * (`ACTION_CHANNEL_NOTIFICATION_SETTINGS` with the package and the channel,
     * https://developer.android.com/develop/ui/views/notifications/channels).
     */
    override fun openNotificationSettings(channelId: String?) {
        val settings = if (channelId != null) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        }
        try {
            startActivity(settings.putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        } catch (e: ActivityNotFoundException) {
            openAppSettings()
        }
    }

    /** Android 12 and later hear on the phone; below that there is no on-device recognizer to ask (SPEC-ANDROID 11). */
    override fun newVoiceCapture(): VoiceCapture =
        if (Build.VERSION.SDK_INT >= 31) OnDeviceSpeechCapture(this) else VoiceHost.none.newVoiceCapture()

    override val versionName: String
        get() = try {
            val info = if (Build.VERSION.SDK_INT >= 33) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            info.versionName ?: "1.0.0"
        } catch (e: PackageManager.NameNotFoundException) {
            "1.0.0"
        }

    companion object {
        /**
         * Taken's own, unexported way in for its links (the manifest's activity-alias): the widgets, the tile, the
         * notifications and the shortcuts start MainActivity through it, and no other app can (SPEC-ANDROID 10.3).
         */
        const val INTERNAL_LINK = "com.tombaxter.taken.InternalLink"

        private const val PENDING_LINK = "taken.pendingLink"
        private const val PENDING_FROM_TAKEN = "taken.pendingLinkFromTaken"
    }
}

/**
 * The link came from Taken itself: through [MainActivity.INTERNAL_LINK], which is not exported, so only Taken's own
 * PendingIntents and the launcher's static shortcuts (started as Taken) reach it. Anything else that starts the exported
 * MainActivity with a `taken://` link (another app, a page) may only navigate, never log
 * (https://developer.android.com/privacy-and-security/risks/unsafe-use-of-deeplinks).
 */
internal fun fromTaken(intent: Intent?): Boolean = intent?.component?.className == MainActivity.INTERNAL_LINK

/**
 * The `taken://` link an activity was started with, or null: none, or a task relaunched from Recents, which hands the
 * first intent back (FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) and must not replay its link.
 */
internal fun launchLink(intent: Intent?): String? {
    if (intent == null) return null
    if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
    return intent.data?.toString()
}

/** A chosen photo as Taken keeps it: the centre square, at most 600 pixels, as JPEG at quality 85 (the iPhone's rule). */
object ProfilePhotos {
    const val SIDE = 600

    fun prepare(resolver: ContentResolver, uri: Uri): ByteArray? = runCatching {
        val source = ImageDecoder.createSource(resolver, uri)
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val shortSide = minOf(info.size.width, info.size.height)
            if (shortSide > SIDE * 2) decoder.setTargetSampleSize(shortSide / (SIDE * 2))
        }
        square(bitmap)
    }.getOrNull()

    fun square(bitmap: Bitmap): ByteArray {
        val side = minOf(bitmap.width, bitmap.height)
        val cropped = Bitmap.createBitmap(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side)
        val target = minOf(SIDE, side)
        val scaled = if (target == side) cropped else Bitmap.createScaledBitmap(cropped, target, target, true)
        return ByteArrayOutputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }
}
