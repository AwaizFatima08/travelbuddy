plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
}

// Release signing: the keystore lives OUTSIDE the repo and the passwords are
// read from environment variables typed in the terminal at build time.
// Nothing secret is ever written to a file.
val keystorePath = System.getenv("TB_KEYSTORE")
    ?: "${rootDir}/../travelbuddy-secrets/travelbuddy-upload.jks"
val storePass: String? = System.getenv("TB_STORE_PASSWORD")
val keyPass: String? = System.getenv("TB_KEY_PASSWORD") ?: storePass

android {
    namespace = "com.homilabs.travelbuddy"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.homilabs.travelbuddy"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
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
        debug {
            // ./gradlew installDebug -PtbEmulator  → talk to the local Firebase emulator
            // (via `adb reverse`), so tests never touch the real project.
            buildConfigField("boolean", "USE_EMULATOR", if (project.hasProperty("tbEmulator")) "true" else "false")
        }
        release {
            buildConfigField("boolean", "USE_EMULATOR", "false")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (storePass != null) signingConfig = signingConfigs.getByName("upload")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // java.time on Android 7 (minSdk 24)
        isCoreLibraryDesugaringEnabled = true
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    val composeBom = platform("androidx.compose:compose-bom:2025.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-process:2.9.4")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.biometric:biometric:1.1.0")

    implementation(platform("com.google.firebase:firebase-bom:34.4.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
}
