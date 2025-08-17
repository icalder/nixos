# NIXOS Configuration Stuff

## Key Links
https://nix.dev/tutorials/nix-language.html

https://search.nixos.org/packages
https://search.nixos.org/options

https://noogle.dev/

https://book.divnix.com/


## Symlinks

```bash
pushd /etc/nixos
sudo ln -sf /home/itcalde/nixos/configuration.nix .

pushd ~/.config/home-manager/
ln -sf ~/nixos/home.nix .
```

## System Configuration

```bash
sudo nixos-rebuild switch
sudo nixos-rebuild switch --rollback
sudo nixos-rebuild switch –-upgrade
sudo nixos-rebuild boot –-upgrade

nixos-rebuild list-generations
sudo nix-collect-garbage -d
sudo nix-collect-garbage –delete-older-than 7d
```

## Channels

```bash
sudo nix-channel --list
sudo nix-channel --add https://channels.nixos.org/nixos-25.05 nixos
sudo nix-channel –-update nixos
sudo nix-channel –-update
```

## Home Manager
https://github.com/nix-community/home-manager

https://nix-community.github.io/home-manager/options.xhtml

```bash
home-manager generations
sudo nix-channel –update
home-manager switch
home-manager switch –rollback
home-manager expire-generations "-1 day"
```