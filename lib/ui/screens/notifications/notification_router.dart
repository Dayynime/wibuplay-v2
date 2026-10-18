import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/clan_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../clan/clan_manage_screen.dart';
import '../clan/clan_screen.dart';
import '../friends/friends_screen.dart';

/// Buka halaman tujuan sebuah notifikasi (dari lonceng, banner in-app, atau
/// tap push di status bar). [data] = payload notif (`clan_id`, dll).
Future<void> openNotificationTarget(
  WidgetRef ref,
  String type,
  Map<String, dynamic> data,
) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  final clanId = data['clan_id']?.toString() ?? '';

  switch (type) {
    case 'friend_request':
    case 'friend_accepted':
      await nav.push<void>(fadeRoute(const FriendsScreen()));
      ref.invalidate(incomingFriendRequestsProvider);
      return;

    case 'clan_join_request':
      if (clanId.isEmpty) return;
      // Masih Officer ke atas di clan itu -> langsung ke Kelola (tab Request).
      final uid = ref.read(authRepositoryProvider).currentUser?.uid ?? '';
      ClanMember? me;
      try {
        me = uid.isEmpty ? null : await ref.read(clanRepositoryProvider).getMyMembership(uid);
      } catch (_) {}
      final role = (me != null && me.clanId == clanId) ? me.role : null;
      await nav.push<void>(fadeRoute(
        (role != null && ClanRoles.canManageClan(role))
            ? ClanManageScreen(clanId: clanId, myRole: role)
            : ClanScreen(clanId: clanId),
      ));
      return;

    case 'clan_joined':
      if (clanId.isEmpty) return;
      await nav.push<void>(fadeRoute(ClanScreen(clanId: clanId)));
      return;
  }
}

/// Ikon per jenis notif (dipakai kalau notif tidak punya foto pelaku).
IconData notificationIcon(String type) => switch (type) {
      'friend_request' => Icons.person_add_alt_1_rounded,
      'friend_accepted' => Icons.how_to_reg_rounded,
      'clan_join_request' => Icons.group_add_rounded,
      'clan_joined' => Icons.shield_rounded,
      _ => Icons.notifications_rounded,
    };
