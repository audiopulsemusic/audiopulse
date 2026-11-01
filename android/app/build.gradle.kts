import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keyStoreFile = if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    val storeFilePath = keystoreProperties["storeFile"] as? String
    if (storeFilePath != null) {
        val f = file(storeFilePath)
        if (f.exists()) f else rootProject.file(storeFilePath).takeIf { it.exists() }
    } else null
} else null

android {
    namespace = "com.audiopulse.audiopulse_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.audiopulse.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyStoreFile != null && keyStoreFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keyStoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keyStoreFile == null || !keyStoreFile.exists()) {
                val isReleaseTask = gradle.startParameter.taskNames.any {
                    it.contains("Release", ignoreCase = true)
                }
                if (isReleaseTask) {
                    throw GradleException(
                        "Keystore de production introuvable (android/key.properties -> upload-keystore.jks). " +
                        "Impossible de signer le build release avec la clé debug."
                    )
                }
            }
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Exigence IzzyOnDroid / F-Droid : désactive l'injection du bloc binaire
    // chiffré propriétaire Google Play (DEPENDENCY_INFO_BLOCK) dans l'APK.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

flutter {
    source = "../.."
}
