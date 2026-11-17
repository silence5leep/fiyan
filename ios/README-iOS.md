# Aplikasi iOS SIAKAD SMK PGRI 1 Ponorogo

Proyek Xcode lengkap (SwiftUI + WKWebView) untuk **https://siakad.smkpgri1po.sch.id/admin/login**,
dengan fitur yang sama seperti versi Android.

> **Penting:** aplikasi iOS **tidak bisa dikompilasi di Windows**. Kompilasi, tanda tangan,
> dan pemasangan ke iPhone memerlukan macOS/Xcode **atau** GitHub Actions (macOS) seperti
> dijelaskan di bawah. Di folder ini semua kode dan aset sudah siap; tidak ada yang perlu
> ditulis ulang.

---

## 1. Isi proyek

```
ios/
├── SIAKAD/
│   ├── SIAKADApp.swift                  # @main SwiftUI + pembungkus UIViewController
│   ├── MainWebViewController.swift      # WKWebView, splash, error, upload, download, tautan
│   ├── Info.plist                       # nama, portrait, launch screen, izin skema
│   └── Assets.xcassets/
│       ├── AppIcon.appiconset/          # ikon 20–1024 px (tanpa alpha, siap App Store)
│       ├── LaunchLogo.imageset/         # logo resmi 116/232/348 px
│       └── LaunchBackground.colorset/   # latar putih launch screen
├── project.yml                          # spesifikasi XcodeGen
├── .gitignore
└── README-iOS.md                        # dokumen ini

.github/workflows/ios-build.yml          # CI: kompilasi + hasilkan IPA tanpa tanda tangan
tools/make-ios-assets.js                 # generator ulang ikon/logo dari assets/favicon.png
```

Identitas aplikasi:

| Item | Nilai |
|---|---|
| Nama tampilan | SIAKAD (subjudul splash: SMK PGRI 1 Ponorogo) |
| Bundle ID | `id.sch.smkpgri1po.siakad` |
| Versi | 1.3 (build 4) |
| Minimum iOS | 14.0 |
| Perangkat | iPhone, portrait, mode terang |
| Bahasa | Indonesia |

---

## 2. Fitur (setara Android)

| Fitur Android | Implementasi iOS |
|---|---|
| Splash logo resmi + indikator | `UILaunchScreen` + overlay splash (min. 0,8 dtk, jaring pengaman 6 dtk) |
| Ikon launcher multi-densitas | `AppIcon.appiconset` 20–1024 px dari logo resmi |
| Login WebView (cookie/session/JS) | `WKWebView` + `WKWebsiteDataStore.default()` |
| Tombol Back | tombol ← di toolbar + gestur geser dari tepi kiri |
| Indikator progres | `UIProgressView` mengikuti `estimatedProgress` |
| Halaman "Coba Lagi" saat offline | tampilan error native + tombol muat ulang |
| Unggah berkas/foto | pemilih **Galeri** (PHPicker, tanpa izin) dan **Berkas** (Files/iCloud) |
| Unduhan PDF/Excel | `WKDownload` → `Documents/Downloads`, lalu sheet Bagikan/Simpan |
| WhatsApp/telepon/email/peta | dibuka di aplikasi lain; domain lain ke browser |
| Hanya domain sekolah di dalam app | validasi host pada setiap navigasi |
| Portrait | `UISupportedInterfaceOrientations` + override di view controller |
| Tarik untuk muat ulang | `UIRefreshControl` |

Perbedaan yang wajar antarplatform:
- iOS tidak punya tombol Back fisik; diganti tombol toolbar dan gestur geser.
- Unggah foto memakai Galeri/Files (iOS tidak membuka kamera langsung dari input file;
  foto bisa diambil lewat aplikasi Kamera lalu dipilih dari Galeri).
- Unduhan disimpan di folder aplikasi dan bisa dibagikan/disimpan ke Files; bukan folder
  "Downloads" publik seperti Android.

---

## 3. Cara tercepat tanpa Mac

### Opsi A — PWA (5 menit, tanpa Apple ID)
1. Buka `https://siakad.smkpgri1po.sch.id/admin/login` di **Safari** (bukan Chrome).
2. Ketuk **Bagikan** → **Tambahkan ke Layar Utama**.
3. Ikon SIAKAD muncul dan terbuka layar penuh.

Ini bukan aplikasi asli (tidak ada splash/unduhan native), tetapi paling cepat.

### Opsi B — Build di GitHub Actions + pasang lewat Windows
1. Buat repositori GitHub, unggah folder `AndroidBuild` (termasuk `.github/` dan `ios/`).
2. Buka tab **Actions** → **iOS Build (unsigned IPA)** → **Run workflow**.
3. Setelah ±5–10 menit, unduh artefak **SIAKAD-unsigned-ipa** (`SIAKAD-unsigned.ipa`).
4. Di Windows, pasang [Sideloadly](https://sideloadly.io/) (butuh iTunes/Apple Devices dari
   Microsoft Store agar driver iPhone terpasang).
5. Sambungkan iPhone, buka Sideloadly, seret `SIAKAD-unsigned.ipa`, masukkan **Apple ID**
   biasa (gratis), klik **Start**.
6. Di iPhone: **Pengaturan → Umum → VPN & Manajemen Perangkat → Trust** akun Apple ID Anda.
7. iOS 16+: aktifkan **Pengaturan → Privasi & Keamanan → Mode Pengembang**, lalu buka aplikasi.

Konsekuensi Apple ID gratis:
- aplikasi berlaku **7 hari**, lalu harus di-*sign* ulang;
- maksimal ±3 aplikasi aktif per akun;
- tidak perlu mendaftarkan UDID, tidak perlu bayar.

> Apple ID akun iCloud Anda bisa dipakai; gunakan sandi aplikasi bila diminta.

---

## 4. Build di macOS (Xcode)

### Prasyarat
- macOS 12+ dengan **Xcode 15+** (Xcode dari App Store).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
  (opsional; bisa juga membuat proyek manual, lihat 4b).

### 4a. Memakai XcodeGen (disarankan)

```bash
cd ios
xcodegen generate
open SIAKAD.xcodeproj
```

Di Xcode:
1. Pilih target **SIAKAD** → tab **Signing & Capabilities**.
2. Centang **Automatically manage signing**.
3. **Team**: pilih Apple ID Anda (tambahkan lewat Xcode → Settings → Accounts bila belum ada).
4. Ganti **Bundle Identifier** bila `id.sch.smkpgri1po.siakad` sudah dipakai akun lain,
   misalnya `id.sch.smkpgri1po.siakad2`.
5. Sambungkan iPhone (atau pilih simulator), tekan **Run** (⌘R).
6. iPhone: **Pengaturan → Umum → VPN & Manajemen Perangkat → Trust** developer.

### 4b. Membuat proyek manual (tanpa XcodeGen)

1. Xcode → **File → New → Project → iOS → App**.
2. Product Name `SIAKAD`, Interface **SwiftUI**, Language **Swift**.
3. Hapus `ContentView.swift` dan `SIAKADApp.swift` bawaan.
4. Seret `ios/SIAKAD/SIAKADApp.swift`, `MainWebViewController.swift`, dan
   `Assets.xcassets` ke proyek (centang *Copy items if needed* → **jangan** centang,
   pilih *Create groups*).
5. Target → **Build Settings**:
   - `Info.plist File` → `SIAKAD/Info.plist`
   - `Asset Catalog App Icon Set Name` → `AppIcon`
   - `iOS Deployment Target` → `14.0`
   - `Targeted Device Family` → `1` (iPhone)
   - `Marketing Version` → `1.3`, `Current Project Version` → `4`
6. Hapus `UILaunchStoryboardName`/`UILaunchScreen` bawaan bila bentrok; file
   `Info.plist` di folder ini sudah benar.
7. Signing & Capabilities → pilih Team → Run.

### 4c. Menghasilkan IPA bertanda tangan

- **Development (langsung ke iPhone):** Product → **Run**, atau Product → **Archive** →
  **Distribute App → Development**.
- **TestFlight / App Store:** perlu **Apple Developer Program** (US$99/tahun).
  Product → **Archive** → **Distribute App → App Store Connect**, lalu undang penguji
  lewat TestFlight (build berlaku 90 hari).

---

## 5. Catatan App Store

Aplikasi ini membungkus situs SIAKAD. Apple menolak aplikasi yang hanya "website dalam
kotak" bila tidak ada nilai tambah (pedoman **4.2 Minimum Functionality**). Peluang lolos
lebih besar bila:
- diajukan oleh **sekolah resmi** dan situsnya memang layanan inti sekolah;
- deskripsi menegaskan aplikasi resmi SIAKAD SMK PGRI 1 Ponorogo;
- fitur native (splash, unduhan, unggah, navigasi) dijelaskan di catatan peninjauan;
- akun demo untuk peninjau disertakan.

Untuk distribusi internal sekolah, TestFlight atau pemasangan langsung lebih praktis
daripada menunggu review App Store.

---

## 6. Kustomisasi

| Yang diubah | Lokasi |
|---|---|
| URL awal | `MainWebViewController.swift` → `Config.startURL` |
| Domain yang diizinkan | `MainWebViewController.swift` → `Config.allowedHost` |
| Nama aplikasi | `Info.plist` → `CFBundleDisplayName`, `project.yml` → `PRODUCT_NAME` |
| Bundle ID | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` |
| Versi | `project.yml` → `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` |
| Warna brand | `MainWebViewController.swift` → `Palette` |
| Ikon/logo | ganti `assets/favicon.png` lalu jalankan `node tools/make-ios-assets.js` |

Bila domain berubah, ubah **dua** nilai di atas agar tautan tetap terbuka di dalam aplikasi.

---

## 7. Keamanan

- Hanya `https` dan domain sekolah yang dimuat di dalam aplikasi; domain lain dibuka di
  browser, dan skema berbahaya (`file:`, `javascript:`) diblokir.
- Validasi sertifikat TLS **tidak** dimatikan. Tidak ada `allowsArbitraryLoads` global.
- `NSAllowsArbitraryLoadsInWebContent` hanya mengizinkan konten http di dalam WebView
  (padanan mode mixed-content Android) — koneksi utama tetap https.
- Tidak ada izin kamera, mikrofon, kontak, atau lokasi. Foto dipilih lewat pemilih sistem
  (PHPicker) yang tidak memerlukan izin.
- Unduhan disimpan di sandbox aplikasi (`Documents/Downloads`), bukan di penyimpanan bebas.
- Tidak ada data login yang disimpan sendiri; sesi dikelola cookie WKWebView.

---

## 8. Checklist pengujian setelah terpasang

- [ ] Splash logo muncul lalu halaman login termuat.
- [ ] Login berhasil dan sesi bertahan setelah aplikasi ditutup-buka.
- [ ] Tombol ← / gestur geser kembali ke halaman sebelumnya.
- [ ] Tarik ke bawah memuat ulang halaman.
- [ ] Matikan internet → muncul "Coba Lagi" → nyalakan internet → tombol berfungsi.
- [ ] Unggah foto dari Galeri pada formulir SIAKAD.
- [ ] Unggah PDF dari Files.
- [ ] Unduh PDF/Excel → muncul sheet Bagikan → simpan ke Files.
- [ ] Tautan WhatsApp/telepon terbuka di aplikasi lain.
- [ ] Rotasi perangkat tidak mengubah orientasi (tetap portrait).

---

## 9. Pemecahan masalah

| Gejala | Penyebab & solusi |
|---|---|
| "Untrusted Developer" | Pengaturan → Umum → VPN & Manajemen Perangkat → Trust akun Anda |
| "Unable to Install" / "requires a newer version" | iPhone lebih lama dari iOS 14; turunkan deployment target di `project.yml` dan Info.plist (mis. 13.0) — beberapa API perlu disesuaikan |
| Aplikasi hilang setelah 7 hari | Batas Apple ID gratis; sign ulang dengan Sideloadly/AltStore |
| Sideloadly: "App ID tidak tersedia" | Bundle ID sudah dipakai akun lain; ubah `PRODUCT_BUNDLE_IDENTIFIER` di `project.yml`, jalankan CI lagi, lalu pasang IPA yang baru |
| "Developer Mode disabled" (iOS 16+) | Pengaturan → Privasi & Keamanan → Mode Pengembang → aktifkan → restart |
| Build gagal: `No such module 'PhotosUI'` | Deployment target < 14.0; naikkan ke 14.0 |
| Build gagal: `Signing for "SIAKAD" requires a development team` | Pilih Team di Signing & Capabilities, atau build dengan `CODE_SIGNING_ALLOWED=NO` untuk CI |
| Ikon tidak muncul | Pastikan `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` dan `AppIcon.appiconset` ikut target |
| Halaman putih terus | Periksa koneksi; server hanya mendukung TLS 1.1+ (iOS 14 sudah mendukung TLS 1.2/1.3) |

---

## 10. Membangun ulang aset ikon

```powershell
node C:\Users\guru01\AndroidBuild\tools\make-ios-assets.js
```

Skrip membaca `assets/favicon.png` (logo resmi 3223×3238) lalu menghasilkan:
- seluruh ukuran `AppIcon` (PNG **RGB tanpa alpha**, syarat App Store);
- `LaunchLogo` 116/232/348 px (transparan);
- `LaunchBackground` putih.
