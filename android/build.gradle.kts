// Every plugin the modules use is listed here once, so the build script classpath is the same for all of them (Now in
// Android does the same: https://github.com/android/nowinandroid/blob/main/build.gradle.kts). Listing the Kotlin JVM
// plugin here also puts Kotlin 2.4.21 on the classpath that AGP 9's built-in Kotlin uses.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.compose) apply false
    alias(libs.plugins.roborazzi) apply false
}
