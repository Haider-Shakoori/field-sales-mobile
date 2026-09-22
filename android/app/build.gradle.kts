import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

fun releaseSigningValue(environmentName: String, propertyName: String): String? {
    return System.getenv(environmentName)
        ?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
}

val releaseStoreFile = releaseSigningValue("FIELD_SALES_KEYSTORE_FILE", "storeFile")
val releaseStorePassword =
    releaseSigningValue("FIELD_SALES_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = releaseSigningValue("FIELD_SALES_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = releaseSigningValue("FIELD_SALES_KEY_PASSWORD", "keyPassword")
val releaseSigningConfigured = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.businessos.fieldpulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.businessos.fieldpulse"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { task ->
        task.path.startsWith(":app:") &&
            task.name.contains("Release", ignoreCase = true)
    }

    if (releaseRequested && !releaseSigningConfigured) {
        throw GradleException(
            "Release signing is not configured. Set FIELD_SALES_KEYSTORE_FILE, " +
                "FIELD_SALES_KEYSTORE_PASSWORD, FIELD_SALES_KEY_ALIAS and " +
                "FIELD_SALES_KEY_PASSWORD, or create android/key.properties.",
        )
    }
}

flutter {
    source = "../.."
}
