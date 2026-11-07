import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

/// Panel opened from the notifications bell in the sidebar rail.
///
/// Lists the user's reminders ("Remind me" on a message), then the DMs that
/// have unread messages, and opens one when clicked. There is no mentions feed
/// yet, so the empty state shows whenever there is nothing to show. Real
/// incoming-message notifications are still delivered by `NotificationService`.
class NotificationsDialog extends ConsumerWidget {
  const NotificationsDialog({super.key});

  void _openConversation(
    BuildContext context,
    WidgetRef ref,
    DmConversation conversation,
  ) {
    // Read before popping: the dialog's context is gone afterwards.
    final router = GoRouter.maybeOf(context);
    ref.read(homeSidebarProvider.notifier).setType(HomeSidebarType.dms);
    ref.read(selectedDmProvider.notifier).select(conversation);
    Navigator.of(context).pop();
    if (router != null &&
        router.routerDelegate.currentConfiguration.uri.path != AppRouter.home) {
      router.go(AppRouter.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final dmState = ref.watch(dmListProvider);
    final deletedIds = ref.watch(
      dmConversationActionsProvider.select((a) => a.deletedIds),
    );
    final hasReminders = ref.watch(remindersProvider).isNotEmpty;
    final unread = (dmState.value ?? const <DmConversation>[])
        .where((c) => c.unreadCount > 0 && !deletedIds.contains(c.channelId))
        .toList();

    return Dialog(
      insetPadding: const EdgeInsets.only(bottom: 80, left: 74),
      alignment: Alignment.bottomLeft,
      backgroundColor: colors.background,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: colors.textHint),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  const RemindersSection(),
                  if (unread.isEmpty && dmState.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (unread.isEmpty && !hasReminders)
                    const _EmptyState()
                  else
                    for (final conversation in unread)
                      _UnreadDmRow(
                        conversation: conversation,
                        onTap: () =>
                            _openConversation(context, ref, conversation),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadDmRow extends StatelessWidget {
  const _UnreadDmRow({required this.conversation, required this.onTap});

  final DmConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final avatarUrl = conversation.effectiveAvatarUrl;
    // Whole first character, so an empty name or an emoji can't break the row.
    final trimmedName = conversation.displayName.trim();
    final initial = trimmedName.isNotEmpty
        ? trimmedName.characters.first.toUpperCase()
        : '?';
    final preview = conversation.previewMessage
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.primaryBg,
              backgroundImage: avatarUrl != null
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null
                  ? Text(
                      initial,
                      style: TextStyle(fontSize: 13, color: colors.primary),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                conversation.unreadCount.unreadBadgeText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_outlined,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "You're all caught up",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You have no unread messages.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
