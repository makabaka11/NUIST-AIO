import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// 向子树广播当前 UI 风格。组件据此在 MD3 / MIUIX 实现间选择，
/// 无需在每个调用点显式传 AppState。
class UiStyleScope extends InheritedWidget {
  const UiStyleScope({super.key, required this.style, required super.child});

  final UiStyle style;

  static UiStyle of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<UiStyleScope>();
    return w?.style ?? UiStyle.material3;
  }

  @override
  bool updateShouldNotify(UiStyleScope oldWidget) => style != oldWidget.style;
}
