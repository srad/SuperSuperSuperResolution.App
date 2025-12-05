# TensorFlow Lite / LiteRT rules
-keep class org.tensorflow.** { *; }
-keep interface org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# Google Play Services TFLite
-keep class com.google.android.gms.tflite.** { *; }
-dontwarn com.google.android.gms.tflite.**

# AutoValue (used by TensorFlow Lite)
-dontwarn com.google.auto.value.AutoValue$Builder
-dontwarn com.google.auto.value.AutoValue

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# GPU Delegate
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**
