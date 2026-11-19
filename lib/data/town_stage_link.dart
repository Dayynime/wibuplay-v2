import 'dart:async';

import 'package:dio/dio.dart';

import 'repository/authed_function.dart';

/// Penghubung "Mulai Nobar" di Panggung Zenime Town dengan tombol Nobar di
/// player: Town menandai (arm) Plaza-nya, lalu room Nobar pertama yang dibuat
/// dalam 30 menit otomatis dipasang ke panggung Plaza itu.
class TownStageLink {
  TownStageLink._();

  static int? _channel;
  static DateTime? _until;

  static void arm(int channel) {
    _channel = channel;
    _until = DateTime.now().add(const Duration(minutes: 30));
  }

  static void disarm() {
    _channel = null;
    _until = null;
  }

  /// Plaza yang sedang menunggu tayangan (sekali pakai), atau null.
  static int? consume() {
    final ch = _channel;
    final until = _until;
    disarm();
    if (ch == null || until == null || DateTime.now().isAfter(until)) return null;
    return ch;
  }

  /// Pasang room Nobar [roomId] ke panggung Plaza [channel] (Edge Function `town`).
  static Future<void> register(Dio dio, String roomId, int channel) async {
    try {
      await callAuthedFunction(dio, 'town', {'action': 'stage_set', 'room_id': roomId, 'channel': channel});
    } catch (_) {
      // Nobar tetap jalan walau gagal dipasang ke panggung.
    }
  }
}
