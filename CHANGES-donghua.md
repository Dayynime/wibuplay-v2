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
- Link video: OK.ru (mp4 per kualitas) -> link .m3u8 langsung -> Dailymotion (HLS "Auto").
  Embed VIP (halaman HTML) belum didukung; episode yang cuma punya VIP tetap "belum tersedia".
  HLS "Auto" tidak bisa didownload.
- `/series?page=` (tab "Semua") dan `type`/`order` diasumsikan/diabaikan: sumber tidak mendokumentasikannya.
- `/schedule/__data.json` belum dipakai UI donghua.

## Perbaikan 2 (error "Respons server tidak dikenali" + lag)

- `svelte_data.dart`: dukung respons NDJSON (data di-stream SvelteKit), tipe khusus devalue
  (`Date`, `Promise`, `Set`, `Map`), dan `{"type":"redirect"}` (diikuti maks. 2x).
- Parsing JSON halaman pindah ke isolate (`Isolate.run`) -> UI/player tidak patah-patah saat memuat.
- Request halaman yang sama digabung: player tidak lagi download `watch/...` dua kali bersamaan.
- Respons HTML (diblok/sibuk) -> pesan "Sumber sedang sibuk / memblokir".
- Header video per host (`AnichinNetwork.headersFor`).
