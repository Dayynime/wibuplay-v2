import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repository/auth_repository.dart';
import '../../../providers.dart';
import 'login_posters.dart';

enum _Mode { signIn, signUp }

/// Layar login Wibuplay (gerbang wajib login lewat AuthGate).
///
/// Konsep: tiga rel poster yang bergulir pelan berlawanan arah, disapu cahaya
/// aurora ungu, dengan panel kaca (glassmorphism) yang naik dari bawah. Form
/// email membuka di panel yang sama (tanpa pindah layar), tinggi panel
/// beranimasi halus.
///
/// Memakai akun Zenime (Firebase project yang sama): Google atau email +
/// password (email wajib diverifikasi). Kalau dibuka lewat push (mis. dari
/// Profil) layar menutup dengan `true` saat berhasil; kalau dipakai sebagai
/// gerbang, AuthGate yang mengganti layar otomatis.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  // Loop panjang (poster + aurora), intro sekali jalan, kilau tombol Google.
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 80))
        ..repeat();
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
        ..forward();
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))
        ..repeat();

  late final Animation<double> _wallIn = _iv(0.0, 0.55, Curves.easeOut);
  late final Animation<double> _logoIn = _iv(0.12, 0.5);
  late final Animation<double> _panelIn = _iv(0.2, 0.7);
  late final Animation<double> _titleIn = _iv(0.45, 0.8);
  late final Animation<double> _subIn = _iv(0.55, 0.88);
  late final Animation<double> _btnIn = _iv(0.65, 1.0);

  _Mode _mode = _Mode.signIn;
  bool _emailOpen = false;
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _messageIsError = true;
  bool _showResend = false;

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Animation<double> _iv(double a, double b, [Curve c = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    _shine.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ logic

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
      _showResend = false;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _message = e.message;
        _messageIsError = true;
        _showResend = e.needsVerification;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Terjadi kesalahan, coba lagi.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dibuka lewat push -> tutup dengan true. Sebagai gerbang -> AuthGate yang
  /// mengganti layar begitu stream auth emit user.
  void _done() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop(true);
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

  void _openEmail() {
    HapticFeedback.selectionClick();
    setState(() {
      _emailOpen = true;
      _message = null;
      _showResend = false;
    });
  }

  void _closeEmail() {
    FocusScope.of(context).unfocus();
    setState(() {
      _emailOpen = false;
      _message = null;
      _showResend = false;
    });
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = _mode == _Mode.signUp ? _Mode.signIn : _Mode.signUp;
      _message = null;
      _showResend = false;
    });
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    final bottomSafe = inset > 0 ? 0.0 : media.padding.bottom;
    final maxPanel = math.max(
      240.0,
      media.size.height - inset - media.padding.top - 64,
    );
    final ready = FirebaseConfig.ready;

    return PopScope(
      canPop: !_emailOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeEmail();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        // Backdrop tidak ikut mengecil saat keyboard muncul; panel yang naik.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _Backdrop(loop: _loop, intro: _wallIn),
            const IgnorePointer(child: _Scrim()),
            _buildTopBar(media.padding.top),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: FadeTransition(
                  opacity: _panelIn,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.28),
                      end: Offset.zero,
                    ).animate(_panelIn),
                    child: _buildPanel(maxPanel, bottomSafe, ready),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(double topPad) {
    final canClose = Navigator.of(context).canPop();
    return Positioned(
      top: topPad + 14,
      left: 20,
      right: 16,
      child: FadeTransition(
        opacity: _logoIn,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
              .animate(_logoIn),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentViolet.withValues(alpha: 0.55),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/images/logo.jpg', width: 38, height: 38),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Zenime',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              if (canClose)
                _Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(double maxHeight, double bottomSafe, bool ready) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: AppColors.backgroundDarkSecondary.withValues(alpha: 0.74),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(24, 12, 24, 22 + bottomSafe),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 380),
                  sizeCurve: Curves.easeOutCubic,
                  firstCurve: Curves.easeOut,
                  secondCurve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  crossFadeState:
                      _emailOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: _buildWelcome(ready),
                  secondChild: _buildEmailForm(ready),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- welcome

  Widget _reveal(Animation<double> a, Widget child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(a),
          child: child,
        ),
      );

  Widget _buildWelcome(bool ready) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _reveal(
          _titleIn,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Siap maraton anime?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  colors: [Color(0xFFB9ADFF), Color(0xFFFF9BDA)],
                ).createShader(r),
                child: const Text(
                  'Masuk dulu, yuk.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _reveal(
          _subIn,
          const Text(
            'Satu akun buat nonton, chat global, kumpulin XP, dan gabung clan.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.45),
          ),
        ),
        const SizedBox(height: 26),
        _reveal(
          _btnIn,
          Column(
            children: [
              if (!ready) ...[
                _Notice(
                  text: 'Login belum dikonfigurasi. Isi apiKey dan appId Firebase di '
                      'lib/core/firebase_config.dart.',
                  isError: true,
                ),
                const SizedBox(height: 14),
              ],
              _GoogleButton(
                busy: _busy && !_emailOpen,
                shine: _shine,
                onTap: (_busy || !ready) ? null : _google,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: (!_emailOpen && _message != null)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _Notice(text: _message!, isError: _messageIsError),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 12),
              _Pressable(
                onTap: _busy ? null : _openEmail,
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: Colors.white.withValues(alpha: 0.06),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mail_outline_rounded, size: 19, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Daftar / masuk pakai email',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Akun Zenime yang sama dipakai di semua versi, jadi datamu nyambung.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- email form

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      prefixIcon: Icon(icon, size: 19, color: AppColors.textSecondary),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: border(Colors.white.withValues(alpha: 0.10)),
      enabledBorder: border(Colors.white.withValues(alpha: 0.10)),
      disabledBorder: border(Colors.white.withValues(alpha: 0.06)),
      focusedBorder: border(AppColors.accentVioletLight, 1.4),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
    Iterable<String>? autofill,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboard,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      autofillHints: autofill,
      textInputAction: action,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      cursorColor: AppColors.accentVioletLight,
      decoration: _decoration(hint, icon, suffix: suffix),
    );
  }

  Widget _buildEmailForm(bool ready) {
    final signUp = _mode == _Mode.signUp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Pressable(
              onTap: _busy ? null : _closeEmail,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(
                  signUp ? 'Buat akun baru' : 'Selamat datang balik',
                  key: ValueKey(signUp),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: signUp
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _field(
                    controller: _username,
                    hint: 'Username',
                    icon: Icons.person_outline_rounded,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        _field(
          controller: _email,
          hint: 'Email',
          icon: Icons.mail_outline_rounded,
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
        ),
        const SizedBox(height: 12),
        _field(
          controller: _password,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          action: TextInputAction.done,
          onSubmitted: (_) => ready ? _submit() : null,
          suffix: IconButton(
            splashRadius: 18,
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 19,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: (_emailOpen && _message != null)
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _Notice(text: _message!, isError: _messageIsError),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (_showResend)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _resend,
              child: const Text('Kirim ulang email verifikasi'),
            ),
          ),
        const SizedBox(height: 18),
        _Pressable(
          onTap: (_busy || !ready) ? null : _submit,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: const LinearGradient(
                colors: [Color(0xFF9486FF), Color(0xFF6352E4)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentViolet.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _busy
                  ? const SizedBox(
                      key: ValueKey('busy'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(
                      signUp ? 'Daftar sekarang' : 'Masuk',
                      key: ValueKey(signUp),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _toggleMode,
            child: Text(
              signUp ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar',
              style: const TextStyle(color: AppColors.accentVioletLight),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================== backdrop

/// Tiga rel poster yang bergulir vertikal tanpa putus (kiri & kanan naik,
/// tengah turun), ditutup wash aurora ungu/pink yang bergerak pelan.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.loop, required this.intro});

  final Animation<double> loop;
  final Animation<double> intro;

  static const double _pad = 12;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final colW = (box.maxWidth - _pad * 2 - _gap * 2) / 3;
        List<String> rail(int i) {
          final mine = <String>[
            for (var k = i; k < kLoginPosters.length; k += 3) kLoginPosters[k],
          ];
          final shift = (i * 3) % mine.length;
          return [...mine.sublist(shift), ...mine.sublist(0, shift)];
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              opacity: intro,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _pad),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: colW,
                      child: _PosterRail(urls: rail(0), width: colW, t: loop, up: true),
                    ),
                    const SizedBox(width: _gap),
                    SizedBox(
                      width: colW,
                      child: _PosterRail(urls: rail(1), width: colW, t: loop, up: false),
                    ),
                    const SizedBox(width: _gap),
                    SizedBox(
                      width: colW,
                      child: _PosterRail(urls: rail(2), width: colW, t: loop, up: true),
                    ),
                  ],
                ),
              ),
            ),
            IgnorePointer(child: _Aurora(t: loop)),
          ],
        );
      },
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({
    required this.urls,
    required this.width,
    required this.t,
    required this.up,
  });

  final List<String> urls;
  final double width;
  final Animation<double> t;
  final bool up;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final itemH = width / 0.68;
    final unit = (itemH + _gap) * urls.length;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).round();

    // Daftar digandakan, geser tepat satu "unit" supaya loop tidak kelihatan.
    final strip = RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final url in [...urls, ...urls])
            Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: SizedBox(
                width: width,
                height: itemH,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: cacheW,
                    fadeInDuration: const Duration(milliseconds: 500),
                    fadeInCurve: Curves.easeOut,
                    placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceCard),
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: AppColors.surfaceCard),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: AnimatedBuilder(
          animation: t,
          child: strip,
          builder: (context, child) {
            final p = t.value;
            final dy = up ? -p * unit : (p - 1) * unit;
            return Transform.translate(offset: Offset(0, dy), child: child);
          },
        ),
      ),
    );
  }
}

class _Aurora extends StatelessWidget {
  const _Aurora({required this.t});

  final Animation<double> t;

  Widget _blob(Alignment at, Color c, double size, double alpha) => Align(
        alignment: at,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        // Frekuensi bulat -> loop 80 detik tersambung mulus.
        final a = t.value * 2 * math.pi * 4;
        return Stack(
          fit: StackFit.expand,
          children: [
            _blob(
              Alignment(-0.85 + 0.28 * math.sin(a), 0.35 + 0.18 * math.cos(a)),
              AppColors.accentViolet,
              560,
              0.42,
            ),
            _blob(
              Alignment(0.95 + 0.2 * math.cos(a * 0.5 + 1), 0.0 + 0.22 * math.sin(a * 0.5)),
              const Color(0xFFE056C8),
              480,
              0.24,
            ),
          ],
        );
      },
    );
  }
}

/// Gelapkan bagian bawah supaya panel kaca terbaca, bagian atas sedikit
/// diredam supaya logo tetap jelas.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    const bg = AppColors.backgroundDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.16, 0.42, 0.68, 1.0],
          colors: [
            bg.withValues(alpha: 0.78),
            bg.withValues(alpha: 0.0),
            bg.withValues(alpha: 0.0),
            bg.withValues(alpha: 0.72),
            bg,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

// ================================================================ widgets

/// Efek tekan: mengecil sedikit + haptic ringan.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.965 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.55,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Tombol Google putih dengan kilau yang menyapu berkala.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.busy,
    required this.shine,
    required this.onTap,
  });

  final bool busy;
  final Animation<double> shine;
  final VoidCallback? onTap;

  static const _ink = Color(0xFF1E1B2E);

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) => AnimatedBuilder(
                    animation: shine,
                    builder: (context, _) {
                      // Menyapu di 40% pertama siklus, sisanya diam.
                      final p = Curves.easeInOut.transform(
                        (shine.value / 0.4).clamp(0.0, 1.0),
                      );
                      final x = -90 + p * (box.maxWidth + 180);
                      return Transform.translate(
                        offset: Offset(x, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Transform(
                            transform: Matrix4.skewX(-0.35),
                            child: Container(
                              width: 70,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.accentVioletLight.withValues(alpha: 0),
                                    AppColors.accentVioletLight.withValues(alpha: 0.28),
                                    AppColors.accentVioletLight.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: busy
                    ? const Row(
                        key: ValueKey('busy'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.accentViolet,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Menghubungkan...',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('idle'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (r) => const SweepGradient(
                              colors: [
                                Color(0xFF4285F4),
                                Color(0xFF34A853),
                                Color(0xFFFBBC05),
                                Color(0xFFEA4335),
                                Color(0xFF4285F4),
                              ],
                            ).createShader(r),
                            child: const Text(
                              'G',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Lanjut dengan Google',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
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

/// Kotak pesan error / sukses.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = isError ? AppColors.errorRed : AppColors.successGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 17,
            color: c,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: c, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
