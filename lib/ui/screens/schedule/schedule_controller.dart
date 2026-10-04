import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anime_item.dart';
import '../../../providers.dart';
import '../home/home_controller.dart';

/// Port ScheduleUiState.
class ScheduleUiState {
  const ScheduleUiState({
    this.selectedDay = 'SENIN',
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  final String selectedDay;
  final List<AnimeItem> items;
  final bool isLoading;
  final String? error;

  ScheduleUiState copyWith({
    String? selectedDay,
    List<AnimeItem>? items,
    bool? isLoading,
    String? Function()? error,
  }) {
    return ScheduleUiState(
      selectedDay: selectedDay ?? this.selectedDay,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }
}

/// Port ScheduleViewModel.
class ScheduleController extends Notifier<ScheduleUiState> {
  static const List<String> days = [
    'SENIN',
    'SELASA',
    'RABU',
    'KAMIS',
    'JUMAT',
    'SABTU',
    'MINGGU',
  ];

  bool _alive = true;
  int _request = 0;

  @override
  ScheduleUiState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final today = HomeController.currentDayName();
    Future.microtask(() => loadSchedule(today));
    return ScheduleUiState(selectedDay: today);
  }

  void onDaySelected(String day) {
    if (state.selectedDay == day) return;
    state = state.copyWith(selectedDay: day);
    loadSchedule(day);
  }

  Future<void> loadSchedule(String day) async {
    final request = ++_request;
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final list = await ref.read(repositoryProvider).getSchedule(day);
      if (!_alive || request != _request) return;
      state = state.copyWith(items: list, isLoading: false);
    } catch (e) {
      if (!_alive || request != _request) return;
      final msg = errorMessage(e, 'Gagal memuat jadwal rilis');
      state = state.copyWith(isLoading: false, error: () => msg);
    }
  }
}

final scheduleControllerProvider =
    NotifierProvider<ScheduleController, ScheduleUiState>(ScheduleController.new);
