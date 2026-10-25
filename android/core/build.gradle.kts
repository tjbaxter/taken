import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// :core is plain Kotlin on the JVM with no Android dependency at all: the iPhone's Shared/ rules, ported line for line,
// and the iPhone's XCTest cases carried over as JUnit tests (SPEC-ANDROID 4 and 8). It runs in seconds on any JVM.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        optIn.add("kotlinx.serialization.ExperimentalSerializationApi")
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test.junit)
}

tasks.test {
    useJUnit()
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
