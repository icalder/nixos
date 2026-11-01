# Pin the WiFi regulatory domain instead of inheriting it from the access point.
#
# Why this exists: on 2026-11-01 nixos-3a lost its association at 03:22 and
# cfg80211 logged
#
#     CTRL-EVENT-REGDOM-CHANGE init=CORE type=WORLD
#
# then could not rejoin. Every channel assignment the driver attempted over the
# following six hours failed with `brcmf_set_channel: set chanspec ... fail,
# reason -52`. The mechanism is a lockout: with no user-set country, cfg80211
# restores the world domain when the association goes away, and the world domain
# forbids the higher channels; the only thing that sets a permissive domain here
# was the AP's country information element, which is only received *while*
# associated. Recovery needed a power cycle. See NIXOS-3A-ISSUES.md §4.
#
# `country=` in the wpa_supplicant global config is a *user* regulatory hint.
# A user hint is what cfg80211 restores on teardown instead of the world domain,
# and wpa_supplicant re-applies it each time it starts -- so the companion
# watchdog (modules/wifi-link-watchdog.nix) re-pushes the hint every time it
# restarts the supplicant.
#
# Two settings that look like this one but are not:
#
#   * `cfg80211.ieee80211_regdom` (kernel module parameter) -- sets the initial
#     world domain, not a user hint, and is discouraged upstream.
#   * `networking.wireless.regDomain` -- does not exist in this nixpkgs.
#     `networking.wireless.extraConfig` is the supported way to reach a supplicant
#     global that nixpkgs does not model; its own `example` in the module is
#     another global (`p2p_disabled=1`). It is appended to
#     /etc/wpa_supplicant/nixos.conf among nixpkgs' own globals (`pmf=1`,
#     `bgscan=`), and the supplicant reads globals after a closed network block,
#     which is where they all land.
{
  config,
  lib,
  ...
}:
let
  cfg = config.wifiRegulatory;
  inherit (lib) mkOption types;
in
{
  options.wifiRegulatory.country = mkOption {
    type = types.nullOr (types.addCheck types.str (
      s: builtins.stringLength s == 2 && s == lib.toUpper s
    ));
    default = null;
    example = "GB";
    description = ''
      Two-letter ISO 3166-1 alpha-2 country code, written to the wpa_supplicant
      global configuration as `country=`. `null` leaves the regulatory domain to
      whatever the access point advertises, which is the default behaviour and
      the one that locked nixos-3a out on 2026-11-01.

      Inert on hosts where `networking.wireless.enable` is off, because nothing
      reads the configuration file (rpi4-1).
    '';
  };

  config = lib.mkIf (cfg.country != null) {
    networking.wireless.extraConfig = ''
      # Set by modules/wifi-regulatory.nix. A user regulatory hint survives the
      # loss of the association; a country element learned from the AP does not.
      country=${cfg.country}
    '';
  };
}
