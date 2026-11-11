import 'package:dio/dio.dart';

import '../models/affinity_models.dart';
import 'authed_function.dart';

/// Edge Function `affinity`. UID pemanggil diambil server dari Firebase ID Token.
/// Pesan error dari server dilempar sebagai Exception (siap ditampilkan).
class AffinityRepository {
  AffinityRepository(this._dio);

  final Dio _dio;

  Future<dynamic> _call(Map<String, dynamic> body) async {
    final d = await callAuthedFunction(_dio, 'affinity', body);
    return d is Map ? d['data'] : null;
  }

  Future<AffinityList> list(String uid) async {
    final d = await _call({'action': 'list', 'uid': uid});
    return d is Map ? AffinityList.fromJson(Map<String, dynamic>.from(d)) : const AffinityList();
  }

  Future<AffinityDetail?> detail(String id) async {
    final d = await _call({'action': 'detail', 'id': id});
    return d is Map ? AffinityDetail.fromJson(Map<String, dynamic>.from(d)) : null;
  }

  Future<List<AffinityRequest>> requests({required bool incoming}) async {
    final d = await _call({'action': incoming ? 'incoming' : 'outgoing'});
    if (d is! List) return const [];
    return d
        .whereType<Map>()
        .map((e) => AffinityRequest.fromJson(Map<String, dynamic>.from(e)))
        .whereType<AffinityRequest>()
        .toList();
  }

  Future<void> request({
    required String target,
    required AffinityType type,
    String? role,
    String? message,
  }) async {
    await _call({
      'action': 'request',
      'target': target,
      'type': type.key,
      if (role != null) 'role': role,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    });
  }

  Future<void> cancel(String requestId) => _call({'action': 'cancel', 'id': requestId});

  /// true = diterima.
  Future<bool> respond(String requestId, {required bool accept}) async {
    final d = await _call({'action': 'respond', 'id': requestId, 'accept': accept});
    return d is Map && d['accepted'] == true;
  }

  Future<void> breakBond(String affinityId) => _call({'action': 'break', 'id': affinityId});
}
