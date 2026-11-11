#!/system/bin/sh
# Mosey overlay mount script (overlayfs + userxattr)
MODDIR=${0%/*}
TMP=/data/adb/mosey_ov
SRC=$MODDIR/system
LOG=/data/adb/mosey_mount.log
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

mounted() { grep -q " $1 " /proc/self/mountinfo 2>/dev/null; }

if ! mounted $TMP; then
  mkdir -p $TMP
  mount -t tmpfs tmpfs $TMP || { log "tmpfs fail"; exit 1; }
fi

mk() { mkdir -p $TMP/u$1 $TMP/w$1; }

ovl() {
  if mounted "$2"; then log "skip $2"; return 0; fi
  mount -t overlay overlay -o lowerdir=$2,upperdir=$TMP/u$1,workdir=$TMP/w$1,userxattr $2 && log "mounted $2" || log "FAIL $2"
}

# 1 /vendor/bin
mk 1; chcon u:object_r:vendor_file:s0 $TMP/u1
if [ ! -f $TMP/u1/mosey_server ]; then
  cp $SRC/vendor/bin/mosey_server $TMP/u1/; chmod 755 $TMP/u1/mosey_server; chcon u:object_r:mosey_server_exec:s0 $TMP/u1/mosey_server
fi
ovl 1 /vendor/bin

# 2 /vendor/lib64
mk 2; chcon u:object_r:vendor_file:s0 $TMP/u2
if [ ! -f $TMP/u2/libmosey_daemon_ffi.so ]; then
  cp $SRC/vendor/lib64/libmosey_daemon_ffi.so $TMP/u2/; chmod 644 $TMP/u2/libmosey_daemon_ffi.so; chcon u:object_r:vendor_file:s0 $TMP/u2/libmosey_daemon_ffi.so
fi
ovl 2 /vendor/lib64

# 3 /vendor/etc/init
mk 3; chcon u:object_r:vendor_configs_file:s0 $TMP/u3
if [ ! -f $TMP/u3/mosey.rc ]; then
  cp $SRC/vendor/etc/init/mosey.rc $TMP/u3/; chmod 644 $TMP/u3/mosey.rc; chcon u:object_r:vendor_configs_file:s0 $TMP/u3/mosey.rc
fi
ovl 3 /vendor/etc/init

# 4 vintf manifest
mk 4; chcon u:object_r:vendor_configs_file:s0 $TMP/u4
if [ ! -f $TMP/u4/manifest_mosey.xml ]; then
  cp $SRC/vendor/etc/vintf/manifest/manifest_mosey.xml $TMP/u4/; chmod 644 $TMP/u4/manifest_mosey.xml; chcon u:object_r:vendor_configs_file:s0 $TMP/u4/manifest_mosey.xml
fi
ovl 4 /vendor/etc/vintf/manifest

# 5 /system_ext/priv-app
mk 5; chcon u:object_r:system_file:s0 $TMP/u5; mkdir -p $TMP/u5/MoseyApp; chcon u:object_r:system_file:s0 $TMP/u5/MoseyApp
if [ ! -f $TMP/u5/MoseyApp/MoseyApp.apk ]; then
  cp $SRC/system_ext/priv-app/MoseyApp/MoseyApp.apk $TMP/u5/MoseyApp/; chmod 644 $TMP/u5/MoseyApp/MoseyApp.apk; chcon u:object_r:system_file:s0 $TMP/u5/MoseyApp/MoseyApp.apk
fi
ovl 5 /system_ext/priv-app

# 6 /system_ext/etc
mk 6; chcon u:object_r:system_file:s0 $TMP/u6
mkdir -p $TMP/u6/permissions $TMP/u6/default-permissions
chcon u:object_r:system_file:s0 $TMP/u6/permissions $TMP/u6/default-permissions
if [ ! -f $TMP/u6/permissions/privapp-permissions-com.google.android.mosey.xml ]; then
  cp $SRC/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml $TMP/u6/permissions/; chmod 644 $TMP/u6/permissions/privapp-permissions-com.google.android.mosey.xml; chcon u:object_r:system_file:s0 $TMP/u6/permissions/privapp-permissions-com.google.android.mosey.xml
fi
if [ ! -f $TMP/u6/default-permissions/default-permissions-com.google.android.mosey.xml ]; then
  cp $SRC/system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml $TMP/u6/default-permissions/; chmod 644 $TMP/u6/default-permissions/default-permissions-com.google.android.mosey.xml; chcon u:object_r:system_file:s0 $TMP/u6/default-permissions/default-permissions-com.google.android.mosey.xml
fi
ovl 6 /system_ext/etc

# 7 /system/priv-app/ShareLive -> global (sepGlobal) build; CN build hardcodes nearbyShareSupported=false
if [ -f $SRC/system/priv-app/ShareLive/ShareLive.apk ] && [ ! -f /data/adb/mosey_keep_stock_sharelive ]; then
  mk 7; chcon u:object_r:system_file:s0 $TMP/u7
  if [ ! -f $TMP/u7/ShareLive.apk ]; then
    cp $SRC/system/priv-app/ShareLive/ShareLive.apk $TMP/u7/; chmod 644 $TMP/u7/ShareLive.apk; chcon u:object_r:system_file:s0 $TMP/u7/ShareLive.apk
  fi
  ovl 7 /system/priv-app/ShareLive
fi

# 8 /product/etc/permissions: drop cn.google.services (unlock-cn-gms approach)
if [ -f $SRC/product/etc/permissions/services.cn.google.xml ]; then
  mk 8; chcon u:object_r:system_file:s0 $TMP/u8
  if [ ! -f $TMP/u8/services.cn.google.xml ]; then
    cp $SRC/product/etc/permissions/services.cn.google.xml $TMP/u8/; chmod 644 $TMP/u8/services.cn.google.xml; chcon u:object_r:system_file:s0 $TMP/u8/services.cn.google.xml
  fi
  ovl 8 /product/etc/permissions
fi

# make sure the privapp allowlist file is present in the (possibly pre-existing) overlay
if [ -d /system_ext/etc/permissions ]; then
  [ -f /system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml ] || \
    cp $SRC/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml /system_ext/etc/permissions/ 2>/dev/null
  [ -f /system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml ] && \
    chcon u:object_r:system_file:s0 /system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml 2>/dev/null
fi

log "DONE"