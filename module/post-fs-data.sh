#!/system/bin/sh
MODDIR=${0%/*}
# mount in init's mount namespace so the framework sees it
nsenter -t 1 -m /system/bin/sh "$MODDIR/mount.sh" >> /data/adb/mosey_boot.log 2>&1
# force servicemanager to reload VINTF manifests (cache key = /apex/apex-info-list.xml mtime)
nsenter -t 1 -m /system/bin/touch /apex/apex-info-list.xml 2>/dev/null
echo "[$(date)] post-fs-data done" >> /data/adb/mosey_boot.log
# drop stale PackageManager parse cache for ShareLive (APK content is swapped at late-load)
rm -f /data/system/package_cache/*/ShareLive-* 2>/dev/null
