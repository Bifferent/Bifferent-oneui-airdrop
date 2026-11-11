#!/system/bin/sh
# KSU module action: restart the whole share/mosey stack.
# Use after changing "谁可以与您分享" back to 任何人 if devices are no longer discovered.
MODDIR=${0%/*}
LOG=/data/adb/mosey_boot.log
log() { echo "[$(date '+%m-%d %H:%M:%S')] [action] $*" >> "$LOG"; }

log "restarting share stack"
/data/adb/ksud sepolicy apply "$MODDIR/sepolicy.rule" >/dev/null 2>&1

# restart HAL / daemon
if pidof mosey_server >/dev/null 2>&1; then kill -9 $(pidof mosey_server) 2>/dev/null; sleep 1; fi
nsenter -t 1 -m -- /system/bin/sh -c 'setenforce 0; (runcon u:r:mosey_server:s0 /vendor/bin/mosey_server >/data/adb/mosey_server.log 2>&1 &); sleep 1; setenforce 1'
sleep 1

# restart apps so ProtocolX starts from a clean state
am force-stop com.google.android.mosey >/dev/null 2>&1
sleep 1
am force-stop com.samsung.android.app.sharelive >/dev/null 2>&1
sleep 1
sleep 1
for i in 1 2 3; do am start -n com.samsung.android.app.sharelive/.presentation.main.MainActivity >/dev/null 2>&1 && break; sleep 2; done
log "done, mosey_server pid=$(pidof mosey_server)"