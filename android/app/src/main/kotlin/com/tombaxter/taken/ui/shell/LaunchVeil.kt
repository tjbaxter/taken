package com.tombaxter.taken.ui.shell

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import com.tombaxter.taken.core.theme.Launch
import com.tombaxter.taken.core.theme.Look

/**
 * The launch's veil (SPEC-ANDROID 6.1, :core's [Launch]). The splash screen hands over on Signal's canvas; a light look
 * then fades in from that canvas over 0.4 s, easing out, as the iPhone's RootView does, instead of cutting from dark to
 * light. A dark look starts with no veil. Once per new activity: a rotation, fold or resize keeps the screen as it is (the
 * veil's state is saved), and with animations removed in Android's settings Compose ends the fade at once. The veil takes
 * no touches: what is under it already works.
 */
@Composable
fun LaunchVeil(look: Look, content: @Composable () -> Unit) {
    var pending by rememberSaveable { mutableStateOf(Launch.veiled(look)) }
    val veil = remember { Animatable(if (pending) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (!pending) return@LaunchedEffect
        // Saved as done before the fade runs, so a rotation in the middle of it does not veil the screen again.
        pending = false
        veil.animateTo(0f, tween(Launch.VEIL_MILLIS, easing = EaseOut))
    }
    Box(Modifier.fillMaxSize()) {
        content()
        if (veil.value > 0f) {
            Box(
                Modifier
                    .fillMaxSize()
                    .testTag("launch-veil")
                    .graphicsLayer { alpha = veil.value }
                    .background(Color((0xFF000000L or Launch.CANVAS).toInt())),
            )
        }
    }
}
