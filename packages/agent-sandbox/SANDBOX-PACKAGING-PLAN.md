# Packaging plan: `agent-sandbox` (provides `sandbox`)

Task: turn `packages/agent-sandbox/` into a flake-based Nix package that installs a
`sandbox` command, expose it through the repo flake, and install it on the WSL host
(`hosts/wsl/configuration.nix`). Bubblewrap must come in as a runtime dependency of the
package so it lands in the system closure too.

This document is the full specification for the change. Follow the steps in order.

---

## 1. Acceptance criteria

| # | Criterion | Check |
|---|---|---|
| A1 | `nix build .#packages.x86_64-linux.agent-sandbox` succeeds (root flake) | step 6.3 |
| A2 | The package installs `bin/sandbox` and `bin/sandbox-verify` | step 6.3 |
| A3 | `bubblewrap` is a runtime dependency of the package (in its closure) | step 6.4 |
| A4 | `sandbox bash -c 'echo ok'` works after a system rebuild | step 6.5 |
| A5 | `sandbox-verify` reports 0 failed checks | step 6.6 |
| A6 | `./sandbox.sh` in the repo checkout still works without the package installed | step 6.1 |
| A7 | `bwrap` is on the system `PATH` (not only inside the wrapper) | step 6.5 |

---

## 2. Baseline (measured on this host, 2026-09-13)

- Scripts present: `sandbox.sh`, `verify-sandbox.sh`, `README.md`. No Nix files.
- `bwrap` is **not** on `PATH` (`which bwrap` → nothing). The repo relies on the
  `resolve_bwrap()` fallback, cached at `~/.cache/bwrap-experiments/bwrap-path` →
  `/nix/store/kxcgm56aqlvgffr88i2d76zhiklxj3r7-bubblewrap-0.11.2/bin/bwrap`.
  Earlier commit `0f8a72c` removed the setuid `security.wrappers.bwrap`, so nothing puts
  `bwrap` on `PATH` today. Installing it explicitly is required (A7).
- Nixpkgs in use: `26.05pre` (`nixpkgs` input `nixos-26.05`). `pkgs.bubblewrap` = 0.11.2.
  `pkgs ? sandbox` = **false** → no attribute collision in nixpkgs.
- No `sandbox`/`bwrap` binary in `/run/current-system/sw/bin` or `~/.nix-profile/bin` →
  no command collision.
- Unprivileged user namespaces work: `unshare -Ur true` succeeds,
  `user.max_user_namespaces = 160387`. There is no `kernel.unprivileged_userns_clone`
  sysctl (mainline kernel). No NixOS kernel/module option needs to change.
- `/app` exists on the host (`drwxr-xr-x root root`), created ad hoc per README issue 12.
  Step 6 makes it declarative.
- `sandbox.sh` passes `shellcheck` clean. `verify-sandbox.sh` has four findings
  (SC2164 once, SC2088 twice, SC2016 once) — step 2 clears SC2164 and SC2088;
  SC2016 is intentional.
- Repo pattern for local packages: sub-flake under `packages/<name>/` with
  `inputs = { }` (no declared inputs, not buildable standalone, no nested
  `flake.lock`), wired in the root as a `path:` input with
  `inputs.nixpkgs.follows = "nixpkgs"` plus `overlays.default` (`fr24feed`,
  `adsbexchange`). Follow it.

---

## 3. Design decisions

**D1 — Package attribute `agent-sandbox`, commands `sandbox` and `sandbox-verify`.**
The script name the user asked for is `sandbox`. `pkgs.sandbox` is free in nixpkgs today,
but it is too generic to claim in an overlay that is applied to every package set in this
flake (`mkPkgs` applies all overlays; a bare `sandbox` name invites a future collision with
nixpkgs or another overlay). Name the package `agent-sandbox`, name the binaries
`sandbox` / `sandbox-verify`, and set `meta.mainProgram = "sandbox"` so `nix run` picks the
right entry point.

**D2 — `stdenv.mkDerivation` + `wrapProgram`, not `writeShellApplication`.**
`writeShellApplication` takes one `name`/`text` pair, so two commands would need two
derivations plus a `symlinkJoin` to expose them as one package; it also injects its own
`export PATH=` line and a shellcheck gate. One `mkDerivation` that installs both scripts
and wraps them in place is smaller, standard, and keeps both commands in one package
output.

**D3 — The scripts stay the single source of truth for sandbox policy.**
The derivation only installs files and injects dependencies (Single Responsibility). No
`sed`-based templating of the store paths into the script: the wrapper sets `BWRAP` and
prepends a PATH, and the script already honours `BWRAP="${BWRAP:-$(resolve_bwrap)}"`.
Runtime host paths (`$HOME`, `$PWD`, `/init`, `/run/WSL`) are resolved by the script at
run time, so the package stays user-independent and cache-free.

**D4 — Two dependency layers, keep them separate.**
- *Build/wrapper deps* (what Nix must pin): `bubblewrap` (pinned absolute path via
  `--set BWRAP`), `coreutils`, `procps`, `curl` (PATH prefix for the two commands).
- *Runtime environment assumptions* (not package deps, documented only): the sandbox
  binds host paths that only exist on a running NixOS/WSL system — `/nix/store`,
  `/run/current-system/sw`, `/bin`, `/lib64`, `/etc/static/ssl`, and on WSL `/init`,
  `/run/WSL`, `/mnt/c/...`. These cannot be Nix dependencies; they are the sandbox's
  contract with the host. A `buildInputs` entry for them would be a lie.

**D5 — Platforms: `x86_64-linux` only, for now.**
`sandbox.sh` binds `/lib64` (x86_64 dynamic linker path; aarch64 uses `/lib`). Declare
`meta.platforms = [ "x86_64-linux" ]` and `supportedSystems = [ "x86_64-linux" ]` so an
aarch64 evaluation fails with a clear "unsupported platform" instead of a cryptic bwrap
error. Follow-up F1 covers aarch64.

**D6 — Sub-flake declares no inputs; the root provides nixpkgs via `follows`.**
`inputs = { }`, exactly like `fr24feed` and `adsbexchange` (the root's
`inputs.nixpkgs.follows = "nixpkgs"` on the input still applies — that is how those two
work). The sub-flake is only ever consumed through the root, so it is not buildable
standalone: there is no nested `flake.lock` to create or keep in sync, and every build —
system and verification alike — runs against the root's single locked nixpkgs. The
price: `nix build path:./packages/agent-sandbox#default` does not work, so the
verification build goes through a new root output `packages.x86_64-linux.agent-sandbox`
(step 5.4). Root flake commands resolve the **committed** tree (git+file), so the commit
lands before the first Nix verification (6.2); the `path:` prefix is still used once,
for the pre-commit lock update.

---

## 4. Target layout

```
packages/agent-sandbox/
├── flake.nix                  NEW  sub-flake (inputs = { }): packages.default + overlays.default
├── default.nix                NEW  the derivation (install + wrap)
├── sandbox.sh                 EDIT usage text only; behaviour unchanged
├── verify-sandbox.sh          EDIT run under any cwd, find `sandbox` on PATH
├── README.md                  EDIT add "Install" section
└── SANDBOX-PACKAGING-PLAN.md  THIS FILE
```

Root `flake.nix`: one new input, one new overlay, one new `packages` entry.
`hosts/wsl/configuration.nix`: two packages in `environment.systemPackages`, one
tmpfiles rule. `flake.lock`: one new node (updated pre-commit, 6.2).

---

## 5. Implementation steps

### Step 1 — `sandbox.sh`

Behaviour is already package-ready (`BWRAP` override, `$HOME`/`$PWD` resolution, WSL
detection). Change documentation strings only, so the installed command documents itself
correctly:

1. Header comment: `Usage: ./sandbox.sh <command> [args...]` →
   `Usage: sandbox <command> [args...]` (and the two `e.g.` lines).
2. Header comment: `EXTRA_BINDS="…" ./sandbox.sh pi -p "…"` → `EXTRA_BINDS="…" sandbox pi -p "…"`.
3. Error message prefixes: `echo "sandbox.sh: bad mode …"` → `echo "sandbox: bad mode …"`,
   and `echo "sandbox.sh: no such host path: …"` → `echo "sandbox: no such host path: …"`.
   An installed command should name itself.
4. Keep `resolve_bwrap()` untouched. It is the fallback that satisfies A6 (repo checkout
   without the package). With the package installed, `BWRAP` is set by the wrapper and
   `resolve_bwrap()` is never called — the `nix-shell -p` branch cannot fire.

No functional edits. The sandbox policy is unchanged and stays reviewed as-is.

### Step 2 — `verify-sandbox.sh`

Two packaging blockers, plus one lint cleanup. All three keep the script working from a
checkout as well as from the Nix store.

2.1 Replace the `cd` into the script's own directory (that becomes the read-only Nix
store) with a scratch directory. The suite only needs a writable directory to act as the
project bind. Capture the script's own directory **before** the `cd`, so 2.2 can still
find it:

```bash
# Before
set -u
cd "$(dirname "$0")"
```

```bash
# After
set -u
# Resolve the launcher directory before any cd: BASH_SOURCE is relative when the
# script is invoked as ./verify-sandbox.sh, and the scratch dir is not the checkout.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Run the checks from a scratch dir: the suite writes marker files into the project
# bind, and the installed script lives in the read-only Nix store.
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-sandbox-verify.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR" || exit 1
```

This also clears SC2164. Ordering matters: `SELF_DIR` first. Resolving it after the `cd`
looks up `./sandbox.sh` relative to the scratch dir and the suite aborts with "no sandbox
launcher found" — that is the failure this ordering prevents.

2.2 Resolve the launcher instead of hard-coding `./sandbox.sh`. Precedence: `SANDBOX_BIN`
(set by the `sandbox-verify` wrapper) → `sandbox.sh` beside this file (checkout) →
`sandbox` on `PATH`. There are **three** call sites to convert — `in_sandbox` plus two
direct calls in the "write lands on host" and "owned by host uid" checks:

```bash
# Before
in_sandbox() { ./sandbox.sh bash -c "$1" >/dev/null 2>&1; echo $?; }
```

```bash
# After
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
```

```bash
# Before (two direct calls, in the project-bind and ownership checks)
( ./sandbox.sh bash -c 'echo sandbox-wrote-this > /app/.v-bindfile' >/dev/null 2>&1 )
( ./sandbox.sh bash -c 'touch /app/.v-owner' >/dev/null 2>&1 )
```

```bash
# After
( "$SANDBOX_BIN" bash -c 'echo sandbox-wrote-this > /app/.v-bindfile' >/dev/null 2>&1 )
( "$SANDBOX_BIN" bash -c 'touch /app/.v-owner' >/dev/null 2>&1 )
```

Check with `grep -n '\./sandbox\.sh' verify-sandbox.sh`: only the header comment may
remain. Run through the wrapper, `BASH_SOURCE` resolves to
`$out/bin/.sandbox-verify-wrapped` and no `sandbox.sh` sits beside it, so the lookup would
fall through to `sandbox` on `PATH` anyway — but the wrapper always sets `SANDBOX_BIN`.

Also update the header comment `Run: ./verify-sandbox.sh` →
`Run: sandbox-verify (or ./verify-sandbox.sh)`.

The one other `./sandbox.sh` occurrence (the direct call in the "sandbox write lands on
host" check) becomes `"$SANDBOX_BIN"`.

2.3 Clear SC2088 by spelling the sandbox paths out in the two check descriptions that
contain a quoted `~`. They already test `/home/sandbox/.pi`, so the new text is more
accurate:

```
check "/home/sandbox/.pi writable (pi self-manages, config in git)" ...
check "/home/sandbox/.pi/agent writable (sessions/extensions)"      ...
```

The single SC2016 finding (single-quoted `$(...)` inside the HTTPS sandbox command)
is intentional — mark it so `shellcheck` stays fully quiet:

```
# shellcheck disable=SC2016 -- the command runs inside the namespace; expansion must happen there
check "outbound HTTPS works"                  0 "$(in_sandbox 'curl -fsS --max-time 10 https://github.com >/dev/null')"
```

### Step 3 — `packages/agent-sandbox/default.nix` (new)

```nix
{
  lib,
  stdenv,
  makeWrapper,
  bubblewrap,
  coreutils,
  procps,
  curl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agent-sandbox";
  version = "0.1.0";

  # Only the two scripts are install inputs. Keep build artefacts (result,
  # flake.lock) out of the source: with `src = ./.` their appearance changes
  # the output hash and drags every rebuild out of the cache.
  src = lib.sourceByRegex ./. [ "sandbox\.sh" "verify-sandbox\.sh" ];

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 sandbox.sh $out/bin/sandbox
    install -Dm755 verify-sandbox.sh $out/bin/sandbox-verify

    # Rewrite '#!/usr/bin/env bash' to the store bash, and make bash a
    # runtime dependency. Without this the wrapped script cannot be exec'd:
    # /usr/bin/env does not exist on the NixOS host root.
    patchShebangs --host $out/bin

    runHook postInstall
  '';

  # bubblewrap is pinned to a store path, so the script never has to look it up.
  # coreutils/procps/curl/gnugrep are what the boundary checks in sandbox-verify run
  # on the host side (the grep package is named gnugrep, separate from coreutils).
  postFixup = ''
    wrapProgram $out/bin/sandbox \
      --set BWRAP ${lib.getExe bubblewrap} \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap coreutils ]}

    wrapProgram $out/bin/sandbox-verify \
      --set SANDBOX_BIN $out/bin/sandbox \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap coreutils procps curl gnugrep ]}
  '';

  meta = with lib; {
    description = "Bubblewrap sandbox for coding agents: workspace-writable, rest-invisible";
    longDescription = ''
      Runs a command (pi, gemini, bash, …) in a bubblewrap namespace where the
      project directory, /tmp and ~/.pi are writable, the Nix store and system
      profiles are read-only, and everything else on the host is invisible.
      Threat model: accidental out-of-scope edits, not a malicious agent.
      sandbox-verify runs the boundary checks.
    '';
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sandbox";
  };
})
```

Notes:

- `$out/bin/sandbox` inside `postFixup` is substituted by the *builder*, not by Nix — no
  fixed-point cycle. Do not replace it with `lib.getExe finalAttrs.finalPackage`; that is
  a real recursion here.
- `--set BWRAP` plus `--prefix PATH` both point at bubblewrap on purpose: `--set` covers
  the script's own `$BWRAP`, the PATH prefix covers any child process that calls `bwrap`.
- `maintainers` is left out: `maintainers.icalder` is not in nixpkgs, and an unknown
  entry there is an eval error. Add it only after adding yourself to the list.
- `lib.sourceByRegex` keeps the output hash independent of `flake.lock`, `result` and the
  docs. Measured: plain `src = ./.` produced two different store paths for identical
  scripts, because `nix build` wrote `flake.lock` and `result` into the directory between
  builds. The filtered source is stable across rebuilds.
- Final output references (measured): `bash`, `bubblewrap`, `coreutils`, `curl`, `gnugrep`, `procps`,
  and the package itself (`SANDBOX_BIN` points at `$out/bin/sandbox`, expected).

### Step 4 — `packages/agent-sandbox/flake.nix` (new)

```nix
{
  description = "Bubblewrap sandbox for coding agents (sandbox, sandbox-verify)";

  # No inputs: this sub-flake is only ever consumed through the root flake,
  # which provides nixpkgs via `inputs.nixpkgs.follows` (same as fr24feed and
  # adsbexchange). It is not buildable standalone, so no flake.lock is created.
  inputs = { };

  outputs =
    { self, nixpkgs, ... }:
    let
      # The script binds /lib64 (x86_64 dynamic linker); see SANDBOX-PACKAGING-PLAN.md F1
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        {
          default = nixpkgs.legacyPackages.${system}.callPackage ./default.nix { };
        }
      );

      overlays.default =
        final: prev:
        {
          agent-sandbox = self.packages.${final.stdenv.hostPlatform.system}.default;
        };
    };
}
```

Keep this flake dependency-free — the package is two shell scripts and `makeWrapper`.
`inputs = { }` is load-bearing (D6): declaring a `nixpkgs` input would make the
sub-flake buildable standalone and create a nested `flake.lock` that would have to
be kept in sync with the root's lock.

### Step 5 — root `flake.nix`

Four edits.

5.1 Declare the input (insert after the `adsbexchange` block, next to the other local
packages):

```nix
    agent-sandbox = {
      url = "path:packages/agent-sandbox";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

5.2 Add `agent-sandbox` to the `outputs = { self, nixpkgs, ... }@inputs:` argument list,
in the same position as the input.

5.3 Apply the overlay in `mkPkgs`, so `pkgs.agent-sandbox` resolves everywhere this flake
builds a package set (the WSL system, the Hyper-V images, the Pi systems, home-manager):

```nix
      mkPkgs =
        system: config:
        import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.agenix
            ...
            adsbexchange.overlays.default
            agent-sandbox.overlays.default
            antigravity-nix.overlays.default
          ];
          inherit config;
        };
```

5.4 Expose the package in the root's `packages` output — this is what the verification
build (6.3) and `nix run .#agent-sandbox` (works because of `meta.mainProgram`) address:

```nix
      packages.${system} = {
        agent-sandbox = pkgs.agent-sandbox; # local, see packages/agent-sandbox
        hyperv-image = self.nixosConfigurations.hyperv-vm.config.system.build.image;
        ...
```

The root `flake.lock` gains a new node. It is updated from the working tree by
`nix flake metadata path:.` in 6.2 *before* the commit, so files and lock land in one
commit; afterwards, root flake commands (committed tree) do not rewrite it — verified:
a clean-tree `nix build` performed no lock update.

`follows` means `agent-sandbox` builds against the flake's own `nixpkgs` (26.05). With
`path:` inputs, Nix copies the directory on each evaluation (the lock node records only
`path`/`type`, no revision), so local edits take effect without `nix flake update`.

### Step 6 — `hosts/wsl/configuration.nix`

6.1 Install both packages. `bubblewrap` is a dependency of `agent-sandbox`, but it is
listed on its own so that `bwrap` is on the *system* PATH as well (A7) — the wrapper only
exposes it inside `sandbox`. This restores a plain `bwrap` for other callers (the esp-rs
devshell case from commit `0f8a72c`) without a setuid wrapper.

```nix
  environment.systemPackages =
    (with pkgs; [
      xdg-utils
      vim
      wget
      nixfmt
      usbutils
      kmod # for modprobe, required by WSL usbipd
      docker-compose # This is V2 (the Go version) - podman needs it in PATH
      hello-script
      goodbye-script
      bubblewrap # sandbox's runtime; also on PATH for other devshells
      agent-sandbox # provides `sandbox` and `sandbox-verify`
    ])
    ++ [ llama-cpp-cuda ];
```

6.2 Make the `/app` host anchor declarative (README issue 12: WSL interop maps the Linux
CWD to `\\wsl.localhost\NixOS\app` and fails with EINVAL when the path is missing on the
Windows side). It exists on this machine already; the rule keeps it after a rebuild on a
fresh host:

```nix
  systemd.tmpfiles.rules = [
    "d /var/lib/llama-models 0775 root llama -"
    # Anchor for the sandbox project bind: WSL interop maps the CWD to
    # \\wsl.localhost\NixOS\app, so /app must exist on the host.
    "d /app 0755 root root -"
  ];
```

6.3 Nothing else on the host needs to change. Unprivileged user namespaces already work
(section 2), and no setuid wrapper is wanted (commit `0f8a72c`).

### Step 7 — `packages/agent-sandbox/README.md`

Add an `Install` section after `Quick start`, and adjust the `Requirements` paragraph:

- Installed (NixOS, this flake): `sandbox` and `sandbox-verify` are on `PATH`; bubblewrap
  comes in as a dependency. `./sandbox.sh` remains for running straight from a checkout.
- One-off without installing: `nix run .#agent-sandbox -- bash -c '…'` (the root flake's
  `packages` entry; `meta.mainProgram` selects `sandbox`).
- Keep the manual `bwrap` note for non-NixOS users.
- The env-override bullets under `Tuning` already document `PROJECT_DIR`, `PI_HOME`,
  `EXTRA_BINDS`, `WIN_USER`; add `BWRAP` (set by the wrapper, override to test another
  build) and `SANDBOX_BIN` (set by the `sandbox-verify` wrapper) in the same style.

Do not restructure the README; it is accurate.

(The commit is step 6.2 in the verification order — it must precede the first
root-flake build, which resolves the committed tree.)

---

## 6. Verification

Run in order. Each step states what "pass" looks like.

> Two rehearsal rounds preceded this plan (both on this host, against nixos-26.05, with
> `packages/agent-sandbox/` left untouched until the change is applied):
>
> 1. A throwaway copy of the directory in `/tmp` (discarded) rehearsed the derivation
>    and the script patches, with a standalone sub-flake.
> 2. After D6 was finalised as `inputs = { }` (no standalone build), the root wiring was
>    re-rehearsed end to end in a scratch git worktree of this repo (branch deleted
>    afterwards).
>
> Every code block in sections 5 and 6 was extracted verbatim from this document and run
> in one of the two rounds. Results (round 2 unless noted):
>
> | Rehearsal | Result |
> |---|---|
> | `nix build .#packages.x86_64-linux.agent-sandbox` | builds; `bin/sandbox` + `bin/sandbox-verify` (both rounds) |
> | patchShebangs in `installPhase` | both `#!/usr/bin/env bash` lines rewritten to store bash (round 1) |
> | `nix path-info -r result \| grep -c bubblewrap` | `1`; wrapper pins `...bubblewrap-0.11.2/bin/bwrap` |
> | `./result/bin/sandbox bash -c …` | runs, uid `1001`, cwd `/app` |
> | packaged `./result/bin/sandbox-verify` | `Results: 23 passed, 0 failed` (A5 proven pre-change) |
> | `nix run .#agent-sandbox -- bash -c …` | runs, uid `1001`, cwd `/app` |
> | patched `./verify-sandbox.sh` from a checkout | `Results: 23 passed, 0 failed` |
> | `./sandbox.sh bash -c 'echo CHECKOUT-OK'` from a checkout | prints `CHECKOUT-OK` |
> | unpatched packaged `sandbox-verify` | fails exactly the two blockers 2.1/2.2 describe: `cd` into the read-only store ("Read-only file system"), `./sandbox.sh` → exit 127 (round 1) |
> | `shellcheck` on patched `verify-sandbox.sh` | only the intentional SC2016 note remains (round 1) |
> | `nix flake metadata path:.` pre-commit | adds the `agent-sandbox` lock node from the working tree |
> | single commit (files + `flake.lock`) → `nix build .#…` | clean tree: no lock rewrite, no dirty files |
> | `nix flake metadata .` | `input graph ok` |
> | `nix eval .#packages.x86_64-linux.agent-sandbox.version` | `"0.1.0"` |
> | sub-flake dir after all builds | no `flake.lock` created (D6) |
>
> Round 1 also caught two script defects, fixed in step 2: resolving `SELF_DIR` after
> the `cd` (abort with "no sandbox launcher found"), and a third `./sandbox.sh` call
> site in the ownership check.

**6.1 Repo checkout still works** (A6) — the only pre-Nix check; no build involved.

```sh
cd ~/nixos/packages/agent-sandbox
./sandbox.sh bash -c 'echo CHECKOUT-OK'
./verify-sandbox.sh
```

Pass: prints `CHECKOUT-OK` (the `resolve_bwrap()` fallback still matters), then
`Results: 23 passed, 0 failed`.

**6.2 Update the lock, then commit.** Root flake commands resolve the **committed**
tree (git+file), so the files must be committed before any `.#` build. The lock node
can be added from the working tree with the `path:` prefix — do that first, so files
and lock land in one commit:

```sh
cd ~/nixos
nix flake metadata path:.   # adds the agent-sandbox node to flake.lock (working tree)
git add -A
git commit                  # message below
```

Commit message:

```
feat(agent-sandbox): package the bwrap agent sandbox as a flake

Adds packages/agent-sandbox/{flake.nix,default.nix}: `sandbox` and
`sandbox-verify`, with bubblewrap pinned as a runtime dependency. Wired
through agent-sandbox.overlays.default and a root packages entry, installed
on the wsl host, along with bubblewrap itself and the /app interop anchor.
```

Pass: `git status --short` is empty.

**6.3 Build the package through the root flake** (A1, A2)

```sh
cd ~/nixos
nix build .#packages.x86_64-linux.agent-sandbox
ls -l result/bin
```

Pass: `sandbox` and `sandbox-verify` listed, regular files in
`/nix/store/...-agent-sandbox-0.1.0/bin/`. The tree stays clean: the lock was
committed in 6.2, so no lock rewrite happens.

**6.4 Dependency closure contains bubblewrap** (A3)

```sh
nix path-info -r ./result | grep -c bubblewrap
grep -o 'BWRAP=[^ ]*bwrap' result/bin/sandbox
```

Pass: at least `1`, then a `/nix/store/...-bubblewrap-0.11.2/bin/bwrap` path.

**6.5 Install and smoke-test on the host**

```sh
cd ~/nixos && sudo nixos-rebuild switch --flake .#nixos
command -v sandbox sandbox-verify bwrap && bwrap --version
sandbox bash -c 'echo SANDBOX-OK; id -u; pwd'
```

Pass: `bwrap --version` → `bubblewrap 0.11.2`; `SANDBOX-OK`, uid `1001`, pwd `/app`
(A4, A7).

Note: `sandbox bash -c 'command -v bwrap'` prints nothing. That is correct — the script
sets the sandbox `PATH` explicitly (`--setenv PATH …`) and bubblewrap is not part of it.
Bubblewrap runs on the host to *create* the namespace; nested sandboxing is not intended.
A7 is about the host PATH, which the `bubblewrap` entry in `environment.systemPackages`
covers.

**6.6 Boundary suite from the installed command** (A5)

```sh
sandbox-verify
```

Pass: `Results: 23 passed, 0 failed`, exit 0. The wrapper sets `SANDBOX_BIN` to the
installed `sandbox`, so this exercises the package, not the checkout. If a check fails,
run `sandbox-verify` from the checkout for comparison — that separates packaging
regressions from policy regressions.

**6.7 Real agent run**

```sh
cd ~/nixos && sandbox pi -p "list the files in this project"
```

Pass: agent completes and answers. This confirms the store-wrapped script still resolves
node, `~/.pi`, and the MCP servers from `$HOME`.

**6.8 Root flake input graph and package resolve** (cheap, no builds)

```sh
cd ~/nixos
nix flake metadata . > /dev/null && echo "input graph ok"
nix eval .#packages.x86_64-linux.agent-sandbox.version
```

Pass: `input graph ok`, then `"0.1.0"`. The first command validates the input graph
(the lock was already updated in 6.2, so nothing is rewritten); the second proves
`pkgs.agent-sandbox` resolves through the overlay and the new `packages` entry. Do not
run the root `nix flake check` for this change — it evaluates every output (slow); the
two commands above cover the same ground.

---

## 7. Risks and gotchas

| Risk | Impact | Mitigation |
|---|---|---|
| Store copy of `$HOME` paths at *build* time | Would bake in a user | None possible — the derivation installs scripts only; every host path is resolved at run time (D3) |
| `patchShebangs` omitted | `sandbox` fails with `/usr/bin/env: No such file or directory` | Step 3 calls it explicitly on `$out/bin` |
| Overlay attr named `sandbox` | Future collision in every package set | D1: attr `agent-sandbox`, `mainProgram = "sandbox"` |
| `lib.getExe finalAttrs.finalPackage` in `postFixup` | Infinite recursion at eval | Use the literal `$out/bin/sandbox` (builder-substituted) |
| Root flake commands see the committed tree | Uncommitted edits invisible to `nix build .#…` | Commit before Nix verification (6.2); only `path:`-prefixed commands use the working tree (the pre-commit lock update) |
| `nix flake metadata path:.` rewrites the root `flake.lock` | Noise commit if run outside 6.2 | It is the pre-commit lock update in 6.2 and the only lock this change touches — the sub-flake creates none (D6) |
| aarch64 evaluation | Fails at run time on `/lib64` | `platforms`/`supportedSystems` restricted to `x86_64-linux` (D5); nothing in the aarch64 package sets accesses `agent-sandbox`, so the attr stays unevaluated — if accessed, it fails with a missing-attribute error, not a cryptic bwrap error |
| Package pulls `/nix/store` + system profile into the sandbox read-only | Documented exposure, not a regression | Unchanged policy; README "Trade-offs" already covers it |
| `sandbox` needs `$HOME/.npm-global`, `$HOME/.cargo`, `$HOME/.local`, `$HOME/.nix-profile`, `$HOME/.pi` to exist | bwrap `--ro-bind` errors on a missing source | Known host assumption. Follow-up F2: switch those to `--ro-bind-try` |

Rollback: revert the two config edits plus the input/overlay/`packages` entry in
`flake.nix` and the lock node in `flake.lock`, rebuild. Nothing else touches state; `/app`
and `~/.cache/bwrap-experiments` can stay.

---

## 8. Out of scope / follow-ups

- **F1 aarch64** — bind the arch dynamic linker dir (`/lib` vs `/lib64`) with
  `--ro-bind-try`, then add `aarch64-linux` to `supportedSystems`/`meta.platforms`.
- **F2 portability** — `--ro-bind` → `--ro-bind-try` for the per-user `$HOME` binds so
  `sandbox` degrades gracefully on hosts missing `~/.cargo` or `~/.npm-global`.
- **F3 CI** — add a workflow that runs `nix build .#packages.x86_64-linux.agent-sandbox`
  (root flake; evaluates all inputs) and `shellcheck packages/agent-sandbox/*.sh` (needs
  the SC2016 annotation from 2.3). `sandbox-verify` cannot run in CI: it needs user
  namespaces and outbound HTTPS.
- **F4 nixosModule** — a `nixosModules.default` that sets `environment.systemPackages`
  and the `/app` tmpfiles rule in one import. Skipped: this repo installs host packages
  per host, and keeping the WSL host explicit is clearer for a single-host feature.
- **F5 shellcheck gate in the build** — `writeShellApplication`-style check via a
  `checkPhase`. Deferred until the existing findings are all annotated.
- **F6 rename `sandbox.sh` → keep** — no rename; the file is referenced by README, the
  wrapper, and muscle memory.
