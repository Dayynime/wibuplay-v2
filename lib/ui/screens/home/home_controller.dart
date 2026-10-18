import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/home_sections.dart';
import '../../../providers.dart';

/// Port HomeViewModel: Loading / Success / Error lewat AsyncValue.
/// Tidak memuat ulang kalau sudah sukses, kecuali forceRefresh.
class HomeController extends AsyncNotifier<HomeSectionData> {
  @override
  Future<HomeSectionData> build() => _fetch(false);

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
