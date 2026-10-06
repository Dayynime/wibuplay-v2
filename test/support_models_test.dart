import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/data/models/support_models.dart';

void main() {
  group('TopSupporter.fromJson', () {
    test('membaca semua field termasuk akun terhubung', () {
      final s = TopSupporter.fromJson({
        'rank': 1,
        'name': ' Rynz ',
        'avatar_url': 'https://x/a.png',
        'username_color': '#FF8800',
        'total_amount': 300000,
        'donation_count': 4,
        'is_linked': true,
      });
      expect(s.rank, 1);
      expect(s.name, 'Rynz');
      expect(s.usernameColor, '#FF8800');
      expect(s.totalAmount, 300000);
      expect(s.donationCount, 4);
      expect(s.isLinked, isTrue);
    });

    test('default aman kalau field kosong', () {
      final s = TopSupporter.fromJson({});
      expect(s.name, 'Anonim');
      expect(s.isLinked, isFalse);
      expect(s.usernameColor, isNull);
    });
  });
}
