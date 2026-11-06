import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../data/repository/authed_function.dart';
import '../../../providers.dart';
import '../../components/friend_avatar.dart';

/// Kirim notif mention lewat Edge Function `chat-mention`. Server mengecek
/// ulang semuanya (wajib teman, anggota clan, nama ada di teks, maks 5).
class ChatMentionRepository {
  ChatMentionRepository(this._dio);

  final Dio _dio;

  Future<void> notify(String channel, int messageId, List<String> uids) async {
    if (uids.isEmpty) return;
    try {
      await callAuthedFunction(_dio, 'chat-mention', {
        'action': 'notify',
        'channel': channel,
        'message_id': messageId,
        'uids': uids.take(5).toList(),
      });
    } catch (_) {
      // Notif mention cuma pelengkap; pesan tetap terkirim.
    }
  }
}

final chatMentionRepositoryProvider = Provider<ChatMentionRepository>(
  (ref) => ChatMentionRepository(ref.watch(supabaseDioProvider)),
);

/// Daftar teman untuk saran mention (dimuat sekali selama layar chat terbuka).
final mentionFriendsProvider = FutureProvider.autoDispose<List<FriendDisplay>>((ref) async {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  if (uid == null || uid.isEmpty) return const [];
  try {
    final lists = await ref.read(friendRepositoryProvider).getLists(uid);
    return lists.friends;
  } catch (_) {
    return const [];
  }
});

/// Melacak mention yang dipilih di satu kolom ketik.
class MentionTracker {
  MentionTracker(this.input);

  final TextEditingController input;

  /// username -> uid yang dipilih dari saran.
  final Map<String, String> _picked = {};

  /// Kata yang sedang diketik setelah "@" (null = tidak sedang mention).
  /// "@" harus di awal teks atau setelah spasi/baris baru.
  String? get query {
    final sel = input.selection;
    final text = input.text;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final before = text.substring(0, sel.baseOffset.clamp(0, text.length));
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    if (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1])) return null;
    final q = before.substring(at + 1);
    if (q.length > 24 || q.contains('\n') || q.contains('@')) return null;
    return q;
  }

  /// Ganti "@ketikan" dengan "@Nama " dan ingat uid-nya.
  void pick(FriendDisplay f) {
    final sel = input.selection;
    final text = input.text;
    final end = sel.baseOffset.clamp(0, text.length);
    final at = text.substring(0, end).lastIndexOf('@');
    if (at < 0) return;
    final insert = '@${f.username} ';
    final next = text.replaceRange(at, end, insert);
    input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    _picked[f.username] = f.firebaseUid;
  }

  /// Uid yang namanya masih ada di teks saat dikirim (maks 5).
  List<String> uidsFor(String text) {
    final lower = text.toLowerCase();
    return _picked.entries
        .where((e) => lower.contains('@${e.key.toLowerCase()}'))
        .map((e) => e.value)
        .toSet()
        .take(5)
        .toList();
  }

  void clear() => _picked.clear();
}

/// Saran teman di atas kolom ketik saat mengetik "@". Hanya teman.
class MentionSuggestions extends ConsumerWidget {
  const MentionSuggestions({super.key, required this.tracker});

  final MentionTracker tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: tracker.input,
      builder: (context, _) {
        final q = tracker.query;
        if (q == null) return const SizedBox.shrink();
        final friends = ref.watch(mentionFriendsProvider).valueOrNull;
        if (friends == null) return const SizedBox.shrink();
        final ql = q.toLowerCase();
        final list = friends
            .where((f) => ql.isEmpty || f.username.toLowerCase().contains(ql))
            .take(5)
            .toList();
        return Container(
          constraints: const BoxConstraints(maxHeight: 230),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    friends.isEmpty ? 'Mention cuma bisa ke teman. Kamu belum punya teman.' : 'Teman tidak ditemukan',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final f in list)
                      InkWell(
                        onTap: () => tracker.pick(f),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              FriendAvatar(
                                url: f.avatarUrl,
                                seed: f.firebaseUid,
                                label: f.username,
                                size: 30,
                                framed: false,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  f.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (f.userNumber != null)
                                Text(
                                  '#${f.userNumber}',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Teks pesan dengan "@kata" diwarnai.
class MentionText extends StatelessWidget {
  const MentionText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  static final RegExp _re = RegExp(r'(^|\s)(@[^\s@]+)');

  @override
  Widget build(BuildContext context) {
    if (!text.contains('@')) return Text(text, style: style);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _re.allMatches(text)) {
      final start = m.start + m.group(1)!.length;
      if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
      spans.add(TextSpan(
        text: m.group(2),
        style: const TextStyle(color: AppColors.accentVioletLight, fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
