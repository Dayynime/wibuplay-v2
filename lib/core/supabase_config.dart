/// Supabase milik Zenime (self-hosted). Versi Flutter ini memakai backend yang sama,
/// jadi akun, chat, dan data lain nyambung dengan Zenime.
///
/// Anon key memang didesain untuk tertanam di app (sama seperti di Zenime);
/// keamanan datanya bergantung pada RLS dan Edge Function di server.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://supabase.zenime.biz.id';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzkwMTc4Njg0LCJleHAiOjE5NDc4NTg2ODR9.SH96iiwN4sQciG-8iIvO1bOFqEt58glG07z3AVYVrxE';

  // Halaman pembayaran (storefront) Zenime, dibuka di browser dengan kode akun
  // + id paket sebagai query. QRIS = otomatis, "manual" = pembeli luar negeri
  // yang diverifikasi admin.
  static const String premiumStorefrontUrl = 'https://zenime.biz.id/beli-premium';
  static const String premiumManualStorefrontUrl = 'https://zenime.biz.id/bayar-manual';
  static const String coinStorefrontUrl = 'https://zenime.biz.id/top-up-coin';
  static const String coinManualStorefrontUrl = 'https://zenime.biz.id/coin-bayar-manual';

  // Halaman donasi ("Dukung Kami", bayar QRIS via Aulaa). Kode akun dikirim
  // lewat query `code` supaya kolom Kode Zenime langsung terisi.
  static const String donationStorefrontUrl = 'https://zenime.biz.id/donasi';
}
