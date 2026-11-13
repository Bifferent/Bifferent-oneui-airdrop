#!/system/bin/sh
# Low-power visibility watcher.
# Polls only the prefs mtime every 10s (one stat call) and parses the XML only when it
# actually changed. Silent restart: does not bring S互传 to the foreground.
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
log "visibility watcher started (10s low-power) pid=$$"

LAST=""
LAST_ACTION=0
MTIME=$(stat -c %Y "$PREF" 2>/dev/null)

while true; do
  sleep 10
  M=$(stat -c %Y "$PREF" 2>/dev/null)
  [ "$M" = "$MTIME" ] && continue
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
done
