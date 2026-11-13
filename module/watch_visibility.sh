#!/system/bin/sh
# Foreground-gated visibility watcher.
# - When S互传 is not running: only one cheap "pidof" every 30s (no prefs access).
# - When S互传 is running: poll the prefs mtime every 3s; parse only on change.
# - On a switch to "任何人" (3), silently restart the share stack (NO_OPEN=1).
MODDIR=${0%/*}
PREF=/data/data/com.samsung.android.app.sharelive/shared_prefs/quick_share_nearby_setting_pref.xml
PIDFILE=/data/adb/mosey_watch.pid
LOG=/data/adb/mosey_boot.log
log() { echo "[$(date '+%m-%d %H:%M:%S')] [watch] $*" >> "$LOG"; }

if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$old" ] && kill -9 "$old" 2>/dev/null
fi
echo $$ > "$PIDFILE"
log "visibility watcher started (foreground-gated) pid=$$"

LAST=""
LAST_ACTION=0
# initial state: remember the current value so the first real switch to 3 triggers
V0=$(sed -n 's/.*name="device_visibility_type" value="\([0-9]*\)".*/\1/p' "$PREF" 2>/dev/null | tail -1)
[ -n "$V0" ] && LAST="$V0"
MTIME=$(stat -c %Y "$PREF" 2>/dev/null)

while true; do
  if ! pidof com.samsung.android.app.sharelive >/dev/null 2>&1; then
    # app not running: nothing can change the visibility setting
    sleep 30
    continue
  fi

  M=$(stat -c %Y "$PREF" 2>/dev/null)
  if [ "$M" = "$MTIME" ]; then
    sleep 3
    continue
  fi
  MTIME="$M"

  V=$(sed -n 's/.*name="device_visibility_type" value="\([0-9]*\)".*/\1/p' "$PREF" 2>/dev/null | tail -1)
  NOW=$(date +%s)
  if [ -n "$V" ] && [ "$V" != "$LAST" ]; then
    if [ "$V" = "3" ] && [ -n "$LAST" ] && [ $((NOW - LAST_ACTION)) -gt 20 ]; then
      log "visibility -> anyone, silent restart"
      sleep 2
      LAST_ACTION=$NOW
      NO_OPEN=1 sh "$MODDIR/action.sh" >> "$LOG" 2>&1
      log "silent restart done"
    fi
    LAST="$V"
  fi
  sleep 3
done