#!/system/bin/sh
# Watch S互传 visibility. When the user switches to "任何人" (type 3), ProtocolX can get
# stuck in a suspended state (suspendGuard lost) and never resumes. Restart the share
# stack automatically a few seconds after such a switch.
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
log "visibility watcher started pid=$$"

LAST=""
LAST_ACTION=0
while true; do
  V=$(sed -n 's/.*name="device_visibility_type" value="\([0-9]*\)".*/\1/p' "$PREF" 2>/dev/null | tail -1)
  NOW=$(date +%s)
  if [ -n "$V" ] && [ "$V" != "$LAST" ]; then
    if [ "$V" = "3" ] && [ -n "$LAST" ] && [ $((NOW - LAST_ACTION)) -gt 20 ]; then
      log "visibility switched to anyone (3), restart share stack in 3s"
      sleep 3
      LAST_ACTION=$NOW
      sh "$MODDIR/action.sh" >> "$LOG" 2>&1
      log "auto restart done"
    fi
    LAST="$V"
  fi
  sleep 3
done
