import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/nobar_models.dart';
import '../../../data/voice/nobar_voice.dart';
import '../../components/friend_avatar.dart';

const Color _kGreen = Color(0xFF22C55E);
const Color _kRed = Color(0xFFEF4444);
const Color _kGold = Color(0xFFF5B301);

/// Panel voice chat ala Mobile Legends: 5 slot anggota (lingkaran hijau saat
/// ngomong), tombol mic, speaker, bisukan semua, dan kontrol host.
class NobarVoicePanel extends StatelessWidget {
  const NobarVoicePanel({
    super.key,
    required this.room,
    required this.voice,
    required this.myUid,
    required this.onKick,
    required this.onInvite,
  });

  final NobarRoom room;
  final NobarVoice voice;
  final String myUid;
  final Future<void> Function(NobarMember m) onKick;
  final VoidCallback onInvite;

  bool get _iAmHost => room.isHost(myUid);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final slots = room.maxMembers;
        final members = room.members;
        final others = members.where((m) => m.uid != myUid).toList();
        final linked = others.where((m) => voice.peer(m.uid).connected).length;

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.headset_mic_rounded, color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Voice Chat',
                    style: TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    !voice.started
                        ? 'Menyambungkan…'
                        : others.isEmpty
                            ? 'Menunggu teman'
                            : '$linked/${others.length} tersambung',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < slots; i++)
                    Expanded(
                      child: i < members.length
                          ? _MemberSlot(
                              member: members[i],
                              isMe: members[i].uid == myUid,
                              isHost: members[i].uid == room.hostUid,
                              voice: voice,
                              onTap: members[i].uid == myUid ? null : () => _memberSheet(context, members[i]),
                            )
                          : _EmptySlot(onTap: onInvite),
                    ),
                ],
              ),
              if (voice.notice != null) ...[
                const SizedBox(height: 10),
                Text(voice.notice!, style: const TextStyle(color: AppColors.warningAmber, fontSize: 12)),
              ] else if (voice.micOn && voice.speakerOn) ...[
                const SizedBox(height: 10),
                const Text(
                  'Tips: pakai earphone biar suara anime nggak ikut masuk ke mic.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _MicButton(voice: voice)),
                  const SizedBox(width: 8),
                  _SquareButton(
                    icon: voice.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                    label: voice.speakerOn ? 'Speaker' : 'Earpiece',
                    onTap: voice.toggleSpeaker,
                  ),
                  const SizedBox(width: 8),
                  _SquareButton(
                    icon: voice.muteAll ? Icons.headset_off_rounded : Icons.headset_rounded,
                    label: voice.muteAll ? 'Dibisukan' : 'Dengar',
                    active: voice.muteAll,
                    onTap: () => voice.setMuteAll(!voice.muteAll),
                  ),
                  if (_iAmHost) ...[
                    const SizedBox(width: 8),
                    _SquareButton(
                      icon: Icons.mic_external_off_rounded,
                      label: 'Mute all',
                      onTap: () {
                        voice.forceMute(null);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(content: Text('Mic semua anggota dimatikan')));
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _memberSheet(BuildContext context, NobarMember m) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListenableBuilder(
        listenable: voice,
        builder: (ctx, _) {
          final pv = voice.peer(m.uid);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FriendAvatar(url: m.avatarUrl, seed: m.uid, label: m.username, size: 56, framed: false),
                  const SizedBox(height: 8),
                  Text(
                    m.username,
                    style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (m.uid == room.hostUid) 'Host',
                      pv.micOn ? 'Mic nyala' : 'Mic mati',
                      if (!pv.connected) 'belum tersambung',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(
                      pv.mutedByMe ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: AppColors.textWhite,
                    ),
                    title: Text(
                      pv.mutedByMe ? 'Bunyikan lagi' : 'Bisukan',
                      style: const TextStyle(color: AppColors.textWhite),
                    ),
                    subtitle: const Text(
                      'Cuma di HP kamu, dia tidak tahu',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    onTap: () => voice.toggleMuteFor(m.uid),
                  ),
                  if (_iAmHost) ...[
                    ListTile(
                      enabled: pv.micOn,
                      leading: const Icon(Icons.mic_off_rounded, color: AppColors.textWhite),
                      title: const Text('Matikan mic-nya', style: TextStyle(color: AppColors.textWhite)),
                      subtitle: const Text(
                        'Dia masih bisa menyalakannya lagi',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      onTap: () {
                        voice.forceMute(m.uid);
                        Navigator.pop(ctx);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_remove_rounded, color: _kRed),
                      title: const Text('Keluarkan dari room', style: TextStyle(color: _kRed)),
                      subtitle: const Text(
                        'Tidak bisa masuk lagi ke room ini',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onKick(m);
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MemberSlot extends StatelessWidget {
  const _MemberSlot({
    required this.member,
    required this.isMe,
    required this.isHost,
    required this.voice,
    this.onTap,
  });

  final NobarMember member;
  final bool isMe;
  final bool isHost;
  final NobarVoice voice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pv = voice.peer(member.uid);
    final micOn = isMe ? voice.micOn : pv.micOn;
    final speaking = isMe ? (voice.micOn && voice.meSpeaking) : pv.speaking;
    final mutedByMe = !isMe && voice.isMutedByMe(member.uid);
    final faded = !member.active || (!isMe && !pv.connected && voice.started);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: faded ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: speaking ? _kGreen : Colors.white.withValues(alpha: 0.08),
                          width: speaking ? 3 : 2,
                        ),
                        boxShadow: speaking
                            ? [BoxShadow(color: _kGreen.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: 1)]
                            : null,
                      ),
                    ),
                    FriendAvatar(
                      url: member.avatarUrl,
                      seed: member.uid,
                      label: member.username,
                      size: 48,
                      framed: false,
                    ),
                    if (isHost)
                      const Positioned(
                        top: -6,
                        child: Icon(Icons.workspace_premium_rounded, color: _kGold, size: 18),
                      ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: mutedByMe ? AppColors.surfaceElevated : (micOn ? _kGreen : _kRed),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surfaceCard, width: 2),
                        ),
                        child: Icon(
                          mutedByMe
                              ? Icons.volume_off_rounded
                              : (micOn ? Icons.mic_rounded : Icons.mic_off_rounded),
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isMe ? 'Kamu' : member.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isMe ? AppColors.textWhite : AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(Icons.add_rounded, color: Colors.white.withValues(alpha: 0.35)),
            ),
            const SizedBox(height: 6),
            const Text('Undang', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.voice});

  final NobarVoice voice;

  @override
  Widget build(BuildContext context) {
    final on = voice.micOn;
    final busy = voice.micBusy || !voice.started;
    return Material(
      color: on ? _kGreen : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : voice.toggleMic,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (voice.micBusy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              else
                Icon(on ? Icons.mic_rounded : Icons.mic_off_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                on ? 'Mic ON' : 'Mic OFF',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.textWhite : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 60,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: active ? AppColors.backgroundDark : AppColors.textWhite),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? AppColors.backgroundDark : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Versi ringkas untuk mode layar penuh: avatar yang sedang ngomong + tombol mic.
class NobarMiniVoice extends StatelessWidget {
  const NobarMiniVoice({super.key, required this.room, required this.voice, required this.myUid});

  final NobarRoom room;
  final NobarVoice voice;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final speaking = room.members
            .where((m) => m.uid == myUid ? (voice.micOn && voice.meSpeaking) : voice.peer(m.uid).speaking)
            .toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final m in speaking)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kGreen.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FriendAvatar(url: m.avatarUrl, seed: m.uid, label: m.username, size: 22, framed: false),
                      const SizedBox(width: 6),
                      Text(
                        m.uid == myUid ? 'Kamu' : m.username,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.graphic_eq_rounded, color: _kGreen, size: 14),
                    ],
                  ),
                ),
              ),
            Material(
              color: voice.micOn ? _kGreen : Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: voice.micBusy || !voice.started ? null : voice.toggleMic,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    voice.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
