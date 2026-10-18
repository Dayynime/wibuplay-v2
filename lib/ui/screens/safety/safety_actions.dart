import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/build_flags.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repository/safety_repository.dart';
import '../../../providers.dart';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String _errText(Object e) => e.toString().replaceFirst('Exception: ', '');

/// Sheet laporan: pilih alasan, catatan opsional, lalu kirim.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetUid,
  required String targetName,
  required ReportChannel channel,
  int? messageId,
  String? messageText,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReportSheet(
      targetUid: targetUid,
      targetName: targetName,
      channel: channel,
      messageId: messageId,
      messageText: messageText,
    ),
  );
  if (sent == true && context.mounted) {
    _toast(context, 'Laporan terkirim. Terima kasih, tim kami akan meninjaunya.');
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.targetUid,
    required this.targetName,
    required this.channel,
    this.messageId,
    this.messageText,
  });

  final String targetUid;
  final String targetName;
  final ReportChannel channel;
  final int? messageId;
  final String? messageText;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  final TextEditingController _note = TextEditingController();
  bool _sending = false;
  bool _alsoBlock = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(safetyRepositoryProvider).report(
            targetUid: widget.targetUid,
            channel: widget.channel,
            reason: reason,
            messageId: widget.messageId,
            messageText: widget.messageText,
            note: _note.text,
          );
      if (_alsoBlock) {
        await ref.read(blockedUsersProvider.notifier).block(widget.targetUid);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = _errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMessage = widget.messageId != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMessage ? 'Laporkan pesan' : 'Laporkan ${widget.targetName}',
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isMessage
                    ? 'Pesan dari ${widget.targetName} akan dikirim ke tim moderasi.'
                    : 'Laporan akan ditinjau oleh tim moderasi.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              if (isMessage && (widget.messageText ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.messageText!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final r in ReportReason.values)
                RadioListTile<ReportReason>(
                  value: r,
                  groupValue: _reason,
                  onChanged: _sending ? null : (v) => setState(() => _reason = v),
                  activeColor: AppColors.accentViolet,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(r.label, style: const TextStyle(color: AppColors.textWhite)),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                enabled: !_sending,
                maxLength: 300,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(color: AppColors.textWhite),
                decoration: const InputDecoration(
                  hintText: 'Keterangan tambahan (opsional)',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                ),
              ),
              CheckboxListTile(
                value: _alsoBlock,
                onChanged: _sending ? null : (v) => setState(() => _alsoBlock = v ?? false),
                activeColor: AppColors.accentViolet,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Blokir ${widget.targetName} juga',
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_reason == null || _sending) ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Kirim laporan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Konfirmasi lalu blokir. Mengembalikan true kalau berhasil diblokir.
Future<bool> confirmBlockUser(
  BuildContext context,
  WidgetRef ref, {
  required String uid,
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: Text('Blokir $name?', style: const TextStyle(color: AppColors.textWhite)),
      content: const Text(
        'Pesannya tidak akan tampil lagi di Chat Global, dan kalian tidak bisa '
        'saling mengirim pesan pribadi. Kamu bisa membuka blokir kapan saja di '
        'Pengaturan > Pengguna Diblokir.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Blokir', style: TextStyle(color: AppColors.errorRed)),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(blockedUsersProvider.notifier).block(uid);
    if (context.mounted) _toast(context, '$name diblokir');
    return true;
  } catch (e) {
    if (context.mounted) _toast(context, _errText(e));
    return false;
  }
}

/// Alur hapus akun dari dalam aplikasi (wajib untuk Google Play).
Future<void> startDeleteAccount(BuildContext context, WidgetRef ref) async {
  final reasonCtl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: const Text('Hapus akun?', style: TextStyle(color: AppColors.textWhite)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Akun dan datamu akan dihapus permanen paling lambat 7 hari kerja, '
              'termasuk profil, pesan chat, keanggotaan clan, favorit, riwayat, '
              'status Premium, dan saldo ZCoin. Tindakan ini tidak bisa dibatalkan '
              'setelah diproses.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtl,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: AppColors.textWhite),
              decoration: const InputDecoration(
                hintText: 'Alasan (opsional)',
                hintStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(BuildFlags.deleteAccountUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Data apa saja yang dihapus?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Hapus akun', style: TextStyle(color: AppColors.errorRed)),
        ),
      ],
    ),
  );
  // Controller tidak di-dispose di sini: dialog masih beranimasi keluar.
  final reason = reasonCtl.text;
  if (ok != true || !context.mounted) return;

  try {
    await ref.read(safetyRepositoryProvider).requestAccountDeletion(reason: reason);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Permintaan diterima', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Akunmu dijadwalkan untuk dihapus. Kamu akan dikeluarkan dari aplikasi '
          'sekarang. Kalau berubah pikiran, hubungi zenimeapp@proton.me sebelum '
          'penghapusan diproses.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    await ref.read(authRepositoryProvider).signOut();
  } catch (e) {
    if (context.mounted) _toast(context, _errText(e));
  }
}

/// Daftar pengguna yang diblokir, dengan tombol buka blokir.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  late Future<List<BlockedUser>> _future = _load();

  Future<List<BlockedUser>> _load() => ref.read(safetyRepositoryProvider).listBlocks();

  Future<void> _unblock(BlockedUser u) async {
    try {
      await ref.read(blockedUsersProvider.notifier).unblock(u.uid);
      if (!mounted) return;
      _toast(context, '${u.username ?? 'Pengguna'} tidak diblokir lagi');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) _toast(context, _errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        title: const Text('Pengguna Diblokir'),
      ),
      body: FutureBuilder<List<BlockedUser>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_errText(snap.error!),
                      style: const TextStyle(color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            );
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Kamu belum memblokir siapa pun.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
            itemBuilder: (context, i) {
              final u = list[i];
              final name = (u.username ?? '').isEmpty ? 'Pengguna' : u.username!;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.surfaceDark,
                  backgroundImage:
                      (u.avatarUrl ?? '').isEmpty ? null : NetworkImage(u.avatarUrl!),
                  child: (u.avatarUrl ?? '').isEmpty
                      ? Text(name.characters.first.toUpperCase(),
                          style: const TextStyle(color: AppColors.textWhite))
                      : null,
                ),
                title: Text(name, style: const TextStyle(color: AppColors.textWhite)),
                trailing: TextButton(
                  onPressed: () => _unblock(u),
                  child: const Text('Buka blokir'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
