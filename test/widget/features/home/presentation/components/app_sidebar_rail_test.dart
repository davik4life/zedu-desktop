import 'package:flutter/rendering.dart';
import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';
import '../../../../../helpers/helpers.dart';

class _DmListWithUnread extends DmListNotifier {
  @override
  Future<List<DmConversation>> build() async => [
    DmConversation(
      channelId: 'unread-dm',
      username: 'Ada',
      participantId: 'ada',
      previewMessage: 'Hello',
      unreadCount: 1,
    ),
  ];
}

class _EmptyDmList extends DmListNotifier {
  @override
  Future<List<DmConversation>> build() async => const [];
}

void main() {
  testWidgets('navigation labels use labelSmall and fit the 50px rail', (
    tester,
  ) async {
    // Use the app font instead of Flutter test's fallback font for layout.
    await (FontLoader(
      FontFamily.lato,
    )..addFont(rootBundle.load('assets/fonts/Lato/Lato-Regular.ttf'))).load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dmListProvider.overrideWith(_EmptyDmList.new),
          dueReminderCountProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: AppSidebarRail.width,
              height: 600,
              child: AppSidebarRail(activeType: HomeSidebarType.home),
            ),
          ),
        ),
      ),
    );

    final rail = tester.getSize(find.byType(AppSidebarRail));
    expect(rail.width, AppSidebarRail.width);

    final labelStyle = AppTheme.light.textTheme.labelSmall!;
    for (final label in ['Home', 'DMs', 'People', 'Files', 'Buzz']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontSize, labelStyle.fontSize);
      expect(text.style?.fontWeight, labelStyle.fontWeight);

      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse, reason: '$label is clipped');
      final labelSize = tester.getSize(find.text(label));
      final singleLineHeight = labelStyle.fontSize! * labelStyle.height!;
      expect(
        labelSize.height,
        lessThanOrEqualTo(singleLineHeight + 1),
        reason: '$label wrapped',
      );
      expect(labelSize.width, lessThanOrEqualTo(38));
    }

    final navIcons = tester.widgetList<Icon>(find.byType(Icon)).take(5);
    expect(navIcons, hasLength(5));
    for (final icon in navIcons) {
      expect(icon.size, 20);
    }

    final notificationIcon = tester.widget<Icon>(
      find.byIcon(Icons.notifications_none_outlined),
    );
    final settingsIcon = tester.widget<Icon>(
      find.byIcon(Icons.settings_outlined),
    );

    expect(notificationIcon.size, 20);
    expect(settingsIcon.size, 20);

    expect(tester.takeException(), isNull);
  });

  testWidgets('settings rail button has a tooltip with message "Settings"', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dmListProvider.overrideWith(_EmptyDmList.new),
          dueReminderCountProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: AppSidebarRail.width,
              height: 600,
              child: AppSidebarRail(activeType: HomeSidebarType.home),
            ),
          ),
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.byIcon(Icons.settings_outlined),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Settings',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('notification bell shows an indicator for unread DMs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dmListProvider.overrideWith(_DmListWithUnread.new),
          dueReminderCountProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: AppSidebarRail.width,
              height: 600,
              child: AppSidebarRail(activeType: HomeSidebarType.home),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('notification-unread-indicator')),
      findsOneWidget,
    );
  });
}
