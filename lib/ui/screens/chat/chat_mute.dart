import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/authed_function.dart';
import '../../../providers.dart';
import '../../components/app_toast.dart';
import '../../glass/glass.dart';

/// Status mute chat (Global, Clan, Komentar). Dari Edge Function `chat-mute`.
class ChatMute {
  const ChatMute({this.muted = false, this.permanent = false, this.until, this.reason, this.message});

  final bool muted;
  final bool permanent;
  final DateTime? until;
  final String? reason;
  final String? message;

  /// Masih berlaku sekarang (mute berwaktu bisa habis saat layar terbuka).
  bool get active => muted && (permanent || (until != null && until!.isAfter(DateTime.now())));

  factory ChatMute.fromJson(Map<String, dynamic> j) => ChatMute(
        muted: j['muted'] == true,
        permanent: j['permanent'] == true,
        until: DateTime.tryParse((j['until'] as String?) ?? '')?.toLocal(),
        reason: (j['reason'] as String?)?.trim(),
        message: j['message'] as String?,
      );
}

class ChatMuteException implements Exception {
  const ChatMuteException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ChatMuteRepository {
  ChatMuteRepository(this._dio);

  final Dio _dio;

  Future<ChatMute> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, 'chat-mute', body);
      return d is Map ? ChatMute.fromJson(Map<String, dynamic>.from(d)) : const ChatMute();
    } on DioException catch (_) {
      throw const ChatMuteException('Koneksi bermasalah, coba lagi');
    } catch (e) {
      // callAuthedFunction meneruskan pesan error server sebagai Exception.
      final m = e.toString().replaceFirst('Exception: ', '').trim();
      throw ChatMuteException(m.isEmpty || m.length > 200 ? fallback : m);
    }
  }

  Future<ChatMute> myStatus() => _call({'action': 'status'}, 'Gagal cek status mute');

  Future<ChatMute> check(String uid) => _call({'action': 'check', 'uid': uid}, 'Gagal cek status mute');

  /// [duration]: 1h | 1d | 1w | perm
  Future<ChatMute> mute(String uid, String duration, {String? reason}) => _call(
        {'action': 'mute', 'uid': uid, 'duration': duration, if (reason != null && reason.isNotEmpty) 'reason': reason},
        'Gagal mute user',
      );

  Future<ChatMute> unmute(String uid) => _call({'action': 'unmute', 'uid': uid}, 'Gagal cabut mute');
}

final chatMuteRepositoryProvider = Provider<ChatMuteRepository>(
  (ref) => ChatMuteRepository(ref.watch(supabaseDioProvider)),
);

/// Status mute diriku. Gagal dimuat = dianggap tidak di-mute (server tetap
/// menolak pesan kalau ternyata di-mute).
final myChatMuteProvider = FutureProvider.autoDispose<ChatMute>((ref) async {
  try {
    return await ref.read(chatMuteRepositoryProvider).myStatus();
  } catch (_) {
    return const ChatMute();
  }
});

/// true = aku developer/admin/moderator (boleh mute user lain).
final canChatMuteProvider = FutureProvider<bool>((ref) async {
  try {
    final r = await ref.read(adminRepositoryProvider).getMyRole();
    return r.role == 'developer' || r.role == 'admin' || r.role == 'moderator';
  } catch (_) {
    return false;
  }
});

String _fmt(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

/// Ganti kolom ketik dengan info mute selama aku di-mute. Status dicek ulang
/// tiap menit dan saat mute habis.
class ChatMuteGate extends ConsumerStatefulWidget {
  const ChatMuteGate({super.key, required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  ConsumerState<ChatMuteGate> createState() => _ChatMuteGateState();
}

class _ChatMuteGateState extends ConsumerState<ChatMuteGate> {
  Timer? _poll;
  Timer? _expire;
  DateTime? _scheduledFor;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) ref.invalidate(myChatMuteProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _expire?.cancel();
    super.dispose();
  }

  void _scheduleExpire(ChatMute m) {
    final until = m.until;
    if (!m.active || m.permanent || until == null || until == _scheduledFor) return;
    _scheduledFor = until;
    _expire?.cancel();
    _expire = Timer(until.difference(DateTime.now()) + const Duration(seconds: 2), () {
      if (mounted) ref.invalidate(myChatMuteProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(myChatMuteProvider).valueOrNull;
    if (m == null || !m.active) return widget.child;
    _scheduleExpire(m);
    final text = m.permanent ? 'Kamu di-mute permanen dari chat' : 'Kamu di-mute sampai ${_fmt(m.until!)}';
    final banner = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: widget.compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.errorRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_off_rounded, color: AppColors.errorRed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (m.reason != null && m.reason!.isNotEmpty)
                  Text(
                    'Alasan: ${m.reason}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.compact) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: banner);
    }
    return Container(
      color: AppColors.backgroundDarkSecondary,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SafeArea(top: false, child: banner),
    );
  }
}

/// Menu mute untuk developer/admin/moderator: 1 jam, 1 hari, 1 minggu,
/// permanen, atau cabut mute. Role dicek ulang di server.
Future<void> showChatMuteSheet(BuildContext context, WidgetRef ref, {required String uid, required String name}) {
  return showGlassSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    builder: (_) => _MuteSheet(uid: uid, name: name, host: context),
  );
}

class _MuteSheet extends ConsumerStatefulWidget {
  const _MuteSheet({required this.uid, required this.name, required this.host});

  final String uid;
  final String name;

  /// Context layar pemanggil: toast ditampilkan di sini setelah sheet ditutup.
  final BuildContext host;

  @override
  ConsumerState<_MuteSheet> createState() => _MuteSheetState();
}

class _MuteSheetState extends ConsumerState<_MuteSheet> {
  final _reason = TextEditingController();
  ChatMute? _current;
  bool _busy = false;

  static const _options = [
    ('1h', '1 jam'),
    ('1d', '1 hari'),
    ('1w', '1 minggu'),
    ('perm', 'Permanen'),
  ];

  ChatMuteRepository get _repo => ref.read(chatMuteRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _repo.check(widget.uid).then((m) {
      if (mounted) setState(() => _current = m);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ChatMute> Function() action, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      if (widget.host.mounted) showAppToast(widget.host, ok, kind: ToastKind.success);
    } on ChatMuteException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, e.message, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    final active = cur != null && cur.active;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 14 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_off_rounded, color: AppColors.errorRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mute ${widget.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              active
                  ? (cur.permanent ? 'Sedang di-mute permanen.' : 'Sedang di-mute sampai ${_fmt(cur.until!)}.')
                  : 'Tidak bisa kirim pesan di Chat Global, Clan, dan Komentar.',
              style: TextStyle(color: active ? AppColors.errorRed : AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              maxLength: 120,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Alasan (opsional, terlihat oleh user)',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                counterText: '',
                filled: true,
                fillColor: AppColors.surfaceElevated,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (code, label) in _options)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => _repo.mute(widget.uid, code, reason: _reason.text.trim()),
                              code == 'perm' ? '${widget.name} di-mute permanen' : '${widget.name} di-mute $label',
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: code == 'perm' ? AppColors.errorRed : AppColors.surfaceElevated,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(() => _repo.unmute(widget.uid), 'Mute ${widget.name} dicabut'),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('Cabut mute'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.successGreen,
                    side: BorderSide(color: AppColors.successGreen.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
