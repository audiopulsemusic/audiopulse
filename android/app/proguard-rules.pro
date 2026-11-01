# Flutter & AudioService / ExoPlayer keep rules for R8 release minification
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# Ignore optional Google Play Core classes referenced by Flutter Deferred Components
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.exoplayer2.**
-dontwarn org.slf4j.**
