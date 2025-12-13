{ pkgs, fr24feed, ... }:

pkgs.buildFHSEnv {
  name = "fr24feed-fhs";

  targetPkgs = pkgs: [
    fr24feed
  ];

  runScript = "/bin/fr24feed --config-file=/etc/fr24feed.ini";

  extraBwrapArgs = [
    "--bind"
    "/dev/shm"
    "/dev/shm"
    "--bind"
    "/var/log/fr24feed"
    "/var/log/fr24feed"
    "--bind"
    "/etc/fr24feed.ini"
    "/etc/fr24feed.ini"
  ];
}
