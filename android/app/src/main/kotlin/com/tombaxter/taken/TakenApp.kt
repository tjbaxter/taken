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
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.reminders.PlannedTrialReminder
import com.tombaxter.taken.core.reminders.ReminderSnapshot
import com.tombaxter.taken.core.reminders.TrialReminderSlot
import com.tombaxter.taken.core.todo.TodoNotificationScheduler
import com.tombaxter.taken.data.DataStorePersistence
import com.tombaxter.taken.data.DataStoreTodoPersistence
import com.tombaxter.taken.data.LedgerFile
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
import kotlinx.coroutines.withTimeoutOrNull
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
    /** Taken Pro's answer: Google Play's in release builds, on for good in debug ([BuildWiring]). Tests hold their own. */
    var pro: ProSource = BuildWiring.pro(context, persistence, scope)
        internal set

    init {
        // pro.json as it is written: the cached answer before Play's, the trials this phone recorded, the prices.
        scope.launch {
            stores.ledger.data.catch { }.collect { pro.adoptLedger(it.ledger) }
        }
    }

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
     * moments the day changes under them. `refresh()` is their one entry point; Pro changing calls it through
     * [proChanged] (SPEC-ANDROID 9.7).
     */
    val surfaces = Surfaces(
        context = app,
        stores = stores,
        pro = { pro },
        clock = { clock() },
        zone = { zone() },
        scope = scope,
        recheckPro = { recheckProIfStale() },
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
     * Pro itself changed (a purchase, a renewal seen, a cancellation, a refund, a trial that converted): the widgets, the
     * tile and the reminders follow it (SPEC-ANDROID 9.7), so a locked widget opens up, the nudge's window moves and the
     * trial reminder is planned or withdrawn. `AppModel.onProChanged` calls it, and so does a widget's, the tile's or a
     * nudge's recheck that changed Pro with no screen open ([ProRecheck]).
     */
    fun proChanged() {
        scope.launch { surfaces.refresh() }
        scope.launch { reminders.rebuild() }
    }

    /**
     * Asks Google Play again when the cached answer is a subscription past its check horizon (`PlayEntitlement.needsCheck`),
     * before the widgets, the tile or the nudge are worked out from it. On Android that horizon is not the end of the period
     * paid for (SPEC-ANDROID 9.4): a cancelled plan is still returned by Play "until it expires", and access must not be
     * removed while the person is still entitled to it (https://developer.android.com/google/play/billing/lifecycle/subscriptions).
     * So an expired horizon means "ask Play", never "ended": the surfaces' refresh (their alarm at the horizon, a restart,
     * every write) and every reminder rebuild (an alarm, a restart, a write) ask here first, inside the broadcast's time.
     * `queryPurchasesAsync` needs no activity. A change of Pro runs [proChanged]; Play's answer is written to pro.json either
     * way, which moves the horizon on. [Own choice: where the background recheck runs, and its 5 s bound, which keeps a
     * rebuild well inside a broadcast's time.]
     */
    internal suspend fun recheckProIfStale() {
        val status = pro.status ?: try {
            stores.ledger.data.first().ledger?.status
        } catch (e: IOException) {
            return
        }
        if (!PlayEntitlement.needsCheck(status, clock())) return
        val changed = withTimeoutOrNull(RECHECK_TIMEOUT_MS) { pro.refresh() } ?: false
        if (changed) proChanged()
    }

    /**
     * What the reminders are planned from, read from the files. Pro's answer is the source's, or pro.json's cached one
     * while the source has none yet (a receiver in a fresh process), as the iPhone's surfaces read the ledger; Play is asked
     * first when that answer's horizon has passed ([recheckProIfStale]), so a nudge is never dropped on a guess.
     */
    private suspend fun reminderSnapshot(): ReminderSnapshot? = try {
        recheckProIfStale()
        val stack = stores.stack.data.first()
        val tasks = stores.todos.data.first().tasks
        val ledger = stores.ledger.data.first().ledger
        val status = pro.status ?: ledger?.status
        val access = ProGate.access(
            status, settled = true, legacyLog = false, hasLogged = ProGate.hasLogged(stack, ledger), now = clock(),
        )
        ReminderSnapshot(stack, tasks, ProGate.nudgeWindow(access, status), zone(), trialReminder(status, ledger, stack))
    } catch (e: IOException) {
        null
    }

    /**
     * Taken Pro's trial reminder for one rebuild (SPEC-ANDROID 9.7 and 10.4): the Pro lane's plan over the files just read
     * ([PlannedTrialReminder]), its mark written to pro.json once it is posted, inside the rebuild, so a receiver's
     * broadcast never ends before it.
     */
    private fun trialReminder(status: ProStatus?, ledger: ProLedger?, stack: StackState): TrialReminderSlot =
        PlannedTrialReminder(status, ledger, stack, zone()) { mark ->
            try {
                stores.ledger.updateData { file -> LedgerFile(ProLedgers.withTrialReminder(file.ledger, mark)) }
            } catch (e: IOException) {
                // pro.json cannot be written now. The reminder's moment has passed, so the next rebuild plans none; only
                // a later nudge time on the same day could plan it again.
            }
        }

    companion object {
        /** How long a background recheck waits for Google Play before the cached answer stands. [Own choice] */
        const val RECHECK_TIMEOUT_MS = 5_000L
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
            // Pro itself changed: the widgets, the tile and the alarms follow it (SPEC-ANDROID 9.7).
            loaded.onProChanged = container::proChanged
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
