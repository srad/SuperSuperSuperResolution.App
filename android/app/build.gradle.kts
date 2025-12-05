plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Version variables for easy updates
val liteRtVersion = "16.4.0"
val liteRtGpuVersion = "16.4.0"
val coroutinesVersion = "1.10.2"

android {
    namespace = "com.github.srad.magicresolution"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"//flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.github.srad.magicresolution"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // You can add this line to enable code shrinking, which is likely what triggered the R8 error.
            isMinifyEnabled = true

            // This line tells R8 to use the default optimization rules and your custom rules.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // LiteRT (TFLite) with Google Play Services
    implementation("com.google.android.gms:play-services-tflite-java:$liteRtVersion")
    implementation("com.google.android.gms:play-services-tflite-support:$liteRtVersion")
    implementation("com.google.android.gms:play-services-tflite-gpu:$liteRtGpuVersion")

    // TFLite GPU delegate plugin (works with Play Services without conflicts)
    implementation("org.tensorflow:tensorflow-lite-gpu-delegate-plugin:0.4.4")

    // AutoValue - needed at compile time for TensorFlow Lite annotations
    compileOnly("com.google.auto.value:auto-value-annotations:1.11.1")

    // Kotlin coroutines for async operations
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$coroutinesVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:$coroutinesVersion")
}

flutter {
    source = "../.."
}
