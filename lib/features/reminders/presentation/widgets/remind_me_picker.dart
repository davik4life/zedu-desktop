import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

/// "Today at 3:20 PM", "Tomorrow at 9:00 AM" or "Mon, Nov 9 at 9:00 AM".
String reminderDueLabel(BuildContext context, DateTime due, DateTime now) {
  final time = TimeOfDay.fromDateTime(due).format(context);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final days = day.difference(today).inDays;
  if (days <= 0) return 'today at $time';
  if (days == 1) return 'tomorrow at $time';
  final date = MaterialLocalizations.of(context).formatMediumDate(due);
  return '$date at $time';
}

/// Asks when to remind the user, then saves the reminder and confirms with a
/// toast. Does nothing if the dialog is dismissed.
Future<void> remindAboutMessage(
  BuildContext context,
  WidgetRef ref, {
  required String channelId,
  required String channelName,
  required String senderName,
  required String messageText,
  String? participantId,
  String? messageId,
}) async {
  final notifier = ref.read(remindersProvider.notifier);
  final now = ref.read(reminderClockProvider)();

  final due = await showDialog<DateTime>(
    context: context,
    builder: (_) => ReminderTimeDialog(now: now),
  );
  if (due == null) return;

  final saved = await notifier.add(
    channelId: channelId,
    channelName: channelName,
    senderName: senderName,
    preview: reminderPreviewText(messageText),
    dueAt: due,
    participantId: participantId,
    messageId: messageId,
  );
  // The message can be gone by now (another chat was opened); the reminder
  // is saved either way, only the confirmation is skipped.
  if (!context.mounted) return;
  AppToastService.show(
    context,
    type: saved ? AppToastType.success : AppToastType.error,
    message: saved
        ? "We'll remind you ${reminderWhen(context, due, now)}."
        : "Reminder set, but it couldn't be saved on this device. It works "
              'until you close Zedu.',
  );
}

/// "in 20 min", or the day and time once it is an hour or more away.
String reminderWhen(BuildContext context, DateTime due, DateTime now) {
  final minutes = due.difference(now).inMinutes;
  if (minutes < 60) return 'in ${minutes < 1 ? 1 : minutes} min';
  return reminderDueLabel(context, due, now);
}

/// The "Remind me" choices. Pops the chosen [DateTime], or null on dismiss.
class ReminderTimeDialog extends StatelessWidget {
  const ReminderTimeDialog({super.key, required this.now});

  final DateTime now;

  Future<void> _pickCustom(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !context.mounted) return;
    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!due.isAfter(now)) {
      AppToastService.show(
        context,
        type: AppToastType.error,
        message: 'Pick a time in the future.',
      );
      return;
    }
    Navigator.of(context).pop(due);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 380,
        // Scrolls on a short window or with large text instead of overflowing.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Remind me about this message',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textHint, size: 20),
                    tooltip: 'Close',
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final preset in reminderPresets(now))
                _ChoiceTile(
                  key: ValueKey('remind-${preset.label}'),
                  label: preset.label,
                  hint: reminderDueLabel(context, preset.dueAt, now),
                  onTap: () => Navigator.of(context).pop(preset.dueAt),
                ),
              const SizedBox(height: 8),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: 8),
              _ChoiceTile(
                key: const ValueKey('remind-custom'),
                label: 'Pick a date and time…',
                icon: Icons.event_outlined,
                accent: true,
                onTap: () => _pickCustom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One choice in the picker, styled like the suggestions in the status dialog.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.label,
    required this.onTap,
    this.hint,
    this.icon,
    this.accent = false,
  });

  final String label;
  final String? hint;
  final IconData? icon;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(8);
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: radius,
          hoverColor: colors.primaryBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: accent ? colors.primary : colors.textPrimary,
                    ),
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: colors.textHint,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
