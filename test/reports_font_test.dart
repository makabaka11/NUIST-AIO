import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' as md;
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/campus_ui.dart' as campus;
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/accounts/charts.dart';
import 'package:nuist_aio/src/accounts/accounts.dart';
import 'package:nuist_aio/src/accounts/accounts_page.dart';
import 'package:nuist_aio/src/accounts/reports.dart';
import 'package:nuist_aio/src/theme_settings.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<AppState> mount(WidgetTester tester, UiStyle style) async {
    tester.view.physicalSize = const md.Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
    await state.load();
    state.onboarded = true;
    await state.setUiStyle(style);
    await tester.pumpWidget(CampusApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  void push(WidgetTester tester, md.Widget child) {
    md.Navigator.of(tester.element(find.byType(md.Scaffold).first)).push(
      md.MaterialPageRoute<void>(
        builder: (_) =>
            md.Scaffold(body: md.SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets(
    'MIUIX uses stock blue in both modes and hides MD3 color preferences',
    (tester) async {
      final state = await mount(tester, UiStyle.miuix);
      md.Navigator.of(tester.element(find.byType(md.Scaffold).first)).push(
        md.MaterialPageRoute<void>(
          builder: (_) => ThemeSettingsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('主题配色'), findsNothing);
      expect(find.text('壁纸动态取色'), findsNothing);
      expect(find.text('液态玻璃导航栏'), findsNothing);
      for (final mode in [md.ThemeMode.light, md.ThemeMode.dark]) {
        await state.setMode(mode);
        for (final palette in [
          CampusPalette.values.first,
          CampusPalette.values.last,
        ]) {
          await state.setPalette(palette);
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(ThemeSettingsPage));
          final native = mode == md.ThemeMode.dark
              ? darkColorScheme()
              : lightColorScheme();
          expect(MiuixTheme.of(context).colors, native);
          expect(md.Theme.of(context).colorScheme.primary, native.primary);
          expect(md.Theme.of(context).colorScheme.tertiary, native.primary);
        }
      }
      await state.setUiStyle(UiStyle.material3);
      await tester.pumpAndSettle();
      expect(find.text('主题配色'), findsOneWidget);
      expect(state.palette, CampusPalette.values.last);
    },
  );

  for (final style in UiStyle.values) {
    testWidgets(
      '$style font slider has real width, responds to dragging and keeps 16 visible ticks',
      (tester) async {
        final state = await mount(tester, style);
        md.Navigator.of(tester.element(find.byType(md.Scaffold).first)).push(
          md.MaterialPageRoute<void>(
            builder: (_) => ThemeSettingsPage(state: state),
          ),
        );
        await tester.pumpAndSettle();
        final slider = find.byType(
          style == UiStyle.miuix ? MiuixSlider : md.Slider,
        );
        expect(tester.getSize(slider).width, greaterThan(200));
        expect(tester.getSize(slider).height, greaterThanOrEqualTo(28));
        for (final delta in [-400.0, 400.0, -400.0]) {
          await tester.drag(slider, md.Offset(delta, 0));
          await tester.pumpAndSettle();
          expect(
            state.fontScale,
            delta < 0 ? AppState.minFontScale : AppState.maxFontScale,
          );
          expect(
            await SharedPreferencesAsync().getDouble('fontScale'),
            state.fontScale,
          );
          final ticks = find.byWidgetPredicate(
            (widget) =>
                widget.key is md.ValueKey<String> &&
                (widget.key! as md.ValueKey<String>).value.startsWith(
                  'slider-fixed-tick-',
                ),
          );
          expect(ticks, findsNWidgets(16));
          for (final element in ticks.evaluate()) {
            expect(
              tester.getSize(find.byWidget(element.widget)),
              const md.Size(3, 3),
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'font scale persists, defaults safely and clamps corrupt preferences',
    () async {
      final state = AppState();
      await state.load();
      expect(state.fontScale, 1);
      await state.setFontScale(.85);
      final restored = AppState();
      await restored.load();
      expect(restored.fontScale, .85);
      await SharedPreferencesAsync().setDouble('fontScale', 90);
      final clamped = AppState();
      await clamped.load();
      expect(clamped.fontScale, AppState.maxFontScale);
    },
  );

  for (final style in UiStyle.values) {
    testWidgets(
      '$style font slider previews, persists and resets using its own component',
      (tester) async {
        final state = await mount(tester, style);
        tester.platformDispatcher.textScaleFactorTestValue = 1.2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        md.Navigator.of(tester.element(find.byType(md.Scaffold).first)).push(
          md.MaterialPageRoute<void>(
            builder: (_) => ThemeSettingsPage(state: state),
          ),
        );
        await tester.pumpAndSettle();
        if (style == UiStyle.miuix) {
          expect(find.byType(md.Slider), findsNothing);
          tester.widget<MiuixSlider>(find.byType(MiuixSlider)).onValueChanged!(
            .85,
          );
        } else {
          expect(find.byType(MiuixSlider), findsNothing);
          tester.widget<md.Slider>(find.byType(md.Slider)).onChanged!(.85);
        }
        await tester.pumpAndSettle();
        expect(state.fontScale, .85);
        final context = tester.element(
          find.byKey(const md.ValueKey('font-size-slider')),
        );
        expect(
          md.MediaQuery.textScalerOf(context).scale(20),
          closeTo(20 * 1.2 * .85, .001),
        );
        if (style == UiStyle.miuix) {
          tester
              .widget<MiuixSlider>(find.byType(MiuixSlider))
              .onValueChangeFinished!();
        } else {
          tester.widget<md.Slider>(find.byType(md.Slider)).onChangeEnd!(.85);
        }
        await tester.pumpAndSettle();
        expect(await SharedPreferencesAsync().getDouble('fontScale'), .85);
        if (style == UiStyle.miuix) {
          final slider = tester.widget<MiuixSlider>(find.byType(MiuixSlider));
          slider.onValueChanged!(1.1);
          slider.onValueChangeFinished!();
          await tester.pumpAndSettle();
          expect(await SharedPreferencesAsync().getDouble('fontScale'), 1.1);
        }
        await tester.tap(find.text('恢复默认'));
        await tester.pumpAndSettle();
        expect(state.fontScale, 1);
        expect(tester.takeException(), isNull);
      },
    );

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '$style annual month labels do not overlap at font scale $scale',
        (tester) async {
          await mount(tester, style);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final months = [
            for (var i = 0; i < 12; i++)
              MonthlySpending(
                '${DateTime(2025, 11 + i).year}-${DateTime(2025, 11 + i).month.toString().padLeft(2, '0')}',
                1000 + i * 100,
                0,
                i,
              ),
          ];
          push(
            tester,
            md.Padding(
              padding: const md.EdgeInsets.all(40),
              child: MonthlySpendingChart(months: months),
            ),
          );
          await tester.pumpAndSettle();
          final labels = find.byWidgetPredicate(
            (w) =>
                w is md.Text &&
                w.key is md.ValueKey<String> &&
                (w.key! as md.ValueKey<String>).value.startsWith('month-axis-'),
          );
          final rects =
              labels
                  .evaluate()
                  .map((e) => tester.getRect(find.byWidget(e.widget)))
                  .toList()
                ..sort((a, b) => a.left.compareTo(b.left));
          expect(rects.length, greaterThan(1));
          for (var i = 1; i < rects.length; i++) {
            expect(rects[i - 1].right, lessThanOrEqualTo(rects[i].left + .1));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$style electricity report renders real points and survives large text',
      (tester) async {
        final state = await mount(tester, style);
        final now = DateTime.now();
        state.dorm = const DormSelection(
          'example',
          '示例宿舍',
          {'room': '101'},
          ['示例101'],
        );
        final key = state.dorm!.key;
        state.accounts = AccountCache(
          electricity: Electricity(key, {
            '剩余电量': '196.33',
            '供电状态': '正常供电',
          }, now),
          electricityHistory: [
            for (var i = 0; i < 8; i++)
              ElectricitySnapshot(
                now.subtract(Duration(hours: 8 - i)),
                197.03 - i * .1,
                '度',
                '正常供电',
                key,
              ),
          ],
        );
        if (Platform.environment['CAPTURE_REPORTS'] == '1') {
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await (FontLoader('Roboto')..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('/System/Library/Fonts/STHeiti Light.ttc')
                        .readAsBytesSync(),
                  ),
                ),
              ))
              .load();
        }
        final boundaryKey = md.GlobalKey();
        md.Navigator.of(tester.element(find.byType(md.Scaffold).first)).push(
          md.MaterialPageRoute<void>(
            builder: (_) => md.RepaintBoundary(
              key: boundaryKey,
              child: CampusAccountsPage(
                state: state,
                initial: AccountSection.electricity,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(ElectricityTrendChart),
          180,
          scrollable: find.byType(md.Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('区间余额变化'), findsOneWidget);
        expect(find.text('8 次'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['CAPTURE_REPORTS'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('/tmp/nuist-electricity-${style.name}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$style reports distinguish missing months and scrub real balance samples',
      (tester) async {
        await mount(tester, style);
        push(
          tester,
          const MonthlySpendingReport(
            months: [MonthlySpending('2026-10', 0, 0, 0, hasData: false)],
            onSelected: ignoreMonth,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('该月账单尚未查询'), findsOneWidget);
        expect(find.text('¥ 0.00'), findsNothing);
        md.Navigator.of(tester.element(find.byType(MonthlySpendingReport)))
            .pop();
        await tester.pumpAndSettle();
        final now = DateTime.now();
        push(
          tester,
          BalanceHistoryReport(
            snapshots: [
              WalletSnapshot(now.subtract(const Duration(days: 1)), 1234),
              WalletSnapshot(now, 4321),
            ],
            range: TimeRange.days7,
            color: md.Colors.green,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('¥ 43.21'), findsOneWidget);
        if (style == UiStyle.miuix) {
          tester.widget<MiuixSlider>(find.byType(MiuixSlider)).onValueChanged!(
            0,
          );
        } else {
          tester.widget<md.Slider>(find.byType(md.Slider)).onChanged!(0);
        }
        await tester.pumpAndSettle();
        expect(find.text('¥ 12.34'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'MIUIX appearance action stays at the right edge at both font extremes',
    (tester) async {
      final state = await mount(tester, UiStyle.miuix);
      for (final scale in [AppState.minFontScale, AppState.maxFontScale]) {
        await state.setFontScale(scale);
        await tester.pumpAndSettle();
        final action = tester.getRect(find.byTooltip('外观与主题'));
        expect(action.right, closeTo(352, 1));
        expect(tester.takeException(), isNull);
      }
    },
  );

  if (Platform.environment['CAPTURE_REPORTS'] == '1') {
    testWidgets('capture annual report examples', (tester) async {
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
      for (final style in UiStyle.values) {
        final state = await mount(tester, style);
        final key = md.GlobalKey();
        await tester.pumpWidget(
          md.RepaintBoundary(
            key: key,
            child: CampusApp(state: state),
          ),
        );
        await tester.pumpAndSettle();
        final months = [
          for (var i = 0; i < 12; i++)
            MonthlySpending(
              '${DateTime(2025, 12 + i).year}-${DateTime(2025, 12 + i).month.toString().padLeft(2, '0')}',
              1200 + (i * 373) % 3000,
              5000,
              20 + i,
            ),
        ];
        md.Navigator.of(tester.element(find.byType(md.Scaffold).first)).push(
          md.MaterialPageRoute<void>(
            builder: (context) => md.Scaffold(
              appBar: const campus.AppBar(title: md.Text('年度报表 · 模拟数据')),
              body: md.SingleChildScrollView(
                padding: const md.EdgeInsets.all(20),
                child: campus.Card(
                  child: md.Padding(
                    padding: const md.EdgeInsets.all(20),
                    child: MonthlySpendingReport(
                      months: months,
                      selectedIndex: 11,
                      onSelected: ignoreMonth,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/nuist-annual-report-${style.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  test('electricity does not invent a power supply status', () {
    final electricity = Electricity('room', {'剩余电量': '10.00'}, DateTime.now());
    expect(electricity.status, '状态未返回');
  });
}

void ignoreMonth(int _) {}
