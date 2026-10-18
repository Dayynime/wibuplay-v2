import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/data/models/account_models.dart';

void main() {
  group('daysLeftFromIso', () {
    final now = DateTime.utc(2026, 10, 5, 12);

    test('dibulatkan ke bawah', () {
      expect(daysLeftFromIso('2026-10-15T11:00:00Z', now: now), 9);
      expect(daysLeftFromIso('2026-10-15T12:00:00Z', now: now), 10);
    });

    test('sudah lewat -> 0', () {
      expect(daysLeftFromIso('2026-09-01T00:00:00Z', now: now), 0);
    });

    test('kosong atau format salah -> null', () {
      expect(daysLeftFromIso(null, now: now), isNull);
      expect(daysLeftFromIso('', now: now), isNull);
      expect(daysLeftFromIso('bukan tanggal', now: now), isNull);
    });
  });

  group('formatZCoin', () {
    test('pemisah ribuan titik ala id-ID', () {
      expect(formatZCoin(0), '0');
      expect(formatZCoin(999), '999');
      expect(formatZCoin(1000), '1.000');
      expect(formatZCoin(902499), '902.499');
      expect(formatZCoin(1234567), '1.234.567');
    });
  });

  group('parsing respons server', () {
    test('PremiumStatus', () {
      final s = PremiumStatus.fromJson({'is_premium': true, 'expires_at': '2027-01-01T00:00:00Z'});
      expect(s.isPremium, isTrue);
      expect(s.expiresAt, '2027-01-01T00:00:00Z');
      expect(const PremiumStatus().isPremium, isFalse);
    });

    test('ProfileIdentity', () {
      final i = ProfileIdentity.fromJson({'zenime_code': 'ZN-DYHKT2', 'user_number': 2});
      expect(i.zenimeCode, 'ZN-DYHKT2');
      expect(i.userNumber, 2);
    });
  });
}
