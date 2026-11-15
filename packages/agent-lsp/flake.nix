{
  description = "agent-lsp: code intelligence infrastructure for AI agents (MCP server)";

  inputs = { };

  outputs =
    { self, nixpkgs, ... }:
    let
      # Pure Go build; cross-compiles cleanly on both host architectures.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # Define the 'agent-lsp' package for each supported system
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          agentLsp = pkgs.callPackage ./agent-lsp.nix { };
        in
        {
          default = agentLsp;
          "agent-lsp" = agentLsp;
        }
      );

      # Used by the root flake to make `pkgs.agent-lsp` available.
      overlays.default = final: prev: {
        agent-lsp = self.packages.${final.stdenv.hostPlatform.system}.agent-lsp;
      };
    };
}
