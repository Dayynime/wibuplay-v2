/// Supabase milik Zenime (self-hosted). Wibuplay memakai backend yang sama,
/// jadi akun, chat, dan data lain nyambung dengan Zenime.
///
/// Anon key memang didesain untuk tertanam di app (sama seperti di Zenime);
/// keamanan datanya bergantung pada RLS dan Edge Function di server.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://supabase.zenime.biz.id';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzkwMTc4Njg0LCJleHAiOjE5NDc4NTg2ODR9.SH96iiwN4sQciG-8iIvO1bOFqEt58glG07z3AVYVrxE';
}
