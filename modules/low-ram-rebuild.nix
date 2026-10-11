# Constrain how a Nix rebuild may consume this machine.
#
# A `nixos-rebuild` on a low-RAM host fails in two distinct ways:
#
#   1. Peak RSS exceeds what is left, and the OOM killer fires.
#   2. Peak RSS stays *just* inside RAM, so nothing is killed, but reclaim and
#      block I/O fight each other and every process ends up in an
#      uninterruptible sleep. The box stops answering and only a power cycle
#      clears it.
#
# Failure 2 is the dangerous one, and it is silent: no OOM record is written, so
# the event leaves no evidence behind. This module exists to turn failure 2 into
# failure 1, because a logged, failed build leaves the machine running.
#
# Three mechanisms do that:
#
#   * Nix pauses before memory runs out (`min-free`), so a build stops at a
#     known-safe point rather than at whatever point the kernel gives up.
#   * Builds are serialised, so peak RSS is one compiler rather than one per
#     core.
#   * The build runs in a memory cgroup with a ceiling, so a build that outruns
#     the pause is killed inside its own cgroup instead of taking the host.
#
# Derivations are built by nix-daemon, not by the unit that asked for them, so
# the cgroup ceiling has to go on nix-daemon. Putting it on nixos-upgrade only
# caps the client and the activation script.
#
# Opt-in, and sized per host. The ceilings are tuned for a machine with a few
# hundred MiB to give away; applying them to a board with spare RAM turns an
# OOM-avoidance measure into an OOM cause, and serialising builds there is a
# throughput loss bought for nothing. Only hosts that set lowRamRebuild.enable
# are affected.
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.lowRamRebuild;

  # Bytes, so callers pass memory sizes rather than magic factors.
  MiB = m: m * 1024 * 1024;
in
{
  options = {
    lowRamRebuild = {
      enable = mkEnableOption ''
        constraints on how a Nix rebuild may consume this machine: serialised
        builds, a memory cgroup ceiling on nix-daemon, and deprioritised build
        units. Enable only on hosts whose RAM is the binding constraint.'';

      throttleAtMiB = mkOption {
        type = types.ints.positive;
        default = 512;
        description = ''
          memory.high for nix-daemon. Above this the kernel reclaims hard from
          the build's cgroup and slows it down. Counts page cache too, so expect
          it to bite well before the build is actually in trouble.
        '';
      };

      killAtMiB = mkOption {
        type = types.ints.positive;
        default = 640;
        description = ''
          memory.max for nix-daemon. Above this the kernel kills the build,
          which surfaces as a failed derivation. Must exceed throttleAtMiB, and
          must leave enough RAM for the kernel, journald and sshd.
        '';
      };

      swapBudgetMiB = mkOption {
        type = types.ints.positive;
        default = 1024;
        description = ''
          memory.swap.max for nix-daemon. Bounds how far a build may spill onto
          backing store.
        '';
      };

      pauseBelow = mkOption {
        type = types.ints.positive;
        default = MiB 256;
        description = ''
          Nix waits before starting a build while available memory is under this
          many bytes.
        '';
      };

      resumeAt = mkOption {
        type = types.ints.positive;
        default = MiB 512;
        description = ''
          Nix resumes waiting builds once available memory reaches this many
          bytes. Must exceed pauseBelow or builds thrash at the boundary.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # One derivation at a time, one compiler thread per derivation.
    #
    # `cores = 0` -- the NixOS default behind the obsolete nix.buildCores --
    # hands every build all CPUs, so cargo or make start one compiler process
    # per core. Two concurrent builds on four cores is eight concurrent
    # compilers, which is how a survivable peak becomes an unrecoverable one.
    nix.settings = {
      max-jobs = 1;
      cores = 1;

      # Disk-space-triggered garbage collection, NOT a memory guard. Per the Nix
      # manual: when free disk in /nix/store falls below min-free during a
      # build, Nix garbage-collects until max-free bytes are free. The names
      # invite the wrong reading; the memory protection in this module comes
      # entirely from the serialisation above and the cgroup ceiling below.
      min-free = config.lowRamRebuild.pauseBelow;
      max-free = config.lowRamRebuild.resumeAt;

      # Hardlink store paths as they are realised. Costs no extra I/O at build
      # time and directly buys back space on a small root partition.
      auto-optimise-store = true;
    };

    systemd.services.nix-daemon = {
      serviceConfig = {
        # Builds yield CPU and disk to interactive work. Keeping sshd and
        # journald able to make progress is what separates a slow machine from
        # an unreachable one. nix-daemon.nix sets its own best-effort/4 pair,
        # so these have to override it rather than clash with it.
        Nice = 19;
        CPUWeight = 20;
        IOSchedulingClass = lib.mkForce "idle";
        IOSchedulingPriority = lib.mkForce 7;

        MemoryAccounting = true;
        MemoryHigh = "${toString config.lowRamRebuild.throttleAtMiB}M";
        MemoryMax = "${toString config.lowRamRebuild.killAtMiB}M";
        MemorySwapMax = "${toString config.lowRamRebuild.swapBudgetMiB}M";

        # Ninja and cargo spawn a process per job; cap them so a runaway build
        # cannot exhaust the PID space either.
        TasksAccounting = true;
        TasksMax = 512;
      };
    };

    systemd.services.nixos-upgrade = {
      serviceConfig = {
        # The client and its activation script. Activation restarts every unit,
        # which is when a host already short of memory tends to stall, so give
        # it a bounded window rather than an indefinite one.
        Nice = 19;
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 7;
        MemoryAccounting = true;
        TasksAccounting = true;
        TasksMax = 512;
        TimeoutStartSec = "3h";
      };
    };
  };
}
