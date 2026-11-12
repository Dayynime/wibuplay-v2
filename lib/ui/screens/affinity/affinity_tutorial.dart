import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';
import '../../redesign/z_kit.dart';
import 'affinity_fx.dart';

const _seenKey = 'affinity_tutorial_seen_v1';

/// Tampilkan tutorial sekali saja (pertama kali membuka halaman Afinitas).
Future<void> maybeShowAffinityTutorial(BuildContext context) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_seenKey) ?? false) return;
    await p.setBool(_seenKey, true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showAffinityTutorial(context);
}

/// Tutorial Afinitas (bisa dibuka lagi lewat tombol "?").
Future<void> showAffinityTutorial(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => const _TutorialSheet(),
  );
}

class _TutorialSheet extends StatefulWidget {
  const _TutorialSheet();

  @override
  State<_TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<_TutorialSheet> {
  final _pc = PageController();
  int _page = 0;

  static const _count = 6;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int p) {
    HapticFeedback.selectionClick();
    _pc.animateToPage(p, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  Color get _accent => switch (_page) {
        0 => AffinityType.soulmate.color,
        1 => AffinityType.nakama.color,
        2 => AffinityType.kin.color,
        3 => AffinityType.partner.color,
        4 => AffinityType.rival.color,
        _ => AffinityType.senpai.color,
      };

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final last = _page == _count - 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: (h * 0.86).clamp(480.0, 760.0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
        gradient: RadialGradient(
          center: const Alignment(0, -1.25),
          radius: 1.0,
          colors: [_accent.withValues(alpha: 0.22), AppColors.surfaceDark],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Text('${_page + 1} / $_count',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!last)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Lewati', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (p) => setState(() => _page = p),
              children: const [
                _PageIntro(),
                _PageTypes(),
                _PageHow(),
                _PagePoints(),
                _PageLevels(),
                _PageManage(),
              ],
            ),
          ),
          // Titik halaman
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var k = 0; k < _count; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: k == _page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: k == _page ? _accent : const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
            ],
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  if (_page > 0) ...[
                    SizedBox(
                      height: 48,
                      width: 56,
                      child: OutlinedButton(
                        onPressed: () => _go(_page - 1),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: AppColors.textWhite,
                          side: const BorderSide(color: Color(0x26FFFFFF)),
                          shape: const StadiumBorder(),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: last ? () => Navigator.of(context).pop() : () => _go(_page + 1),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet, shape: const StadiumBorder()),
                        child: Text(last ? 'Mulai jalin ikatan' : 'Lanjut',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kerangka satu halaman
// ---------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({required this.hero, required this.jp, required this.title, required this.body, required this.children});

  final Widget hero;
  final String jp;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      children: [
        SizedBox(height: 96, child: Center(child: hero)),
        const SizedBox(height: 14),
        Text(jp, textAlign: TextAlign.center, style: ZFont.jp(size: 11.5, color: AppColors.textSecondary, letterSpacing: 3)),
        const SizedBox(height: 2),
        Text(title, textAlign: TextAlign.center, style: ZFont.display(size: 22, height: 1.2)),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.55),
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.sub, this.trailing, this.color});

  final IconData icon;
  final String title;
  final String? sub;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accentVioletLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x0FFFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w700)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(trailing!, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w800)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 15, color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Apa itu Afinitas
// ---------------------------------------------------------------------------

class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) {
    final red = AffinityType.soulmate.color;
    Widget thread() => Container(
          width: 30,
          height: 2,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, red, Colors.transparent])),
        );
    Widget avatar(Color a, Color b) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: AppColors.surfaceDark, width: 3),
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white70, size: 28),
        );
    return _Page(
      hero: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar(const Color(0xFFE4344A), const Color(0xFF5A1626)),
          thread(),
          const AffinitySeal(type: AffinityType.soulmate, size: 58, delay: Duration(milliseconds: 250), beat: true),
          thread(),
          avatar(const Color(0xFF5B8DEF), const Color(0xFF1B3A8A)),
        ],
      ),
      jp: '絆 · AFINITAS',
      title: 'Ikatan spesial dengan temanmu',
      body: 'Afinitas adalah hubungan khusus antara kamu dan teman, misalnya Soulmate, Nakama, atau Rival. '
          'Ikatannya tampil di profil kalian berdua dan makin kuat kalau kalian sering main bareng.',
      children: const [
        _Row(
          icon: Icons.people_alt_rounded,
          title: 'Cuma dengan teman',
          sub: 'Kalian harus sudah berteman di Zenime dulu.',
        ),
        _Row(
          icon: Icons.handshake_rounded,
          title: 'Harus disetujui',
          sub: 'Ikatan baru aktif setelah temanmu menerima permintaan.',
        ),
        _Row(
          icon: Icons.card_giftcard_rounded,
          title: 'Gratis',
          sub: 'Semua jenis afinitas tidak memakai ZCoin.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Jenis afinitas
// ---------------------------------------------------------------------------

class _PageTypes extends StatelessWidget {
  const _PageTypes();

  @override
  Widget build(BuildContext context) {
    Widget tile(AffinityType t, int i) => Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              AffinitySeal(type: t, size: 34, delay: Duration(milliseconds: 120 + 70 * i)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w800)),
                    Text(t.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget grid(List<AffinityType> ts, int start) => GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.15,
          padding: EdgeInsets.zero,
          children: [for (var i = 0; i < ts.length; i++) tile(ts[i], start + i)],
        );

    return _Page(
      hero: const AffinitySeal(type: AffinityType.nakama, size: 72, delay: Duration(milliseconds: 200)),
      jp: '八つの絆',
      title: '8 jenis ikatan',
      body: 'Pilih jenis yang paling pas dengan hubungan kalian. Tiap jenis punya cap kanji dan warna sendiri.',
      children: [
        const Text('Eksklusif · cuma 1 slot',
            style: TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        grid(const [AffinityType.soulmate, AffinityType.crush, AffinityType.partner, AffinityType.twin], 0),
        const SizedBox(height: 14),
        const Text('Grup · 5 slot',
            style: TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        grid(const [AffinityType.nakama, AffinityType.kin, AffinityType.senpai, AffinityType.rival], 4),
        const SizedBox(height: 8),
        const _Note('Kin dan Senpai · Kouhai punya peran. Kamu pilih jadi Kakak/Adik atau Senpai/Kouhai, '
            'temanmu otomatis dapat peran pasangannya.'),
        const _Note('Satu teman cuma bisa punya 1 jenis afinitas denganmu, tapi jenisnya bisa diganti kapan saja.'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Cara membuat
// ---------------------------------------------------------------------------

class _PageHow extends StatelessWidget {
  const _PageHow();

  @override
  Widget build(BuildContext context) {
    final c = AffinityType.kin.color;
    Widget step(int n, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 1.5)),
                child: Text('$n', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        );
    return _Page(
      hero: const AffinitySeal(type: AffinityType.kin, size: 72, delay: Duration(milliseconds: 200)),
      jp: '絆を結ぶ',
      title: 'Cara membuat ikatan',
      body: 'Ada dua cara: dari halaman Afinitas ini, atau dari profil temanmu.',
      children: [
        step(1, 'Tekan "Tambah afinitas"', 'Di bawah halaman ini. Atau buka profil teman lalu tekan "Ajak Afinitas".'),
        step(2, 'Pilih teman & jenis ikatan', 'Slot yang sudah penuh otomatis redup dan tidak bisa dipilih.'),
        step(3, 'Pilih peran (kalau ada)', 'Untuk Kin dan Senpai · Kouhai. Tambahkan pesan singkat kalau mau.'),
        step(4, 'Tunggu temanmu menerima', 'Dia dapat notifikasi di lonceng. Setelah diterima, ikatan muncul di profil kalian berdua.'),
        const SizedBox(height: 4),
        const _Note('Maksimal 3 permintaan yang menunggu jawaban sekaligus. Lihat & batalkan lewat ikon kotak keluar di kanan atas.'),
        const _Note('Permintaan hangus kalau tidak dijawab dalam 7 hari. Kalau ditolak, kamu bisa minta lagi ke orang yang sama setelah 3 hari.'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Cara menaikkan poin
// ---------------------------------------------------------------------------

class _PagePoints extends StatelessWidget {
  const _PagePoints();

  @override
  Widget build(BuildContext context) {
    final gold = AffinityType.partner.color;
    return _Page(
      hero: const AffinitySeal(type: AffinityType.partner, size: 72, delay: Duration(milliseconds: 200)),
      jp: '絆を深める',
      title: 'Cara menaikkan poin',
      body: 'Poin naik otomatis dari aktivitas berdua. Tidak perlu klaim apa pun.',
      children: [
        _Row(icon: Icons.chat_bubble_rounded, title: 'Chat pribadi', sub: 'Tiap pesan · maks 40 poin/hari', trailing: '+2', color: gold),
        _Row(icon: Icons.grid_on_rounded, title: 'Main catur sampai selesai', sub: 'Minimal 10 langkah · maks 100 poin/hari', trailing: '+20', color: gold),
        _Row(icon: Icons.live_tv_rounded, title: 'Nobar di room yang sama', sub: 'Maks 75 poin/hari', trailing: '+25', color: gold),
        _Row(icon: Icons.redeem_rounded, title: 'Gift Premium di Chat Global', sub: 'Per hari Premium · tanpa batas', trailing: '+50', color: gold),
        _Row(icon: Icons.wb_sunny_rounded, title: 'Sama-sama buka app hari ini', sub: 'Sekali sehari', trailing: '+10', color: gold),
        const SizedBox(height: 6),
        const Text('Bonus x1.5 sesuai jenis',
            style: TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in const [AffinityType.nakama, AffinityType.rival, AffinityType.senpai])
              Container(
                padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                decoration: BoxDecoration(
                  color: t.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AffinitySeal(type: t, size: 20, stamp: false),
                    const SizedBox(width: 6),
                    Text('${t == AffinityType.senpai ? 'Senpai' : t.label} · ${t.bonusHint!.replaceAll('Poin ', '')}',
                        style: const TextStyle(color: AppColors.textWhite, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Level
// ---------------------------------------------------------------------------

class _PageLevels extends StatelessWidget {
  const _PageLevels();

  @override
  Widget build(BuildContext context) {
    final c = AffinityType.rival.color;
    const pts = AffinityLevels.defaultThresholds;
    const meaning = ['Pertemuan', 'Ikatan', 'Percaya', 'Sehati', 'Abadi'];
    return _Page(
      hero: const AffinitySeal(type: AffinityType.rival, size: 72, delay: Duration(milliseconds: 200), clash: true),
      jp: '五つの段階',
      title: '5 tahap level',
      body: 'Makin banyak poin, makin tinggi level ikatan kalian. Level terlihat di cincin warna sekitar avatar.',
      children: [
        for (var k = 0; k < 5; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.alphaBlend(c.withValues(alpha: 0.12 + 0.05 * k), AppColors.surfaceDark),
                    border: Border.all(color: c.withValues(alpha: 0.4 + 0.15 * k), width: 1.5),
                  ),
                  child: Text(AffinityLevels.short[k], style: affinityKanjiStyle(color: c, size: 14)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'Lv ${k + 1} · ${AffinityLevels.names[k]}',
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: '  ${AffinityLevels.jp[k]} · ${meaning[k]}'),
                    ]),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ),
                Text(k == 0 ? 'Awal' : '${_fmt(pts[k])} poin',
                    style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const _Note('Kalau 14 hari tidak berinteraksi, poin turun 2% per hari. Tapi tenang, level yang sudah dicapai tidak bisa turun.'),
        const _Note('Naik level dapat notifikasi dan tercatat sebagai momen di halaman detail ikatan.'),
      ],
    );
  }

  static String _fmt(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}

// ---------------------------------------------------------------------------
// 6. Mengelola ikatan
// ---------------------------------------------------------------------------

class _PageManage extends StatelessWidget {
  const _PageManage();

  @override
  Widget build(BuildContext context) {
    final c = AffinityType.senpai.color;
    return _Page(
      hero: const AffinitySeal(type: AffinityType.senpai, size: 72, delay: Duration(milliseconds: 200)),
      jp: '思い出',
      title: 'Lihat & kelola ikatan',
      body: 'Ketuk avatar siapa pun di halaman Afinitas untuk membuka detail ikatan kalian.',
      children: [
        _Row(icon: Icons.insights_rounded, title: 'Detail ikatan', sub: 'Level, poin, berapa kali catur, nobar, dan chat bareng.', color: c),
        _Row(icon: Icons.auto_awesome_rounded, title: 'Momen', sub: 'Tercatat otomatis: mulai ikatan, naik level, 30/100/365 hari bersama.', color: c),
        _Row(icon: Icons.swap_horiz_rounded, title: 'Ganti jenis', sub: 'Misalnya Crush jadi Soulmate. Poin & level tetap dibawa, tapi perlu disetujui lagi.', color: c),
        _Row(icon: Icons.link_off_rounded, title: 'Putuskan', sub: 'Cukup dari satu pihak. Poin & momen hilang, pihak lain diberi tahu.', color: c),
        const _Note('Kalau pertemanan dihapus, afinitas di antara kalian ikut hilang.'),
        const _Note('Tutorial ini bisa dibuka lagi kapan saja lewat tombol ? di kanan atas.'),
      ],
    );
  }
}
