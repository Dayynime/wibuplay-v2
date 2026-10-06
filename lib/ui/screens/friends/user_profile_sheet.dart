import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../components/friend_avatar.dart';
import '../../components/game_badges.dart';
import '../../components/net_image.dart';
import '../../components/role_badges.dart';

/// Profil ringkas user lain (dibuka dari Chat Global, Chat Teman, dan layar
/// Teman) lengkap dengan tombol Tambah Teman, mengikuti alur Zenime.
Future<void> showUserProfileSheet(BuildContext context, String uid) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => UserProfileSheet(uid: uid),
  );
}

class UserProfileSheet extends ConsumerStatefulWidget {
  const UserProfileSheet({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends ConsumerState<UserProfileSheet> {
  FriendRelation? _relation;
  bool _relationFailed = false;
  bool _busy = false;
  String? _error;

  String get _myUid => ref.read(authRepositoryProvider).currentUser?.uid ?? '';
  bool get _isMe => _myUid.isNotEmpty && _myUid == widget.uid;

  @override
  void initState() {
    super.initState();
    if (!_isMe && _myUid.isNotEmpty) _loadRelation();
  }

  Future<void> _loadRelation() async {
    try {
      final r = await ref.read(friendRepositoryProvider).getRelation(_myUid, widget.uid);
      if (!mounted) return;
      setState(() {
        _relation = r;
        _relationFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _relationFailed = true);
    }
  }

  /// Jalankan aksi lalu muat ulang hubungan (juga kalau gagal, mis. dia kirim
  /// permintaan barengan sehingga baris sudah ada).
  Future<void> _act(Future<void> Function() action, String fallback) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    try {
      await action();
    } catch (e) {
      err = errorMessage(e, fallback);
    }
    ref.invalidate(incomingFriendRequestsProvider);
    await _loadRelation();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final profile = ref.watch(chatProfileProvider(uid)).valueOrNull;
    final premium = ref.watch(premiumProvider(uid)).valueOrNull ?? false;
    final level = ref.watch(myXpProvider(uid)).valueOrNull?.level;
    final clanTag = ref.watch(userClanTagProvider(uid)).valueOrNull;

    final name = (profile?.username.trim().isNotEmpty ?? false) ? profile!.username : 'Pengguna Zenime';
    final banner = premium && (profile?.bannerUrl?.isNotEmpty ?? false) ? profile!.bannerUrl : null;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: banner != null
                      ? NetImage(banner)
                      : const ColoredBox(color: AppColors.surfaceVariantDark),
                ),
              ),
              Positioned(
                top: 110 - 44,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceDark,
                    shape: BoxShape.circle,
                  ),
                  child: FriendAvatar(
                    url: profile?.avatarUrl,
                    seed: uid,
                    label: name,
                    size: 88,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 54),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (profile?.userNumber != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'ID #${profile!.userNumber}',
                      style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: UserCheckBadge(firebaseUid: uid, isPremium: premium, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (level != null) LevelBadge(level: level, height: 20),
              if (clanTag != null && clanTag.isNotEmpty) ClanRainbowBadge(text: clanTag, height: 20),
              RoleBadge(firebaseUid: uid, height: 20),
            ],
          ),
          const SizedBox(height: 18),
          if (!_isMe) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildFriendActions(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFriendActions() {
    if (_myUid.isEmpty) {
      return const Text(
        'Masuk dulu untuk menambah teman.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }
    if (_relationFailed) {
      return TextButton(
        onPressed: _loadRelation,
        child: const Text('Gagal memuat status teman. Coba lagi', style: TextStyle(color: AppColors.accentViolet)),
      );
    }
    final relation = _relation;
    if (relation == null) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet),
          ),
        ),
      );
    }
    final repo = ref.read(friendRepositoryProvider);

    Widget filled(IconData icon, String label, VoidCallback? onTap) => SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _busy ? null : onTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              shape: const StadiumBorder(),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        );

    Widget outlined(IconData icon, String label, VoidCallback? onTap, {Color color = Colors.white}) =>
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.4)),
              shape: const StadiumBorder(),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );

    return switch (relation) {
      FriendRelationNone() => filled(
          Icons.person_add,
          'Tambah Teman',
          () => _act(() => repo.sendRequest(_myUid, widget.uid), 'Gagal mengirim permintaan'),
        ),
      FriendRelationOutgoing(:final friendshipId) => outlined(
          Icons.hourglass_top,
          'Permintaan Terkirim · Batalkan',
          () => _act(() => repo.remove(friendshipId), 'Gagal membatalkan permintaan'),
        ),
      FriendRelationIncoming(:final friendshipId) => Row(
          children: [
            Expanded(
              child: outlined(
                Icons.close,
                'Tolak',
                () => _act(() => repo.remove(friendshipId), 'Gagal menolak permintaan'),
                color: AppColors.errorRed,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: filled(
                Icons.check,
                'Terima',
                () => _act(() => repo.accept(friendshipId), 'Gagal menerima permintaan'),
              ),
            ),
          ],
        ),
      FriendRelationFriends(:final friendshipId) => outlined(
          Icons.person_remove,
          'Teman · Hapus Teman',
          () => _confirmRemove(friendshipId),
        ),
    };
  }

  Future<void> _confirmRemove(String friendshipId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Hapus teman?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Kalian nggak bisa saling chat private lagi sampai berteman lagi.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _act(() => ref.read(friendRepositoryProvider).remove(friendshipId), 'Gagal menghapus teman');
    }
  }
}
