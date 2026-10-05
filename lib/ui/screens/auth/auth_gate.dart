import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../providers.dart';
import 'login_screen.dart';

/// Gerbang wajib login. Belum login -> LoginScreen, sudah login -> [child]
/// (AppShell), dengan cross-fade halus. Login/logout otomatis mengganti layar
/// lewat [authUserProvider], jadi LoginScreen tidak perlu navigasi manual.
///
/// Kalau Firebase belum dikonfigurasi (apiKey/appId masih placeholder), gerbang
/// dilewati supaya app tidak terkunci di layar login yang tidak bisa dipakai.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!FirebaseConfig.ready) return child;

    // currentUser sudah terisi sinkron dari sesi tersimpan, jadi user yang
    // sudah login tidak sempat melihat kilasan layar login saat stream loading.
    final user = ref.watch(authUserProvider).valueOrNull ??
        ref.read(authRepositoryProvider).currentUser;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: user != null
          ? KeyedSubtree(key: const ValueKey('app'), child: child)
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}
