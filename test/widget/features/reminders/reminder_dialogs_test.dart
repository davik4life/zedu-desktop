import 'package:zedu/features/features.dart';

import '../../../helpers/helpers.dart';

void main() {
  group('ReminderTimeDialog', () {
    final now = DateTime(2026, 11, 7, 14, 30); // a Saturday

    Future<DateTime?> openAndPick(WidgetTester tester, String label) async {
      DateTime? picked;
      await tester.pumpWidget(
        buildTestMaterialApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showDialog<DateTime>(
                  context: context,
                  builder: (_) => ReminderTimeDialog(now: now),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('lists the quick choices and a custom option', (tester) async {
      await tester.pumpWidget(
        buildTestMaterialApp(ReminderTimeDialog(now: now)),
      );

      expect(find.text('Remind me about this message'), findsOneWidget);
      for (final label in [
        'In 20 minutes',
        'In 1 hour',
        'In 3 hours',
        'Tomorrow at 9:00',
        'Next Monday at 9:00',
        'Pick a date and time…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('choosing "In 1 hour" returns that time', (tester) async {
      final picked = await openAndPick(tester, 'In 1 hour');
      expect(picked, DateTime(2026, 11, 7, 15, 30));
    });

    testWidgets('choosing "Tomorrow at 9:00" returns 9:00 the next day', (
      tester,
    ) async {
      final picked = await openAndPick(tester, 'Tomorrow at 9:00');
      expect(picked, DateTime(2026, 11, 8, 9));
    });
  });
}
