#!/usr/bin/env bash
# verify-sandbox.sh — prove the sandbox enforces the intended boundaries.
# Each check prints PASS/FAIL. Run: sandbox-verify (or ./verify-sandbox.sh)
set -u
# Resolve the launcher directory before any cd: BASH_SOURCE is relative when the
# script is invoked as ./verify-sandbox.sh, and the scratch dir is not the checkout.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Run the checks from a scratch dir: the suite writes marker files into the project
# bind, and the installed script lives in the read-only Nix store.
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-sandbox-verify.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR" || exit 1

pass=0; fail=0
check() { # check <description> <expected:0|1> <actual-exit>
  local desc="$1" expected="$2" actual="$3"
  if { [ "$expected" = 0 ] && [ "$actual" -eq 0 ]; } || { [ "$expected" = 1 ] && [ "$actual" -ne 0 ]; }; then
    echo "PASS  $desc"; pass=$((pass+1))
  else
    echo "FAIL  $desc (expected exit $expected, got $actual)"; fail=$((fail+1))
  fi
}

# Which launcher to exercise: the sandbox-verify wrapper sets SANDBOX_BIN; running the
# file straight from a checkout picks up the sibling sandbox.sh; otherwise use PATH.
if [ -z "${SANDBOX_BIN:-}" ]; then
  if [ -x "$SELF_DIR/sandbox.sh" ]; then
    SANDBOX_BIN="$SELF_DIR/sandbox.sh"
  elif command -v sandbox >/dev/null 2>&1; then
    SANDBOX_BIN="sandbox"
  else
    echo "verify-sandbox.sh: no sandbox launcher found; set SANDBOX_BIN" >&2
    exit 1
  fi
fi

in_sandbox() { "$SANDBOX_BIN" bash -c "$1" >/dev/null 2>&1; echo $?; }

# Host home of whoever runs this (resolved at runtime, user-independent).
HOST_HOME="$HOME"

echo "== Visibility: host paths must be invisible =="
check "cannot read $HOST_HOME/.ssh"           1 "$(in_sandbox "ls $HOST_HOME/.ssh")"
check "cannot read /etc/shadow"               1 "$(in_sandbox 'cat /etc/shadow')"
check "cannot see /root"                      1 "$(in_sandbox 'ls /root')"
check "host home dir not visible"             1 "$(in_sandbox "ls $HOST_HOME")"
check "cannot read host /tmp"                 1 "$(in_sandbox 'cat /tmp/host-marker 2>/dev/null')"
echo "marker" > /tmp/host-marker
check "host /tmp not visible in sandbox"      1 "$(in_sandbox 'cat /tmp/host-marker')"
rm -f /tmp/host-marker

echo "== Writability: only /app and /tmp =="
check "can write /app"                        0 "$(in_sandbox 'touch /app/.v-test && rm /app/.v-test')"
check "can write /tmp"                        0 "$(in_sandbox 'touch /tmp/.v-test && rm /tmp/.v-test')"
check "cannot write /"                        1 "$(in_sandbox 'touch /x 2>/dev/null')"
check "cannot write /etc"                     1 "$(in_sandbox 'touch /etc/x 2>/dev/null')"
check "cannot write /home/sandbox"            1 "$(in_sandbox 'touch /home/sandbox/x 2>/dev/null')"
check "cannot write /nix/store"               1 "$(in_sandbox 'touch /nix/store/x 2>/dev/null')"
check "cannot write /run/current-system/sw"   1 "$(in_sandbox 'touch /run/current-system/sw/x 2>/dev/null')"
check "/home/sandbox/.pi writable (pi self-manages, config in git)" 0 "$(in_sandbox 'touch /home/sandbox/.pi/.v-selftest && rm /home/sandbox/.pi/.v-selftest')"
check "/home/sandbox/.pi/agent writable (sessions/extensions)"      0 "$(in_sandbox 'touch /home/sandbox/.pi/agent/.v-selftest && rm /home/sandbox/.pi/agent/.v-selftest')"

# gh binds ~/.config/gh read-write (token refresh); skipped on hosts without one.
echo "== gh CLI config (~/.config/gh) =="
if [ -d "$HOST_HOME/.config/gh" ]; then
  check "/home/sandbox/.config/gh visible (gh auth)"              0 "$(in_sandbox 'test -d /home/sandbox/.config/gh')"
  check "/home/sandbox/.config/gh writable (gh token refresh)"   0 "$(in_sandbox 'touch /home/sandbox/.config/gh/.v-selftest && rm /home/sandbox/.config/gh/.v-selftest')"
else
  echo "SKIP  gh config checks (no ~/.config/gh on host)"
fi

echo "== Project dir: real bind mount to host =="
echo "host-side-content" > .v-bindfile
check "sandbox reads host file"               0 "$(in_sandbox 'grep -q host-side-content /app/.v-bindfile')"
( "$SANDBOX_BIN" bash -c 'echo sandbox-wrote-this > /app/.v-bindfile' >/dev/null 2>&1 )
if grep -q sandbox-wrote-this .v-bindfile; then rc=0; else rc=1; fi
check "sandbox write lands on host"           0 "$rc"
rm -f .v-bindfile

echo "== Process isolation =="
check "sandbox sees fresh PID 1"              0 "$(in_sandbox 'test "$(ps -o pid= -p 1 | tr -d " ")" = 1')"
host_pid_count=$(ps -e --no-headers | wc -l)
check "fewer processes visible than host"     0 "$(in_sandbox "test \$(ps -e --no-headers | wc -l) -lt $host_pid_count")"

echo "== User/ownership =="
host_uid=$(id -u)
check "runs as host uid (mapped)"             0 "$(in_sandbox "test \"\$(id -u)\" = $host_uid")"
( "$SANDBOX_BIN" bash -c 'touch /app/.v-owner' >/dev/null 2>&1 )
if [ "$(stat -c %u .v-owner)" = "$host_uid" ]; then rc=0; else rc=1; fi
check "sandbox-created file owned by host uid" 0 "$rc"
rm -f .v-owner

echo "== Nix (needs the host nix daemon) =="
if [ -S "${NIX_DAEMON_SOCKET:-/nix/var/nix/daemon-socket/socket}" ]; then
  # First run on a machine without cowsay in the store fetches ~136 MiB via
  # cache.nixos.org (through the daemon).
  check "nix-shell runs a package via host daemon" 0 "$(in_sandbox 'nix-shell -p cowsay --run "cowsay VERIFY-COW" | grep -q VERIFY-COW')"
else
  echo "SKIP  nix-shell check (no nix daemon socket on host)"
fi

echo "== Network =="
check "DNS resolution works"                  0 "$(in_sandbox 'getent hosts github.com')"
# shellcheck disable=SC2016 -- the command runs inside the namespace; expansion must happen there
check "outbound HTTPS works"                  0 "$(in_sandbox 'curl -fsS --max-time 10 https://github.com >/dev/null')"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
