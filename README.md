## Xiaomi DaFang Hacks / XiaoFang 1S / Wyzecam V2 / Wyzecam Pan / Other T20 Devices

[![Join the chat at https://gitter.im/Xiaomi-Dafang-Hacks/Lobby](https://badges.gitter.im/Xiaomi-Dafang-Hacks/Lobby.svg)](https://gitter.im/Xiaomi-Dafang-Hacks/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

This repository contains custom firmware for the following devices:

Name | Picture
--- | ---
Xiaomi Dafang | ![Dafang](/dafang.png)
Xiaomi Xiaofang 1S (old Version with T20 is supported, newer Version with T20L is in beta) | ![XiaoFang](/xiaofang.png)
Wyzecam Pan | ![Dafang](/dafang.png)
Wyzecam V2 | ![XiaoFang](/xiaofang.png)
Neos SmartCam | ![XiaoFang](/xiaofang.png)
Sannce I21AG, MixSight HX-I2110T2, WanScam HW0036, Digoo BB-M2 | ![XiaoFang](/sannce.jpg)
Any other Device with Ingenic T10/T20 Device https://github.com/EliasKotlyar/Xiaomi-Dafang-Hacks/issues/980 | ![T20](/t20.png)

If you want to test the Xiaofang T20L (newer version) please check out the [additional instructions](https://github.com/EliasKotlyar/Xiaomi-Dafang-Hacks/blob/master/hacks/install_cfw_t20l.md).

If you have a classic XiaoFang with a ARM-Processor, consider using https://github.com/samtap/fang-hacks

### Attention: Do not install the latest Firmware on your Device. It will disable the support of this hack. 

Further information about this topic can be found here: https://github.com/EliasKotlyar/Xiaomi-Dafang-Hacks/issues/669


## How to install the CFW

Before you try to install it, please read the [FAQ](/hacks/faq.md)

After that, continue to the
[Installation](/hacks/install_cfw.md)


### Support

If you encounter a problem, please see first if you find similiar open/closed issues. 
Or ask in our [Gitter channel](https://gitter.im/Xiaomi-Dafang-Hacks/Lobby) for help.

If you don't find anything related, feel free to open a new issue.
If you/we solve your issue, please condense your gained insights into a pull request for continuous self-improvement.

### Partner Community:

We are really excited to announce that we have now a open source partner community, which provides a lot of content about the T10/T20/T30 Devices

![Ebaina](/ebaina.png)

Start here for more informations:
http://bbs.ebaina.com/thread-53811-1-1.html

欢迎来到这个存储库亲爱的朋友们。 从这里开始，获取关于在您的设备上获取此hack的教程：[开始](/hacks/install_cfw_cn.md)



## Technical Information about the hack:

Start [here](/hacks/technical.md)

## Integration in Home Automation Systems:

[Domoticz](/integration/domoticz/domoticz.md)

[Home Assistant](/integration/homeassistant/homeassistant.md)

[HomeKit](/integration/homekit/homekit.md)

[OpenHab](https://community.openhab.org/t/how-to-configure-a-hacked-xiaomi-dafang-to-work-with-openhab/51121)

[Synology](/integration/synology/synology.md)

[tinyCam](/integration/tinycam/tinycam.md)

[Zoneminder](/integration/zoneminder/zoneminder.md)

## Other features

### Motion detection

It is possible to run your own scripts on motion detection. See [here](/integration/custom/motiondetection.md)

### Cloudflare Tunnel

The camera can be published through a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (`cloudflared`), so the web UI, RTSP or SSH can be reached from outside without opening ports on your router.

1. Create a tunnel in the Cloudflare Zero Trust dashboard (*Networks > Tunnels*) and copy its token.
2. Add public hostnames pointing to the camera services, e.g. `https://localhost:443` (enable *No TLS Verify*, the certificate is self-signed) or `ssh://localhost:22`.
3. Cloudflare doesn't publish MIPS builds, so build `cloudflared` for the camera and copy it to `/system/sdcard/bin/cloudflared`:
   ```
   git clone https://github.com/cloudflare/cloudflared.git && cd cloudflared
   GOOS=linux GOARCH=mipsle GOMIPS=softfloat CGO_ENABLED=0 go build -mod=mod -trimpath -ldflags "-s -w" -o cloudflared ./cmd/cloudflared
   ```
4. In the web UI, paste the token in *Network services configuration > Cloudflare Tunnel* and start the service (and enable autostart) in *Control System > Services*.
5. In the same tab, set the user and password for access through the tunnel. `cloudflared` connects to the web server from `127.0.0.1`, and `lighttpd` asks for this user/password only for those connections ([lighttpd.conf.dist](/firmware_mod/config/lighttpd.conf.dist)); access from the local network is not affected. Until a user is set, every request through the tunnel is denied. The password is stored only as a hash in `config/lighttpd.tunnel.user`.
6. Optionally adjust the **failed login ban** in the same tab: an IP that fails the tunnel login *N* times within *T* minutes is blocked (HTTP 403) for *T* minutes (default 5 attempts / 15 minutes, 0 attempts disables it). The tab lists the banned IPs and has a button to release them.

How the ban works: `lighttpd` logs the tunnel requests that carry credentials, with the client IP from the `CF-Connecting-IP` header (set by Cloudflare), to `/tmp/lighttpd-tunnel-auth.log`. [tunnel-ban.sh](/firmware_mod/scripts/tunnel-ban.sh), started together with `cloudflared`, counts the 401 responses per IP and writes the ban rule to `/tmp/lighttpd-tunnel-ban.conf`, which `lighttpd.conf` includes; `lighttpd` is then restarted (about 2 seconds). Successful logins from the same IP don't reset the counter. Everything is kept in RAM, so it also works with the SD card read-only, and bans are cleared on reboot. `mod_access` must come before `mod_auth` in `server.modules`, otherwise banned IPs could keep trying passwords.

The camera clock must be correct (NTP), otherwise the TLS connection to Cloudflare fails. Settings are stored in `config/cloudflared.conf` (see [cloudflared.conf.dist](/firmware_mod/config/cloudflared.conf.dist)) and the log in `/system/sdcard/log/cloudflared.log`.

### Read-only SD card

Power loss while the camera is writing can corrupt the FAT file system of the SD card (the kernel then remounts it read-only on its own, with `FAT-fs ... Filesystem has been set read-only` in `dmesg`). Rebooting doesn't fix it: put the card in a PC and run `chkdsk X: /f` (Windows) or `fsck.vfat -a` (Linux).

To avoid this, the card can be forced read-only after startup ([sdcard.conf.dist](/firmware_mod/config/sdcard.conf.dist), `SDCARD_READONLY=true`). In this mode the logs are kept in RAM, and anything that writes to the card (saving settings in the web UI, recordings, timelapse, updates, a swap file on the SD card) stops working.

The top bar of the web UI shows the mode of the card (**SD: read-write** in green, **SD: read-only** in orange, or in red when the kernel set it read-only because of file system errors). Clicking it shows the reason and has shortcuts to enable/disable the read-only mode and to make the card writable (or read-only) until the next reboot, e.g. to change some settings. The shortcuts are disabled while the card has file system errors.

The camera kernel only supports FAT (`vfat`) on the SD card: ext4 or NTFS would need a different kernel.

Logs (`/system/sdcard/log`) are always kept in RAM (tmpfs, 10 MB by default, `SDCARD_LOG_TMPFS_SIZE` in `config/sdcard.conf`) and lost on reboot.

### Two partition SD card

A card can have a second FAT32 partition (`mmcblk0p2`, *data*) for recordings and timelapse, so the system partition (`mmcblk0p1`, mounted by the camera firmware) can stay read-only. On every boot [sdcard_data.sh](/firmware_mod/scripts/sdcard_data.sh) repairs it with `fsck.vfat -a` before mounting it on `/system/sdcard/data` (not possible for the system partition, which is already mounted) and bind mounts `DCIM/` and `time_lapse/` from it. When the system partition has a `.expand_data` file, the first boot grows the data partition to the end of the card (only the size in the partition table changes), reboots once and formats it.

To make such a card: one FAT32 partition of ~512 MB with the firmware (plus empty `data/`, `log/`, `DCIM/` and `time_lapse/` folders and an empty `.expand_data` file), followed by a small FAT32 partition. The top bar of the web UI then shows the mode of each partition, and each one can be made read-only or writable until reboot or at boot (`SDCARD_READONLY` / `DATA_READONLY` in `config/sdcard.conf`).

### Wifi networks and access point fallback

*System configuration > Network* lists the wifi networks the camera can connect to (SSID, password, priority, hidden). The camera connects to the available network with the highest priority; leave the password empty to keep the current one. The networks are stored in `config/wpa_supplicant.conf`.

If the camera is connected when the networks are saved and can't reconnect within 25 seconds, the previous networks are restored automatically.

If no network connects within the *Wifi Connect Timeout* (default 30 seconds, also after a disconnection), the camera opens its own access point (*Access Point SSID/Password*, at least 8 characters; the web UI is at `http://10.0.0.1`) for the *Access Point Duration* (default 5 minutes) and then tries the networks again. The access point stays open while a client is connected to it, and indefinitely when no network is configured. These times are in `config/wifi.conf` ([wifi.conf.dist](/firmware_mod/config/wifi.conf.dist)).

## Contributions:

Any contribution to the development is highly welcome. Simply open a pull request against our beta branch on GitHub.
