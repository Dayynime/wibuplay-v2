import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/voice/chess_voice_call.dart';

const Color _kGreen = Color(0xFF22C55E);
const Color _kRed = Color(0xFFEF4444);

/// Bar panggilan suara di layar catur: telepon lawan, angkat/tolak,
/// mute, speaker, dan tutup. Membangun ulang dirinya sendiri dari [call].
class ChessVoiceBar extends StatelessWidget {
  const ChessVoiceBar({super.key, required this.call, required this.opponentName, required this.tick});

  final ChessVoiceCall call;
  final String opponentName;

  /// Detak 250 ms dari layar catur, untuk durasi panggilan.
  final ValueListenable<int> tick;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([call, tick]),
      builder: (context, _) => _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    final s = call.state;
    final incoming = s == ChessVoiceState.incoming;
    final connected = s == ChessVoiceState.connected;

    String title;
    String? subtitle;
    switch (s) {
      case ChessVoiceState.idle:
        title = 'Ngobrol dengan lawan';
        subtitle = call.notice ?? 'Panggilan suara, mic aktif hanya saat ditelepon';
      case ChessVoiceState.outgoing:
        title = 'Memanggil $opponentName…';
        subtitle = 'Lawan perlu membuka layar catur ini';
      case ChessVoiceState.incoming:
        title = '$opponentName menelepon';
        subtitle = 'Angkat untuk ngobrol sambil main';
      case ChessVoiceState.connecting:
        title = 'Menyambungkan…';
        subtitle = null;
      case ChessVoiceState.connected:
        final at = call.connectedAt;
        final d = at == null ? Duration.zero : DateTime.now().difference(at);
        final mm = d.inMinutes.toString().padLeft(2, '0');
        final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
        title = 'Tersambung · $mm:$ss';
        subtitle = call.remoteMuted ? '$opponentName mematikan mic' : null;
    }

    final accent = incoming || connected ? _kGreen : Colors.white.withValues(alpha: 0.08);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: incoming ? _kGreen.withValues(alpha: 0.12) : AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: incoming || connected ? accent.withValues(alpha: 0.55) : accent),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? (call.muted ? Icons.mic_off_rounded : Icons.graphic_eq_rounded)
                : (incoming ? Icons.ring_volume_rounded : Icons.headset_mic_rounded),
            color: connected || incoming ? _kGreen : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: s == ChessVoiceState.idle && call.notice != null
                          ? AppColors.warningAmber
                          : AppColors.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ..._actions(s),
        ],
      ),
    );
  }

  List<Widget> _actions(ChessVoiceState s) {
    switch (s) {
      case ChessVoiceState.idle:
        return [
          _RoundButton(
            icon: Icons.call_rounded,
            color: _kGreen,
            tooltip: 'Telepon lawan',
            onTap: () => call.start(),
          ),
        ];
      case ChessVoiceState.incoming:
        return [
          _RoundButton(icon: Icons.call_end_rounded, color: _kRed, tooltip: 'Tolak', onTap: call.decline),
          const SizedBox(width: 8),
          _RoundButton(icon: Icons.call_rounded, color: _kGreen, tooltip: 'Angkat', onTap: () => call.accept()),
        ];
      case ChessVoiceState.outgoing:
      case ChessVoiceState.connecting:
        return [
          _RoundButton(icon: Icons.call_end_rounded, color: _kRed, tooltip: 'Tutup', onTap: call.hangUp),
        ];
      case ChessVoiceState.connected:
        return [
          _RoundButton(
            icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: call.muted ? AppColors.textWhite : AppColors.surfaceElevated,
            iconColor: call.muted ? AppColors.backgroundDark : AppColors.textWhite,
            tooltip: call.muted ? 'Nyalakan mic' : 'Matikan mic',
            onTap: call.toggleMute,
          ),
          const SizedBox(width: 6),
          _RoundButton(
            icon: call.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
            color: AppColors.surfaceElevated,
            iconColor: AppColors.textWhite,
            tooltip: call.speakerOn ? 'Pakai earpiece' : 'Pakai speaker',
            onTap: () => call.toggleSpeaker(),
          ),
          const SizedBox(width: 6),
          _RoundButton(icon: Icons.call_end_rounded, color: _kRed, tooltip: 'Tutup', onTap: call.hangUp),
        ];
    }
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}
