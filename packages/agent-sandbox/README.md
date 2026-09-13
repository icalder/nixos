# bwrap sandbox for coding agents (pi, gemini, …) on NixOS

Goal: run the pi coding agent (and similar tools) in a bubblewrap sandbox that
prevents **accidental** edits/deletions out of scope — writable filesystem
access limited to the project directory, `/tmp`, and pi's own config dir —
while **read** access covers what the agent needs to work. A safe sandbox
equivalent to running the agent in docker/podman.

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

The script is user-independent: host paths resolve from `$HOME` at runtime,
and on WSL the Windows username is detected via `cmd.exe` (override with
`WIN_USER=…`). On non-WSL machines the Windows-side binds are skipped
automatically.

## What the sandbox looks like

| Path in sandbox | Source | Access | Why |
|---|---|---|---|
| `/app` | your project dir (`$PWD`) | **read-write** | the agent's workspace; a real bind mount, edits land on the host |
| `/tmp` | fresh tmpfs | **read-write** | private scratch, dies with the sandbox |
| `/home/sandbox/.pi` | host | **read-write** | pi's config, extensions, skills, sessions — pi self-manages (config is in git) |
| `/home/sandbox/.cache/codebase-memory-mcp` | host | **read-write** | codebase-memory index store — sandboxed runs share the host's indexed projects |
| `/home/sandbox/.cache`, `/home/sandbox/.gemini` | fresh tmpfs | **read-write** | tool caches that want to write in `$HOME` |
| `/nix/store` | host | read-only | node, all nix package deps |
| `/run/current-system/sw` | host | read-only | system binaries (git, curl, python3, …) |
| `/bin`, `/lib64`, `/usr/bin/env` | host | read-only | sh/bash, linker, `env` for `#!/usr/bin/env node` shebangs |
| `/etc/resolv.conf`, `/etc/passwd`, `/etc/group`, `/etc/ssl`, `/etc/static/ssl` | host | read-only | DNS, user lookup, TLS CA bundle |
| `~/.npm-global` | host | read-only | pi and gemini installs (node bundles) |
| `~/.nix-profile` | host | read-only | node, npm, user-installed nix tools |
| `~/.cargo`, `~/.local` | host | read-only | MCP server binaries (cratesio-mcp, codebase-memory-mcp) |
| `/init`, `/run/WSL` | host | read-only | WSL interop — needed to launch Windows binaries (see Browser tools) |
| `/mnt/c/…/cmd.exe`, `/mnt/c/…/msedge.exe` | host | read-only | the only Windows executables exposed (username lookup, Edge launcher) |
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

- Cannot read: `~/.ssh`, `/etc/shadow`, `/root`, other home dirs, host `/tmp`.
- Cannot write: `/`, `/etc`, `$HOME`, `/nix/store`, system profile.
- `~/.pi` is writable, as intended (pi self-manages; config is in git).
- Can read+write: `/app` (and changes propagate to the host) and `/tmp`.
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
    the launcher sets the Windows process's CWD to the Linux CWD mapped as
    `\\wsl.localhost\NixOS\<path>`; if that path doesn't exist on the host
    (e.g. `/app`, which is a bind that exists only inside the sandbox),
    launch fails. CWDs that exist on the host (`/tmp`, `/run/WSL`, …) work.
    Fixed by creating an empty `/app` on the host (`sudo mkdir /app`,
    one-time) so the Windows-side path exists; the project bind covers it
    up inside the sandbox.

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
- **Read exposure** — the whole nix store and system profile are readable.
  That's the docker base-image equivalent and is what makes the setup robust;
  binding individual store paths instead would be stricter but fragile.
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
2. **`/app` must exist on the host** (one-time: `sudo mkdir /app`). The
   interop launcher maps the Linux CWD to a Windows path
   (`\\wsl.localhost\NixOS\app`) and fails with `Invalid argument` if that
   path doesn't exist on the Windows side. The sandbox bind of your project
   over `/app` is unaffected; the empty host dir is just the Windows-side
   anchor. (Any CWD that exists only inside the sandbox breaks interop the
   same way.)
3. **Minimal `/mnt/c` binds** — never the whole Windows filesystem: just
   `cmd.exe` (username), `msedge.exe` (launcher), the `Pi` profile dir
   (read-write, where Edge stores its profile and the script cleans
   `SingletonLock`), and the real Edge `User Data` dir read-only for
   `--profile` mode. The Windows username is detected at startup via
   `cmd.exe` (the same trick the skill uses); `WIN_USER=…` overrides it,
   and on non-WSL machines all of these binds are skipped.

Usage from inside the sandbox (note the real path — see caveat 1):

```sh
S=~/.pi/pi-skills/browser-tools
./sandbox.sh node $S/browser-start.js            # start Edge (visible window)
./sandbox.sh node $S/browser-nav.js https://example.com
./sandbox.sh node $S/browser-eval.js 'document.title'
./sandbox.sh node $S/browser-screenshot.js /tmp/shot.png
```

Verified: launch, navigate, eval, and screenshot all work from inside the
sandbox.

Caveats:

1. **Dangling skill symlink** — `~/.pi/agent/skills/browser-tools` is a
   symlink to `~/.pi/pi-skills/browser-tools`; the absolute target doesn't
   exist inside the sandbox. Invoke scripts via the real
   `~/.pi/pi-skills/browser-tools/…` path (as above). Optional one-line host
   fix that works in both environments: make the link relative
   (`ln -sfn ../pi-skills/browser-tools ~/.pi/agent/skills/browser-tools`) —
   that's a change to your git-tracked `~/.pi`, so it's left to you.
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
- Different Windows user (WSL): `WIN_USER=…` env var (auto-detected via
  `cmd.exe` by default).
- Explicit bubblewrap binary: `BWRAP=…` env var (the package wrapper already pins
  it to the store path; override to test another build).
- Launcher for `sandbox-verify`: `SANDBOX_BIN=…` env var (the wrapper sets it to the
  installed `sandbox`; from a checkout it falls back to the sibling `sandbox.sh`,
  then to `sandbox` on `PATH`).
- Interactive use: `./sandbox.sh pi` works the same way (TUI runs in the
  sandbox); this project only tested non-interactive `pi -p`.

## Files

- `sandbox.sh` — the sandbox wrapper (one bwrap invocation, commented).
- `verify-sandbox.sh` — 23-check boundary verification suite.
- `AGENTS.md` — project aim and the failing prior attempt.
