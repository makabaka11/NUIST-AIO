import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' as md;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/campus_ui.dart' as campus;
import 'package:nuist_aio/src/theme_settings.dart';
import 'package:nuist_aio/src/widgets.dart' show PageBody;

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AppState> mount(
    WidgetTester tester, {
    bool miuix = true,
    double width = 412,
    double scale = 1,
  }) async {
    tester.view.physicalSize = md.Size(width, 915);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = AppState();
    await state.load();
    state.onboarded = true;
    await state.setUiStyle(miuix ? UiStyle.miuix : UiStyle.material3);
    await tester.pumpWidget(CampusApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  void expectMiuixOnly() {
    for (final type in [
      md.Card,
      md.FilledButton,
      md.OutlinedButton,
      md.TextButton,
      md.IconButton,
      md.ChoiceChip,
      md.Chip,
      md.ListTile,
      md.AppBar,
      md.SegmentedButton<int>,
      md.AlertDialog,
      md.Switch,
      md.InkWell,
      md.DropdownButtonFormField<String>,
      md.RefreshIndicator,
    ]) {
      expect(
        find.byType(type),
        findsNothing,
        reason: 'MIUIX must not render $type',
      );
    }
    // flutter_miuix itself uses Flutter TextField for editing. It must be inside
    // MiuixTextField, never a page's standalone MD3 input.
    for (final input in find.byType(md.TextField).evaluate()) {
      expect(
        find.ancestor(
          of: find.byWidget(input.widget),
          matching: find.byType(MiuixTextField),
        ),
        findsOneWidget,
      );
    }
  }

  testWidgets(
    'MIUIX tabs stay isolated in light and dark on a narrow large-text screen',
    (tester) async {
      final state = await mount(tester, width: 360, scale: 1.5);
      for (final mode in [md.ThemeMode.light, md.ThemeMode.dark]) {
        await state.setMode(mode);
        await tester.pumpAndSettle();
        for (final tab in ['首页', '学习', '功能', '我的']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expectMiuixOnly();
          expect(tester.takeException(), isNull, reason: '$mode / $tab');
        }
        final context = tester.element(find.byType(MiuixNavigationBar));
        final c = MiuixTheme.of(context).colors;
        expect(md.Theme.of(context).colorScheme.surface, c.surface);
        final nativeColors = mode == md.ThemeMode.dark
            ? darkColorScheme()
            : lightColorScheme();
        expect(c.surface, nativeColors.surface);
        expect(c.surfaceContainer, nativeColors.surfaceContainer);
        expect(md.Theme.of(context).colorScheme.primary, c.primary);
        expect(
          md.Theme.of(context).brightness,
          mode == md.ThemeMode.dark ? md.Brightness.dark : md.Brightness.light,
        );
      }
    },
  );

  testWidgets(
    'switching styles preserves feature search, selected tab and pushed settings route',
    (tester) async {
      final state = await mount(tester, miuix: false);
      await tester.tap(find.text('功能').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(md.TextField), '图书');
      await state.setUiStyle(UiStyle.miuix);
      await tester.pumpAndSettle();
      expect(find.byType(MiuixTextField), findsOneWidget);
      expect(
        tester
            .widget<MiuixTextField>(find.byType(MiuixTextField))
            .controller!
            .text,
        '图书',
      );
      expect(find.text('图书馆').hitTestable(), findsOneWidget);
      final context = tester.element(find.byType(MiuixTextField));
      md.Navigator.of(context).push(
        md.MaterialPageRoute<void>(
          builder: (_) => ThemeSettingsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await state.setUiStyle(UiStyle.material3);
      await tester.pumpAndSettle();
      expect(find.text('外观与主题').hitTestable(), findsOneWidget);
      expect(find.byType(md.AppBar), findsOneWidget);
      await state.setUiStyle(UiStyle.miuix);
      await state.setMode(md.ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(find.text('外观与主题').hitTestable(), findsOneWidget);
      expectMiuixOnly();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('图书馆').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<MiuixTextField>(find.byType(MiuixTextField))
            .controller!
            .text,
        '图书',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MIUIX dropdown selection, validation and modal dismissal work', (
    tester,
  ) async {
    final state = await mount(tester);
    final navigator = md.Navigator.of(
      tester.element(find.byType(MiuixNavigationBar)),
    );
    final formKey = md.GlobalKey<md.FormState>();
    final controller = md.TextEditingController();
    addTearDown(controller.dispose);
    var selected = 'a';
    navigator.push(
      md.MaterialPageRoute<void>(
        builder: (_) => md.StatefulBuilder(
          builder: (context, setState) => md.Scaffold(
            appBar: const campus.AppBar(title: md.Text('控件验证')),
            body: md.Form(
              key: formKey,
              child: md.ListView(
                padding: const md.EdgeInsets.all(20),
                children: [
                  campus.DropdownButtonFormField<String>(
                    initialValue: selected,
                    items: const [
                      md.DropdownMenuItem(value: 'a', child: md.Text('选项甲')),
                      md.DropdownMenuItem(value: 'b', child: md.Text('选项乙')),
                    ],
                    onChanged: (v) => setState(() => selected = v!),
                  ),
                  campus.TextFormField(
                    controller: controller,
                    decoration: const md.InputDecoration(labelText: '名称'),
                    validator: (v) => v == null || v.isEmpty ? '请输入名称' : null,
                  ),
                  campus.FilledButton(
                    onPressed: () => formKey.currentState!.validate(),
                    child: const md.Text('验证'),
                  ),
                  campus.TextButton(
                    onPressed: () => campus.showDialog<bool>(
                      context: context,
                      builder: (dialog) => campus.AlertDialog(
                        title: const md.Text('确认操作'),
                        actions: [
                          campus.TextButton(
                            onPressed: () => md.Navigator.pop(dialog, false),
                            child: const md.Text('取消'),
                          ),
                        ],
                      ),
                    ),
                    child: const md.Text('显示确认'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项甲'));
    await tester.pumpAndSettle();
    expectMiuixOnly();
    await tester.tap(find.text('选项乙'));
    await tester.pumpAndSettle();
    expect(selected, 'b');
    await tester.tap(find.text('验证'));
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsOneWidget);
    await tester.enterText(find.byType(md.TextField), '测试');
    await tester.tap(find.text('验证'));
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsNothing);
    await tester.tap(find.text('显示确认'));
    await tester.pumpAndSettle();
    expectMiuixOnly();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认操作'), findsNothing);
    expect(state.uiStyle, UiStyle.miuix);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncontrolled input and scrolling survive style changes', (
    tester,
  ) async {
    final state = await mount(tester, miuix: false);
    final navigator = md.Navigator.of(
      tester.element(find.byType(md.Scaffold).first),
    );
    navigator.push(
      md.MaterialPageRoute<void>(
        builder: (_) => md.Scaffold(
          appBar: const campus.AppBar(title: md.Text('保留编辑状态')),
          body: PageBody(
            children: [
              const campus.TextField(
                decoration: md.InputDecoration(labelText: '临时输入'),
              ),
              for (var i = 0; i < 30; i++)
                md.SizedBox(height: 60, child: md.Text('条目 $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(md.TextField), '保留这段文字');
    md.FocusManager.instance.primaryFocus?.unfocus();
    final initialPosition = tester
        .state<md.ScrollableState>(find.byType(md.Scrollable).first)
        .position;
    initialPosition.jumpTo(120);
    await tester.pumpAndSettle();
    final position = tester
        .state<md.ScrollableState>(find.byType(md.Scrollable).first)
        .position;
    final offset = position.pixels;
    expect(offset, greaterThan(0));
    await state.setUiStyle(UiStyle.miuix);
    await tester.pumpAndSettle();
    expect(
      tester
          .state<md.ScrollableState>(find.byType(md.Scrollable).first)
          .position
          .pixels,
      offset,
    );
    expect(
      tester
          .widget<MiuixTextField>(find.byType(MiuixTextField))
          .controller!
          .text,
      '保留这段文字',
    );
    await state.setUiStyle(UiStyle.material3);
    await tester.pumpAndSettle();
    expect(
      tester.widget<md.TextField>(find.byType(md.TextField)).controller!.text,
      '保留这段文字',
    );
    expect(tester.takeException(), isNull);
  });

  test('page sources use the adaptive UI boundary', () {
    for (final file
        in Directory('lib/src')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (file.path.endsWith('/campus_ui.dart') ||
          file.path.endsWith('/app.dart')) {
        continue;
      }
      if (RegExp(
        r'\b(Card|FilledButton|OutlinedButton|TextButton|IconButton|ChoiceChip|ListTile|AppBar|TextField|AlertDialog)\(',
      ).hasMatch(source)) {
        expect(
          source.contains("import 'package:flutter/material.dart'"),
          isFalse,
          reason: file.path,
        );
      }
    }
  });

  if (Platform.environment['CAPTURE_MIUIX'] == '1') {
    testWidgets('capture MIUIX review', (tester) async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('Roboto')..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/STHeiti Light.ttc')
                    .readAsBytesSync(),
              ),
            ),
          ))
          .load();
      final state = await mount(tester);
      final boundaryKey = md.GlobalKey();
      await tester.pumpWidget(
        md.RepaintBoundary(
          key: boundaryKey,
          child: CampusApp(state: state),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/miuix-$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('home');
      await tester.tap(find.byTooltip('外观与主题'));
      await capture('settings-light');
      await state.setMode(md.ThemeMode.dark);
      await capture('settings-dark');
      expect(tester.takeException(), isNull);
    });
  }
}
