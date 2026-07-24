-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Specific necessary classes
-keep class com.antonkarpenko.ffmpegkit.FFmpegKitConfig { *; }
-keep class com.antonkarpenko.ffmpegkit.AbiDetect { *; }
-keep class com.antonkarpenko.ffmpegkit.*Session { *; }
-keep class com.antonkarpenko.ffmpegkit.*Callback { *; }

# SurveyCam releases ImageReader SurfaceProducers before FlutterEngine teardown
# to work around Flutter engine issue #188300. The private field name is used by
# reflection and must remain stable in minified release builds.
-keepclassmembers class io.flutter.embedding.engine.renderer.FlutterRenderer {
    java.util.List imageReaderProducers;
}
