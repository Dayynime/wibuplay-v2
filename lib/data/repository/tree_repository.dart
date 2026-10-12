import 'package:dio/dio.dart';

import '../models/tree_models.dart';
import 'authed_function.dart';

class TreeException implements Exception {
  const TreeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Pohon ZCoin lewat Edge Function `tree-game`. UID diambil server dari
/// Firebase ID Token; jumlah buah, ZCoin, dan kuota dihitung server.
class TreeRepository {
  TreeRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'tree-game';

  String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      return 'Koneksi bermasalah, coba lagi.';
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, body);
      if (d is Map) return Map<String, dynamic>.from(d);
      throw TreeException(fallback);
    } on TreeException {
      rethrow;
    } catch (e) {
      throw TreeException(_msg(e, fallback));
    }
  }

  static TreeState _tree(dynamic v) =>
      TreeState.fromJson(v is Map ? Map<String, dynamic>.from(v) : const {});

  Future<TreeState> get() async {
    final d = await _call({'action': 'get'}, 'Gagal memuat pohon');
    return TreeState.fromJson(d);
  }

  Future<TreeHarvestResult> harvest(int count) async {
    final d = await _call({'action': 'harvest', 'count': count}, 'Gagal panen');
    return TreeHarvestResult(
      harvested: (d['harvested'] as num?)?.toInt() ?? 0,
      coins: (d['coins'] as num?)?.toInt() ?? 0,
      balance: (d['balance'] as num?)?.toInt() ?? 0,
      tree: _tree(d['tree']),
    );
  }

  Future<TreeUpgradeResult> upgrade() async {
    final d = await _call({'action': 'upgrade'}, 'Gagal upgrade pohon');
    return TreeUpgradeResult(
      cost: (d['cost'] as num?)?.toInt() ?? 0,
      balance: (d['balance'] as num?)?.toInt() ?? 0,
      tree: _tree(d['tree']),
    );
  }

  /// Siram pohon teman. Return bonus menit yang didapat pohon teman.
  Future<int> water(String friendUid) async {
    final d = await _call({'action': 'water', 'friend_uid': friendUid}, 'Gagal menyiram');
    return (d['bonus_min'] as num?)?.toInt() ?? 0;
  }

  Future<TreeWaterStatus> waterStatus() async {
    final d = await _call({'action': 'water_status'}, 'Gagal memuat jatah siram');
    return TreeWaterStatus.fromJson(d);
  }
}
