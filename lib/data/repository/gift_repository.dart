import 'package:dio/dio.dart';

import '../models/support_models.dart';
import 'authed_function.dart';

/// Status kuota Gift Premium milik user yang login (dari server).
class GiftStatus {
  const GiftStatus({
    required this.isPremium,
    required this.isPermanent,
    required this.hasPurchase,
    required this.canGift,
    required this.availableDays,
    required this.windowUsed,
    required this.windowMax,
    required this.monthUsed,
    required this.monthMax,
    this.maxDaysPerGift = 3,
    this.giveawayMaxSlots = 3,
    this.openGiveawayId,
    this.expiresAt,
    this.windowUnlockAt,
    this.monthResetAt,
  });

  final bool isPremium;
  final bool isPermanent;
  final bool hasPurchase;
  final bool canGift;
  final int availableDays;
  final int windowUsed;
  final int windowMax;
  final int monthUsed;
  final int monthMax;
  final int maxDaysPerGift;
  final int giveawayMaxSlots;

  /// Giveaway milik sendiri yang masih berjalan (null = tidak ada).
  final int? openGiveawayId;
  final DateTime? expiresAt;
  final DateTime? windowUnlockAt;
  final DateTime? monthResetAt;

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;
  static DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory GiftStatus.fromJson(Map<String, dynamic> j) => GiftStatus(
        isPremium: j['is_premium'] == true,
        isPermanent: j['is_permanent'] == true,
        hasPurchase: j['has_purchase'] == true,
        canGift: j['can_gift'] == true,
        availableDays: _i(j['available_days']),
        windowUsed: _i(j['window_used']),
        windowMax: _i(j['window_max']),
        monthUsed: _i(j['month_used']),
        monthMax: _i(j['month_max']),
        maxDaysPerGift: j['max_days_per_gift'] == null ? 3 : _i(j['max_days_per_gift']),
        giveawayMaxSlots: j['giveaway_max_slots'] == null ? 3 : _i(j['giveaway_max_slots']),
        openGiveawayId: (j['open_giveaway_id'] as num?)?.toInt(),
        expiresAt: _d(j['expires_at']),
        windowUnlockAt: _d(j['window_unlock_at']),
        monthResetAt: _d(j['month_reset_at']),
      );
}

/// Status satu giveaway (untuk kartu di chat global).
class GiveawayState {
  const GiveawayState({
    required this.id,
    required this.creatorUid,
    required this.days,
    required this.slots,
    required this.claimed,
    required this.status,
    required this.claimedByMe,
    this.expiresAt,
  });

  final int id;
  final String creatorUid;
  final int days;
  final int slots;
  final int claimed;

  /// 'open' | 'done' | 'expired'
  final String status;
  final bool claimedByMe;
  final DateTime? expiresAt;

  bool get isOpen => status == 'open' && claimed < slots;

  factory GiveawayState.fromJson(Map<String, dynamic> j) => GiveawayState(
        id: GiftStatus._i(j['id']),
        creatorUid: (j['creator_uid'] as String?) ?? '',
        days: GiftStatus._i(j['days']),
        slots: GiftStatus._i(j['slots']),
        claimed: GiftStatus._i(j['claimed']),
        status: (j['status'] as String?) ?? 'expired',
        claimedByMe: j['claimed_by_me'] == true,
        expiresAt: GiftStatus._d(j['expires_at']),
      );
}

class GiftException implements Exception {
  const GiftException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gift Premium lewat Edge Function `premium-gift`. Semua aturan (kuota,
/// syarat pernah beli, sisa premium, ban) dicek di server; app cuma meminta.
class GiftRepository {
  GiftRepository(this._dio);

  final Dio _dio;

  String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      return 'Koneksi bermasalah, coba lagi.';
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  /// Peringkat Top Giver (publik, tanpa login).
  Future<List<TopGiver>> topGivers({int limit = 50}) async {
    final res = await _dio.post<dynamic>(
      'functions/v1/premium-gift',
      data: {'action': 'top_givers', 'limit': limit},
    );
    final d = res.data;
    if (d is! List) return const [];
    final rows = d.whereType<Map>().toList();
    return [
      for (var i = 0; i < rows.length; i++)
        TopGiver.fromJson(Map<String, dynamic>.from(rows[i]), i + 1),
    ];
  }

  Future<GiftStatus> status() async {
    try {
      final d = await callAuthedFunction(_dio, 'premium-gift', {'action': 'status'});
      return GiftStatus.fromJson(d is Map ? Map<String, dynamic>.from(d) : const {});
    } catch (e) {
      throw GiftException(_msg(e, 'Gagal memuat kuota gift'));
    }
  }

  /// Buat giveaway di chat global. Return baris pesan kartu giveaway.
  Future<Map<String, dynamic>?> createGiveaway({
    required int days,
    required int slots,
    String message = '',
  }) async {
    try {
      final d = await callAuthedFunction(_dio, 'premium-gift', {
        'action': 'giveaway_create',
        'days': days,
        'slots': slots,
        'message': message.trim(),
      });
      final m = d is Map ? d['message'] : null;
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (e) {
      throw GiftException(_msg(e, 'Giveaway gagal dibuat'));
    }
  }

  /// Klaim giveaway. Return jumlah hari yang didapat.
  Future<int> claimGiveaway(int id) async {
    try {
      final d = await callAuthedFunction(_dio, 'premium-gift', {
        'action': 'giveaway_claim',
        'giveaway_id': id,
      });
      final c = d is Map ? d['claim'] : null;
      return c is Map ? ((c['days'] as num?)?.toInt() ?? 0) : 0;
    } catch (e) {
      throw GiftException(_msg(e, 'Gagal klaim'));
    }
  }

  Future<List<GiveawayState>> giveawayStates(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final d = await callAuthedFunction(_dio, 'premium-gift', {
      'action': 'giveaway_states',
      'ids': ids.take(50).toList(),
    });
    if (d is! List) return const [];
    return d
        .whereType<Map>()
        .map((e) => GiveawayState.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// [channel] 'global' atau 'private'. Return baris pesan bubble gift
  /// (null kalau bubble gagal dibuat; gift-nya tetap sah).
  Future<Map<String, dynamic>?> send({
    required String recipientUid,
    required int days,
    required String channel,
  }) async {
    try {
      final d = await callAuthedFunction(_dio, 'premium-gift', {
        'action': 'send',
        'recipient_uid': recipientUid,
        'days': days,
        'channel': channel,
      });
      final m = d is Map ? d['message'] : null;
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (e) {
      throw GiftException(_msg(e, 'Gift gagal dikirim'));
    }
  }
}
