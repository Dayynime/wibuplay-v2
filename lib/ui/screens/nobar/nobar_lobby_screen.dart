import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/nobar_models.dart';
import '../../../data/repository/nobar_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../components/net_image.dart';
import 'nobar_screen.dart';

/// Buka layar room nobar. [replace] = ganti layar sekarang (dari player).
Future<void> openNobarRoom(BuildContext context, NobarRoom room, {bool replace = false}) async {
  final nav = Navigator.of(context);
  final route = fadeRoute<void>(NobarScreen(initial: room));
  if (replace) {
    await nav.pushReplacement<void, void>(route);
  } else {
    await nav.push<void>(route);
  }
}

/// Lobby Nobar: masuk pakai kode, atau kembali ke room yang masih aktif.
/// Room baru dibuat dari tombol "Nobar" di layar player.
class NobarLobbyScreen extends ConsumerStatefulWidget {
  const NobarLobbyScreen({super.key});

  @override
  ConsumerState<NobarLobbyScreen> createState() => _NobarLobbyScreenState();
}

class _NobarLobbyScreenState extends ConsumerState<NobarLobbyScreen> {
  final TextEditingController _code = TextEditingController();
  List<NobarRoom>? _rooms;
  List<NobarPublicRoom>? _public;
  bool _busy = false;
  Timer? _poll;

  NobarRepository get _repo => ref.read(nobarRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
    // Daftar "Lagi nobar" diperbarui sendiri selama lobby terbuka.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _loadPublic());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() => Future.wait([_loadMine(), _loadPublic()]);

  Future<void> _loadMine() async {
    try {
      final list = await _repo.myRooms();
      if (mounted) setState(() => _rooms = list);
    } catch (_) {
      if (mounted) setState(() => _rooms = const []);
    }
  }

  Future<void> _loadPublic() async {
    try {
      final list = await _repo.publicRooms();
      if (mounted) setState(() => _public = list);
    } catch (_) {
      if (mounted && _public == null) setState(() => _public = const []);
    }
  }

  /// Tap room di daftar "Lagi nobar": room sendiri langsung dibuka, room
  /// orang lain wajib memasukkan kode dari host.
  Future<void> _tapPublic(NobarPublicRoom r) async {
    if (r.isMember) {
      final mine = _rooms ?? const [];
      if (mine.isNotEmpty) {
        await _enter(() => _repo.joinById(mine.first.id));
        return;
      }
    }
    if (r.isFull) {
      _snack('Room penuh (maksimal ${r.maxMembers} orang)');
      return;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _CodeDialog(room: r),
    );
    if (code == null || !mounted) return;
    await _enter(() => _repo.joinByCode(code));
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _enter(Future<NobarRoom> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await action();
      if (!mounted) return;
      setState(() => _busy = false);
      HapticFeedback.mediumImpact();
      await openNobarRoom(context, room);
      if (mounted) _load();
    } on NobarException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.message);
    }
  }

  void _joinCode() {
    final code = _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length != 6) {
      _snack('Kode room harus 6 karakter');
      return;
    }
    FocusScope.of(context).unfocus();
    _enter(() => _repo.joinByCode(code));
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        title: const Text('Nobar', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E2A44), Color(0xFF0F2034)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.groups_rounded, color: AppColors.accentViolet),
                      SizedBox(width: 8),
                      Text(
                        'Nonton bareng + voice chat',
                        style: TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Maksimal $kNobarMaxMembers orang per room. Video ikut host, '
                    'semua bisa buka mic & ngobrol realtime.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 6,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800,
                          ),
                          onSubmitted: (_) => _joinCode(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'KODE ROOM',
                            hintStyle: const TextStyle(color: AppColors.textMuted, letterSpacing: 2),
                            filled: true,
                            fillColor: AppColors.surfaceElevated,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentViolet,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _busy ? null : _joinCode,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Masuk', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: AppColors.warningAmber, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mau bikin room? Buka anime yang mau ditonton, lalu tekan tombol '
                      '"Nobar" di bawah video. Bagikan kodenya ke temanmu.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (rooms == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
              )
            else if (rooms.isNotEmpty) ...[
              const Text(
                'Room kamu yang masih aktif',
                style: TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final r in rooms) _roomTile(r),
              const SizedBox(height: 10),
            ],
            ..._publicSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _publicSection() {
    final list = _public;
    return [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Color(0xFFFF4D6A), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            list == null || list.isEmpty ? 'Lagi nobar' : 'Lagi nobar · ${list.length} room',
            style: const TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Mau gabung? Minta kode room ke host-nya.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      if (list == null)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2.5)),
        )
      else if (list.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surfaceCard, borderRadius: BorderRadius.circular(14)),
          child: const Text(
            'Belum ada yang nobar sekarang. Jadi yang pertama!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        )
      else
        for (final r in list) _publicTile(r),
    ];
  }

  Widget _publicTile(NobarPublicRoom r) {
    final poster = r.posterUrl;
    final shown = r.members.take(4).toList();
    final String status;
    final Color statusColor;
    if (r.isMember) {
      status = 'Kamu di sini';
      statusColor = AppColors.successGreen;
    } else if (r.isFull) {
      status = 'Penuh';
      statusColor = AppColors.textMuted;
    } else {
      status = '${r.memberCount}/${r.maxMembers}';
      statusColor = AppColors.accentVioletLight;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : () => _tapPublic(r),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 62,
                    child: poster == null
                        ? const ColoredBox(color: AppColors.surfaceElevated)
                        : NetImage(poster, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (r.movieTitle == null || r.movieTitle!.isEmpty) ? 'Nobar' : r.movieTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Host: ${r.host.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (final m in shown)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: FriendAvatar(
                                url: m.avatarUrl,
                                seed: m.uid,
                                label: m.username,
                                size: 22,
                                framed: false,
                              ),
                            ),
                          if (r.memberCount > shown.length)
                            Text(
                              '+${r.memberCount - shown.length}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Icon(
                      r.isMember ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomTile(NobarRoom r) {
    final poster = r.posterUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _enter(() => _repo.joinById(r.id)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 62,
                    child: poster == null || poster.isEmpty
                        ? const ColoredBox(color: AppColors.surfaceElevated)
                        : NetImage(poster, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.movieTitle ?? 'Nobar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kode ${r.code} · ${r.members.length}/${r.maxMembers} orang',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minta kode room sebelum gabung ke room orang lain.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.room});

  final NobarPublicRoom room;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _c.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length != 6) {
      setState(() => _error = 'Kode room harus 6 karakter');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    return AlertDialog(
      backgroundColor: AppColors.surfaceCard,
      title: const Text('Masukkan kode room', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Room ${r.host.username}${r.movieTitle == null || r.movieTitle!.isEmpty ? '' : ' · ${r.movieTitle}'}. '
            'Minta kodenya ke host.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(color: AppColors.textWhite, letterSpacing: 4, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'KODE ROOM',
              errorText: _error,
              hintStyle: const TextStyle(color: AppColors.textMuted, letterSpacing: 2),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
          onPressed: _submit,
          child: const Text('Gabung', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
