import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'providers.dart';
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

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWith((ref) => store)],
      child: const WibuplayApp(),
    ),
  );
}

class WibuplayApp extends StatelessWidget {
  const WibuplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wibuplay',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
