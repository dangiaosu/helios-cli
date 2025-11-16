#!/bin/bash

# Helios Snapshot Downloader with Auto Retry & Resume
# GitHub: https://github.com/dangiaosu/helios-cli
# Usage: curl -sL https://raw.githubusercontent.com/dangiaosu/helios-cli/main/helios-cli.sh | bash

set -e

echo "============================================================"
echo "HELIOS SNAPSHOT DOWNLOADER v1.1"
echo "============================================================"
echo ""

# Kiem tra va cai dat UFW neu chua co
echo "[1/5] Kiem tra va cau hinh firewall..."

if ! command -v ufw &> /dev/null; then
    echo "UFW chua duoc cai dat, dang cai..."
    apt update > /dev/null 2>&1
    apt install -y ufw > /dev/null 2>&1
    echo "Da cai dat UFW!"
fi

echo "Dang cau hinh UFW rules..."

# Deny cac port khong can thiet
ufw deny 8080 > /dev/null 2>&1 || true
ufw deny 8546 > /dev/null 2>&1 || true
ufw deny 8547 > /dev/null 2>&1 || true
ufw deny 10337 > /dev/null 2>&1 || true

# Cho phep local RPC
ufw allow from 127.0.0.1 to any port 8545 > /dev/null 2>&1 || true

echo "UFW rules da duoc cap nhat!"
echo ""

# Cai dat cac cong cu can thiet
echo "[2/5] Cai dat cac cong cu can thiet..."
apt update > /dev/null 2>&1
apt install -y wget curl jq > /dev/null 2>&1
echo "Da cai dat: wget, curl, jq"
echo ""

# Tao thu muc backup neu chua co
BACKUP_DIR="/root/.heliades/backups"
echo "[3/5] Kiem tra thu muc backup..."

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Dang tao thu muc: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# Chuyen den thu muc backup
cd "$BACKUP_DIR" || {
    echo "Loi: Khong the truy cap thu muc $BACKUP_DIR"
    exit 1
}

echo "Thu muc hien tai: $(pwd)"
echo ""

# Lay du lieu JSON tu API
echo "[4/5] Dang lay thong tin snapshot tu server..."
json_data=$(curl -s https://snapshots.helioschainlabs.org/snapshots/)

# Kiem tra neu API tra ve loi
if [ -z "$json_data" ]; then
    echo "Loi: Khong the ket noi den server snapshot!"
    echo "Kiem tra ket noi mang hoac thu lai sau."
    exit 1
fi

# Lay URL download cua snapshot moi nhat
latest_url=$(echo "$json_data" | jq -r '.snapshots | sort_by(.blockId) | reverse | .[0].downloadUrl')

# Kiem tra neu lay duoc URL
if [ -z "$latest_url" ] || [ "$latest_url" = "null" ]; then
    echo "Loi: Khong tim thay snapshot moi nhat!"
    exit 1
fi

# Lay thong tin snapshot
latest_blockid=$(echo "$json_data" | jq -r '.snapshots | sort_by(.blockId) | reverse | .[0].blockId')
latest_filename=$(echo "$json_data" | jq -r '.snapshots | sort_by(.blockId) | reverse | .[0].fileName')

# Hien thi thong tin snapshot
echo "============================================================"
echo "Snapshot moi nhat:"
echo "  Block ID  : $latest_blockid"
echo "  File      : $latest_filename"
echo "  URL       : $latest_url"
echo "============================================================"
echo ""

# Lay ten file tu URL
filename=$(basename "$latest_url")

# Kiem tra xem file da ton tai chua
if [ -f "$filename" ]; then
    filesize=$(du -h "$filename" | cut -f1)
    echo "Canh bao: File $filename da ton tai! (Dung luong: $filesize)"
    echo ""
    read -p "Ban co muon tai lai khong? (y/n): " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "Giu nguyen file cu. Thoat."
        exit 0
    fi
    echo "Dang xoa file cu..."
    rm -f "$filename"
    echo ""
fi

# Download file voi retry va resume support
echo "[5/5] Bat dau tai xuong snapshot..."
echo "Thong tin download:"
echo "  - Auto retry     : Khong gioi han"
echo "  - Resume support : Co"
echo "  - Timeout        : 30s"
echo "  - Retry delay    : 5s"
echo "============================================================"
echo ""

# Download voi progress bar day du
wget -c \
     -t 0 \
     --retry-connrefused \
     --waitretry=5 \
     --read-timeout=30 \
     --timeout=30 \
     --progress=bar:force \
     "$latest_url"

# Kiem tra ket qua download
if [ $? -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo "TAI XUONG THANH CONG!"
    echo "============================================================"
    echo "File      : $BACKUP_DIR/$filename"
    echo "Dung luong: $(du -h "$filename" | cut -f1)"
    echo "============================================================"
    exit 0
else
    echo ""
    echo "============================================================"
    echo "TAI XUONG THAT BAI!"
    echo "============================================================"
    echo "Chay lai script de tiep tuc (wget se tu dong resume)."
    echo "============================================================"
    exit 1
fi
