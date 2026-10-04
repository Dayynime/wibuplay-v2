import 'package:flutter/widgets.dart';

/// Dipakai layar yang berisi video (Cuplix) untuk tahu kapan tertutup layar lain
/// (Detail/Player). Di Kotlin composable Cuplix otomatis dibuang saat NavHost
/// pindah destinasi; di Flutter tab tetap hidup di IndexedStack, jadi perlu sinyal ini.
final RouteObserver<ModalRoute<Object?>> routeObserver =
    RouteObserver<ModalRoute<Object?>>();
