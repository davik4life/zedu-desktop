import 'package:zedu/core/core.dart';

/// A direct message the user asked to be reminded about ("Remind me").
///
/// Stored on this device only. [dueAt] is when the reminder fires, [firedAt]
/// is set once its desktop notification was shown, so a restart never
/// notifies twice for the same reminder.
class MessageReminder {
  const MessageReminder({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.senderName,
    required this.preview,
    required this.dueAt,
    required this.createdAt,
    this.participantId,
    this.messageId,
    this.firedAt,
  });

  final String id;

  /// The DM conversation's channel id.
  final String channelId;

  /// The other person's name.
  final String channelName;

  /// The other person, needed to reopen a conversation that is no longer in
  /// the loaded list.
  final String? participantId;
  final String? messageId;
  final String senderName;

  /// A short plain-text excerpt of the message.
  final String preview;
  final DateTime dueAt;
  final DateTime createdAt;
  final DateTime? firedAt;

  /// True once [dueAt] has passed.
  bool isDue(DateTime now) => !dueAt.isAfter(now);

  /// Due but its notification has not been shown yet.
  bool needsNotification(DateTime now) => firedAt == null && isDue(now);

  MessageReminder copyWith({DateTime? dueAt, DateTime? firedAt}) {
    return MessageReminder(
      id: id,
      channelId: channelId,
      channelName: channelName,
      senderName: senderName,
      preview: preview,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt,
      participantId: participantId,
      messageId: messageId,
      firedAt: firedAt ?? this.firedAt,
    );
  }

  /// A new due time clears [firedAt] so a snoozed reminder notifies again.
  MessageReminder snoozedTo(DateTime dueAt) => MessageReminder(
    id: id,
    channelId: channelId,
    channelName: channelName,
    senderName: senderName,
    preview: preview,
    dueAt: dueAt,
    createdAt: createdAt,
    participantId: participantId,
    messageId: messageId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'channel_id': channelId,
    'channel_name': channelName,
    'participant_id': participantId,
    'message_id': messageId,
    'sender_name': senderName,
    'preview': preview,
    'due_at': dueAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'fired_at': firedAt?.toUtc().toIso8601String(),
  };

  /// Returns null for an entry that is damaged, so one bad record never
  /// hides the rest of the list.
  static MessageReminder? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final channelId = raw['channel_id'];
    final dueAt = DateTime.tryParse('${raw['due_at']}');
    if (id is! String || id.isEmpty) return null;
    if (channelId is! String || channelId.isEmpty) return null;
    if (dueAt == null) return null;
    return MessageReminder(
      id: id,
      channelId: channelId,
      channelName: '${raw['channel_name'] ?? ''}',
      participantId: raw['participant_id'] as String?,
      messageId: raw['message_id'] as String?,
      senderName: '${raw['sender_name'] ?? ''}',
      preview: '${raw['preview'] ?? ''}',
      dueAt: dueAt.toLocal(),
      createdAt: (DateTime.tryParse('${raw['created_at']}') ?? dueAt).toLocal(),
      firedAt: DateTime.tryParse('${raw['fired_at']}')?.toLocal(),
    );
  }
}

/// A "Remind me" choice: the label shown and the time it resolves to.
class ReminderPreset {
  const ReminderPreset(this.label, this.dueAt);

  final String label;
  final DateTime dueAt;
}

/// The quick choices offered for a reminder, relative to [now].
///
/// "Tomorrow" and "Next Monday" land at 9:00 local time. Next Monday is always
/// a later day, so on a Monday it means a week from today.
List<ReminderPreset> reminderPresets(DateTime now) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
  final daysToMonday = (DateTime.monday - now.weekday + 7) % 7;
  final nextMonday = DateTime(
    now.year,
    now.month,
    now.day + (daysToMonday == 0 ? 7 : daysToMonday),
    9,
  );
  return [
    ReminderPreset('In 20 minutes', now.add(const Duration(minutes: 20))),
    ReminderPreset('In 1 hour', now.add(const Duration(hours: 1))),
    ReminderPreset('In 3 hours', now.add(const Duration(hours: 3))),
    ReminderPreset('Tomorrow at 9:00', tomorrow),
    // On a Sunday, next Monday is tomorrow: do not offer the same time twice.
    if (nextMonday != tomorrow)
      ReminderPreset('Next Monday at 9:00', nextMonday),
  ];
}

/// Shortens [text] for a reminder: markup is stripped, whitespace collapsed,
/// and anything over 80 characters (as people see them, so an emoji is never
/// split) is cut to 77 plus "...".
String reminderPreviewText(String text) {
  final plain = text
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final characters = plain.characters;
  if (characters.length <= 80) return plain;
  return '${characters.take(77)}...';
}
