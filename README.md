# C9 Pribadi

Installer sederhana untuk Cloud9 pribadi di Ubuntu.

Installer ini tidak menjalankan `apt upgrade -y`. Ia hanya melakukan `apt-get update` lalu memasang paket yang dibutuhkan, supaya lebih aman untuk VPS produksi dan tidak memicu upgrade sistem penuh saat instalasi.

Setelah install selesai:

- Cloud9 jalan sebagai service `systemd`
- tetap hidup walau terminal ditutup
- otomatis aktif lagi saat VPS reboot
- login memakai `username` dan `password` yang dimasukkan saat install
- `Find in Files` sudah dipasang saat install, jadi popup `Cloud9 Installer` tidak muncul lagi pada login pertama
- state workspace awal diperbaiki otomatis, jadi tree `workspace` tidak macet loading karena `expanded=[]`
- self-check installer GUI bawaan Cloud9 dimatikan untuk mode personal ini, supaya koneksi awal VFS tidak menggantung
- kompatibilitas VFS write diperbaiki, jadi toast `Failed to write to 'state.settings'` tidak muncul lagi di Node/Ubuntu modern
- drag-and-drop ke tree kiri diperbaiki; kalau browser salah mendeteksi target sebagai editor/pane, installer memaksa fallback ke upload `workspace` supaya tidak mentok lagi di popup `Maximum open count exceeded`
- jika instalasi gagal di tengah jalan, installer membersihkan temporary directory, tarball Node.js, dan cache npm yang dibuat selama proses install
- setelah `systemctl enable --now`, installer langsung memverifikasi service aktif; jika gagal start, log `journalctl` terakhir akan ditampilkan lalu install dihentikan
- terminal Cloud9 langsung punya PHP 8 lengkap untuk CLI dan extension umum
- extension PHP `imagick` dan `redis` langsung dipasang
- `ffmpeg` langsung tersedia untuk encode, transcode, dan probing media
- `redis-server` langsung dipasang dan dijalankan sebagai service
- `composer` langsung tersedia setelah install
- `pip` dan `pip3` permanen diarahkan ke Python 3
- `pip2` permanen diarahkan ke Python 2.7
- `python2` permanen diarahkan ke `Python 2.7`
- `python` dan `python3` permanen diarahkan ke `Python 3`
- `node`, `npm`, dan `npx` langsung tersedia setelah install

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
- PHP default: `8.3`
- PTY module: `node-pty-prebuilt-multiarch@0.10.1-pre.5`
- Python 2 default: `2.7.18`

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

Command runtime setelah install:

- `php file.php`
- `composer install`
- `php -m | grep imagick`
- `php -m | grep redis`
- `ffmpeg -version`
- `ffprobe -version`
- `python -m pip install nama-paket`
- `pip install nama-paket`
- `pip3 install nama-paket`
- `pip2 install nama-paket`
- `python file.py` menjalankan Python 3
- `python3 file.py` menjalankan Python 3
- `python2 file.py` menjalankan Python 2.7
- `node app.js`
- `npm install`
- `npx nama-tool`
- `redis-cli ping`

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
- `C9_PHP_VERSION`
- `C9_PHP_PACKAGES`
- `C9_INSTALL_COMPOSER`
- `C9_COMPOSER_APT_PACKAGE`
- `C9_INSTALL_PYTHON2_PIP`
- `C9_PYTHON2_GET_PIP_URL`
- `C9_INSTALL_PHP_IMAGICK`
- `C9_PHP_IMAGICK_APT_PACKAGE`
- `C9_INSTALL_PHP_REDIS`
- `C9_PHP_REDIS_APT_PACKAGE`
- `C9_INSTALL_IMAGEMAGICK`
- `C9_IMAGEMAGICK_APT_PACKAGE`
- `C9_INSTALL_FFMPEG`
- `C9_FFMPEG_APT_PACKAGE`
- `C9_INSTALL_REDIS_SERVER`
- `C9_REDIS_SERVER_APT_PACKAGE`
- `C9_EXTRA_APT_PACKAGES`
- `C9_PYTHON3_APT_PACKAGES`
- `C9_PYTHON2_BUILD_APT_PACKAGES`
- `C9_PYTHON2_VERSION`
- `C9_PYTHON2_DIST_MIRROR`
- `C9_PYTHON2_PREFIX`
- `C9_INSTALL_DIR`
- `C9_SERVICE_NAME`
- `C9_WORKSPACE_DIR`
- `C9_SETTING_DIR`

Kalau ingin ganti versi PHP 8 yang dipasang:

```bash
sudo C9_PHP_VERSION=8.2 ./install.sh
```

Kalau tidak ingin Composer dipasang:

```bash
sudo C9_INSTALL_COMPOSER=0 ./install.sh
```

Kalau tidak ingin Redis service dan extension tambahan dipasang:

```bash
sudo C9_INSTALL_REDIS_SERVER=0 C9_INSTALL_PHP_REDIS=0 C9_INSTALL_PHP_IMAGICK=0 ./install.sh
```

Kalau tidak ingin `ffmpeg` dipasang:

```bash
sudo C9_INSTALL_FFMPEG=0 ./install.sh
```

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

Selain itu installer terbaru juga:

- mem-patch bug tree Cloud9 lama saat `state/projecttree/expanded` kosong
- memperbaiki atau membuat file `workspace/.c9/state.settings`
- menjaga root `workspace` tetap bisa dibuka walau state lama sempat korup
- mem-patch jalur VFS write `REST` dan `socket` setelah `vendored modules` dipulihkan, jadi toast `Failed to write to 'state.settings'` tidak tertimpa lagi oleh proses repair internal installer

Kalau sebelumnya Anda masih melihat toast `Failed to write to 'state.settings'. options.stream must be readable.`, itu biasanya karena versi installer lama memasang patch terlalu awal lalu patch tersebut tertimpa lagi oleh `restore_vendored_modules`.

Versi terbaru juga memperbaiki validator internal installer, jadi patch workspace bootstrap tidak lagi salah dianggap hilang padahal file sudah berhasil dipatch.

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

Kalau tampilan `workspace` pernah stuck loading, update script lalu jalankan ulang installer:

```bash
cd ~/c9-pribadi
git fetch origin
git reset --hard origin/master
chmod +x install.sh
sudo ./install.sh
```

## Catatan

Service dibuat dengan `systemd`, jadi menutup SSH atau keluar dari VPS tidak akan mematikan Cloud9.

Jika repo `public`, `git clone https://github.com/sutorrinaldi/c9-pribadi.git` tidak seharusnya meminta username/password. Prompt login biasanya muncul kalau URL repo salah, repo masih private, atau credential helper Git di server sedang memaksa autentikasi.
