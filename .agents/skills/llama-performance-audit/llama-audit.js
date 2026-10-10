#!/usr/bin/env node
'use strict';

/**
 * llama-audit.js — audit performance changes in llama.cpp relative to the
 * version pinned in a NixOS configuration file.
 *
 * This is a thin wrapper around the shared core in
 * ../_shared/llama-audit-core.js.  It is responsible only for:
 *   - CLI argument parsing (--config, --tag, --repo, --swap-settings,
 *     --target, --brief, --help)
 *   - extracting the base build tag from the Nix config
 *
 * All GitHub comparison, swap-settings parsing, commit filtering, and output
 * formatting live in the shared core so the sibling Windows auditor reuses
 * the same logic without duplication.
 */

const fs = require('fs');
const path = require('path');
const {
  audit,
  extractPriorityTerms,
  resolveProjectPath,
} = require(path.join(__dirname, '..', '_shared', 'llama-audit-core.js'));

function usage() {
  console.log(`Usage: node $0 [--config PATH] [--tag TAG] [--repo OWNER/REPO] [--swap-settings PATH] [--target TAG] [--brief]

Options:
  --config PATH       Parse a Nix configuration to extract a tag/version (e.g. configuration.nix)
  --tag TAG           Use explicit Git tag (e.g. b9222)
  --repo REPO         GitHub repo (default: ggml-org/llama.cpp)
  --swap-settings PATH  Path to modules/llama-swap-settings.nix to extract your model flags
  --target TAG        Compare to this tag (default: latest release, not master)
  --brief             One-line per matching commit
  --help              Show this help`);
}

// ── CLI Parsing ────────────────────────────────────────────────────────
const args = process.argv.slice(2);
let REPO = 'ggml-org/llama.cpp';
let TAG = '';
let CONFIG = '';
let SWAP_SETTINGS = '';
let TARGET = '';
let BRIEF = false;

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === '--config') CONFIG = args[++i];
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

// ── Auto-detect config path ────────────────────────────────────────────
if (!TAG && !CONFIG) {
  for (const c of [
    '@hosts/wsl/configuration.nix',
    './configuration.nix',
    './hosts/wsl/configuration.nix',
  ]) {
    if (fs.existsSync(resolveProjectPath(c))) { CONFIG = c; break; }
  }
}
if (!SWAP_SETTINGS) {
  for (const s of [
    '@modules/llama-swap-settings.nix',
    './modules/llama-swap-settings.nix',
    './llama-swap-settings.nix',
  ]) {
    if (fs.existsSync(resolveProjectPath(s))) { SWAP_SETTINGS = s; break; }
  }
}

if (!TAG && !CONFIG) {
  process.stderr.write(
    'Either --tag or --config must be provided (no auto-detect found)\n',
  );
  usage();
  process.exit(2);
}

// ── Extract Tag from Nix Config ────────────────────────────────────────
if (CONFIG) {
  const resolvedConfig = resolveProjectPath(CONFIG);
  if (!fs.existsSync(resolvedConfig)) {
    process.stderr.write(`Config file not found: ${CONFIG}\n`);
    process.exit(2);
  }
  const content = fs.readFileSync(resolvedConfig, 'utf8');
  let tagMatch = content.match(/(?:tag|rev|shortRev)\s*=\s*"b(\d+)"/);
  if (tagMatch) {
    TAG = `b${tagMatch[1]}`;
  } else {
    let verMatch = content.match(/version\s*=\s*"(\d+)"/);
    if (verMatch) TAG = `b${verMatch[1]}`;
  }
  if (!TAG) {
    process.stderr.write(
      `Could not detect tag in ${CONFIG}; try --tag manually\n`,
    );
    process.exit(2);
  }
}

// ── Run Audit via Shared Core ──────────────────────────────────────────
audit({
  repo: REPO,
  tag: TAG,
  target: TARGET,
  swapSettings: SWAP_SETTINGS,
  brief: BRIEF,
});

process.exit(0);
