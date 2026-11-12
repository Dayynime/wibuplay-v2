import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/home_sections.dart';
import '../../../providers.dart';

/// Port HomeViewModel: Loading / Success / Error lewat AsyncValue.
/// Tidak memuat ulang kalau sudah sukses, kecuali forceRefresh.
///
/// Saat app dibuka, salinan Beranda terakhir di HP langsung ditampilkan
/// (tanpa shimmer), lalu data baru diambil di belakang dan menggantikannya.
/// Kalau belum ada salinan (instal baru), alurnya sama seperti dulu.
class HomeController extends AsyncNotifier<HomeSectionData> {
  @override
  FutureOr<HomeSectionData> build() {
    // Salinan di memori (dimuat di main() sebelum runApp): dikembalikan
    // SINKRON, jadi Beranda langsung berisi di frame pertama tanpa skeleton.
    final mem = ref.read(repositoryProvider).peekCachedHome(currentDay: currentDayName());
    if (mem != null) {
      Future.microtask(_refreshInBackground);
      return mem;
    }
    return _buildFromDisk();
  }

  Future<HomeSectionData> _buildFromDisk() async {
    final cached = await ref
        .read(repositoryProvider)
        .loadCachedHome(currentDay: currentDayName());
    if (cached != null) {
      Future.microtask(_refreshInBackground);
      return cached;
    }
    return _fetch(false);
  }

  /// Segarkan diam-diam; kalau gagal, salinan yang tampil tetap dipakai.
  Future<void> _refreshInBackground() async {
    try {
      final fresh = await ref
          .read(repositoryProvider)
          .getHomeSections(forceRefresh: true, currentDay: currentDayName());
      state = AsyncData(fresh);
    } catch (_) {}
  }

  /// Nama hari Indonesia (SENIN..MINGGU) sesuai hari ini.
  static String currentDayName() {
    const days = ['SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU', 'MINGGU'];
    return days[DateTime.now().weekday - 1];
  }

  Future<HomeSectionData> _fetch(bool force) async {
    try {
      return await ref
          .read(repositoryProvider)
          .getHomeSections(forceRefresh: force, currentDay: currentDayName());
    } catch (e) {
      throw Exception(errorMessage(e, 'Gagal memuat data beranda'));
    }
  }

  Future<void> loadHomeData({bool forceRefresh = false}) async {
    if (!forceRefresh && state is AsyncData<HomeSectionData>) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(forceRefresh));
  }
}

final homeControllerProvider =
    AsyncNotifierProvider<HomeController, HomeSectionData>(HomeController.new);
