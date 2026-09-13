#!/usr/bin/env bash
# sandbox.sh — run a command inside a bwrap sandbox.
#
# Threat model: prevent *accidental* out-of-scope edits/deletions, not
# malicious activity. pi's config lives in git, so it is bound read-write
# (pi sometimes needs to manage its own extensions/skills).
#
# Writable: /app (the project dir), /tmp (private tmpfs), ~/.pi
# Read-only: nix store, system binaries, pi/npm/cargo installs
# Invisible: everything else on the host (ssh keys, other projects, /root…)
#
# User-independent: host paths are resolved from $HOME at runtime; on WSL
# the Windows username is resolved via cmd.exe (same as browser-start.js).
#
# Usage: sandbox <command> [args...]
#   e.g. sandbox pi -p "hello"
#        sandbox bash -c 'ls /'
set -euo pipefail

# --- configuration (all overridable via environment) -----------------------
# Fixed identity *inside* the sandbox (not the host user).
SANDBOX_HOME="/home/sandbox"
# Host-side paths, resolved at runtime.
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
PI_HOME="${PI_HOME:-$HOME/.pi}"
CACHE_HOME="${CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}}"
# WSL interop (browser-tools skill). WSL-only; skipped elsewhere.
WSL_CMD_EXE="${WSL_CMD_EXE:-/mnt/c/Windows/System32/cmd.exe}"
EDGE_EXE="${EDGE_EXE:-/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe}"
# Extra host paths for a particular task, e.g.
#   EXTRA_BINDS="/data/reports:/app/data:ro /scratch:/tmp/scratch:rw" sandbox pi -p "…"
# Entries: SRC:DEST[:ro|rw] (ro is the default). Expanded before --remount-ro /
# so bwrap can create destination mount points. Paths must not contain spaces.
EXTRA_BINDS="${EXTRA_BINDS:-}"

# Locate bubblewrap: already on PATH, nix profiles, or via nix-shell (cached).
resolve_bwrap() {
  if command -v bwrap >/dev/null 2>&1; then command -v bwrap; return; fi
  local p
  for p in "$HOME/.nix-profile/bin/bwrap" /run/current-system/sw/bin/bwrap; do
    [ -x "$p" ] && { printf '%s' "$p"; return; }
  done
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/bwrap-experiments/bwrap-path"
  if [ -s "$cache" ] && [ -x "$(cat "$cache")" ]; then cat "$cache"; return; fi
  local path
  path="$(nix-shell -p bubblewrap --run 'command -v bwrap')"
  mkdir -p "$(dirname "$cache")" && printf '%s' "$path" > "$cache"
  printf '%s' "$path"
}

# Windows username, same approach as browser-start.js. Only called on WSL.
resolve_win_user() {
  local u
  u=$("$WSL_CMD_EXE" /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n' | head -n 1) || return 0
  [ -n "$u" ] && printf '%s' "$u"
  return 0
}
WIN_USER="${WIN_USER:-}"
if [ -z "$WIN_USER" ] && [ -x "$WSL_CMD_EXE" ]; then
  WIN_USER="$(resolve_win_user)"
fi

BWRAP="${BWRAP:-$(resolve_bwrap)}"

# Base sandbox. No comment lines may appear in the Windows block appended
# below if you convert it back to a single backslash-continued exec — a #
# there terminates the command early (bash gotcha).
bwrap_args=(
  --unshare-all
  --share-net
  --dev /dev
  --proc /proc
  --ro-bind /nix/store /nix/store
  --ro-bind /run/current-system/sw /run/current-system/sw
  --ro-bind /bin /bin
  --ro-bind /lib64 /lib64
  --dir /usr/bin
  --symlink /run/current-system/sw/bin/env /usr/bin/env
  --ro-bind /etc/resolv.conf /etc/resolv.conf
  --ro-bind /etc/passwd /etc/passwd
  --ro-bind /etc/group /etc/group
  --ro-bind /etc/ssl /etc/ssl
  --ro-bind /etc/static/ssl /etc/static/ssl
  --tmpfs /tmp
  --bind "$PROJECT_DIR" /app
  --dir "$SANDBOX_HOME"
  --bind "$PI_HOME" "$SANDBOX_HOME/.pi"
  --ro-bind "$HOME/.npm-global" "$SANDBOX_HOME/.npm-global"
  --ro-bind "$HOME/.cargo" "$SANDBOX_HOME/.cargo"
  --ro-bind "$HOME/.local" "$SANDBOX_HOME/.local"
  --ro-bind "$HOME/.nix-profile" "$SANDBOX_HOME/.nix-profile"
  --tmpfs "$SANDBOX_HOME/.cache"
  --bind-try "$CACHE_HOME/codebase-memory-mcp" "$SANDBOX_HOME/.cache/codebase-memory-mcp"
  --tmpfs "$SANDBOX_HOME/.gemini"
)

# WSL/Windows interop (browser-tools skill: launches Windows Edge).
# PE binaries run via the WSLInterop binfmt handler (interpreter /init) and
# per-process sockets in /run/WSL; only the entry .exe files need binding
# (DLLs resolve on the Windows side). /app must exist on the host (sudo
# mkdir /app, one-time) or the launcher's CWD mapping fails.
# Appended only when a Windows user resolved; on non-WSL machines the
# sandbox works without any Windows-side binds.
# Validate and expand EXTRA_BINDS into --ro-bind/--bind flags. Fails with a
# clear message instead of a cryptic bwrap error.
add_extra_binds() {
  local entry src dst mode
  [ -n "$EXTRA_BINDS" ] || return 0
  for entry in $EXTRA_BINDS; do
    src="${entry%%:*}"; dst="${entry#*:}"
    mode="ro"
    if [[ "$dst" == *:* ]]; then mode="${dst##*:}"; dst="${dst%:*}"; fi
    case "$mode" in
      ro) bwrap_args+=(--ro-bind "$src" "$dst") ;;
      rw) bwrap_args+=(--bind "$src" "$dst") ;;
      *) echo "sandbox: bad mode '$mode' (want ro or rw) in: $entry" >&2; exit 1 ;;
    esac
    [ -e "$src" ] || { echo "sandbox: no such host path: $src" >&2; exit 1; }
  done
}
add_extra_binds

if [ -n "$WIN_USER" ]; then
  bwrap_args+=(
    --ro-bind /init /init
    --ro-bind /run/WSL /run/WSL
    --ro-bind "$WSL_CMD_EXE" "$WSL_CMD_EXE"
    --ro-bind-try "$EDGE_EXE" "$EDGE_EXE"
    --bind-try "/mnt/c/Users/$WIN_USER/AppData/Local/Pi" "/mnt/c/Users/$WIN_USER/AppData/Local/Pi"
    --ro-bind-try "/mnt/c/Users/$WIN_USER/AppData/Local/Microsoft/Edge/User Data" "/mnt/c/Users/$WIN_USER/AppData/Local/Microsoft/Edge/User Data"
  )
fi

# Environment + finalisation. --remount-ro / must come after all mounts
# (bwrap can't create mount points once the root is read-only).
bwrap_args+=(
  --setenv HOME "$SANDBOX_HOME"
  --setenv PATH "$SANDBOX_HOME/.pi/agent/bin:$SANDBOX_HOME/.npm-global/bin:$SANDBOX_HOME/.cargo/bin:$SANDBOX_HOME/.local/bin:$SANDBOX_HOME/.nix-profile/bin:/run/current-system/sw/bin:/bin"
  --unsetenv PI_SESSION_FILE
  --unsetenv PI_SESSION_ID
  --unsetenv PI_CODING_AGENT
  --remount-ro /
  --chdir /app
)

exec "$BWRAP" "${bwrap_args[@]}" "$@"
