import 'dart:ui' show FontFeature;

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

/// Posisi pesan dalam satu rombongan (pesan beruntun dari orang yang sama).
enum ZGroupPos { single, first, mid, last }

extension ZGroupPosX on ZGroupPos {
  /// Pesan pertama rombongan: tampilkan avatar + nama + badge.
  bool get isHead => this == ZGroupPos.single || this == ZGroupPos.first;
}

/// Hitung posisi dari tetangga: [olderSame] = pesan sebelumnya (lebih lama)
/// dari orang yang sama dan masih dekat waktunya; [newerSame] sebaliknya.
ZGroupPos zGroupPos({required bool olderSame, required bool newerSame}) {
  if (olderSame && newerSame) return ZGroupPos.mid;
  if (olderSame) return ZGroupPos.last;
  if (newerSame) return ZGroupPos.first;
  return ZGroupPos.single;
}

/// Dua pesan satu rombongan kalau pengirimnya sama dan jaraknya <= 3 menit.
bool zSameGroup(String uidA, DateTime? a, String uidB, DateTime? b) {
  if (uidA.isEmpty || uidA != uidB || a == null || b == null) return false;
  return a.difference(b).inSeconds.abs() <= 180;
}

/// Gelembung: biru bergradien (milikku) atau biru-abu (orang lain).
class ZChatBubble extends StatelessWidget {
  const ZChatBubble({
    super.key,
    required this.mine,
    required this.child,
    this.highlighted = false,
    this.bare = false,
    this.joinedTop = false,
    this.pos = ZGroupPos.single,
    this.time,
  });

  final bool mine;
  final Widget child;

  /// Posisi dalam rombongan: menentukan sudut yang menyambung.
  final ZGroupPos pos;

  /// Jam kecil di pojok kanan bawah (di dalam gelembung / di atas kartu).
  final String? time;

  /// Disorot sebentar (lompat dari kutipan balasan).
  final bool highlighted;

  /// Tanpa latar (stiker / kartu hadiah / giveaway / undangan catur).
  final bool bare;

  /// Pesan lanjutan dari orang yang sama: sudut atas tidak berekor.
  final bool joinedTop;

  static const Color others = Color(0xFF1C222E);

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(18);
    const t = Radius.circular(6);
    // Sisi avatar: atas berekor (6); kalau ada pesan sesudahnya, bawah juga 6
    // supaya gelembung terlihat menyambung.
    final topSide = joinedTop && pos == ZGroupPos.single ? r : t;
    final bottomSide = pos == ZGroupPos.first || pos == ZGroupPos.mid ? t : r;
    final radius = BorderRadius.only(
      topLeft: mine ? r : topSide,
      topRight: mine ? topSide : r,
      bottomLeft: mine ? r : bottomSide,
      bottomRight: mine ? bottomSide : r,
    );
    final timeText = time == null
        ? null
        : Text(
            time!,
            style: TextStyle(
              color: mine ? const Color(0xBFFFFFFF) : AppColors.textMuted,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
        child: time == null
            ? child
            : Stack(
                children: [
                  child,
                  // Jam ditempel di pojok kartu / stiker.
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xA60B0E14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        time!,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(12, 8, 11, 7),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: mine ? null : (highlighted ? const Color(0xFF262D3B) : others),
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
        // Jam satu baris dengan teks kalau muat, kalau tidak turun ke kanan.
        child: timeText == null
            ? child
            : Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  child,
                  Padding(padding: const EdgeInsets.only(bottom: 1), child: timeText),
                ],
              ),
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
    this.pos = ZGroupPos.single,
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

  /// Posisi dalam rombongan: kepala menampilkan avatar & kepala pesan,
  /// lanjutan hanya gelembung (avatar diganti ruang kosong).
  final ZGroupPos pos;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final maxW = maxBubbleWidth ?? (screen * 0.72).clamp(200.0, 320.0);
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final head = pos.isHead;
    final column = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null && head)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: header,
          ),
        ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: bubble),
        // Reaksi menempel di tepi bawah gelembung.
        if (below != null)
          Transform.translate(
            offset: const Offset(0, -5),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: below),
          ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 3),
            child: footer,
          ),
      ],
    );
    // Lanjutan rombongan: avatar tidak diulang, cukup ruang selebar avatar.
    final side = head ? RepaintBoundary(child: avatar) : const SizedBox(width: 36);
    return Padding(
      padding: EdgeInsets.only(top: compact || !head ? 3 : 12, bottom: 0),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mine
            // Border avatar animasi di lapisan sendiri: gelembung & badge
            // tidak ikut digambar ulang tiap frame border berganti.
            ? [Flexible(child: column), const SizedBox(width: 8), side]
            : [side, const SizedBox(width: 8), Flexible(child: column)],
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
      fillColor: const Color(0xFF1C222E),
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


/// Kepala pesan: baris nama (nama, centang, #ID) + satu baris badge yang
/// tidak pernah turun ke baris baru (kelebihan terpotong rapi).
class ZChatHeader extends StatelessWidget {
  const ZChatHeader({super.key, required this.mine, required this.nameRow, this.badges = const []});

  final bool mine;
  final List<Widget> nameRow;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final align = mine ? MainAxisAlignment.end : MainAxisAlignment.start;
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: align, children: nameRow),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 3),
          LayoutBuilder(
            builder: (context, c) => ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth.isFinite ? c.maxWidth : 0),
                  child: Row(
                    mainAxisAlignment: align,
                    children: [
                      for (var i = 0; i < badges.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        badges[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
