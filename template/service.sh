#!/system/bin/sh
MODDIR=${0%/*}
DATA_DIR="$MODDIR/config"

[ -f "$DATA_DIR/initrc" ] || exit 0

MAGISK_TMP=$(magisk --path) || MAGISK_TMP="/sbin"

# First try Android 11's new init.rc since some devices use the new path but still have the legacy init.rc file
# https://github.com/topjohnwu/Magisk/pull/4836
INITRC_NAME="system/etc/init/hw/init.rc"

# legacy init.rc (Android 10 and older)
[ -f "/$INITRC_NAME" ] || INITRC_NAME="init.rc"

INITRC="/$INITRC_NAME"

# First try SAR path
MAGISKRC="$MAGISK_TMP/.magisk/rootdir/$INITRC_NAME"

# SAR path not found = Rootfs, Magisk modifies the init.rc file directly
[ -f "$MAGISKRC" ] || MAGISKRC=$INITRC

trim() {
  trimmed=$1
  trimmed=${trimmed%% }
  trimmed=${trimmed## }
  echo $trimmed
}

# https://github.com/topjohnwu/Magisk/blob/master/native/jni/init/rootdir.cpp#L24
grep_flash_recovery() {
  # Some devices don't have the flash_recovery service
  # (like Samsung renamed it to "ota_cleanup" but Magisk won't remove it, so we no need to do anything for this)
  LINE=$(grep "service flash_recovery " "$INITRC") || return 1
  LINE=${LINE#*"service flash_recovery "}
  trim "$LINE"
}

reset_flash_recovery() {
  FLASH_RECOVERY=$(grep_flash_recovery) || return

  # Skip if the flash_recovery service was not removed by Magisk
  grep -qxF "service flash_recovery /system/bin/xxxxx" "$MAGISKRC" || return

  # Skip if the install-recovery.sh does not exist
  [ -f "$FLASH_RECOVERY" ] || return

  # Skip if there is the state set for the service
  [ "$(getprop 'init.svc.flash_recovery' 2>/dev/null)" = "" ] || return

  # Set a "fake" state for the service
  resetprop 'init.svc.flash_recovery' 'stopped'
}

grep_service_name() {
  ARG=$1
  LINE=$(grep "service .* $MAGISK_TMP/magisk --$ARG" "$MAGISKRC")
  LINE=${LINE#*"service "}
  LINE=${LINE%" $MAGISK_TMP"*}
  trim "$LINE"
}

del_service_name() {
  resetprop --delete "init.svc.$1"
}

delete_services() {
  # Wait for boot to complete
  while [ "$(getprop sys.boot_completed)" != "1" ]
  do
    sleep 1
  done

  # Remove Magisk's services' names from system properties
  POST_FS_DATA=$(grep_service_name "post-fs-data")
  LATE_START_SERVICE=$(grep_service_name "service")
  BOOT_COMPLETED=$(grep_service_name "boot-complete")
  del_service_name "$POST_FS_DATA"
  del_service_name "$LATE_START_SERVICE"
  del_service_name "$BOOT_COMPLETED"
}

reset_flash_recovery
delete_services &
