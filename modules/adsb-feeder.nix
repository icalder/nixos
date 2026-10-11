# The ADS-B feeder chain: RTL-SDR dongle -> dump1090-fa -> { nginx map,
# fr24feed, adsbexchange container }.
#
# alarmpi and nixos-3a run the identical chain and share one fr24 key, so only
# one of them may feed at a time. This module is the whole thing behind one
# boolean, so failing over is a single line in a host config rather than
# copying a block of options between two files that have already drifted apart.
#
# To fail over from nixos-3a to alarmpi:
#
#   hosts/nixos-3a/configuration.nix     adsbFeeder.enable = false;
#   hosts/alarmpi/configuration.nix      adsbFeeder.enable = true;
#
# then rebuild both, the old feeder first. alarmpi is already a recipient of
# secrets/fr24key.age, so no re-encryption is needed.
#
# Enabling this on a Raspberry Pi 3 B+ costs roughly 60 MiB of RAM and a
# resident Debian guest, which is why it is off on alarmpi by default: that box
# has 865 MiB total and spends its Sunday night rebuilding inside it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.adsbFeeder;
in
{
  options.adsbFeeder = {
    enable = lib.mkEnableOption ''
      the ADS-B feeder chain: dump1090-fa, its nginx map, fr24feed and the
      adsbexchange container. Enable on exactly one host at a time, since the
      feeders share a single fr24 key
    '';

    latitude = lib.mkOption {
      type = lib.types.str;
      default = "51.87696";
      description = "Antenna latitude, passed to dump1090-fa for range/MLAT maths.";
    };

    longitude = lib.mkOption {
      type = lib.types.str;
      default = "-2.20132";
      description = "Antenna longitude, passed to dump1090-fa for range/MLAT maths.";
    };
  };

  config = lib.mkMerge [
    # Turning the chain off has to be more than "stop creating the units",
    # because NixOS never removes enable symlinks for units it has stopped
    # managing. A host that once ran the container keeps booting it after
    # failing back, and the guest then crash-loops its own journald and
    # segfaults feed-adsbx forever -- which is what used to happen on alarmpi
    # every Sunday during the rebuild.
    (lib.mkIf (!cfg.enable) {
      systemd.targets.machines.enable = false;

      system.activationScripts.adsb-feeder-drop-stale-units = {
        # No deps: systemctl and rm need nothing that activation ordering can
        # supply, and naming a script that does not exist here breaks the
        # toplevel's dependency resolution.
        text = ''
          # disable takes no job, so it is safe to wait on; stop does, and
          # activation runs synchronously, so a wedged guest must not be able to
          # hang the whole switch. Both stay silent when there is nothing to do.
          ${pkgs.systemd}/bin/systemctl disable systemd-nspawn@adsbexchange.service || true
          ${pkgs.systemd}/bin/systemctl stop --no-block systemd-nspawn@adsbexchange.service || true
          ${pkgs.systemd}/bin/systemctl stop --no-block machines.target || true

          # reset-failed is the one call that complains on a host that never ran
          # the guest, because the instance is never loaded, and it printed
          #   Failed to reset failed state of unit systemd-nspawn@adsbexchange.service:
          #   Unit systemd-nspawn@adsbexchange.service not loaded.
          # into every activation. Noise on a clean switch is not harmless: it is
          # what you read past when the real thing appears. Guarded on the unit
          # actually being failed. Probing LoadState instead does not work --
          # systemctl show loads the unit in order to answer and reports it
          # loaded, which is exactly the state reset-failed rejects.
          if ${pkgs.systemd}/bin/systemctl is-failed systemd-nspawn@adsbexchange.service >/dev/null 2>&1; then
            ${pkgs.systemd}/bin/systemctl reset-failed systemd-nspawn@adsbexchange.service || true
          fi

          # The symlinks are what make the guest come back on every boot, so they
          # are removed unconditionally; rm is silent when the path is already
          # gone, and they can outlive the unit being loadable.
          rm -rf /etc/systemd/system/systemd-nspawn@adsbexchange.service.d
          rm -f /etc/systemd/system/machines.target.wants/systemd-nspawn@adsbexchange.service
        '';
      };
    })

    (lib.mkIf cfg.enable {
      systemd.targets.machines.enable = true;

      age.secrets.fr24key = {
        file = ../secrets/fr24key.age;
        owner = "root";
        group = "fr24feed";
        mode = "0440";
      };

      services.fr24feed = {
        enable = true;
        fr24key = config.age.secrets.fr24key.path;
      };

      services.dump1090-fa = {
        enable = true;
        extraArgs = [
          "--quiet"
          "--adaptive-range"
          "--lat"
          cfg.latitude
          "--lon"
          cfg.longitude
        ];
      };

      # dump1090-fa's unit sandboxes the network by default, which prevents the
      # Beast/SBS output the other feeders connect to on localhost.
      systemd.services.dump1090-fa.serviceConfig = {
        PrivateNetwork = lib.mkForce false;
        Restart = "always";
        RestartSec = "5s";
      };

      services.nginx = {
        enable = true;
        virtualHosts."default" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = 80;
            }
          ];
          locations."/dump1090" = {
            return = "301 /dump1090/";
          };
          locations."/dump1090/data/" = {
            alias = "/run/dump1090-fa/";
            extraConfig = "expires off;";
          };
          locations."/dump1090/" = {
            alias = "${pkgs.dump1090-fa}/share/dump1090/";
            index = "index.html";
          };
        };
      };

      # Unpacking the guest rootfs has to happen in an activation script because
      # ExecStartPre cannot mknod under /var/lib/machines.
      system.activationScripts.prepare-adsbexchange-machine = {
        deps = [ "users" ];
        text = ''
          IMAGE_DEST="/var/lib/machines/adsbexchange"
          if [ ! -d "$IMAGE_DEST" ]; then
            echo "Deploying adsbexchange machine image during system activation..."
            mkdir -p "$IMAGE_DEST"
            ${pkgs.gnutar}/bin/tar --use-compress-program=${pkgs.gzip}/bin/gzip -xpf ${pkgs.adsbexchange-fs}/rootfs.tar.gz -C "$IMAGE_DEST" --numeric-owner --xattrs --xattrs-include='*'
          fi
        '';
      };

      systemd.nspawn.adsbexchange = {
        enable = true;
        execConfig = {
          Boot = true;
        };
        networkConfig = {
          VirtualEthernet = "no";
        };
        filesConfig = {
          BindReadOnly = [ "/etc/resolv.conf:/etc/resolv.conf" ];
        };
      };

      systemd.services."systemd-nspawn@adsbexchange" = {
        wantedBy = [ "machines.target" ];
        # https://mynixos.com/nixpkgs/option/systemd.mounts.*.overrideStrategy
        overrideStrategy = "asDropin";
      };
    })
  ];
}
