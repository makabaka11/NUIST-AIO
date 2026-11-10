import 'dart:math' as math;

import 'campus_ui.dart';

import 'package:flutter/services.dart';

import 'app_state.dart';
import 'image_saver.dart';
import 'miuix_widgets.dart';

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    // 两套风格共用布局结构，避免切换时重建 Scrollable 及其业务子树。
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: ListView(
          // extendBody 开启时，Scaffold 把底栏总高度写入 MediaQuery 底部内边距。
          // 尾部留白取该值即可：末尾内容刚好停在玻璃上沿，既不被遮挡，也不会
          // 再划出一段多余空白；无底栏延伸时回落到 28 常规留白。
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            math.max(28.0, MediaQuery.paddingOf(context).bottom),
          ),
          children: children,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    if (UiStyleScope.of(context) == UiStyle.miuix) {
      return MiuixSectionTitle(title, trailing: trailing);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    if (UiStyleScope.of(context) == UiStyle.miuix) {
      return MiuixIconTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.primary, size: 27),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.loading = false,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (UiStyleScope.of(context) == UiStyle.miuix) {
      return MiuixEmptyCard(
        icon: icon,
        title: title,
        message: message,
        loading: loading,
        action: action,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 30),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LoadingText(
              message,
              loading: loading,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.6),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

void showPendingFeature(BuildContext context, String name) {
  if (UiStyleScope.of(context) == UiStyle.miuix) {
    showMiuixPendingFeature(context, name);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.construction_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 36,
            ),
            const SizedBox(height: 20),
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('入口已预留，具体功能将在后续版本接入。'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 自适应交流群二维码弹窗。MD3 用 Dialog；MIUIX 用 squircle 底部表。
/// [groupNumber] 为 QQ 群号，点击"复制群号"写入剪贴板并提示。
void showGroupQrDialog(BuildContext context, String groupNumber) {
  if (UiStyleScope.of(context) == UiStyle.miuix) {
    showMiuixGroupQrSheet(context, groupNumber);
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '信大AIO交流群',
                style: Theme.of(dialogContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  'assets/qq_group_qrcode.jpg',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  semanticLabel: 'QQ 群二维码',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '群号：$groupNumber',
                style: Theme.of(dialogContext).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: groupNumber));
                        Navigator.pop(dialogContext);
                        showCampusSnackBar(
                          context,
                          const SnackBar(
                            content: Text('群号已复制到剪贴板'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('复制群号'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 自适应偏好设置分组容器。MD3 模式渲染 Card + Column；
/// MIUIX 模式渲染 MiuixGroupCard（squircle 圆角 + 细分隔线）。
/// [children] 通常是 [PreferenceRow]。
class PreferenceGroup extends StatelessWidget {
  const PreferenceGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (UiStyleScope.of(context) == UiStyle.miuix) {
      return MiuixGroupCard(children: children);
    }
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      child: Column(children: children),
    );
  }
}

/// 自适应偏好设置行。MD3 模式渲染 ListTile；MIUIX 模式渲染 MiuixArrowRow
/// （sink 按压反馈 + squircle 裁剪）。两种模式下 [trailing] 均生效。
class PreferenceRow extends StatelessWidget {
  const PreferenceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (UiStyleScope.of(context) == UiStyle.miuix) {
      return MiuixArrowRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: trailing,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colors.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 自适应开关行。MD3 用 SwitchListTile；MIUIX 用 MiuixSwitchRow。
class PreferenceSwitchRow extends StatelessWidget {
  const PreferenceSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (UiStyleScope.of(context) == UiStyle.miuix) {
      return MiuixSwitchRow(
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: onChanged,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
      activeTrackColor: colors.primary,
    );
  }
}

/// 自适应二维码展示弹窗。MD3 用 Dialog；MIUIX 用 squircle 底部表。
/// 用于把 [assetPath] 指向的二维码图片展示出来，并提供"保存"与"关闭"
/// 两个按钮。保存会调用 [saveAssetImageToFile] 落盘并通过 SnackBar 提示。
void showAssetQrDialog(
  BuildContext context, {
  required String title,
  required String assetPath,
  required String fileNamePrefix,
  String? caption,
}) {
  if (UiStyleScope.of(context) == UiStyle.miuix) {
    showMiuixAssetQrSheet(
      context,
      title: title,
      assetPath: assetPath,
      fileNamePrefix: fileNamePrefix,
      caption: caption,
    );
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(dialogContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  assetPath,
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  semanticLabel: '$title 二维码',
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 16),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final path = await saveAssetImageToFile(
                            assetPath,
                            fileNamePrefix,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (context.mounted) {
                            showCampusSnackBar(
                              context,
                              SnackBar(
                                content: Text('二维码已保存到：$path'),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            showCampusSnackBar(
                              context,
                              SnackBar(
                                content: Text('保存失败：$e'),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('保存'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
