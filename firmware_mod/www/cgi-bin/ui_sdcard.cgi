#!/bin/sh                                                          
source ./func.cgi
source /system/sdcard/scripts/common_functions.sh


echo "Content-type: text"
echo "Pragma: no-cache"
echo "Cache-Control: max-age=0, no-store, no-cache"
echo ""

if [ -n "$F_cmd" ]; then
  case "$F_cmd" in
  events)
    echo "["
    find /system/sdcard/DCIM/${F_dir}/ -type f | xargs ls --full-time \
      | awk '{sub(/\/system\/sdcard\/DCIM/, "viewer"); printf "{\"file\" : \"%s\", \"date\" : \"%s %s\"},", $9, $6, $7}' \
      | head -c -1
    echo "]"    
    ;;
  check_sdcard)
	  mount|grep "/system/sdcard"|grep "rw,">/dev/null
	  if [ $? == 1 ]; then
		  echo -n "nok"
	  else
		  echo -n "ok"
	  fi
	  ;;
  sdcard_status)
    # For each partition (p1 = system, p2 = data): present (true|false),
    # mount (ro|rw|none), config (read-only mode at boot, config/sdcard.conf),
    # reason (when ro: config|fs_error|unknown). mount/config/reason without a
    # prefix are the system partition (older pages).
    for part in 1 2; do
      sdcard_part_state $part
      echo "p${part}_present#:#$PART_PRESENT"
      echo "p${part}_mount#:#$PART_MOUNT"
      echo "p${part}_config#:#$PART_CONFIG"
      echo "p${part}_reason#:#$PART_REASON"
    done
    sdcard_ro_state
    echo "mount#:#$SD_MOUNT"
    echo "config#:#$SD_CONFIG"
    echo "reason#:#$SD_REASON"
    ;;
  sdcard_config)
    # Turn the read-only mode of a partition on/off (at boot) and apply it now
    case "$F_readonly" in true|false) ;; *) echo "Invalid value"; exit 0 ;; esac
    case "$F_part" in 2) part=2; key=DATA_READONLY; mnt=/system/sdcard/data; name="data partition" ;;
                      *) part=1; key=SDCARD_READONLY; mnt=/system/sdcard; name="system partition" ;; esac
    sdcard_part_state $part
    if [ "$PART_PRESENT" != true ] || [ "$PART_MOUNT" = none ]; then
      echo "The $name is not mounted."; exit 0
    fi
    if [ "$PART_REASON" = "fs_error" ]; then
      echo "The $name has file system errors and the kernel set it read-only. Repair it first (fsck / chkdsk on a PC), then change this setting."
      exit 0
    fi
    # The setting is stored on the system partition: make it writable meanwhile
    sdcard_part_state 1
    SYS_MOUNT=$PART_MOUNT
    if [ "$SYS_MOUNT" = "ro" ] && ! mount -o remount,rw /system/sdcard; then
      echo "Could not make the system partition writable to save the setting."; exit 0
    fi
    SD_CONF=/system/sdcard/config/sdcard.conf
    [ -f "$SD_CONF" ] || cp "$SD_CONF.dist" "$SD_CONF"
    if grep -q "^$key=" "$SD_CONF"; then
      sed -i "s/^$key=.*/$key=$F_readonly/" "$SD_CONF"
    else
      echo "$key=$F_readonly" >> "$SD_CONF"
    fi
    sd_sync
    # Apply now (the system partition goes back to how it was, unless it is the one changed)
    if [ "$part" = 1 ]; then
      target=$([ "$F_readonly" = true ] && echo ro || echo rw)
    else
      [ "$SYS_MOUNT" = "ro" ] && mount -o remount,ro /system/sdcard 2>/dev/null
      target=$([ "$F_readonly" = true ] && echo ro || echo rw)
      mnt=/system/sdcard/data
    fi
    if mount -o remount,$target $mnt 2>/dev/null; then
      echo "Read-only mode of the $name $([ "$F_readonly" = true ] && echo enabled || echo disabled). It is now $([ "$target" = ro ] && echo read-only || echo writable)."
    else
      echo "Read-only mode of the $name $([ "$F_readonly" = true ] && echo enabled || echo disabled). It is still busy (files open for writing), the change applies after the next reboot."
    fi
    ;;
  sdcard_remount)
    # Temporary change of a partition, until the next reboot
    case "$F_mode" in rw|ro) ;; *) echo "Invalid mode"; exit 0 ;; esac
    case "$F_part" in 2) part=2; mnt=/system/sdcard/data; name="data partition" ;;
                      *) part=1; mnt=/system/sdcard; name="system partition" ;; esac
    sdcard_part_state $part
    if [ "$PART_PRESENT" != true ] || [ "$PART_MOUNT" = none ]; then
      echo "The $name is not mounted."; exit 0
    fi
    if [ "$F_mode" = "rw" ] && [ "$PART_REASON" = "fs_error" ]; then
      echo "The $name has file system errors: writing to it may corrupt more data. Repair it first (fsck / chkdsk on a PC)."
      exit 0
    fi
    sd_sync
    if mount -o remount,$F_mode $mnt 2>/dev/null; then
      echo "The $name is $([ "$F_mode" = rw ] && echo writable || echo read-only) until the next reboot."
    else
      echo "Could not remount the $name (files open for writing?)."
    fi
    ;;
  getFiles)
    if [[ -d /system/sdcard/DCIM/${F_dir} ]]; then
        find /system/sdcard/DCIM/${F_dir}/ -type f | xargs ls -lh
    fi
    ;;
  sdcardInfo)
      echo "sdcardSize#:#$(df -h /system/sdcard | awk 'NR==2{print$4}')"
      echo "sdcardUsed#:#$(df -h /system/sdcard | awk 'NR==2{print$3}')"
      echo "sdcardUsedPercent#:#$(df -h /system/sdcard | awk 'NR==2{print$5}')"
    ;;
  del_file)
    F_file=$(echo ${F_file} | sed -e 's/%2F/\//g' | sed -e 's/viewer/\/system\/sdcard\/DCIM/') 
    echo "Remove ${F_file}"
    rm $F_file
    ;;
  *)
    echo "Unsupported command '$F_cmd'"
    ;;

  esac
  fi
