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
import com.tombaxter.taken.billing.PlayBilling
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.data.DataStorePersistence
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
 * https://developer.android.com/training/dependency-injection/manual): the stores, the persistence over them, the one
 * Google Play Billing client (SPEC-ANDROID 9.3; it connects and asks nothing yet), and Taken Pro's answer, which stays
 * [ProSource.untilBilling] until NEXT 2 reads Play's purchases.
 */
class AppContainer(context: Context) {
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val stores = TakenStores(context)
    val persistence = DataStorePersistence(stores, scope)
    val billing = PlayBilling(context)
    val pro: ProSource = ProSource.untilBilling
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
            val photo = withContext(Dispatchers.IO) { com.tombaxter.taken.data.PhotoFile.read(stores.photoFile) }
            val loaded = AppModel(
                persistence = container.persistence,
                initialState = state,
                initialLedger = ledger,
                initialProfile = profile,
                initialPhoto = photo,
                pro = container.pro,
                clockNow = { Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS) },
            )
            model = loaded
            launch { stores.stack.data.collect { loaded.adopt(it) } }
            launch { stores.ledger.data.collect { file -> file.ledger?.let(loaded::adoptLedger) } }
        }
    }

    companion object {
        fun factory(container: AppContainer): ViewModelProvider.Factory = viewModelFactory {
            initializer { AppViewModel(container) }
        }
    }
}
