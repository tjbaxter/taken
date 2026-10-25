package com.tombaxter.taken

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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
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

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A link is handled once. A recreated activity (rotation, fold, resize, a return after process death) gets its
        // launch intent again, and so does a task relaunched from Recents: neither replays the link. Navigation does the
        // same with the deep-link-handled flag it keeps in saved state (NavController's KEY_DEEP_LINK_HANDLED).
        // A link that came before the files were read is carried across in the saved state instead.
        pendingLink = if (savedInstanceState == null) launchLink(intent) else savedInstanceState.getString(PENDING_LINK)
        setContent {
            val model = viewModel.model
            if (model == null) {
                Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color(0xFF08090A)))
                return@setContent
            }
            LaunchedEffect(model) {
                pendingLink?.let(model::handle)
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
            TakenRoot(model, this)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        pendingLink?.let { outState.putString(PENDING_LINK, it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The newest intent is the activity's from now on, so a later recreation reads this one, not the first.
        setIntent(intent)
        val link = intent.data?.toString() ?: return
        val model = viewModel.model
        if (model == null) pendingLink = link else model.handle(link)
    }

    // MARK: Platform

    override val touchExploration: Boolean
        get() = getSystemService(AccessibilityManager::class.java)?.isTouchExplorationEnabled == true

    /**
     * taken-log.csv through the Android Sharesheet with a FileProvider URI (https://developer.android.com/training/sharing/send).
     * The log is built and written off the main thread, where disk work never belongs
     * (https://developer.android.com/topic/performance/vitals/anr); the Sharesheet opens back on it.
     */
    override fun shareCsv(make: () -> String) {
        lifecycleScope.launch {
            val uri = withContext(Dispatchers.IO) {
                try {
                    val folder = File(cacheDir, "exports").apply { mkdirs() }
                    val file = File(folder, com.tombaxter.taken.core.stack.CsvExport.FILE_NAME)
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

    private companion object {
        const val PENDING_LINK = "taken.pendingLink"
    }
}

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
