# Scanly release shrinking rules.

# ML Kit text recognition references the optional Chinese, Devanagari,
# Japanese and Korean recognizers. Scanly bundles only the Latin model (and
# uses Tesseract for Bangla), so those classes are intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit (document scanner and text recognition) finds its internal
# components by class name at runtime. Without these rules R8 strips or
# renames them in release builds, Google's scanner fails to start
# (NullPointerException in mlkit_vision_document_scanner) and text
# recognition throws, so the app silently fell back to slower paths.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.components.** { *; }

# Tesseract4Android calls back into Java from native code by class/method
# name, so these must not be renamed or removed.
-keep class com.googlecode.tesseract.android.** { *; }
