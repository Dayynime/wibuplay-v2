# CI GitHub Actions (Flutter)

Workflow diadaptasi dari `android-workflow-template`. Kode di `lib/` dan `test/` tidak diubah.

## Cara pakai

- Push ke `main`/`master` atau buka PR: `build.yml` jalan, APK debug dan profile ada di Artifacts.
- Rilis: `git tag v1.0.1 && git push origin v1.0.1`: `release.yml` build, tanda tangan, verifikasi, publish ke GitHub Release.
- `versionCode` rilis dari versi: `1.2.3` menjadi `10203`.

## Package name (applicationId)

- applicationId Wibuplay = `com.aistudio.zenime.app` (sama dengan Zenime), diatur otomatis oleh langkah "Atur applicationId" di `build.yml` dan `release.yml`. `namespace` tetap `com.dayynime.wibuplay` (independen, tidak mempengaruhi ID app).
- Supaya bisa meng-update Zenime yang sudah terpasang: tanda tangan rilis HARUS sama dengan Zenime dan versionCode harus lebih besar dari versi Zenime terakhir (13 saat ini; `1.0.0` -> `10000` sudah lebih besar).
- APK Zenime yang beredar ditandatangani `debug.keystore` (CN=Android Debug, SHA-1 `0A:D0:D7:7C:1F:9E:63:45:28:F3:6D:E9:A7:08:B7:3F:D1:6F:EA:D3`, sudah terdaftar di Firebase). Jadi secret rilis diisi dengan debug.keystore itu: `KEYSTORE_BASE64` = `base64 -w0 debug.keystore`, `KEY_ALIAS` = `androiddebugkey`, `STORE_PASSWORD` = `android`, `KEY_PASSWORD` = `android`. `KEY_ALIAS` WAJIB diisi (default `upload` tidak cocok).
- Hanya APK dari `release.yml` yang bisa meng-update Zenime: build `build.yml` memakai versionCode = nomor run (kecil, lebih rendah dari 13) sehingga ditolak Android sebagai downgrade.
- Secret `FIREBASE_API_KEY` dan `FIREBASE_APP_ID` diambil dari google-services.json Zenime (client `com.aistudio.zenime.app`), bukan app com.dayynime.wibuplay.

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
Belum: shared element transition poster, download offline.
PiP: `android_native/MainActivity.kt` (MethodChannel `wibuplay/pip`) disalin CI menimpa MainActivity bawaan + manifest `supportsPictureInPicture`; tombol PiP di kontrol + auto-PiP saat pindah app selama video memutar. Mini player: tekan back di player -> video lanjut di kartu mengambang (geser, tap = buka lagi, play/pause, X); `lib/ui/components/mini_player.dart`.
Player ala Zenime: kecepatan putar, gesture kecerahan (kiri) / volume (kanan) lewat plugin `screen_brightness` + `volume_controller`, tombol prev/next/-10/+10, Lewati Intro, auto-skip intro/outro (default aktif), flash double-tap seek, daftar episode di fullscreen, spinner buffering saat kontrol tersembunyi.
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

### Catatan Chat Global (badge ala Zenime)

- Bubble chat: baris 1 = username > centang biru Premium > #ID; baris 2 = badge clan (rainbow animasi, `ClanRainbowBadge`) + badge level.
- Tag clan diambil batch lewat `clan_members?select=firebase_uid,clans(tag)`; Premium dicek paralel per uid lewat `zenime-check-premium` (Edge Function cuma terima satu uid per request).
- Belum: centang berwarna per role (developer/admin/moderator) dan badge role teks seperti di Zenime. Hanya centang Premium biru.


### Catatan Top Leaderboard (Beranda)

- Slide Top Leaderboard sekarang dua kolom ala Zenime: TOP XP (XP nonton bulan ini) dan TOP CLAN (urut level lalu total XP), dipisah garis vertikal, tema navy.
- Data clan: `ChatRepository.getTopClans` (`rest/v1/clans`), provider `heroTopClansProvider`. Slide tampil kalau salah satu kolom ada isinya.
- Tampilan (redesain): dua panel kaca di atas kartu navy dengan glow lembut emas/ungu; tiap baris = avatar dengan ring (emas/perak/perunggu untuk top 3) + badge rank di pojok, nama di atas, nilai emas (XP / Lv) di bawah nama. Baris disebar rata, tinggi tetap 28.
- Beda dari Zenime: tap di panel TOP XP (bukan cuma header) (ke leaderboard XP). Kolom clan belum punya halaman tujuan di Wibuplay, jadi tanpa chevron/tap. Subtitle "XP nonton bulan ini" dihapus, dan angka XP tanpa tulisan "XP".

### Catatan Hero Carousel (Beranda)

- Gaya "Poster Otomatis" ala Zenime: slide anime sekarang SATU kartu yang gambarnya ganti sendiri tiap 4,5 detik (crossfade 700ms + zoom pelan 1.0 -> 1.08), bukan satu halaman per anime. Chip views kiri atas, indikator rotasi kanan atas, peringkat `#N` + judul + `TIPE • STATUS` di tengah bawah, ikut beranimasi.
- Pager luar cuma: kartu anime, Top Leaderboard, Top Support. Rotasi berhenti saat user sedang geser atau ada di slide leaderboard/support. Gambar berikutnya di-preload (`netImageHeaders` di `net_image.dart`).
- Beda dari versi sebelumnya: tombol play berdenyut, chip genre/tahun, dan parallax dihapus (Zenime tidak punya). Dot indikator bawah sekarang bisa di-tap.

## Ikon dan splash screen Zenime

- Nama app (label) dan nama artifact/APK: `Zenime`.
- Ikon launcher (adaptive, sama dengan app Zenime) dan splash screen (latar `#0B0E14` + logo Zenime) ada di folder `android_res/`.
- Langkah "Pasang ikon dan splash Zenime" di `build.yml` dan `release.yml` menyalin `android_res/` ke `android/app/src/main/res/` setelah `flutter create`, dan menghapus `ic_launcher.png` bawaan Flutter supaya tidak bentrok dengan `ic_launcher.webp`.
- Logo di layar login: `assets/images/logo.jpg` (logo Zenime).
- Nama paket Dart (`wibuplay` di `pubspec.yaml`) dan namespace Android sengaja tidak diubah, karena hanya internal dan tidak terlihat di app.

### Catatan Splash + Intro (ala Zenime)

- Urutan buka app: IntegrityGate -> splash (`UpdateGate`, sekalian cek update) -> intro (`OnboardingGate`, sekali saja) -> login (`AuthGate`) -> app.
- Intro: 6 slide (Anime, Offline, Komik & Donghua, Chat + Clan, Level + XP, Premium) dengan background aurora, parallax, indikator, tombol bergradasi mengikuti slide, tombol "Lewati", dan back = mundur slide. File: `lib/ui/screens/onboarding/`.
- Flag `onboarding_seen_v1` di shared_preferences (`LocalStore.onboardingSeen`). User lama yang update akan melihat intro sekali karena flag belum ada.
- Splash ditahan minimal 1,8 detik (`UpdateGate.minSplash`) hanya saat intro belum pernah dilihat; buka app berikutnya tidak tertahan.

### Catatan Versi (disamakan dengan Zenime)

- Zenime terakhir: versionName `2.3`, versionCode `13`. Wibuplay mulai dari `2.3.0+13` (`pubspec.yaml`).
- Build rilis (`release.yml`) mengambil versi dari tag: `git tag v2.3.0 && git push origin v2.3.0` -> versionName `2.3.0`, versionCode `20300` (rumus major*10000 + minor*100 + patch, jauh di atas 13, jadi bisa menimpa Zenime lama). Format tag wajib x.y.z, jadi pakai `v2.3.0`, bukan `v2.3`.
- Cek update memperlakukan `2.3` dan `2.3.0` sama, jadi tidak ada loop wajib update.
- Rilis berikutnya naikkan tag (mis. `v2.4.0`); applicationId dan keystore harus sama dengan Zenime supaya APK bisa menimpa.

### Catatan Halaman Clan

- Alur: Beranda > tap panel TOP CLAN di slide leaderboard > `ClanBrowseScreen` (Semua Clan / Leaderboard / Clan Saya + cari) > tap clan > `ClanScreen` (detail).
- Detail clan: header (avatar, nama, tag rainbow, level, progress XP ke level berikut, statistik Total XP / Member / Donasi hari ini), tombol aksi sesuai relasi user (Join Clan / Menunggu Persetujuan / Sudah Gabung Clan Lain / Donasi ZCoin + Keluar Clan), tab Members (cari, filter role, urut) dan Donasi hari ini.
- Data: `ClanRepository` (`data/repository/clan_repository.dart`). Baca lewat PostgREST (`clans`, `clan_members`, `clan_donation_log`); aksi lewat Edge Function `zenime-clan-join-request`, `-donate`, `-leave`, `-my-request-status` dengan Firebase ID Token di header Authorization.
- Kelola Clan (`clan_manage_screen.dart`): tombol "Kelola Clan" muncul untuk Officer ke atas. Tab Request (terima/tolak) untuk Officer ke atas; tab Pengaturan (nama, tag 3 huruf, beli kuota member pakai saldo donasi) khusus Leader. Endpoint: `zenime-clan-pending-requests`, `-respond-request`, `-settings`, `-buy-slots`.
- Ubah role dan kick: menu titik tiga di baris member (halaman clan), hanya muncul kalau role kita boleh bertindak ke target (`ClanRoles.canActOn`). Endpoint: `zenime-clan-set-role`, `zenime-clan-kick`. Aturan izin cuma buat UI; validasi asli di server.
- Belum dipindah dari Zenime: Buat Clan, ganti foto clan (butuh image picker + upload), centang role global di list member (cuma centang Premium). Rumus XP per level clan perkiraan (sama seperti Zenime).
- Belum ada tombol ke halaman Clan selain dari panel TOP CLAN di Beranda.

### Catatan Bubble Chat Global

- Lebar bubble sekarang tetap (270dp seperti Zenime, `_kBubbleMaxWidth` di `chat_screen.dart`), jadi semua bubble seragam apa pun panjang pesannya. Di layar sempit otomatis dikecilkan. Kutipan balasan ikut selebar bubble.
- Bubble sendiri memakai warna yang sama dengan bubble orang lain (`surfaceCard`); bedanya cuma posisi (kanan) dan tanpa avatar.

### Catatan Migrasi Data Zenime (Room -> Wibuplay)

- Zenime (Kotlin) menyimpan favorit, riwayat tonton, dan data download di Room `databases/zenime_database` (v5); Wibuplay (Flutter) memakai shared_preferences. Karena applicationId sama, saat Wibuplay meng-update Zenime file Room itu masih ada tapi dulu tidak terbaca, sehingga riwayat/favorit tampak hilang.
- `lib/data/local/zenime_room_migration.dart` (dipanggil di `main.dart` setelah `LocalStore.open()`) mengimpor sekali: `favorites`, `watch_history`, `downloaded_episodes` (via `sqflite`, hanya SELECT). Data yang sudah ada di Wibuplay tidak ditimpa. DB Room tidak diubah/dihapus. Flag `zenime_room_migrated_v1` baru ditulis kalau pembacaan sukses.
- File video download Zenime ada di `getExternalFilesDir(MOVIES)/<animeId>/<episodeId>.mp4` (app-private) dan ikut bertahan saat update; metadatanya diimpor ke `LocalStore.downloads`.
- Data hanya bertahan kalau APK meng-UPDATE (applicationId sama + tanda tangan sama + versionCode lebih besar). Kalau Android menolak update dan user harus uninstall dulu, semua data lokal ikut terhapus. Pakai hanya APK dari `release.yml` dengan keystore Zenime.

### Download Offline (khusus Premium)

- Port EpisodeDownloadManager Zenime: `lib/data/download/episode_download_manager.dart` + MethodChannel `wibuplay/download` di `android_native/MainActivity.kt` (android.app.DownloadManager sistem; tetap jalan walau app di-swipe, ada notifikasi bawaan).
- File: `getExternalFilesDir(MOVIES)/<animeId>/<episodeId>.mp4`, sama dengan Zenime. Batas 15 episode offline (`kMaxActiveDownloads`).
- Gating: HANYA memulai download baru yang khusus Premium (`isDownloadAllowed` di `core/premium_access.dart`; non-premium dapat ajakan Premium di Detail). Melihat daftar Download, memutar file offline (tanpa cek Premium/kunci episode, jalan juga tanpa internet), dan menghapus download terbuka untuk semua user.
- UI: ikon download di tiap item Daftar Episode (Detail), halaman Download (Profil > ikon gear Pengaturan > Download), pemutaran offline lewat server "Offline" di player (fallback ke file lokal kalau stream gagal / tidak ada internet).
- Beranda saat gagal memuat (offline) dan ada download tersimpan: menampilkan daftar "Video yang sudah didownload" bergaya feed YouTube yang bisa langsung diputar (`ui/screens/download/offline_downloads_view.dart`, port fallback HomeScreen Zenime).

### Pengaturan (port Zenime)

- Halaman `ui/screens/profile/settings_screen.dart` (ikon gear di Profil): kartu Akun (profil + keluar, status Premium AKTIF/BELUM AKTIF + sisa hari, ZCoin, Chat Global), Pemutaran Video (Kualitas Video Default 1080p/720p/480p/360p, Lewati Intro Otomatis, Auto-Lanjut Episode), Download, Bersihkan Cache, Tentang Aplikasi (logo, versi dari package_info_plus).
- Kualitas default disimpan di `LocalStore.defaultQuality` dan dipakai `PlayerController` untuk memilih server awal.
- Tidak diport: Mode Tema / Dynamic Color (warna Wibuplay hard-coded gelap, desain tidak boleh berubah), Tampilan Beranda (hero carousel, sengaja dilewati), Panel Admin (belum ada di Wibuplay).

### Palet Warna (Zenime Crimson Dark)

- Palet Wibuplay sekarang = palet Zenime: aksen crimson `#E4344A` di atas navy `#0B0E14` (surface `#151A23`, variant `#1C222E`, teks `#F5F5F7` / `#9AA0AC`). Semua ada di `lib/core/theme/app_colors.dart`; nama `accentViolet*` dipertahankan tapi nilainya crimson.
- Warna hard-coded di layar (gradien login/update/pengumuman, latar overlay, dll.) sudah dipetakan ke palet yang sama. Warna semantik (badge role, badge game, biru Google/Instagram, pilihan warna username) sengaja tidak diubah.
- Splash/launch native (`android_res/values-v31/styles.xml`, `drawable*/launch_background.xml`) memakai `#0B0E14`.
- Tema tidak bisa diganti saat runtime: warna dipakai sebagai `const` di ratusan tempat, jadi ganti palet = ubah `app_colors.dart` lalu build ulang.

### Detail Anime (layout Zenime)

- `ui/screens/detail/detail_screen.dart`: hero cover penuh 360dp (judul, metadata, tombol favorit/bookmark, tombol play crimson bulat = lanjut episode terakhir atau episode pertama), baris 6 tab Info | Episode | Season | Cuplix | Cover | Poster (swipe kiri/kanan untuk pindah tab), daftar episode grid 3 kolom (nomor di pojok kanan bawah, bingkai untuk episode terakhir ditonton, gembok Premium, badge download, pita NEW).
- Download episode: tekan lama kartu episode (khusus Premium; tekan lama pada episode yang sudah didownload = hapus).
- Tab Season memakai `AnimeRepository.getSeasons` (daftar season dari respons detail). Rating bintang "4.8" Zenime tidak diport karena angkanya hard-coded, bukan data asli.
- Section "Lanjutkan Menonton" di Beranda dihapus (riwayat tonton tetap tersimpan dan tampil di Profil).

## Keamanan dan fix bug (port dari Zenime)

- **IntegrityGuard** (`lib/core/integrity_guard.dart` + channel `wibuplay/security` di `MainActivity.kt`): blokir app kalau terdeteksi (1) tanda tangan APK beda dari yang resmi, (2) app proxy/MITM (Reqable, HTTP Toolkit, dll). Deteksi auto clicker sudah dihapus. Dicek di `IntegrityGate` (`ui/screens/security/integrity_gate.dart`) SEBELUM init Firebase/Remote Config, jadi tidak ada request jaringan kalau kedeteksi; dicek lagi tiap app balik ke foreground.
- **Cek tanda tangan**: `release.yml` menghitung SHA-256 sertifikat dari keystore rilis lalu mengirimnya lewat `--dart-define=APK_SIG_SHA256`. Build `build.yml` (debug/profile) tidak mengisinya, jadi cek tanda tangan dilewati (tidak ke-block). Butuh `KEY_ALIAS` dan `STORE_PASSWORD` benar di secret.
- **Cache status Premium** (`lib/data/local/premium_status_cache.dart`): fallback saat cek live gagal karena jaringan (offline/timeout/5xx). Ditandatangani HMAC (key AndroidKeyStore), terikat uid, TTL 3 hari, dan mati kalau `expires_at` lewat. Penolakan server (4xx) tidak memakai cache. Dihapus saat logout.
- **Manifest** (patch di workflow): `allowBackup=false`, cleartext HTTP hanya untuk host di `android_res/xml/network_security_config.xml` (bukan global lagi), `<queries>` untuk deteksi app lain. Catatan: aturan ini berlaku untuk video_player/ExoPlayer; Dio (dart:io) tidak terpengaruh.
- **Fix jaringan lemot (WiFi/Indihome)**: retry GET sekarang juga untuk connect timeout (jeda 300ms), connectTimeout API utama 10 detik (sama Zenime). Tidak dipindah: tuning buffer/timeout ExoPlayer (`PlayerConfig.kt`), karena plugin video_player tidak membuka opsi itu.
- **Log**: semua `debugPrint` dibungkus `kDebugMode`, tidak ada log di release.
