#!/usr/bin/env bash
# sandbox.sh — run a command inside a bwrap sandbox.
#
# Threat model: prevent *accidental* out-of-scope edits/deletions, not
# malicious activity. pi's config lives in git, so it is bound read-write
# (pi sometimes needs to manage its own extensions/skills).
#
# Writable: /app (the project dir), /tmp (private tmpfs), ~/.pi, ~/.cargo,
#           ~/.go (module cache, go install, build cache), ~/.config/gh,
#           /nix/var/nix (private tmpfs, nix client state in local mode)
# Read-only: nix store, system binaries, pi/npm/cargo installs, nix.conf
# Nix: routes through the host nix daemon (NIX_REMOTE=daemon, socket bound
#      read-only) when one is running — fetches/builds then land in the host
#      store, exactly like running nix as this user on the host.
# Invisible: everything else on the host (ssh keys, other projects, /root…)
#
# User-independent: host paths are resolved from $HOME at runtime; on WSL the
# Windows profile name is read off /mnt/c/Users (cmd.exe only as a fallback).
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
WIN_USERS_DIR="${WIN_USERS_DIR:-/mnt/c/Users}"
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

# --- Windows profile name (WSL) --------------------------------------------
# Needed *before* bwrap runs: it decides which two Windows dirs to bind, and it
# is exported into the sandbox because the browser-tools launcher inside cannot
# look it up (only the profile bound here is visible under /mnt/c/Users).

# A directory the Windows side can resolve. Interop maps a Windows process's
# cwd to \\wsl.localhost\<distro>\<linux cwd> and refuses the exec ("Invalid
# argument") when that path is not visible from the host, so every Windows exec
# here runs from one of these. Only these exact paths count: a directory
# created inside a private mount namespace stays invisible host-side, even
# under /tmp, and a bind mount only resolves to the path its source has there.
# Only the path *string* is checked, and only at exec time — the child then
# falls back to C:\Windows, because Windows rejects UNC working directories —
# so the sandbox's /tmp being a private tmpfs, not the host's, is harmless.
interop_cwd() {
  local d
  for d in /tmp /var/tmp /; do
    [ -d "$d" ] && { printf '%s' "$d"; return; }
  done
  printf '/'
}

# How strongly $1 looks like the interactive user's Windows profile; prints
# nothing for the profiles Windows creates for itself. Mirrors profileScore()
# in the browser-tools launcher — keep the two in step.
win_profile_score() {
  local name="$1" dir score=0
  case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
    default* | public* | wdagutilityaccount* | wsiaccount* | "all users"*) return 1 ;;
  esac
  dir="$WIN_USERS_DIR/$name"
  [ -d "$dir/AppData/Local" ] && score=$((score + 2))
  [ -d "$dir/AppData/Local/Microsoft/Edge/User Data" ] && score=$((score + 4))
  [ "$score" -gt 0 ] || return 1
  printf '%s' "$score"
}

# The interactive user's Windows profile, read off the filesystem: no interop
# call, so no cwd dependency and no Windows round-trip. Highest score wins,
# ties go to the most recently touched profile.
win_user_from_profiles() {
  local entry name score
  [ -d "$WIN_USERS_DIR" ] || return 0
  for entry in "$WIN_USERS_DIR"/*; do
    [ -d "$entry" ] && [ ! -L "$entry" ] || continue
    name="${entry##*/}"
    score="$(win_profile_score "$name")" || continue
    printf '%s %s %s\n' "$score" "$(stat -c %Y "$entry" 2>/dev/null || echo 0)" "$name"
  done | sort -k1,1nr -k2,2nr | sed -n '1p' | cut -d' ' -f3-
}

# Fallback: ask Windows directly. Runs from interop_cwd, never the caller's cwd.
win_user_from_cmd() {
  local u
  [ -x "$WSL_CMD_EXE" ] || return 0
  u=$(cd "$(interop_cwd)" && "$WSL_CMD_EXE" /c 'echo %USERNAME%' 2>/dev/null | head -n 1 | tr -d '\r\n') || return 0
  printf '%s' "$u"
}

WIN_USER="${WIN_USER:-}"
if [ -z "$WIN_USER" ]; then
  WIN_USER="$(win_user_from_profiles)"
  [ -n "$WIN_USER" ] || WIN_USER="$(win_user_from_cmd)"
fi
if [ -z "$WIN_USER" ] && [ -d /mnt/c ]; then
  echo "sandbox: no Windows user resolved — the browser-tools skill cannot start Edge. Set WIN_USER=<profile name>." >&2
fi

BWRAP="${BWRAP:-$(resolve_bwrap)}"

# Base sandbox, kept as an array rather than a backslash-continued command
# line: comments are then safe inside it, and the Windows block below can be
# appended conditionally.
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
  # nix client config: enables the 'flakes' experimental feature (needed for
  # the default NIX_PATH entry nixpkgs=flake:nixpkgs) and carries the
  # substituters/trusted-keys.
  --ro-bind /etc/nix/nix.conf /etc/nix/nix.conf
  --tmpfs /tmp
  # Private, per-session nix state tree. In daemon mode the client barely
  # touches it; in local mode (no daemon on the host) it lets nix-shell/
  # nix-env create their profile (/nix/var/nix/profiles/per-user/<user>/
  # profile) and GC temp roots (/nix/var/nix/temproots) instead of hitting
  # the read-only root.
  --tmpfs /nix/var/nix
  --bind "$PROJECT_DIR" /app
  --dir "$SANDBOX_HOME"
  --bind "$PI_HOME" "$SANDBOX_HOME/.pi"
  # Re-expose the same dir at the host's absolute path so absolute symlinks
  # inside .pi (e.g. agent/skills/browser-tools -> ~/.pi/pi-skills/browser-tools)
  # resolve in the sandbox. No new exposure: identical content, already rw.
  --bind "$PI_HOME" "$HOME/.pi"
  --ro-bind "$HOME/.npm-global" "$SANDBOX_HOME/.npm-global"
  # cargo writes under ~/.cargo (registry cache/src, cargo install output) —
  # cargo fetch/build needs it; same accident-not-malice model as ~/.pi.
  --bind "$HOME/.cargo" "$SANDBOX_HOME/.cargo"
  # Go writes under ~/go (module cache under pkg/mod, go install output
  # under bin) — go build/test need it so agents don't have to point GOPATH
  # / GOMODCACHE at /tmp. -try keeps the sandbox working on hosts without a
  # Go setup; same accident-not-malice model as ~/.cargo.
  --bind-try "$HOME/go" "$SANDBOX_HOME/go"
  --ro-bind "$HOME/.local" "$SANDBOX_HOME/.local"
  --ro-bind "$HOME/.nix-profile" "$SANDBOX_HOME/.nix-profile"
  --ro-bind "$HOME/.gitconfig" "$SANDBOX_HOME/.gitconfig"
  --tmpfs "$SANDBOX_HOME/.cache"
  --bind-try "$CACHE_HOME/codebase-memory-mcp" "$SANDBOX_HOME/.cache/codebase-memory-mcp"
  # Go build cache (default GOCACHE): without this every sandbox session
  # would recompile from scratch, since .cache is a fresh tmpfs.
  --bind-try "$CACHE_HOME/go-build" "$SANDBOX_HOME/.cache/go-build"
  --tmpfs "$SANDBOX_HOME/.gemini"
  # gh CLI credentials: gh keeps tokens in ~/.config/gh/hosts.yml and rewrites
  # that file on token refresh, so it is read-write (like ~/.pi). Only the gh
  # dir is exposed, not the whole ~/.config. -try keeps the sandbox working on
  # hosts without a gh login.
  --bind-try "$HOME/.config/gh" "$SANDBOX_HOME/.config/gh"
)

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

# WSL/Windows interop (browser-tools skill: launches Windows Edge).
# PE binaries run via the WSLInterop binfmt handler (interpreter /init) and
# per-process sockets in /run/WSL; only the entry .exe files need binding (DLLs
# resolve on the Windows side). A Windows process cannot inherit the sandbox's
# cwd — interop only resolves paths visible from the host — so the launcher
# pins its own (see interop_cwd) and no longer needs /app to exist host-side.
# Appended only when a Windows user resolved; on non-WSL machines the sandbox
# works without any Windows-side binds.
if [ -n "$WIN_USER" ]; then
  WIN_PI_DIR="$WIN_USERS_DIR/$WIN_USER/AppData/Local/Pi"
  WIN_EDGE_DIR="$WIN_USERS_DIR/$WIN_USER/AppData/Local/Microsoft/Edge/User Data"
  # The skill creates this dir too, but only a host-side mkdir makes it bindable:
  # bwrap cannot bind a path that does not exist, and inside the sandbox the root
  # is read-only, so the skill's own mkdir would fail. Guarded on the parent so a
  # wrong WIN_USER cannot invent directory trees on the drive.
  if [ ! -e "$WIN_PI_DIR" ] && [ -d "$(dirname "$WIN_PI_DIR")" ]; then
    mkdir -p "$WIN_PI_DIR" 2>/dev/null || true
  fi
  bwrap_args+=(
    --ro-bind /init /init
    --ro-bind /run/WSL /run/WSL
    --ro-bind "$WSL_CMD_EXE" "$WSL_CMD_EXE"
    --ro-bind-try "$EDGE_EXE" "$EDGE_EXE"
    --bind-try "$WIN_PI_DIR" "$WIN_PI_DIR"
    --ro-bind-try "$WIN_EDGE_DIR" "$WIN_EDGE_DIR"
    # Hand the launcher the answers it cannot find inside: the profile name and
    # the exact paths that were bound (it must not guess at others).
    --setenv WIN_USER "$WIN_USER"
    --setenv WIN_USERS_DIR "$WIN_USERS_DIR"
    --setenv WSL_CMD_EXE "$WSL_CMD_EXE"
    --setenv EDGE_EXE "$EDGE_EXE"
  )
fi

# Nix via the host daemon. The client-side store access is read-only, so
# client-side operations fail: the flake-registry fetch locks a file next to
# the store path, and store writes (fetch/build) are impossible. With the
# daemon socket bound and NIX_REMOTE=daemon, the host daemon (running as
# root) does the fetches, builds, locks and profile work — full nix-shell /
# nix develop / nix build support. Skipped when the host has no daemon
# socket (then only packages already in the store work, via the /nix/var/nix
# tmpfs above). Override with NIX_REMOTE=… (e.g. NIX_REMOTE=local).
NIX_DAEMON_SOCKET="${NIX_DAEMON_SOCKET:-/nix/var/nix/daemon-socket/socket}"
if [ -S "$NIX_DAEMON_SOCKET" ]; then
  bwrap_args+=(
    --ro-bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
    --setenv NIX_REMOTE "${NIX_REMOTE:-daemon}"
  )
fi

# Environment + finalisation. --remount-ro / must come after all mounts
# (bwrap can't create mount points once the root is read-only).
bwrap_args+=(
  --setenv HOME "$SANDBOX_HOME"
  --setenv PATH "$SANDBOX_HOME/.pi/agent/bin:$SANDBOX_HOME/.npm-global/bin:$SANDBOX_HOME/.cargo/bin:$SANDBOX_HOME/go/bin:$SANDBOX_HOME/.local/bin:$SANDBOX_HOME/.nix-profile/bin:/run/current-system/sw/bin:/bin"
  --unsetenv PI_SESSION_FILE
  --unsetenv PI_SESSION_ID
  --unsetenv PI_CODING_AGENT
  # The sandbox is the safety net: tell pi's per-command and per-write guard
  # extensions (command-guardian, file-write-approval) to stand down.
  --setenv PI_SANDBOX 1
  --remount-ro /
  --chdir /app
)

exec "$BWRAP" "${bwrap_args[@]}" "$@"
