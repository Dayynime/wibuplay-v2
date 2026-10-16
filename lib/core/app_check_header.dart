import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_config.dart';

/// Header App Check (`X-Firebase-AppCheck`) untuk Edge Function yang rawan
/// di-bot (heartbeat XP, claim giveaway). Token didapat dari Play Integrity dan
/// di-cache SDK, jadi panggilan berikutnya instan. Gagal / device tanpa Google
/// Play -> header kosong; server yang memutuskan (mode log: tetap jalan).
Future<Map<String, String>> appCheckHeaders() async {
  if (!FirebaseConfig.ready) return const {};
  try {
    final t = await FirebaseAppCheck.instance.getToken().timeout(const Duration(seconds: 5));
    if (t != null && t.isNotEmpty) return {'X-Firebase-AppCheck': t};
  } catch (_) {}
  return const {};
}
