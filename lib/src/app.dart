import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_miuix/miuix.dart';

import 'app_state.dart';
import 'updates/update_ui.dart';
import 'miuix_widgets.dart';
import 'onboarding.dart';
import 'shell.dart';

void registerCampusLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'hangyuantong Chaoxing adapter',
    ], await rootBundle.loadString('assets/licenses/hangyuantong.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'ShiGuangSchedule NUIST adapter',
    ], await rootBundle.loadString('assets/licenses/shiguang.txt'));
  });
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => DynamicColorBuilder(
      builder: (light, dark) {
        final useDynamic =
            state.uiStyle == UiStyle.material3 &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            state.dynamicColor;
        MiuixColors miuixColors(Brightness brightness) =>
            brightness == Brightness.dark
            ? darkColorScheme()
            : lightColorScheme();

        ThemeData theme(Brightness brightness, ColorScheme? dynamic) {
          var scheme =
              (useDynamic ? dynamic : null) ??
              ColorScheme.fromSeed(
                seedColor: state.palette.seed,
                brightness: brightness,
              );
          if (state.uiStyle == UiStyle.miuix) {
            // 业务图表和自绘布局仍读取 Theme.of；这些语义色必须来自同一套
            // MIUIX token，避免底色、文字和组件出现两套调色板。
            final c = miuixColors(brightness);
            scheme =
                ColorScheme.fromSeed(
                  seedColor: c.primary,
                  brightness: brightness,
                ).copyWith(
                  primary: c.primary,
                  onPrimary: c.onPrimary,
                  primaryContainer: c.primaryContainer,
                  onPrimaryContainer: _readableContainerText(
                    c.onPrimaryContainer,
                    c.primaryContainer,
                  ),
                  tertiary: c.primary,
                  onTertiary: c.onPrimary,
                  surfaceTint: c.primary,
                  secondary: c.secondary,
                  onSecondary: c.onSecondaryVariant,
                  secondaryContainer: c.secondaryContainer,
                  // MIUIX 的 onSecondaryContainer 是输入占位色，业务正文应使用
                  // onSecondaryVariant，避免在浅灰容器上出现低对比度文字。
                  onSecondaryContainer: c.onSecondaryVariant,
                  tertiaryContainer: c.tertiaryContainer,
                  onTertiaryContainer: _readableContainerText(
                    c.onTertiaryContainer,
                    c.tertiaryContainer,
                  ),
                  surface: c.surface,
                  onSurface: c.onSurface,
                  onSurfaceVariant: c.onSurfaceVariantSummary,
                  surfaceContainerLowest: c.surface,
                  surfaceContainerLow: c.surfaceContainer,
                  surfaceContainer: c.surfaceContainer,
                  surfaceContainerHigh: c.surfaceContainerHigh,
                  surfaceContainerHighest: c.surfaceContainerHighest,
                  outline: c.outline,
                  outlineVariant: c.dividerLine,
                  error: c.error,
                  onError: c.onError,
                  errorContainer: c.errorContainer,
                  onErrorContainer: c.onErrorContainer,
                );
          }
          return ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            textTheme: state.uiStyle == UiStyle.miuix
                ? _miuixTextTheme(scheme)
                : null,
            scaffoldBackgroundColor: scheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: scheme.surface,
              foregroundColor: scheme.onSurface,
              centerTitle: false,
              scrolledUnderElevation: 0,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: scheme.surfaceContainer,
              elevation: 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            ),
            // 统一页面转场：缩放 + 淡入，避免硬切闪现。
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
              },
            ),
          );
        }

        return MaterialApp(
          title: '信大AIO',
          navigatorObservers: [updateRouteObserver],
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme(Brightness.light, light),
          darkTheme: theme(Brightness.dark, dark),
          themeMode: state.themeMode,
          // 整棵树的亮度用于 MediaQuery，与 themeMode 一致。
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            // 固定祖先结构，切换风格不会替换 MaterialApp/Navigator，保留
            // 当前路由、标签、滚动位置和未提交的输入。
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: state.fontScale == 1
                    ? media.textScaler
                    : _CampusTextScaler(media.textScaler, state.fontScale),
              ),
              child: MiuixTheme(
                data: MiuixThemeData(
                  colors: miuixColors(brightness),
                  textStyles: defaultTextStyles(),
                  brightness: brightness,
                ),
                child: UiStyleScope(style: state.uiStyle, child: child!),
              ),
            );
          },
          home: UpdateStartupGate(
            updates: state.updates,
            child: state.onboarded
                ? CampusShell(state: state)
                : OnboardingPage(state: state),
          ),
        );
      },
    ),
  );
}

TextTheme _miuixTextTheme(ColorScheme scheme) {
  final t = defaultTextStyles();
  return TextTheme(
    headlineLarge: t.title1,
    headlineMedium: t.title1,
    headlineSmall: t.title2,
    titleLarge: t.title2,
    titleMedium: t.title3,
    titleSmall: t.subtitle,
    bodyLarge: t.body1,
    bodyMedium: t.body2,
    bodySmall: t.footnote1,
    labelLarge: t.button,
    labelMedium: t.footnote1,
    labelSmall: t.footnote2,
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
}

/// 保留系统的非线性字号规则，再应用用户选择的比例。
class _CampusTextScaler extends TextScaler {
  const _CampusTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is _CampusTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

// MIUIX 的部分容器前景色用作强调装饰，映射给正文时需要足够的对比度。
Color _readableContainerText(Color foreground, Color background) {
  final textLuminance = Color.alphaBlend(
    foreground,
    background,
  ).computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final text = textLuminance + .05;
  final fill = backgroundLuminance + .05;
  if ((text > fill ? text / fill : fill / text) >= 4.5) return foreground;
  return fill / .05 >= 1.05 / fill ? Colors.black : Colors.white;
}
