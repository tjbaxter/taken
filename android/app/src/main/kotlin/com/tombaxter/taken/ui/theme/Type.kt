package com.tombaxter.taken.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.tombaxter.taken.R

/**
 * Geist for every word and Geist Mono for times and counts (SIL OFL, bundled from Taken/Fonts). The iPhone's point sizes
 * become the same `sp`, so text scales with the person's font size (SPEC-ANDROID 6.1).
 */
object TakenType {
    val sans = FontFamily(
        Font(R.font.geist_regular, FontWeight.Normal),
        Font(R.font.geist_medium, FontWeight.Medium),
        Font(R.font.geist_semibold, FontWeight.SemiBold),
    )

    val mono = FontFamily(
        Font(R.font.geist_mono_regular, FontWeight.Normal),
        Font(R.font.geist_mono_medium, FontWeight.Medium),
        Font(R.font.geist_mono_semibold, FontWeight.SemiBold),
    )

    fun sans(size: Int, weight: FontWeight = FontWeight.Normal, lineHeight: TextUnit = TextUnit.Unspecified): TextStyle =
        TextStyle(fontFamily = sans, fontWeight = weight, fontSize = size.sp, lineHeight = lineHeight)

    fun mono(size: Int, weight: FontWeight = FontWeight.Medium): TextStyle =
        TextStyle(fontFamily = mono, fontWeight = weight, fontSize = size.sp)

    /** The Add sheet's chips: mono caps, letter-spaced 8% of the size. */
    fun monoCaps(size: Int, weight: FontWeight = FontWeight.Medium): TextStyle =
        TextStyle(fontFamily = mono, fontWeight = weight, fontSize = size.sp, letterSpacing = 0.08.em)

    /** Every Material component's text in Geist, never Material's default font. */
    val typography: Typography = Typography().let { base ->
        Typography(
            displayLarge = base.displayLarge.copy(fontFamily = sans),
            displayMedium = base.displayMedium.copy(fontFamily = sans),
            displaySmall = base.displaySmall.copy(fontFamily = sans),
            headlineLarge = base.headlineLarge.copy(fontFamily = sans, fontWeight = FontWeight.SemiBold),
            headlineMedium = base.headlineMedium.copy(fontFamily = sans, fontWeight = FontWeight.SemiBold),
            headlineSmall = base.headlineSmall.copy(fontFamily = sans, fontWeight = FontWeight.SemiBold),
            titleLarge = base.titleLarge.copy(fontFamily = sans, fontWeight = FontWeight.SemiBold),
            titleMedium = base.titleMedium.copy(fontFamily = sans, fontWeight = FontWeight.Medium),
            titleSmall = base.titleSmall.copy(fontFamily = sans, fontWeight = FontWeight.Medium),
            bodyLarge = base.bodyLarge.copy(fontFamily = sans, fontSize = 17.sp),
            bodyMedium = base.bodyMedium.copy(fontFamily = sans, fontSize = 15.sp),
            bodySmall = base.bodySmall.copy(fontFamily = sans, fontSize = 14.sp),
            labelLarge = base.labelLarge.copy(fontFamily = sans, fontWeight = FontWeight.Medium, fontSize = 15.sp),
            labelMedium = base.labelMedium.copy(fontFamily = sans, fontWeight = FontWeight.Medium),
            labelSmall = base.labelSmall.copy(fontFamily = sans, fontWeight = FontWeight.Medium),
        )
    }
}
