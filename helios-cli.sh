#!/bin/bash

# Helios Snapshot Downloader with Auto Retry & Resume
# GitHub: [your-repo-url]
# Usage: curl -sL [raw-github-url] | bash

set -e

echo "============================================================"
echo "HELIOS SNAPSHOT DOWNLOADER v1.0"
echo "============================================================"
echo ""

# Cau hinh UFW firewall
echo "[1/5] Cau hinh firewall..."
if command -v ufw &> /dev/null; then
    echo "Dang cau hinh UFW rules..."
    
    # Deny cac port khong can thiet
    sudo ufw deny 8080 2>/dev/null || true
    sudo ufw deny 8546 2>/dev/null || true
    sudo ufw deny 8547 2>/dev/null || true
    sudo ufw deny 10337 2>/dev/null || true
    
    # Cho phep local RPC
    sudo ufw allow from 127.0.0.1 to any port 8545 2>/dev/null || true
    
    echo "UFW rules da duoc cap nhat!"
else
    echo "UFW khong duoc cai dat, bo qua buoc nay."
fi
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
echo "  Block ID : $latest_blockid"
echo "  File     : $latest_filename"
echo "  URL      : $latest_url"
echo "============================================================"
echo ""

# Lay ten file tu URL
filename=$(basename "$latest_url")

# Kiem tra xem file da ton tai chua (file hoan thanh)
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
echo "  - Auto retry    : Khong gioi han"
echo "  - Resume support: Co"
echo "  - Timeout       : 30s"
echo "  - Retry delay   : 5s"
echo "============================================================"
echo ""

# Wget options:
# -c : continue/resume download
# -t 0 : unlimited retries
# --retry-connrefused : retry even if connection refused
# --waitretry=5 : wait 5s between retries
# --read-timeout=30 : timeout after 30s of no data
# --timeout=30 : connection timeout 30s
# --progress=bar:force:noscroll : show progress bar
# --show-progress : show progress even in non-interactive mode

wget -c \
     -t 0 \
     --retry-connrefused \
     --waitretry=5 \
     --read-timeout=30 \
     --timeout=30 \
     --progress=bar:force:noscroll \
     --show-progress \
     "$latest_url" 2>&1 | grep --line-buffered -E "saved|%|written"

# Kiem tra ket qua download
download_status=${PIPESTATUS[0]}

echo ""
echo "============================================================"

if [ $download_status -eq 0 ]; then
    echo "TAI XUONG THANH CONG!"
    echo "============================================================"
    echo "File     : $BACKUP_DIR/$filename"
    echo "Dung luong: $(du -h "$filename" | cut -f1)"
    echo "============================================================"
    echo ""
    echo "BUOC TIEP THEO:"
    echo "1. Restore snapshot:"
    echo "   helios restore --snapshot $filename"
    echo ""
    echo "2. Hoac giai nen:"
    echo "   tar -xzf $filename"
    echo ""
    echo "3. Roi start lai node:"
    echo "   systemctl restart helios"
    echo "============================================================"
    exit 0
else
    echo "TAI XUONG THAT BAI!"
    echo "============================================================"
    echo ""
    echo "Co the thu:"
    echo "1. Chay lai script (wget se tu dong resume):"
    echo "   bash helios-cli.sh"
    echo ""
    echo "2. Hoac download tu GitHub:"
    echo "   curl -sL [your-github-raw-url] | bash"
    echo ""
    echo "3. Kiem tra ket noi mang va dung luong o dia"
    echo ""
    echo "File tam thoi (neu co): $BACKUP_DIR/$filename"
    echo "Neu chay lai, wget se tu dong tiep tuc tu cho cu."
    echo "============================================================"
    exit 1
fi
