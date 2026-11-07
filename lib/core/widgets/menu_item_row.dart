import 'package:zedu/core/core.dart';

/// The content of a popup menu item: an outlined icon and a label, spaced the
/// way the account menu does it. [color] tints both, for a destructive action.
class MenuItemRow extends StatelessWidget {
  const MenuItemRow({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 20, color: tint),
        const SizedBox(width: 8),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    );
  }
}
