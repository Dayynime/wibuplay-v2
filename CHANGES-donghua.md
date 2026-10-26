# Wibuplay v2: donghua langsung ke v1.anichin.space (meniru web anichin-web)

Timpa file berikut ke proyek (path sama):

| File | Perubahan |
| --- | --- |
| `lib/data/api/svelte_data.dart` | BARU. Decoder `__data.json` SvelteKit (port `unpack_svelte` dari scraper) |
| `lib/data/api/anichin_network.dart` | Base URL tetap `https://v1.anichin.space/` (TESTING, tanpa Remote Config); token Premium ditempel ke `watch/...` |
| `lib/data/repository/anichin_repository.dart` | Ditulis ulang: baca endpoint web langsung, petakan ke model lama (UI tidak berubah) |
| `lib/providers.dart` | `createAnichinDio(premiumTokenManager)` (sama seperti ori) |
| `test/svelte_data_test.dart`, `test/anichin_repository_test.dart` | BARU |

## Endpoint yang dipakai (relatif ke base URL)

| App memanggil | Endpoint sumber |
| --- | --- |
| Beranda | `__data.json` (latestEpisodes, popularSeries) + `api/trending` |
| Cari | `api/search?q=` |
| Ongoing / Completed | `ongoing/__data.json?page=` , `completed/__data.json?page=` |
| Semua | `series/__data.json?page=` |
| Genre | `genres/__data.json` , `series/__data.json?genre=&page=` |
| Detail | `series/<slug>/__data.json` |
| Episode | `watch/<slug>/__data.json` |
| Link video | embed dari `watch/...` -> OK.ru `POST https://ok.ru/dk` (metadata) |

Jalankan: `flutter pub get && flutter analyze && flutter test`
(belum dijalankan: kode ditulis tanpa Flutter SDK).

## Catatan

- Remote Config `anichin_base_url` TIDAK dibaca dan JANGAN diubah: app versi publik masih memakainya.
  Saat rilis, pindahkan base URL ke parameter baru (mis. `donghua_base_url`).
- Token Premium dikembalikan: ditempel (header `Authorization: Bearer`) ke request `watch/<slug>/...`
  ke host v1.anichin.space saja, tidak ke OK.ru. 401 -> token diambil ulang lalu coba sekali lagi.
  Token hanya berguna kalau server di host itu memang memeriksanya.
- Link video: OK.ru (mp4 per kualitas) -> VIP `rmb.anichin.bio/hls/<id>.m3u8` -> link .m3u8 langsung
  -> Dailymotion (HLS "Auto"). Header Referer disesuaikan per host.
  HLS "Auto" tidak bisa didownload.
- `/series?page=` (tab "Semua") dan `type`/`order` diasumsikan/diabaikan: sumber tidak mendokumentasikannya.
- `/schedule/__data.json` belum dipakai UI donghua.

## Perbaikan 2 (error "Respons server tidak dikenali" + lag)

- `svelte_data.dart`: dukung respons NDJSON (data di-stream SvelteKit), tipe khusus devalue
  (`Date`, `Promise`, `Set`, `Map`), dan `{"type":"redirect"}` (diikuti maks. 2x).
- (Dibatalkan) parsing di isolate; data cuma <50 KB, parse langsung.
- Request halaman yang sama digabung: player tidak lagi download `watch/...` dua kali bersamaan.
- Respons HTML (diblok/sibuk) -> pesan "Sumber sedang sibuk / memblokir".
- Header video per host (`AnichinNetwork.headersFor`).

## Perbaikan 3 (lewat server cache VPS)

- Base URL donghua: `https://api.zenime.biz.id/app-api/` (anichin-web/app_api.py di VPS,
  service `anichin-api` port 8090, Caddy `handle /app-api/*`). Path & isi JSON sama dengan sumber.
- Token Premium tetap dikirim ke `watch/...` (host VPS); server mengeceknya kalau env
  `PREMIUM_TOKEN_SECRET` diisi.

## Perbaikan 4 (server VIP)

- Embed VIP `rmb.anichin.bio/?id=<id>` -> `https://rmb.anichin.bio/hls/<id>.m3u8` (master HLS, video di CDN Rumble).
- Master HLS (VIP / m3u8 / Dailymotion) dipecah per varian -> pilihan 360p/480p/720p/1080p,
  batas 480p non-premium tetap berlaku. Gagal dibaca -> "Auto".
- HLS tidak bisa didownload (bukan file mp4).

## Diagnosa sementara (X-App-Timing)

- App mencatat lama tiap langkah donghua (token, jaringan, parse, OK.ru/HLS, total detail/video)
  dan mengirimnya ke VPS lewat header `X-App-Timing` pada request `health` (3 dtk setelah langkah terakhir).
  Terbaca di log Caddy. Hapus `AnichinTiming` & `_TimingInterceptor` setelah masalah ketemu.
