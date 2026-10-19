import java.util.Properties

plugins {
    id("com.android.application")
    // android.builtInKotlin=false (gradle.properties): Kotlin is applied explicitly.
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from outside the repository: android/key.properties (git-ignored,
// see key.properties.example) or the WATTBYTE_KEYSTORE_* environment variables used by CI.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    (keyProps.getProperty(prop) ?: System.getenv(env))?.takeIf { it.isNotBlank() }
val releaseStoreFile = signingValue("storeFile", "WATTBYTE_KEYSTORE_FILE")
// Which of the four values are absent (names only, never values).
val missingSigningValues = listOfNotNull(
    "storeFile (WATTBYTE_KEYSTORE_FILE)".takeIf { releaseStoreFile == null },
    "storePassword (WATTBYTE_KEYSTORE_PASSWORD)".takeIf { signingValue("storePassword", "WATTBYTE_KEYSTORE_PASSWORD") == null },
    "keyAlias (WATTBYTE_KEY_ALIAS)".takeIf { signingValue("keyAlias", "WATTBYTE_KEY_ALIAS") == null },
    "keyPassword (WATTBYTE_KEY_PASSWORD)".takeIf { signingValue("keyPassword", "WATTBYTE_KEY_PASSWORD") == null },
)
val hasReleaseKey = missingSigningValues.isEmpty()
// Opt-in for a deliberately UNSIGNED release artifact (for example to run R8 in CI without secrets).
val allowUnsignedRelease = System.getenv("WATTBYTE_ALLOW_UNSIGNED_RELEASE") == "1" ||
    project.findProperty("wattbyte.allowUnsignedRelease") == "true"

android {
    namespace = "pl.wattbyte.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "pl.wattbyte.app"
        // NetworkStatsManager without subscriberId (all SIMs) needs API 29.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "WATTBYTE_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "WATTBYTE_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "WATTBYTE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // R8 shrinking/obfuscation and resource shrinking. Flutter's Gradle plugin already enables both
            // for release; they are stated here so the release configuration is readable in one place.
            // Rules: Flutter's own, every plugin's consumer rules, and proguard-rules.pro (added by Flutter).
            isMinifyEnabled = true
            isShrinkResources = true
            // Never the debug key. Without a release key the release tasks stop (requireReleaseSigning below),
            // or, only on explicit opt-in, produce an UNSIGNED artifact.
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// A release artifact must come out of this build signed with the upload key or not at all.
// bundleRelease / assembleRelease stop up front when the key is missing, before any compilation.
val requireReleaseSigning = tasks.register("requireReleaseSigning") {
    group = "verification"
    description = "Fails a release build that has no signing key unless WATTBYTE_ALLOW_UNSIGNED_RELEASE=1."
    doFirst {
        if (hasReleaseKey) return@doFirst
        val missing = missingSigningValues.joinToString(", ")
        if (!allowUnsignedRelease) {
            throw GradleException(
                "BLOCKED - RELEASE KEY REQUIRED: no Android release signing key (missing: $missing). " +
                    "Provide android/key.properties (see android/key.properties.example) or the WATTBYTE_KEYSTORE_FILE, " +
                    "WATTBYTE_KEYSTORE_PASSWORD, WATTBYTE_KEY_ALIAS and WATTBYTE_KEY_PASSWORD environment variables. " +
                    "To build an UNSIGNED artifact on purpose (it cannot be uploaded to Google Play), set " +
                    "WATTBYTE_ALLOW_UNSIGNED_RELEASE=1. The debug key is never used for release."
            )
        }
        // error level on purpose: `flutter build` runs Gradle with -q, which hides warnings, and this must be seen.
        logger.error(
            "WARNING - UNSIGNED RELEASE ARTIFACT: no release signing key (missing: $missing) and " +
                "WATTBYTE_ALLOW_UNSIGNED_RELEASE is set. The output is not signed, is rejected by Google Play " +
                "and cannot be installed."
        )
    }
}
tasks.matching { it.name == "bundleRelease" || it.name == "assembleRelease" }.configureEach {
    dependsOn(requireReleaseSigning)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
