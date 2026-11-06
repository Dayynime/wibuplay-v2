import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/authed_function.dart';
import '../../../providers.dart';
import '../../components/app_toast.dart';

/// Emoji reaksi yang boleh dipakai (sama dengan server, chat_react.sql).
const List<String> kChatReactEmojis = ['👍', '😂', '❤️', '🔥', '😮', '😢'];

/// Reaksi satu pesan: jumlah per emoji + reaksiku (null = belum).
class MsgReactions {
  const MsgReactions({this.counts = const {}, this.mine});

  final Map<String, int> counts;
  final String? mine;

  bool get isEmpty => counts.values.every((n) => n <= 0);

  static MsgReactions fromJson(Map<dynamic, dynamic> j) {
    final raw = j['counts'];
    final counts = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = (v as num?)?.toInt() ?? 0;
        if (k is String && n > 0) counts[k] = n;
      });
    }
    return MsgReactions(counts: counts, mine: j['mine'] as String?);
  }

  /// Hasil kalau aku memilih [emoji] (emoji yang sama = batal).
  MsgReactions toggled(String emoji) {
    final c = Map<String, int>.from(counts);
    void dec(String e) {
      final n = (c[e] ?? 0) - 1;
      if (n <= 0) {
        c.remove(e);
      } else {
        c[e] = n;
      }
    }

    if (mine == emoji) {
      dec(emoji);
      return MsgReactions(counts: c);
    }
    if (mine != null) dec(mine!);
    c[emoji] = (c[emoji] ?? 0) + 1;
    return MsgReactions(counts: c, mine: emoji);
  }
}

class ChatReactRepository {
  ChatReactRepository(this._dio);

  final Dio _dio;

  Future<Map<int, MsgReactions>> counts(String channel, List<int> ids) async {
    final d = await callAuthedFunction(_dio, 'chat-react', {'action': 'counts', 'channel': channel, 'ids': ids});
    final items = d is Map ? d['items'] : null;
    final out = <int, MsgReactions>{};
    if (items is List) {
      for (final e in items.whereType<Map>()) {
        final id = (e['id'] as num?)?.toInt();
        if (id != null) out[id] = MsgReactions.fromJson(e);
      }
    }
    return out;
  }

  Future<MsgReactions> react(String channel, int id, String? emoji) async {
    final d = await callAuthedFunction(
      _dio,
      'chat-react',
      {'action': 'react', 'channel': channel, 'id': id, 'emoji': emoji},
    );
    final item = d is Map ? d['item'] : null;
    return item is Map ? MsgReactions.fromJson(item) : const MsgReactions();
  }
}

final chatReactRepositoryProvider = Provider<ChatReactRepository>(
  (ref) => ChatReactRepository(ref.watch(supabaseDioProvider)),
);

/// Reaksi per pesan untuk satu channel ('global' / 'clan'). Pesan yang
/// sedang tampil didaftarkan lewat [track]; diperbarui tiap 15 detik.
class ChatReactionStore extends AutoDisposeFamilyNotifier<Map<int, MsgReactions>, String> {
  List<int> _tracked = const [];
  final Set<int> _fetched = {};
  Timer? _poll;
  Timer? _debounce;
  bool _busy = false;

  /// Pesan yang baru saja kuberi reaksi: jangan ditimpa hasil polling lama.
  final Map<int, DateTime> _pendingUntil = {};

  @override
  Map<int, MsgReactions> build(String channel) {
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _fetch(_tracked));
    ref.onDispose(() {
      _poll?.cancel();
      _debounce?.cancel();
    });
    return const {};
  }

  /// Daftarkan pesan yang sedang dimuat (maks 100 terbaru).
  void track(Iterable<int> ids) {
    final list = ids.toList();
    _tracked = list.length > 100 ? list.sublist(list.length - 100) : list;
    final fresh = _tracked.where((id) => !_fetched.contains(id)).toList();
    if (fresh.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(_tracked));
  }

  Future<void> _fetch(List<int> ids) async {
    if (ids.isEmpty || _busy) return;
    _busy = true;
    try {
      final got = await ref.read(chatReactRepositoryProvider).counts(arg, ids);
      final now = DateTime.now();
      final next = Map<int, MsgReactions>.from(state);
      for (final id in ids) {
        final until = _pendingUntil[id];
        if (until != null && until.isAfter(now)) continue;
        next[id] = got[id] ?? const MsgReactions();
      }
      _fetched.addAll(ids);
      state = next;
    } catch (_) {
      // Reaksi cuma pelengkap; polling berikutnya mencoba lagi.
    } finally {
      _busy = false;
    }
  }

  /// Pilih / batalkan reaksi. Return pesan error (null = sukses).
  Future<String?> react(int id, String emoji) async {
    final before = state[id] ?? const MsgReactions();
    final after = before.toggled(emoji);
    _pendingUntil[id] = DateTime.now().add(const Duration(seconds: 20));
    state = {...state, id: after};
    try {
      final res = await ref.read(chatReactRepositoryProvider).react(arg, id, after.mine);
      state = {...state, id: res};
      return null;
    } catch (e) {
      state = {...state, id: before};
      final m = e.toString().replaceFirst('Exception: ', '').trim();
      return e is DioException || m.isEmpty || m.length > 200 ? 'Gagal memberi reaksi' : m;
    } finally {
      _pendingUntil.remove(id);
    }
  }
}

final chatReactionsProvider =
    AutoDisposeNotifierProviderFamily<ChatReactionStore, Map<int, MsgReactions>, String>(ChatReactionStore.new);

/// Pilih / batalkan reaksi; error ditampilkan sebagai toast di [context].
Future<void> reactToMessage(BuildContext context, WidgetRef ref, String channel, int id, String emoji) async {
  HapticFeedback.selectionClick();
  final err = await ref.read(chatReactionsProvider(channel).notifier).react(id, emoji);
  if (err != null && context.mounted) showAppToast(context, err, kind: ToastKind.error);
}

/// Chip reaksi di bawah isi pesan ("👍 3  😂 1"). Tap = ikut / batal.
class ChatReactionChips extends ConsumerWidget {
  const ChatReactionChips({super.key, required this.channel, required this.id});

  final String channel;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(chatReactionsProvider(channel).select((m) => m[id]));
    if (r == null || r.isEmpty) return const SizedBox.shrink();
    final entries = r.counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in entries)
            Material(
              color: r.mine == e.key ? AppColors.accentViolet.withValues(alpha: 0.22) : const Color(0x14FFFFFF),
              shape: StadiumBorder(
                side: BorderSide(
                  color: r.mine == e.key ? AppColors.accentViolet.withValues(alpha: 0.7) : Colors.transparent,
                ),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => reactToMessage(context, ref, channel, id, e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(
                    '${e.key} ${e.value}',
                    style: TextStyle(
                      color: r.mine == e.key ? AppColors.textWhite : AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Baris pilihan emoji di atas menu pesan (tekan lama).
class ChatReactionPicker extends ConsumerWidget {
  const ChatReactionPicker({super.key, required this.channel, required this.id, required this.onPicked});

  final String channel;
  final int id;

  /// Emoji yang dipilih. Pemanggil menutup menu lalu memanggil
  /// [reactToMessage] dengan context & ref layarnya sendiri.
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(chatReactionsProvider(channel).select((m) => m[id]?.mine));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final e in kChatReactEmojis)
            GestureDetector(
              onTap: () => onPicked(e),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mine == e ? AppColors.accentViolet.withValues(alpha: 0.3) : const Color(0x14FFFFFF),
                ),
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
      ),
    );
  }
}
