import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

/// The messages of a channel, newest at the bottom. Shows [empty] when the
/// channel has no messages yet.
class ChannelMessageList extends ConsumerWidget {
  const ChannelMessageList({
    super.key,
    required this.channelId,
    required this.empty,
  });

  final String channelId;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatHistory = ref.watch(chatHistoryProvider(channelId));
    final pendingMessages = chatHistory.messages
        .where(
          (m) =>
              m['status'] != null &&
              (m['channel_id'] == channelId || m['is_channel'] == true),
        )
        .map(
          (m) => ChannelMessage(
            id: m['id']?.toString(),
            senderName: (m['sender_name'] as String?)?.isNotEmpty == true
                ? m['sender_name'] as String
                : chatHistory.currentUserName,
            avatarUrl: (m['avatar_url'] as String?)?.isNotEmpty == true
                ? m['avatar_url'] as String
                : chatHistory.currentUserAvatarUrl,
            text: m['content']?.toString() ?? '',
            createdAt: DateTime.tryParse(
              m['created_at']?.toString() ?? '',
            )?.toLocal(),
            status: m['status']?.toString(),
            media: ChannelMessage.mediaFrom(m['media'] ?? m['files']),
          ),
        )
        .toList();

    return ref
        .watch(channelHistoryProvider(channelId))
        .when(
          loading: () => pendingMessages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _buildList(context, ref, pendingMessages),
          error: (_, _) => pendingMessages.isEmpty
              ? Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.invalidate(channelHistoryProvider(channelId)),
                    child: const Text("Couldn't load messages. Retry"),
                  ),
                )
              : _buildList(context, ref, pendingMessages),
          data: (history) {
            final allMessages = [...pendingMessages, ...history.messages];
            return allMessages.isEmpty
                ? empty
                : _buildList(context, ref, allMessages, history: history);
          },
        );
  }

  /// Asks when to be reminded about [message], then saves the reminder.
  void _remind(BuildContext context, WidgetRef ref, ChannelMessage message) {
    final channels = ref.read(channelProvider).value ?? const <Channel>[];
    var name = ref.read(activeChatProvider).id ?? '';
    for (final channel in channels) {
      if (channel.id == channelId) name = channel.name;
    }
    remindAboutMessage(
      context,
      ref,
      source: ReminderSource.channel,
      channelId: channelId,
      channelName: name.isEmpty ? 'channel' : name,
      senderName: message.senderName,
      messageText: message.text,
      messageId: message.threadId ?? message.id,
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<ChannelMessage> messages, {
    ChannelHistoryState? history,
  }) {
    // Read only when a message names its sender, so lists without sender ids
    // never touch the signed-in user.
    String? me;
    bool isMine(ChannelMessage message) {
      final sender = message.userId;
      if (sender == null || message.threadId == null) return false;
      if (message.status != null) return false;
      me ??= ref.read(chatHistoryProvider(channelId)).currentUserId;
      return me!.isNotEmpty && sender == me;
    }

    // The footer sits after the oldest message, which is the top of this
    // reversed list. Older pages are appended behind the reader, so the
    // scroll offset (measured from the newest end) holds.
    final showFooter =
        history != null && (history.hasMore || history.loadMoreError != null);

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: messages.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _OlderMessagesFooter(channelId: channelId);
        }
        final message = messages[index];
        // Only the sender's own, already sent messages can be changed.
        final own = isMine(message);
        final tile = ChannelMessageTile(
          channelId: channelId,
          message: message,
          saveAction:
              message.status == null && (message.threadId ?? message.id) != null
              ? SaveLaterButton(
                  channelId: channelId,
                  threadId: message.threadId ?? message.id!,
                )
              : null,
          onRetry: message.id != null
              ? () => ref
                    .read(chatHistoryProvider(channelId))
                    .retryMessage(message.id!)
              : null,
          onEdit: own
              ? () => _editChannelMessage(context, ref, channelId, message)
              : null,
          onDelete: own
              ? () => _deleteChannelMessage(context, ref, channelId, message)
              : null,
          // Any message that was sent can be reminded about, not only your own.
          onRemind: message.status == null
              ? () => _remind(context, ref, message)
              : null,
        );
        // Newest first, so the next index is the older neighbour. A day
        // starts at the oldest message or where the older one is another day.
        final time = message.createdAt;
        final isOldest = index == messages.length - 1;
        final olderTime = isOldest ? null : messages[index + 1].createdAt;
        final startsDay =
            time != null &&
            (isOldest ||
                (olderTime != null && !DateUtils.isSameDay(time, olderTime)));
        if (!startsDay) return tile;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ChannelDayDivider(label: channelDayLabel(time)),
            tile,
          ],
        );
      },
    );
  }
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The label of the divider above a day's first message: "Today",
/// "Yesterday", the weekday within the last week, otherwise the date, with
/// the year only when it isn't this year.
String channelDayLabel(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  // Whole days between the calendar dates, unaffected by DST changes.
  final daysAgo = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  final weekday = _weekdays[day.weekday - 1];
  if (daysAgo > 1 && daysAgo < 7) return weekday;
  final date = '$weekday, ${_months[day.month - 1]} ${day.day}';
  return day.year == today.year ? date : '$date, ${day.year}';
}

/// A line with the day's label, above the first message of each day.
class ChannelDayDivider extends StatelessWidget {
  const ChannelDayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(child: Divider(color: colors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ),
            Expanded(child: Divider(color: colors.divider)),
          ],
        ),
      ),
    );
  }
}

/// The top of the list while older messages remain: loads the next page once
/// it scrolls into view, and offers a retry when that fails.
class _OlderMessagesFooter extends ConsumerWidget {
  const _OlderMessagesFooter({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(channelHistoryProvider(channelId)).value;
    final notifier = ref.read(channelHistoryProvider(channelId).notifier);

    if (history?.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Center(
          child: TextButton(
            onPressed: notifier.loadMore,
            child: const Text("Couldn't load older messages. Retry"),
          ),
        ),
      );
    }

    if (history != null && history.hasMore && !history.isLoadingMore) {
      // Built means visible: the list only builds what is on screen. Retries
      // are left to the button above so a failing request cannot loop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) notifier.loadMore();
      });
    }

    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            semanticsLabel: 'Loading older messages',
          ),
        ),
      ),
    );
  }
}

class ChannelMessageTile extends ConsumerStatefulWidget {
  const ChannelMessageTile({
    super.key,
    required this.channelId,
    required this.message,
    this.onRetry,
    this.onEdit,
    this.onDelete,
    this.saveAction,
    this.onRemind,
  });

  final String channelId;
  final ChannelMessage message;
  final VoidCallback? onRetry;

  /// Set for the current user's own messages; shows Edit in the menu.
  final VoidCallback? onEdit;

  /// Set for the current user's own messages; shows Delete in the menu.
  final VoidCallback? onDelete;
  final Widget? saveAction;

  /// Set for every sent message; shows "Remind me" in the menu.
  final VoidCallback? onRemind;

  @override
  ConsumerState<ChannelMessageTile> createState() => _ChannelMessageTileState();
}

class _ChannelMessageTileState extends ConsumerState<ChannelMessageTile> {
  /// Emojis with a toggle request still in flight, to block double taps.
  final Set<String> _busyEmojis = {};

  ChannelMessage get _message => widget.message;

  Future<void> _toggleReaction(String emoji, {String? reactionId}) async {
    final messageId = _message.id;
    if (messageId == null || messageId.isEmpty) return;
    if (_busyEmojis.contains(emoji)) return;

    setState(() => _busyEmojis.add(emoji));
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await ref
          .read(channelRepositoryProvider)
          .toggleReaction(
            channelId: widget.channelId,
            threadId: messageId,
            emoji: emoji,
          );
      switch (result) {
        case Success<bool>():
          ref.invalidate(channelHistoryProvider(widget.channelId));
          if (reactionId != null && reactionId.isNotEmpty) {
            ref.invalidate(
              reactionUsersProvider((
                reactionId: reactionId,
                threadId: messageId,
              )),
            );
          }
        case Failure<bool>(:final error):
          scaffoldMessenger?.showSnackBar(
            SnackBar(content: Text(error.message)),
          );
      }
    } finally {
      if (mounted) setState(() => _busyEmojis.remove(emoji));
    }
  }

  void _openEmojiPicker() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: DmEmojiPicker(
          onEmojiSelected: (emoji) {
            Navigator.of(dialogContext).pop();
            _toggleReaction(emoji);
          },
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final avatarUrl = _message.avatarUrl;
    final time = _message.createdAt;
    final initial = avatarInitial(_message.senderName);
    final status = _message.status;
    final hasReactions = _message.reactions.isNotEmpty;
    final canReact =
        _message.id != null && _message.id!.isNotEmpty && status == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.primary,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(initial, style: TextStyle(color: colors.onPrimary))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: _message.senderName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                          children: [
                            if (time != null)
                              TextSpan(
                                text:
                                    '  ${TimeOfDay.fromDateTime(time).format(context)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    ?widget.saveAction,
                    if (widget.onEdit != null ||
                        widget.onDelete != null ||
                        widget.onRemind != null)
                      _MessageMenu(
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                        onRemind: widget.onRemind,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_message.text.isNotEmpty || _message.media.isEmpty)
                  ReportMessageMenu(
                    senderName: _message.senderName,
                    messageText: _message.text,
                    child: MessageLinkScope(
                      builder: (context, links) => SelectableText.rich(
                        buildInlineMarkdownSpan(
                          _message.text,
                          TextStyle(fontSize: 15, color: colors.textPrimary),
                          plainText: links.span,
                        ),
                      ),
                    ),
                  ),
                if (_message.media.isNotEmpty) ...[
                  if (_message.text.isNotEmpty) const SizedBox(height: 8),
                  MessageAttachmentList(media: _message.media, isMe: false),
                ],
                if (hasReactions || canReact)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final reaction in _message.reactions)
                          _ReactionPill(
                            reaction: reaction,
                            reacted: _didUserReact(reaction),
                            busy: _busyEmojis.contains(reaction.emoji),
                            onTap: () => _toggleReaction(
                              reaction.emoji,
                              reactionId: reaction.reactionId,
                            ),
                          ),
                        if (canReact)
                          IconButton(
                            onPressed: _openEmojiPicker,
                            icon: Icon(
                              Icons.add_reaction_outlined,
                              size: 18,
                              color: colors.textHint,
                            ),
                            tooltip: 'Add reaction',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: status == 'failed'
                        ? GestureDetector(
                            onTap: widget.onRetry,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 13,
                                  color: colors.error,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Failed – Tap to retry',
                                  style: TextStyle(
                                    color: colors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            status == 'sending' ? 'Sending...' : '',
                            style: TextStyle(
                              color: colors.textHint,
                              fontSize: 11,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _didUserReact(ChannelReaction reaction) {
    final messageId = _message.id ?? '';
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;
    final String? myUsername = user == null
        ? null
        : (user.username.isEmpty ? user.email.split('@').first : user.username)
              .toLowerCase();
    if (myUsername == null) return false;
    final users = ref
        .watch(
          reactionUsersProvider((
            reactionId: reaction.reactionId,
            threadId: messageId,
          )),
        )
        .value;
    return users?.any((u) => u.toLowerCase() == myUsername) ?? false;
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.reaction,
    required this.reacted,
    required this.busy,
    required this.onTap,
  });

  final ChannelReaction reaction;
  final bool reacted;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = reacted ? colors.primary : colors.background;
    final border = reacted ? colors.primary : colors.divider;
    final foreground = reacted ? colors.onPrimary : colors.textSecondary;

    return Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: busy ? null : onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reaction.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                '${reaction.count}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the new text of [message] and saves it (Ziki #2839).
Future<void> _editChannelMessage(
  BuildContext context,
  WidgetRef ref,
  String channelId,
  ChannelMessage message,
) async {
  final threadId = message.threadId;
  if (threadId == null) return;
  final edited = await showDialog<String>(
    context: context,
    builder: (_) => _EditChannelMessageDialog(initialText: message.text),
  );
  if (!context.mounted || edited == null) return;
  final text = edited.trim();
  if (text.isEmpty || text == message.text) return;
  final result = await ref
      .read(channelRepositoryProvider)
      .editChannelMessage(
        channelId: channelId,
        threadId: threadId,
        content: text,
      );
  if (!context.mounted) return;
  switch (result) {
    case Success():
      ref.invalidate(channelHistoryProvider(channelId));
    case Failure():
      AppToastService.show(
        context,
        type: AppToastType.error,
        message: "Couldn't edit the message. Please try again.",
      );
  }
}

/// Confirms, then deletes [message] for everyone (Ziki #2839).
Future<void> _deleteChannelMessage(
  BuildContext context,
  WidgetRef ref,
  String channelId,
  ChannelMessage message,
) async {
  final threadId = message.threadId;
  if (threadId == null) return;
  final colors = context.colors;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text('It will be removed for everyone in the channel.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: colors.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) return;
  final result = await ref
      .read(channelRepositoryProvider)
      .deleteChannelMessage(channelId: channelId, threadId: threadId);
  if (!context.mounted) return;
  switch (result) {
    case Success():
      ref.invalidate(channelHistoryProvider(channelId));
    case Failure():
      AppToastService.show(
        context,
        type: AppToastType.error,
        message: "Couldn't delete the message. Please try again.",
      );
  }
}

/// Remind me for any message; Edit and Delete for the user's own.
class _MessageMenu extends StatelessWidget {
  const _MessageMenu({this.onEdit, this.onDelete, this.onRemind});

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRemind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 28,
      height: 20,
      child: PopupMenuButton<String>(
        key: const ValueKey('channel-message-actions'),
        tooltip: 'Message actions',
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(Icons.more_horiz, color: colors.textSecondary),
        onSelected: (value) {
          if (value == 'remind') onRemind?.call();
          if (value == 'edit') onEdit?.call();
          if (value == 'delete') onDelete?.call();
        },
        itemBuilder: (_) => [
          if (onRemind != null)
            const PopupMenuItem(
              value: 'remind',
              child: MenuItemRow(
                icon: Icons.alarm_add_outlined,
                label: 'Remind me',
              ),
            ),
          if (onEdit != null)
            const PopupMenuItem(
              value: 'edit',
              child: MenuItemRow(
                icon: Icons.edit_outlined,
                label: 'Edit message',
              ),
            ),
          if (onDelete != null)
            PopupMenuItem(
              value: 'delete',
              child: MenuItemRow(
                icon: Icons.delete_outline,
                label: 'Delete message',
                color: colors.error,
              ),
            ),
        ],
      ),
    );
  }
}

/// Edits a channel message's text; pops the new text, or null on Cancel.
class _EditChannelMessageDialog extends StatefulWidget {
  const _EditChannelMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditChannelMessageDialog> createState() =>
      _EditChannelMessageDialogState();
}

class _EditChannelMessageDialogState extends State<_EditChannelMessageDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit message'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('channel-message-edit-field'),
          controller: _controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_controller.text),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
