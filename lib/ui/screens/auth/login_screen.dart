import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repository/auth_repository.dart';
import '../../../providers.dart';

enum _Mode { signIn, signUp }

/// Layar login. Memakai akun Zenime (Firebase project yang sama): Google atau
/// email + password (email wajib diverifikasi). Menutup diri dengan `true`
/// kalau login berhasil. Login bersifat opsional: hanya dibutuhkan untuk Chat.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _messageIsError = true;
  bool _showResend = false;

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _showResend = false;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _messageIsError = true;
        _showResend = e.needsVerification;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Terjadi kesalahan, coba lagi.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _google() => _run(() async {
        await _auth.signInWithGoogle();
        _done();
      });

  Future<void> _submit() => _run(() async {
        final email = _email.text.trim();
        final password = _password.text;
        if (email.isEmpty || password.isEmpty) {
          throw const AuthFailure('Email dan password wajib diisi.');
        }
        if (_mode == _Mode.signUp) {
          await _auth.signUpWithEmail(_username.text, email, password);
          if (!mounted) return;
          setState(() {
            _mode = _Mode.signIn;
            _message = 'Berhasil daftar! Cek email $email untuk verifikasi, baru bisa masuk.';
            _messageIsError = false;
          });
        } else {
          await _auth.signInWithEmail(email, password);
          _done();
        }
      });

  Future<void> _resend() => _run(() async {
        await _auth.resendVerificationEmail(_email.text, _password.text);
        if (!mounted) return;
        setState(() {
          _message = 'Email verifikasi dikirim ulang, cek inbox kamu.';
          _messageIsError = false;
        });
      });

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surfaceDark,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      border: OutlineInputBorder(borderRadius: AppShapes.card, borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: AppShapes.card, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShapes.card,
        borderSide: const BorderSide(color: AppColors.accentViolet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signUp = _mode == _Mode.signUp;
    final ready = FirebaseConfig.ready;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        title: Text(signUp ? 'Daftar' : 'Masuk'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset('assets/images/logo.jpg', width: 72, height: 72),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Masuk dengan akun Zenime',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Akun yang sama dipakai di semua versi Zenime, jadi chat dan datamu nyambung.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 22),
            if (!ready)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: AppShapes.card,
                ),
                child: const Text(
                  'Login belum dikonfigurasi. Isi apiKey dan appId Firebase untuk Zenime '
                  'di lib/core/firebase_config.dart (lihat panduan setup).',
                  style: TextStyle(color: AppColors.warningAmber, fontSize: 12),
                ),
              ),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: (_busy || !ready) ? null : _google,
                icon: const Icon(Icons.account_circle_outlined, size: 20),
                label: const Text('Masuk dengan Google'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textWhite,
                  side: const BorderSide(color: AppColors.surfaceElevated),
                  shape: RoundedRectangleBorder(borderRadius: AppShapes.pill),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(child: Divider(color: AppColors.surfaceElevated)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('atau pakai email',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ),
                Expanded(child: Divider(color: AppColors.surfaceElevated)),
              ],
            ),
            const SizedBox(height: 16),
            if (signUp) ...[
              TextField(
                controller: _username,
                enabled: !_busy,
                style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                cursorColor: AppColors.accentViolet,
                textInputAction: TextInputAction.next,
                decoration: _decoration('Username', Icons.person_outline),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
              cursorColor: AppColors.accentViolet,
              textInputAction: TextInputAction.next,
              decoration: _decoration('Email', Icons.mail_outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
              cursorColor: AppColors.accentViolet,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => ready ? _submit() : null,
              decoration: _decoration(
                'Password',
                Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError ? AppColors.errorRed : AppColors.successGreen,
                  fontSize: 12,
                ),
              ),
            ],
            if (_showResend)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Kirim ulang email verifikasi'),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: (_busy || !ready) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                  foregroundColor: AppColors.textWhite,
                  shape: RoundedRectangleBorder(borderRadius: AppShapes.pill),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textWhite,
                        ),
                      )
                    : Text(signUp ? 'Daftar' : 'Masuk'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _mode = signUp ? _Mode.signIn : _Mode.signUp;
                        _message = null;
                        _showResend = false;
                      }),
              child: Text(signUp ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar'),
            ),
          ],
        ),
      ),
    );
  }
}
