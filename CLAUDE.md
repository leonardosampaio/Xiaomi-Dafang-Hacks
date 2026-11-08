# CLAUDE.md

Custom firmware (CFW) for Ingenic T20 cameras (Xiaomi Dafang, Xiaofang 1S, Wyzecam V2/Pan...).
Everything under `firmware_mod/` is copied to the root of a FAT32 SD card and runs from
`/system/sdcard` on the camera. There is no build step: the code is shell scripts, CGI
scripts, static web files and prebuilt MIPS binaries.

## Layout

- `firmware_mod/run.sh` – startup script (logs, bind mounts of `etc`/`root`/busybox, swap,
  crond, network, timezone, NTP, drivers, OSD/motion, then `config/autostart/*`).
- `firmware_mod/scripts/common_functions.sh` – shared helpers (`rewrite_config`, LEDs,
  `set_timezone`, `remount_sdcard`/`remount_sdcard_ro`, `sdcard_ro_state`,
  `wpa_networks_list`/`wpa_ssid_decode`...). Sourced by scripts and CGIs.
- `firmware_mod/scripts/wifi.sh` – station/AP state machine: `wpa_supplicant` + watchdog
  (no connection within `connect_timeout` → AP), AP + `ap_timer` (after `ap_timeout`, or
  when no client is connected, → station again). `wpa_action.sh` is the `wpa_cli` hook.
- `firmware_mod/scripts/sdcard_data.sh` – data partition (`mmcblk0p2`) of two partition
  cards: first boot expansion (writes p2's size in the MBR, offset 474, then reboots),
  format, `fsck.vfat -a`, mount on `/system/sdcard/data`, bind mounts of `DCIM/`,
  `time_lapse/`. Called at the start of `run.sh`. Logs are always in a tmpfs (10 MB).
- `firmware_mod/scripts/tunnel-ban.sh` – IP ban daemon for failed logins through the
  Cloudflare Tunnel (started/stopped by `controlscripts/cloudflared`; state in `/tmp`).
- `firmware_mod/controlscripts/<service>` – one script per service, `start|stop|status`,
  pid file in `/run/<service>.pid`. Autostart = `config/autostart/<service>` (a two-line
  script calling the control script).
- `firmware_mod/config/*.conf.dist` – default configs; the real `*.conf` is created from
  the `.dist` on first use. Configs are **sourced by the shell**, so values written from
  the web UI must be validated (see `save_config_cloudflared` in `ui_net_services.cgi`).
  Personal `*.conf` files are in `.gitignore`.
- `firmware_mod/www/` – web UI (lighttpd + jQuery + w3.css). Each page `X.html` has
  `js/X.js` and `cgi-bin/ui_X.cgi`.
  - CGIs source `func.cgi`, which turns query/POST params into `F_<name>` variables
    (still URL-encoded: decode with `printf '%b' "${F_x//%/\\x}"`; jQuery encodes spaces as `+`).
  - Responses use the `key#:#value` line format; `getConfig()` in the JS fills the element
    with `id=key`.
  - Services listed in *Control System > Services*: `services=` list in
    `cgi-bin/ui_control.cgi` + `serviceFriendlyNames` in `js/control.js`.
  - Network services tabs: `net_services.html` + `get_config_<x>`/`save_config_<x>` in
    `cgi-bin/ui_net_services.cgi`.
  - Wifi networks: `get_wifi_networks`/`save_wifi_networks` in `ui_system.cgi`; "keep the
    password" refers to the network by its **position** in the list (`net_orig_N`), not by
    SSID (two networks can have the same SSID).
  - SD card badge in the top bar (`index.html`/`js/index.js`): `sdcard_status`,
    `sdcard_config`, `sdcard_remount` in `ui_sdcard.cgi`.
  - `func.cgi` `eval`s the parameters: jQuery's `encodeURIComponent` leaves `!'()*`
    unescaped, which breaks the `eval`. Encode them too when posting free text
    (`cgiEncode()` in `js/system.js`).
  - Unquoted `[ -n ${F_x} ]` is always true: quote it or use `${F_x+x}`. Password fields
    prefilled with `*****` must be ignored when unchanged.
- `firmware_mod/bin`, `lib`, `driver` – prebuilt binaries for mipsle (uClibc).
- `hacks/`, `information/`, `integration/` – documentation.

## Target device

- Ingenic T20 (MIPS32 little-endian, XBurst), Linux 3.10.14, ~100 MB RAM, no swap besides
  zram. BusyBox shell (`sh`/ash): no bash-only syntax in scripts that run on the camera
  (CGIs already use some ash extensions like `${var//a/b}`, which BusyBox ash supports).
- Go binaries: `GOOS=linux GOARCH=mipsle GOMIPS=softfloat CGO_ENABLED=0`.
  `cloudflared` (not in the repo, ~29 MB) is built from its git tag with
  `go build -mod=mod -trimpath -ldflags "-s -w -X main.Version=<tag>" ./cmd/cloudflared`
  (its `vendor/` is out of sync, so `-mod=mod` is required) and copied to
  `/system/sdcard/bin/cloudflared`.
- TLS clients need `/system/sdcard/config/ssl/cacert/cacert.pem` (there is no `/etc/ssl`)
  and a correct clock: without NTP the clock starts in 1970 and TLS fails.
- Validate scripts locally with `sh -n` / `bash -n` before deploying; for logic, run the
  CGI locally with `busybox sh`, `REQUEST_METHOD`/`QUERY_STRING` (or POST body on stdin)
  and the `/system/sdcard` paths rewritten to a temporary folder.
- Some BusyBox applets are not in `PATH` on the camera (e.g. `mkfifo`): call them as
  `/system/sdcard/bin/busybox <applet>`. There is no `od`, `which`, `ip`, `ifconfig`,
  `route` or `iptables` (use `/proc/net/route`, `netstat`, `hexdump`).
- The kernel only supports `vfat`/`msdos` for the SD card (no ext4, NTFS or FUSE). The
  firmware in flash (`/etc/init.d/rcS`) mounts only `/dev/mmcblk0p1` and runs `run.sh`.
- There is **no working `sync`** (the card's busybox, bind mounted over `/bin/busybox`, has
  no `sync` applet): use `sd_sync` (`blockdev --flushbufs`) from `common_functions.sh`.
- `killall <name>` doesn't find daemons started as `busybox <applet>` (e.g. crond): kill by PID.
- Watchdog resets show up as `CPU0 RESET ERROR PC:<addr>` at the top of `dmesg`; look the
  address up in `/proc/kallsyms`.
- lighttpd (1.4.56-devel build):
  - A graceful reload (`kill -USR1`) **kills the server when clients are connected**: restart
    it (`controlscripts/lighttpd stop; start`) instead.
  - `include_shell` must exit 0 (`cat file 2>/dev/null || true`).
  - Modules run in `server.modules` order: `mod_access` must come before `mod_auth`.
  - Test config changes on a copy in `/tmp` with other ports before touching the real one.

## Local device (this checkout)

- SSH command is in `ssh.txt` (git-ignored). **Never print its contents or the password**;
  run it with something like `eval "$(grep -v '^#' ssh.txt | head -1) '<cmd>'"`.
- Camera at `192.168.0.10`. The firmware on its SD card is **older than this repo**
  (e.g. `ftp_server`, `mqtt_control`, `onvif-srvd.sh` instead of the current names), so do
  not copy repo files over the card wholesale: compare with `git show HEAD:<file>` first and,
  if the card differs, apply only the diff (`git diff -- <file> | patch`).
- The SD card can drop to read-only after an unclean shutdown (FAT errors in `dmesg`); it
  happened several times, and the camera rebooted often on 2026-11-08 (cause unknown).
  A reboot doesn't fix it. Don't remount it rw without asking; fix it with `chkdsk D: /f`
  on Windows (the `chkdsk` process keeps `D:` locked until its window is closed).
- **Before deploying, check that the card is `rw`** (`mount | grep sdcard`), and **after
  deploying, compare md5sums**: writes to a read-only card fail silently when stderr is
  discarded (`2>/dev/null`).
- Deploy over SSH with `eval "$SSHCMD 'cat > /system/sdcard/<f>.new && mv ...'" < file`
  (piping into `eval` doesn't work in this zsh setup).
- Never hardcode test data that depends on the camera state (e.g. the order of the wifi
  networks): build it from a `get` first. Changing the wifi config remotely can leave the
  camera offline (only recoverable through the SD card).
- The PC and the user's browser share the same public IP: testing the tunnel ban
  from here also bans the user's own session (release it right after).
- When the card is in the PC it shows up in Windows (WSL host) as a removable drive (`D:`
  last time) and is not mounted in WSL (no passwordless sudo). Use `robocopy` /
  `powershell.exe` from WSL; the PowerShell is old (no `Get-FileHash`/`Format-Hex`).
  The WSL shell is zsh (unquoted variables are not word-split).
- Backups of the card go to `~/backups/dafang-sdcard-<date>[-b]/`; backups of edited configs
  on the card itself are `config/*.bak-20261108*`.
- A two partition image of this card (p1 512 MiB + p2 256 MiB, expands on first boot) is in
  `~/backups/dafang-2part-2026-11-08/` (contains wifi passwords, tunnel token, SSH host keys).
  It was built without root: `mkfs.vfat` + `mcopy` on partition files, `sfdisk` + `dd`
  into the image; verify by extracting p1 again and `diff -r`.
- Wifi on the card: `LRS_IoT` (priority 2) and `LRS` (priority 1); AP `dafang1-sem-rede`;
  `connect_timeout=30`, `ap_timeout=300`.
- Web server on the card: HTTPS on 443 enabled, no password for LAN clients; requests
  from `127.0.0.1` (i.e. through the Cloudflare Tunnel →
  `https://localhost:443`) require the user in `config/lighttpd.tunnel.user`. Never expose
  the web UI without that block. The card's `lighttpd.conf` also has the IP ban block,
  `mod_access` first and `server.tag = ""`. Check the config with
  `LD_LIBRARY_PATH=/system/sdcard/lib:/thirdlib:/system/lib bin/lighttpd -t -f <file>`
  (the old `bin/lighttpd` wrapper on cards didn't export the library path, so starting it
  from SSH failed; fixed in the repo and on this card).
- `ntpd` is restarted when the wifi connects (`wifi.sh`), since a boot without network left
  the clock in 1970. `cloudflared` autostart is off on the card.
- Local preferences: NTP `pool.ntp.br`, timezone `America/Fortaleza`.

## Contributing

Upstream PRs go against the `beta` branch.
