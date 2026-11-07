import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

/// The user's reminders ("Remind me" on a message), shown at the top of the
/// notifications panel: the ones that are due first, then the upcoming ones.
/// Clicking a row opens the chat; the check button marks it done and the
/// clock button snoozes it. Draws nothing when there are none.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);
    if (reminders.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final now = ref.watch(reminderClockProvider)();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(
            'Reminders',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textHint,
            ),
          ),
        ),
        for (final reminder in reminders)
          ReminderTile(
            key: ValueKey('reminder-${reminder.id}'),
            reminder: reminder,
            now: now,
          ),
        Divider(height: 1, color: colors.divider),
      ],
    );
  }
}

class ReminderTile extends ConsumerWidget {
  const ReminderTile({super.key, required this.reminder, required this.now});

  final MessageReminder reminder;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final due = reminder.isDue(now);
    final notifier = ref.read(remindersProvider.notifier);
    final who = reminder.senderName.isEmpty ? '' : '${reminder.senderName}: ';

    return InkWell(
      onTap: () {
        ref.read(reminderOpenerProvider)(reminder);
        Navigator.of(context).pop();
      },
      mouseCursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.primaryBg,
              child: Icon(
                Icons.person_outline,
                size: 16,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    '$who${reminder.preview}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    due
                        ? 'Due ${reminderDueLabel(context, reminder.dueAt, now)}'
                        : 'Reminds ${reminderDueLabel(context, reminder.dueAt, now)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: due ? FontWeight.w600 : FontWeight.normal,
                      color: due ? colors.primary : colors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<DateTime>(
              key: ValueKey('snooze-${reminder.id}'),
              tooltip: 'Snooze',
              icon: Icon(
                Icons.snooze_outlined,
                size: 18,
                color: colors.textHint,
              ),
              onSelected: (time) => notifier.snooze(reminder.id, time),
              itemBuilder: (_) => [
                for (final preset in reminderPresets(now))
                  PopupMenuItem(value: preset.dueAt, child: Text(preset.label)),
              ],
            ),
            IconButton(
              key: ValueKey('done-${reminder.id}'),
              tooltip: 'Mark as done',
              icon: Icon(
                Icons.check_circle_outline,
                size: 18,
                color: colors.textHint,
              ),
              onPressed: () => notifier.dismiss(reminder.id),
            ),
          ],
        ),
      ),
    );
  }
}
