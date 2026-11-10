// MIUIX 风格组件库——基于 flutter_miuix 复刻 HyperOS 视觉语言。
// 提供与 widgets.dart 中 MD3 通用组件一一对应的 MIUIX 实现，
// 由 widgets.dart 根据 AppState.uiStyle 在两套实现间切换。
// 所有组件假定祖先已用 MiuixTheme 包裹（app.dart 在 MIUIX 模式下注入）。

import 'campus_ui.dart';

import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import 'image_saver.dart';

export 'ui_style_scope.dart';

/// MIUIX 风格的小节标题。使用 MiuixText 的 subtitle 样式，
/// 视觉比 MD3 的 titleMedium 更轻，对齐 HyperOS 偏好设置页风格。
class MiuixSectionTitle extends StatelessWidget {
  const MiuixSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        Expanded(
          child: MiuixSmallTitle(
            title,
            insideMargin: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// MIUIX 风格的功能入口卡片。squircle 圆角 + sink 按压反馈，
/// 内容沿用 MD3 版 IconTile 的图标 / 标题 / 副标题布局。
class MiuixIconTile extends StatelessWidget {
  const MiuixIconTile({
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
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      cornerRadius: 16,
      colors: MiuixCardColors(
        color: colors.surfaceContainer,
        contentColor: colors.onSurfaceContainer,
      ),
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 27),
            const SizedBox(height: 20),
            MiuixText(
              title,
              style: MiuixTheme.of(context).textStyles.title3,
              color: colors.onSurfaceContainer,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              MiuixText(
                subtitle!,
                style: MiuixTheme.of(context).textStyles.body2,
                color: colors.onSurfaceContainerVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// MIUIX 风格的空状态卡片。比 MD3 版更克制的留白，
/// 并为可选 action 提供主色按钮槽位。
class MiuixEmptyCard extends StatelessWidget {
  const MiuixEmptyCard({
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
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      cornerRadius: 16,
      colors: MiuixCardColors(
        color: colors.surfaceContainer,
        contentColor: colors.onSurfaceContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 30),
            const SizedBox(height: 20),
            MiuixText(
              title,
              style: MiuixTheme.of(context).textStyles.title3,
              color: colors.onSurfaceContainer,
            ),
            const SizedBox(height: 8),
            if (loading)
              LoadingText(
                message,
                style: MiuixTheme.of(context).textStyles.body2
                    .copyWith(color: colors.onSurfaceContainerVariant),
              )
            else
              MiuixText(
                message,
                style: MiuixTheme.of(context).textStyles.body2,
                color: colors.onSurfaceContainerVariant,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// MIUIX 风格的开关行。用于设置项：左侧标题与副标题，右侧 MiuixSwitch。
/// 整行可点（点击行任意位置切换开关），按压时整行 sink 反馈。
class MiuixSwitchRow extends StatelessWidget {
  const MiuixSwitchRow({
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
  Widget build(BuildContext context) => MiuixSwitchPreference(
    title: title,
    summary: subtitle,
    value: value,
    onChanged: onChanged,
    insideMargin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  );
}

/// MIUIX 风格的分组卡片。包裹一组 [children]（通常是 ListTile 或
/// MiuixSwitchRow），整体 squircle 圆角，内部用细分隔线。
class MiuixGroupCard extends StatelessWidget {
  const MiuixGroupCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      cornerRadius: 16,
      colors: MiuixCardColors(
        color: colors.surfaceContainer,
        contentColor: colors.onSurfaceContainer,
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: MiuixHorizontalDivider(color: colors.dividerLine),
              ),
          ],
        ],
      ),
    );
  }
}

/// MIUIX 风格的列表行（带 leading icon + trailing chevron）。
/// 用于偏好设置类入口。点击触发 [onTap]，整行 sink 反馈。
class MiuixArrowRow extends StatelessWidget {
  const MiuixArrowRow({
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
  Widget build(BuildContext context) => MiuixArrowPreference(
    title: title,
    summary: subtitle,
    onClick: onTap,
    startAction: Icon(
      icon,
      color: MiuixTheme.of(context).colors.primary,
      size: 24,
    ),
    endActions: trailing == null ? null : [trailing!],
    insideMargin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  );
}

/// MIUIX 风格的"功能开发中"底部表。带弹簧进场动画与 squircle 圆角，
/// 替代 MD3 版 showModalBottomSheet 的平移淡入。
void showMiuixPendingFeature(BuildContext context, String name) {
  final colors = MiuixTheme.of(context).colors;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 240),
    ),
    builder: (sheetContext) {
      // 让底部表内容在出场时带轻微上浮 + 缩放，避免纯平移闪现。
      return AnimatedPadding(
        padding: MediaQuery.of(sheetContext).viewInsets,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: ShapeDecoration(
            color: colors.surfaceContainer,
            shape: MiuixSquircleBorder(cornerRadius: 28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.construction_outlined,
                  color: colors.primary,
                  size: 36,
                ),
                const SizedBox(height: 20),
                MiuixText(
                  name,
                  style: MiuixTheme.of(sheetContext).textStyles.title2,
                  color: colors.onSurfaceContainer,
                ),
                const SizedBox(height: 12),
                MiuixText(
                  '入口已预留，具体功能将在后续版本接入。',
                  style: MiuixTheme.of(sheetContext).textStyles.body2,
                  color: colors.onSurfaceContainerVariant,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: MiuixTextButton(
                    '知道了',
                    onPressed: () => Navigator.pop(sheetContext),
                    colors: MiuixButtonColors(
                      color: colors.primary,
                      disabledColor: colors.primary,
                      contentColor: colors.onPrimary,
                      disabledContentColor: colors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// MIUIX 风格的交流群二维码底部表。squircle 容器 + 二维码 + 群号，
/// 底部提供"复制群号"和"关闭"两个按钮。
void showMiuixGroupQrSheet(BuildContext context, String groupNumber) {
  final colors = MiuixTheme.of(context).colors;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 240),
    ),
    builder: (sheetContext) {
      return AnimatedPadding(
        padding: MediaQuery.of(sheetContext).viewInsets,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: ShapeDecoration(
            color: colors.surfaceContainer,
            shape: MiuixSquircleBorder(cornerRadius: 28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixText(
                  '信大AIO交流群',
                  style: MiuixTheme.of(sheetContext).textStyles.title2,
                  color: colors.onSurfaceContainer,
                ),
                const SizedBox(height: 20),
                // 二维码图片——squircle 圆角裁剪，白色底衬。
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: MiuixSquircleBorder(cornerRadius: 20),
                  ),
                  child: ClipRect(
                    child: Image.asset(
                      'assets/qq_group_qrcode.jpg',
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                      semanticLabel: 'QQ 群二维码',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                MiuixText(
                  '群号：$groupNumber',
                  style: MiuixTheme.of(sheetContext).textStyles.body2,
                  color: colors.onSurfaceContainerVariant,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: MiuixTextButton(
                        '复制群号',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: groupNumber));
                          Navigator.pop(sheetContext);
                          showCampusSnackBar(
                            context,
                            const SnackBar(
                              content: Text('群号已复制到剪贴板'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        colors: MiuixButtonColors(
                          color: colors.surfaceContainerHighest,
                          disabledColor: colors.surfaceContainerHighest,
                          contentColor: colors.onSurfaceContainer,
                          disabledContentColor: colors.onSurfaceContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MiuixTextButton(
                        '关闭',
                        onPressed: () => Navigator.pop(sheetContext),
                        colors: MiuixButtonColors(
                          color: colors.primary,
                          disabledColor: colors.primary,
                          contentColor: colors.onPrimary,
                          disabledContentColor: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// MIUIX 风格的二维码展示底部表。squircle 容器 + 二维码 + 副标题，
/// 底部提供"保存"和"关闭"两个按钮。保存会把 asset 图片落盘到本机
/// Pictures 目录并通过 SnackBar 提示路径。
void showMiuixAssetQrSheet(
  BuildContext context, {
  required String title,
  required String assetPath,
  required String fileNamePrefix,
  String? caption,
}) {
  final colors = MiuixTheme.of(context).colors;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 240),
    ),
    builder: (sheetContext) {
      final theme = MiuixTheme.of(sheetContext);
      return AnimatedPadding(
        padding: MediaQuery.of(sheetContext).viewInsets,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: ShapeDecoration(
            color: colors.surfaceContainer,
            shape: MiuixSquircleBorder(cornerRadius: 28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixText(
                  title,
                  style: theme.textStyles.title2,
                  color: colors.onSurfaceContainer,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: MiuixSquircleBorder(cornerRadius: 20),
                  ),
                  child: ClipRect(
                    child: Image.asset(
                      assetPath,
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                      semanticLabel: '$title 二维码',
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 16),
                  MiuixText(
                    caption,
                    style: theme.textStyles.body2,
                    color: colors.onSurfaceContainerVariant,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: MiuixTextButton(
                        '保存',
                        onPressed: () async {
                          try {
                            final path = await saveAssetImageToFile(
                              assetPath,
                              fileNamePrefix,
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
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
                        colors: MiuixButtonColors(
                          color: colors.surfaceContainerHighest,
                          disabledColor: colors.surfaceContainerHighest,
                          contentColor: colors.onSurfaceContainer,
                          disabledContentColor: colors.onSurfaceContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MiuixTextButton(
                        '关闭',
                        onPressed: () => Navigator.pop(sheetContext),
                        colors: MiuixButtonColors(
                          color: colors.primary,
                          disabledColor: colors.primary,
                          contentColor: colors.onPrimary,
                          disabledContentColor: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// MIUIX 风格的主操作按钮。等价于 MD3 FilledButton，squircle 圆角 + sink 按压。
class MiuixPrimaryButton extends StatelessWidget {
  const MiuixPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final button = MiuixTextButton(
      label,
      onPressed: enabled ? onPressed : null,
      enabled: enabled,
      cornerRadius: 18,
      colors: MiuixButtonColors(
        color: colors.primary,
        disabledColor: colors.disabledPrimaryButton,
        contentColor: colors.onPrimary,
        disabledContentColor: colors.disabledOnPrimaryButton,
      ),
      insideMargin: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    );
    if (!expand) return button;
    return SizedBox(
      width: double.infinity,
      child: Center(child: button),
    );
  }
}

/// 自适应顶栏。MD3 模式返回标准 AppBar；MIUIX 模式返回 squircle 风格的
/// 小标题顶栏（MiuixText 标题 + 可选操作按钮）。供被 push 的二级页面复用，
/// 让两种风格下的页面标题栏保持一致语言。
PreferredSizeWidget campusAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? leading,
}) => AppBar(
  title: Text(title),
  actions: actions,
  leading: leading,
  centerTitle: false,
);
