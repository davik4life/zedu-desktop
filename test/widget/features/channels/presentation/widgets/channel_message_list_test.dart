import '../../../../../helpers/helpers.dart';

import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

class MockChannelRepository extends Mock implements ChannelRepository {}

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    status: AuthStatus.authenticated,
    user: User(
      id: 'user-1',
      firstName: 'Test',
      lastName: 'User',
      email: 'test@example.com',
      phone: '',
      username: 'testuser',
      isVerified: true,
      isOnboarded: true,
      createdAt: DateTime(2026),
      currentOrg: 'org-1',
      currentOrganisationSlug: 'test-org',
      avatarUrl: '',
      defaultAvatarUrl: '',
    ),
  );
}

class FakeChatHistoryNotifier extends ChangeNotifier
    implements ChatHistoryNotifier {
  FakeChatHistoryNotifier(this.channelId);

  @override
  final String channelId;

  @override
  List<Map<String, dynamic>> messages = [];

  @override
  String get currentUserName => 'Test User';

  @override
  String? get currentUserAvatarUrl => null;

  @override
  String get currentUserId => 'me-1';

  String? retriedMessageId;

  @override
  Future<void> retryMessage(String messageId) async {
    retriedMessageId = messageId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Success<ChannelMessagePage> _page(
  List<ChannelMessage> messages, {
  bool hasMore = false,
}) => Success(ChannelMessagePage(messages: messages, hasMore: hasMore));

/// No workspace, so the list does not need the app config to load one.
class _NoWorkspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState();
}

void main() {
  late MockChannelRepository repository;
  late FakeChatHistoryNotifier fakeChatHistory;

  setUp(() {
    repository = MockChannelRepository();
    fakeChatHistory = FakeChatHistoryNotifier('ch-1');
  });

  void stubPage(int page, Result<ChannelMessagePage> result) {
    when(
      () => repository.fetchChannelMessages('ch-1', page: page),
    ).thenAnswer((_) async => result);
  }

  Future<void> pumpList(
    WidgetTester tester, [
    Result<List<ChannelMessage>>? legacy,
    FakeChatHistoryNotifier? chatNotifier,
  ]) async {
    if (legacy != null) {
      stubPage(1, switch (legacy) {
        Success<List<ChannelMessage>>(:final value) => Success(
          ChannelMessagePage(messages: value, hasMore: false),
        ),
        Failure<List<ChannelMessage>>(:final error) =>
          Failure<ChannelMessagePage>(error),
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelRepositoryProvider.overrideWithValue(repository),
          authNotifierProvider.overrideWith(_FakeAuthNotifier.new),
          // The Save for later button on each message reads the workspace.
          workspaceProvider.overrideWith(_NoWorkspace.new),
          chatHistoryProvider.overrideWith(
            (ref, channelId) => chatNotifier ?? fakeChatHistory,
          ),
        ],
        retry: (_, _) => null,
        child: buildTestMaterialApp(
          const Scaffold(
            body: ChannelMessageList(
              channelId: 'ch-1',
              empty: Text('Welcome to #general'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the messages, newest at the bottom', (tester) async {
    stubPage(
      1,
      _page(const [
        ChannelMessage(id: '2', senderName: 'gold', text: 'newest'),
        ChannelMessage(id: '1', senderName: 'Ada', text: 'oldest'),
      ]),
    );
    await pumpList(tester);

    expect(find.text('Welcome to #general'), findsNothing);
    expect(
      tester.getTopLeft(find.text('oldest')).dy,
      lessThan(tester.getTopLeft(find.text('newest')).dy),
    );
  });

  testWidgets('opens a URL in a message when it is tapped', (tester) async {
    final opened = <Uri>[];
    final original = messageLinkLauncher;
    messageLinkLauncher = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => messageLinkLauncher = original);

    await pumpList(
      tester,
      const Success([
        ChannelMessage(senderName: 'Ada', text: 'https://example.com/channel'),
      ]),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(SelectableText)) + const Offset(20, 8),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(opened, [Uri.parse('https://example.com/channel')]);
  });

  testWidgets('shows the welcome screen when empty', (tester) async {
    stubPage(1, _page(const <ChannelMessage>[]));
    await pumpList(tester);

    expect(find.text('Welcome to #general'), findsOneWidget);
  });

  testWidgets('offers a retry when loading fails', (tester) async {
    stubPage(1, const Failure(ApiFailure(message: 'boom')));
    await pumpList(tester);

    expect(find.text("Couldn't load messages. Retry"), findsOneWidget);
  });

  testWidgets('loads older messages when the top of the list shows', (
    tester,
  ) async {
    stubPage(
      1,
      _page(const [
        ChannelMessage(id: '2', senderName: 'gold', text: 'newest'),
      ], hasMore: true),
    );
    stubPage(
      2,
      _page(const [ChannelMessage(id: '1', senderName: 'Ada', text: 'oldest')]),
    );
    await pumpList(tester);

    expect(find.text('newest'), findsOneWidget);
    expect(find.text('oldest'), findsOneWidget);
    verify(() => repository.fetchChannelMessages('ch-1', page: 2)).called(1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an inline retry when an older page fails', (tester) async {
    stubPage(
      1,
      _page(const [
        ChannelMessage(id: '2', senderName: 'gold', text: 'newest'),
      ], hasMore: true),
    );
    stubPage(2, const Failure(ApiFailure(message: 'boom')));
    await pumpList(tester);

    // The messages stay, and the failure is not retried on its own.
    expect(find.text('newest'), findsOneWidget);
    expect(find.text("Couldn't load older messages. Retry"), findsOneWidget);
    verify(() => repository.fetchChannelMessages('ch-1', page: 2)).called(1);

    stubPage(
      2,
      _page(const [ChannelMessage(id: '1', senderName: 'Ada', text: 'oldest')]),
    );
    await tester.tap(find.text("Couldn't load older messages. Retry"));
    await tester.pumpAndSettle();

    expect(find.text('oldest'), findsOneWidget);
    expect(find.text("Couldn't load older messages. Retry"), findsNothing);
  });

  testWidgets(
    'renders a placeholder initial for an empty senderName without crashing',
    (tester) async {
      stubPage(
        1,
        _page(const [
          ChannelMessage(id: '1', senderName: '', text: 'empty sender'),
        ]),
      );
      await pumpList(tester);

      expect(find.text('?'), findsOneWidget);
      expect(find.text('empty sender'), findsOneWidget);
    },
  );

  testWidgets(
    'shows sending indicator for optimistic pending channel message (#2571)',
    (tester) async {
      fakeChatHistory.messages = [
        {
          'id': 'temp-1',
          'content': 'Sending channel message',
          'channel_id': 'ch-1',
          'status': 'sending',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      await pumpList(tester, const Success(<ChannelMessage>[]));

      expect(find.text('Sending channel message'), findsOneWidget);
      expect(find.text('Sending...'), findsOneWidget);
    },
  );

  testWidgets(
    'shows failed indicator and invokes retryMessage on tap (#2571)',
    (tester) async {
      fakeChatHistory.messages = [
        {
          'id': 'failed-msg-1',
          'content': 'Failed channel message',
          'channel_id': 'ch-1',
          'status': 'failed',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      await pumpList(tester, const Success(<ChannelMessage>[]));

      expect(find.text('Failed channel message'), findsOneWidget);
      expect(find.text('Failed – Tap to retry'), findsOneWidget);

      await tester.tap(find.text('Failed – Tap to retry'));
      expect(fakeChatHistory.retriedMessageId, 'failed-msg-1');
    },
  );

  group('attachments rendering (#2681)', () {
    testWidgets('renders file attachment chip in channel message', (
      tester,
    ) async {
      await pumpList(
        tester,
        const Success([
          ChannelMessage(
            senderName: 'Ada',
            text: 'Here is the report',
            media: [
              {
                'file_name': 'quarterly_report.pdf',
                'file_link': 'https://cdn.zedu.chat/quarterly_report.pdf',
                'file_type': 'pdf',
              },
            ],
          ),
        ]),
      );

      expect(find.text('Here is the report'), findsOneWidget);
      expect(find.text('quarterly_report.pdf'), findsOneWidget);
      expect(find.byType(MessageAttachmentList), findsOneWidget);
    });

    testWidgets(
      'file-only channel message displays attachment without empty text line',
      (tester) async {
        await pumpList(
          tester,
          const Success([
            ChannelMessage(
              senderName: 'Ada',
              text: '',
              media: [
                {
                  'file_name': 'document.docx',
                  'file_link': 'https://cdn.zedu.chat/document.docx',
                  'file_type': 'docx',
                },
              ],
            ),
          ]),
        );

        expect(find.text('document.docx'), findsOneWidget);
        expect(find.byType(SelectableText), findsNothing);
      },
    );

    testWidgets('renders image preview for image attachment', (tester) async {
      await pumpList(
        tester,
        const Success([
          ChannelMessage(
            senderName: 'Ada',
            text: 'Look at this photo',
            media: [
              {
                'file_name': 'photo.png',
                'file_link': 'https://cdn.zedu.chat/photo.png',
                'file_type': 'png',
              },
            ],
          ),
        ]),
      );

      expect(find.text('Look at this photo'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('optimistic pending channel message carries attachments', (
      tester,
    ) async {
      fakeChatHistory.messages = [
        {
          'id': 'temp-att-1',
          'content': 'Sending attachment',
          'channel_id': 'ch-1',
          'status': 'sending',
          'created_at': DateTime.now().toIso8601String(),
          'media': [
            {
              'file_name': 'pending_upload.pdf',
              'file_link': 'https://cdn.zedu.chat/pending_upload.pdf',
              'file_type': 'pdf',
            },
          ],
        },
      ];

      await pumpList(tester, const Success(<ChannelMessage>[]));

      expect(find.text('Sending attachment'), findsOneWidget);
      expect(find.text('pending_upload.pdf'), findsOneWidget);
      expect(find.text('Sending...'), findsOneWidget);
    });
  });

  group('day dividers', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 0, 1);
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    final older = DateTime(now.year, now.month, now.day - 10, 9);

    testWidgets('one divider above the first message of each day', (
      tester,
    ) async {
      await pumpList(
        tester,
        Success([
          ChannelMessage(senderName: 'Ada', text: 'today', createdAt: today),
          ChannelMessage(
            senderName: 'Ada',
            text: 'yesterday late',
            createdAt: yesterday.add(const Duration(hours: 2)),
          ),
          ChannelMessage(
            senderName: 'Ada',
            text: 'yesterday',
            createdAt: yesterday,
          ),
          ChannelMessage(
            senderName: 'Ada',
            text: 'old later',
            createdAt: older.add(const Duration(hours: 5)),
          ),
          ChannelMessage(senderName: 'Ada', text: 'old', createdAt: older),
        ]),
      );

      expect(find.byType(ChannelDayDivider), findsNWidgets(3));
      final olderLabel = channelDayLabel(older);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      for (final (label, first, last) in [
        (olderLabel, 'old', 'old later'),
        ('Yesterday', 'yesterday', 'yesterday late'),
        ('Today', 'today', 'today'),
      ]) {
        expect(find.text(label), findsOneWidget);
        expect(top(label), lessThan(top(first)));
        expect(top(label), lessThanOrEqualTo(top(last)));
      }
      expect(top(olderLabel), lessThan(top('Yesterday')));
      expect(top('old later'), lessThan(top('Yesterday')));
      expect(top('Yesterday'), lessThan(top('Today')));
    });

    testWidgets('no divider for messages without a time', (tester) async {
      await pumpList(
        tester,
        const Success([ChannelMessage(senderName: 'Ada', text: 'undated')]),
      );

      expect(find.byType(ChannelDayDivider), findsNothing);
    });
  });

  group('channelDayLabel', () {
    final now = DateTime(2026, 11, 4, 9); // A Wednesday.

    test('today and yesterday by calendar day, not 24 hours', () {
      expect(channelDayLabel(DateTime(2026, 11, 4, 0, 1), now: now), 'Today');
      expect(
        channelDayLabel(DateTime(2026, 11, 3, 23, 59), now: now),
        'Yesterday',
      );
    });

    test('the weekday within the last week', () {
      expect(channelDayLabel(DateTime(2026, 11, 2), now: now), 'Monday');
      expect(channelDayLabel(DateTime(2026, 10, 29), now: now), 'Thursday');
    });

    test('the date from a week ago, with the year only when not this year', () {
      expect(
        channelDayLabel(DateTime(2026, 10, 28), now: now),
        'Wednesday, Oct 28',
      );
      expect(
        channelDayLabel(DateTime(2025, 12, 31), now: now),
        'Wednesday, Dec 31, 2025',
      );
    });
  });

  group('editing and deleting own messages (Ziki #2839)', () {
    const mine = ChannelMessage(
      senderName: 'Test User',
      text: 'my typo',
      threadId: 't-1',
      userId: 'me-1',
    );
    const theirs = ChannelMessage(
      senderName: 'Ada',
      text: 'not yours',
      threadId: 't-2',
      userId: 'u-2',
    );
    final actions = find.byKey(const ValueKey('channel-message-actions'));

    setUp(() {
      when(
        () => repository.editChannelMessage(
          channelId: any(named: 'channelId'),
          threadId: any(named: 'threadId'),
          content: any(named: 'content'),
        ),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repository.deleteChannelMessage(
          channelId: any(named: 'channelId'),
          threadId: any(named: 'threadId'),
        ),
      ).thenAnswer((_) async => const Success(null));
    });

    testWidgets('every sent message gets a menu, with Remind me', (
      tester,
    ) async {
      await pumpList(tester, const Success([mine, theirs]));

      expect(actions, findsNWidgets(2));
    });

    testWidgets('Edit and Delete are only offered on your own messages', (
      tester,
    ) async {
      await pumpList(tester, const Success([mine, theirs]));

      Finder menuOf(String text) => find.descendant(
        of: find.ancestor(
          of: find.text(text),
          matching: find.byType(ChannelMessageTile),
        ),
        matching: actions,
      );

      await tester.tap(menuOf('not yours'));
      await tester.pumpAndSettle();
      expect(find.text('Remind me'), findsOneWidget);
      expect(find.text('Edit message'), findsNothing);
      expect(find.text('Delete message'), findsNothing);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      await tester.tap(menuOf('my typo'));
      await tester.pumpAndSettle();
      expect(find.text('Remind me'), findsOneWidget);
      expect(find.text('Edit message'), findsOneWidget);
      expect(find.text('Delete message'), findsOneWidget);
    });

    testWidgets('Edit saves the new text and reloads the channel', (
      tester,
    ) async {
      await pumpList(tester, const Success([mine]));

      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit message'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('channel-message-edit-field')),
        'fixed text',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(
        () => repository.editChannelMessage(
          channelId: 'ch-1',
          threadId: 't-1',
          content: 'fixed text',
        ),
      ).called(1);
      verify(() => repository.fetchChannelMessages('ch-1')).called(2);
    });

    testWidgets('Delete asks first, then deletes and reloads', (tester) async {
      await pumpList(tester, const Success([mine]));

      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete message'));
      await tester.pumpAndSettle();
      expect(find.text('Delete message?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      verify(
        () =>
            repository.deleteChannelMessage(channelId: 'ch-1', threadId: 't-1'),
      ).called(1);
      verify(() => repository.fetchChannelMessages('ch-1')).called(2);
    });

    testWidgets('cancelling the delete changes nothing', (tester) async {
      await pumpList(tester, const Success([mine]));

      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(
        () => repository.deleteChannelMessage(
          channelId: any(named: 'channelId'),
          threadId: any(named: 'threadId'),
        ),
      );
    });

    testWidgets('a failed edit says so', (tester) async {
      when(
        () => repository.editChannelMessage(
          channelId: any(named: 'channelId'),
          threadId: any(named: 'threadId'),
          content: any(named: 'content'),
        ),
      ).thenAnswer((_) async => const Failure(ApiFailure(message: 'offline')));
      await pumpList(tester, const Success([mine]));

      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit message'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('channel-message-edit-field')),
        'fixed text',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(
        find.text("Couldn't edit the message. Please try again."),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  const reactedMessage = ChannelMessage(
    id: 'm-1',
    senderName: 'Ada',
    text: 'reacted message',
    reactions: [
      ChannelReaction(emoji: '👍', reactionId: 'r-1', count: 3),
      ChannelReaction(emoji: '🔥', reactionId: 'r-2', count: 1),
    ],
  );

  void stubReactionUsers() {
    when(
      () => repository.fetchReactionUsers(
        reactionId: any(named: 'reactionId'),
        threadId: any(named: 'threadId'),
      ),
    ).thenAnswer((_) async => const Success(<String>[]));
  }

  testWidgets('renders a pill with the count for each reaction (#2684)', (
    tester,
  ) async {
    stubReactionUsers();

    await pumpList(tester, const Success([reactedMessage]));

    expect(find.text('👍'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
    'tapping a pill toggles the reaction and refreshes the history (#2684)',
    (tester) async {
      stubReactionUsers();
      when(
        () => repository.toggleReaction(
          channelId: 'ch-1',
          threadId: 'm-1',
          emoji: '👍',
        ),
      ).thenAnswer((_) async => const Success(true));

      await pumpList(tester, const Success([reactedMessage]));

      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();

      verify(
        () => repository.toggleReaction(
          channelId: 'ch-1',
          threadId: 'm-1',
          emoji: '👍',
        ),
      ).called(1);
    },
  );

  testWidgets('highlights only the pills the user has reacted with (#2684)', (
    tester,
  ) async {
    when(
      () => repository.fetchReactionUsers(reactionId: 'r-1', threadId: 'm-1'),
    ).thenAnswer((_) async => const Success(['Ada', 'testuser']));
    when(
      () => repository.fetchReactionUsers(reactionId: 'r-2', threadId: 'm-1'),
    ).thenAnswer((_) async => const Success([]));

    await pumpList(tester, const Success([reactedMessage]));

    final colors = tester.element(find.text('👍')).colors;
    final thumbsPill = tester.widget<Material>(
      find.ancestor(of: find.text('👍'), matching: find.byType(Material)).first,
    );
    final firePill = tester.widget<Material>(
      find.ancestor(of: find.text('🔥'), matching: find.byType(Material)).first,
    );

    expect(thumbsPill.color, colors.primary);
    expect(firePill.color, colors.background);
  });

  testWidgets('the add-reaction button opens the picker and reacts (#2684)', (
    tester,
  ) async {
    stubReactionUsers();
    when(
      () => repository.toggleReaction(
        channelId: 'ch-1',
        threadId: 'm-1',
        emoji: '😀',
      ),
    ).thenAnswer((_) async => const Success(true));

    await pumpList(tester, const Success([reactedMessage]));

    await tester.tap(find.byIcon(Icons.add_reaction_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Emoji'), findsOneWidget);

    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();

    expect(find.text('Emoji'), findsNothing);
    verify(
      () => repository.toggleReaction(
        channelId: 'ch-1',
        threadId: 'm-1',
        emoji: '😀',
      ),
    ).called(1);
  });

  testWidgets('pending messages show no reactions row (#2684)', (tester) async {
    fakeChatHistory.messages = [
      {
        'id': 'temp-1',
        'content': 'Optimistic message',
        'channel_id': 'ch-1',
        'status': 'sending',
        'created_at': DateTime.now().toIso8601String(),
      },
    ];

    await pumpList(tester, const Success(<ChannelMessage>[]));

    expect(find.text('Optimistic message'), findsOneWidget);
    expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
  });
}
