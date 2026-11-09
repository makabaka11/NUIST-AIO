import 'package:flutter/material.dart';

/// Remove the native platform view before the route begins its exit animation.
/// Applies to the app bar, system back, and successful import completion.
mixin WebViewPageLifecycle<T extends StatefulWidget> on State<T> {
  bool webViewVisible = true;
  bool _closingWebView = false;
  bool _canPopWebView = false;

  Future<void> closeWebViewPage([Object? result]) async {
    if (_closingWebView || !mounted) return;
    setState(() {
      _closingWebView = true;
      webViewVisible = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _canPopWebView = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(result);
  }

  Widget guardWebViewPage(Widget child) => PopScope<Object?>(
    canPop: _canPopWebView,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) closeWebViewPage(result);
    },
    child: child,
  );
}
