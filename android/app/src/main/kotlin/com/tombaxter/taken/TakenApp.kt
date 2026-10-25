package com.tombaxter.taken

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.reminders.ReminderSnapshot
import com.tombaxter.taken.core.reminders.TrialReminderSlot
import com.tombaxter.taken.core.todo.TodoNotificationScheduler
import com.tombaxter.taken.data.DataStorePersistence
import com.tombaxter.taken.data.DataStoreTodoPersistence
import com.tombaxter.taken.data.TakenStores
import com.tombaxter.taken.notify.AndroidAlarms
import com.tombaxter.taken.notify.AndroidNotifications
import com.tombaxter.taken.notify.PreferenceArmedMoments
import com.tombaxter.taken.notify.ReminderChannels
import com.tombaxter.taken.notify.ReminderScheduler
import com.tombaxter.taken.notify.RescheduleReceiver
import com.tombaxter.taken.widget.Surfaces
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.time.Instant
import java.time.ZoneId

/** The process: one AppContainer, so every file has exactly one DataStore (SPEC-ANDROID 5.1). */
class TakenApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

/**
 * Taken's few objects, by hand (SPEC-ANDROID 3.1: no DI framework for a graph this small,
 * https://developer.android.com/training/dependency-injection/manual): the stores, the persistence over them, Taken
 * Pro's answer, the reminders (SPEC-ANDROID 10.4) and the widgets and the tile (10.1 and 10.2). A release build asks
 * Google Play through the one BillingClient of the process ([BuildWiring], SPEC-ANDROID 9.3); a debug build, whose
 * `.debug` package Play sells nothing to, reads Pro as on.
 */
class AppContainer(context: Context) {
    private val app: Context = context.applicationContext
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val stores = TakenStores(context)
    val persistence = DataStorePersistence(stores, scope)
    val todoPersistence = DataStoreTodoPersistence(stores, scope)
    val weightPersistence = com.tombaxter.taken.data.DataStoreWeightPersistence(stores, scope)
    val pro: ProSource = BuildWiring.pro(context, persistence, scope)

    init {
        // pro.json as it is written: the cached answer before Play's, the trials this phone recorded, the prices.
        scope.launch {
            stores.ledger.data.catch { }.collect { pro.adoptLedger(it.ledger) }
        }
    }

    /**
     * Taken Pro's trial reminder, delivered by the reminders on its own channel once the integrator plugs the Pro lane's
     * plan in here (`TrialReminder.plan` and its mark in pro.json, SPEC-ANDROID 9.7 and 10.4). Until then it plans none.
     */
    var trialReminders: TrialReminderSlot = TrialReminderSlot.none

    /** The moment and the time zone the reminders plan with: the phone's. Tests hold their own. */
    internal var clock: () -> Instant = { Instant.now() }
    internal var zone: () -> ZoneId = { ZoneId.systemDefault() }

    /** Taken's notifications, posted and withdrawn through Android's NotificationManager. */
    val notifications = AndroidNotifications(app)

    /** The reminders: the nudge, the trial reminder and the to-dos' due times, one inexact alarm per kind. */
    val reminders = ReminderScheduler(
        snapshot = ::reminderSnapshot,
        alarms = AndroidAlarms(app),
        notifications = notifications,
        armed = PreferenceArmedMoments(app),
        clock = { clock() },
        onArmed = { any ->
            remindersArmed = any
            restartReceiverFollows()
        },
    )

    /**
     * The home screen widgets and the Take all tile (SPEC-ANDROID 10.1 and 10.2), redrawn after every write and at the
     * moments the day changes under them. `refresh()` is their one entry point; Pro changing calls it through the Pro
     * lane's `AppModel.onProChanged` once the integrator connects them (SPEC-ANDROID 9.7).
     */
    val surfaces = Surfaces(
        context = app,
        stores = stores,
        pro = { pro },
        clock = { clock() },
        zone = { zone() },
        scope = scope,
        onArmed = { any ->
            surfacesArmed = any
            restartReceiverFollows()
        },
    )

    /** What Today and Profile ask of the widgets and the tile. */
    val surfaceHost: SurfaceHost = AndroidSurfaceHost(app, surfaces, scope)

    @Volatile
    private var remindersArmed = false

    @Volatile
    private var surfacesArmed = false

    /**
     * The receiver for restarts, clock and time zone changes and updates is on while a reminder or a surface's refresh is
     * armed, and off when neither is (Google's alarm guide enables its boot receiver only while needed).
     */
    private fun restartReceiverFollows() {
        synchronized(this) { RescheduleReceiver.setEnabled(app, remindersArmed || surfacesArmed) }
    }

    /**
     * Where the To-do tab hands its tasks after every change and every return to the front (SPEC-ANDROID 10.4): a
     * rebuild of the reminders, which reads todos.json. The tasks handed over are on their way there, and the file's
     * change starts another rebuild with what was saved, so a save that failed never leaves a due time behind.
     */
    val todoNotifications: TodoNotificationScheduler = TodoNotificationScheduler { reminders.rebuild() }

    init {
        // Channels exist before anything is posted: "execute this code when your app starts"
        // (https://developer.android.com/develop/ui/views/notifications/build-notification).
        ReminderChannels.ensure(app)
        // Every write, from the screen or from a notification's TAKE ALL, reaches taken.json or todos.json first; each new
        // file rebuilds the reminders (the iPhone's `Sync.afterWrite`). The first values rebuild once per process start.
        scope.launch {
            merge(stores.stack.data.map { }, stores.todos.data.map { })
                .catch { }
                .collect { reminders.rebuild() }
        }
        // The widgets and the tile follow the same writes, and pro.json's too (a refused log, Pro's cached answer): the
        // iPhone's `Sync.afterWrite` reloads its widget timelines and its control after every write.
        scope.launch {
            merge(stores.stack.data.map { }, stores.todos.data.map { }, stores.ledger.data.map { })
                .catch { }
                .collect { surfaces.refresh() }
        }
    }

    /**
     * What the reminders are planned from, read from the files. Pro's answer is the source's, or pro.json's cached one
     * while the source has none yet (a receiver in a fresh process), as the iPhone's surfaces read the ledger.
     */
    private suspend fun reminderSnapshot(): ReminderSnapshot? = try {
        val stack = stores.stack.data.first()
        val tasks = stores.todos.data.first().tasks
        val ledger = stores.ledger.data.first().ledger
        val status = pro.status ?: ledger?.status
        val access = ProGate.access(
            status, settled = true, legacyLog = false, hasLogged = ProGate.hasLogged(stack, ledger), now = clock(),
        )
        ReminderSnapshot(stack, tasks, ProGate.nudgeWindow(access, status), zone(), trialReminders)
    } catch (e: IOException) {
        null
    }
}

/**
 * Loads the files once, then holds the AppModel across rotations. The files' later changes (a write from elsewhere) are
 * adopted when no write of the app's own is on its way.
 */
class AppViewModel(private val container: AppContainer) : ViewModel() {
    var model: AppModel? by mutableStateOf(null)
        private set

    init {
        viewModelScope.launch {
            val stores = container.stores
            val state = stores.stack.data.first()
            val ledger = stores.ledger.data.first().ledger ?: ProLedger(firstSeenAt = Instant.now()).also { fresh ->
                // The ledger is written fresh the first time Taken runs, as on the iPhone; never legacy on Android.
                container.persistence.updateLedger { it ?: fresh }
            }
            val profile = stores.profile.data.first()
            val weights = stores.weights.data.first()
            val todos = stores.todos.data.first()
            val photo = withContext(Dispatchers.IO) { com.tombaxter.taken.data.PhotoFile.read(stores.photoFile) }
            val clockNow = { Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS) }
            // The To-do tab's model lives in the app's scope, not this ViewModel's: a note being saved when the activity
            // finishes (back, a swipe home) still reaches its file.
            val notifications = NotificationsModel(
                rebuild = { container.scope.launch { container.reminders.rebuild() } },
                withdraw = container.notifications::withdraw,
            )
            val todo = TodoModel(
                persistence = container.todoPersistence,
                initialState = todos,
                clockNow = clockNow,
                notifications = container.todoNotifications,
                scope = container.scope,
            )
            val loaded = AppModel(
                persistence = container.persistence,
                initialState = state,
                initialLedger = ledger,
                initialProfile = profile,
                initialPhoto = photo,
                pro = container.pro,
                clockNow = clockNow,
                scope = viewModelScope,
                weightModel = WeightModel(
                    persistence = container.weightPersistence,
                    initialState = weights,
                    clockNow = clockNow,
                ),
                todoModel = todo,
                notificationsModel = notifications,
                surfaceHost = container.surfaceHost,
            )
            model = loaded
            launch { stores.stack.data.collect { loaded.adopt(it) } }
            launch { stores.ledger.data.collect { file -> file.ledger?.let(loaded::adoptLedger) } }
            launch { stores.weights.data.collect { loaded.weight.adopt(it) } }
            launch { stores.todos.data.collect { todo.adopt(it) } }
        }
    }

    companion object {
        fun factory(container: AppContainer): ViewModelProvider.Factory = viewModelFactory {
            initializer { AppViewModel(container) }
        }
    }
}
