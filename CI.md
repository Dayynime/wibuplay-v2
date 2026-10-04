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
pengganti Room), Beranda lengkap (hero banner, Lanjutkan Menonton, Top Hits, Favorit, Episode Baru,
Jadwal Hari Ini, Populer, Mungkin Kamu Suka), bottom bar melayang.
Belum: Jelajah, Jadwal, Cuplix, Profil, Detail, Player, shared element transition poster.
Drift/build_runner diganti shared_preferences supaya tidak butuh codegen.
