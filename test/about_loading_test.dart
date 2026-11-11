import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' as md;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/about/about_page.dart';
import 'package:nuist_aio/src/about/material_about_page.dart';
import 'package:nuist_aio/src/about/miuix_about_page.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/campus_ui.dart' as campus;
import 'package:nuist_aio/src/profile/profile_header.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<AppState> mount(WidgetTester tester, UiStyle style) async {
    tester.view.physicalSize = const md.Size(360, 820);
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

  for (final style in UiStyle.values) {
    testWidgets(
      '$style about entry consolidates information and QR dialog keeps its style',
      (tester) async {
        await mount(tester, style);
        await tester.tap(find.text('我的').last);
        await tester.pumpAndSettle();
        expect(find.text('开发者'), findsNothing);
        expect(find.text('信大AIO交流群'), findsNothing);
        expect(find.text('关于信大AIO'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('关于应用'),
          350,
          scrollable: find.byType(md.Scrollable).first,
        );
        await md.Scrollable.ensureVisible(
          tester.element(find.text('关于应用')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('关于应用'));
        await tester.pumpAndSettle();
        expect(find.byType(AboutPage), findsOneWidget);
        expect(
          find.byType(
            style == UiStyle.miuix ? MiuixAboutPage : MaterialAboutPage,
          ),
          findsOneWidget,
        );
        expect(
          find.byType(
            style == UiStyle.miuix ? MaterialAboutPage : MiuixAboutPage,
          ),
          findsNothing,
        );
        if (style == UiStyle.miuix) {
          expect(find.byType(MiuixArrowPreference), findsWidgets);
          expect(find.byType(MiuixSmallTopAppBar), findsOneWidget);
        }
        expect(find.text('信大 AIO'), findsOneWidget);
        expect(find.text('v0.5.0 · Build 15'), findsOneWidget);
        final launches = <String>[];
        const launcher = MethodChannel('plugins.flutter.io/url_launcher');
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(launcher, (call) async {
          expect(call.method, 'launch');
          expect(call.arguments['useWebView'], isFalse);
          launches.add(call.arguments['url'] as String);
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
        final repositories = find.text('项目仓库');
        await tester.scrollUntilVisible(
          repositories,
          200,
          scrollable: find.byType(md.Scrollable).first,
        );
        expect(
          tester.getTopLeft(repositories).dy,
          lessThan(tester.getTopLeft(find.text('交流与反馈')).dy),
        );
        for (final host in ['GitHub', 'Gitee']) {
          await tester.tap(repositories);
          await tester.pumpAndSettle();
          await tester.tap(find.text(host));
          await tester.pumpAndSettle();
        }
        expect(launches, [
          'https://github.com/makabaka11/NUIST-AIO',
          'https://gitee.com/ded_retr0/NUIST-AIO',
        ]);
        await tester.scrollUntilVisible(
          find.text('交流与反馈'),
          200,
          scrollable: find.byType(md.Scrollable).first,
        );
        await tester.tap(find.text('交流与反馈'));
        await tester.pumpAndSettle();
        expect(find.text('群号：1135530515'), findsOneWidget);
        if (style == UiStyle.miuix) {
          expect(find.byType(md.FilledButton), findsNothing);
          expect(find.byType(md.ListTile), findsNothing);
        }
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('赞赏码'),
          200,
          scrollable: find.byType(md.Scrollable).first,
        );
        expect(
          tester.getTopLeft(find.text('赞赏码')).dy,
          greaterThan(tester.getTopLeft(find.text('交流与反馈')).dy),
        );
        await tester.tap(find.text('赞赏码'));
        await tester.pumpAndSettle();
        final appreciationImage = find.byWidgetPredicate(
          (widget) =>
              widget is md.Image &&
              widget.image is md.AssetImage &&
              (widget.image as md.AssetImage).assetName ==
                  'assets/appreciation_code.png',
        );
        expect(appreciationImage, findsOneWidget);
        expect(
          tester.widget<md.Image>(appreciationImage).fit,
          md.BoxFit.contain,
        );
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(appreciationImage, findsNothing);
        await tester.scrollUntilVisible(
          find.text('联系邮箱'),
          250,
          scrollable: find.byType(md.Scrollable).first,
        );
        expect(find.text('Retr0'), findsOneWidget);
        expect(find.text('ded000@retr0.xyz'), findsOneWidget);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.text('关于应用'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$style initialization and profile refresh show native inline spinners only while busy',
      (tester) async {
        final state = await mount(tester, style);
        state.connectingServices = true;
        state.servicesNotice = '正在初始化校园服务…';
        await tester.pumpWidget(CampusApp(state: state));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('正在初始化校园服务…'), findsOneWidget);
        expect(find.byType(campus.InlineLoadingIndicator), findsOneWidget);
        expect(
          find.byType(
            style == UiStyle.miuix
                ? MiuixCircularProgressIndicator
                : md.CircularProgressIndicator,
          ),
          findsOneWidget,
        );
        state.connectingServices = false;
        state.servicesNotice = '部分服务未连接，请重试。';
        await tester.pumpWidget(CampusApp(state: state));
        await tester.pumpAndSettle();
        expect(find.byType(campus.InlineLoadingIndicator), findsNothing);
        state.connectedAt = DateTime.now();
        state.syncingProfile = true;
        final navigator = md.Navigator.of(
          tester.element(find.byType(md.Scaffold).first),
        );
        navigator.push(
          md.MaterialPageRoute<void>(
            builder: (_) => md.Scaffold(
              body: ProfileHeader(state: state, onLogin: () {}),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('正在同步…'), findsOneWidget);
        expect(find.byType(campus.InlineLoadingIndicator), findsNWidgets(2));
        state.syncingProfile = false;
        await tester.pumpWidget(CampusApp(state: state));
        await tester.pumpAndSettle();
        expect(find.text('更新资料'), findsOneWidget);
        expect(find.byType(campus.InlineLoadingIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  if (Platform.environment['CAPTURE_ABOUT'] == '1') {
    testWidgets('capture about page', (tester) async {
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
      final state = await mount(tester, UiStyle.miuix);
      await state.setMode(md.ThemeMode.dark);
      final key = md.GlobalKey();
      await tester.pumpWidget(
        md.RepaintBoundary(
          key: key,
          child: CampusApp(state: state),
        ),
      );
      await tester.pumpAndSettle();
      md.Navigator.of(tester.element(find.byType(md.Scaffold).first))
          .push(md.MaterialPageRoute<void>(builder: (_) => const AboutPage()));
      await tester.pumpAndSettle();
      for (final style in UiStyle.values) {
        await state.setUiStyle(style);
        for (final mode in [md.ThemeMode.light, md.ThemeMode.dark]) {
          await state.setMode(mode);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('/tmp/nuist-about-${style.name}-${mode.name}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }
}
