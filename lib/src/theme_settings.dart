import 'package:flutter/foundation.dart';

import 'campus_ui.dart';

import 'app_state.dart';
import 'miuix_widgets.dart';
import 'widgets.dart';

Future<void> uiAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      showCampusSnackBar(context, const SnackBar(content: Text('未能保存，请稍后重试。')));
    }
  }
}

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: campusAppBar(context, title: '外观与主题'),
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
      final isMiuix = state.uiStyle == UiStyle.miuix;
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
          const SectionTitle('字体大小'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '字号比例 · ${(state.fontScale * 100).round()}%',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            uiAction(context, () => state.setFontScale(1)),
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                  Slider(
                    key: const ValueKey('font-size-slider'),
                    value: state.fontScale,
                    min: AppState.minFontScale,
                    max: AppState.maxFontScale,
                    divisions: 15,
                    fixedTicks: true,
                    label: '字体大小 ${(state.fontScale * 100).round()}%',
                    onChanged: (value) =>
                        state.setFontScale(value, persist: false),
                    onChangeEnd: (value) =>
                        uiAction(context, () => state.setFontScale(value)),
                  ),
                  const Text('75%–150%，每档 5%。在系统字号基础上调整，100% 为默认大小。'),
                  const SizedBox(height: 12),
                  Text(
                    '校园日常，从容阅读。',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('界面风格'),
          Text(
            '选择整套组件的视觉语言。Material 3 为原生质感；MIUIX 为 HyperOS 风格。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final style in UiStyle.values)
                ChoiceChip(
                  showCheckmark: false,
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          style == UiStyle.miuix
                              ? Icons.blur_circular_outlined
                              : Icons.layers_outlined,
                          size: 22,
                        ),
                        const SizedBox(height: 6),
                        Text(style.label),
                      ],
                    ),
                  ),
                  selected: state.uiStyle == style,
                  onSelected: (_) =>
                      uiAction(context, () => state.setUiStyle(style)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isMiuix
                ? 'MIUIX 使用经典黑白配色与澎湃蓝强调色，可调整明暗模式和字体大小。'
                : '当前为 Material 3 风格：可在下方开启液态玻璃导航栏。切换到 MIUIX 后将使用其内置导航栏。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (!isMiuix) ...[
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
                          onTap: () => uiAction(
                            context,
                            () => state.setPalette(palette),
                          ),
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
              PreferenceSwitchRow(
                title: '壁纸动态取色',
                subtitle: 'Android 12 及以上支持；不可用时使用所选配色',
                value: state.dynamicColor,
                onChanged: (value) =>
                    uiAction(context, () => state.setDynamic(value)),
              )
            else
              Text(
                '安卓端支持跟随壁纸动态取色。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
          if (!isMiuix) ...[
            const SectionTitle('导航栏'),
            PreferenceSwitchRow(
              title: '液态玻璃导航栏',
              subtitle: '悬浮毛玻璃底栏；关闭后使用 Material 3 导航栏',
              value: state.liquidGlassNav,
              onChanged: (value) =>
                  uiAction(context, () => state.setLiquidGlassNav(value)),
            ),
          ],
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
                      isMiuix ? '经典蓝色，清晰阅读。' : '把喜欢的颜色，带进每一天。',
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
