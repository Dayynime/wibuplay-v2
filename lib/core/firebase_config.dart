import 'package:firebase_core/firebase_core.dart';

/// Firebase project yang SAMA dengan Zenime (supaya UID user sama, jadi
/// akun, XP, dan chat nyambung).
///
/// Dua nilai di bawah (apiKey dan appId) harus diisi dari
/// google-services.json milik app Android Zenime (com.aistudio.zenime.app,
/// applicationId yang sekarang juga dipakai versi Flutter ini) di Firebase project yang sama:
///   - apiKey -> client[0].api_key[0].current_key
///   - appId  -> client[0].client_info.mobilesdk_app_id  (format 1:xxx:android:yyy)
///
/// Bisa diisi langsung di sini, atau lewat --dart-define=FIREBASE_API_KEY=...
/// dan --dart-define=FIREBASE_APP_ID=... saat build.
class FirebaseConfig {
  FirebaseConfig._();

  static const String projectId = 'zenime-609d0';
  static const String messagingSenderId = '936105562787';
  static const String storageBucket = 'zenime-609d0.firebasestorage.app';

  /// Web Client ID (OAuth client type 3) dipakai Google Sign-In untuk minta idToken.
  static const String webClientId = '936105562787-4rrc0ju88d4t2u82u9us4r6hi7q0e70t.apps.googleusercontent.com';

  static const String apiKey =
      String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'ISI_API_KEY_ZENIME');
  static const String appId =
      String.fromEnvironment('FIREBASE_APP_ID', defaultValue: 'ISI_APP_ID_ZENIME');

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      !apiKey.startsWith('ISI_') &&
      !appId.startsWith('ISI_');

  /// True kalau Firebase.initializeApp() sukses. Selama false, fitur login
  /// dan chat dimatikan (app lain tetap jalan normal).
  static bool ready = false;

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
  );
}
