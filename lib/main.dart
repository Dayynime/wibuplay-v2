import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/firebase_config.dart';
import 'core/remote_config_manager.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'data/local/zenime_room_migration.dart';
import 'providers.dart';
import 'ui/app_routes.dart';
import 'ui/components/mini_player.dart';
import 'ui/route_observer.dart';
import 'ui/components/announcement_popup.dart';
import 'ui/screens/auth/auth_gate.dart';
import 'ui/screens/maintenance/maintenance_screen.dart';
import 'ui/screens/security/ban_overlay.dart';
import 'ui/screens/onboarding/onboarding_gate.dart';
import 'ui/screens/security/integrity_gate.dart';
import 'ui/screens/update/update_gate.dart';
import 'ui/shell/app_shell.dart';

/// Firebase (login Zenime) + Remote Config. Dipanggil [IntegrityGate] HANYA
/// setelah lolos cek keamanan, jadi tidak ada request jaringan sama sekali
/// kalau app terlarang terdeteksi. Kalau belum dikonfigurasi atau gagal init,
/// app tetap jalan normal; hanya login dan chat yang nonaktif.
Future<void> _initBackend() async {
  if (!FirebaseConfig.isConfigured) return;
  try {
    await Firebase.initializeApp(options: FirebaseConfig.options);
    FirebaseConfig.ready = true;
    // Base URL API dari Remote Config harus siap sebelum request pertama.
    // forceRefresh (bukan refresh) SENGAJA: app yang baru di-update mewarisi
    // cache Remote Config sesi lama dan bisa melewatkan fetch sampai 1 jam,
    // padahal maintenance_mode harus langsung kebaca saat app dibuka.
    await RemoteConfigManager.forceRefresh();
    // Pantau maintenance_* real-time selama app terbuka.
    RemoteConfigManager.watchMaintenance();
  } catch (_) {
    FirebaseConfig.ready = false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Port MainActivity: edge-to-edge, status/nav bar warna BackgroundDark, ikon terang.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.backgroundDark,
      systemNavigationBarColor: AppColors.backgroundDark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final store = await LocalStore.open();
  // Impor sekali favorit/riwayat/download dari database Room Zenime lama
  // (applicationId sama), supaya data tidak hilang saat update ke Wibuplay.
  await ZenimeRoomMigration.run(store);

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWith((ref) => store)],
      child: const ZenimeApp(),
    ),
  );
}

class ZenimeApp extends ConsumerWidget {
  const ZenimeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Urutan buka app: IntegrityGate -> splash (UpdateGate) -> intro
    // (OnboardingGate, sekali saja) -> login (AuthGate) -> app. Splash ditahan
    // minimal 1,8 detik hanya saat intro belum pernah dilihat, supaya buka app
    // berikutnya tetap cepat.
    final introSeen = ref.read(localStoreProvider).onboardingSeen;
    return MaterialApp(
      title: 'Zenime',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: appNavigatorKey,
      navigatorObservers: [routeObserver],
      // Mini player ngambang di atas semua layar (di luar Navigator).
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(child: child ?? const SizedBox.shrink()),
          const MiniPlayerOverlay(),
          // Paling atas: menutup semua halaman (juga yang di-push) saat maintenance.
          const MaintenanceOverlay(),
          // Muncul real-time saat admin ban user yang lagi buka app.
          const BanOverlay(),
        ],
      ),
      home: IntegrityGate(
        onClear: _initBackend,
        child: UpdateGate(
          minSplash: introSeen ? Duration.zero : const Duration(milliseconds: 1800),
          child: const OnboardingGate(
            child: AuthGate(child: AnnouncementHost(child: AppShell())),
          ),
        ),
      ),
    );
  }
}
