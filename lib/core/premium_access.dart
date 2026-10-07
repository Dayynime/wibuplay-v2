/// Port PremiumAccess.kt (bagian kunci episode). Jumlah episode TERBARU
/// (index paling tinggi) yang dikunci buat non-premium.
const int kLockedLatestEpisodesCount = 3;

/// Ekstrak angka dari index episode, misal "12" -> 12.
int? episodeIndexValue(String? episodeIndex) {
  if (episodeIndex == null) return null;
  final direct = int.tryParse(episodeIndex.trim());
  if (direct != null) return direct;
  final m = RegExp(r'\d+').firstMatch(episodeIndex);
  return m == null ? null : int.tryParse(m.group(0)!);
}

/// Index tertinggi dari daftar episode = total episode. 0 kalau tidak ada
/// index yang terbaca (dianggap belum diketahui -> tidak ada yang dikunci).
int latestEpisodeIndex(Iterable<String?> episodeIndexes) {
  var best = 0;
  for (final raw in episodeIndexes) {
    final v = episodeIndexValue(raw);
    if (v != null && v > best) best = v;
  }
  return best;
}

/// Cuma [kLockedLatestEpisodesCount] episode paling baru yang dikunci buat
/// non-premium. Index tak terbaca atau total belum diketahui (<= 0) dianggap
/// TIDAK terkunci, daripada salah kunci gara-gara data belum siap.
bool isEpisodeLocked(String? episodeIndex, int totalEpisodes, bool isPremium) {
  if (isPremium) return false;
  if (kLockedLatestEpisodesCount <= 0) return false;
  if (totalEpisodes <= 0) return false;
  final value = episodeIndexValue(episodeIndex);
  if (value == null) return false;
  return value > totalEpisodes - kLockedLatestEpisodesCount;
}

/// Kualitas maksimal (dalam "p") yang boleh diputar non-premium, sama dengan
/// Zenime. Isi 0 (atau negatif) kalau mau semua kualitas terbuka untuk semua.
const int kNonPremiumMaxQualityP = 480;

/// Ekstrak angka resolusi dari label kualitas, misal "1080p" -> 1080.
int? qualityValueP(String? quality) {
  final m = RegExp(r'\d+').firstMatch(quality ?? '');
  return m == null ? null : int.tryParse(m.group(0)!);
}

/// Terkunci cuma kalau angkanya kebaca DAN di atas batas. Label tanpa angka
/// (mis. "HD", "Auto") dibiarkan lolos daripada salah kunci.
bool isQualityLocked(String? quality, bool isPremium) {
  if (isPremium) return false;
  if (kNonPremiumMaxQualityP <= 0) return false;
  final v = qualityValueP(quality);
  if (v == null) return false;
  return v > kNonPremiumMaxQualityP;
}

/// Download untuk nonton offline KHUSUS Premium (port isDownloadAllowed):
/// non-premium tidak boleh download episode apa pun, juga tidak memutar file
/// offline dan tidak membuka tab Download.
bool isDownloadAllowed(bool isPremium) => isPremium;

/// Batas episode offline bersamaan (selesai + sedang jalan), murni proteksi
/// storage dan sama untuk semua user Premium (sama dengan Zenime).
const int kMaxActiveDownloads = 15;
