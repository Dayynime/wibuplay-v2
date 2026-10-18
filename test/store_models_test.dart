import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/data/models/store_models.dart';

PremiumPackage _p(String id, String duration, int price, {String? badge}) =>
    PremiumPackage(
      id: id,
      label: duration,
      durationText: duration,
      price: price,
      badge: badge,
    );

void main() {
  group('PremiumPackage.months', () {
    test('bulan dan tahun', () {
      expect(_p('a', '1 bulan', 1).months, 1);
      expect(_p('b', '12 bulan', 1).months, 12);
      expect(_p('c', '1 tahun', 1).months, 12);
    });

    test('teks tanpa angka -> null', () {
      expect(_p('d', 'Selamanya', 1).months, isNull);
      expect(_p('e', '0 bulan', 1).months, isNull);
    });

    test('perMonth hanya untuk paket lebih dari sebulan', () {
      expect(_p('a', '1 bulan', 20000).perMonth, isNull);
      expect(_p('b', '3 bulan', 45000).perMonth, 15000);
    });
  });

  group('premiumSavingPercents', () {
    test('dibanding harga per bulan tertinggi', () {
      final list = [
        _p('m1', '1 bulan', 20000),
        _p('m3', '3 bulan', 45000), // 15.000 / bulan -> hemat 25%
        _p('m12', '12 bulan', 120000), // 10.000 / bulan -> hemat 50%
      ];
      final out = premiumSavingPercents(list);
      expect(out['m1'], isNull);
      expect(out['m3'], 25);
      expect(out['m12'], 50);
    });

    test('hemat di bawah 5% tidak ditampilkan', () {
      final list = [
        _p('m1', '1 bulan', 20000),
        _p('m3', '3 bulan', 59000), // 19.666 / bulan -> ~1%
      ];
      expect(premiumSavingPercents(list), isEmpty);
    });

    test('durasi tak terbaca -> kosong', () {
      expect(premiumSavingPercents([_p('x', 'Selamanya', 1000)]), isEmpty);
      expect(premiumSavingPercents(const []), isEmpty);
    });
  });

  group('fromJson', () {
    test('harga bisa angka atau string', () {
      expect(
        PremiumPackage.fromJson({
          'id': 'p1',
          'label': '1 Bulan',
          'duration_text': '1 bulan',
          'price': '20000',
          'badge': ' ',
        }).price,
        20000,
      );
      final coin = CoinPackage.fromJson({
        'id': 'c1',
        'label': 'x',
        'coin_amount': 1000,
        'bonus_coin': '100',
        'price': 10000,
      });
      expect(coin.totalCoin, 1100);
      expect(coin.bonusPercent, 10);
    });

    test('badge kosong -> null', () {
      expect(
        PremiumPackage.fromJson({'id': 'a', 'price': 1, 'badge': '  '}).badge,
        isNull,
      );
    });

    test('bonus tanpa jumlah pokok tidak error', () {
      const c = CoinPackage(
        id: 'a',
        label: '',
        coinAmount: 0,
        bonusCoin: 50,
        price: 1,
      );
      expect(c.bonusPercent, 0);
    });
  });

  test('formatRupiah memakai titik ribuan', () {
    expect(formatRupiah(1500000), '1.500.000');
    expect(formatRupiah(900), '900');
  });
}
