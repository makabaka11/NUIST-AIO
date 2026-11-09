import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'auth/registration_page.dart';
import 'onboarding.dart';
import 'shell.dart';

void registerCampusLicenses() {
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
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            state.dynamicColor;
        ThemeData theme(Brightness brightness, ColorScheme? dynamic) {
          final scheme =
              (useDynamic ? dynamic : null) ??
              ColorScheme.fromSeed(
                seedColor: state.palette.seed,
                brightness: brightness,
              );
          return ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
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
          );
        }

        return MaterialApp(
          title: '信大AIO',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme(Brightness.light, light),
          darkTheme: theme(Brightness.dark, dark),
          themeMode: state.themeMode,
          // 首次启动先经过内测邀请码注册；已注册或此前完成过向导的
          // 装机直接进入向导 / 主界面，之后不再要求注册。
          home: !state.registered && !state.onboarded
              ? RegistrationPage(state: state)
              : state.onboarded
              ? CampusShell(state: state)
              : OnboardingPage(state: state),
        );
      },
    ),
  );
}
