#!/system/bin/sh
# Mosey boot service: mount, start mosey_server, keep system apps/permissions in shape
MODDIR=${0%/*}
LOG=/data/adb/mosey_boot.log
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Atomic single-instance lock. mkdir is one atomic filesystem operation; a pid+age marker
# is not sufficient because a second invocation can enter while the first is still preparing.
LOCK=/data/adb/mosey_service.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  LOCKPID=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$LOCKPID" ] && kill -0 "$LOCKPID" 2>/dev/null; then
    log "service already running pid=$LOCKPID; exit"
    exit 0
  fi
  # Recover stale lock only when its recorded owner is gone.
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
cleanup_lock() { rm -rf "$LOCK"; }
trap cleanup_lock EXIT INT TERM

revert_system_update() {
  pkg="$1"; pathpat="$2"; n=0
  while [ $n -lt 10 ]; do
    if pm path "$pkg" 2>/dev/null | grep -q "$pathpat"; then
      return 0
    fi
    pm uninstall-system-updates "$pkg" >/dev/null 2>&1 || cmd package uninstall-system-updates "$pkg" >/dev/null 2>&1
    n=$((n+1)); sleep 3
  done
  return 1
}

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

# 3) maintain exactly one mosey_server instance. The service lock serializes this stage.
NPID=$(pidof mosey_server)
if [ -z "$NPID" ]; then
  log "starting mosey_server"
  nsenter -t 1 -m -- /system/bin/sh -c 'setenforce 0; (runcon u:r:mosey_server:s0 /vendor/bin/mosey_server >/data/adb/mosey_server.log 2>&1 &); sleep 1; setenforce 1'
  sleep 2
  NPID=$(pidof mosey_server)
fi
if [ -n "$NPID" ]; then log "mosey_server pid=$NPID"; else log "mosey_server FAILED"; fi

# 4) S互传 must be the system (global) build, not the Galaxy Store CN update
revert_system_update com.samsung.android.app.sharelive '^package:/system' && log "ShareLive system build ok"

# 4b) MoseyApp must be the system build; Play may auto-update it to a newer data app
revert_system_update com.google.android.mosey '^package:/system_ext' && log "MoseyApp system build ok"

# 5) MoseyApp runtime permissions + GMS nearby sharing components
if pm path com.google.android.mosey >/dev/null 2>&1; then
  for p in android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH_ADVERTISE android.permission.BLUETOOTH_CONNECT android.permission.NEARBY_WIFI_DEVICES android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION android.permission.ACCESS_BACKGROUND_LOCATION android.permission.ACCESS_MEDIA_LOCATION; do
    pm grant com.google.android.mosey $p >/dev/null 2>&1
  done
  if [ -f "$MODDIR/nearby_components.txt" ]; then
    while read -r c; do
      [ -n "$c" ] && pm enable com.google.android.gms/$c >/dev/null 2>&1
    done < "$MODDIR/nearby_components.txt"
  fi
  # keep Nearby/Mosey out of doze so discovery does not stall after screen-off
  dumpsys deviceidle whitelist +com.google.android.mosey >/dev/null 2>&1
  log "mosey permissions granted"
fi

# 6) MoseyApp needs a PackageManager rescan -> framework restart, once per boot
NEED_REBOOT=0
if ! pm path com.google.android.mosey >/dev/null 2>&1; then NEED_REBOOT=1; fi
if ! pm path com.samsung.android.app.sharelive 2>/dev/null | grep -q '^package:/system'; then NEED_REBOOT=1; fi

if [ "$NEED_REBOOT" = "1" ]; then
  BID=$(cat /proc/sys/kernel/random/boot_id)
  DONE=$(cat /data/adb/mosey_last_softreboot 2>/dev/null)
  if [ "$BID" != "$DONE" ]; then
    echo "$BID" > /data/adb/mosey_last_softreboot
    # Scene's "系统自救" treats a post-fs-data re-run within 180s as a bootloop and
    # disables every other module; clear its markers before our soft reboot.
    rm -f /data/adb/modules/scene_resurgence/splash.last /data/adb/modules/scene_resurgence/animation.last 2>/dev/null
    log "cleared scene_resurgence boot markers"
    log "triggering soft reboot"
    nohup /data/adb/ksud soft-reboot >> "$LOG" 2>&1 &
  else
    log "already soft-rebooted this boot; skip"
  fi
fi

# 7) keep next unrooted boot clean: drop the ShareLive parse cache for the mounted (HK) APK
rm -f /data/system/package_cache/*/ShareLive-* 2>/dev/null
( sleep 120; rm -f /data/system/package_cache/*/ShareLive-* 2>/dev/null ) >/dev/null 2>&1 &
( sleep 600; rm -f /data/system/package_cache/*/ShareLive-* 2>/dev/null ) >/dev/null 2>&1 &
# Play can re-update MoseyApp after boot; re-check later
( sleep 120; revert_system_update com.google.android.mosey '^package:/system_ext' >/dev/null 2>&1 ) >/dev/null 2>&1 &
( sleep 600; revert_system_update com.google.android.mosey '^package:/system_ext' >/dev/null 2>&1 ) >/dev/null 2>&1 &

# 8) visibility watcher (single instance)
if [ -f "$MODDIR/watch_visibility.sh" ]; then
  pkill -f watch_visibility.sh 2>/dev/null
  sleep 1
  setsid /system/bin/sh "$MODDIR/watch_visibility.sh" >/dev/null 2>&1 &
  log "visibility watcher launched"
fi

rm -rf "$LOCK"