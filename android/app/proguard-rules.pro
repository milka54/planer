# Flutter / Firebase
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson / JSON
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

-dontwarn com.google.android.gms.**
-dontwarn android.support.**
