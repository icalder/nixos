{
  description = "A flake for the graphify Python application";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        pyp = pkgs.python3Packages;

        # tree-sitter-typescript — not in nixpkgs, build from GitHub source
        tree-sitter-typescript = pyp.buildPythonPackage (finalAttrs: {
          pname = "tree-sitter-typescript";
          version = "0.23.2";
          pyproject = true;

          src = pkgs.fetchFromGitHub {
            owner = "tree-sitter";
            repo = "tree-sitter-typescript";
            tag = "v${finalAttrs.version}";
            hash = "sha256-CU55+YoFJb6zWbJnbd38B7iEGkhukSVpBN7sli6GkGY=";
          };

          build-system = [ pyp.setuptools ];

          optional-dependencies = {
            core = [ pyp.tree-sitter ];
          };

          doCheck = false;
          pythonImportsCheck = [ "tree_sitter_typescript" ];

          meta = with pkgs.lib; {
            description = "TypeScript and TSX grammars for tree-sitter";
            homepage = "https://github.com/tree-sitter/tree-sitter-typescript";
            license = licenses.mit;
          };
        });

        # tree-sitter-go — not in nixpkgs, build from GitHub source
        tree-sitter-go = pyp.buildPythonPackage (finalAttrs: {
          pname = "tree-sitter-go";
          version = "0.25.0";
          pyproject = true;

          src = pkgs.fetchFromGitHub {
            owner = "tree-sitter";
            repo = "tree-sitter-go";
            tag = "v${finalAttrs.version}";
            hash = "sha256-y7bTET8ypPczPnMVlCaiZuswcA7vFrDOc2jlbfVk5Sk=";
          };

          build-system = [ pyp.setuptools ];

          optional-dependencies = {
            core = [ pyp.tree-sitter ];
          };

          doCheck = false;
          pythonImportsCheck = [ "tree_sitter_go" ];

          meta = with pkgs.lib; {
            description = "Go grammar for tree-sitter";
            homepage = "https://github.com/tree-sitter/tree-sitter-go";
            license = licenses.mit;
          };
        });

        graphifyPackage = pyp.buildPythonApplication rec {
          pname = "graphifyy";
          version = "0.8.33"; # Update this to the exact version you need

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-9MN3XQB3Jullae0UGdpYt2X/5bqds4iknQ8UdYTuekY=";
          };

          pyproject = true;
          build-system = [ pkgs.python3Packages.setuptools ];

          # Runtime Python library dependencies
          propagatedBuildInputs = with pkgs.python3Packages; [
            networkx
            datasketch
            rapidfuzz
            tree-sitter
            tree-sitter-python
            tree-sitter-javascript
            tree-sitter-rust
            tree-sitter-bash
            tree-sitter-json
            tree-sitter-c-sharp
          ] ++ [ tree-sitter-typescript tree-sitter-go ];

          # Many tree-sitter grammars (go, java, cpp, ruby, etc.) are not in nixpkgs.
          # The package handles missing grammars gracefully at runtime.
          pythonImportsCheck = [
            # Only check core imports; skip tree-sitter grammars not in nixpkgs
          ];

          # Disable tests if PyPI source doesn't bundle the test suite
          doCheck = false;

          # Many tree-sitter grammars (go, java, cpp, ruby, etc.) are not in nixpkgs.
          # The package loads them lazily and handles missing ones gracefully at runtime.
          dontCheckRuntimeDeps = true;

          meta = with pkgs.lib; {
            description = "AI coding assistant skill that turns folders into a queryable knowledge graph";
            homepage = "https://graphify.net/";
            license = licenses.mit;
            mainProgram = "graphify";
          };
        };
      in
      {
        # Expose the package to 'nix build' or other flakes
        packages = {
          graphify = graphifyPackage;
          default = graphifyPackage;
        };

        # Allows you to drop into a temporary shell with graphify available via 'nix shell'
        apps.default = flake-utils.lib.mkApp {
          drv = graphifyPackage;
        };
      }
    ))
    // {
      # 2. System-agnostic outputs (overlays) merged via '//'
      overlays.default = final: prev: {
        graphify = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };
    };
}
