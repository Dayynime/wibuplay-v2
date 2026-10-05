import 'account_models.dart';

int _int(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// "Rp" tanpa simbol: 1500000 -> "1.500.000".
String formatRupiah(int amount) => formatZCoin(amount);

/// Paket Premium dari Edge Function `zenime-list-packages`.
/// Port PremiumPackage di Zenime.
class PremiumPackage {
  const PremiumPackage({
    required this.id,
    required this.label,
    required this.durationText,
    required this.price,
    this.badge,
  });

  final String id;
  final String label;
  final String durationText;
  final int price;
  final String? badge;

  factory PremiumPackage.fromJson(Map<String, dynamic> j) => PremiumPackage(
        id: j['id']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        durationText: j['duration_text']?.toString() ?? '',
        price: _int(j['price']),
        badge: _strOrNull(j['badge']),
      );

  /// "12 bulan" -> 12, "1 tahun" -> 12. null kalau teks durasi tidak berangka.
  int? get months {
    final m = RegExp(r'\d+').firstMatch(durationText);
    final n = m == null ? null : int.tryParse(m.group(0)!);
    if (n == null || n <= 0) return null;
    return durationText.toLowerCase().contains('tahun') ? n * 12 : n;
  }

  /// Harga per bulan, hanya untuk paket lebih dari sebulan.
  int? get perMonth {
    final m = months;
    return (m != null && m > 1) ? price ~/ m : null;
  }
}

/// Persen hemat tiap paket, dibanding harga per bulan tertinggi (biasanya
/// paket 1 bulan). Hanya paket yang hemat minimal 5% yang masuk.
Map<String, int> premiumSavingPercents(List<PremiumPackage> packages) {
  double? base;
  for (final p in packages) {
    final m = p.months;
    if (m == null) continue;
    final perMonth = p.price / m;
    if (base == null || perMonth > base) base = perMonth;
  }
  final out = <String, int>{};
  final b = base;
  if (b == null || b <= 0) return out;
  for (final p in packages) {
    final m = p.months;
    if (m == null || m <= 1) continue;
    final pct = (((b - p.price / m) / b) * 100).toInt();
    if (pct >= 5) out[p.id] = pct;
  }
  return out;
}

/// Paket top up ZCoin dari `zenime-list-coin-packages`. Port CoinPackage.
class CoinPackage {
  const CoinPackage({
    required this.id,
    required this.label,
    required this.coinAmount,
    required this.bonusCoin,
    required this.price,
  });

  final String id;
  final String label;
  final int coinAmount;
  final int bonusCoin;
  final int price;

  factory CoinPackage.fromJson(Map<String, dynamic> j) => CoinPackage(
        id: j['id']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        coinAmount: _int(j['coin_amount']),
        bonusCoin: _int(j['bonus_coin']),
        price: _int(j['price']),
      );

  /// Total ZCoin yang diterima (pokok + bonus).
  int get totalCoin => coinAmount + bonusCoin;

  /// Bonus dalam persen dari jumlah pokok (dibulatkan ke bawah).
  int get bonusPercent => coinAmount > 0 ? bonusCoin * 100 ~/ coinAmount : 0;
}
