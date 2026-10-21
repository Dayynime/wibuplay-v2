import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/wallpaper_models.dart';
import '../../../data/repository/wallpaper_repository.dart';
import '../../../providers.dart';
import '../../components/rarity_chip.dart';

const Color _border = Color(0x14FFFFFF);

/// Panel Admin > Wallpaper > Event Limited.
/// Developer, Admin, dan Moderator bisa bikin / ubah / akhiri / hapus event.
/// Semua aturan dicek ULANG di server (wp_event_save dkk).
class AdminWallpaperEventsScreen extends ConsumerStatefulWidget {
  const AdminWallpaperEventsScreen({super.key});

  @override
  ConsumerState<AdminWallpaperEventsScreen> createState() => _AdminWallpaperEventsScreenState();
}

class _AdminWallpaperEventsScreenState extends ConsumerState<AdminWallpaperEventsScreen> {
  AdminEventPage? _page;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  WallpaperRepository get _repo => ref.read(wallpaperRepositoryProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _repo.adminEvents();
      if (!mounted) return;
      setState(() {
        _page = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is WallpaperException ? e.message : 'Gagal memuat event';
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.errorRed : AppColors.surfaceElevated,
      ));
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _snack(ok);
      await _load();
    } catch (e) {
      _snack(e is WallpaperException ? e.message : 'Aksi gagal, coba lagi', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor([AdminWallpaperEvent? event]) async {
    final page = _page;
    if (page == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _EventEditor(page: page, event: event),
      ),
    );
    if (saved == true) {
      _snack(event == null ? 'Event dibuat' : 'Event disimpan');
      _load();
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title, style: const TextStyle(color: AppColors.textWhite, fontSize: 17)),
        content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        title: const Text('Event Limited'),
      ),
      floatingActionButton: p == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.accentViolet,
              foregroundColor: Colors.white,
              onPressed: _busy ? null : () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Event baru'),
            ),
      body: RefreshIndicator(
        color: AppColors.accentViolet,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            const _InfoCard(),
            const SizedBox(height: 14),
            if (_loading && p == null)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
              )
            else if (_error != null && p == null)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: const Text('Muat ulang')),
                  ],
                ),
              )
            else if (p != null && p.events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'Belum ada event. Tekan "Event baru" untuk membuat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else if (p != null)
              for (final e in p.events) _eventTile(p, e),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(AdminEventPage p, AdminWallpaperEvent e) {
    final now = p.serverNow;
    final (label, color) = e.isRunning(now)
        ? ('Berlangsung', AppColors.successGreen)
        : e.isUpcoming(now)
            ? ('Akan datang', AppColors.warningAmber)
            : ('Selesai', AppColors.textMuted);
    final names = {for (final c in p.candidates) c.id: c.name};
    final items = e.wallpaperIds.map((id) => names[id] ?? 'Wallpaper').join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: e.isRunning(now) ? const Color(0x88D7DCE4) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.name,
                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatEventTime(e.startsAt)}  →  ${formatEventTime(e.endsAt)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          if (e.isRunning(now))
            Text(
              'Berakhir dalam ${formatEventCountdown(e.endsAt.difference(now))}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            )
          else if (e.isUpcoming(now))
            Text(
              'Mulai dalam ${formatEventCountdown(e.startsAt.difference(now))}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          const SizedBox(height: 4),
          Text(
            '${e.wallpaperIds.length} wallpaper: $items',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          if (e.creatorName != null)
            Text('oleh ${e.creatorName}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          if (!e.isEnded(now))
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _openEditor(e),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Ubah'),
                ),
                if (e.isRunning(now))
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await _confirm(
                              'Akhiri event?',
                              'Wallpaper Limited "${e.name}" langsung hilang dari Spin, dan pengumuman selesai '
                                  'dikirim ke chat global. Yang sudah dapat tetap memilikinya.',
                              'Akhiri sekarang',
                            )) {
                              return;
                            }
                            await _run(() => _repo.adminEventAction(e.id, 'event_end'), 'Event diakhiri');
                          },
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: const Text('Akhiri sekarang'),
                  ),
                if (e.isUpcoming(now))
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await _confirm('Hapus event?', 'Event "${e.name}" dibatalkan.', 'Hapus')) {
                              return;
                            }
                            await _run(() => _repo.adminEventAction(e.id, 'event_delete'), 'Event dihapus');
                          },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Hapus'),
                  ),
              ],
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: RarityChip(rarity: WallpaperRarity.limited),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Wallpaper Limited cuma bisa didapat dari Spin selama event-nya berjalan. '
                'Saat event mulai dan selesai, pengumuman otomatis muncul di chat global. '
                'Bobot (peluang) wallpaper tetap diatur Admin/Developer saat approve.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      );
}

// ================================================================ editor

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({required this.page, this.event});

  final AdminEventPage page;
  final AdminWallpaperEvent? event;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.event?.name ?? '');
  late DateTime _start;
  late DateTime _end;
  late final Set<String> _picked = {...?widget.event?.wallpaperIds};
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.event == null;
  bool get _running => widget.event?.isRunning(widget.page.serverNow) ?? false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e != null) {
      _start = e.startsAt.toLocal();
      _end = e.endsAt.toLocal();
    } else {
      // default: mulai 1 jam lagi (dibulatkan ke jam), durasi 3 hari
      final n = DateTime.now().add(const Duration(hours: 1));
      _start = DateTime(n.year, n.month, n.day, n.hour);
      _end = _start.add(const Duration(days: 3));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Event lain yang belum selesai & sedang memakai wallpaper ini.
  int? _busyIn(AdminEventCandidate c) {
    final ev = c.eventId;
    if (ev == null || ev == widget.event?.id) return null;
    final now = widget.page.serverNow;
    for (final e in widget.page.events) {
      if (e.id == ev && !e.isEnded(now)) return ev;
    }
    return null;
  }

  String _eventName(int id) {
    for (final e in widget.page.events) {
      if (e.id == id) return e.name;
    }
    return 'lain';
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 120)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  String? _validate() {
    final n = _name.text.trim();
    if (n.isEmpty || n.length > 40) return 'Nama event 1-40 karakter';
    if (_end.difference(_start) < const Duration(minutes: 10)) return 'Jam selesai minimal 10 menit setelah jam mulai';
    if (_end.difference(_start) > const Duration(days: 60)) return 'Event maksimal 60 hari';
    if (!_end.isAfter(DateTime.now())) return 'Jam selesai harus di masa depan';
    if (_picked.isEmpty) return 'Pilih minimal 1 wallpaper Limited';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(wallpaperRepositoryProvider).adminSaveEvent(
            eventId: widget.event?.id,
            name: _name.text.trim(),
            // event berjalan: kirim jam mulai asli dari server apa adanya
            startsAt: _running ? widget.event!.startsAt : _start,
            endsAt: _end,
            wallpaperIds: _picked.toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is WallpaperException ? e.message : 'Gagal menyimpan event';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.page.candidates;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        title: Text(_isNew ? 'Event baru' : 'Ubah event'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 ._!?'()&+:#\-]"))],
            style: const TextStyle(color: AppColors.textWhite),
            decoration: const InputDecoration(labelText: 'Nama event', hintText: 'mis. Halloween 2026'),
          ),
          const SizedBox(height: 4),
          _timeRow(
            label: 'Mulai',
            value: _start,
            locked: _running,
            onTap: () async {
              final v = await _pick(_start);
              if (v == null) return;
              setState(() {
                final dur = _end.difference(_start);
                _start = v;
                if (!_end.isAfter(_start)) _end = _start.add(dur.isNegative ? const Duration(days: 1) : dur);
              });
            },
          ),
          const SizedBox(height: 8),
          _timeRow(
            label: 'Selesai',
            value: _end,
            onTap: () async {
              final v = await _pick(_end);
              if (v != null) setState(() => _end = v);
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Durasi ${formatEventCountdown(_end.difference(_start))}. Jam mengikuti jam HP kamu.'
            '${_running ? ' Event sedang berjalan, jam mulai tidak bisa diubah.' : ''}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Wallpaper Limited',
                  style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text('${_picked.length} dipilih', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          if (candidates.isEmpty)
            const Text(
              'Belum ada wallpaper Limited. Approve atau edit wallpaper dengan rarity Limited dulu di tab Wallpaper.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: candidates.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (_, i) => _candidate(candidates[i]),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _timeRow({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
    bool locked = false,
  }) {
    String two(int v) => v.toString().padLeft(2, '0');
    final text = '${two(value.day)}/${two(value.month)}/${value.year}  ${two(value.hour)}:${two(value.minute)}';
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: locked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(
                label == 'Mulai' ? Icons.play_circle_outline : Icons.stop_circle_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              SizedBox(width: 60, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: locked ? AppColors.textMuted : AppColors.textWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(locked ? Icons.lock_outline : Icons.edit_calendar_outlined, color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _candidate(AdminEventCandidate c) {
    final busyIn = _busyIn(c);
    final selected = _picked.contains(c.id);
    final disabled = busyIn != null;
    return GestureDetector(
      onTap: disabled
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sudah dipakai event "${_eventName(busyIn!)}"')),
              )
          : () => setState(() => selected ? _picked.remove(c.id) : _picked.add(c.id)),
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFFD7DCE4) : _border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (c.previewUrl != null)
                        CachedNetworkImage(
                          imageUrl: c.previewUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariantDark),
                        )
                      else
                        const ColoredBox(color: AppColors.surfaceVariantDark),
                      if (selected)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: Color(0xFFD7DCE4),
                            child: Icon(Icons.check_rounded, size: 15, color: Color(0xFF1C2230)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textWhite, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      disabled ? 'Dipakai event lain' : (c.isActive ? 'bobot ${c.weight}' : 'nonaktif'),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
