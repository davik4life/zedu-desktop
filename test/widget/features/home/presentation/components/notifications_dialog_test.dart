import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';
import '../../../../../helpers/helpers.dart';

/// No reminders, so these tests do not need the storage and workspace the
/// real list reads.
class _NoReminders extends RemindersNotifier {
  @override
  List<MessageReminder> build() => const [];
}

class _WithReminders extends RemindersNotifier {
  _WithReminders(this.reminders);

  final List<MessageReminder> reminders;

  @override
  List<MessageReminder> build() => reminders;
}

final _reminder = MessageReminder(
  id: 'r1',
  channelId: 'dm-ada',
  channelName: 'Ada',
  participantId: 'p-ada',
  senderName: 'Ada',
  preview: 'Send the course outline',
  dueAt: DateTime(2020),
  createdAt: DateTime(2019),
  firedAt: DateTime(2020),
);

void main() {
  group('NotificationsDialog', () {
    Future<void> openDialog(
      WidgetTester tester, {
      List<MessageReminder> reminders = const [],
      List<Override> overrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remindersProvider.overrideWith(() => _WithReminders(reminders)),
            ...overrides,
          ],
          child: buildTestMaterialApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const NotificationsDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the heading and empty state', (tester) async {
      await openDialog(tester);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text("You're all caught up"), findsOneWidget);
      expect(find.text("There's nothing to show here yet."), findsOneWidget);
    });

    testWidgets('close button is labelled and closes it', (tester) async {
      await openDialog(tester);

      final close = find.widgetWithIcon(IconButton, Icons.close);
      expect(close, findsOneWidget);
      expect(tester.widget<IconButton>(close).tooltip, 'Close');

      await tester.tap(close);
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsDialog), findsNothing);
    });

    group('reminders', () {
      testWidgets('are listed, and replace the empty state', (tester) async {
        await openDialog(tester, reminders: [_reminder]);

        expect(find.text('Reminders'), findsOneWidget);
        expect(find.text('Ada'), findsOneWidget);
        expect(find.text('Ada: Send the course outline'), findsOneWidget);
        expect(find.textContaining('Due '), findsOneWidget);
        expect(find.text("You're all caught up"), findsNothing);
      });

      testWidgets('clicking one opens its chat and closes the panel', (
        tester,
      ) async {
        MessageReminder? opened;
        await openDialog(
          tester,
          reminders: [_reminder],
          overrides: [
            reminderOpenerProvider.overrideWithValue((r) => opened = r),
          ],
        );

        await tester.tap(find.text('Ada'));
        await tester.pumpAndSettle();

        expect(opened?.id, 'r1');
        expect(find.text('Notifications'), findsNothing);
      });

      testWidgets('offer snooze and done on each one', (tester) async {
        await openDialog(tester, reminders: [_reminder]);

        expect(find.byKey(const ValueKey('snooze-r1')), findsOneWidget);
        expect(find.byKey(const ValueKey('done-r1')), findsOneWidget);
      });
    });

    testWidgets('sidebar bell opens the panel', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dueReminderCountProvider.overrideWithValue(0),
            remindersProvider.overrideWith(_NoReminders.new),
          ],
          child: buildTestMaterialApp(
            const Scaffold(
              body: Row(
                children: [AppSidebarRail(activeType: HomeSidebarType.home)],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsDialog), findsOneWidget);
    });
  });
}
