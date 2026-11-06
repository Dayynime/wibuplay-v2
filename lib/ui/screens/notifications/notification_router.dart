import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/clan_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../clan/clan_access_widgets.dart';
import '../clan/clan_manage_screen.dart';
import '../clan/clan_screen.dart';
import '../friends/friends_screen.dart';
import '../feed/feed_screen.dart';
import '../nobar/nobar_invite.dart';
import '../sticker/sticker_upload_screen.dart';
import '../chat/chat_screen.dart';

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
    case 'feed_comment':
      final postId = int.tryParse(data['post_id']?.toString() ?? '');
      if (postId == null) return;
      await nav.push<void>(fadeRoute(FeedPostScreen(postId: postId)));
      return;

    case 'chat_mention':
      // Chat Clan = tab 2, Chat Global = tab 0.
      final tab = data['channel']?.toString() == 'clan' ? 2 : 0;
      await nav.push<void>(fadeRoute(ChatScreen(initialTab: tab)));
      return;

    case 'private_message':
      final sender = data['sender_uid']?.toString();
      await nav.push<void>(fadeRoute(ChatScreen(initialTab: 1, openPeerUid: sender)));
      return;

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

    case 'nobar_invite':
      await handleNobarInviteNotification(ref, data);
      return;

    case 'clan_invite':
      await handleClanInviteNotification(ref, data);
      return;

    case 'sticker_reviewed':
      ref.invalidate(stickerCatalogProvider);
      await nav.push<void>(fadeRoute(const StickerUploadScreen()));
      return;
  }
}

/// Ikon per jenis notif (dipakai kalau notif tidak punya foto pelaku).
IconData notificationIcon(String type) => switch (type) {
      'friend_request' => Icons.person_add_alt_1_rounded,
      'friend_accepted' => Icons.how_to_reg_rounded,
      'clan_join_request' => Icons.group_add_rounded,
      'clan_joined' => Icons.shield_rounded,
      'clan_invite' => Icons.mail_rounded,
      'sticker_reviewed' => Icons.emoji_emotions_rounded,
      'private_message' => Icons.chat_bubble_rounded,
      'nobar_invite' => Icons.groups_rounded,
      'nobar_declined' => Icons.group_off_rounded,
      _ => Icons.notifications_rounded,
    };
