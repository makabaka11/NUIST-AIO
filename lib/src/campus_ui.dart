/// 页面统一从此处导入 UI。Material 是路由、布局的基础设施；可见控件
/// 在这里按 UiStyle 分派，MIUIX 分支不得返回 MD3 视觉控件。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' as md;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    hide
        Card,
        FilledButton,
        OutlinedButton,
        TextButton,
        IconButton,
        ChoiceChip,
        Chip,
        ListTile,
        AppBar,
        TextField,
        TextFormField,
        SegmentedButton,
        AlertDialog,
        DropdownButtonFormField,
        CircularProgressIndicator,
        LinearProgressIndicator,
        Switch,
        InkWell,
        showModalBottomSheet,
        showAboutDialog,
        RefreshIndicator,
        Slider;
import 'package:flutter_miuix/miuix.dart';

import 'app_state.dart' show UiStyle;
import 'ui_style_scope.dart';

export 'package:flutter/material.dart'
    hide
        Card,
        FilledButton,
        OutlinedButton,
        TextButton,
        IconButton,
        ChoiceChip,
        Chip,
        ListTile,
        AppBar,
        TextField,
        TextFormField,
        SegmentedButton,
        AlertDialog,
        DropdownButtonFormField,
        CircularProgressIndicator,
        LinearProgressIndicator,
        Switch,
        InkWell,
        showModalBottomSheet,
        showAboutDialog,
        RefreshIndicator,
        Slider;

bool _miuix(BuildContext context) => UiStyleScope.of(context) == UiStyle.miuix;

class Card extends StatelessWidget {
  const Card({
    super.key,
    this.child,
    this.color,
    this.shape,
    this.clipBehavior,
    this.margin,
    this.semanticContainer = true,
  });
  final Widget? child;
  final Color? color;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final EdgeInsetsGeometry? margin;
  final bool semanticContainer;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.Card(
        color: color,
        shape: shape,
        clipBehavior: clipBehavior,
        margin: margin,
        semanticContainer: semanticContainer,
        child: child,
      );
    }
    final c = MiuixTheme.of(context).colors;
    Widget result = ClipPath(
      clipper: ShapeBorderClipper(shape: MiuixSquircleBorder(cornerRadius: 16)),
      child: MiuixCard(
        cornerRadius: 16,
        colors: MiuixCardColors(
          color: color ?? c.surfaceContainer,
          contentColor: c.onSurfaceContainer,
        ),
        child: child,
      ),
    );
    if (shape case OutlinedBorder(side: final side)
        when side != BorderSide.none) {
      result = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: MiuixSquircleBorder(cornerRadius: 16, side: side),
        ),
        child: result,
      );
    }
    if (margin != null) result = Padding(padding: margin!, child: result);
    return Semantics(container: semanticContainer, child: result);
  }
}

enum _ButtonKind { primary, secondary, text }

Widget _button(
  BuildContext context, {
  required _ButtonKind kind,
  required Widget child,
  required VoidCallback? onPressed,
  Widget? icon,
  ButtonStyle? style,
}) {
  final content = icon == null
      ? child
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 8),
            Flexible(child: child),
          ],
        );
  if (!_miuix(context)) {
    return switch (kind) {
      _ButtonKind.primary =>
        icon == null
            ? md.FilledButton(onPressed: onPressed, style: style, child: child)
            : md.FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: child,
              ),
      _ButtonKind.secondary =>
        icon == null
            ? md.OutlinedButton(
                onPressed: onPressed,
                style: style,
                child: child,
              )
            : md.OutlinedButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: child,
              ),
      _ButtonKind.text =>
        icon == null
            ? md.TextButton(onPressed: onPressed, style: style, child: child)
            : md.TextButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: child,
              ),
    };
  }
  final c = MiuixTheme.of(context).colors;
  final primary = kind == _ButtonKind.primary;
  final foreground = primary ? c.onPrimary : c.primary;
  final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
  Widget result = MiuixButton(
    onPressed: onPressed,
    colors: MiuixButtonColors(
      color: primary
          ? c.primary
          : kind == _ButtonKind.text
          ? Colors.transparent
          : c.secondaryVariant,
      disabledColor: primary
          ? c.disabledPrimaryButton
          : c.disabledSecondaryVariant,
      contentColor: foreground,
      disabledContentColor: c.disabledOnPrimaryButton,
    ),
    insideMargin:
        style?.padding?.resolve(states) ??
        const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
    child: IconTheme.merge(
      data: IconThemeData(
        color: onPressed == null ? c.disabledOnPrimaryButton : foreground,
        size: 20,
      ),
      child: content,
    ),
  );
  final minimum = style?.minimumSize?.resolve(states);
  if (minimum != null) {
    result = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minimum.width,
        minHeight: minimum.height,
      ),
      child: result,
    );
  }
  return result;
}

class FilledButton extends StatelessWidget {
  const FilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       _tonal = false;
  const FilledButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.style,
  }) : child = label,
       _tonal = false;
  const FilledButton.tonalIcon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.style,
  }) : child = label,
       _tonal = true;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool _tonal;
  static ButtonStyle styleFrom({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Color? backgroundColor,
    Color? foregroundColor,
  }) => md.FilledButton.styleFrom(
    padding: padding,
    minimumSize: minimumSize,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
  );
  @override
  Widget build(BuildContext context) {
    if (_tonal && !_miuix(context)) {
      return md.FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: icon,
        label: child,
        style: style,
      );
    }
    return _button(
      context,
      kind: _tonal ? _ButtonKind.secondary : _ButtonKind.primary,
      child: child,
      icon: icon,
      onPressed: onPressed,
      style: style,
    );
  }
}

class OutlinedButton extends StatelessWidget {
  const OutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       _tonal = false;
  const OutlinedButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.style,
  }) : child = label,
       _tonal = false;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool _tonal;
  static ButtonStyle styleFrom({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Color? backgroundColor,
    Color? foregroundColor,
  }) => md.OutlinedButton.styleFrom(
    padding: padding,
    minimumSize: minimumSize,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
  );
  @override
  Widget build(BuildContext context) {
    return _button(
      context,
      kind: _tonal ? _ButtonKind.secondary : _ButtonKind.secondary,
      child: child,
      icon: icon,
      onPressed: onPressed,
      style: style,
    );
  }
}

class TextButton extends StatelessWidget {
  const TextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       _tonal = false;
  const TextButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.style,
  }) : child = label,
       _tonal = false;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool _tonal;
  static ButtonStyle styleFrom({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Color? backgroundColor,
    Color? foregroundColor,
  }) => md.TextButton.styleFrom(
    padding: padding,
    minimumSize: minimumSize,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
  );
  @override
  Widget build(BuildContext context) {
    return _button(
      context,
      kind: _tonal ? _ButtonKind.secondary : _ButtonKind.text,
      child: child,
      icon: icon,
      onPressed: onPressed,
      style: style,
    );
  }
}

class IconButton extends StatelessWidget {
  const IconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.color,
    this.iconSize,
    this.visualDensity,
    this.padding,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final Color? color;
  final double? iconSize;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.IconButton(
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        color: color,
        iconSize: iconSize,
        visualDensity: visualDensity,
        padding: padding,
      );
    }
    final c = MiuixTheme.of(context).colors;
    Widget result = Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: MiuixIconButton(
        onPressed: onPressed,
        minWidth: 48,
        minHeight: 48,
        child: IconTheme.merge(
          data: IconThemeData(
            size: iconSize ?? 24,
            color: onPressed == null
                ? c.disabledOnPrimaryButton
                : color ?? c.onSurface,
          ),
          child: icon,
        ),
      ),
    );
    if (tooltip != null) result = Tooltip(message: tooltip!, child: result);
    return result;
  }
}

class ChoiceChip extends StatelessWidget {
  const ChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.avatar,
    this.showCheckmark,
    this.selectedColor,
    this.labelStyle,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  final bool? showCheckmark;
  final Color? selectedColor;
  final TextStyle? labelStyle;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        avatar: avatar,
        showCheckmark: showCheckmark,
        selectedColor: selectedColor,
        labelStyle: labelStyle,
      );
    }
    final c = MiuixTheme.of(context).colors;
    final fg =
        labelStyle?.color ?? (selected ? c.onPrimary : c.onSecondaryVariant);
    return Semantics(
      selected: selected,
      button: true,
      enabled: onSelected != null,
      child: MiuixButton(
        onPressed: onSelected == null ? null : () => onSelected!(!selected),
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        colors: MiuixButtonColors(
          color: selected ? selectedColor ?? c.primary : c.secondaryVariant,
          disabledColor: c.disabledSecondaryVariant,
          contentColor: fg,
          disabledContentColor: c.disabledOnSecondaryVariant,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: fg, size: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatar != null) ...[avatar!, const SizedBox(width: 8)],
              label,
            ],
          ),
        ),
      ),
    );
  }
}

class Chip extends StatelessWidget {
  const Chip({super.key, required this.label});
  final Widget label;
  @override
  Widget build(BuildContext context) => !_miuix(context)
      ? md.Chip(label: label)
      : MiuixCard(
          cornerRadius: 12,
          insideMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: label,
        );
}

class ListTile extends StatelessWidget {
  const ListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.dense,
    this.isThreeLine = false,
    this.enabled = true,
    this.selected = false,
  });
  final Widget? leading, title, subtitle, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;
  final bool isThreeLine, enabled, selected;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
        contentPadding: contentPadding,
        dense: dense,
        isThreeLine: isThreeLine,
        enabled: enabled,
        selected: selected,
      );
    }
    final theme = MiuixTheme.of(context);
    final c = theme.colors;
    if (title is Text &&
        (title as Text).data != null &&
        (subtitle == null ||
            subtitle is Text && (subtitle as Text).data != null)) {
      return MiuixBasicComponent(
        title: (title as Text).data,
        summary: (subtitle as Text?)?.data,
        startAction: leading,
        endActions: trailing == null ? null : [trailing!],
        onClick: onTap,
        enabled: enabled,
        insideMargin:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      );
    }
    return MiuixPressable(
      onPressed: enabled ? onTap : null,
      enabled: enabled && onTap != null,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Padding(
        padding:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: IconTheme.merge(
          data: IconThemeData(color: c.primary),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 16)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      DefaultTextStyle.merge(
                        style: theme.textStyles.body1.copyWith(
                          color: c.onSurface,
                        ),
                        child: title!,
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle.merge(
                        style: theme.textStyles.body2.copyWith(
                          color: c.onSurfaceVariantSummary,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 保留 Scaffold/Navigator 的标准返回语义，视觉独立于 MD3 AppBar。
class AppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.toolbarHeight,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.backgroundColor,
  });
  final Widget? title, leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double? toolbarHeight;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final Color? backgroundColor;
  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.AppBar(
        title: title,
        leading: leading,
        actions: actions,
        bottom: bottom,
        toolbarHeight: toolbarHeight,
        automaticallyImplyLeading: automaticallyImplyLeading,
        centerTitle: centerTitle,
        backgroundColor: backgroundColor,
      );
    }
    final theme = MiuixTheme.of(context);
    final route = ModalRoute.of(context);
    final back =
        leading ??
        (automaticallyImplyLeading && (route?.impliesAppBarDismissal ?? false)
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back),
              )
            : null);
    if (title == null || title is Text && (title as Text).data != null) {
      return MiuixSmallTopAppBar(
        title: (title as Text?)?.data ?? '',
        color: backgroundColor ?? theme.colors.surface,
        navigationIcon: back,
        actions: actions,
        bottomContent: bottom,
      );
    }
    return ColoredBox(
      color: backgroundColor ?? theme.colors.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: toolbarHeight ?? kToolbarHeight,
              child: NavigationToolbar(
                leading: back,
                centerMiddle: centerTitle ?? false,
                middle: DefaultTextStyle.merge(
                  style: theme.textStyles.title2.copyWith(
                    color: theme.colors.onBackground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Padding(
                    padding: EdgeInsets.only(left: back == null ? 20 : 0),
                    child: title,
                  ),
                ),
                trailing: actions == null
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: actions!),
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

class TextField extends StatefulWidget {
  const TextField({
    super.key,
    this.controller,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.onSubmitted,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.enabled,
    this.readOnly = false,
    this.focusNode,
    this.textInputAction,
  });
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged, onSubmitted;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final int? maxLines, minLines;
  final bool autofocus, readOnly;
  final bool? enabled;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  @override
  State<TextField> createState() => _CampusTextFieldState();
}

class _CampusTextFieldState extends State<TextField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != null && widget.controller == null) {
      _controller.value = oldWidget.controller!.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? _controller;
    final focusNode = widget.focusNode ?? _focusNode;
    final TextField(
      :onChanged,
      :decoration,
      :onSubmitted,
      :keyboardType,
      :maxLines,
      :minLines,
      :autofocus,
      :enabled,
      :readOnly,
      :textInputAction,
    ) = widget;
    if (!_miuix(context)) {
      return md.TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: decoration,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        maxLines: maxLines,
        minLines: minLines,
        autofocus: autofocus,
        enabled: enabled,
        readOnly: readOnly,
        focusNode: focusNode,
        textInputAction: textInputAction,
      );
    }
    return MiuixTextField(
      controller: controller,
      onChanged: onChanged,
      label: decoration.labelText ?? decoration.hintText ?? '',
      useLabelAsPlaceholder: decoration.labelText == null,
      leadingIcon: decoration.prefixIcon,
      trailingIcon: decoration.suffixIcon,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      singleLine: maxLines == 1,
      maxLines: maxLines,
      minLines: minLines,
      autofocus: autofocus,
      enabled: enabled ?? true,
      readOnly: readOnly,
      focusNode: focusNode,
      textInputAction: textInputAction,
    );
  }
}

class TextFormField extends StatelessWidget {
  const TextFormField({
    super.key,
    this.controller,
    this.decoration = const InputDecoration(),
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });
  final TextEditingController? controller;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int? maxLines;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.TextFormField(
        controller: controller,
        decoration: decoration,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
      );
    }
    return FormField<String>(
      initialValue: controller?.text,
      validator: (value) => validator?.call(controller?.text ?? value),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: decoration,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: field.didChange,
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 16),
              child: Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class SegmentedButton<T> extends StatelessWidget {
  const SegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.showSelectedIcon = true,
  });
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool showSelectedIcon;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.SegmentedButton<T>(
        segments: segments,
        selected: selected,
        onSelectionChanged: onSelectionChanged,
        showSelectedIcon: showSelectedIcon,
      );
    }
    if (segments.every(
      (segment) =>
          segment.label is Text &&
          (segment.label as Text).data != null &&
          segment.enabled,
    )) {
      final labels = segments
          .map((segment) => (segment.label as Text).data!)
          .toList();
      final scaler = MediaQuery.textScalerOf(context);
      var minWidth = 80.0;
      for (final label in labels) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: MiuixTheme.of(context).textStyles.body2,
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        minWidth = math.max(minWidth, painter.width + 36);
        painter.dispose();
      }
      return LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.hasBoundedWidth
              ? constraints.maxWidth
              : minWidth * labels.length + 8,
          child: IgnorePointer(
            ignoring: onSelectionChanged == null,
            child: MiuixTabRowWithContour(
              tabs: labels,
              selectedTabIndex: math.max(
                0,
                segments.indexWhere(
                  (segment) => selected.contains(segment.value),
                ),
              ),
              onTabSelected: (index) =>
                  onSelectionChanged?.call({segments[index].value}),
              minWidth: minWidth,
              maxWidth: math.max(180, minWidth),
              height: scaler.scale(14) + 28,
            ),
          ),
        ),
      );
    }
    // 自定义富文本标签或部分禁用项仍使用 MIUIX 按钮，保留对应的交互语义。
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget segment(int i) => ChoiceChip(
          label: segments[i].label ?? const SizedBox.shrink(),
          selected: selected.contains(segments[i].value),
          onSelected: onSelectionChanged == null || !segments[i].enabled
              ? null
              : (_) => onSelectionChanged!({segments[i].value}),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              if (constraints.hasBoundedWidth)
                Expanded(child: segment(i))
              else
                segment(i),
            ],
          ],
        );
      },
    );
  }
}

class AlertDialog extends StatelessWidget {
  const AlertDialog({super.key, this.title, this.content, this.actions});
  final Widget? title, content;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.AlertDialog(title: title, content: content, actions: actions);
    }
    final t = MiuixTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: MiuixCard(
          cornerRadius: 32,
          insideMargin: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: t.textStyles.title2.copyWith(
                      color: t.colors.onSurface,
                    ),
                    child: title!,
                  ),
                if (content != null) ...[const SizedBox(height: 16), content!],
                if (actions != null) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Material 的模态路由仅承担焦点、拖拽、返回值与无障碍屏障；MIUIX
/// 内容及轮廓独立绘制，且弹层在 Navigator 内继承当前风格。
Future<T?> showModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool? showDragHandle,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool useRootNavigator = false,
  Color? barrierColor,
  AnimationController? transitionAnimationController,
  AnimationStyle? sheetAnimationStyle,
}) {
  if (!_miuix(context)) {
    return md.showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      shape: shape,
      useRootNavigator: useRootNavigator,
      barrierColor: barrierColor,
      transitionAnimationController: transitionAnimationController,
      sheetAnimationStyle: sheetAnimationStyle,
    );
  }
  return md.showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor,
    transitionAnimationController: transitionAnimationController,
    sheetAnimationStyle: sheetAnimationStyle,
    backgroundColor:
        backgroundColor ?? MiuixTheme.of(context).colors.background,
    shape: MiuixSquircleBorder(cornerRadius: 28),
    showDragHandle: false,
    builder: (context) => ClipPath(
      clipper: ShapeBorderClipper(shape: MiuixSquircleBorder(cornerRadius: 28)),
      child: builder(context),
    ),
  );
}

class DropdownButtonFormField<T> extends StatelessWidget {
  const DropdownButtonFormField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = false,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      return md.DropdownButtonFormField<T>(
        initialValue: initialValue,
        items: items,
        onChanged: onChanged,
        decoration: decoration,
        isExpanded: isExpanded,
      );
    }
    Widget? selected;
    for (final item in items ?? <DropdownMenuItem<T>>[]) {
      if (item.value == initialValue) selected = item.child;
    }
    return MiuixCard(
      child: ListTile(
        title: selected ?? Text(decoration.hintText ?? '请选择'),
        subtitle: decoration.labelText == null
            ? null
            : Text(decoration.labelText!),
        trailing: const Icon(Icons.unfold_more),
        enabled: onChanged != null,
        onTap: onChanged == null
            ? null
            : () async {
                final value = await showModalBottomSheet<T>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (sheet) => ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(sheet).height * .7,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      children: [
                        for (final item in items ?? <DropdownMenuItem<T>>[])
                          ListTile(
                            title: item.child,
                            enabled: item.enabled,
                            trailing: item.value == initialValue
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(sheet, item.value),
                          ),
                      ],
                    ),
                  ),
                );
                if (context.mounted && value != null) onChanged!(value);
              },
      ),
    );
  }
}

class CircularProgressIndicator extends StatelessWidget {
  const CircularProgressIndicator({
    super.key,
    this.value,
    this.strokeWidth = 4,
    this.color,
  });
  final double? value;
  final double strokeWidth;
  final Color? color;
  @override
  Widget build(BuildContext context) => !_miuix(context)
      ? md.CircularProgressIndicator(
          value: value,
          strokeWidth: strokeWidth,
          color: color,
        )
      : MiuixCircularProgressIndicator(
          progress: value,
          strokeWidth: strokeWidth,
        );
}

class LinearProgressIndicator extends StatelessWidget {
  const LinearProgressIndicator({
    super.key,
    this.value,
    this.minHeight,
    this.borderRadius,
    this.color,
    this.backgroundColor,
    this.valueColor,
  });
  final double? value, minHeight;
  final BorderRadiusGeometry? borderRadius;
  final Color? color, backgroundColor;
  final Animation<Color?>? valueColor;
  @override
  Widget build(BuildContext context) => !_miuix(context)
      ? md.LinearProgressIndicator(
          value: value,
          minHeight: minHeight,
          borderRadius: borderRadius,
          color: color,
          backgroundColor: backgroundColor,
          valueColor: valueColor,
        )
      : MiuixLinearProgressIndicator(
          progress: value,
          height: minHeight ?? 4,
          colors: MiuixProgressIndicatorColors(
            foregroundColor:
                valueColor?.value ??
                color ??
                MiuixTheme.of(context).colors.primary,
            disabledForegroundColor: MiuixTheme.of(context)
                .colors
                .disabledPrimarySlider,
            backgroundColor:
                backgroundColor ??
                MiuixTheme.of(context).colors.secondaryContainer,
          ),
        );
}

class Switch extends StatelessWidget {
  const Switch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => !_miuix(context)
      ? md.Switch(value: value, onChanged: onChanged)
      : MiuixSwitch(
          value: value,
          onChanged: onChanged,
          enabled: onChanged != null,
        );
}

class InkWell extends StatelessWidget {
  const InkWell({
    super.key,
    this.onTap,
    this.onLongPress,
    this.child,
    this.borderRadius,
    this.customBorder,
  });
  final VoidCallback? onTap, onLongPress;
  final Widget? child;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  @override
  Widget build(BuildContext context) => !_miuix(context)
      ? md.InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          customBorder: customBorder,
          child: child,
        )
      : MiuixPressable(
          onPressed: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius ?? BorderRadius.circular(16),
          feedbackType: MiuixPressFeedbackType.sink,
          child: child ?? const SizedBox.shrink(),
        );
}

void showAboutDialog({
  required BuildContext context,
  String? applicationName,
  String? applicationVersion,
  Widget? applicationIcon,
  List<Widget>? children,
}) {
  if (!_miuix(context)) {
    md.showAboutDialog(
      context: context,
      applicationName: applicationName,
      applicationVersion: applicationVersion,
      applicationIcon: applicationIcon,
      children: children,
    );
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(applicationName ?? '关于'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?applicationIcon,
          if (applicationVersion != null) Text(applicationVersion),
          const SizedBox(height: 16),
          ...?children,
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const _CampusLicensesPage(),
            ),
          ),
          child: const Text('开源许可'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 共用 ScaffoldMessenger 的排队/关闭生命周期，消息表面按当前风格绘制。
void showCampusSnackBar(BuildContext context, md.SnackBar message) {
  if (!_miuix(context)) {
    ScaffoldMessenger.of(context).showSnackBar(message);
    return;
  }
  final c = MiuixTheme.of(context).colors;
  ScaffoldMessenger.of(context).showSnackBar(
    md.SnackBar(
      duration: message.duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      content: MiuixCard(
        cornerRadius: 18,
        colors: MiuixCardColors(
          color: message.backgroundColor ?? c.surfaceContainerHighest,
          contentColor: c.onSurfaceContainerHighest,
        ),
        insideMargin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: c.onSurfaceContainerHighest),
          child: message.content,
        ),
      ),
    ),
  );
}

class RefreshIndicator extends StatefulWidget {
  const RefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  State<RefreshIndicator> createState() => _RefreshIndicatorState();
}

class _RefreshIndicatorState extends State<RefreshIndicator> {
  bool refreshing = false;
  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => !_miuix(context)
      ? md.RefreshIndicator(onRefresh: widget.onRefresh, child: widget.child)
      : MiuixPullToRefresh(
          isRefreshing: refreshing,
          onRefresh: refresh,
          refreshTexts: const ['下拉刷新', '松开刷新', '正在刷新', '刷新完成'],
          child: widget.child,
        );
}

class _CampusLicensesPage extends StatefulWidget {
  const _CampusLicensesPage();
  @override
  State<_CampusLicensesPage> createState() => _CampusLicensesPageState();
}

class _CampusLicensesPageState extends State<_CampusLicensesPage> {
  late final licenses = LicenseRegistry.licenses.toList();

  void openLicense(LicenseEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(entry.packages.join('、'))),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              entry.paragraphs.map((p) => p.text).join('\n\n'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppBar(title: Text('开源许可')),
    body: FutureBuilder<List<LicenseEntry>>(
      future: licenses,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('许可信息暂时无法加载。'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final entry = snapshot.data![index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Card(
                child: ListTile(
                  title: Text(entry.packages.join('、')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLicense(entry),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

void showCampusLicenses(BuildContext context) {
  if (!_miuix(context)) {
    showLicensePage(
      context: context,
      applicationName: '信大AIO',
      applicationVersion: '0.3.5',
    );
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const _CampusLicensesPage()));
}

/// 行内加载状态，使用当前风格的进度组件，不使用字符或静态沙漏图标。
class InlineLoadingIndicator extends StatelessWidget {
  const InlineLoadingIndicator({super.key, this.size = 16});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CircularProgressIndicator(strokeWidth: 2),
  );
}

class LoadingText extends StatelessWidget {
  const LoadingText(this.text, {super.key, this.loading = true, this.style});
  final String text;
  final bool loading;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (loading) ...[
        const InlineLoadingIndicator(),
        const SizedBox(width: 10),
      ],
      Flexible(child: Text(text, style: style)),
    ],
  );
}

class Slider extends StatelessWidget {
  const Slider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.fixedTicks = false,
  });
  final double value, min, max;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final int? divisions;
  final String? label;
  final bool fixedTicks;

  Widget _ticks(BuildContext context, Widget slider) {
    if (!fixedTicks || divisions == null) return slider;
    // 刻度单独绘制，避免被已填充轨道或滑块遮住而产生节点数变化的错觉。
    final color = _miuix(context)
        ? MiuixTheme.of(context).colors.onSurfaceVariantSummary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        slider,
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i <= divisions!; i++)
                  Container(
                    key: ValueKey('slider-fixed-tick-$i'),
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_miuix(context)) {
      final slider = md.Slider(
        value: value,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
      );
      return _ticks(
        context,
        !fixedTicks
            ? slider
            : SliderTheme(
                data: SliderTheme.of(context)
                    .copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
                child: slider,
              ),
      );
    }
    var latestValue = value;
    return _ticks(
      context,
      Semantics(
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            width: double.infinity,
            child: MiuixSlider(
              value: value,
              onValueChanged: onChanged == null
                  ? null
                  : (next) {
                      latestValue = next;
                      onChanged!(next);
                    },
              min: min,
              max: max,
              steps: divisions == null ? 0 : math.max(0, divisions! - 1),
              onValueChangeFinished: () => onChangeEnd?.call(latestValue),
            ),
          ),
        ),
      ),
    );
  }
}
