#!/usr/bin/env bash
# Extract the mosey userspace files from a Samsung AP tar.md5 (HK/global firmware).
# Usage: ./scripts/extract_from_firmware.sh /path/to/AP_*.tar.md5 [outdir]
set -euo pipefail
AP="${1:?usage: $0 <AP_*.tar.md5> [outdir]}"
OUT="${2:-out}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"

echo "[*] super.img.lz4"
[ -f "$OUT/super.img.lz4" ] || tar -xf "$AP" -C "$OUT" super.img.lz4
echo "[*] decompress"
[ -f "$OUT/super.img" ] || lz4 -d "$OUT/super.img.lz4" "$OUT/super.img"
if [ ! -f "$OUT/super.raw.img" ]; then
  if python3 - "$OUT/super.img" <<'PY'
import sys
sys.exit(0 if open(sys.argv[1],'rb').read(4) == b'\x3a\xff\x26\xed' else 1)
PY
  then
    echo "[*] sparse -> raw"
    python3 "$HERE/sparse2img.py" "$OUT/super.img" "$OUT/super.raw.img"
  else
    ln -f "$OUT/super.img" "$OUT/super.raw.img" 2>/dev/null || cp "$OUT/super.img" "$OUT/super.raw.img"
  fi
fi

mkdir -p "$OUT/parts" "$OUT/root"
for p in vendor system_ext system; do
  if [ ! -f "$OUT/parts/$p.img" ]; then
    echo "[*] extract partition: $p"
    python3 "$HERE/lpunpack.py" "$OUT/super.raw.img" extract "$p" "$OUT/parts/$p.img"
  fi
  if [ ! -d "$OUT/root/$p" ]; then
    mkdir -p "$OUT/root/$p"
    echo "[*] erofs -> $OUT/root/$p"
    fsck.erofs --extract="$OUT/root/$p" "$OUT/parts/$p.img" >/dev/null
  fi
done

P="$OUT/payload"
mkdir -p "$P"
cp "$OUT/root/vendor/bin/mosey_server"                                   "$P/"
cp "$OUT/root/vendor/lib64/libmosey_daemon_ffi.so"                       "$P/"
cp "$OUT/root/vendor/etc/init/mosey.rc"                                  "$P/"
cp "$OUT/root/vendor/etc/vintf/manifest/manifest_mosey.xml"              "$P/"
cp "$OUT/root/system_ext/priv-app/MoseyApp/MoseyApp.apk"                 "$P/"
cp "$OUT/root/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml"        "$P/"
cp "$OUT/root/system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml" "$P/"
cp "$OUT/root/system/priv-app/ShareLive/ShareLive.apk"                   "$P/"

echo "[+] payload ready: $P"
ls -la "$P"
