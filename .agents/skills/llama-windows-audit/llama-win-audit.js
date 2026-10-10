#!/usr/bin/env node
'use strict';

/**
 * llama-win-audit.js — audit performance changes in llama.cpp relative to the
 * version currently deployed in the Windows install directory.
 *
 * This is a thin wrapper around the shared core in
 * ../_shared/llama-audit-core.js.  It is responsible only for:
 *   - CLI argument parsing (--win-dir, --tag, --repo, --swap-settings,
 *     --target, --brief, --help)
 *   - extracting the base build tag from the Windows llama.cpp manifest
 *     (~/winhome/llama-cpp/.llama-cpp-manifest, # build: bXXXXX line)
 *   - locating the Windows llama-swap YAML config
 *     (~/winhome/scoop/persist/llama-swap/config.yaml) and choosing the
 *     right extraction strategy (YAML-aware vs. Nix)
 *
 * All GitHub comparison, swap-settings parsing, commit filtering, and output
 * formatting live in the shared core so this skill reuses the exact same
 * logic as the Nix-config-based auditor (llama-performance-audit).
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const {
  audit,
  resolveProjectPath,
  extractPriorityTerms,
  extractPriorityTermsFromYaml,
} = require(path.join(__dirname, '..', '_shared', 'llama-audit-core.js'));

const DEFAULT_WIN_DIR = path.join(os.homedir(), 'winhome', 'llama-cpp');
const MANIFEST_NAME = '.llama-cpp-manifest';

function usage() {
  console.log(`Usage: node $0 [--win-dir PATH] [--tag TAG] [--repo OWNER/REPO] [--swap-settings PATH] [--target TAG] [--brief]

Options:
  --win-dir PATH      Windows llama.cpp install directory (default: ~/winhome/llama-cpp)
  --tag TAG           Use explicit Git tag (e.g. b11429) instead of reading manifest
  --repo REPO         GitHub repo (default: ggml-org/llama.cpp)
  --swap-settings PATH  Path to a swap-settings config file (.yaml or .nix).
                        Defaults to the Windows llama-swap YAML config, falling
                        back to the Nix module if not found.
  --target TAG        Compare to this tag (default: latest release, not master)
  --brief             One-line per matching commit
  --help              Show this help`);
}

// ── CLI Parsing ────────────────────────────────────────────────────────
const args = process.argv.slice(2);
let REPO = 'ggml-org/llama.cpp';
let TAG = '';
let WIN_DIR = '';
let SWAP_SETTINGS = '';
let TARGET = '';
let BRIEF = false;

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === '--win-dir') WIN_DIR = args[++i];
  else if (arg === '--tag') TAG = args[++i];
  else if (arg === '--repo') REPO = args[++i];
  else if (arg === '--swap-settings') SWAP_SETTINGS = args[++i];
  else if (arg === '--target') TARGET = args[++i];
  else if (arg === '--brief') BRIEF = true;
  else if (arg === '--help') { usage(); process.exit(0); }
  else {
    process.stderr.write(`Unknown arg: ${arg}\n`);
    usage();
    process.exit(2);
  }
}

// ── Auto-detect swap-settings ─────────────────────────────────────────
//
// On the Windows workflow the *actual* llama-swap config lives at:
//   ~/winhome/scoop/persist/llama-swap/config.yaml
//
// That YAML file contains the real `cmd:` strings per model and is the
// source of truth for your deployed flags.  Fall back to the Nix module
// only when the Windows YAML is unavailable.
if (!SWAP_SETTINGS) {
  const DEFAULT_WIN_CONFIG = path.join(
    os.homedir(), 'winhome', 'scoop', 'persist', 'llama-swap', 'config.yaml',
  );
  for (const s of [
    DEFAULT_WIN_CONFIG,
    '@modules/llama-swap-settings.nix',
    './modules/llama-swap-settings.nix',
    './llama-swap-settings.nix',
    path.join(__dirname, '..', '..', '..', 'modules', 'llama-swap-settings.nix'),
  ]) {
    if (fs.existsSync(resolveProjectPath(s))) { SWAP_SETTINGS = s; break; }
  }
}

// ── Extract Tag from Windows Manifest ──────────────────────────────────
if (!TAG) {
  const winDir = WIN_DIR || DEFAULT_WIN_DIR;
  const manifestPath = path.join(winDir, MANIFEST_NAME);

  if (!fs.existsSync(manifestPath)) {
    process.stderr.write(
      `Could not find Windows manifest at ${manifestPath}\n` +
      `Install your Windows llama.cpp build (update-llama-cpp.sh) or use --tag.\n`,
    );
    process.exit(2);
  }

  const content = fs.readFileSync(manifestPath, 'utf8');
  const buildMatch = content.match(/^# build:\s*(b?\d+)/m);
  if (!buildMatch) {
    process.stderr.write(
      `Could not detect build tag in ${manifestPath} (expected "# build: bXXXXX")\n`,
    );
    process.exit(2);
  }
  // Normalize to "b" + digits form
  TAG = buildMatch[1].startsWith('b')
    ? buildMatch[1]
    : `b${buildMatch[1]}`;
}

// ── Choose extraction strategy & run audit ─────────────────────────────
//
// The Windows YAML config needs a different parser than the Nix module.
// We detect format by file extension and pre-extract priority terms, then
// pass them directly to audit() (the caller-owned Strategy pattern keeps
// the shared core format-agnostic).
let priorityTerms = [];
if (SWAP_SETTINGS) {
  const resolved = resolveProjectPath(SWAP_SETTINGS);
  if (/\.ya?ml$/i.test(resolved)) {
    priorityTerms = extractPriorityTermsFromYaml(resolved);
  } else {
    priorityTerms = extractPriorityTerms(resolved);
  }
}

audit({
  repo: REPO,
  tag: TAG,
  target: TARGET,
  priorityTerms,
  brief: BRIEF,
});

process.exit(0);
