import 'package:flutter_test/flutter_test.dart';
import 'package:zedu/features/features.dart';

MessageReminder _reminder({DateTime? dueAt, DateTime? firedAt}) =>
    MessageReminder(
      id: 'r1',
      channelId: 'c1',
      channelName: 'general',
      senderName: 'Amara',
      preview: 'Hello',
      dueAt: dueAt ?? DateTime(2026, 11, 9, 9),
      createdAt: DateTime(2026, 11, 8, 12),
      messageId: 'm1',
      firedAt: firedAt,
    );

void main() {
  group('reminderPresets', () {
    // Saturday 7 Nov 2026, 14:30.
    final saturday = DateTime(2026, 11, 7, 14, 30);

    test('offers three relative choices and two 9:00 choices', () {
      final presets = reminderPresets(saturday);
      expect(presets.map((p) => p.label), [
        'In 20 minutes',
        'In 1 hour',
        'In 3 hours',
        'Tomorrow at 9:00',
        'Next Monday at 9:00',
      ]);
      expect(presets[0].dueAt, DateTime(2026, 11, 7, 14, 50));
      expect(presets[1].dueAt, DateTime(2026, 11, 7, 15, 30));
      expect(presets[2].dueAt, DateTime(2026, 11, 7, 17, 30));
      expect(presets[3].dueAt, DateTime(2026, 11, 8, 9));
      expect(presets[4].dueAt, DateTime(2026, 11, 9, 9));
    });

    test('on a Monday, next Monday is a week away', () {
      final monday = DateTime(2026, 11, 9, 8);
      expect(reminderPresets(monday).last.dueAt, DateTime(2026, 11, 16, 9));
    });

    test('on a Sunday, next Monday is tomorrow so it is not offered twice', () {
      final sunday = DateTime(2026, 11, 8, 20);
      final labels = reminderPresets(sunday).map((p) => p.label);
      expect(labels, contains('Tomorrow at 9:00'));
      expect(labels, isNot(contains('Next Monday at 9:00')));
    });

    test('tomorrow rolls over a month end', () {
      final lastDay = DateTime(2026, 11, 30, 22);
      expect(reminderPresets(lastDay)[3].dueAt, DateTime(2026, 12, 1, 9));
    });
  });

  group('MessageReminder', () {
    test('is due once its time has passed, and not before', () {
      final r = _reminder(dueAt: DateTime(2026, 11, 9, 9));
      expect(r.isDue(DateTime(2026, 11, 9, 8, 59)), isFalse);
      expect(r.isDue(DateTime(2026, 11, 9, 9)), isTrue);
    });

    test('needs a notification only until it was notified', () {
      final now = DateTime(2026, 11, 9, 10);
      expect(_reminder().needsNotification(now), isTrue);
      expect(_reminder(firedAt: now).needsNotification(now), isFalse);
    });

    test('snoozing clears the notified mark so it notifies again', () {
      final fired = _reminder(firedAt: DateTime(2026, 11, 9, 9, 1));
      final snoozed = fired.snoozedTo(DateTime(2026, 11, 9, 10));
      expect(snoozed.firedAt, isNull);
      expect(snoozed.dueAt, DateTime(2026, 11, 9, 10));
      expect(snoozed.id, fired.id);
    });

    test('survives a JSON round trip', () {
      final original = _reminder(firedAt: DateTime(2026, 11, 9, 9, 1));
      final copy = MessageReminder.tryFromJson(original.toJson())!;
      expect(copy.id, original.id);
      expect(copy.channelId, 'c1');
      expect(copy.channelName, 'general');
      expect(copy.messageId, 'm1');
      expect(copy.dueAt.isAtSameMomentAs(original.dueAt), isTrue);
      expect(copy.firedAt!.isAtSameMomentAs(original.firedAt!), isTrue);
    });

    test('a damaged record is rejected instead of throwing', () {
      expect(MessageReminder.tryFromJson(null), isNull);
      expect(MessageReminder.tryFromJson('text'), isNull);
      expect(MessageReminder.tryFromJson(<String, dynamic>{}), isNull);
      final good = _reminder().toJson();
      expect(MessageReminder.tryFromJson({...good, 'id': ''}), isNull);
      expect(
        MessageReminder.tryFromJson({...good, 'channel_id': null}),
        isNull,
      );
      expect(MessageReminder.tryFromJson({...good, 'due_at': 'soon'}), isNull);
    });
  });

  group('reminderPreviewText', () {
    test('strips markup and collapses whitespace', () {
      expect(
        reminderPreviewText('<p>Hello   <b>there</b></p>\n\nfriend &amp; co'),
        'Hello there friend & co',
      );
    });

    test('leaves a short message alone', () {
      expect(reminderPreviewText('Hi'), 'Hi');
    });

    test('cuts a long message to 77 characters plus an ellipsis', () {
      final out = reminderPreviewText('x' * 200);
      expect(out.length, 80);
      expect(out.endsWith('...'), isTrue);
    });

    test('never splits an emoji at the cut', () {
      final out = reminderPreviewText('${'a' * 76}😀😀😀😀😀');
      expect(out, '${'a' * 76}😀...');
    });
  });
}
