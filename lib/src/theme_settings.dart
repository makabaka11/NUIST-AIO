import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'widgets.dart';

Future<void> uiAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未能保存，请稍后重试。')));
    }
  }
}

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('外观与主题')),
    body: PageBody(children: [ThemeControls(state: state)]),
  );
}

class ThemeControls extends StatelessWidget {
  const ThemeControls({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final activeDynamic =
          state.dynamicColor &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('明暗模式'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in [
                (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
                (ThemeMode.light, '浅色', Icons.light_mode_outlined),
                (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
              ])
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(item.$2),
                  avatar: Icon(item.$3, size: 18),
                  selected: state.themeMode == item.$1,
                  onSelected: (_) =>
                      uiAction(context, () => state.setMode(item.$1)),
                ),
            ],
          ),
          const SectionTitle('主题配色'),
          Text(
            '选择一种喜欢的颜色，让校园日常有自己的风格。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final palette in CampusPalette.values)
                Semantics(
                  selected: !activeDynamic && state.palette == palette,
                  button: true,
                  label: '${palette.label}主题',
                  child: SizedBox(
                    width: 88,
                    child: Card(
                      color: ColorScheme.fromSeed(
                        seedColor: palette.seed,
                        brightness: colors.brightness,
                      ).primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: !activeDynamic && state.palette == palette
                              ? colors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () =>
                            uiAction(context, () => state.setPalette(palette)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 17,
                                backgroundColor: palette.seed,
                                child:
                                    !activeDynamic && state.palette == palette
                                    ? const Icon(
                                        Icons.check,
                                        size: 19,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                palette.label,
                                style: TextStyle(
                                  color: ColorScheme.fromSeed(
                                    seedColor: palette.seed,
                                    brightness: colors.brightness,
                                  ).onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            Card(
              color: colors.surfaceContainerLow,
              child: SwitchListTile(
                title: const Text('壁纸动态取色'),
                subtitle: const Text('Android 12 及以上支持；不可用时使用所选配色'),
                value: state.dynamicColor,
                onChanged: (value) =>
                    uiAction(context, () => state.setDynamic(value)),
              ),
            )
          else
            Text(
              '安卓端支持跟随壁纸动态取色。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          const SectionTitle('导航栏'),
          Card(
            color: colors.surfaceContainerLow,
            child: SwitchListTile(
              title: const Text('液态玻璃导航栏'),
              subtitle: const Text('悬浮毛玻璃底栏；关闭后使用 Material 3 导航栏'),
              value: state.liquidGlassNav,
              onChanged: (value) =>
                  uiAction(context, () => state.setLiquidGlassNav(value)),
            ),
          ),
          const SectionTitle('效果预览'),
          Card(
            color: colors.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.palette_outlined,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '把喜欢的颜色，带进每一天。',
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
