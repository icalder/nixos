# Restart the supplicant, and bounce the link if that is not enough, when the
# wireless carrier is lost.
#
# Why this exists: nixos-3a lost its association at 03:22 on 2026-11-01 and did
# not rejoin for seven hours. The machine was not hung -- journald, fr24feed and
# timesyncd all kept logging until 09:12 -- it was simply offline, and a
# Raspberry Pi 3 Model A Plus has no Ethernet, so nothing could reach it and
# nothing on it noticed. A hardware watchdog would not have fired either, because
# systemd's event loop was alive the whole time (NIXOS-3A-ISSUES.md §2, §7.6).
#
# The signal is `/sys/class/net/<iface>/carrier`. cfg80211 clears carrier when
# the interface leaves the associated state, which is exactly the transition that
# went unnoticed; it is also the same signal dhcpcd used to log `wlan0: carrier
# lost` at 03:22:17. It needs no new packages and no state.
#
# `wpa_cli` is deliberately not used. nixpkgs hardens the supplicant instances
# with `RootDirectory=/run/wpa_supplicant` and `ctrl_interface=
# /run/wpa_supplicant/control`, so the control socket is not reachable from the
# host: `/run/wpa_supplicant` ends up holding systemd's chroot scaffolding
# (dev, etc, nix, proc, root, run, sys, tmp, usr, var) and no socket, and
# `wpa_cli -i wlan0 status` fails with "Failed to connect to non-global
# ctrl_ifname". That is upstream behaviour, not local configuration, so it is
# left alone and the watchdog reads sysfs instead.
#
# Escalation is two stages because the two failure shapes need different levers:
# a supplicant that gave up on the BSSID is fixed by a restart (which also
# re-applies the `country=` regulatory hint -- see
# modules/wifi-regulatory.nix), while a brcmfmac firmware wedge of the kind the
# 2026-11-01 journal shows (`brcmf_set_channel: set chanspec ... fail, reason
# -52`) needs the interface re-initialised.
#
# To stop it fighting an operator: `systemctl stop wifi-link-watchdog.timer`, or
# `touch /run/wifi-link-watchdog/disable` for a single run at a time (it lives on
# tmpfs, so it clears at boot).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.wifiLinkWatchdog;
  inherit (lib) concatStringsSep mkIf mkOption types;

  supplicantUnit = "wpa_supplicant-${cfg.interface}.service";

  # Both the per-interface and the single-instance spelling are listed; the
  # script only touches units that exist. nixos-3a runs `dhcpcd.service`.
  dhcpUnits = [
    "dhcpcd@${cfg.interface}.service"
    "dhcpcd.service"
    "systemd-networkd.service"
  ];

  # Absolute paths throughout: a systemd unit on NixOS has no usable PATH, and
  # this script is run by systemd, not by a login shell.
  script = pkgs.writeShellScript "wifi-link-watchdog" ''
    set -u

    # The two overrides exist so the failure path can be exercised against a
    # nonexistent interface, off the real radio and off the real counter:
    #   WIFI_LINK_WATCHDOG_INTERFACE=does-not-exist wifi-link-watchdog
    IFACE="''${WIFI_LINK_WATCHDOG_INTERFACE:-${cfg.interface}}"
    THRESHOLD=${toString cfg.missesBeforeAction}
    STATE_DIR="''${WIFI_LINK_WATCHDOG_STATE_DIR:-/run/wifi-link-watchdog}"
    CARRIER_FILE="/sys/class/net/''${IFACE}/carrier"
    SUPPLICANT_UNIT='${supplicantUnit}'
    CAT='${pkgs.coreutils}/bin/cat'
    ECHO='${pkgs.coreutils}/bin/echo'
    LOGGER='${pkgs.util-linux}/bin/logger'

    # Everything the check decides goes to the journal. The point of this unit is
    # to leave a record of a link loss that nobody noticed, so it narrates itself.
    log() {
      "''${LOGGER}" -t wifi-link-watchdog "$*"
    }
    SYSTEMCTL='${pkgs.systemd}/bin/systemctl'
    IP='${pkgs.iproute2}/bin/ip'
    MKDIR='${pkgs.coreutils}/bin/mkdir'
    SLEEP='${pkgs.coreutils}/bin/sleep'

    if [ -e "''${STATE_DIR}/disable" ]; then
      exit 0
    fi
    "''${MKDIR}" -p "''${STATE_DIR}"

    carrier="$(''${CAT} ''${CARRIER_FILE} 2>/dev/null || ''${ECHO} 0)"
    misses="$(''${CAT} ''${STATE_DIR}/misses 2>/dev/null || ''${ECHO} 0)"

    if [ "''${carrier}" = "1" ]; then
      if [ "''${misses}" != "0" ]; then
        log "carrier restored on ''${IFACE} after ''${misses} missed check(s)"
        ''${ECHO} 0 > "''${STATE_DIR}/misses"
      fi
      exit 0
    fi

    misses=$((misses + 1))
    ''${ECHO} "''${misses}" > "''${STATE_DIR}/misses"
    log "no carrier on ''${IFACE} (missed check ''${misses}, acting at ''${THRESHOLD})"

    if [ "''${misses}" -lt "''${THRESHOLD}" ]; then
      exit 0
    fi

    restart_units() {
      for unit in "$@"; do
        if "''${SYSTEMCTL}" -q is-enabled "''${unit}" 2>/dev/null \
          || "''${SYSTEMCTL}" -q is-active "''${unit}" 2>/dev/null; then
          log "restarting ''${unit}"
          "''${SYSTEMCTL}" restart "''${unit}" || log "restarting ''${unit} failed"
        fi
      done
    }

    stage=1
    if [ "''${misses}" -ge "$((THRESHOLD * 2))" ]; then
      stage=2
      log "stage 2: supplicant restarts have not restored the link, bouncing ''${IFACE}"
      "''${IP}" link set "''${IFACE}" down
      ''${SLEEP} 5
      "''${IP}" link set "''${IFACE}" up
      ''${SLEEP} 10
    fi

    restart_units "''${SUPPLICANT_UNIT}"
    if [ "''${stage}" = 2 ]; then
      restart_units ${concatStringsSep " " (map (u: "'${u}'") dhcpUnits)}
    fi

    # Give reassociation and DHCP a chance before reporting, so the next line in
    # the journal says whether the action worked. The counter is left alone here:
    # it resets only when carrier is seen again, so a link that is still down
    # escalates on the next check.
    ''${SLEEP} 20
    after="$(''${CAT} ''${CARRIER_FILE} 2>/dev/null || ''${ECHO} 0)"
    log "stage ''${stage} done on ''${IFACE}: carrier=''${after}, misses=''${misses}"
  '';
in
{
  options.wifiLinkWatchdog = {
    # A plain mkEnableOption would mean every wireless host has to remember to
    # turn it on. The thing being watched only exists when the host runs
    # wpa_supplicant, so that is the default; a host can still say
    # `wifiLinkWatchdog.enable = false` to opt out.
    enable = mkOption {
      type = types.bool;
      default = config.networking.wireless.enable;
      description = ''
        Run a periodic check that restarts the wireless supplicant, and bounces
        the interface if that has not restored the link, when the wireless
        carrier is lost. Defaults to whether the host runs wpa_supplicant at
        all, so wired hosts get nothing.
      '';
    };

    interface = mkOption {
      type = types.str;
      default = "wlan0";
      description = "Wireless interface to watch.";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "2min";
      example = "5min";
      description = ''
        How often to check, which is also how long the link has to recover on its
        own before the first action is taken (missesBeforeAction checks).
      '';
    };

    missesBeforeAction = mkOption {
      type = types.ints.positive;
      default = 3;
      description = ''
        Consecutive failed checks before acting. The point is to ride out a
        normal reassociation or a rekey, which clears carrier for a few seconds,
        so this must be comfortably longer than one such blip. Stage 2 -- the
        link bounce -- starts at twice this many misses.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.wifi-link-watchdog = {
      description = "Restart wpa_supplicant and bounce ${cfg.interface} when its carrier is lost";
      unitConfig.ConditionPathExists = [ "/sys/class/net/${cfg.interface}/carrier" ];
      serviceConfig = {
        Type = "oneshot";
        # Covers the built-in sleeps plus two unit restarts.
        TimeoutStartSec = "3min";
        ExecStart = [ "${script}" ];
      };
    };

    systemd.timers.wifi-link-watchdog = {
      description = "Periodic wireless carrier check for ${cfg.interface}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Give the first association of the boot time to complete.
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.checkInterval;
        AccuracySec = "10s";
      };
    };
  };
}
