let
  iain = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAuSEf//2a4x+eTqtmhNfQuTJ0vMmGSq5En6FAsxTUYPauzXmH59sG/SRryZpsQq+nGEZLfQ1R2mAq8M71ZJPCCOoYTN3yxdyCpjlodva7+5PpTvE9KQmThlm9Y+RL8dVq413uEwlav2kLa0RBsx10i2vcVMJ1FKno7mQz5/u6G3CXt++YJoPWoNVPIxIIefUot2kj9b2b7wf4EuWPOr5noH41N/E67/1OqfItqaaSGgP9ky9qCKdrI8J1ukhSDsvxmlF/f0kgpl6KVAEpx0/qfVsBoR5BBuNJg8gcWUso0Y92D+7sWULKXZV69Ka4uJ93HqCrKkd1iQpGOO/n6VCRkQ==";

  # users = [ iain ];

  # ssh-keyscan nixos-3a
  nixos-3a = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqMAA/sZuIG4u5p1GVw9evmXkVerZDv87lM8SK1lGHV";
  alarmpi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOc81C+BaiHAbMMA0SrFW/L8smbg0m0UIXdmb5/U1hcg";
  k3sserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDev89Fy7G4ogUsrdcdI1yxWalJr+XTaF5ncI8c03VX1";

  systems = [
    nixos-3a
    alarmpi
  ];
in
{
  # agenix -e itcalde.age
  # generate with 'mkpasswd'
  "itcalde.age" = {
    publicKeys = [
      iain
    ]
    ++ systems;
    armor = true;
  };

  # agenix -e wireless.conf.age
  "wireless.conf.age" = {
    publicKeys = [
      iain
    ]
    ++ systems;
    armor = true;
  };

  # agenix -e fr24key.age
  "fr24key.age" = {
    publicKeys = [
      iain
      nixos-3a
      alarmpi
    ];
    armor = true;
  };

  # agenix -e changeip-credentials.age
  "changeip-credentials.age" = {
    publicKeys = [
      iain
      k3sserver
    ];
    armor = true;
  };
}

# systemctl status run-agenix.d.mount
# systemctl show run-agenix.d.mount
