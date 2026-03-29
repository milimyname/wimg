plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.wimg.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.wimg.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.7.0"

        ndk {
            abiFilters += "arm64-v8a"
        }
        ndkVersion = "30.0.14904198"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

dependencies {
    // Compose
    implementation(platform("androidx.compose:compose-bom:2025.03.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.navigation:navigation-compose:2.8.0")

    // JSON parsing for C ABI results
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // AppCompat for theme switching
    implementation("androidx.appcompat:appcompat:1.7.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
