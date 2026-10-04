import 'dart:async';

import 'package:android_id/android_id.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/firebase_config.dart';
import '../models/chat_models.dart';
import 'chat_repository.dart';

/// Error login/daftar dengan pesan yang siap ditampilkan ke user.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.needsVerification = false});

  final String message;

  /// True kalau gagal karena email belum diverifikasi (UI menampilkan tombol kirim ulang).
  final bool needsVerification;

  @override
  String toString() => message;
}

/// Login memakai Firebase Auth project yang sama dengan Zenime, jadi UID
/// user sama dan datanya (chat, XP, dll) nyambung. Port AuthRepository.kt.
///
/// Aturan sama dengan Zenime: akun email WAJIB verifikasi dulu. Selama belum
/// verifikasi, user dianggap belum login ([currentUser] tetap null).
class AuthRepository {
  AuthRepository(this._chat, this._dio) {
    if (FirebaseConfig.ready) {
      _current = _usable(FirebaseAuth.instance.currentUser);
      _sub = FirebaseAuth.instance.userChanges().listen((u) => _publish(_usable(u)));
    }
  }

  final ChatRepository _chat;
  final Dio _dio;

  final StreamController<User?> _out = StreamController<User?>.broadcast();
  StreamSubscription<User?>? _sub;
  User? _current;

  bool get available => FirebaseConfig.ready;

  User? get currentUser => _current;

  /// Emit user saat ini lebih dulu, lalu tiap perubahan login/logout.
  Stream<User?> get userStream async* {
    yield _current;
    yield* _out.stream;
  }

  void dispose() {
    _sub?.cancel();
    _out.close();
  }

  User? _usable(User? u) {
    if (u == null) return null;
    final viaGoogle = u.providerData.any((p) => p.providerId == 'google.com');
    return (viaGoogle || u.emailVerified) ? u : null;
  }

  void _publish(User? u) {
    final sameUser = _current?.uid == u?.uid;
    _current = u;
    if (!sameUser) _out.add(u);
  }

  void _requireReady() {
    if (!FirebaseConfig.ready) {
      throw const AuthFailure(
        'Login belum dikonfigurasi. Isi FirebaseConfig.apiKey dan appId untuk Wibuplay.',
      );
    }
  }

  String _defaultUsername(User user) {
    final name = user.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = user.email;
    if (email != null && email.contains('@')) {
      final prefix = email.substring(0, email.indexOf('@'));
      if (prefix.isNotEmpty) return prefix;
    }
    final uid = user.uid;
    return 'User${uid.length > 6 ? uid.substring(0, 6) : uid}';
  }

  // ------------------------------------------------------------------ Google

  Future<void> signInWithGoogle() async {
    _requireReady();
    try {
      final gsi = GoogleSignIn(
        serverClientId: FirebaseConfig.webClientId,
        scopes: const ['email'],
      );
      final account = await gsi.signIn().timeout(const Duration(seconds: 90));
      if (account == null) throw const AuthFailure('Login dibatalkan.');
      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthFailure('Google tidak mengembalikan token. Coba lagi.');
      }
      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      final result = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 20));
      final user = result.user;
      if (user == null) throw const AuthFailure('Login berhasil tapi data user kosong.');
      await _afterSignIn(user);
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'Koneksi timeout, sinyal internet kemungkinan lemah. Coba lagi di jaringan yang lebih stabil.',
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebase(e));
    } on PlatformException catch (e) {
      final text = '${e.code} ${e.message ?? ''}';
      if (text.contains('network_error')) {
        throw const AuthFailure('Tidak ada koneksi internet.');
      }
      if (text.contains('ApiException: 10') || text.contains('DEVELOPER_ERROR')) {
        throw const AuthFailure(
          'Google Sign-In belum cocok dengan konfigurasi Firebase (cek SHA-1 dan Web Client ID).',
        );
      }
      if (text.contains('sign_in_canceled')) {
        throw const AuthFailure('Login dibatalkan.');
      }
      throw AuthFailure('Login Google gagal (${e.code}).');
    }
  }

  // ------------------------------------------------------------------- Email

  /// Daftar, set displayName, kirim email verifikasi, lalu signOut:
  /// user wajib verifikasi dulu sebelum bisa masuk.
  Future<void> signUpWithEmail(String username, String email, String password) async {
    _requireReady();
    final name = username.trim();
    if (name.isEmpty) throw const AuthFailure('Username tidak boleh kosong.');
    try {
      final result = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 20));
      final user = result.user;
      if (user == null) throw const AuthFailure('Daftar berhasil tapi data user kosong.');
      await user.updateDisplayName(name);
      await user.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure('Koneksi timeout, coba lagi di jaringan yang lebih stabil.');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebase(e));
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    _requireReady();
    try {
      final result = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 20));
      final user = result.user;
      if (user == null) throw const AuthFailure('Login berhasil tapi data user kosong.');
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser ?? user;
      if (!fresh.emailVerified) {
        await FirebaseAuth.instance.signOut();
        throw const AuthFailure(
          'Email kamu belum diverifikasi. Cek inbox (atau folder spam), klik link verifikasinya, lalu masuk lagi.',
          needsVerification: true,
        );
      }
      await _afterSignIn(fresh);
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure('Koneksi timeout, coba lagi di jaringan yang lebih stabil.');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebase(e));
    }
  }

  Future<void> resendVerificationEmail(String email, String password) async {
    _requireReady();
    try {
      final result = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 20));
      final user = result.user;
      if (user == null) throw const AuthFailure('Gagal masuk sementara untuk kirim ulang email.');
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser ?? user;
      if (fresh.emailVerified) {
        await FirebaseAuth.instance.signOut();
        throw const AuthFailure('Email kamu sudah diverifikasi, coba masuk lagi.');
      }
      await fresh.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure('Koneksi timeout, coba lagi di jaringan yang lebih stabil.');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebase(e));
    }
  }

  Future<void> signOut() async {
    if (!FirebaseConfig.ready) return;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    _publish(null);
  }

  // ---------------------------------------------------------------- internal

  /// Cek ban (akun/perangkat) dulu seperti Zenime, baru aktifkan sesi dan
  /// pastikan baris chat_profiles ada.
  Future<void> _afterSignIn(User user) async {
    final ban = await _checkBan(user);
    if (ban.banned) {
      await signOut();
      throw AuthFailure(ban.reason ?? 'Akun/perangkat ini diblokir.');
    }
    _publish(_usable(user));
    unawaited(_chat.ensureProfile(user.uid, _defaultUsername(user), user.photoURL));
  }

  /// Edge Function `zenime-check-ban` butuh Firebase ID Token asli di header
  /// Authorization. Gagal cek (jaringan/server) dianggap tidak diban, sama
  /// seperti Zenime.
  Future<BanStatus> _checkBan(User user) async {
    try {
      final token = await user.getIdToken();
      var deviceId = '';
      try {
        deviceId = await AndroidId().getId() ?? '';
      } catch (_) {}
      final res = await _dio.post<dynamic>(
        'functions/v1/zenime-check-ban',
        data: {'device_id': deviceId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = res.data;
      if (data is Map) return BanStatus.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {}
    return const BanStatus();
  }

  String _mapFirebase(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email ini sudah dipakai akun lain. Coba masuk, atau pakai email lain.';
      case 'weak-password':
        return 'Password terlalu lemah, minimal 6 karakter.';
      case 'invalid-email':
        return 'Format email tidak valid.';
      case 'user-not-found':
        return 'Akun dengan email ini tidak ditemukan. Daftar dulu ya.';
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Email atau password salah.';
      case 'user-disabled':
        return 'Akun ini dinonaktifkan.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
      case 'network-request-failed':
        return 'Tidak ada koneksi internet.';
      default:
        return e.message ?? 'Terjadi kesalahan (${e.code}).';
    }
  }
}
