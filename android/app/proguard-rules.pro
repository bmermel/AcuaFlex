# Flutter / embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase / Play services (Auth, Firestore, etc.)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# OkHttp / Okio (dependencias transitivas)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

# Play Core (referenciado por Flutter deferred components; no está en el APK si no usás feature modules)
-dontwarn com.google.android.play.core.**
