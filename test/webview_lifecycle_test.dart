import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/webview_page_lifecycle.dart';

class BrowserTestPage extends StatefulWidget {
  const BrowserTestPage({super.key});
  @override
  State<BrowserTestPage> createState() => _BrowserTestPageState();
}

class _BrowserTestPageState extends State<BrowserTestPage>
    with WebViewPageLifecycle<BrowserTestPage> {
  @override
  Widget build(BuildContext context) => guardWebViewPage(
    Scaffold(
      appBar: AppBar(title: const Text('Browser test')),
      body: Column(
        children: [
          if (webViewVisible) const Text('native view placeholder'),
          TextButton(
            onPressed: () => closeWebViewPage(true),
            child: const Text('Import complete'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  for (final back in ['app bar', 'system', 'import']) {
    testWidgets('$back removes WebView before reverse transition', (
      tester,
    ) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('home')),
        ),
      );
      bool? result;
      final route = MaterialPageRoute<bool>(
        builder: (_) => const BrowserTestPage(),
      );
      key.currentState!.push(route).then((value) => result = value);
      await tester.pumpAndSettle();
      bool reversed = false;
      bool viewRemovedBeforeReverse = false;
      route.animation!.addStatusListener((status) {
        if (status == AnimationStatus.reverse) {
          reversed = true;
          viewRemovedBeforeReverse = find
              .text('native view placeholder')
              .evaluate()
              .isEmpty;
        }
      });
      switch (back) {
        case 'app bar':
          await tester.tap(find.byType(BackButton));
        case 'system':
          await tester.binding.handlePopRoute();
        case 'import':
          await tester.tap(find.text('Import complete'));
      }
      await tester.pumpAndSettle();
      expect(reversed, isTrue);
      expect(viewRemovedBeforeReverse, isTrue);
      expect(find.text('home'), findsOneWidget);
      expect(result, back == 'import' ? isTrue : isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
