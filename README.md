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
# sudo nixos-rebuild switch --flake .#nixos
sudo nixos-rebuild switch --rollback
sudo nixos-rebuild switch –-upgrade
sudo nixos-rebuild boot –-upgrade

nixos-rebuild list-generations
sudo nix-collect-garbage -d
sudo nix-collect-garbage –delete-older-than 7d
```

## Home Manager
https://github.com/nix-community/home-manager

https://nix-community.github.io/home-manager/options.xhtml

```bash

# update flake in ~/.config/home-manager to update to update home-manager inputs

home-manager generations
home-manager switch --flake ~/nixos#itcalde
home-manager switch –rollback
home-manager expire-generations "-1 day"
```

## Useful commands

`nix-store --query --requisites /run/current-system`

### why-depends

This command can be used to determine which package is causing curl to be installed, for example.

```bash
# Find the current location of the curl executable
curl_location=$(command -v curl)

# Get the real store path
curl_store_path=$(realpath "$curl_location")

echo "Curl store path: $curl_store_path"

nix why-depends /run/current-system "$curl_store_path"
```