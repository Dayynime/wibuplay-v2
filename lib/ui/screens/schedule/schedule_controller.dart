import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anime_item.dart';
import '../../../providers.dart';
import '../home/home_controller.dart';

/// Semua anime yang tayang pada satu hari (0 = Senin ... 6 = Minggu).
class DaySection {
  const DaySection({
    required this.dayIndex,
    required this.dayName,
    required this.anime,
  });

  final int dayIndex;
  final String dayName;
  final List<AnimeItem> anime;
}

/// Ambil "HH:mm" dari "yyyy-MM-dd HH:mm:ss"; "--:--" kalau tidak ada.
String formatKeyTime(String? keyTime) {
  if (keyTime == null || keyTime.trim().isEmpty) return '--:--';
  final i = keyTime.indexOf(' ');
  if (i < 0) return '--:--';
  final part = keyTime.substring(i + 1);
  return part.length >= 5 ? part.substring(0, 5) : '--:--';
}

class ScheduleUiState {
  const ScheduleUiState({
    this.sections = const [],
    this.isLoading = false,
    this.error,
    required this.todayIndex,
  });

  final List<DaySection> sections;
  final bool isLoading;
  final String? error;

  /// Indeks hari ini, dipakai untuk lompat otomatis saat halaman dibuka.
  final int todayIndex;

  ScheduleUiState copyWith({
    List<DaySection>? sections,
    bool? isLoading,
    String? Function()? error,
  }) {
    return ScheduleUiState(
      sections: sections ?? this.sections,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      todayIndex: todayIndex,
    );
  }
}

/// Port ScheduleViewModel.kt: satu minggu penuh dimuat sekaligus.
class ScheduleController extends Notifier<ScheduleUiState> {
  /// Kunci yang dipakai API.
  static const List<String> days = [
    'SENIN',
    'SELASA',
    'RABU',
    'KAMIS',
    'JUMAT',
    'SABTU',
    'MINGGU',
  ];

  static const List<String> dayNames = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  bool _alive = true;
  int _request = 0;

  @override
  ScheduleUiState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(loadFullWeek);
    return ScheduleUiState(
      isLoading: true,
      todayIndex: days.indexOf(HomeController.currentDayName()).clamp(0, 6),
    );
  }

  Future<void> loadFullWeek() async {
    final request = ++_request;
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      var failed = 0;
      final results = await Future.wait([
        for (final day in days)
          ref.read(repositoryProvider).getSchedule(day).catchError((_) {
            failed++;
            return <AnimeItem>[];
          }),
      ]);
      if (!_alive || request != _request) return;
      if (failed == days.length) {
        throw Exception('Gagal memuat jadwal rilis');
      }
      final sections = [
        for (var i = 0; i < days.length; i++)
          DaySection(
            dayIndex: i,
            dayName: dayNames[i],
            anime: _sortByTime(results[i]),
          ),
      ];
      state = state.copyWith(sections: sections, isLoading: false);
    } catch (e) {
      if (!_alive || request != _request) return;
      final msg = errorMessage(e, 'Gagal memuat jadwal rilis');
      state = state.copyWith(isLoading: false, error: () => msg);
    }
  }

  /// Urut dari jam paling awal; yang tanpa jam di akhir.
  static List<AnimeItem> _sortByTime(List<AnimeItem> list) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final ta = formatKeyTime(a.$2.keyTime);
      final tb = formatKeyTime(b.$2.keyTime);
      final c = ta.compareTo(tb); // "--:--" otomatis paling akhir
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}

final scheduleControllerProvider =
    NotifierProvider<ScheduleController, ScheduleUiState>(ScheduleController.new);
