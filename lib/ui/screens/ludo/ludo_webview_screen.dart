import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/remote_config_manager.dart';
import '../../../providers.dart';
import 'ludo_invite.dart';

/// Warna latar game web (langit biru), dipakai selama halaman dimuat.
const Color _kSky = Color(0xFFCDEBFB);
const Color _kInk = Color(0xFF2B3A55);

/// Minigame Ludo: web game (ludo.zenime.biz.id) dibuka di WebView, login
/// otomatis pakai akun Firebase yang sedang login lewat bridge `ZenimeBridge`.
///
/// Kontrak bridge (sama dengan web game):
///   web -> app : {"type":"ready"} | {"type":"getToken"} | {"type":"share","code":"ABC234"}
///                | {"type":"haptic","kind":"light"|"heavy"} | {"type":"close"}
///   app -> web : window.zenimeReceive({"type":"auth","token","name","avatar"})
class LudoWebViewScreen extends ConsumerStatefulWidget {
  const LudoWebViewScreen({super.key, this.code});

  /// Kode room dari kartu undangan: langsung gabung ke room itu.
  final String? code;

  @override
  ConsumerState<LudoWebViewScreen> createState() => _LudoWebViewScreenState();
}

class _LudoWebViewScreenState extends ConsumerState<LudoWebViewScreen> {
  static final RegExp _codeRe = RegExp(r'^[A-Z2-9]{6}$');

  late final Uri? _url = _buildUrl();

  Uri? _buildUrl() {
    final base = RemoteConfigManager.ludoWebUrl;
    final code = widget.code?.toUpperCase();
    if (base == null || code == null || !_codeRe.hasMatch(code)) return base;
    return base.replace(queryParameters: {...base.queryParameters, 'code': code});
  }
  WebViewController? _ctrl;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final url = _url;
    if (url == null) return;
    unawaited(WakelockPlus.enable());
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Game tidak bisa di-zoom (pinch / double tap).
      ..enableZoom(false)
      ..setBackgroundColor(_kSky)
      ..addJavaScriptChannel('ZenimeBridge', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false) return;
          if (mounted) {
            setState(() {
              _failed = true;
              _loading = false;
            });
          }
        },
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          if (u == null) return NavigationDecision.prevent;
          // Hanya halaman game sendiri yang boleh dibuka di WebView.
          if (u.scheme == 'https' && u.host == url.host) return NavigationDecision.navigate;
          if (u.scheme == 'https' || u.scheme == 'http') {
            unawaited(launchUrl(u, mode: LaunchMode.externalApplication));
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(url);
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void _onMessage(String raw) {
    Map<String, dynamic>? msg;
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) msg = d;
    } catch (_) {}
    if (msg == null) return;
    switch (msg['type']) {
      case 'ready':
        unawaited(_sendAuth(forceRefresh: false));
      case 'getToken':
        unawaited(_sendAuth(forceRefresh: true));
      case 'share':
        final code = msg['code'];
        final players = msg['players'];
        if (code is String && _codeRe.hasMatch(code) && mounted) {
          unawaited(showLudoShareSheet(context, code, players is int && players >= 2 && players <= 4 ? players : null));
        }
      case 'haptic':
        if (msg['kind'] == 'heavy') {
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.lightImpact();
        }
      case 'close':
        // pop() langsung (bukan maybePop) supaya tidak tertahan PopScope.
        if (mounted) Navigator.of(context).pop();
    }
  }

  /// Kirim Firebase ID token + nama/avatar ke web. Nama & avatar cuma
  /// tampilan cadangan; server mengambil identitas dari token.
  Future<void> _sendAuth({required bool forceRefresh}) async {
    final user = FirebaseAuth.instance.currentUser;
    final ctrl = _ctrl;
    if (user == null || ctrl == null) return;
    String? token;
    try {
      token = await user.getIdToken(forceRefresh);
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty || !mounted) return;

    String? name;
    String? avatar;
    try {
      final p = await ref.read(chatProfileProvider(user.uid).future);
      if (p != null) {
        if (p.username.trim().isNotEmpty) name = p.username.trim();
        avatar = p.avatarUrl;
      }
    } catch (_) {}
    name ??= (user.displayName?.trim().isNotEmpty ?? false) ? user.displayName!.trim() : 'Pemain';
    if (avatar != null && !avatar.startsWith('https://')) avatar = null;

    final payload = jsonEncode({'type': 'auth', 'token': token, 'name': name, 'avatar': avatar});
    if (!mounted) return;
    try {
      await ctrl.runJavaScript('window.zenimeReceive && window.zenimeReceive($payload);');
    } catch (_) {}
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari game?'),
        content: const Text('Kalau sedang main, kamu bisa kembali lagi ke room yang sama selama game belum selesai.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Keluar')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  void _retry() {
    final url = _url;
    final ctrl = _ctrl;
    if (url == null || ctrl == null) return;
    setState(() {
      _failed = false;
      _loading = true;
    });
    unawaited(ctrl.loadRequest(url));
  }

  /// Di Android pakai Hybrid Composition: WebView tampil sebagai view
  /// Android asli, jadi scroll/animasinya selancar di browser. Mode bawaan
  /// (texture layer) menyalin WebView ke tekstur tiap frame dan terasa
  /// patah-patah di banyak HP.
  Widget _webView(WebViewController ctrl) {
    final platform = ctrl.platform;
    if (platform is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: platform,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: ctrl);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return PopScope(
      canPop: ctrl == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: _kSky,
          body: SafeArea(
            child: ctrl == null
                ? _Message(
                    icon: Icons.hourglass_empty_rounded,
                    text: 'Ludo segera hadir.',
                    buttonText: 'Kembali',
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : Stack(
                    children: [
                      Positioned.fill(child: _webView(ctrl)),
                      if (_failed)
                        Positioned.fill(
                          child: ColoredBox(
                            color: _kSky,
                            child: _Message(
                              icon: Icons.wifi_off_rounded,
                              text: 'Game tidak bisa dimuat. Cek koneksi internetmu.',
                              buttonText: 'Coba lagi',
                              onPressed: _retry,
                            ),
                          ),
                        )
                      else if (_loading)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: _kSky,
                            child: Center(child: CircularProgressIndicator(color: _kInk)),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, required this.buttonText, required this.onPressed});

  final IconData icon;
  final String text;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: _kInk),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kInk, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(backgroundColor: _kInk, foregroundColor: Colors.white),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}
