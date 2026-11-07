import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

class _MockStorage extends Mock implements SecureStorageService {}

/// Remembers what was shown instead of posting desktop notifications.
class _FakeAlerts implements ReminderAlerts {
  final shown = <String>[];
  final summaries = <int>[];

  @override
  Future<void> show(MessageReminder reminder) async => shown.add(reminder.id);

  @override
  Future<void> showSummary(int count) async => summaries.add(count);
}

final _user = User(
  id: 'u1',
  firstName: 'Grace',
  lastName: 'Test',
  email: 'test@example.invalid',
  phone: '',
  username: 'tester',
  isVerified: true,
  isOnboarded: true,
  createdAt: DateTime(2026),
  currentOrg: 'org-a',
  currentOrganisationSlug: 'test',
  avatarUrl: '',
  defaultAvatarUrl: '',
);

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: _user);
}

class _Settings extends NotificationSettingsNotifier {
  _Settings({this.dnd = false});
  final bool dnd;

  @override
  NotificationSettings build() => NotificationSettings(
    dndUntil: dnd ? DateTime.now().add(const Duration(hours: 1)) : null,
  );
}

MessageReminder _saved(String id, DateTime dueAt, {DateTime? firedAt}) =>
    MessageReminder(
      id: id,
      channelId: 'c1',
      channelName: 'general',
      senderName: 'Amara',
      preview: 'Hello',
      dueAt: dueAt,
      createdAt: DateTime(2026, 11, 7),
      firedAt: firedAt,
    );

void main() {
  late _MockStorage storage;
  late _FakeAlerts alerts;
  late DateTime clock;
  late List<MessageReminder> saved;

  const key = 'message_reminders_u1_';

  ProviderContainer makeContainer({bool dnd = false}) {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_Auth.new),
        notificationSettingsProvider.overrideWith(() => _Settings(dnd: dnd)),
        reminderStoreProvider.overrideWithValue(
          ReminderStore(() => storage, userId: 'u1', orgId: ''),
        ),
        reminderClockProvider.overrideWithValue(() => clock),
        reminderAlertsProvider.overrideWithValue(alerts),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    storage = _MockStorage();
    alerts = _FakeAlerts();
    clock = DateTime(2026, 11, 7, 10);
    saved = [];
    when(() => storage.readData(key)).thenAnswer(
      (_) async =>
          saved.isEmpty ? null : '[${saved.map((r) => _json(r)).join(',')}]',
    );
    when(() => storage.writeData(key, any())).thenAnswer((_) async {});
    when(() => storage.deleteValue(key)).thenAnswer((_) async {});
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('adding saves the reminder, sorted by due time', () async {
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await settle();

    final later = await notifier.add(
      channelId: 'c1',
      channelName: 'general',
      senderName: 'Amara',
      preview: 'second',
      dueAt: clock.add(const Duration(hours: 2)),
    );
    await notifier.add(
      channelId: 'dm1',
      channelName: 'Jonas',
      senderName: 'Jonas',
      preview: 'first',
      dueAt: clock.add(const Duration(minutes: 20)),
    );

    expect(later, isTrue);
    final list = container.read(remindersProvider);
    expect(list.map((r) => r.preview), ['first', 'second']);
    verify(() => storage.writeData(key, any())).called(2);
  });

  test('add reports false when the device cannot save it', () async {
    when(() => storage.writeData(key, any())).thenThrow(Exception('locked'));
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await settle();

    final ok = await notifier.add(
      channelId: 'c1',
      channelName: 'general',
      senderName: 'A',
      preview: 'x',
      dueAt: clock.add(const Duration(hours: 1)),
    );

    expect(ok, isFalse);
    // Still held in memory, so it works until the app closes.
    expect(container.read(remindersProvider), hasLength(1));
  });

  test('a long preview is shortened', () async {
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await settle();
    await notifier.add(
      channelId: 'c1',
      channelName: 'general',
      senderName: 'A',
      preview: 'x' * 500,
      dueAt: clock.add(const Duration(hours: 1)),
    );
    expect(container.read(remindersProvider).single.preview.length, 201);
  });

  test(
    'loads saved reminders and notifies once for one that came due',
    () async {
      saved = [_saved('due', clock.subtract(const Duration(minutes: 5)))];
      final container = makeContainer();
      container.read(remindersProvider);
      await settle();

      expect(alerts.shown, ['due']);
      final list = container.read(remindersProvider);
      expect(list.single.firedAt, isNotNull);
      expect(container.read(dueReminderCountProvider), 1);

      // A second check does not notify again.
      await container.read(remindersProvider.notifier).checkDue();
      expect(alerts.shown, ['due']);
    },
  );

  test(
    'a reminder already notified before a restart is not repeated',
    () async {
      saved = [
        _saved(
          'old',
          clock.subtract(const Duration(hours: 1)),
          firedAt: clock.subtract(const Duration(minutes: 59)),
        ),
      ];
      final container = makeContainer();
      container.read(remindersProvider);
      await settle();

      expect(alerts.shown, isEmpty);
      expect(container.read(dueReminderCountProvider), 1);
    },
  );

  test('a future reminder does not notify until its time', () async {
    saved = [_saved('soon', clock.add(const Duration(minutes: 30)))];
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await settle();
    expect(alerts.shown, isEmpty);
    expect(container.read(dueReminderCountProvider), 0);

    clock = clock.add(const Duration(minutes: 31));
    await notifier.checkDue();
    expect(alerts.shown, ['soon']);
  });

  test('many missed reminders are announced once', () async {
    saved = [
      for (var i = 0; i < 5; i++)
        _saved('r$i', clock.subtract(Duration(minutes: 10 + i))),
    ];
    final container = makeContainer();
    container.read(remindersProvider);
    await settle();

    expect(alerts.shown, isEmpty);
    expect(alerts.summaries, [5]);
    expect(container.read(dueReminderCountProvider), 5);
  });

  test('do not disturb keeps the reminder due but shows no banner', () async {
    saved = [_saved('due', clock.subtract(const Duration(minutes: 5)))];
    final container = makeContainer(dnd: true);
    container.read(remindersProvider);
    await settle();

    expect(alerts.shown, isEmpty);
    expect(container.read(dueReminderCountProvider), 1);
  });

  test('snoozing makes it notify again at the new time', () async {
    saved = [_saved('due', clock.subtract(const Duration(minutes: 5)))];
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await settle();
    expect(alerts.shown, ['due']);

    await notifier.snooze('due', clock.add(const Duration(hours: 1)));
    expect(container.read(remindersProvider).single.firedAt, isNull);
    expect(container.read(dueReminderCountProvider), 0);

    clock = clock.add(const Duration(hours: 1, minutes: 1));
    await notifier.checkDue();
    expect(alerts.shown, ['due', 'due']);
  });

  test('dismissing removes it and clears the stored entry', () async {
    saved = [_saved('a', clock.add(const Duration(hours: 1)))];
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await settle();
    expect(container.read(remindersProvider), hasLength(1));

    await notifier.dismiss('a');
    expect(container.read(remindersProvider), isEmpty);
    verify(() => storage.deleteValue(key)).called(1);
  });

  test('a reminder added while loading is not lost', () async {
    saved = [_saved('old', clock.add(const Duration(hours: 5)))];
    final container = makeContainer();
    final notifier = container.read(remindersProvider.notifier);
    await notifier.add(
      channelId: 'c1',
      channelName: 'general',
      senderName: 'A',
      preview: 'new',
      dueAt: clock.add(const Duration(hours: 1)),
    );
    await settle();

    expect(
      container.read(remindersProvider).map((r) => r.preview),
      containsAll(['new', 'Hello']),
    );
  });
}

String _json(MessageReminder r) => jsonEncode(r.toJson());
