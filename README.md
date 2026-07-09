# C9 Pribadi

Installer sederhana untuk Cloud9 pribadi di Ubuntu.

Setelah install selesai:

- Cloud9 jalan sebagai service `systemd`
- tetap hidup walau terminal ditutup
- otomatis aktif lagi saat VPS reboot
- login memakai `username` dan `password` yang dimasukkan saat install
- `Find in Files` sudah dipasang saat install, jadi popup `Cloud9 Installer` tidak muncul lagi pada login pertama

## Dukungan

- Ubuntu `18.04`
- Ubuntu `20.04`
- Ubuntu `22.04`
- Ubuntu `24.04`

Default yang dipakai:

- Cloud9 repo: `https://github.com/c9/core.git`
- Branch: `master`
- Commit: `7e1ac98f51b85e8bed401c593774ef73ada3cd07`
- Node.js default: `14`
- PTY module: `node-pty-prebuilt-multiarch@0.10.1-pre.5`

## Cara install

Paling sederhana, langsung download script lalu jalankan:

```bash
curl -fsSL https://raw.githubusercontent.com/sutorrinaldi/c9-pribadi/master/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

Atau kalau ingin clone repo penuh:

```bash
git clone https://github.com/sutorrinaldi/c9-pribadi.git
cd c9-pribadi
chmod +x install.sh
sudo ./install.sh
```

Saat installer berjalan, CLI akan menanyakan:

- `username`
- `password`

Setelah selesai, buka URL yang ditampilkan installer lalu login.

## Popup installer

Kalau install memakai versi `install.sh` terbaru, popup `Cloud9 Installer` untuk `c9.ide.find` seharusnya tidak muncul lagi saat login pertama.

Penyebab popup itu di Cloud9 lama adalah plugin `Find in Files` mencoba memasang `nak` ke `~/.c9` saat pertama dipakai.

Installer ini sudah menangani hal itu dengan:

- memasang `nak` saat proses install
- membuat file status `installed`
- menjalankan Cloud9 dengan `--setting-path`

Kalau popup masih muncul, biasanya berarti VPS masih memakai hasil install lama atau service belum memakai launcher terbaru.

## Perintah service

Lihat status:

```bash
systemctl status c9-pribadi
```

Restart:

```bash
sudo systemctl restart c9-pribadi
```

Stop:

```bash
sudo systemctl stop c9-pribadi
```

Start lagi:

```bash
sudo systemctl start c9-pribadi
```

## Default lokasi install

- Cloud9 source: `/opt/c9/core`
- Service name: `c9-pribadi`
- Runtime home: `/var/lib/c9-pribadi`
- Workspace: `/var/lib/c9-pribadi/workspace`
- Port default: `8181`

## Opsi environment

Kalau ingin ubah default sebelum install:

```bash
sudo C9_PORT=9000 C9_NODE_MAJOR=16 ./install.sh
```

Variabel yang bisa diubah:

- `C9_PORT`
- `C9_LISTEN`
- `C9_NODE_MAJOR`
- `C9_NODE_VERSION`
- `C9_INSTALL_DIR`
- `C9_SERVICE_NAME`
- `C9_WORKSPACE_DIR`
- `C9_SETTING_DIR`

## Reinstall atau update

Kalau sebelumnya install sempat gagal, update script dulu lalu jalankan ulang:

```bash
cd ~/c9-pribadi
git fetch origin
git reset --hard origin/master
chmod +x install.sh
sudo ./install.sh
```

Versi terbaru tidak lagi memakai `node-pty-prebuilt@0.7.6`, karena paket lama itu sering jatuh ke compile source dan gagal di Ubuntu 24.04 saat bertemu `python3.12` + `node-gyp` lama.

Installer terbaru juga mem-patch loader PTY bawaan Cloud9 agar:

- mencoba `node-pty-prebuilt-multiarch` secara langsung
- menampilkan error PTY asli di `journalctl` kalau native binary gagal di-load
- menjalankan smoke test PTY saat install, jadi install gagal lebih awal kalau backend terminal memang belum sehat

## Troubleshooting

Kalau ingin melihat log terbaru service:

```bash
sudo journalctl -u c9-pribadi --since "5 minutes ago" -l --no-pager
```

Atau setelah restart:

```bash
sudo systemctl restart c9-pribadi
sudo journalctl -u c9-pribadi -n 80 -l --no-pager
```

## Catatan

Service dibuat dengan `systemd`, jadi menutup SSH atau keluar dari VPS tidak akan mematikan Cloud9.

Jika repo `public`, `git clone https://github.com/sutorrinaldi/c9-pribadi.git` tidak seharusnya meminta username/password. Prompt login biasanya muncul kalau URL repo salah, repo masih private, atau credential helper Git di server sedang memaksa autentikasi.
