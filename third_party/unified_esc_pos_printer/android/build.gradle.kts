group = "com.elriztechnology.unified_esc_pos_printer"
version = "1.0"

plugins {
    id("com.android.library")
}

// Upstream skipped this for "AGP 9+ built-in Kotlin support", but on this
// project's AGP 9.1.0 that leaves UnifiedEscPosPrinterPlugin.kt uncompiled
// (compileDebugKotlin never runs), so GeneratedPluginRegistrant.java fails
// with "cannot find symbol: class UnifiedEscPosPrinterPlugin". Applying it
// unconditionally fixes that; the root project's settings.gradle.kts already
// declares org.jetbrains.kotlin.android's version, so no version is needed here.
apply(plugin = "org.jetbrains.kotlin.android")

android {
    namespace = "com.elriztechnology.unified_esc_pos_printer"
    // Bumped from the upstream 34: this package's own network_info_plus (>=7.0.0
    // <9.0.0, resolves to 8.2.1) requires compileSdk 36+ from anything that
    // depends on it, including this module itself.
    compileSdk = 36

    defaultConfig {
        minSdk = 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

project.extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
}
