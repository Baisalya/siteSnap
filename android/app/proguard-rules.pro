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
