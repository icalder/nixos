# cd ~/.config/home-manager
# ln -sf ~/nixos/home.nix .

{
  config,
  pkgs,
  unstable-pkgs,
  ...
}:

# Home manager options search: https://home-manager-options.extranix.com/?query=ssh&release=release-24.05

let
  config-dir =
    if builtins.getEnv ("XDG_CONFIG_DIR") != "" then
      builtins.getEnv ("XDG_CONFIG_DIR")
    else
      "${config.home.homeDirectory}/.config";
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "itcalde";
  home.homeDirectory = "/home/itcalde";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')

    # LSP server
    pkgs.nil
    pkgs.nixfmt-rfc-style
    # Include nodejs by default as it's required by many agents and tools
    pkgs.nodejs
    # Required for paplay
    pkgs.pulseaudio
    pkgs.file
    pkgs.skopeo
    pkgs.agenix
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    ".config/nixpkgs/config.nix".text = ''
      {
        allowUnsupportedSystem = true;
      }
    ''; # to allow aarch64 on x86_64 host

    # ".config/warp-terminal/user_preferences.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/warp-terminal.json"; # warp terminal
    # ".config/Code/User/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/vscode-settings.json"; # vscode settings.json

    ".gitconfig".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/gitconfig";
    ".npmrc".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/npmrc";
    #     ".ssh/id_rsa.pub".text = ''
    # ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAuSEf//2a4x+eTqtmhNfQuTJ0vMmGSq5En6FAsxTUYPauzXmH59sG/SRryZpsQq+nGEZLfQ1R2mAq8M71ZJPCCOoYTN3yxdyCpjlodva7+5PpTvE9KQmThlm9Y+RL8dVq413uEwlav2kLa0RBsx10i2vcVMJ1FKno7mQz5/u6G3CXt++YJoPWoNVPIxIIefUot2kj9b2b7wf4EuWPOr5noH41N/E67/1OqfItqaaSGgP9ky9qCKdrI8J1ukhSDsvxmlF/f0kgpl6KVAEpx0/qfVsBoR5BBuNJg8gcWUso0Y92D+7sWULKXZV69Ka4uJ93HqCrKkd1iQpGOO/n6VCRkQ== itcalde@wombatzone.localdomain
    #     '';
  };

  # Optional: Let Podman search Docker Hub by default
  xdg.configFile."containers/registries.conf".text = ''
    [registries.search]
    registries = ['docker.io', 'quay.io']
  '';

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/itcalde/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
    # Silences the "Executing external compose provider" warning
    PODMAN_COMPOSE_WARNING_LOGS = "0";
  };

  home.sessionPath = [
    # Add custom paths to your $PATH here. For example, if you have a
    # directory where you store your own scripts, you can add it like this:
    # "${config.home.homeDirectory}/bin"
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.bash = {
    # All available options are listed here:
    # https://mynixos.com/home-manager/options/programs.bash

    enable = true;

    # This option allows you to set the default shell for your user. It is
    # recommended to use the same shell as the one you are using in your
    # terminal emulator.
    shellAliases = {
      # https://nix.dev/tutorials/nix-language.html
      # https://nixos.org/guides/nix-pills/04-basics-of-language.html
      gsudo = "sudo git -c \"include.path=${config-dir}/git/config\" -c \"include.path=${builtins.getEnv ("HOME")}/.gitconfig\"";
      #   ll = "ls -l";
      #   la = "ls -la";
      #   l = "ls -CF";
    };

    # git clone https://github.com/magicmonty/bash-git-prompt.git ~/.bash-git-prompt --depth=1
    initExtra = ''
      if [ -f "$HOME/.bash-git-prompt/gitprompt.sh" ]; then
          GIT_PROMPT_ONLY_IN_REPO=1
          source "$HOME/.bash-git-prompt/gitprompt.sh"
      fi
    '';
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
      };
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  services.ssh-agent.enable = true;
  services.podman.enable = true;

  home.activation = {

  };
}
