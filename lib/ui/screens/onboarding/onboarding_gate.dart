import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import 'onboarding_screen.dart';

/// Gerbang intro. Dipasang DI DALAM UpdateGate (splash) dan DI LUAR AuthGate:
/// splash -> intro (sekali saja) -> login -> app.
///
/// Flag disimpan di shared_preferences lewat [LocalStore.onboardingSeen].
/// Selesai atau "Lewati" sama-sama menandai intro sudah dilihat, jadi tidak
/// muncul lagi di buka-buka berikutnya.
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  late bool _seen = ref.read(localStoreProvider).onboardingSeen;

  void _finish() {
    ref.read(localStoreProvider).setOnboardingSeen(true);
    setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: _seen
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : OnboardingScreen(
              key: const ValueKey('onboarding'),
              onFinished: _finish,
            ),
    );
  }
}
