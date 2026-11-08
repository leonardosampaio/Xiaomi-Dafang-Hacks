#!/bin/sh
#
# Data partition of the SD card (mmcblk0p2), used for the files the camera
# writes (recordings, timelapse; logs are kept in RAM). The system partition
# (mmcblk0p1, mounted by the camera firmware) can then stay read-only.
#
# The partition is FAT32 like the system one (the kernel only supports FAT on
# the SD card), but it is checked/repaired with fsck before it is mounted on
# every boot, which is not possible for the system partition.
#
# Usage (from run.sh, before anything writes to the card):
#   sdcard_data.sh boot     expand/format if requested, fsck, mount, bind mounts
#                           (status in /tmp/sdcard_data.log)
#
# Markers on the system partition, set by the SD card image:
#   .expand_data   first boot: grow mmcblk0p2 to the end of the card and reboot
#   .format_data   format mmcblk0p2 (after it was grown)

SD=/system/sdcard
BB=$SD/bin/busybox
DISK=/dev/mmcblk0
DATA_DEV=/dev/mmcblk0p2
DATA_DIR=$SD/data
DATA_DIRS="DCIM time_lapse"
STATUS=/tmp/sdcard_data.log
CONFIG=$SD/config/sdcard.conf

export PATH=$SD/bin:/bin:/sbin:/usr/bin:/usr/sbin:/system/bin
export LD_LIBRARY_PATH=$SD/lib:/thirdlib:/system/lib

# There is no working "sync" on the camera: flush the partitions instead
sd_sync() {
  for dev in /dev/mmcblk0p1 "$DATA_DEV"; do
    [ -b "$dev" ] && $BB blockdev --flushbufs "$dev" 2>/dev/null
  done
  return 0
}

log() {
  echo "$(date '+%F %T') $*" >> "$STATUS"
}

# Read a 32-bit little endian value from the MBR
mbr_le32() {
  $BB dd if="$DISK" bs=1 skip="$1" count=4 2>/dev/null | $BB hexdump -e '1/4 "%u"'
}

# First boot: grow the data partition to the end of the card. Only the size of
# the second MBR entry changes (the start stays the same, the system partition
# is not touched). The kernel can't re-read the partition table while the card
# is mounted, so the camera reboots, and the next boot formats the partition.
data_expand() {
  [ -f "$SD/.expand_data" ] || return 0
  [ -b "$DATA_DEV" ] || { log "expand: no $DATA_DEV"; return 0; }
  total=$(cat /sys/block/mmcblk0/size)
  start=$(mbr_le32 470)
  size=$(mbr_le32 474)
  new=$((total - start))
  if [ -z "$start" ] || [ "$start" -le 0 ] || [ "$new" -le "$size" ]; then
    log "expand: nothing to do (start=$start size=$size disk=$total)"
    rm -f "$SD/.expand_data"
    return 0
  fi
  # Remove the marker first: if the system partition is not writable, don't
  # touch the partition table (it would reboot forever)
  if ! rm -f "$SD/.expand_data" || [ -f "$SD/.expand_data" ]; then
    log "expand: can't remove the marker (system partition read-only?), skipped"
    return 0
  fi
  touch "$SD/.format_data"
  bytes=""; i=0
  while [ $i -lt 4 ]; do
    bytes="$bytes\\$(printf %o $(( (new >> (8 * i)) & 255 )))"
    i=$((i + 1))
  done
  printf "$bytes" | $BB dd of="$DISK" bs=1 seek=474 count=4 conv=notrunc,fsync 2>/dev/null
  $BB blockdev --flushbufs "$DISK" 2>/dev/null
  sd_sync
  if [ "$(mbr_le32 474)" = "$new" ]; then
    log "expand: data partition grown from $size to $new sectors, rebooting"
    sd_sync
    /sbin/reboot
    sleep 60
  else
    log "expand: failed to write the partition table"
    rm -f "$SD/.format_data"
  fi
}

data_format() {
  [ -f "$SD/.format_data" ] || return 0
  [ -b "$DATA_DEV" ] || return 0
  if $SD/bin/mkfs.vfat -F 32 -n DATA "$DATA_DEV" >> "$STATUS" 2>&1; then
    log "format: data partition formatted"
    rm -f "$SD/.format_data"
  else
    log "format: mkfs.vfat failed"
  fi
}

data_mount() {
  [ -b "$DATA_DEV" ] || { log "no data partition"; return 1; }
  DATA_READONLY=false
  [ -f "$CONFIG" ] && . "$CONFIG"
  # Repair the file system before mounting it (it is not mounted yet)
  $SD/bin/fsck.vfat -a "$DATA_DEV" > /tmp/sdcard_data_fsck.log 2>&1
  log "fsck exit code $? (see /tmp/sdcard_data_fsck.log)"
  mkdir -p "$DATA_DIR" 2>/dev/null
  opts=rw
  [ "$DATA_READONLY" = true ] && opts=ro
  if ! mount -t vfat -o "$opts" "$DATA_DEV" "$DATA_DIR"; then
    log "mount of $DATA_DEV failed"
    return 1
  fi
  log "data partition mounted $opts on $DATA_DIR"
  for d in $DATA_DIRS; do
    [ "$opts" = rw ] && mkdir -p "$DATA_DIR/$d"
    [ -d "$SD/$d" ] || mkdir -p "$SD/$d" 2>/dev/null
    if [ -d "$DATA_DIR/$d" ] && [ -d "$SD/$d" ]; then
      mount -o bind "$DATA_DIR/$d" "$SD/$d" && log "$SD/$d -> data partition"
    fi
  done
  return 0
}

case "$1" in
  boot)
    data_expand
    data_format
    data_mount
    ;;
  *)
    echo "Usage: $0 boot"
    ;;
esac
