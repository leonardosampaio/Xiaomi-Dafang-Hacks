#!/bin/sh

. /system/sdcard/www/cgi-bin/func.cgi
. /system/sdcard/scripts/common_functions.sh

export LD_LIBRARY_PATH=/system/lib
export LD_LIBRARY_PATH=/thirdlib:$LD_LIBRARY_PATH

echo "Content-type: text/html"
echo "Pragma: no-cache"
echo "Cache-Control: max-age=0, no-store, no-cache"
echo ""

if [ -n "$F_cmd" ]; then
  case "$F_cmd" in
  get_config)
    echo "hostname#:#$(hostname)"
    echo "theme#:#"
    echo "ntp#:#$(cat /system/sdcard/config/ntp_srv.conf)"
    echo "timezone#:#$(/system/sdcard/bin/busybox awk -F '\t' -v tzn="$(cat /system/sdcard/config/timezone.conf)" '{print "<option value=\""$1"\""; if ($1==tzn) print "selected"; print ">" $1 "</option>"}' /system/sdcard/www/json/timezones.tsv | tr -d '\n')"
    echo "currenttime#:#Current time is $(date) - $(cat /etc/TZ)"
    echo "github_token#:#$(get_config /system/sdcard/config/updates.conf github_token)"
    [ -f /system/sdcard/config/wifi.conf ] || cp /system/sdcard/config/wifi.conf.dist /system/sdcard/config/wifi.conf
    echo "connect_timeout#:#$(get_config /system/sdcard/config/wifi.conf connect_timeout)"
    echo "ap_timeout#:#$(get_config /system/sdcard/config/wifi.conf ap_timeout)"
    echo "ap_ssid#:#$(get_config /system/sdcard/config/hostapd.conf ssid)"
    echo "usb_eth#:#$([ -f /system/sdcard/config/usb_eth_driver.conf ] && echo on || echo off)"
    echo "ssh_key#:#$(cat /system/sdcard/root/.ssh/authorized_keys)"
    echo "ssh_port#:#$(get_config /system/sdcard/config/ssh.conf ssh_port)"
    echo "ssh_password#:#$(get_config /system/sdcard/config/ssh.conf ssh_password)"
  ;;
  save_config)
	if [ -n ${F_hostname} ]; then
		hst=$(printf '%b' "${F_hostname//%/\\x}")
		if [ "$(cat /system/sdcard/config/hostname.conf)" != "$hst" ]; then
	  		echo -n "<p>Setting hostname to '$hst' "
	  		echo "$hst" > /system/sdcard/config/hostname.conf
	  		if hostname "$hst"; then
				echo "Success</p>"
	  		else
				echo "Failed</p>"
	  		fi
		fi
	fi
	if [ -n "${F_password}" ] && [ "${F_password}" != "*****" ]; then
		password=$(printf '%b' "${F_password//%/\\x}")
		echo "<p>Setting http password</p>"
		http_password "$password"
	fi
	if [ -n ${F_timezone} ]; then
		timezone_name=$(printf '%b' "${F_timezone//%/\\x}")
		if [ "$(cat /system/sdcard/config/timezone.conf)" != "$timezone_name" ]; then
	  		echo "<p>Setting time zone to '$timezone_name'</p>"
	  		echo "$timezone_name" > /system/sdcard/config/timezone.conf
	  		# Set system timezone from timezone name
	  		set_timezone
		fi
	fi
	if [ -n ${F_ntp} ]; then
		ntp=$(printf '%b' "${F_ntp//%/\\x}")
		if [ $ntp != $(cat /system/sdcard/config/ntp_srv.conf) ]; then
	  		echo "<p>Setting NTP Server to ${ntp} "
	  		echo "$ntp" > /system/sdcard/config/ntp_srv.conf
		fi
	fi
	if [ -n ${F_github_token+x} ]; then
		github_token=$(printf '%b' "${F_github_token//%/\\x}")
		if [ "$github_token" != "$(get_config /system/sdcard/config/updates.conf github_token)" ]; then
	  		echo "<p>Setting GitHub token</p>"
	  		rewrite_config /system/sdcard/config/updates.conf github_token "$github_token"
		fi
	fi
  if [ -n ${F_ssh_port} ]; then
		ssh_port=$(printf '%b' "${F_ssh_port//%/\\x}")
		echo "<p>Changing SSH port to: $ssh_port</p>"
		rewrite_config /system/sdcard/config/ssh.conf ssh_port "$ssh_port"
	fi
  if [ -n ${F_ssh_password} ]; then
		ssh_password=$(printf '%b' "${F_ssh_password//%/\\x}")
		echo "<p>Changing SSH password to: $ssh_password</p>"
		rewrite_config /system/sdcard/config/ssh.conf ssh_password "$ssh_password"
	fi
  if [ -n ${F_ssh_key} ]; then
		ssh_key=$(printf '%b' "${F_ssh_key//%/\\x}" | sed 's/%20/ /g')
		echo "<p>Changing SSH key to: $ssh_key</p>"
		echo "$ssh_key" > /system/sdcard/root/.ssh/authorized_keys
	fi

  if [ -n ${F_ssh_key} ] || [ -n ${F_ssh_password} ] || [ -n ${F_ssh_port} ]; then
  		echo "Re" 
		/system/sdcard/controlscripts/dropbear stop 
          	/system/sdcard/controlscripts/dropbear start
  fi
  [ -f /system/sdcard/config/wifi.conf ] || cp /system/sdcard/config/wifi.conf.dist /system/sdcard/config/wifi.conf
  if [ -n "${F_connect_timeout}" ]; then
    case "$F_connect_timeout" in
      *[!0-9]*) echo "<p>Invalid wifi connect timeout</p>" ;;
      *) if [ "$F_connect_timeout" != "$(get_config /system/sdcard/config/wifi.conf connect_timeout)" ]; then
           echo "<p>Setting wifi connect timeout to: $F_connect_timeout</p>"
           rewrite_config /system/sdcard/config/wifi.conf connect_timeout "$F_connect_timeout"
         fi ;;
    esac
  fi
  if [ -n "${F_ap_timeout}" ]; then
    case "$F_ap_timeout" in
      *[!0-9]*) echo "<p>Invalid access point duration</p>" ;;
      *) if [ "$F_ap_timeout" != "$(get_config /system/sdcard/config/wifi.conf ap_timeout)" ]; then
           echo "<p>Setting access point duration to: $F_ap_timeout</p>"
           rewrite_config /system/sdcard/config/wifi.conf ap_timeout "$F_ap_timeout"
         fi ;;
    esac
  fi
  if [ -n "${F_ap_ssid}" ]; then
    F_ap_ssid=$(echo "$F_ap_ssid" | sed 's/+/ /g')
    ap_ssid=$(printf '%b' "${F_ap_ssid//%/\\x}")
    if [ "$ap_ssid" != "$(get_config /system/sdcard/config/hostapd.conf ssid)" ]; then
      echo "<p>Setting access point SSID to: $ap_ssid</p>"
      rewrite_config /system/sdcard/config/hostapd.conf ssid "$ap_ssid"
    fi
  fi
  if [ -n "${F_ap_password}" ] && [ "${F_ap_password}" != "*****" ]; then
    ap_password=$(printf '%b' "$(echo "$F_ap_password" | sed 's/+/ /g; s/%/\\x/g')")
    if [ ${#ap_password} -lt 8 ] || [ ${#ap_password} -gt 63 ]; then
      echo "<p>Access point password must have 8 to 63 characters, not changed</p>"
    else
      echo "<p>Setting access point password</p>"
      rewrite_config /system/sdcard/config/hostapd.conf wpa_passphrase "$ap_password"
    fi
  fi
  if [ -n ${F_usb_eth} ]; then
    usb_eth=$(printf '%b' "${F_usb_eth//%/\\x}")
    if [ "$usb_eth" = "on" ]; then
      echo "<p>Enabling USB ethernet</p>"
      touch /system/sdcard/config/usb_eth_driver.conf
    else
      echo "<p>Disabling USB ethernet</p>"
      rm -f /system/sdcard/config/usb_eth_driver.conf
    fi
  fi
	return
	;;
  get_wifi_networks)
    # One network per line: ssid#:#priority#:#hidden#:#secured (passwords are never sent)
    wpa_networks_list | grep -v '^\037' | while IFS="$(printf '\037')" read -r ssid psk prio scan km; do
      secured=true
      [ "$km" = "NONE" ] && [ -z "$psk" ] && secured=false
      echo "$(wpa_ssid_decode "$ssid")#:#${prio:-0}#:#$([ "$scan" = 1 ] && echo true || echo false)#:#$secured"
    done
    return
    ;;
  save_wifi_networks)
    # Rewrite the network blocks of wpa_supplicant.conf from the list sent by the UI.
    # Empty password = keep the current one of that network (net_orig_N = its
    # position in the list returned by get_wifi_networks, 1-based; empty = new).
    WPA_CONFIG=/system/sdcard/config/wpa_supplicant.conf
    [ -s "$WPA_CONFIG" ] || cp "$WPA_CONFIG.dist" "$WPA_CONFIG"
    urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%/\\x/g')"; }
    OLD_LIST="$(wpa_networks_list)"
    TMP="$WPA_CONFIG.tmp"
    # Keep the global settings (everything before the first network block)
    awk '/^[ \t]*network[ \t]*=[ \t]*\{/ { exit } { print }' "$WPA_CONFIG" > "$TMP"
    count=0; errors=0; i=0
    case "$F_net_count" in ''|*[!0-9]*) F_net_count=0 ;; esac
    while [ "$i" -lt "$F_net_count" ]; do
      eval "ssid=\$F_net_ssid_$i; pass=\$F_net_pass_$i; prio=\$F_net_prio_$i; hidden=\$F_net_hidden_$i; orig=\$F_net_orig_$i"
      i=$((i + 1))
      ssid="$(urldecode "$ssid")"; pass="$(urldecode "$pass")"
      case "$orig" in ''|*[!0-9]*) orig="" ;; esac
      [ -n "$ssid" ] || continue
      if [ ${#ssid} -gt 32 ] || echo "$ssid" | grep -q '["[:cntrl:]]'; then
        echo "<p>Invalid SSID '$ssid' (max 32 characters, no quotes), not saved</p>"; errors=$((errors + 1)); continue
      fi
      case "$prio" in ''|*[!0-9]*) prio=0 ;; esac
      psk_line=""; km="NONE"
      if [ -n "$pass" ]; then
        if [ ${#pass} -lt 8 ] || [ ${#pass} -gt 63 ] || echo "$pass" | grep -q '[[:cntrl:]]'; then
          echo "<p>Password of '$ssid' must have 8 to 63 characters, network not saved</p>"; errors=$((errors + 1)); continue
        fi
        psk_line="psk=\"$pass\""; km="WPA-PSK"
      elif [ -n "$orig" ]; then
        # Keep the current password of the network
        old="$(echo "$OLD_LIST" | grep -v '^\037' | sed -n "${orig}p" | cut -d "$(printf '\037')" -f 2,5)"
        o_psk="${old%%$(printf '\037')*}"; o_km="${old#*$(printf '\037')}"
        if [ -n "$o_psk" ]; then psk_line="psk=$o_psk"; km="${o_km:-WPA-PSK}"; fi
      fi
      {
        echo ""
        echo "network={"
        printf '\tssid="%s"\n' "$ssid"
        [ "$hidden" = "true" ] && printf '\tscan_ssid=1\n'
        printf '\tkey_mgmt=%s\n' "$km"
        if [ "$km" != "NONE" ]; then
          printf '\tpairwise=CCMP TKIP\n\tgroup=CCMP TKIP WEP104 WEP40\n'
          printf '\t%s\n' "$psk_line"
        fi
        printf '\tpriority=%s\n' "$prio"
        echo "}"
      } >> "$TMP"
      count=$((count + 1))
      echo "<p>Wifi network '$ssid' saved (priority $prio$([ "$km" = NONE ] && echo ', open network'))</p>"
    done
    if [ "$errors" -gt 0 ]; then
      rm -f "$TMP"
      echo "<p><b>Wifi networks not changed: fix the errors above and save again</b></p>"
    else
      cp "$WPA_CONFIG" "$WPA_CONFIG.prev"
      mv "$TMP" "$WPA_CONFIG"
      echo "<p>$count wifi network(s) configured</p>"
      # Apply in background so this response gets back before the wifi reconfigures.
      # If the camera was connected and can't reconnect within 25 seconds (less than
      # the minimum connect_timeout, before the access point opens), restore the
      # previous networks.
      WPA_CLI="/system/bin/wpa_cli -i wlan0"
      if $WPA_CLI status 2>/dev/null | grep -q '^wpa_state=COMPLETED'; then
        echo "<p>If the camera can't reconnect within 25 seconds, the previous networks are restored.</p>"
        (
          sleep 2
          $WPA_CLI reconfigure > /dev/null 2>&1
          n=0
          while [ $n -lt 25 ]; do
            sleep 1; n=$((n + 1))
            $WPA_CLI status 2>/dev/null | grep -q '^wpa_state=COMPLETED' && [ $n -ge 5 ] && exit 0
          done
          echo "$(date +"%D %T") Wifi did not reconnect after saving the networks, restoring the previous ones" >> /system/sdcard/log/wifi.log
          cp "$WPA_CONFIG.prev" "$WPA_CONFIG"
          $WPA_CLI reconfigure > /dev/null 2>&1
        ) > /dev/null 2>&1 &
      else
        ( sleep 2; $WPA_CLI reconfigure > /dev/null 2>&1 ) > /dev/null 2>&1 &
      fi
    fi
    return
    ;;
  *)
    echo "Unsupported command '$F_cmd'"
    ;;

  esac
  fi

exit 0
