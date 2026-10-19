// Unit tests for the Android-free parts of wattbyte_system (DayRanges, BatteryValues).
//
// The plugin itself is built by the Flutter app's Gradle build (AGP 9 + KGP), where
// AGP currently leaves KGP-compiled unit test classes off the test classpath, so
// the pure logic is tested here on a plain JVM instead.
plugins {
    kotlin("jvm") version "2.2.20"
}

repositories {
    mavenCentral()
}

kotlin {
    jvmToolchain(17)
}

sourceSets {
    main {
        kotlin.srcDir("../src/main/kotlin")
        kotlin.include("**/DayRanges.kt", "**/BatteryValues.kt")
    }
    test {
        kotlin.srcDir("../src/test/kotlin")
    }
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    testLogging {
        events("passed", "failed", "skipped")
    }
}
