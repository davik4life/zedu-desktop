import 'dart:async';

import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

/// The reminder list of the signed-in user in the selected workspace.
final reminderStoreProvider = Provider<ReminderStore>((ref) {
  final userId = ref.watch(
    authNotifierProvider.select((state) => state.user?.id ?? ''),
  );
  final orgId = ref.watch(currentOrgIdProvider);
  return ReminderStore(
    () => locator<SecureStorageService>(),
    userId: userId,
    orgId: orgId,
  );
});

/// The current time, replaceable in tests.
final reminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final reminderAlertsProvider = Provider<ReminderAlerts>(ReminderAlerts.new);

/// Opens the conversation a reminder was set on, even if it is no longer in
/// the loaded list.
final reminderOpenerProvider = Provider<void Function(MessageReminder)>((ref) {
  return (reminder) async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}

    ref.read(homeSidebarProvider.notifier).setType(HomeSidebarType.dms);

    final conversations = ref.read(dmListProvider).value ?? const [];
    DmConversation? conversation;
    for (final c in conversations) {
      if (c.channelId == reminder.channelId) {
        conversation = c;
        break;
      }
    }
    conversation ??= DmConversation(
      channelId: reminder.channelId,
      username: reminder.channelName,
      participantId: reminder.participantId ?? '',
      previewMessage: reminder.preview,
      unreadCount: 0,
    );
    ref.read(selectedDmProvider.notifier).select(conversation);

    final router = locator.isRegistered<GoRouter>()
        ? locator<GoRouter>()
        : AppRouter.router;
    try {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path != AppRouter.home) router.go(AppRouter.home);
    } catch (_) {
      router.go(AppRouter.home);
    }
  };
});

/// Shows the desktop notification for a reminder that came due.
class ReminderAlerts {
  ReminderAlerts(this._ref);

  final Ref _ref;

  Future<void> show(MessageReminder reminder) async {
    final who = reminder.senderName.isEmpty ? '' : '${reminder.senderName}: ';
    final notification = LocalNotification(
      title: 'Reminder · ${reminder.channelName}',
      body: reminderPreviewText('$who${reminder.preview}'),
    );
    notification.onClick = () => _ref.read(reminderOpenerProvider)(reminder);
    try {
      await notification.show();
    } catch (_) {}
  }

  /// One notification for several reminders that came due while the app was
  /// closed, instead of a burst of banners.
  Future<void> showSummary(int count) async {
    try {
      await LocalNotification(
        title: 'Reminders',
        body: '$count messages are waiting in Later',
      ).show();
    } catch (_) {}
  }
}

class RemindersNotifier extends Notifier<List<MessageReminder>> {
  Timer? _timer;
  bool _disposed = false;
  late ReminderStore _store;

  /// More reminders than this coming due together are announced once.
  static const maxSeparateAlerts = 3;

  @override
  List<MessageReminder> build() {
    _store = ref.watch(reminderStoreProvider);
    final signedIn =
        ref.watch(authNotifierProvider.select((s) => s.user?.id)) != null;
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    if (signedIn) unawaited(Future.microtask(_load));
    return const [];
  }

  Future<void> _load() async {
    final saved = await _store.load();
    if (_disposed) return;
    // A reminder added while loading must not be lost.
    final byId = {for (final r in saved) r.id: r};
    for (final r in state) {
      byId[r.id] = r;
    }
    state = _sorted(byId.values);
    await checkDue();
  }

  List<MessageReminder> _sorted(Iterable<MessageReminder> reminders) =>
      reminders.toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  /// Adds a reminder. Returns false when it could not be saved to this device;
  /// it still works until the app closes.
  Future<bool> add({
    required String channelId,
    required String channelName,
    required String senderName,
    required String preview,
    required DateTime dueAt,
    String? participantId,
    String? messageId,
  }) async {
    final now = ref.read(reminderClockProvider)();
    final reminder = MessageReminder(
      id: '${now.microsecondsSinceEpoch}-${state.length}',
      channelId: channelId,
      channelName: channelName,
      participantId: participantId,
      messageId: messageId,
      senderName: senderName,
      preview: preview.length > 200 ? '${preview.substring(0, 200)}…' : preview,
      dueAt: dueAt,
      createdAt: now,
    );
    state = _sorted([...state, reminder]);
    final saved = await _store.save(state);
    _schedule();
    return saved;
  }

  /// Removes a reminder (done, or no longer wanted).
  Future<void> dismiss(String id) async {
    state = [
      for (final r in state)
        if (r.id != id) r,
    ];
    await _store.save(state);
    _schedule();
  }

  /// Moves a reminder to [dueAt]; it notifies again when that time comes.
  Future<void> snooze(String id, DateTime dueAt) async {
    state = _sorted([
      for (final r in state) r.id == id ? r.snoozedTo(dueAt) : r,
    ]);
    await _store.save(state);
    _schedule();
  }

  /// Notifies for every reminder that came due, then arms the timer for the
  /// next one. Runs on load and whenever the timer fires.
  Future<void> checkDue() async {
    if (_disposed) return;
    final now = ref.read(reminderClockProvider)();
    final due = state.where((r) => r.needsNotification(now)).toList();
    if (due.isNotEmpty) {
      final dnd = ref.read(notificationSettingsProvider).isDndActive;
      final alerts = ref.read(reminderAlertsProvider);
      if (!dnd) {
        if (due.length > maxSeparateAlerts) {
          await alerts.showSummary(due.length);
        } else {
          for (final r in due) {
            await alerts.show(r);
          }
        }
      }
      if (_disposed) return;
      // Marked as notified even under Do Not Disturb: the reminder stays in
      // Later with the badge, and is not announced again after DND ends.
      final dueIds = {for (final r in due) r.id};
      state = [
        for (final r in state)
          dueIds.contains(r.id) ? r.copyWith(firedAt: now) : r,
      ];
      await _store.save(state);
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed) return;
    final now = ref.read(reminderClockProvider)();
    DateTime? next;
    for (final r in state) {
      if (r.firedAt != null) continue;
      if (next == null || r.dueAt.isBefore(next)) next = r.dueAt;
    }
    if (next == null) return;
    var wait = next.difference(now);
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer = Timer(wait, () => unawaited(checkDue()));
  }
}

final remindersProvider =
    NotifierProvider<RemindersNotifier, List<MessageReminder>>(
      RemindersNotifier.new,
    );

/// Reminders that came due: shown as the badge on the Later button.
final dueReminderCountProvider = Provider<int>(
  (ref) => ref.watch(
    remindersProvider.select(
      (reminders) => reminders.where((r) => r.firedAt != null).length,
    ),
  ),
);
