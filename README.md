# C9 Pribadi

Installer sederhana untuk Cloud9 pribadi di Ubuntu.

Setelah install selesai:

- Cloud9 jalan sebagai service `systemd`
- tetap hidup walau terminal ditutup
- otomatis aktif lagi saat VPS reboot
- login memakai `username` dan `password` yang dimasukkan saat install

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

## Cara install

Jika repo GitHub Anda berisi file ini di root:

```bash
git clone https://github.com/sutorrinaldi/REPO.git
cd REPO
chmod +x install.sh
sudo ./install.sh
```

Jika folder `c9-pribadi` masih berada di dalam repo yang lebih besar:

```bash
git clone https://github.com/sutorrinaldi/REPO.git
cd REPO/c9-pribadi
chmod +x install.sh
sudo ./install.sh
```

Saat installer berjalan, CLI akan menanyakan:

- `username`
- `password`

Setelah selesai, buka URL yang ditampilkan installer lalu login.

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

## Catatan

Service dibuat dengan `systemd`, jadi menutup SSH atau keluar dari VPS tidak akan mematikan Cloud9.
