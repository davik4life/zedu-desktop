import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

class _MockStorage extends Mock implements SecureStorageService {}

MessageReminder _reminder(String id) => MessageReminder(
  id: id,
  channelId: 'dm-1',
  channelName: 'Amara',
  senderName: 'Amara',
  preview: 'Hi',
  dueAt: DateTime(2026, 11, 9, 9),
  createdAt: DateTime(2026, 11, 8),
);

void main() {
  late _MockStorage storage;
  late ReminderStore store;
  const key = 'message_reminders_u1_org1';

  setUp(() {
    storage = _MockStorage();
    store = ReminderStore(() => storage, userId: 'u1', orgId: 'org1');
  });

  test('keys the list by user and org', () async {
    when(() => storage.readData(any())).thenAnswer((_) async => null);
    await store.load();
    verify(() => storage.readData(key)).called(1);
  });

  test('loads nothing when nothing was saved', () async {
    when(() => storage.readData(key)).thenAnswer((_) async => null);
    expect(await store.load(), isEmpty);
  });

  test('saves and loads the same reminders', () async {
    String? saved;
    when(() => storage.writeData(key, any())).thenAnswer((invocation) async {
      saved = invocation.positionalArguments[1] as String;
    });
    expect(await store.save([_reminder('a'), _reminder('b')]), isTrue);

    when(() => storage.readData(key)).thenAnswer((_) async => saved);
    final loaded = await store.load();
    expect(loaded.map((r) => r.id), ['a', 'b']);
  });

  test('skips a damaged entry and keeps the rest', () async {
    final raw = jsonEncode([
      _reminder('good').toJson(),
      {'id': 'broken'},
      'junk',
    ]);
    when(() => storage.readData(key)).thenAnswer((_) async => raw);
    expect((await store.load()).map((r) => r.id), ['good']);
  });

  test('corrupt storage loads as empty instead of throwing', () async {
    when(() => storage.readData(key)).thenAnswer((_) async => '{not json');
    expect(await store.load(), isEmpty);
    when(() => storage.readData(key)).thenAnswer((_) async => '{"a":1}');
    expect(await store.load(), isEmpty);
  });

  test('a storage read error loads as empty instead of throwing', () async {
    when(() => storage.readData(key)).thenThrow(Exception('keychain locked'));
    expect(await store.load(), isEmpty);
  });

  test('a storage write error reports false instead of throwing', () async {
    when(
      () => storage.writeData(key, any()),
    ).thenThrow(Exception('keychain locked'));
    expect(await store.save([_reminder('a')]), isFalse);
  });

  test('storage that is not available never throws', () async {
    final unavailable = ReminderStore(
      () => throw StateError('not registered'),
      userId: 'u1',
      orgId: 'org1',
    );
    expect(await unavailable.load(), isEmpty);
    expect(await unavailable.save([_reminder('a')]), isFalse);
  });

  test('saving an empty list removes the entry', () async {
    when(() => storage.deleteValue(key)).thenAnswer((_) async {});
    expect(await store.save(const []), isTrue);
    verify(() => storage.deleteValue(key)).called(1);
    verifyNever(() => storage.writeData(any(), any()));
  });
}
