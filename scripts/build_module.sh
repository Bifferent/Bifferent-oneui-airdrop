#!/usr/bin/env bash
# Assemble the KernelSU module zip from an extracted payload.
# Usage: ./scripts/build_module.sh <payload_dir> [dist_dir]
set -euo pipefail
PAYLOAD="${1:?usage: $0 <payload_dir> [dist_dir]}"
DIST="${2:-dist}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="mosey_airdrop_s9280"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/$NAME"
cp -a "$ROOT/module/." "$WORK/$NAME/"

S="$WORK/$NAME/system"
mkdir -p "$S/vendor/bin" "$S/vendor/lib64" "$S/vendor/etc/init" "$S/vendor/etc/vintf/manifest" \
         "$S/system_ext/priv-app/MoseyApp" "$S/system_ext/etc/permissions" "$S/system_ext/etc/default-permissions" \
         "$S/system/priv-app/ShareLive"

cp "$PAYLOAD/mosey_server"                                   "$S/vendor/bin/"
cp "$PAYLOAD/libmosey_daemon_ffi.so"                        "$S/vendor/lib64/"
cp "$PAYLOAD/mosey.rc"                                      "$S/vendor/etc/init/"
cp "$PAYLOAD/manifest_mosey.xml"                            "$S/vendor/etc/vintf/manifest/"
cp "$PAYLOAD/MoseyApp.apk"                                  "$S/system_ext/priv-app/MoseyApp/"
cp "$PAYLOAD/privapp-permissions-com.google.android.mosey.xml"        "$S/system_ext/etc/permissions/"
cp "$PAYLOAD/default-permissions-com.google.android.mosey.xml"        "$S/system_ext/etc/default-permissions/"
cp "$PAYLOAD/ShareLive.apk"                                 "$S/system/priv-app/ShareLive/"

chmod 755 "$WORK/$NAME"/*.sh
chmod 755 "$S/vendor/bin/mosey_server"

find "$WORK" -name '.DS_Store' -delete 2>/dev/null || true
mkdir -p "$ROOT/$DIST"
OUT="$ROOT/$DIST/$NAME.zip"
rm -f "$OUT"
( cd "$WORK/$NAME" && zip -qr "$OUT" . )
echo "[+] built: $OUT"
unzip -l "$OUT" | tail -5
