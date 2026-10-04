# CI GitHub Actions (Flutter)

Workflow diadaptasi dari `android-workflow-template`. Kode di `lib/` dan `test/` tidak diubah.

## Cara pakai

- Push ke `main`/`master` atau buka PR: `build.yml` jalan, APK debug dan profile ada di Artifacts.
- Rilis: `git tag v1.0.1 && git push origin v1.0.1`: `release.yml` build, tanda tangan, verifikasi, publish ke GitHub Release.
- `versionCode` rilis dari versi: `1.2.3` menjadi `10203`.

## Beda dengan template Gradle

- Build type `perf` diganti `flutter build apk --profile` (AOT, ditandatangani debug key).
- Tidak perlu snippet `build.gradle.kts`: APK rilis ditandatangani ulang pakai `apksigner` di CI.
- Folder `android/` dibuat otomatis oleh CI kalau belum ada.

## Secrets GitHub (hanya untuk release.yml)

Settings > Secrets and variables > Actions:

| Secret | Isi |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 my-upload-key.jks` |
| `STORE_PASSWORD` | password keystore |
| `KEY_PASSWORD` | password key |
| `KEY_ALIAS` | opsional, default `upload` |

## Status port Flutter (dari Kotlin wibuplay-main)

Sudah: tema, model + JsonHelper, ApiService, Dio, repository, penyimpanan lokal (favorit + riwayat tonton,
pengganti Room), Beranda lengkap, bottom bar melayang, Detail (3 tab, favorit, tonton), Player
(video_player, kontrol, seek, fullscreen, server/kualitas, auto-next, simpan progres, resume, bagikan).
Jelajah (cari, filter, urutan, genre, scroll tak terbatas) dan Jadwal (per hari) juga sudah.
Cuplix (feed vertikal, pemutaran per halaman dengan loop time_start..time_end, prefetch + cache URL stream,
suka, bagikan, tombol tonton penuh, paginasi kursor, error/retry) dan Profil (header, tab Favorit / Riwayat /
Pengaturan, hapus satu item, hapus semua riwayat dengan dialog) sudah, tersambung ke tab 3 dan 4 di app_shell.
Belum: shared element transition poster, gesture kecerahan/volume di fullscreen (butuh plugin tambahan).
Drift/build_runner diganti shared_preferences supaya tidak butuh codegen.
CI menambal AndroidManifest hasil flutter create (INTERNET, cleartext, nama app) karena
manifest rilis bawaan Flutter tidak punya izin internet.

### Catatan Cuplix dan Profil (beda dari Kotlin)

- Cuplix: pemutar dilepas saat tab lain dibuka, saat Detail/Player menutupi layar (RouteObserver di
  `lib/ui/route_observer.dart`, didaftarkan di `main.dart`), dan saat app ke background. Kotlin tidak menangani background.
- Cuplix: muat-lanjut tidak jalan kalau muat sebelumnya masih berlangsung (di Kotlin dua muat bersamaan bisa
  menandai feed habis terlalu cepat). Permintaan stream untuk episode yang sama dibagi, tidak dobel.
- Cuplix: Kotlin selalu memakai `scroll_likes` dan tidak punya UI urutan. `CuplixController.setSort()` ada tapi belum dipanggil UI.
- Cuplix: suka hanya di memori (hilang saat app ditutup) dan tombol komentar belum ada aksi, sama seperti Kotlin.
- Profil: "Bersihkan Cache Memori" di Kotlin hanya Toast; di Flutter mengosongkan cache gambar di memori (cache disk tidak disentuh).
- Profil: nama "Wibu Sejati" dan badge "VIP Member" masih tetap (hardcode), sama seperti Kotlin.
