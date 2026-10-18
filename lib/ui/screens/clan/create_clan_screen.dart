import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/clan_photo_uploader.dart';
import '../../../data/repository/clan_repository.dart';
import '../../../providers.dart';
import 'clan_widgets.dart';

/// Biaya bikin clan (ZCoin), sama dengan Zenime (CREATE_CLAN_COST).
const int createClanCost = 2500;

/// Buat Clan: foto (opsional), nama 3-30 karakter, tag 3-4 huruf/angka.
/// Port CreateClanScreen.kt. Pop dengan clanId kalau berhasil.
class CreateClanScreen extends ConsumerStatefulWidget {
  const CreateClanScreen({super.key, required this.firebaseUid});

  final String firebaseUid;

  @override
  ConsumerState<CreateClanScreen> createState() => _CreateClanScreenState();
}

class _CreateClanScreenState extends ConsumerState<CreateClanScreen> {
  final _nameCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _picker = ImagePicker();

  String? _photoPath;
  bool _uploading = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  bool get _nameValid {
    final n = _nameCtrl.text.trim().length;
    return n >= 3 && n <= 30;
  }

  bool get _tagValid => RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(_tagCtrl.text.trim().toUpperCase());

  Future<void> _pickPhoto() async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (f != null) setState(() => _photoPath = f.path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal membuka galeri');
    }
  }

  Future<void> _submit(int balance) async {
    if (_submitting || _uploading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    String? photoUrl;
    final path = _photoPath;
    if (path != null) {
      setState(() => _uploading = true);
      try {
        photoUrl = await ClanPhotoUploader.uploadClanPhoto(
          path,
          '${widget.firebaseUid}-${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            _uploading = false;
            _submitting = false;
            _error = 'Gagal upload foto. Periksa koneksi lalu coba lagi.';
          });
        }
        return;
      }
      if (mounted) setState(() => _uploading = false);
    }

    try {
      final clan = await ref.read(clanRepositoryProvider).createClan(
            name: _nameCtrl.text.trim(),
            tag: _tagCtrl.text.trim().toUpperCase(),
            photoUrl: photoUrl,
          );
      ref.invalidate(coinBalanceProvider(widget.firebaseUid));
      if (mounted) Navigator.of(context).pop(clan.id);
    } on ClanException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal bikin clan');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label, String hint, String helper, {bool error = false}) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      counterText: '',
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      helperStyle: TextStyle(color: error ? AppColors.errorRed : AppColors.textMuted),
      filled: true,
      fillColor: clanSurface,
      enabledBorder: border(error ? AppColors.errorRed : clanBorder),
      focusedBorder: border(error ? AppColors.errorRed : AppColors.accentViolet),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(coinBalanceProvider(widget.firebaseUid));
    final loadingBalance = balanceAsync.isLoading;
    final balance = balanceAsync.valueOrNull ?? 0;
    final canAfford = balance >= createClanCost;
    final canSubmit = _nameValid && _tagValid && canAfford && !_submitting && !_uploading;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Text('Buat Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Foto clan
            Center(
              child: GestureDetector(
                onTap: _submitting ? null : _pickPhoto,
                child: Container(
                  width: 96,
                  height: 96,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: clanSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: clanBorder),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_photoPath != null)
                        Image.file(File(_photoPath!), fit: BoxFit.cover)
                      else
                        const Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 32),
                      if (_uploading)
                        const ColoredBox(
                          color: Color(0x80000000),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Opsional, ketuk untuk pilih foto',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtrl,
              maxLength: 30,
              onChanged: (_) => setState(() => _error = null),
              style: const TextStyle(color: Colors.white),
              cursorColor: AppColors.accentViolet,
              decoration: _decoration(
                'Nama Clan',
                'Contoh: Octagram',
                _nameCtrl.text.isNotEmpty && !_nameValid ? 'Nama 3-30 karakter' : '3-30 karakter',
                error: _nameCtrl.text.isNotEmpty && !_nameValid,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagCtrl,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                TextInputFormatter.withFunction(
                  (o, n) => n.copyWith(text: n.text.toUpperCase()),
                ),
              ],
              onChanged: (_) => setState(() => _error = null),
              style: const TextStyle(color: Colors.white),
              cursorColor: AppColors.accentViolet,
              decoration: _decoration(
                'Tag (singkatan)',
                'Contoh: OCT',
                _tagCtrl.text.isNotEmpty && !_tagValid
                    ? 'Harus 3-4 huruf/angka'
                    : '3-4 karakter, jadi identitas singkat clan',
                error: _tagCtrl.text.isNotEmpty && !_tagValid,
              ),
            ),
            const SizedBox(height: 24),
            // Biaya + saldo
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: clanSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: clanBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Biaya bikin clan',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 4),
                      const Text(
                        '$createClanCost ZCoin',
                        style: TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Saldo kamu',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 4),
                      if (loadingBalance)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentViolet),
                        )
                      else
                        Text(
                          '$balance ZCoin',
                          style: TextStyle(
                            color: canAfford ? AppColors.textWhite : AppColors.errorRed,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!loadingBalance && !canAfford) ...[
              const SizedBox(height: 8),
              const Text(
                'Saldo ZCoin kamu kurang buat bikin clan. Top up dulu ya.',
                style: TextStyle(color: AppColors.errorRed, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            ClanGradientButton(
              text: 'Buat Clan',
              icon: Icons.group_add_rounded,
              loading: _submitting,
              onTap: canSubmit ? () => _submit(balance) : null,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
