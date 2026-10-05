import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/firebase_config.dart';
import 'core/remote_config_manager.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'providers.dart';
import 'ui/route_observer.dart';
import 'ui/components/announcement_popup.dart';
import 'ui/screens/auth/auth_gate.dart';
import 'ui/screens/update/update_gate.dart';
import 'ui/shell/app_shell.dart';

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

  // Firebase (login Zenime). Kalau belum dikonfigurasi atau gagal init, app
  // tetap jalan normal; hanya login dan chat yang nonaktif.
  if (FirebaseConfig.isConfigured) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseConfig.ready = true;
      // Base URL API dari Remote Config harus siap sebelum request pertama.
      await RemoteConfigManager.refresh();
    } catch (_) {
      FirebaseConfig.ready = false;
    }
  }

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWith((ref) => store)],
      child: const ZenimeApp(),
    ),
  );
}

class ZenimeApp extends StatelessWidget {
  const ZenimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenime',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [routeObserver],
      home: const UpdateGate(
        child: AuthGate(child: AnnouncementHost(child: AppShell())),
      ),
    );
  }
}
