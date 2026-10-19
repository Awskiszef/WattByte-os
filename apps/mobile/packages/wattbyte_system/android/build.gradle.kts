group = "pl.wattbyte.system"
version = "1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    // android.builtInKotlin=false in the host app: Kotlin is applied explicitly.
    id("kotlin-android")
}

android {
    namespace = "pl.wattbyte.system"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // NetworkStatsManager accepts a null subscriberId (all SIMs) from API 29.
        minSdk = 29
    }

    testOptions {
        unitTests {
            all {
                it.useJUnitPlatform()
                it.testLogging {
                    events("passed", "skipped", "failed")
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// AGP 9.1 with android.builtInKotlin=false (the Flutter template default) compiles
// unit tests via KGP but leaves their class directory off the test classpath,
// so the JVM reports ClassNotFoundException. Add it explicitly.
tasks.withType<Test>().configureEach {
    val variant = name.removePrefix("test").removeSuffix("UnitTest").replaceFirstChar { it.lowercase() }
    val kotlinTestClasses = layout.buildDirectory.dir("tmp/kotlin-classes/${variant}UnitTest")
    // doFirst: AGP finalises the classpath after configuration, so append at execution time.
    doFirst {
        classpath += files(kotlinTestClasses)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
