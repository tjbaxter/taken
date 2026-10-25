// :app is everything Android: Compose screens themed as Taken, DataStore persistence, and the Robolectric and Roborazzi
// tests that draw the screens for Tom (SPEC-ANDROID 4). Kotlin is built into AGP 9: no kotlin-android plugin
// (https://developer.android.com/build/migrate-to-built-in-kotlin).
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose)
    alias(libs.plugins.roborazzi)
}

android {
    namespace = "com.tombaxter.taken"
    // compileSdk 37 (Android 17 is out); targetSdk 36, which Google Play requires of new apps from 31 August 2026
    // (https://developer.android.com/google/play/requirements/target-sdk); minSdk 28, where Auto Backup is end-to-end
    // encrypted (SPEC-ANDROID 3.2).
    compileSdk = 37

    defaultConfig {
        applicationId = "com.tombaxter.taken"
        minSdk = 28
        targetSdk = 36
        // Android's own first release (SPEC-ANDROID 3.2). android-release.yml sets 1000 + its run number (NEXT 1).
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        debug {
            // A debug install never collides with the Play build.
            applicationIdSuffix = ".debug"
        }
        release {
            // R8 shrinks and optimises the release (https://developer.android.com/build/shrink-code).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests {
            // Robolectric reads the merged resources and the fonts (https://robolectric.org/getting-started/).
            isIncludeAndroidResources = true
        }
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

// Robolectric on Java 17 and later needs these opens (https://robolectric.org/getting-started/), and its native
// graphics want room for the screenshots.
tasks.withType<Test>().configureEach {
    maxHeapSize = "4g"
    // Roborazzi's recommendation for faithful screenshots (https://github.com/takahirom/roborazzi#robolectricpixelcopyrendermode).
    systemProperty("robolectric.pixelCopyRenderMode", "hardware")
    jvmArgs(
        "--add-opens=java.base/java.lang=ALL-UNNAMED",
        "--add-opens=java.base/java.util=ALL-UNNAMED",
        "--add-opens=java.base/java.io=ALL-UNNAMED",
        "--add-opens=java.base/java.net=ALL-UNNAMED",
        "--add-opens=java.base/java.security=ALL-UNNAMED",
        "--add-opens=java.base/java.text=ALL-UNNAMED",
        "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
        "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED",
        "--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED",
    )
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}

dependencies {
    implementation(project(":core"))

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    implementation(libs.activity.compose)
    implementation(libs.core.ktx)
    // The splash screen on every API level, Signal's canvas and the capsule (SPEC-ANDROID 6.1). Sends nothing off the phone.
    implementation(libs.core.splashscreen)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.navigation3.runtime)
    implementation(libs.navigation3.ui)
    implementation(libs.datastore)
    implementation(libs.kotlinx.coroutines.android)
    // The home screen widgets (SPEC-ANDROID 10.1): Glance draws RemoteViews from Compose-style code; WorkManager runs its
    // sessions. Neither sends anything off the phone.
    implementation(libs.glance.appwidget)
    implementation(libs.work.runtime.ktx)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.ext.junit)
    // Glance's own unit tests of a widget's content (runGlanceAppWidgetUnitTest,
    // https://developer.android.com/develop/ui/compose/glance/testing).
    testImplementation(libs.glance.appwidget.testing)
    // ComponentActivity in the debug manifest, which the Compose test rule launches under Robolectric.
    debugImplementation(libs.compose.ui.test.manifest)
}
