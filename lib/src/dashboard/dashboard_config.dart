import 'dart:convert';

enum DashboardWidgetId {
  library('图书借阅'),
  electricity('宿舍电费'),
  wallet('校园卡余额'),
  spending('本月支出'),
  holiday('下次小长假');

  const DashboardWidgetId(this.label);
  final String label;
}

class DashboardLayout {
  const DashboardLayout({
    this.order = DashboardWidgetId.values,
    this.disabled = const {},
  });
  final List<DashboardWidgetId> order;
  final Set<DashboardWidgetId> disabled;
  List<DashboardWidgetId> get enabled =>
      order.where((id) => !disabled.contains(id)).toList();
  DashboardLayout toggle(DashboardWidgetId id, bool enabled) => DashboardLayout(
    order: order,
    disabled: enabled ? ({...disabled}..remove(id)) : {...disabled, id},
  );
  DashboardLayout reorder(int oldIndex, int newIndex) {
    final next = [...order];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    return DashboardLayout(order: next, disabled: disabled);
  }

  String encode() => jsonEncode({
    'order': order.map((id) => id.name).toList(),
    'disabled': disabled.map((id) => id.name).toList(),
  });
  factory DashboardLayout.decode(String? raw) {
    try {
      final j = jsonDecode(raw!) as Map;
      final byName = {for (final id in DashboardWidgetId.values) id.name: id};
      final order = <DashboardWidgetId>{
        for (final name in j['order'] as List)
          if (byName[name] != null) byName[name]!,
        ...DashboardWidgetId.values,
      }.toList();
      final disabled = {
        for (final name in j['disabled'] as List)
          if (byName[name] != null) byName[name]!,
      };
      return DashboardLayout(order: order, disabled: disabled);
    } catch (_) {
      return const DashboardLayout();
    }
  }
}
