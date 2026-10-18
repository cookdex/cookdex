import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val production = providers.environmentVariable("COOKDEX_PRODUCTION").orNull == "1"
// Only production config reads owner-managed secrets. No debug-key fallback.
val releaseDirectory = rootProject.projectDir.resolve("../../../cookdex-secrets/android-release").canonicalFile
val releaseProperties = Properties()
if (production) {
    try {
        releaseDirectory.resolve("key.properties").inputStream().use { releaseProperties.load(it) }
        check(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
            !releaseProperties.getProperty(it).isNullOrBlank()
        })
        check(releaseProperties.getProperty("storeFile") == "cookdex-release.p12")
        check(releaseDirectory.resolve("cookdex-release.p12").isFile)
    } catch (_: Exception) {
        throw GradleException("Production signing is missing or invalid. Run the owner key setup script; debug signing is forbidden.")
    }
}

android {
    useLibrary("android.test.runner")
    useLibrary("android.test.base")
    useLibrary("android.test.mock")
    namespace = "com.sylph.cookdex"
    compileSdk = 37
    buildToolsVersion = "36.0.0"
    ndkVersion = "30.0.16248370"

    // Flutter adds its supported ABIs after defaultConfig. Exclude non-shipping
    // dependency binaries at packaging too, while retaining all ARM64 scanner JNI.
    packaging {
        jniLibs.excludes += "**/libcookdex_core_probe.so"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Selected together with Dart identity and Rust sync by build.ps1.
        applicationId = if (production) "com.sylph.cookdex" else "com.sylph.cookdex.dev"
        manifestPlaceholders["appLabel"] = if (production) "cookdex" else "cookdex dev"
        manifestPlaceholders["appIcon"] = if (production) "@mipmap/ic_launcher_production" else "@mipmap/ic_launcher"
        // Filter every dependency, including scanner libraries, to shipped ARM64.
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 37
        testInstrumentationRunner = "android.test.InstrumentationTestRunner"
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    providers.environmentVariable("RECIPE_DEBUG_KEYSTORE").orNull?.let {
        signingConfigs.getByName("debug").storeFile = file(it)
    }
    if (production) {
        signingConfigs.create("productionRelease") {
            storeFile = releaseDirectory.resolve("cookdex-release.p12")
            storeType = "PKCS12"
            storePassword = releaseProperties.getProperty("storePassword")
            keyAlias = releaseProperties.getProperty("keyAlias")
            keyPassword = releaseProperties.getProperty("keyPassword")
        }
    }
    buildTypes {
        getByName("profile") {
            // Enforced by the build type: never depend on caller environment.
            applicationIdSuffix = ".profile"
            manifestPlaceholders["appLabel"] = "cookdex profile"
        }
        release {
            ndk { abiFilters.clear(); abiFilters += "arm64-v8a" }
            signingConfig = signingConfigs.getByName(if (production) "productionRelease" else "debug")
        }
    }
}

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        // Flutter adds engine ABIs separately; filter dependency JNI at packaging too.
        variant.packaging.jniLibs.excludes.addAll(setOf("**/armeabi-v7a/**", "**/x86/**", "**/x86_64/**"))
    }
    onVariants(selector().withBuildType("profile")) { variant ->
        // Permanent benchmark identity, even after the production cutover changes
        // defaultConfig.applicationId. Never inherit the dev/daily-driver ID.
        variant.applicationId.set("com.sylph.cookdex.dev.profile")
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}
