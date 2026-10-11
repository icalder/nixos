# Kernel and journald behaviour for a root filesystem on an SD card.
#
# SD cards do not fail cleanly under sustained write load; they stall. The
# controller erases blocks while it writes, so a burst of writeback can block
# the queue for seconds at a time, and every process with a dirty page is
# parked in an uninterruptible sleep until the queue drains. Nothing is logged,
# because nothing has actually errored.
#
# The defaults assume a block device with uniform latency, so they let a large
# amount of dirty data accumulate and then submit it in one burst. On an SD card
# that burst is the stall. The settings below keep writeback small and
# continuous instead, and keep reclaim awake early enough that processes never
# enter direct reclaim while the card is busy.
{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  MiB = m: m * 1024 * 1024;

  # Swapping is only cheap when something fast is behind it. With zram the swap
  # device is RAM, so trading page cache for swapped-out anonymous memory is a
  # win; with only a swapfile on the card it is the slowest device on the box
  # doing the work. These two settings therefore follow the swap topology rather
  # than being applied unconditionally -- hosts without zram (nixos-3a) get the
  # kernel defaults back.
  swapIsRamBacked = config.zramSwap.enable;

  # Restated rather than left unset: systemd-sysctl only writes keys present in
  # its config, so a key that simply leaves boot.kernel.sysctl keeps whatever
  # value an earlier generation already pushed into the running kernel.
  swappiness = if swapIsRamBacked then 180 else 60;
  pageCluster = if swapIsRamBacked then 0 else 3;
in
{
  options = {
    sdCardTuning.journalBudget = mkOption {
      type = types.str;
      default = "64M";
      description = ''
        Ceiling for the persistent journal. The journal is the largest
        continuous writer on a quiet host, and its size is unbounded by default
        (15% of the filesystem), which on a 30 GB card is over 4 GB.
      '';
    };
  };

  config = {
    boot.kernel.sysctl = {
      # Express the dirty-page limits in bytes. The ratio defaults resolve to
      # roughly 86 MiB background / 173 MiB hard limit on a 1 GB host, and
      # 173 MiB is far more than an SD card can absorb in one go. Writing these
      # keys clears the corresponding *_ratio keys, which is what we want.
      "vm.dirty_background_bytes" = MiB 8;
      "vm.dirty_bytes" = MiB 24;

      # Start kswapd at 1% of memory rather than the default 0.1%. Waking it
      # early is what keeps processes out of direct reclaim, and direct reclaim
      # on a host whose only reclaim target is a busy SD card is the deadlock
      # that requires a power cycle.
      "vm.watermark_scale_factor" = 100;

      # Keep a larger atomic reserve. DMA and network allocations cannot
      # sleep-for-reclaim, and a 22 MiB default is easily exhausted by a card
      # that is mid-erase.
      "vm.min_free_kbytes" = 65536;

      # Prefer swapping to discarding the page cache, but only when swap is
      # RAM-backed. Compressed in-RAM swap costs far less than re-reading
      # binaries from a stalled card, so bias reclaim towards anonymous memory;
      # values above 100 are valid and mean "swap is cheaper than page cache".
      # Without zram this does the opposite of what it is for, so it falls back
      # to the kernel default of 60.
      "vm.swappiness" = swappiness;

      # Dentries and inodes are cheap to regenerate; let go of them sooner.
      "vm.vfs_cache_pressure" = 200;

      # Swap readahead, as a power of two in pages: 0 means 4 KiB per fault
      # instead of the default 1 MiB. Against zram, readahead is a wasted bet
      # because zram access is cheap and near-random. Against a swapfile on the
      # card the opposite holds -- small reads are worse than bulk reads -- so
      # the default of 3 (1 MiB) is kept there.
      "vm.page-cluster" = pageCluster;
    };

    # fstrim on an SD card is close to useless -- the card's own wear levelling
    # already remaps blocks -- and it is a long, queue-saturating operation that
    # competes with everything else for the same bus.
    services.fstrim.enable = false;

    services.journald.extraConfig = ''
      SystemMaxUse=${config.sdCardTuning.journalBudget}
      SystemKeepFree=512M
      RuntimeMaxUse=32M
      # Bound a single journal file so vacuuming stays cheap on a slow card.
      MaxFileSec=1week
      # Sealing adds a hash chain per record, i.e. more writes and more CPU,
      # for a tamper-evidence guarantee that is worthless once the card itself
      # is the thing being trusted.
      Seal=no
    '';
  };
}
