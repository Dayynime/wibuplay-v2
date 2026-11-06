import '../../core/supabase_config.dart';

// Stiker dikirim di chat/komentar sebagai teks "[stiker:KODE]" lewat fungsi
// chat yang sudah ada. App mengenali pesan yang ISINYA HANYA token itu lalu
// menampilkan gambar stiker (kalau kodenya ada di katalog yang disetujui).
// App versi lama tetap melihat teksnya.

final RegExp _stickerRe = RegExp(r'^\s*\[stiker:([A-Za-z0-9]{8})\]\s*$');

/// Kode stiker kalau [text] adalah pesan stiker, selain itu null.
String? stickerCodeOf(String text) => _stickerRe.firstMatch(text)?.group(1);

/// Teks pesan untuk mengirim stiker [code].
String stickerMessage(String code) => '[stiker:$code]';

/// Teks pratinjau (balasan, daftar chat): "🖼️ Stiker" untuk pesan stiker.
String stickerPreviewText(String text) => stickerCodeOf(text) != null ? '🖼️ Stiker' : text;

String _publicUrl(String path) => '${SupabaseConfig.url}/storage/v1/object/public/stickers/$path';

/// Stiker di katalog publik (sudah disetujui).
class Sticker {
  const Sticker({required this.code, required this.name, required this.path, this.pack});

  final String code;
  final String name;
  final String path;

  /// Nama pack (null = "Lainnya").
  final String? pack;

  String get url => _publicUrl(path);

  factory Sticker.fromJson(Map<String, dynamic> j) => Sticker(
        code: (j['code'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        path: (j['path'] as String?) ?? '',
        pack: _packOf(j['pack']),
      );
}

/// Label tab untuk stiker tanpa pack.
const String kStickerNoPack = 'Lainnya';

String? _packOf(Object? v) {
  final s = (v as String?)?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// Status stiker milik sendiri.
class MySticker {
  const MySticker({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    this.path,
    this.rejectReason,
    this.pack,
  });

  final String id;
  final String code;
  final String name;
  final String? pack;

  /// pending | approved | rejected | removed
  final String status;
  final String? path;
  final String? rejectReason;

  String? get url => path == null ? null : _publicUrl(path!);

  factory MySticker.fromJson(Map<String, dynamic> j) => MySticker(
        id: (j['id'] as String?) ?? '',
        code: (j['code'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'pending',
        path: j['path'] as String?,
        rejectReason: j['reject_reason'] as String?,
        pack: _packOf(j['pack']),
      );
}

/// Stiker di antrean review admin.
class AdminSticker {
  const AdminSticker({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.uploaderUid,
    required this.uploaderName,
    this.sizeBytes,
    this.previewUrl,
    this.path,
    this.rejectReason,
    this.pack,
  });

  final String id;
  final String code;
  final String name;
  final String status;
  final String? pack;
  final String uploaderUid;
  final String uploaderName;
  final int? sizeBytes;

  /// Signed URL relatif (file staging, khusus antrean pending).
  final String? previewUrl;
  final String? path;
  final String? rejectReason;

  /// URL gambar untuk ditampilkan di panel admin (null = file sudah tidak ada).
  String? get imageUrl {
    if (previewUrl != null && previewUrl!.isNotEmpty) {
      return previewUrl!.startsWith('http') ? previewUrl : '${SupabaseConfig.url}$previewUrl';
    }
    if (status == 'approved' && path != null) return _publicUrl(path!);
    return null;
  }

  factory AdminSticker.fromJson(Map<String, dynamic> j) => AdminSticker(
        id: (j['id'] as String?) ?? '',
        code: (j['code'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'pending',
        uploaderUid: (j['uploader_uid'] as String?) ?? '',
        uploaderName: (j['uploader_name'] as String?) ?? 'Pengguna',
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
        previewUrl: j['preview_url'] as String?,
        path: j['path'] as String?,
        rejectReason: j['reject_reason'] as String?,
        pack: _packOf(j['pack']),
      );
}
