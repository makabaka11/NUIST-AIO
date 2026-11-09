# Preserve methods invoked by WebView JavaScript, including the native bridge.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
