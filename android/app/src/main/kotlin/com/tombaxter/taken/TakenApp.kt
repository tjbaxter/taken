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
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.todo.TodoNotificationScheduler
import com.tombaxter.taken.data.DataStorePersistence
import com.tombaxter.taken.data.DataStoreTodoPersistence
import com.tombaxter.taken.data.TakenStores
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

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
 * Pro's answer (until Google Play Billing, NEXT 2), and the to-dos' due-time notifications.
 */
class AppContainer(context: Context) {
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val stores = TakenStores(context)
    val persistence = DataStorePersistence(stores, scope)
    val todoPersistence = DataStoreTodoPersistence(stores, scope)
    val pro: ProSource = ProSource.untilBilling

    /**
     * Where the To-do tab hands its tasks after every change and every return to the front (SPEC-ANDROID 10.4). The
     * Reminders step (NEXT 3) replaces this with one that posts on the "To-do due times" channel through one inexact
     * alarm for the soonest of `TodoNotifications.plan`; until then nothing is posted.
     */
    val todoNotifications: TodoNotificationScheduler = TodoNotificationScheduler.none
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
            val todos = stores.todos.data.first()
            val photo = withContext(Dispatchers.IO) { com.tombaxter.taken.data.PhotoFile.read(stores.photoFile) }
            val clockNow = { Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS) }
            // The To-do tab's model lives in the app's scope, not this ViewModel's: a note being saved when the activity
            // finishes (back, a swipe home) still reaches its file.
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
                todoModel = todo,
            )
            model = loaded
            launch { stores.stack.data.collect { loaded.adopt(it) } }
            launch { stores.ledger.data.collect { file -> file.ledger?.let(loaded::adoptLedger) } }
            launch { stores.todos.data.collect { todo.adopt(it) } }
        }
    }

    companion object {
        fun factory(container: AppContainer): ViewModelProvider.Factory = viewModelFactory {
            initializer { AppViewModel(container) }
        }
    }
}
