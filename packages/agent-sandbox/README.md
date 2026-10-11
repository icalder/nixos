# bwrap sandbox for coding agents (pi, gemini, …) on NixOS

Goal: run the pi coding agent (and similar tools) in a bubblewrap sandbox that
prevents **accidental** edits/deletions out of scope — writable filesystem
access limited to the project directory, `/tmp`, and pi's own config dir —
while **read** access covers what the agent needs to work. A safe sandbox
equivalent to running the agent in docker/podman. Nix commands inside the
sandbox route through the host's nix daemon (see trade-offs), so
`nix-shell -p …`, `nix develop` and `nix build` work as on the host.

Threat model: accidental damage, not a malicious agent. pi's config lives in
github, so stray self-modification is recoverable, and pi sometimes needs to
modify its own files (adding an extension or skill, for example).

Result: **it works.** `./sandbox.sh pi -p "…"` runs a fully functional agent
loop (LLM, tools, file edits, bash, MCP servers) inside the sandbox, and a
verification suite proves the boundaries.

## Quick start

```sh
# from your project directory:
./sandbox.sh pi -p "list the files in this project"
./sandbox.sh pi -p "refactor foo.py and run the tests"

# any other command works too:
./sandbox.sh gemini -p "hello"
./sandbox.sh bash -c 'ls /'

# project dir defaults to $PWD, override with:
PROJECT_DIR=/path/to/project ./sandbox.sh pi -p "…"

# prove the boundaries:
./verify-sandbox.sh
```

## Install

- **Installed (NixOS, this flake):** `sandbox` and `sandbox-verify` are on `PATH`, and
  bubblewrap comes in as a dependency of the package. `./sandbox.sh` remains for running
  straight from a checkout.
- **One-off without installing:** `nix run .#agent-sandbox -- bash -c '…'` (the root
  flake's `packages` entry; `meta.mainProgram` selects `sandbox`).
- **Non-NixOS hosts:** install `bwrap` manually (Requirements below).

Requirements: NixOS (or any Linux with unprivileged user namespaces), and
`bubblewrap` — the script finds it on `PATH`, in `~/.nix-profile`, or
installs-on-demand via `nix-shell -p bubblewrap` (cached afterwards).
On NixOS with this flake it is a dependency of the `agent-sandbox` package and
is also on the system PATH. On this machine bubblewrap 0.11.2 is used.

The script is user-independent: host paths resolve from `$HOME` at runtime.
On WSL the Windows profile name is read off `/mnt/c/Users` (the best-matching,
then most recently touched, real profile wins; `cmd.exe` is the fallback and
`WIN_USER=…` the override), and it is exported into the sandbox as `WIN_USER`
so the browser-tools launcher inside does not have to guess. On non-WSL
machines the Windows-side binds are skipped automatically.

## What the sandbox looks like

| Path in sandbox | Source | Access | Why |
|---|---|---|---|
| `/app` | your project dir (`$PWD`) | **read-write** | the agent's workspace; a real bind mount, edits land on the host |
| `/tmp` | fresh tmpfs | **read-write** | private scratch, dies with the sandbox |
| `/home/sandbox/.pi` | host | **read-write** | pi's config, extensions, skills, sessions — pi self-manages (config is in git) |
| `/home/sandbox/.cache/codebase-memory-mcp` | host | **read-write** | codebase-memory index store — sandboxed runs share the host's indexed projects |
| `/home/sandbox/.config/gh` | host | **read-write** | gh CLI credentials (`hosts.yml`) — gh rewrites the file on token refresh, like `~/.pi` |
| `/home/sandbox/.cache`, `/home/sandbox/.gemini` | fresh tmpfs | **read-write** | tool caches that want to write in `$HOME` |
| `/nix/store` | host | read-only | node, all nix package deps |
| `/nix/var/nix` | fresh tmpfs | **read-write** | private nix client state — local-mode profile + GC temp roots |
| `/nix/var/nix/daemon-socket` | host | read-only | nix daemon socket — nix commands route through the host's daemon (when one runs) |
| `/etc/nix/nix.conf` | host | read-only | nix client config (flakes feature, substituters, trusted keys) |
| `/run/current-system/sw` | host | read-only | system binaries (git, curl, python3, …) |
| `/bin`, `/lib64`, `/usr/bin/env` | host | read-only | sh/bash, linker, `env` for `#!/usr/bin/env node` shebangs |
| `/etc/resolv.conf`, `/etc/passwd`, `/etc/group`, `/etc/ssl`, `/etc/static/ssl` | host | read-only | DNS, user lookup, TLS CA bundle |
| `~/.npm-global` | host | read-only | pi and gemini installs (node bundles) |
| `~/.nix-profile` | host | read-only | node, npm, user-installed nix tools |
| `~/.cargo` | host | **read-write** | cargo toolchain — registry cache, `cargo install` output (MCP server binaries) |
| `~/.go` | host | **read-write** | Go toolchain — module cache (`pkg/mod`), `go install` output (`-try` bind: hosts without Go still work) |
| `/home/sandbox/.cache/go-build` | host | **read-write** | Go build cache (default `GOCACHE`) — shared with the host, so sandboxed builds aren't cold every session |
| `~/.local` | host | read-only | codebase-memory-mcp binary |
| `/init`, `/run/WSL` | host | read-only | WSL interop — needed to launch Windows binaries (see Browser tools) |
| `/mnt/c/…/cmd.exe`, `/mnt/c/…/msedge.exe` | host | read-only | the only Windows executables exposed (profile-name fallback, Edge launcher) |
| `/mnt/c/Users/<you>/AppData/Local/Pi` | host | **read-write** | Edge browser profile dir used by the browser-tools skill |
| `/mnt/c/Users/<you>/AppData/Local/Microsoft/Edge/User Data` | host | read-only | source for the skill's `--profile` mode (your real Edge profile — see caveats) |
| `/proc` | fresh | (writes blocked by userns) | process view |
| `/dev` | minimal | — | null, tty, urandom, … no host devices |
| **everything else** | — | **invisible** | host home dir, ssh keys, other projects, /root, /etc/shadow, … |

Namespaces: `--unshare-all` (pid, net, ipc, uts, cgroup, user, mount) with
`--share-net` to keep networking. The user namespace maps your uid 1:1, so
files the agent creates in `/app` are owned by you on the host.

## How to think about it (docker comparison)

- The read-only binds are the "base image" (nix store + system + agent
  installs). They expose *readable* system packages — the same thing a docker
  image does — but nothing writable and no host-unique data.
- `/app` is the "project volume" and `/tmp` the "container tmp".
- `~/.pi` is a plain read-write bind — the "writable config layer": pi needs
to manage its own config (extensions, skills), sessions persist, and anything
stray is recoverable from git. The one deliberate exception to
project+/tmp-only writes.

## Verified properties (`./verify-sandbox.sh`)

- Cannot read: `~/.ssh`, `/etc/shadow`, `/root`, other home dirs, host
  `/tmp`. (The host home dir itself appears as an empty mount-point shell
  holding only the re-exposed `~/.pi` bind — bwrap creates the parent of
  that mount — but no host content inside it is visible.)
- Cannot write: `/`, `/etc`, `$HOME`, `/nix/store`, system profile.
- `~/.pi` is writable, as intended (pi self-manages; config is in git).
- `~/.config/gh` is visible and writable when the host has a gh login
  (checks skipped otherwise) — so `gh auth status` / `gh api` work in the sandbox.
- `~/.cargo` is visible and writable when the host has a cargo install
  (checks skipped otherwise) — so `cargo fetch` / `cargo build` work in the
  sandbox.
- `~/.go` is visible and writable, and the host's `~/.cache/go-build` is
  shared, when the host has a Go setup (checks skipped otherwise) — so
  `go build` / `go test` reuse the host's module and build caches instead of
  pointing `GOPATH`/`GOCACHE` at `/tmp`.
- Can read+write: `/app` (and changes propagate to the host) and `/tmp`.
- `nix-shell -p cowsay` runs end-to-end (via the host nix daemon; skipped when
  the host has no daemon socket).
- Fresh PID namespace (sees PID 1, far fewer processes than host).
- Runs as host uid; files created in the project keep correct ownership.
- Networking works: DNS + outbound HTTPS (TLS verified against the CA bundle).

## Issues found while experimenting (chronological)

1. **`bwrap` not installed** → resolve via `PATH` → nix profiles →
   `nix-shell -p bubblewrap`, caching the store path so startup is ~50 ms
   instead of ~1.9 s.
2. **Wrong per-user profile path** (the prior attempt) — the user's nix
   profile on this machine is `~/.nix-profile`
   (→ `~/.local/state/nix/profiles/profile`), *not*
   `/etc/profiles/per-user/<user>` (that dir is empty here). Missing it
   meant `node` was absent: `env: 'node': No such file or directory`.
3. **pi crashed: `EROFS` writing `~/.pi/agent/sessions`** — pi needs a
   writable state dir (sessions, `settings.json.lock`, `models-store.json`).
   A plain read-only bind of `~/.pi` is not enough; note the "Invalid
   settings file … mkdir settings.json.lock" warning is the giveaway — once
   settings loading fails, model resolution falls back and you get a
   misleading "No API key found for the selected model".
4. **`bwrap 0.11.2 has no `--tmpfile`** — you can't overlay a single writable
   file onto a read-only bind. The strict solution (tmpfs the whole
   `~/.pi/agent` dir, re-bind the read-only parts on top) works but adds a lot
   of mounts; since the threat model is accidents (not malice) and the config
   is in git, the final design just binds `~/.pi` read-write. Keep item 4's
   overlay in your back pocket if you ever want tamper-resistance.
5. **TLS failed inside sandbox (curl exit 60)** — `/etc/ssl/certs/ca-bundle.crt`
   is a symlink into `/etc/static/ssl/…`; only binding `/etc/ssl` left an
   empty CA set. Bind `/etc/static/ssl` too.
6. **Sandbox root was writable** (bwrap's default root is a fresh tmpfs) —
   `touch /x` and `touch /etc/x` succeeded. Fixed with `--remount-ro /`
   (non-recursive: intentional rw mounts like `/app`, `/tmp` stay writable).
7. **MCP servers: `spawn cratesio-mcp ENOENT`** — they live in
   `~/.cargo/bin` and `~/.local/bin`; bind both read-only and put them on
   `PATH`.
8. **`rg`/`fd` not on PATH** — the host gets them from `~/.pi/agent/bin` via
   shell config; the sandbox needs that dir on `PATH` too.
9. **gemini: `mkdir '/home/sandbox/.gemini' ENOENT`** warning — it wants a
   writable dir in `$HOME` (root is now read-only). A `--tmpfs` for it makes
   the warning go away (gemini itself already worked).
10. **Stale env vars when launched from within pi** — `PI_SESSION_FILE`,
    `PI_SESSION_ID`, `PI_CODING_AGENT` point at host paths; stripped with
    `--unsetenv`. `PI_PROVIDER`/`PI_MODEL` are kept (they select the local
    llama-swap model).
11. **WSL interop: `execvp cmd.exe: No such file or directory`** — the
    file *was* bound; the `WSLInterop` binfmt handler's interpreter is
    `/init`, which the sandbox didn't expose. Binding `/init` moved the
    failure to "connect failed" — the launcher also needs the per-process
    sockets in `/run/WSL`; it finds the right per-PID socket even though
    PIDs differ inside the namespace, so it works across the PID boundary.
    Both read-only binds fix
    it; PE binaries then run fine from inside (their DLLs resolve on the
    Windows side, so only the entry `.exe` needs binding).
12. **WSL interop: `Invalid argument` (EINVAL) when CWD is sandbox-only** —
    the interop launcher gives the Windows process a CWD mapped as
    `\\wsl.localhost\<distro>\<linux cwd>`, resolved through the *host's*
    view of the filesystem. A directory the host cannot see — one created
    inside the sandbox (`/home/sandbox`, anything under the private `/tmp`), or
    a project dir on a disk mounted only in the sandbox namespace — has no
    Windows path, and the exec dies with `Invalid argument` before the target
    program runs. Two things mislead here: a *successful* run prints `UNC paths
    are not supported. Defaulting to Windows directory.` and carries on (that
    warning is not the failure), and a bind mount of a host directory *does*
    resolve, because the host sees the directory it came from.
    Fix: every Windows exec pins its CWD to a directory that exists host-side
    (`/tmp`) — `interop_cwd` in `sandbox.sh`, `interopCwd()` in the browser-tools
    launcher. That also retires the old one-time `sudo mkdir /app`.
    Only the CWD *string* has to resolve, and only at exec time: once the
    process is up, Windows rejects its own UNC CWD and puts the child in
    `C:\Windows` (that is the entire warning), so the sandbox's `/tmp` and the
    host's never meet — it does not matter that they are different filesystems
    (tmpfs vs the host's ext4). The consequence to remember is that a Windows
    child resolves *relative* paths against `C:\Windows`, so pass it absolute
    paths on both sides (`/mnt/c/…`, `C:\…`), which the launcher does.
13. **`gh` reported "You are not logged into any GitHub hosts"** — gh keeps
    its auth in `~/.config/gh/hosts.yml`, but the sandbox only binds selected
    `~` dirs (`.pi`, `.cargo`, …); `~/.config` was invisible. Fixed with a
    read-write `--bind-try` of just `~/.config/gh`: gh rewrites `hosts.yml`
    on token refresh (so read-only is not enough), and `-try` keeps the
    sandbox working on hosts without a gh login.
14. **`nix-shell -p cowsay` failed: `creating directory "/nix/var/nix/profiles": Read-only file system`** —
    three layers, found by fixing one and re-running:
    (a) nix-shell/nix-env default their profile to
    `/nix/var/nix/profiles/per-user/<user>/profile` and use
    `/nix/var/nix/temproots` for GC temp roots; none of that exists in the
    sandbox and the root is remounted read-only → fixed with `--tmpfs
    /nix/var/nix` (private, per-session state tree).
    (b) `<nixpkgs>` then failed to resolve: the default NIX_PATH entry is
    `nixpkgs=flake:nixpkgs`, which needs the `flakes` experimental feature —
    configured in `/etc/nix/nix.conf`, which wasn't bound → bind it
    read-only.
    (c) finally the client tried to fetch the flake registry into the store
    and **lock a file next to the store path** — impossible on the read-only
    store. On the host this is invisible because strace shows the client
    talking to the nix daemon (`/nix/var/nix/daemon-socket/socket`), which
    runs as root and does all store work. Fix: bind the daemon socket
    read-only and set `NIX_REMOTE=daemon` (skipped when the host has no
    daemon socket). Side effect: fetches/builds from the sandbox land in the
    host store — exactly like running nix as this user on the host.
    Note the client does *not* pick the daemon automatically when the socket
    exists; `NIX_REMOTE=daemon` is required (`Store URL: local` without it).
15. **`cargo fetch` failed: `failed to create directory
    /home/sandbox/.cargo/registry/src/index.crates.io-…/winapi-util-0.1.11`
    (EROFS)** — cargo's registry cache and `cargo install` output live under
    `~/.cargo`, which was bound read-only. Fixed with a read-write bind (same
    accident-not-malice model as `~/.pi`).
16. **Go builds cold every session, module cache invisible** — `go build`
    defaults its build cache to `~/.cache/go-build` (a fresh tmpfs in the
    sandbox) and its module cache to `~/go/pkg/mod` (invisible), so the only
    workaround was pointing `GOCACHE`/`GOMODCACHE` at `/tmp`. Fixed with
    read-write `--bind-try` of `~/.go` and `~/.cache/go-build` (same model as
    `~/.cargo`; `-try` keeps the sandbox working on hosts without Go).
    `~/.go/bin` (`go install` output) joined `PATH` next to `~/.cargo/bin`.

## Trade-offs and limitations (read these)

- **Network is shared** (`--share-net`). The agent needs it for LLM APIs,
  which also means it can talk to localhost services (e.g. the llama-swap
  proxy on `:8080`) and any network reachable from the host. If you need
  stronger isolation, drop `--share-net` and run the LLM proxy in the
  sandbox too (or use a dedicated netns).
- **`~/.pi` is writable, including auth.json** — pi needs to manage its own
  config (extensions/skills) and the API keys must be readable anyway, so the
  whole dir is a read-write bind. A prompt-injected agent could modify its own
  instructions or keys — accepted under the accident threat model because the
  config is versioned in git. If you later want tamper-resistance, see issues
  log item 4.
- **gh credentials are exposed read-write** — `~/.config/gh` is bound
  read-write because gh rewrites `hosts.yml` on token refresh. Same accepted
  trade-off as `~/.pi` above; unlike `~/.pi` that config is not in git, so a
  stray edit means re-running `gh auth login` on the host.
- **Read exposure** — the whole nix store and system profile are readable.
  That's the docker base-image equivalent and is what makes the setup robust;
  binding individual store paths instead would be stricter but fragile.
- **Nix routes through the host daemon** — the sandbox's nix client is wired
  to the host nix daemon (`NIX_REMOTE=daemon`, socket bound read-only). That
  is what makes `nix-shell -p …` / `nix develop` / `nix build` work at all:
  client-side store access is read-only and can't even create the lock file
  its flake-registry fetch needs. Consequences: fetches and builds from the
  sandbox write to the host store, and the agent has this user's full
  nix-daemon access (per the host's `allowed-users`/`trusted-users`) —
  including `nix store delete`. Accepted under the accident threat model;
  set `NIX_REMOTE=local` for strict read-only-store mode (then only packages
  already in the store work, via the `/nix/var/nix` tmpfs).
- **No host devices/GPU** — only the minimal `--dev /dev` set.
- **Kernel requirement** — unprivileged user namespaces must be enabled
  (they are on this WSL2 NixOS box; `unshare -Ur true` is a quick test).
  `--unshare-all` includes the cgroup namespace — if that fails on another
  system, replace it with an explicit list omitting `--unshare-cgroup`.
- **WSL2 specifics** — `/bin` here is a WSL shim dir (symlinks into the
  store), and the CA bundle lives under `/etc/static/ssl`; both handled.
- **The browser itself runs on Windows, outside the sandbox.** The
  browser-tools skill drives a real Edge on the Windows desktop via CDP on
  `localhost:9222`. The sandbox only controls the WSL side (which files the
  agent can touch); once Edge is up, a prompt-injected agent can operate a
  fully-privileged, user-visible browser. Accepted here because the skill is
  designed for interactive use, but it is the one clearly out-of-sandbox
  capability in this setup.
- **`--profile` mode exposes your real Edge profile read-only** inside the
  sandbox (cookies/logins are readable). Only used when you pass `--profile`;
  remove the bind from `sandbox.sh` if you never want that reachable.

## Browser tools (browser-tools skill: Windows Edge via CDP)

Yes — the sandbox can start a browser. The skill launches **Edge on the
Windows side** (visible window on your desktop) through WSL interop, then
connects over CDP at `http://localhost:9222`.

What that required (all now in `sandbox.sh`):

1. **WSL interop from inside the namespace** — three missing pieces, found by
   bisection: the `WSLInterop` binfmt handler's interpreter `/init`, the
   per-process interop sockets in `/run/WSL`, and the PE executable itself.
   With those bound read-only, `cmd.exe`/`msedge.exe` run fine from inside.
2. **A CWD the Windows side can resolve** — interop maps the Linux CWD to
   `\\wsl.localhost\<distro>\<cwd>` and refuses the exec (`Invalid
   argument`) when that path is not visible from the host, which is true of
   anything created inside the sandbox (`/home/sandbox`, the private `/tmp`).
   So the launcher runs every Windows process from `/tmp` (`interopCwd()`),
   never from the caller's directory. That replaces the old one-time
   `sudo mkdir /app`.
3. **Minimal `/mnt/c` binds** — never the whole Windows filesystem: just
   `cmd.exe` (profile-name fallback), `msedge.exe` (launcher), the `Pi` profile
   dir (read-write, where Edge keeps its profile and the launcher clears
   `SingletonLock`), and the real Edge `User Data` dir read-only for
   `--profile` mode. The Windows profile name is resolved before bwrap runs
   (read off `/mnt/c/Users`, `cmd.exe` only as a fallback) and exported as
   `WIN_USER`, because inside the sandbox only the profile bound here is
   visible; `WIN_USER=…` overrides it, and on non-WSL machines all of these
   binds are skipped.

Usage from inside the sandbox (either skill path works — see caveat 1):

```sh
S=~/.pi/agent/skills/browser-tools
./sandbox.sh node $S/browser-start.js            # start Edge (visible window)
./sandbox.sh node $S/browser-nav.js https://example.com
./sandbox.sh node $S/browser-eval.js 'document.title'
./sandbox.sh node $S/browser-screenshot.js /tmp/shot.png
```

Verified: launch, navigate, eval, and screenshot all work from inside the
sandbox.

Caveats:

1. **Skill path** — `~/.pi/agent/skills/browser-tools` is a symlink to the
   absolute `~/.pi/pi-skills/browser-tools`. It resolves inside the sandbox
   because `~/.pi` is re-exposed at its own host path (so absolute links
   inside it resolve); both paths work.
2. **Slow first connect** — while Edge is starting, WSL2's localhost
   forwarding can hold the connection attempts (SYN not refused until the
   port is actually bound), so `browser-start.js`'s poll loop can look hung
   for a couple of minutes before succeeding. If `:9222` is already up, it
   exits immediately with "Edge already running".
3. **Stopping the test browser** — kill the main `msedge.exe` (its
   `--user-data-dir=…Pi\browser-profile` command line identifies it; don't
   blanket `taskkill /im msedge.exe` if your own Edge is open).
- **codebase-memory project names are path-derived** — a project indexed
  inside the sandbox is named after its sandbox path (e.g. `/app/foo` →
  `app-foo`), so it is a *different* store entry than the same directory
  indexed on the host (`home-<user>-…`). Existing host indexes are
  fully queryable from the sandbox (they're keyed by name in the shared
  store); re-indexing from the sandbox creates a second entry. Index big
  projects on the host, query them from the sandbox.
  Note `/app` itself is rejected as "too broad to index"; name a project
  directory below it.

## Known issues (deferred)

- **LSP tools are unverified.** `vtsls` is "not installed" on the host and in
  the sandbox alike (`lsp.json` has `installMode: off`, and the bundled server
  needs an explicit interactive `/lsp install vtsls`) — not a sandbox
  regression. `rust-analyzer`/`deno` resolve to nix-store paths from the LSP
  lockfile (the store is read-only bound, so launches should work in the
  sandbox too); `rust-analyzer` additionally only exists in projects whose
  flake provides the Rust toolchain. Verdict: iterate on these when a real
  project needs LSP in the sandbox, not upfront.

## Tuning

- Stricter: remove read-only binds you don't need (e.g. `~/.local`), make
  `~/.pi` read-only again (see issues log item 4 if pi must still run), or
  replace `--ro-bind /nix/store` with individual store paths.
- Looser: bind more of the host read-only, add `--dev-bind` for devices.
- Different project dir per invocation: `PROJECT_DIR=…` env var.
- Extra host paths for a particular task: `EXTRA_BINDS` env var —
  space-separated `SRC:DEST[:ro|rw]` entries (default `ro`), e.g.
  `EXTRA_BINDS="/data/reports:/app/data:ro /scratch:/tmp/scratch:rw" ./sandbox.sh pi -p "…"`.
  Binds are applied before `--remount-ro /`, so destination mount points can
  be created. (Raw `--ro-bind` flags passed after the script name *cannot* be
  used: they are appended after `--remount-ro /`, so bwrap can't create new
  mount points and fails with `Read-only file system`.)
- Different pi config: `PI_HOME=…` env var (the `~/.pi` path is parameterised).
- Different Windows setup (WSL): `WIN_USER=…` (otherwise read off
  `WIN_USERS_DIR`, default `/mnt/c/Users`, falling back to `cmd.exe`),
  `WIN_USERS_DIR=…`, `WSL_CMD_EXE=…`, `EDGE_EXE=…` env vars. `WIN_USER`,
  `WSL_CMD_EXE` and `EDGE_EXE` are also exported into the sandbox, so the
  browser-tools launcher inside uses exactly what was bound.
- Explicit bubblewrap binary: `BWRAP=…` env var (the package wrapper already pins
  it to the store path; override to test another build).
- Launcher for `sandbox-verify`: `SANDBOX_BIN=…` env var (the wrapper sets it to the
  installed `sandbox`; from a checkout it falls back to the sibling `sandbox.sh`,
  then to `sandbox` on `PATH`).
- Nix store access: `NIX_REMOTE=…` env var (defaults to `daemon` when the host's
  daemon socket exists; `NIX_REMOTE=local` for strict read-only-store mode) and
  `NIX_DAEMON_SOCKET=…` to point at a non-default daemon socket.
- Interactive use: `./sandbox.sh pi` works the same way (TUI runs in the
  sandbox); this project only tested non-interactive `pi -p`.

## Files

- `sandbox.sh` — the sandbox wrapper (one bwrap invocation, commented).
- `verify-sandbox.sh` — boundary verification suite; the nix-shell check is
  skipped when the host has no nix daemon socket, and the cargo, go and gh
  checks are skipped when the host lacks those toolchains.
