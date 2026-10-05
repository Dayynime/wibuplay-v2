import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/comment_models.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../../components/role_badges.dart';
import 'comments_controller.dart';

const Color _kPinnedGold = Color(0xFFE8A317);
const Color _kSheetColor = AppColors.backgroundDarkSecondary;

/// Komentar episode versi INLINE (di bawah Daftar Episode). Dipasang sebagai
/// sliver di CustomScrollView halaman nonton. Port episodeCommentsSection
/// (Zenime): header jumlah komentar, tab sort, input, lalu daftar komentar.
///
/// [headerKey] dipakai tombol "Komentar" buat scroll ke awal bagian ini.
class CommentsSliver extends ConsumerWidget {
  const CommentsSliver({
    super.key,
    required this.args,
    required this.meta,
    required this.headerKey,
    required this.onUpgradeClick,
  });

  final CommentsArgs args;
  final CommentMeta meta;
  final GlobalKey headerKey;
  final VoidCallback onUpgradeClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(commentsControllerProvider(args));
    final ctrl = ref.read(commentsControllerProvider(args).notifier);
    final myUid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid)) ?? '';
    final top = s.sortedTopLevel;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            key: headerKey,
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 4),
            child: Text(
              '${s.totalCount} Komentar',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _SortChip(
                  label: 'Top Comment',
                  selected: s.sortTop,
                  onTap: () => ctrl.setSortTop(true),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  label: 'Terbaru',
                  selected: !s.sortTop,
                  onTap: () => ctrl.setSortTop(false),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: CommentInputRow(
              myUid: myUid,
              placeholder: 'Tulis komentar..',
              isSending: s.isSending,
              showPremiumToggle: true,
              onUpgradeClick: onUpgradeClick,
              onSend: (text, pinned) =>
                  ctrl.postTopLevel(text, pinned: pinned, meta: meta),
            ),
          ),
        ),
        if (s.errorMessage != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                s.errorMessage!,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
              ),
            ),
          ),
        if (s.isLoading)
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: AppColors.accentViolet,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
          )
        else if (top.isEmpty)
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Belum ada komentar. Jadi yang pertama!',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: top.length,
            itemBuilder: (context, i) {
              final c = top[i];
              return CommentItem(
                key: ValueKey('comment-${c.id}'),
                comment: c,
                isOwn: myUid.isNotEmpty && c.firebaseUid == myUid,
                isPremiumSender: s.premiumUids.contains(c.firebaseUid),
                level: s.levels[c.firebaseUid],
                userNumber: s.userNumbers[c.firebaseUid],
                avatarUrl: s.avatarUrls[c.firebaseUid] ?? c.avatarUrl,
                replyCount: s.repliesByParent[c.id]?.length ?? 0,
                isDeleting: s.deletingCommentId == c.id,
                onReplyClick: () {
                  ctrl.openThread(c.id);
                  showCommentThreadSheet(context, args: args, meta: meta);
                },
                onDeleteClick: () => ctrl.deleteComment(c),
              );
            },
          ),
      ],
    );
  }
}

/// Sheet "Threads": komentar utama + balasan + kolom balas.
Future<void> showCommentThreadSheet(
  BuildContext context, {
  required CommentsArgs args,
  required CommentMeta meta,
}) {
  // Inset sistem dibaca dari context layar (bukan context sheet) supaya
  // tinggi navigasi HP ikut dihitung; useSafeArea tidak menyentuh sisi bawah.
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: _kSheetColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => _ThreadSheet(
      args: args,
      meta: meta,
      bottomInset: bottomInset,
    ),
  ).whenComplete(() {
    // Container yang dipakai sheet sudah hilang; pakai provider scope lewat
    // ProviderScope.containerOf supaya state thread ikut ditutup.
    if (context.mounted) {
      ProviderScope.containerOf(context, listen: false)
          .read(commentsControllerProvider(args).notifier)
          .closeThread();
    }
  });
}

class _ThreadSheet extends ConsumerWidget {
  const _ThreadSheet({
    required this.args,
    required this.meta,
    required this.bottomInset,
  });

  final CommentsArgs args;
  final CommentMeta meta;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(commentsControllerProvider(args));
    final ctrl = ref.read(commentsControllerProvider(args).notifier);
    final myUid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid)) ?? '';
    final threadId = s.openThreadParentId;

    EpisodeComment? parent;
    for (final c in s.topLevel) {
      if (c.id == threadId) {
        parent = c;
        break;
      }
    }
    final replies = s.repliesByParent[threadId] ?? const <EpisodeComment>[];
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.9;

    Widget item(EpisodeComment c, VoidCallback onReply) => CommentItem(
          key: ValueKey('thread-${c.id}'),
          comment: c,
          isOwn: myUid.isNotEmpty && c.firebaseUid == myUid,
          isPremiumSender: s.premiumUids.contains(c.firebaseUid),
          level: s.levels[c.firebaseUid],
          userNumber: s.userNumbers[c.firebaseUid],
          avatarUrl: s.avatarUrls[c.firebaseUid] ?? c.avatarUrl,
          replyCount: null,
          isDeleting: s.deletingCommentId == c.id,
          onReplyClick: onReply,
          onDeleteClick: () => ctrl.deleteComment(c),
        );

    return Padding(
      // Keyboard naik -> sheet ikut naik; kalau tidak ada keyboard, sisakan
      // ruang setinggi bar navigasi HP supaya kolom balas tidak tertutup.
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Threads',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (parent != null) ...[
                    item(parent, () => ctrl.setReplyTarget(null)),
                    const Divider(
                      height: 1,
                      thickness: 0.6,
                      color: AppColors.surfaceElevated,
                    ),
                  ],
                  for (final r in replies) item(r, () => ctrl.setReplyTarget(r)),
                ],
              ),
            ),
            if (s.replyTarget != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Membalas @${s.replyTarget!.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => ctrl.setReplyTarget(null),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            if (s.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Text(
                  s.errorMessage!,
                  style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
                ),
              ),
            CommentInputRow(
              myUid: myUid,
              placeholder: 'Tulis balasan...',
              isSending: s.isSending,
              showPremiumToggle: false,
              onUpgradeClick: () {},
              onSend: (text, _) => ctrl.postReply(text, meta: meta),
            ),
            SizedBox(height: keyboard > 0 ? 8 : bottomInset + 8),
          ],
        ),
      ),
    );
  }
}

/// Baris input komentar/balasan: avatar sendiri, kolom teks, (mahkota), kirim.
class CommentInputRow extends ConsumerStatefulWidget {
  const CommentInputRow({
    super.key,
    required this.myUid,
    required this.placeholder,
    required this.isSending,
    required this.showPremiumToggle,
    required this.onUpgradeClick,
    required this.onSend,
  });

  final String myUid;
  final String placeholder;
  final bool isSending;
  final bool showPremiumToggle;
  final VoidCallback onUpgradeClick;
  final void Function(String text, bool pinned) onSend;

  @override
  ConsumerState<CommentInputRow> createState() => _CommentInputRowState();
}

class _CommentInputRowState extends ConsumerState<CommentInputRow> {
  final TextEditingController _text = TextEditingController();
  bool _pinned = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty || widget.isSending) return;
    widget.onSend(t, _pinned);
    _text.clear();
    setState(() => _pinned = false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.myUid;
    final profile = uid.isEmpty ? null : ref.watch(chatProfileProvider(uid)).valueOrNull;
    final isPremium = ref.watch(myPremiumProvider).valueOrNull ?? false;
    final loggedIn = uid.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          UserAvatar(
            username: profile?.username ?? '',
            url: profile?.avatarUrl,
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _text,
              builder: (context, v, _) => TextField(
                controller: _text,
                enabled: loggedIn,
                maxLength: kMaxCommentLength,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
                cursorColor: AppColors.accentViolet,
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: loggedIn ? widget.placeholder : 'Masuk untuk berkomentar',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.surfaceElevated),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.surfaceVariantDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: AppColors.accentViolet.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showPremiumToggle) ...[
            const SizedBox(width: 8),
            _RoundButton(
              icon: Icons.workspace_premium,
              background: _pinned ? _kPinnedGold : const Color(0x14FFFFFF),
              iconColor: _pinned ? Colors.white : const Color(0x99FFFFFF),
              onTap: () {
                if (isPremium) {
                  setState(() => _pinned = !_pinned);
                } else {
                  widget.onUpgradeClick();
                }
              },
            ),
          ],
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, v, _) {
              final canSend = loggedIn && v.text.trim().isNotEmpty && !widget.isSending;
              return _RoundButton(
                icon: Icons.send,
                iconSize: 16,
                background: canSend ? AppColors.accentViolet : const Color(0x14FFFFFF),
                iconColor: Colors.white,
                onTap: canSend ? _send : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.background,
    required this.iconColor,
    required this.onTap,
    this.iconSize = 18,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;
  final VoidCallback? onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.isOwn,
    required this.isPremiumSender,
    required this.level,
    required this.userNumber,
    required this.avatarUrl,
    required this.replyCount,
    required this.isDeleting,
    required this.onReplyClick,
    required this.onDeleteClick,
  });

  final EpisodeComment comment;
  final bool isOwn;
  final bool isPremiumSender;
  final int? level;
  final int? userNumber;
  final String? avatarUrl;

  /// null = tampilan di dalam thread (tanpa hitungan balasan).
  final int? replyCount;
  final bool isDeleting;
  final VoidCallback onReplyClick;
  final VoidCallback onDeleteClick;

  @override
  Widget build(BuildContext context) {
    final replyTo = comment.replyToUsername;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(username: comment.username, url: avatarUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: UserCheckBadge(
                        firebaseUid: comment.firebaseUid,
                        isPremium: isPremiumSender,
                        size: 15,
                      ),
                    ),
                    if (comment.isPinned) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.workspace_premium, size: 14, color: _kPinnedGold),
                    ],
                    if (userNumber != null) ...[
                      const SizedBox(width: 3),
                      Text(
                        '#$userNumber',
                        style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 10),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      formatCommentRelativeTime(comment.createdAt),
                      style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 10),
                    ),
                    if (isOwn)
                      SizedBox(
                        width: 26,
                        height: 22,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          color: AppColors.surfaceElevated,
                          icon: const Icon(Icons.more_vert, size: 16, color: Color(0x80FFFFFF)),
                          onSelected: (_) => onDeleteClick(),
                          itemBuilder: (_) => const [
                            PopupMenuItem<String>(
                              value: 'hapus',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18, color: AppColors.textWhite),
                                  SizedBox(width: 8),
                                  Text('Hapus', style: TextStyle(color: AppColors.textWhite)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (level != null) ...[
                  const SizedBox(height: 3),
                  LevelBadge(level: level!),
                ],
                const SizedBox(height: 4),
                if (replyTo != null && replyTo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '@$replyTo',
                      style: const TextStyle(
                        color: AppColors.accentViolet,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Text(
                  comment.comment,
                  style: const TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onReplyClick,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          (replyCount != null && replyCount! > 0)
                              ? 'Reply ($replyCount)'
                              : 'Reply',
                          style: const TextStyle(
                            color: AppColors.accentViolet,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (isDeleting) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0x4DFFFFFF),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// "Baru saja", "5 menit lalu", ... lalu dd/MM/yy kalau sudah > 30 hari.
String formatCommentRelativeTime(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  final minutes = diff.inMinutes < 0 ? 0 : diff.inMinutes;
  final hours = minutes ~/ 60;
  final days = hours ~/ 24;
  if (minutes < 1) return 'Baru saja';
  if (minutes < 60) return '$minutes menit lalu';
  if (hours < 24) return '$hours jam lalu';
  if (days < 7) return '$days hari lalu';
  if (days < 30) return '${days ~/ 7} minggu lalu';
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${two(l.year % 100)}';
}
