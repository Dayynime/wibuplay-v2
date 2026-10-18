import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

const List<double> kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

String speedLabel(double speed) {
  final s = speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed.toString();
  return '${s}x';
}

/// Bottom sheet "Pengaturan Pemutar": kecepatan putar + lewati intro/outro
/// otomatis (port PlayerSettingsMenu + pengaturan auto-skip Zenime).
Future<void> showPlayerSettingsSheet(
  BuildContext context, {
  required double speed,
  required bool autoSkipIntro,
  required bool autoSkipOutro,
  required ValueChanged<double> onSpeed,
  required ValueChanged<bool> onAutoSkipIntro,
  required ValueChanged<bool> onAutoSkipOutro,
}) {
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  var curSpeed = speed;
  var curIntro = autoSkipIntro;
  var curOutro = autoSkipOutro;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheet) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 2),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: bottomInset + 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetTitle('Kecepatan Putar'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in kPlaybackSpeeds)
                              _SpeedChip(
                                label: speedLabel(s),
                                selected: curSpeed == s,
                                onTap: () {
                                  setSheet(() => curSpeed = s);
                                  onSpeed(s);
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _SheetTitle('Lewati Otomatis'),
                      _SwitchRow(
                        icon: Icons.fast_forward,
                        title: 'Lewati Intro Otomatis',
                        subtitle: 'Lompat ke detik 90 saat episode dibuka dari awal',
                        value: curIntro,
                        onChanged: (v) {
                          setSheet(() => curIntro = v);
                          onAutoSkipIntro(v);
                        },
                      ),
                      _SwitchRow(
                        icon: Icons.skip_next,
                        title: 'Auto-Lanjut Episode (Outro)',
                        subtitle: 'Lanjut ke episode berikutnya saat hampir habis',
                        value: curOutro,
                        onChanged: (v) {
                          setSheet(() => curOutro = v);
                          onAutoSkipOutro(v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textWhite,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentViolet : AppColors.surfaceVariantDark,
          borderRadius: AppShapes.pill,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textWhite : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.accentViolet),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0x8CFFFFFF), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.textWhite,
              activeTrackColor: AppColors.accentViolet,
            ),
          ],
        ),
      ),
    );
  }
}
