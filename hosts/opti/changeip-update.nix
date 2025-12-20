{ pkgs, config, ... }:

let
  changeip-update = pkgs.writeShellApplication {
    name = "changeip-update";
    runtimeInputs = with pkgs; [
      dnsutils
      curl
      gnugrep
      coreutils
    ];
    text = ''
      # Set variables
      LIVE_HOST="wombatzone.changeip.co"
      BMS_HOST="victron-bms.wombatzone.changeip.co"
      # USER is provided by the systemd EnvironmentFile
      # PASS is provided by the systemd EnvironmentFile

      # Lookup IPs (using absolute path for safety, though runtimeInputs handles it)
      liveIP=$(dig +short "$LIVE_HOST" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
      bmsIP=$(dig +short "$BMS_HOST" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)

      if [[ -z "$liveIP" || -z "$bmsIP" ]]; then
          echo "DNS lookup failed. liveIP='$liveIP', bmsIP='$bmsIP'"
          exit 1
      fi

      if [[ "$liveIP" != "$bmsIP" ]]; then
          echo "DNS update required: $liveIP != $bmsIP"
          response=$(curl -s -w "%{http_code}" --user "$USER:$PASS" "https://nic.changeip.com/nic/update?&set=1&ip=$liveIP")
          http_code="''${response: -3}"
          body="''${response::-3}"

          if [[ "$http_code" != "200" ]]; then
              echo "ChangeIP update failed. HTTP $http_code. Response: $body"
              exit 1
          else
              echo "ChangeIP update successful: $body"
          fi
      fi
    '';
  };
in
{
  age.secrets.changeip-credentials.file = ../../secrets/changeip-credentials.age;
  # Create the systemd service and timer
  systemd.services.changeip-update = {
    description = "Update ChangeIP DDNS";
    startAt = "*:0/5"; # Every 5 minutes
    serviceConfig = {
      Type = "oneshot";
      # systemctl show -p ExecStart changeip-update.service
      ExecStart = "${changeip-update}/bin/changeip-update";
      EnvironmentFile = config.age.secrets.changeip-credentials.path;
      User = "root"; # Change to a restricted user if agenix configuration allows
    };
  };
}
