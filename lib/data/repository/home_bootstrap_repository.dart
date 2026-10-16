import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_bootstrap.dart';
import 'authed_function.dart';

/// Data awal Beranda lewat SATU request (`home-bootstrap`), plus salinan
/// terakhir di HP supaya kartu akun langsung tampil saat app dibuka.
class HomeBootstrapRepository {
  HomeBootstrapRepository(this._dio);

  final Dio _dio;

  static const String _cacheKey = 'home_bootstrap_cache_v1';

  Future<HomeBootstrap> fetch() async {
    final d = await callAuthedFunction(_dio, 'home-bootstrap', const {});
    if (d is! Map) throw Exception('Respons home-bootstrap tidak valid');
    return HomeBootstrap.fromJson(Map<String, dynamic>.from(d));
  }

  /// Salinan terakhir milik [uid] (akun lain diabaikan).
  Future<HomeBootstrap?> loadCache(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_cacheKey);
      if (s == null) return null;
      final j = jsonDecode(s);
      if (j is! Map) return null;
      final b = HomeBootstrap.fromJson(Map<String, dynamic>.from(j));
      return b.uid == uid ? b : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCache(HomeBootstrap b) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheKey, jsonEncode(b.raw));
    } catch (_) {}
  }

  Future<void> clearCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cacheKey);
    } catch (_) {}
  }
}
