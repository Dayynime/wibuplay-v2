import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/sticker_models.dart';
import '../../../data/repository/authed_function.dart';
import '../../../providers.dart';
import '../../components/app_toast.dart';
import '../../glass/glass.dart';
import '../sticker/sticker_widgets.dart';
import 'chat_mute.dart' show canChatMuteProvider;

/// Satu pesan yang disematkan di Chat Global (Edge Function `chat-pin`).
class ChatPin {
  const ChatPin({required this.id, required this.username, required this.message, this.messageType});

  final int id;
  final String username;
  final String message;
  final String? messageType;

  /// Teks singkat untuk banner (stiker / pesan suara diberi label).
  String get preview {
    if (stickerCodeOf(message) != null) return 'Stiker';
    if (messageType == 'voice') return 'Pesan suara';
    return message.replaceAll('\n', ' ');
  }

  static ChatPin? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = (v['id'] as num?)?.toInt();
    if (id == null) return null;
    final name = (v['username'] as String?)?.trim() ?? '';
    return ChatPin(
      id: id,
      username: name.isEmpty ? 'Pengguna' : name,
      message: (v['message'] as String?) ?? '',
      messageType: v['message_type'] as String?,
    );
  }
}

class ChatPinRepository {
  ChatPinRepository(this._dio);

  final Dio _dio;

  Future<List<ChatPin>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, 'chat-pin', body);
      final list = d is Map ? d['pins'] : null;
      if (list is! List) return const [];
      return list.map(ChatPin.fromJson).whereType<ChatPin>().toList();
    } on DioException catch (_) {
      throw Exception('Koneksi bermasalah, coba lagi');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '').trim();
      throw Exception(m.isEmpty || m.length > 200 ? fallback : m);
    }
  }

  Future<List<ChatPin>> list() => _call({'action': 'list'}, 'Gagal memuat pesan disematkan');
  Future<List<ChatPin>> pin(int id) => _call({'action': 'pin', 'id': id}, 'Gagal menyematkan pesan');
  Future<List<ChatPin>> unpin(int id) => _call({'action': 'unpin', 'id': id}, 'Gagal melepas sematan');
}

final chatPinRepositoryProvider = Provider<ChatPinRepository>(
  (ref) => ChatPinRepository(ref.watch(supabaseDioProvider)),
);

/// Daftar sematan (terbaru dulu). Diperbarui tiap 30 dtk selama dipakai.
class ChatPinsNotifier extends AutoDisposeNotifier<List<ChatPin>> {
  Timer? _poll;

  @override
  List<ChatPin> build() {
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    ref.onDispose(() => _poll?.cancel());
    Future.microtask(refresh);
    return const [];
  }

  Future<void> refresh() async {
    try {
      state = await ref.read(chatPinRepositoryProvider).list();
    } catch (_) {}
  }

  /// [pin] true = sematkan, false = lepas. Return pesan error (null = sukses).
  Future<String?> toggle(int id, bool pin) async {
    try {
      final repo = ref.read(chatPinRepositoryProvider);
      state = pin ? await repo.pin(id) : await repo.unpin(id);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }
}

final chatPinsProvider = AutoDisposeNotifierProvider<ChatPinsNotifier, List<ChatPin>>(ChatPinsNotifier.new);

/// Sematkan / lepas dari menu pesan (khusus pemegang role).
Future<void> toggleChatPin(BuildContext context, WidgetRef ref, int id) async {
  final pinned = ref.read(chatPinsProvider).any((p) => p.id == id);
  final err = await ref.read(chatPinsProvider.notifier).toggle(id, !pinned);
  if (!context.mounted) return;
  if (err != null) {
    showAppToast(context, err, kind: ToastKind.error);
  } else {
    showAppToast(
      context,
      pinned ? 'Sematan dilepas' : 'Pesan disematkan',
      kind: ToastKind.success,
      icon: Icons.push_pin_rounded,
    );
  }
}

/// Banner "N pesan disematkan" di atas Chat Global. Tap = daftar lengkap.
/// [onJump] dipanggil saat sebuah sematan dipilih; return true kalau pesan
/// itu sedang dimuat di layar (sheet ditutup lalu lompat ke pesannya).
class ChatPinBanner extends ConsumerWidget {
  const ChatPinBanner({super.key, required this.onJump});

  final bool Function(int id) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(chatPinsProvider);
    if (pins.isEmpty) return const SizedBox.shrink();
    final first = pins.first;
    return Material(
      color: AppColors.surfaceDark,
      child: InkWell(
        onTap: () => showGlassSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surfaceDark,
          builder: (_) => _PinsSheet(onJump: onJump),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentViolet,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pins.length == 1 ? 'Pesan disematkan' : '${pins.length} pesan disematkan',
                      style: const TextStyle(
                        color: AppColors.accentVioletLight,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      first.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.push_pin_outlined, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinsSheet extends ConsumerWidget {
  const _PinsSheet({required this.onJump});

  final bool Function(int id) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(chatPinsProvider);
    final canEdit = ref.watch(canChatMuteProvider).valueOrNull == true;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded, color: AppColors.accentViolet, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Pesan Disematkan',
                    style: TextStyle(color: AppColors.textWhite, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (pins.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Belum ada pesan disematkan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
                  itemCount: pins.length,
                  separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.12), height: 18),
                  itemBuilder: (ctx, i) {
                    final p = pins[i];
                    final sticker = stickerCodeOf(p.message);
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        if (onJump(p.id)) Navigator.pop(ctx);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (sticker != null)
                                  StickerView(code: sticker, size: 72)
                                else
                                  Text(
                                    p.messageType == 'voice' ? '🎤 Pesan suara' : p.message,
                                    style: const TextStyle(color: AppColors.textWhite, fontSize: 14.5, height: 1.35),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  p.username,
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (canEdit)
                            IconButton(
                              tooltip: 'Lepas sematan',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                              onPressed: () => toggleChatPin(context, ref, p.id),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
