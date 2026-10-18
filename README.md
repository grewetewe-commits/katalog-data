# Data Katalog Praktis

Repo publik ini hanya berisi **data jadi** untuk map Roblox **Katalog Praktis**, tanpa kode pengolah.

- Cabang `data`: snapshot JSON yang sudah divalidasi (satu commit tanpa riwayat, ditimpa tiap terbit).
  Map membaca file di sini lewat `raw.githubusercontent.com` dan CDN jsDelivr.
- Cabang `main`: workflow, `terbitkan.sh` (validator + penerbit daftar putih), dan panduan ini.
- Kode otak, data mentah, laporan, dan log lengkap ada di repo dapur **privat** (`katalog-embed`).

## Cara kerja

1. Workflow terjadwal (`otak`, `mata3d`, `ready`) meng-checkout kode dapur memakai secret `TOKEN_DAPUR`,
   menjalankannya, dan menyimpan hasil lengkap ke cabang `data` repo dapur (privat).
2. Job `terbit` (`terbit-inti.yml`) mengambil cabang itu, memvalidasi, lalu menerbitkan **hanya** file daftar putih
   ke cabang `data` repo ini. Paket tidak lengkap / versi mundur ditolak; data publik lama tetap dipakai.
3. Log publik sengaja ringkas. Log lengkap: `LOG_TERAKHIR.txt` di cabang data dapur, dan cabang `diag` dapur bila gagal.
4. `keepalive` menyalakan ulang jadwal tiap bulan (GitHub mematikan jadwal repo publik setelah 60 hari sepi).
5. Selama masa pindah, workflow di repo dapur tetap ada sebagai **cadangan**: otomatis dilewati bila repo ini
   sudah menerbitkan hasil segar (< 8 jam), dan otomatis jalan lagi bila repo ini berhenti menerbitkan.

## Rahasia yang dibutuhkan (Settings → Secrets and variables → Actions)

- `TOKEN_DAPUR`: fine-grained token, Contents read/write untuk `katalog-embed` (dan `katalog-data`).
  **Catat tanggal kedaluwarsanya** dan perbarui sebelum habis. Kalau habis: workflow gagal, map tetap memakai data terakhir.
- `ROBLOX_API_KEY`: API key Open Cloud yang sama dengan yang dipakai repo dapur.

Tidak ada trigger pull request, artifact, atau cache data privat yang bisa diunduh publik.
