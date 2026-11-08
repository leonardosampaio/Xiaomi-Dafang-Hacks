#!/bin/sh

# Included for configure_static_net_iface and get_wifi_mac
. /system/sdcard/scripts/common_functions.sh

CONFIGPATH=/system/sdcard/config
BBOX_BIN=/system/sdcard/bin/busybox

WIFI_IFACE=wlan0
WIFI_LOGFILE=/system/sdcard/log/wifi.log
WIFI_BIN=/system/sdcard/scripts/wifi.sh
WIFI_CONFIG="$CONFIGPATH/wifi.conf"
WIFI_VERBOSE=1

MIN_CONNECT_TIMEOUT=30
# Time the access point stays up before trying the configured networks again
DEFAULT_AP_TIMEOUT=300
MIN_AP_TIMEOUT=60
# While clients are connected to the access point, check again after this time
AP_CLIENT_RECHECK=30

WPA_BIN=/system/bin/wpa_supplicant
WPA_CONFIG="$CONFIGPATH/wpa_supplicant.conf"
WPA_PIDFILE=/var/run/wpa_supplicant.pid

WPA_CLI_BIN=/system/bin/wpa_cli
WPA_CLI_PIDFILE=/var/run/wpa_cli.pid

WPA_ACTION_BIN=/system/sdcard/scripts/wpa_action.sh
WPA_ACTION_PIDFILE=/var/run/wpa_action.pid

HAP_BIN=/system/bin/hostapd
HAP_CLI_BIN=/system/bin/hostapd_cli
HAP_CONFIG="$CONFIGPATH/hostapd.conf"
HAP_PIDFILE=/var/run/hostapd.pid

UDHCPC_BIN=/sbin/udhcpc
UDHCPC_PIDFILE="/var/run/udhcpc.$WIFI_IFACE.pid"

UDHCPD_BIN=/sbin/udhcpd
UDHCPD_CONFIG="$CONFIGPATH/udhcpd.conf"
UDHCPD_PIDFILE=/var/run/udhcpd.pid

AP_TIMER_PIDFILE=/var/run/ap_timer.pid

log() {
  local LEVEL="$1"
  if [ -z "$WIFI_VERBOSE" ] && [ "$LEVEL" = "verbose" ]; then return 0; fi
  shift
  echo "$(date +"%D %T")" "$@" | "$BBOX_BIN" tee -a "$WIFI_LOGFILE"
}

kill_wait() {
  local PIDFILE="$1"
  local PID=$(cat "$PIDFILE")
  log verbose "Killing pid $PID ($PIDFILE)"
  kill "$PID"
  log verbose "Waiting pid $PID ($PIDFILE)"
  wait "$PID"
  log verbose "Removing pidfile $PIDFILE"
  rm -f "$PIDFILE"
}

run_bg() {
  local PIDFILE="$1"
  shift
  "$BBOX_BIN" nohup "$@" 2>&1 >/dev/null &
  echo "$!" > "$PIDFILE"
}

reset_iface() {
  log info "Resetting interface"
  ifconfig "$WIFI_IFACE" down
  ifconfig "$WIFI_IFACE" 0.0.0.0
  ifconfig -a
}

wpa_supplicant_start() {
  log info "Starting wpa_supplicant"
  "$WPA_BIN" -d -B -P "$WPA_PIDFILE" -i "$WIFI_IFACE" -c "$WPA_CONFIG"
}

wpa_supplicant_stop() {
  log info "Stopping wpa_supplicant"
  kill_wait "$WPA_PIDFILE"
}

hostapd_init() {
  if [ -s "$HAP_CONFIG" ]; then return 0; fi
  sed "s/ssid=\(.*\$\)/ssid=\1-$(get_wifi_mac)/" "$HAP_CONFIG.dist" > "$HAP_CONFIG"
}

hostapd_start() {
  log info "Starting hostapd"
  "$HAP_BIN" -d -B -P "$HAP_PIDFILE" "$HAP_CONFIG"
}

hostapd_stop() {
  log info "Stopping hostapd"
  kill_wait "$HAP_PIDFILE"
}

udhcpc_start() {
  log info "Starting udhcpc"
  "$UDHCPC_BIN" -b -p "$UDHCPC_PIDFILE" -i "$WIFI_IFACE" -x hostname:"$(hostname)"
}

udhcpc_stop() {
  log info "Stopping udhcpc"
  kill_wait "$UDHCPC_PIDFILE"
}

udhcpd_init() {
  if [ ! -s "$UDHCPD_CONFIG" ]; then
    cp "$UDHCPD_CONFIG.dist" "$UDHCPD_CONFIG"
  fi
}

udhcpd_start() {
  log info "Starting udhcpd"
  "$UDHCPD_BIN" "$UDHCPD_CONFIG"
}

udhcpd_stop() {
  log info "Stopping udhcpd"
  kill_wait "$UDHCPD_PIDFILE"
}

wpa_cli_start() {
  log info "Starting wpa_cli"
  "$WPA_CLI_BIN" -B -P "$WPA_CLI_PIDFILE" -i "$WIFI_IFACE" -a "$WPA_ACTION_BIN"
}

wpa_cli_stop() {
  log info "Stopping wpa_cli"
  kill_wait "$WPA_CLI_PIDFILE"
}

# (Re)start ntpd when the wifi connects: run.sh starts it only once, during
# boot, and if the network wasn't up yet the clock stays in 1970 (and TLS fails)
ntp_restart() {
  local SERVER="$(cat "$CONFIGPATH/ntp_srv.conf" 2>/dev/null)"
  [ -n "$SERVER" ] || return 0
  killall ntpd > /dev/null 2>&1
  log info "Starting ntpd ($SERVER)"
  "$BBOX_BIN" ntpd -p "$SERVER"
}

wpa_action_connected() {
  log info "Connected"
  wpa_action_watchdog_stop
  ntp_restart
}

wpa_action_disconnected() {
  log info "Disconnected"
  wpa_action_watchdog_stop
  wpa_action_watchdog_start
}

wpa_action_watchdog() {
  local TIMEOUT="$(get_config "$WIFI_CONFIG" connect_timeout)"
  if [ -z "$TIMEOUT" ] || [ "$TIMEOUT" -lt "$MIN_CONNECT_TIMEOUT" ]; then
    TIMEOUT="$MIN_CONNECT_TIMEOUT"
  fi
  log verbose "wpa_action watchdog sleeping $TIMEOUT seconds"
  sleep "$TIMEOUT"
  rm -f "$WPA_ACTION_PIDFILE"
  log verbose "wpa_action watchdog switching to ap mode"
  exec "$WIFI_BIN" ap
}

wpa_action_watchdog_start() {
  log info "Starting wpa_action watchdog"
  run_bg "$WPA_ACTION_PIDFILE" "$WIFI_BIN" wpa_action watchdog
}

wpa_action_watchdog_stop() {
  log info "Stopping wpa_action watchdog"
  kill_wait "$WPA_ACTION_PIDFILE"
}

wpa_has_networks() {
  [ -s "$WPA_CONFIG" ] && grep -q '^[[:space:]]*network[[:space:]]*=[[:space:]]*{' "$WPA_CONFIG"
}

ap_client_count() {
  "$HAP_CLI_BIN" -p /var/run/hostapd -i "$WIFI_IFACE" all_sta 2>/dev/null \
    | grep -c -i -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
}

# Keep the access point up for ap_timeout seconds, then go back to station
# mode to try the configured networks again (if none connects within
# connect_timeout, the wpa_action watchdog opens the access point again).
ap_timer() {
  local TIMEOUT="$(get_config "$WIFI_CONFIG" ap_timeout)"
  case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT="$DEFAULT_AP_TIMEOUT" ;; esac
  if [ "$TIMEOUT" -lt "$MIN_AP_TIMEOUT" ]; then
    TIMEOUT="$MIN_AP_TIMEOUT"
  fi
  log verbose "ap_timer sleeping $TIMEOUT seconds"
  sleep "$TIMEOUT"
  while true; do
    if ! wpa_has_networks; then
      log verbose "ap_timer: no wifi network configured, staying in ap mode"
      sleep "$TIMEOUT"
      continue
    fi
    local CLIENTS="$(ap_client_count)"
    if [ "${CLIENTS:-0}" -gt 0 ]; then
      log verbose "ap_timer: $CLIENTS client(s) connected to the access point, waiting"
      sleep "$AP_CLIENT_RECHECK"
      continue
    fi
    break
  done
  rm -f "$AP_TIMER_PIDFILE"
  log verbose "ap_timer switching to station mode"
  exec "$WIFI_BIN" station
}

ap_timer_start() {
  log info "Starting ap_timer"
  run_bg "$AP_TIMER_PIDFILE" "$WIFI_BIN" ap_timer
}

ap_timer_stop() {
  log info "Stopping ap_timer"
  kill_wait "$AP_TIMER_PIDFILE"
}

station_ifup() {
  if [ -s "$CONFIGPATH/staticip.conf" ]; then
    configure_static_net_iface "$WIFI_IFACE"
  else
    ifconfig "$WIFI_IFACE" up
    udhcpc_start
  fi
}

station_start() {
  log info "Starting station mode"
  ap_stop
  wpa_supplicant_start
  wpa_action_watchdog_start
  wpa_cli_start
  station_ifup
}

station_stop() {
  log info "Stopping station mode"
  wpa_action_watchdog_stop
  wpa_cli_stop
  udhcpc_stop
  wpa_supplicant_stop
  reset_iface
}

ap_ifup() {
  local IP="$(grep router "$UDHCPD_CONFIG" | cut -d ' ' -f3)"
  local NETMASK="$(grep subnet "$UDHCPD_CONFIG" | cut -d ' ' -f3)"
  ifconfig "$WIFI_IFACE" up "$IP" netmask "$NETMASK"
}

ap_start() {
  log info "Starting access point mode"
  station_stop
  hostapd_start
  ap_ifup
  udhcpd_start
  ap_timer_start
}

ap_stop() {
  log info "Stopping access point mode"
  ap_timer_stop
  udhcpd_stop
  hostapd_stop
  reset_iface
}

wifi_init() {
  hostapd_init
  udhcpd_init
  if [ ! -s "$WIFI_CONFIG" ]; then
    cp "$WIFI_CONFIG.dist" "$WIFI_CONFIG"
  fi
}

wifi_start() {
  log info "Starting wifi"
  wifi_init
  if wpa_has_networks; then
    station_start
  else
    ap_start
  fi
}

case $1 in
  start)
    wifi_start
    ;;
  ap|station)
    "$1_start"
    ;;
  wpa_action)
    "$1_$2"
    ;;
  ap_timer)
    "$1"
    ;;
esac
