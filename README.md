# Data Katalog Praktis

Repo publik ini menyediakan data hasil untuk map Roblox **Katalog Praktis**.
Cabang `data` berisi snapshot JSON yang telah divalidasi, dengan satu commit tanpa induk.
Cabang `main` hanya berisi workflow, pengirim/validator `terbitkan.sh`, dan panduan ini.
Kode pengolah, bahan mentah, hasil latihan, dan log lengkap berada di repo dapur terpisah.

Penerbitan memakai daftar putih ketat. Paket yang tidak lengkap atau versinya tidak konsisten
ditolak sebelum push; data publik sebelumnya tetap tersedia. Identitas dan harga item adalah
snapshot, sehingga map tetap perlu memeriksa detail resmi Roblox.

## Penyiapan pemilik

1. Pasang secret `TOKEN_DAPUR` dengan akses Contents read/write hanya ke `katalog-embed`,
   serta `ROBLOX_API_KEY`. Jangan menaruh nilainya di file, issue, atau komentar.
2. Pastikan helper migrasi sudah ada di `main` dapur. Jalankan `terbitkan.yml`, lalu `ready.yml`,
   periksa isi cabang `data` dan log publik. Jalankan satu putaran `otak.yml` penuh.
3. Setelah lulus dan map membaca repo baru, hapus jadwal/push otomatis di dapur dan
   set repository variable `MIGRATION_ACTIVE` = `true` di repo ini untuk menyalakan jadwal baru.
   Selama penyiapan, hanya dispatch manual yang memproses data agar tidak berjalan ganda.
4. Baru kemudian pemilik mengubah dapur menjadi privat. Simpan tanggal kedaluwarsa token
   dan perbarui secret sebelum tanggal tersebut.

Tidak ada pemicu pull request, artifact, atau cache hasil pengolahan privat. Cache yang
diizinkan hanya unduhan model CLIP publik. Runner yang digunakan adalah runner standar
repo publik; tidak ada API AI berbayar atau pengaturan billing yang dipasang.
Layanan tetap memiliki batas teknis, perubahan kebijakan, dan kemungkinan gangguan;
tidak ada jaminan gratis tanpa batas selamanya. `keepalive` juga dapat dinonaktifkan
GitHub setelah tidak ada aktivitas, jadi periksa notifikasi dan status jadwal.
