// :app is everything Android: Compose screens themed as Taken, DataStore persistence, and the Robolectric and Roborazzi
// tests that draw the screens for Tom (SPEC-ANDROID 4). Kotlin is built into AGP 9: no kotlin-android plugin
// (https://developer.android.com/build/migrate-to-built-in-kotlin).
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose)
    alias(libs.plugins.roborazzi)
}

// The Play version code (SPEC-ANDROID 3.2). android-release.yml passes its own (an offset plus the run number, so every
// upload is higher than the last); every other build is 1. Play takes nothing above 2100000000
// (https://developer.android.com/studio/publish/versioning).
val playVersionCode: Int = providers.gradleProperty("takenVersionCode").orNull?.let { value ->
    val code = requireNotNull(value.toIntOrNull()) { "takenVersionCode must be a whole number, not '$value'" }
    require(code in 1..2_100_000_000) { "takenVersionCode $code is outside Play's 1 to 2100000000" }
    code
} ?: 1

// The upload key (SPEC-ANDROID 16). android-release.yml decodes it from its secrets into the runner's temp directory and
// hands the path, the alias and the password over in environment variables, so no signing detail is in a build file
// (Google: move signing information out of the build files, https://developer.android.com/studio/publish/app-signing ;
// GitHub: pass secrets through environment variables, never the command line,
// https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets). One password for the
// store and the key, as Google advises on the same signing page. Without these variables the release bundle is
// unsigned, as android.yml builds it.
val uploadStoreFile: String? = providers.environmentVariable("TAKEN_UPLOAD_STORE_FILE").orNull?.takeIf { it.isNotBlank() }

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
        // Android's own first release (SPEC-ANDROID 3.2), the only place the version name is written.
        versionCode = playVersionCode
        versionName = "1.0.0"
    }

    signingConfigs {
        if (uploadStoreFile != null) {
            create("upload") {
                val password = providers.environmentVariable("TAKEN_UPLOAD_STORE_PASSWORD").orNull
                val alias = providers.environmentVariable("TAKEN_UPLOAD_KEY_ALIAS").orNull
                require(!password.isNullOrEmpty()) { "TAKEN_UPLOAD_STORE_PASSWORD is not set" }
                require(!alias.isNullOrEmpty()) { "TAKEN_UPLOAD_KEY_ALIAS is not set" }
                storeFile = file(uploadStoreFile)
                // The keystore is PKCS12, the format openssl wrote it in (SPEC-ANDROID 16).
                storeType = "PKCS12"
                storePassword = password
                keyAlias = alias
                keyPassword = password
            }
        }
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
            if (uploadStoreFile != null) signingConfig = signingConfigs.getByName("upload")
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
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.navigation3.runtime)
    implementation(libs.navigation3.ui)
    implementation(libs.datastore)
    // Google Play Billing (SPEC-ANDROID 9). The library brings its own BILLING permission and Play services pieces.
    implementation(libs.billing.ktx)
    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.ext.junit)
    // ComponentActivity in the debug manifest, which the Compose test rule launches under Robolectric.
    debugImplementation(libs.compose.ui.test.manifest)
}
