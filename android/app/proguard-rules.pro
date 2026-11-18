# Scanly release shrinking rules.

# ML Kit text recognition references the optional Chinese, Devanagari,
# Japanese and Korean recognizers. Scanly bundles only the Latin model (and
# uses Tesseract for Bangla), so those classes are intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Tesseract4Android calls back into Java from native code by class/method
# name, so these must not be renamed or removed.
-keep class com.googlecode.tesseract.android.** { *; }
