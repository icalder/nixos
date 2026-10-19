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
# The host home dir exists as an empty mount-point shell: the .pi re-exposure
# bind (absolute symlinks in .pi must resolve) makes bwrap create its parent.
# The intent is that no *host content* is reachable, so check that only the
# re-exposed .pi entry is present.
check "host home dir exposes no host content" 0 "$(in_sandbox "test \"\$(ls -A $HOST_HOME 2>/dev/null | grep -cvx .pi)\" -eq 0")"
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

# cargo is bound read-write (registry cache, cargo install); skipped on hosts without one.
echo "== cargo home (~/.cargo) =="
if [ -d "$HOST_HOME/.cargo" ]; then
  check "/home/sandbox/.cargo visible (cargo toolchain)"          0 "$(in_sandbox 'test -d /home/sandbox/.cargo')"
  check "/home/sandbox/.cargo writable (cargo fetch/install)"    0 "$(in_sandbox 'touch /home/sandbox/.cargo/.v-selftest && rm /home/sandbox/.cargo/.v-selftest')"
else
  echo "SKIP  cargo checks (no ~/.cargo on host)"
fi

# Go is bound read-write (module cache, go install, build cache); skipped on
# hosts without a Go setup.
echo "== Go home (~/.go) =="
if [ -d "$HOST_HOME/go" ]; then
  check "/home/sandbox/go visible (Go toolchain)"         0 "$(in_sandbox 'test -d /home/sandbox/go')"
  check "/home/sandbox/go writable (go build/install)"   0 "$(in_sandbox 'touch /home/sandbox/go/.v-selftest && rm /home/sandbox/go/.v-selftest')"
  # .cache is a fresh tmpfs, so a plain write test would pass even without
  # the bind; a host-side marker proves the host cache is the one seen.
  if [ -d "$HOST_HOME/.cache/go-build" ]; then
    echo marker > "$HOST_HOME/.cache/go-build/.v-selftest-host"
    check "/home/sandbox/.cache/go-build shares host build cache" 0 "$(in_sandbox 'test -f /home/sandbox/.cache/go-build/.v-selftest-host')"
    rm -f "$HOST_HOME/.cache/go-build/.v-selftest-host"
  fi
else
  echo "SKIP  go checks (no ~/.go on host)"
fi

# gh binds ~/.config/gh read-write (token refresh); skipped on hosts without one.
echo "== gh CLI config (~/.config/gh) =="
if [ -d "$HOST_HOME/.config/gh" ]; then
  check "/home/sandbox/.config/gh visible (gh auth)"              0 "$(in_sandbox 'test -d /home/sandbox/.config/gh')"
  check "/home/sandbox/.config/gh writable (gh token refresh)"   0 "$(in_sandbox 'touch /home/sandbox/.config/gh/.v-selftest && rm /home/sandbox/.config/gh/.v-selftest')"
else
  echo "SKIP  gh config checks (no ~/.config/gh on host)"
fi

# kubectl config is bound read-only at kubectl's default lookup path;
# skipped on hosts without a kubeconfig.
echo "== kubectl config (~/.kube/config) =="
KUBE_CONFIG="${KUBE_CONFIG:-${KUBECONFIG:-$HOST_HOME/.kube/config}}"
if [ -f "$KUBE_CONFIG" ]; then
  check "/home/sandbox/.kube/config visible (kubectl)" 0 "$(in_sandbox 'test -f /home/sandbox/.kube/config')"
  check "/home/sandbox/.kube/config read-only"         1 "$(in_sandbox 'rm -f /home/sandbox/.kube/config 2>/dev/null')"
  check "kubectl reads the bound config"              0 "$(in_sandbox 'command -v kubectl >/dev/null && kubectl config view >/dev/null')"
else
  echo "SKIP  kubectl config checks (no kubeconfig on host)"
fi

echo "== Container images (podman import/tag/push) =="
# Skipped when the host has no podman: the binary comes from the user's profile,
# the rest (storage/engine config) from the sandbox itself.
# pull/run/build are deliberately *not* tested for success — they cannot work
# without a subordinate uid range; the mapped-uid check below documents why.
HOST_RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if command -v podman >/dev/null 2>&1; then
  check "/sys/fs/cgroup visible (podman statfs at startup)" 0 \
    "$(in_sandbox 'stat -f -c %T /sys/fs/cgroup | grep -q cgroup2')"
  check "XDG_RUNTIME_DIR private and writable (podman needs it)" 0 \
    "$(in_sandbox 'touch "$XDG_RUNTIME_DIR/.v-selftest" && rm "$XDG_RUNTIME_DIR/.v-selftest"')"
  # podman wants a runtime dir, and the host's holds agent sockets (ssh-agent),
  # so the sandbox must get a fresh one rather than a bind of the host's.
  echo marker > "$HOST_RUNTIME/.v-sandbox-probe"
  check "host runtime dir not visible in sandbox" 1 \
    "$(in_sandbox "cat $HOST_RUNTIME/.v-sandbox-probe")"
  rm -f "$HOST_RUNTIME/.v-sandbox-probe"
  # 'vfs' + a graphroot under /tmp is the private per-session store; the host's
  # rootless store (~/.local/share/containers) is unreadable in here and must not
  # be used.
  check "container store is private vfs in /tmp" 0 \
    "$(in_sandbox "test \"\$(podman info --format '{{.Store.GraphDriverName}} {{.Store.GraphRoot}}')\" = 'vfs /tmp/containers/storage'")"
  check "podman cgroup manager disabled (no systemd/cgroupfs writes)" 0 \
    "$(in_sandbox "test \"\$(podman info --format '{{.Host.CgroupManager}}')\" = disabled")"
  # One mapped uid is the reason registry images cannot be extracted (their
  # layers belong to many uids/gids), asserted so a future kernel or namespace
  # change that lifts the limitation shows up as a failure here.
  check "exactly one uid mapped (why pull/run/build cannot work)" 0 \
    "$(in_sandbox 'test "$(wc -l < /proc/self/uid_map)" -eq 1')"

  # Import needs a tarball whose entries are all uid 0/gid 0: that is the only
  # ownership the single mapping can express. Import/tag/save/push then all run
  # in one sandbox session, because the image store lives in the session's /tmp.
  mkdir -p .v-rootfs/etc .v-rootfs/data
  echo selftest > .v-rootfs/etc/app.conf
  echo selftest > .v-rootfs/data/payload
  tar -C .v-rootfs --owner=0 --group=0 --numeric-owner -czf .v-rootfs.tgz .
  check "import -> tag -> save round-trips in one session" 0 "$(in_sandbox '
    podman import /app/.v-rootfs.tgz sbx-verify-src >/dev/null &&
    podman tag sbx-verify-src 127.0.0.1:1/sbx-verify:selftest &&
    podman save --output /tmp/.v-image.tar sbx-verify-src &&
    test -s /tmp/.v-image.tar')"
  # Push is verified by writing the image out to an OCI layout, which runs the
  # same copy/manifest machinery as a registry push with no network. A "push to a
  # dead registry and expect a refusal" test is deliberately not used: on WSL2 a
  # connect to an unbound port is blackholed rather than refused (host-side curl
  # to 127.0.0.1:1 times out too), so it hangs instead of failing fast. Probe a
  # new registry address with `curl -m 5 http://<registry>/v2/` before pushing.
  check "push writes an image out (oci destination)" 0 "$(in_sandbox '
    podman import /app/.v-rootfs.tgz sbx-verify-src >/dev/null &&
    podman tag sbx-verify-src registry.invalid:5000/team/sbx-verify:selftest &&
    podman image exists registry.invalid:5000/team/sbx-verify:selftest &&
    podman push sbx-verify-src oci:/tmp/.v-image.oci &&
    test -s /tmp/.v-image.oci/index.json')"
  rm -rf .v-rootfs .v-rootfs.tgz

  # Registry credentials and registry config come from the host, read-only and
  # read-write respectively; skipped when the host has neither.
  if [ -f "$HOST_HOME/.docker/config.json" ]; then
    check "/home/sandbox/.docker/config.json visible (registry creds)" 0 \
      "$(in_sandbox 'test -f /home/sandbox/.docker/config.json')"
    check "/home/sandbox/.docker/config.json read-only" 1 \
      "$(in_sandbox 'rm -f /home/sandbox/.docker/config.json 2>/dev/null')"
  else
    echo "SKIP  registry credential checks (no ~/.docker/config.json on host)"
  fi
  if [ -d "$HOST_HOME/.config/containers" ]; then
    check "/home/sandbox/.config/containers visible (registries, policy)" 0 \
      "$(in_sandbox 'test -d /home/sandbox/.config/containers')"
    check "/home/sandbox/.config/containers writable (podman login --store)" 0 \
      "$(in_sandbox 'touch /home/sandbox/.config/containers/.v-selftest && rm /home/sandbox/.config/containers/.v-selftest')"
  else
    echo "SKIP  container config checks (no ~/.config/containers on host)"
  fi
else
  echo "SKIP  container image checks (no podman on host)"
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
