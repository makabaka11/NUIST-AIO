import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/navigation/android_liquid_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native bar bridges selection, theme, safe area and disposal', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    final updates = <Map<Object?, Object?>>[];
    int? viewId;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'create') {
        final args = call.arguments as Map;
        viewId = args['id'] as int;
        expect(args['viewType'], 'nuistaio/liquid_nav');
        expect(args['hybrid'], isTrue);
        final config = const StandardMessageCodec().decodeMessage(
          ByteData.sublistView(args['params'] as Uint8List),
        ) as Map;
        expect(config['selectedIndex'], 1);
        messenger.setMockMethodCallHandler(
          MethodChannel('nuistaio/liquid_nav/$viewId'),
          (update) async {
            if (update.method == 'configure') {
              updates.add(Map<Object?, Object?>.from(update.arguments as Map));
            }
            return null;
          },
        );
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      if (viewId != null) {
        messenger.setMockMethodCallHandler(
          MethodChannel('nuistaio/liquid_nav/$viewId'),
          null,
        );
      }
    });
    final selected = <int>[];
    Widget app(int index, Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 34),
          textScaler: TextScaler.linear(1.8),
          disableAnimations: true,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AndroidLiquidNav(
            selectedIndex: index,
            onSelected: selected.add,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(1, Brightness.light));
    await tester.pumpAndSettle();
    expect(viewId, isNotNull);
    expect(tester.getSize(find.byType(AndroidLiquidNav)).height, 130);
    expect(tester.getSize(find.byType(AndroidViewSurface)).height, 96);
    expect(
      tester.getSize(find.byType(AndroidViewSurface)).width,
      lessThanOrEqualTo(472),
    );

    Future<void> send(Object? index) async {
      await messenger.handlePlatformMessage(
        'nuistaio/liquid_nav/$viewId',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('select', index),
        ),
        (_) {},
      );
    }

    await send(3);
    await send(-1);
    await send(4);
    await send('bad');
    expect(selected, [3]);
    await tester.pumpWidget(app(2, Brightness.dark));
    await tester.pumpAndSettle();
    expect(updates.last['selectedIndex'], 2);
    expect(updates.last['dark'], isTrue);
    expect(updates.last['reduceMotion'], isTrue);
    expect(updates.last['textScale'], 1.8);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'dispose'), hasLength(1));
    await send(0);
    expect(selected, [3]);
    expect(tester.takeException(), isNull);
  });
}
