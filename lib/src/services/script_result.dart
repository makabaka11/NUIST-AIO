/// WKWebView bridges JavaScript numbers as doubles, even for integer fields.
/// Serialize the already-filtered adapter result inside the school origin so
/// Dart's JSON decoder preserves integer schema across Android and macOS.
String schoolScriptBody(String source) =>
    'return JSON.stringify(await (async () => {\n$source\n})());';
