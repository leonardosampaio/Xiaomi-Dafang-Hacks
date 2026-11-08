#!/bin/sh
#
# Ban the IPs that fail the web UI login through the Cloudflare Tunnel too many
# times. Started/stopped together with cloudflared (controlscripts/cloudflared).
#
# lighttpd logs the requests that come through the tunnel *with* credentials
# to $AUTH_LOG as "<CF-Connecting-IP> <status>" (see lighttpd.conf), so a 401
# there is a wrong user/password. When an IP reaches BAN_ATTEMPTS failures within
# BAN_TIME minutes, it is banned for BAN_TIME minutes: a rule is written to
# $BAN_CONF (included by lighttpd.conf) and lighttpd is reloaded gracefully.
# Everything lives in /tmp, so it also works with the SD card read-only.
#
# Usage: tunnel-ban.sh run | list | clear

# Started from the web UI, run.sh or a shell: use a known environment (lighttpd
# needs the libraries in /system/sdcard/lib when it is restarted from here)
export PATH=/system/sdcard/bin:/bin:/sbin:/usr/bin:/usr/sbin:/system/bin
export LD_LIBRARY_PATH=/system/sdcard/lib:/thirdlib:/system/lib

CONFIG="${CONFIG:-/system/sdcard/config/cloudflared.conf}"
AUTH_LOG="${AUTH_LOG:-/tmp/lighttpd-tunnel-auth.log}"
BAN_CONF="${BAN_CONF:-/tmp/lighttpd-tunnel-ban.conf}"
STATE="${STATE:-/tmp/tunnel-ban}"
FAILS="$STATE/fails"
BANS="$STATE/bans"
EVENTS="$STATE/events.log"
LIGHTTPD_PID="${LIGHTTPD_PID:-/run/lighttpd.pid}"
MAX_LOG_SIZE=524288

mkdir -p "$STATE"
touch "$FAILS" "$BANS"

BAN_ATTEMPTS=5
BAN_TIME=15
[ -f "$CONFIG" ] && . "$CONFIG"
case "$BAN_ATTEMPTS" in ''|*[!0-9]*) BAN_ATTEMPTS=5 ;; esac
case "$BAN_TIME" in ''|*[!0-9]*) BAN_TIME=15 ;; esac
[ "$BAN_TIME" -lt 1 ] && BAN_TIME=1
BAN_SECONDS=$((BAN_TIME * 60))

log() {
  echo "$(date '+%F %T') $*" >> "$EVENTS"
  # Keep the event log small
  if [ "$(wc -l < "$EVENTS")" -gt 200 ]; then
    tail -n 100 "$EVENTS" > "$EVENTS.tmp" && mv "$EVENTS.tmp" "$EVENTS"
  fi
}

# Restart lighttpd so it reads the new ban rule. A graceful reload (SIGUSR1)
# is not used: this lighttpd build (1.4.56-devel) dies when reloaded while
# clients are connected. The restart takes about 2 seconds.
reload_lighttpd() {
  /system/sdcard/controlscripts/lighttpd stop > /dev/null 2>&1
  sleep 1
  /system/sdcard/controlscripts/lighttpd start > /dev/null 2>&1
  sleep 2
  pid="$(cat "$LIGHTTPD_PID" 2>/dev/null)"
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    log "lighttpd did not start after applying the ban rule, trying again"
    rm -f "$LIGHTTPD_PID"
    /system/sdcard/controlscripts/lighttpd start > /dev/null 2>&1
  fi
}

# Write the lighttpd rule that denies the banned IPs and reload lighttpd
write_ban_conf() {
  ips="$(cut -d ' ' -f 1 "$BANS" | sed 's/\./\\./g' | tr '\n' '|' | sed 's/|$//')"
  if [ -n "$ips" ]; then
    echo "\$REQUEST_HEADER[\"CF-Connecting-IP\"] =~ \"^($ips)\$\" { url.access-deny = (\"\") }" > "$BAN_CONF.tmp"
  else
    : > "$BAN_CONF.tmp"
  fi
  if ! cmp -s "$BAN_CONF.tmp" "$BAN_CONF"; then
    mv "$BAN_CONF.tmp" "$BAN_CONF"
    reload_lighttpd
  else
    rm -f "$BAN_CONF.tmp"
  fi
}

is_banned() {
  grep -q "^$1 " "$BANS"
}

ban() {
  now=$(date +%s)
  echo "$1 $((now + BAN_SECONDS))" >> "$BANS"
  grep -v "^$1 " "$FAILS" > "$FAILS.tmp"; mv "$FAILS.tmp" "$FAILS"
  log "banned $1 for $BAN_TIME minutes after $BAN_ATTEMPTS failed logins"
  write_ban_conf
}

# Remove expired bans and old failures
expire() {
  now=$(date +%s)
  awk -v now="$now" '$2 > now' "$BANS" > "$BANS.tmp"
  if ! cmp -s "$BANS.tmp" "$BANS"; then
    for ip in $(awk -v now="$now" '$2 <= now { print $1 }' "$BANS"); do log "ban expired for $ip"; done
    mv "$BANS.tmp" "$BANS"
    write_ban_conf
  else
    rm -f "$BANS.tmp"
  fi
  awk -v min="$((now - BAN_SECONDS))" '$2 > min' "$FAILS" > "$FAILS.tmp"; mv "$FAILS.tmp" "$FAILS"
  # The auth log is in RAM: truncate it when it gets big (tail -F follows it)
  if [ -f "$AUTH_LOG" ] && [ "$(wc -c < "$AUTH_LOG")" -gt "$MAX_LOG_SIZE" ]; then
    : > "$AUTH_LOG"
  fi
}

handle() {
  ip="$1"; status="$2"
  # Only accept IPv4/IPv6 addresses (the header is set by Cloudflare)
  echo "$ip" | grep -q '^[0-9a-fA-F.:]\{3,45\}$' || return 0
  is_banned "$ip" && return 0
  # Successful logins don't reset the counter: several clients can share the
  # same public IP, and a logged in one must not shield an attacker
  if [ "$status" = "401" ]; then
    now=$(date +%s)
    echo "$ip $now" >> "$FAILS"
    count=$(grep -c "^$ip " "$FAILS")
    log "failed login from $ip ($count/$BAN_ATTEMPTS)"
    [ "$count" -ge "$BAN_ATTEMPTS" ] && ban "$ip"
  fi
}

run() {
  if [ "$BAN_ATTEMPTS" -eq 0 ]; then
    log "IP ban disabled (BAN_ATTEMPTS=0)"
    : > "$BANS"; write_ban_conf
    exit 0
  fi
  log "started: ban after $BAN_ATTEMPTS failed logins, for $BAN_TIME minutes"
  touch "$AUTH_LOG"
  write_ban_conf
  FIFO="$STATE/fifo"
  rm -f "$FIFO"; /system/sdcard/bin/busybox mkfifo "$FIFO"
  /system/sdcard/bin/busybox tail -n 0 -F "$AUTH_LOG" > "$FIFO" 2>/dev/null &
  TAIL_PID=$!
  echo "$TAIL_PID" > "$STATE/tail.pid"
  trap 'kill $TAIL_PID 2>/dev/null; rm -f "$FIFO"; exit 0' INT TERM
  exec 3< "$FIFO"
  while true; do
    if read -t 10 ip status <&3; then
      handle "$ip" "$status"
    fi
    expire
  done
}

case "$1" in
  run) run ;;
  list)
    now=$(date +%s)
    while read -r ip until; do
      [ -n "$ip" ] && echo "$ip $(( (until - now + 59) / 60 ))"
    done < "$BANS"
    ;;
  clear)
    : > "$BANS"; : > "$FAILS"
    log "all bans cleared"
    write_ban_conf
    ;;
  *) echo "Usage: $0 run|list|clear" ;;
esac
