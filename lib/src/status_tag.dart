import 'campus_ui.dart';

/// Text and shape accompany color so status remains readable without color.
class StatusTag extends StatelessWidget {
  const StatusTag(this.label, {super.key, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

Color categoryAccent(BuildContext context, String category) {
  final colors = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final palette = [
    colors.primary,
    colors.tertiary,
    colors.secondary,
    dark ? Colors.teal.shade200 : Colors.teal.shade800,
    dark ? Colors.orange.shade200 : Colors.deepOrange.shade800,
  ];
  final hash = category.runes.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return palette[hash % palette.length];
}
