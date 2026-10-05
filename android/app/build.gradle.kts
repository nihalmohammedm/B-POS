import java.util.Properties

val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Neutral build namespace shared by both flavors — Android still requires one
    // even though pos/captain each ship under their own real applicationId below.
    namespace = "com.bpos.app"
    // network_info_plus (pulled in transitively by unified_esc_pos_printer, for LAN
    // printer subnet scanning) requires compileSdk 36+; Flutter's own default here
    // (flutter.compileSdkVersion) currently resolves lower, so it's pinned explicitly.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two installable apps from one codebase: BPOS (Main POS, -t lib/main_pos.dart)
    // and BPOS Captain (-t lib/main_captain.dart). Different applicationId means
    // they can be installed side by side on the same device.
    flavorDimensions += "app"
    productFlavors {
        create("pos") {
            dimension = "app"
            applicationId = "com.bpos.app"
            resValue("string", "app_name", "BPOS")
        }
        create("captain") {
            dimension = "app"
            applicationId = "com.bpos.captain"
            resValue("string", "app_name", "BPOS Captain")
        }
        // Kitchen display (-t lib/main_kitchen.dart): shows KOTs, rings on new ones.
        create("kitchen") {
            dimension = "app"
            applicationId = "com.bpos.kitchen"
            resValue("string", "app_name", "BPOS Kitchen")
        }
    }

    // Release key lives outside git: android/key.properties + the .jks it points to.
    // Without key.properties the release build falls back to the debug key.
    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
