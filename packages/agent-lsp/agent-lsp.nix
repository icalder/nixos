{ lib
, buildGoModule
, fetchFromGitHub
}:

# Nix equivalent of `go install github.com/blackwell-systems/agent-lsp/cmd/agent-lsp@latest`.
# Pinned to the latest release tag (Nix has no @latest; bump version to upgrade).
#
# go.mod requires go >= 1.26.1; nixpkgs 26.05 provides 1.26.x as `go`.
# All dependencies are pure Go (modernc.org/sqlite), so no CGO/CC is needed.
buildGoModule rec {
  pname = "agent-lsp";
  version = "0.24.2";

  src = fetchFromGitHub {
    owner = "blackwell-systems";
    repo = "agent-lsp";
    tag = "v${version}";
    hash = "sha256-WSl3/xlN3Re8eN3sy9Zm49ljI0vrmm0YWTEY/wI7ZKY=";
  };

  # The main package is not at the repository root; build only it (the
  # internal/ and pkg/ packages are libraries, not binaries).
  subPackages = [ "cmd/agent-lsp" ];

  # No vendor/ in the source tree; the builder runs `go mod vendor` itself
  # and pins the result with this hash (26.05 buildGoModule requires it).
  vendorHash = "sha256-aBokNk3GGCkMX5UYotiQHzWRKfHF6Tc0EA4hIj5XIKg=";

  # Upstream tests (GOWORK=off go test ./internal/... ./cmd/...) are heavy and
  # exercise real language servers; upstream CI runs them on every push.
  doCheck = false;

  meta = with lib; {
    description = "MCP server orchestrating language servers into agent-native code intelligence workflows";
    longDescription = ''
      agent-lsp is not an LSP server itself. It is an orchestration layer that
      manages existing language servers (gopls, rust-analyzer, pyright, ...)
      and exposes batch operations, speculative editing, and multi-step
      workflows to AI agents via the Model Context Protocol.
    '';
    homepage = "https://github.com/blackwell-systems/agent-lsp";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "agent-lsp";
  };
}
