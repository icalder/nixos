{ pkgs, fr24feed, configHostPath ? "/etc/fr24feed.ini", ... }:

pkgs.buildFHSEnv {
  name = "fr24feed-fhs";

  targetPkgs = pkgs: [
    fr24feed
  ];

  runScript = "/bin/fr24feed --config-file=/etc/fr24feed.ini";

  extraBwrapArgs = [
    "--ro-bind"
    configHostPath
    "/etc/fr24feed.ini"
    "--bind"
    "/dev/shm"
    "/dev/shm"
    "--bind"
    "/var/log/fr24feed"
    "/var/log/fr24feed"
  ];
}
