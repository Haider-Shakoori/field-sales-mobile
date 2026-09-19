plugins { id("com.android.application"); id("kotlin-android"); id("dev.flutter.flutter-gradle-plugin") }
android { namespace="com.wesoft.fieldsales"; compileSdk=flutter.compileSdkVersion; ndkVersion=flutter.ndkVersion
 defaultConfig { applicationId="com.wesoft.fieldsales"; minSdk=24; targetSdk=flutter.targetSdkVersion; versionCode=flutter.versionCode; versionName=flutter.versionName }
 compileOptions { sourceCompatibility=JavaVersion.VERSION_17; targetCompatibility=JavaVersion.VERSION_17 }
 kotlinOptions { jvmTarget="17" }
}
flutter { source="../.." }
