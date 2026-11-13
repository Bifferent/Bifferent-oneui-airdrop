#!/system/bin/sh
# Mosey boot service: mount, start mosey_server, make sure system apps/permissions are ready
MODDIR=${0%/*}
LOG=/data/adb/mosey_boot.log
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 300 ]; do sleep 1; i=$((i+1)); done

nsenter -t 1 -m /system/bin/sh "$MODDIR/mount.sh" >> "$LOG" 2>&1

i=0
while ! pm path android >/dev/null 2>&1 && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done

# 1) make servicemanager reload VINTF (cache key = /apex/apex-info-list.xml mtime)
nsenter -t 1 -m /system/bin/touch /apex/apex-info-list.xml 2>/dev/null

# 2) apply SELinux rules live (permissive mosey_server + transitions)
if [ -f "$MODDIR/sepolicy.rule" ]; then
  /data/adb/ksud sepolicy apply "$MODDIR/sepolicy.rule" >/dev/null 2>&1
  log "sepolicy applied"
fi

# 3) (re)start mosey_server
if pidof mosey_server >/dev/null 2>&1; then
  kill -9 $(pidof mosey_server) 2>/dev/null
  sleep 1
fi
log "starting mosey_server"
nsenter -t 1 -m -- /system/bin/sh -c 'setenforce 0; (runcon u:r:mosey_server:s0 /vendor/bin/mosey_server >/data/adb/mosey_server.log 2>&1 &); sleep 1; setenforce 1'
sleep 1
if pidof mosey_server >/dev/null 2>&1; then log "mosey_server pid=$(pidof mosey_server)"; else log "mosey_server FAILED"; fi

# 3) S互传 must be the system (global) build, not the Galaxy Store CN update
if ! pm path com.samsung.android.app.sharelive 2>/dev/null | grep -q '^package:/system'; then
  log "reverting ShareLive to system build"
  n=0
  while [ $n -lt 5 ]; do
    cmd package uninstall-system-updates com.samsung.android.app.sharelive >> "$LOG" 2>&1 && break
    n=$((n+1)); sleep 3
  done
  sleep 2
fi

# 4) MoseyApp runtime permissions + GMS nearby sharing components
if pm path com.google.android.mosey >/dev/null 2>&1; then
  for p in android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_ADVERTISE android.permission.BLUETOOTH_CONNECT android.permission.NEARBY_WIFI_DEVICES android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION android.permission.ACCESS_BACKGROUND_LOCATION android.permission.ACCESS_MEDIA_LOCATION; do
    pm grant com.google.android.mosey $p >/dev/null 2>&1
  done
  if [ -f "$MODDIR/nearby_components.txt" ]; then
    while read -r c; do
      [ -n "$c" ] && pm enable com.google.android.gms/$c >/dev/null 2>&1
    done < "$MODDIR/nearby_components.txt"
  fi
  log "mosey permissions granted"
fi

# 5) MoseyApp needs a PackageManager rescan -> framework restart, once per boot
NEED_REBOOT=0
if ! pm path com.google.android.mosey >/dev/null 2>&1; then NEED_REBOOT=1; fi
if ! pm path com.samsung.android.app.sharelive 2>/dev/null | grep -q '^package:/system'; then NEED_REBOOT=1; fi

if [ "$NEED_REBOOT" = "1" ]; then
  BID=$(cat /proc/sys/kernel/random/boot_id)
  DONE=$(cat /data/adb/mosey_last_softreboot 2>/dev/null)
  if [ "$BID" != "$DONE" ]; then
    echo "$BID" > /data/adb/mosey_last_softreboot
    # Scene's "系统自救" (scene_resurgence) treats a post-fs-data re-run within 180s as a
    # bootloop and disables every other module. Clear its markers before our soft reboot.
    for m in scene_resurgence; do
      rm -f "/data/adb/modules/$m/splash.last" "/data/adb/modules/$m/animation.last" 2>/dev/null
    done
    log "cleared scene_resurgence boot markers"
    log "triggering soft reboot"
    nohup /data/adb/ksud soft-reboot >> "$LOG" 2>&1 &
  else
    log "already soft-rebooted this boot; skip"
  fi
fi
# keep next boot clean: drop the ShareLive parse cache written for the mounted (HK) APK
rm -f /data/system/package_cache/*/ShareLive-* 2>/dev/null
#if the module action is not run manually, keep a watcher for the visibility resume bug
if [ -f "$MODDIR/watch_visibility.sh" ]; then
  setsid /system/bin/sh "$MODDIR/watch_visibility.sh" >/dev/null 2>&1 &
  log "visibility watcher launched"
fi