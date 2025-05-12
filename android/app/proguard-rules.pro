# In android/app/proguard-rules.pro

# TensorFlow Lite - GPU Delegate
-keep class org.tensorflow.lite.gpu.GpuDelegate { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }
-keep class org.tensorflow.lite.gpu.CompatibilityList { *; }

# General TensorFlow Lite (recommended)
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }

# You can also add the rule from your missing_rules.txt if you still see warnings
# after adding the -keep rules, but the -keep rules are more important for fixing the error.
# -dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options