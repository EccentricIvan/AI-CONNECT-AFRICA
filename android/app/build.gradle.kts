import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — reads android/key.properties when present.
// Without it, release builds fall back to debug signing so dev still works.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.aiconnectafrica.ai_connect_africa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aiconnectafrica.ai_connect_africa"
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // fllama's Android llama.cpp binding requires API 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Keep large model assets uncompressed so AssetManager can stream them
    // efficiently out of the fat release APK on first launch.
    androidResources {
        noCompress += listOf("litertlm", "gguf")
    }

    packaging {
        jniLibs {
            // Native libraries are extracted to disk (extractNativeLibs=true).
            // LiteRT-LM's GPU/NPU accelerators (libLiteRtGpuAccelerator.so,
            // the Qualcomm QNN dispatch libraries…) are dlopen'ed by name
            // from the app's native library directory, which only exists on
            // disk when the libraries are extracted.
            useLegacyPackaging = true

            // Android runs LiteRT-LM only (model_runtime_policy.dart); the
            // llama.cpp libraries the llm_llamacpp build hook adds for the
            // desktop runtime are dead weight here (~70 MB, 44 MB of it the
            // Vulkan backend), so they are left out of the APK.
            excludes += listOf(
                "lib/*/libllama.so",
                "lib/*/libggml.so",
                "lib/*/libggml-base.so",
                "lib/*/libggml-cpu*.so",
                "lib/*/libggml-vulkan.so",
                "lib/*/libomp.so",
            )
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
