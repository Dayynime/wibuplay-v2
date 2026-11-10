import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

// =============================================================================
// Kit tampilan chat (redesain "Gelembung"): dipakai Chat Global, Chat Teman,
// dan Chat Clan supaya bentuknya sama persis. Murni tampilan.
//
//  - Baris pesan: avatar di sisi pengirim (kiri orang lain, kanan milikku),
//    kepala (nama + badge) di atas gelembung, kaki (jam · Balas · Hapus)
//    di bawah. Pesanku tetap lengkap dengan avatar & nama.
//  - Gelembung: sudut 18, sudut dekat avatar 6 (ekor). Milikku biru
//    bergradien, orang lain biru-abu. Kartu (stiker, hadiah, giveaway) tampil
//    tanpa gelembung.
// =============================================================================

/// Gelembung: biru bergradien (milikku) atau biru-abu (orang lain).
class ZChatBubble extends StatelessWidget {
  const ZChatBubble({
    super.key,
    required this.mine,
    required this.child,
    this.highlighted = false,
    this.bare = false,
    this.joinedTop = false,
  });

  final bool mine;
  final Widget child;

  /// Disorot sebentar (lompat dari kutipan balasan).
  final bool highlighted;

  /// Tanpa latar (stiker / kartu hadiah / giveaway / undangan catur).
  final bool bare;

  /// Pesan lanjutan dari orang yang sama: sudut atas tidak berekor.
  final bool joinedTop;

  static const Color others = Color(0xFF13273D);

  @override
  Widget build(BuildContext context) {
    final tail = joinedTop ? const Radius.circular(18) : const Radius.circular(6);
    const r = Radius.circular(18);
    final radius = BorderRadius.only(
      topLeft: mine ? r : tail,
      topRight: mine ? tail : r,
      bottomLeft: r,
      bottomRight: r,
    );
    if (bare) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: highlighted ? AppColors.accentVioletLight : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: child,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: mine ? null : (highlighted ? const Color(0xFF1D3853) : others),
        gradient: mine
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accentViolet, AppColors.accentVioletDark],
              )
            : null,
        border: Border.all(
          color: highlighted ? AppColors.accentVioletLight : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: mine
            ? [
                BoxShadow(
                  color: AppColors.accentViolet.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  spreadRadius: -10,
                ),
              ]
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: mine ? Colors.white : AppColors.textWhite),
        child: child,
      ),
    );
  }
}

/// Kutipan balasan di dalam gelembung.
class ZChatQuote extends StatelessWidget {
  const ZChatQuote({super.key, required this.author, required this.text, required this.mine, this.onTap});

  final String author;
  final String text;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = mine ? Colors.white : AppColors.accentVioletLight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: mine ? 0.18 : 0.24),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mine ? const Color(0xD9FFFFFF) : AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris pesan: avatar + (kepala, gelembung, reaksi, kaki).
class ZChatRow extends StatelessWidget {
  const ZChatRow({
    super.key,
    required this.mine,
    required this.avatar,
    required this.bubble,
    this.header,
    this.below,
    this.footer,
    this.maxBubbleWidth,
    this.compact = false,
  });

  final bool mine;
  final Widget avatar;
  final Widget bubble;

  /// Nama + badge di atas gelembung.
  final Widget? header;

  /// Mis. chip reaksi.
  final Widget? below;

  /// Jam · Balas · Hapus.
  final Widget? footer;
  final double? maxBubbleWidth;

  /// Pesan lanjutan: jarak atas lebih rapat.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final maxW = maxBubbleWidth ?? (screen * 0.72).clamp(200.0, 320.0);
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final column = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: header,
          ),
        ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: bubble),
        if (below != null) below!,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 3),
            child: footer,
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: compact ? 2 : 10, bottom: 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mine
            ? [Flexible(child: column), const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), Flexible(child: column)],
      ),
    );
  }
}

/// Kaki pesan: jam, lalu aksi teks kecil.
class ZChatFooter extends StatelessWidget {
  const ZChatFooter({super.key, required this.time, this.actions = const []});

  final String time;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
        for (final (label, onTap) in actions) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bilah "Membalas X" di atas kolom ketik.
class ZChatReplyBar extends StatelessWidget {
  const ZChatReplyBar({super.key, required this.name, required this.text, required this.onClose});

  final String name;
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 18, color: AppColors.accentVioletLight),
          const SizedBox(width: 8),
          Container(width: 3, height: 30, decoration: BoxDecoration(color: AppColors.accentViolet, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Membalas $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.accentVioletLight, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Batal balas',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Latar bilah kolom ketik (gradien gelap + garis atas tipis).
class ZChatComposer extends StatelessWidget {
  const ZChatComposer({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.backgroundDark, AppColors.backgroundDarkSecondary],
        ),
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: children),
        ),
      ),
    );
  }
}

/// Gaya kolom ketik berbentuk pil.
InputDecoration zChatInputDecoration(String hint) => InputDecoration(
      counterText: '',
      filled: true,
      fillColor: const Color(0xFF13273D),
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0x12FFFFFF)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0x0AFFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: AppColors.accentViolet.withValues(alpha: 0.55)),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
    );

/// Tombol bulat di bilah ketik (kirim / giveaway).
class ZChatRoundButton extends StatelessWidget {
  const ZChatRoundButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color = AppColors.accentViolet,
    this.tooltip,
    this.glow = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Color color;
  final String? tooltip;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? color : AppColors.surfaceElevated,
        boxShadow: enabled && glow
            ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -8)]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(child: child),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}
