#!/usr/bin/env bash
# bump.sh — Bump llama.cpp version in hosts/wsl/configuration.nix
# Usage: bump.sh <new-version>
#   e.g. bump.sh 9294
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CONFIG="$REPO_ROOT/hosts/wsl/configuration.nix"

NEW_VERSION="${1:-}"
if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <new-version>"
  echo "  e.g. $0 9294"
  exit 1
fi

echo "=== llama-bump: bumping to b${NEW_VERSION} ==="

# --- Step 1: Capture old values ---
OLD_VERSION=$(rg -oP 'version\s*=\s*"\K\d+' "$CONFIG" | head -1)
OLD_SRC_HASH=$(rg -A3 'fetchFromGitHub' "$CONFIG" | rg -oP 'hash\s*=\s*"\Ksha256-[A-Za-z0-9+/=]+' | head -1)
OLD_NPM_HASH=$(rg -oP 'npmDepsHash\s*=\s*"\Ksha256-[A-Za-z0-9+/=]+' "$CONFIG" | head -1)

echo "Old: version=${OLD_VERSION} src=${OLD_SRC_HASH} npm=${OLD_NPM_HASH}"

# --- No-op check ---
if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo "Already at b${NEW_VERSION}. Nothing to do."
  exit 0
fi

# --- Step 2: Set version + fake hashes ---
# Replace version
sed -i "s/version = \"${OLD_VERSION}\"/version = \"${NEW_VERSION}\"/" "$CONFIG"

# Replace src hash with lib.fakeHash
sed -i '/fetchFromGitHub/,/};/{s/hash = "sha256-[^"]*"/hash = lib.fakeHash/}' "$CONFIG"

# Replace npmDepsHash with lib.fakeHash
sed -i 's/npmDepsHash = "sha256-[^"]*"/npmDepsHash = lib.fakeHash/' "$CONFIG"

echo "Set version=${NEW_VERSION}, src=lib.fakeHash, npmDepsHash=lib.fakeHash"

# --- Step 3: First build — get src hash ---
echo ""
echo "--- Building (pass 1: src hash) ---"
SRC_OUTPUT=$(nix build "$REPO_ROOT"#nixosConfigurations.nixos.config.system.build.toplevel 2>&1 | head -30 || true)
NEW_SRC_HASH=$(echo "$SRC_OUTPUT" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | head -1)

if [[ -z "$NEW_SRC_HASH" ]]; then
  echo "ERROR: Could not extract src hash from build output."
  echo "$SRC_OUTPUT"
  exit 1
fi

echo "Got src hash: ${NEW_SRC_HASH}"

# --- Step 4: Patch src hash ---
# Replace lib.fakeHash in the src block (first occurrence)
sed -i '0,/hash = lib.fakeHash/{s/hash = lib.fakeHash/hash = "'"$NEW_SRC_HASH"'"/}' "$CONFIG"

echo "Patched src hash."

# --- Step 5: Second build — get npmDepsHash ---
echo ""
echo "--- Building (pass 2: npmDepsHash) ---"
NPM_OUTPUT=$(nix build "$REPO_ROOT"#nixosConfigurations.nixos.config.system.build.toplevel 2>&1 | head -30 || true)
NEW_NPM_HASH=$(echo "$NPM_OUTPUT" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | head -1)

if [[ -z "$NEW_NPM_HASH" ]]; then
  echo "ERROR: Could not extract npmDepsHash from build output."
  echo "$NPM_OUTPUT"
  exit 1
fi

echo "Got npmDepsHash: ${NEW_NPM_HASH}"

# --- Step 6: Patch npmDepsHash ---
sed -i 's/npmDepsHash = lib.fakeHash/npmDepsHash = "'"$NEW_NPM_HASH"'"/' "$CONFIG"

echo "Patched npmDepsHash."

# --- Step 7: Summary ---
echo ""
echo "=== Bump complete: b${OLD_VERSION} → b${NEW_VERSION} ==="
echo "| Field         | Old (b${OLD_VERSION})        | New (b${NEW_VERSION})         |"
echo "|---|---|---|"
echo "| \`version\`     | \"${OLD_VERSION}\"             | \"${NEW_VERSION}\"              |"
echo "| \`src.hash\`    | ${OLD_SRC_HASH} | ${NEW_SRC_HASH} |"
echo "| \`npmDepsHash\` | ${OLD_NPM_HASH} | ${NEW_NPM_HASH} |"
echo ""
echo "Run \`nix build .#nixosConfigurations.nixos.config.system.build.toplevel\` for the full build."
