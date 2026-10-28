plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "eu.bortle.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "eu.bortle.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Store builds sign with the upload key the allskyhub hub keeps for this app and hands
    // to the build through the environment (as allskyhub's own app does); never a file in
    // this repository. Without it a release build signs with the debug key, so
    // `flutter run --release` and tool/build_test_apk.sh work.
    val keystore = System.getenv("BORTLE_KEYSTORE") ?: System.getenv("CM_KEYSTORE_PATH")
    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = File(keystore)
                storePassword = System.getenv("BORTLE_KEYSTORE_PASSWORD") ?: System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("BORTLE_KEY_ALIAS") ?: System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("BORTLE_KEY_PASSWORD") ?: System.getenv("CM_KEY_PASSWORD")
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
