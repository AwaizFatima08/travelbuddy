plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: the upload keystore lives OUTSIDE the repo and its password is read from
// environment variables typed in the terminal at build time (scripts/build-release.sh).
// Nothing secret is ever written to a file.
val keystorePath = System.getenv("TB_KEYSTORE")
    ?: "${rootDir}/../../../travelbuddy-secrets/travelbuddy-upload.jks"
val storePass: String? = System.getenv("TB_STORE_PASSWORD")
val keyPass: String? = System.getenv("TB_KEY_PASSWORD") ?: storePass

android {
    namespace = "com.homilabs.travelbuddy"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // java.time etc. on Android 7 (minSdk 24); required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Same package as V1, so v2 ships as an update to the existing Play listing.
        applicationId = "com.homilabs.travelbuddy"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (storePass != null && file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = storePass
                keyAlias = "upload"
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = if (storePass != null) signingConfigs.getByName("upload")
                            else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
