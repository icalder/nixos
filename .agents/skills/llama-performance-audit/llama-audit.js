#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

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

// --- CLI Parsing ---
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

// --- Auto-detect ---
if (!TAG && !CONFIG) {
  for (const c of ['@hosts/wsl/configuration.nix', './configuration.nix', './hosts/wsl/configuration.nix']) {
    if (fs.existsSync(c)) { CONFIG = c; break; }
  }
}
if (!SWAP_SETTINGS) {
  for (const s of ['@modules/llama-swap-settings.nix', './modules/llama-swap-settings.nix', './llama-swap-settings.nix']) {
    if (fs.existsSync(s)) { SWAP_SETTINGS = s; break; }
  }
}

if (!TAG && !CONFIG) {
  process.stderr.write('Either --tag or --config must be provided (no auto-detect found)\n');
  usage();
  process.exit(2);
}

// --- Extract Tag from Config ---
if (CONFIG) {
  if (!fs.existsSync(CONFIG)) {
    process.stderr.write(`Config file not found: ${CONFIG}\n`);
    process.exit(2);
  }
  const content = fs.readFileSync(CONFIG, 'utf8');
  let tagMatch = content.match(/(?:tag|rev|shortRev)\s*=\s*"b(\d+)"/);
  if (tagMatch) {
    TAG = `b${tagMatch[1]}`;
  } else {
    let verMatch = content.match(/version\s*=\s*"(\d+)"/);
    if (verMatch) TAG = `b${verMatch[1]}`;
  }
  if (!TAG) {
    process.stderr.write(`Could not detect tag in ${CONFIG}; try --tag manually\n`);
    process.exit(2);
  }
}

// --- Extract Priority Terms from Swap Settings ---
const priorityTerms = [];
const stopWords = new Set(['on', 'off', 'the', 'and', 'for', 'with', 'from', 'into', 'not', 'yes', 'no']);

if (SWAP_SETTINGS && fs.existsSync(SWAP_SETTINGS)) {
  const content = fs.readFileSync(SWAP_SETTINGS, 'utf8').slice(0, 40000);

  // 1. Long flags: --flag value
  const flagMatches = content.matchAll(/--[a-zA-Z0-9_-]+(?:\s+[^"'\s]+)?/g);
  for (const m of flagMatches) {
    for (const word of m[0].trim().split(/\s+/)) {
      const clean = word.replace(/^-+/, '').toLowerCase();
      if (clean.length >= 3 && !stopWords.has(clean)) priorityTerms.push(clean);
    }
  }

  // 2. Short flags: -flag
  const shortMatches = content.matchAll(/-[a-zA-Z0-9_-]+/g);
  for (const m of shortMatches) {
    const clean = m[0].replace(/^-+/, '').toLowerCase();
    if (clean.length >= 2 && !stopWords.has(clean)) priorityTerms.push(clean);
  }

  // 3. Quantization patterns
  const quantMatches = content.matchAll(/Q\d+_[A-Z0-9_]+|UD-Q\d+_[A-Z0-9_]+/gi);
  for (const m of quantMatches) {
    priorityTerms.push(m[0].toLowerCase());
  }
}
const uniquePriorityTerms = [...new Set(priorityTerms)];

// --- Build Keyword Regexes ---
const BASE_KEYWORDS = '(perf|performance|speed|optimi|tune|throughput|latency|cuda|pdl|flash-attn|flash|vulkan|metal|opencl|sycl|hexagon|adreno|rdna|bf16|fp16|quantiz|moe|mtp|speculat|draft|sampling|d2h|gpu|server|bench|batched-bench|fit-params|quantize|perplexity|ggml-cuda|ggml-zendnn|pdl)';

const priorityRegexStr = uniquePriorityTerms.length > 0 ? `(${uniquePriorityTerms.join('|')})` : '';
const keywordsRegex = new RegExp(`${BASE_KEYWORDS}${priorityRegexStr ? '|' + priorityRegexStr : ''}`, 'i');

// Use word boundaries for priority matching to avoid false positives (e.g., "on" matching "reasoning")
const priorityMatchRegex = uniquePriorityTerms.length > 0
  ? new RegExp(`\\b(${uniquePriorityTerms.map(t => t.replace(/[-_]/g, '[-_ ]')).join('|')})\\b`, 'i')
  : null;

// --- Helper: Run gh CLI ---
function runGh(argsStr) {
  try {
    return execSync(`gh ${argsStr}`, { encoding: 'utf8' });
  } catch (e) {
    process.stderr.write(`gh command failed: ${e.message}\n`);
    process.exit(2);
  }
}

// --- Resolve Target ---
if (!TARGET) {
  try {
    const latestResp = runGh(`api -H "Accept: application/vnd.github+json" "repos/${REPO}/releases/latest"`);
    const latest = JSON.parse(latestResp);
    TARGET = latest.tag_name || 'master';
    process.stderr.write(`Latest release: ${TARGET}\n`);
  } catch (e) {
    process.stderr.write(`Could not fetch latest release; defaulting to master\n`);
    TARGET = 'master';
  }
}

process.stderr.write(`Comparing ${REPO}:${TAG} -> ${TARGET}...\n`);

// --- Fetch Commits with Pagination ---
const allCommits = [];
let page = 1;
let totalPages = 1;
let totalCommits = 0;

while (page <= totalPages) {
  const respStr = runGh(`api -H "Accept: application/vnd.github+json" "repos/${REPO}/compare/${TAG}...${TARGET}?per_page=30&page=${page}"`);
  const resp = JSON.parse(respStr);
  
  if (page === 1) {
    totalCommits = resp.total_commits || 0;
    if (totalCommits === 0) {
      process.stderr.write(`gh compare failed or no commits found. Ensure the repo and tag exist and you have gh auth set up.\n`);
      process.exit(3);
    }
    totalPages = Math.ceil(totalCommits / 30);
    if (totalPages > 1) process.stderr.write(`Found ${totalCommits} commits across ${totalPages} pages, fetching...\n`);
  }
  
  if (resp.commits) {
    for (const c of resp.commits) {
      allCommits.push({
        sha: c.sha,
        message: c.commit.message.replace(/\n/g, ' '),
        url: c.html_url
      });
    }
  }
  page++;
}

// --- Filter & Categorize ---
const matched = [];
const priorityMatched = [];

for (const commit of allCommits) {
  if (keywordsRegex.test(commit.message)) {
    const isPriority = priorityMatchRegex ? priorityMatchRegex.test(commit.message) : false;
    if (isPriority) {
      priorityMatched.push(commit);
    } else {
      matched.push(commit);
    }
  }
}

const totalMatched = matched.length + priorityMatched.length;
if (totalMatched === 0) {
  process.stderr.write('No performance-related commits detected in the diff (by keyword).\n');
  console.log(`You can inspect the full commit list at: https://github.com/${REPO}/compare/${TAG}...${TARGET}`);
  process.exit(0);
}

// --- Output Formatting ---
const printEntry = (c) => {
  const msg = c.message.replace(/\s+/g, ' ').replace(/\s*\(.*?\)\s*/g, '').trim().slice(0, 300);
  console.log(`- ${msg} — ${c.url}`);
};

const groups = {};

const categorize = (msg) => {
  // 1. Try to extract standard llama.cpp commit prefix (e.g., "cuda:", "server :", "[SYCL] ")
  const prefixMatch = msg.match(/^(\[[\w-]+\]|[\w-]+)\s*[:\-]\s*/i);
  if (prefixMatch) {
    let cat = prefixMatch[1].replace(/[\[\]]/g, '').trim();
    const normalized = cat.toLowerCase();
    if (normalized === 'spec') return 'Speculative';
    if (normalized === 'quantize') return 'Quantization';
    return cat.toUpperCase();
  }

  // 2. Fallback to keyword matching for commits without a prefix
  const lmsg = msg.toLowerCase();
  if (/cuda|pdl|ggml_cuda|cublas|nv/.test(lmsg)) return 'CUDA';
  if (/sycl|level zero|intel arc|ggml_sycl/.test(lmsg)) return 'SYCL';
  if (/vulkan|spirv|vk_|ggml_vk|webgpu/.test(lmsg)) return 'Vulkan';
  if (/metal/.test(lmsg)) return 'Metal';
  if (/opencl|adreno|qualcomm|flash_attn/.test(lmsg)) return 'OpenCL';
  if (/hexagon|hmx|snapdragon/.test(lmsg)) return 'Hexagon';
  if (/quantiz|q8_|q6_|q5_|q4_|q_type|ggml-zendnn/.test(lmsg)) return 'Quantization';
  if (/mtp|speculat|draft|sampling|backend sampling|top_k/.test(lmsg)) return 'Speculative';
  if (/server|vram|slots|\/slots|sleep/.test(lmsg)) return 'Server';
  if (/bench|batched-bench|fit-params|perplexity|quantize|tools|ui:|webui/.test(lmsg)) return 'Tools';
  if (/app :|unified executable|llama unified/.test(lmsg)) return 'App';
  return 'Other';
};

for (const commit of matched) {
  const cat = categorize(commit.message);
  if (!groups[cat]) groups[cat] = [];
  groups[cat].push(commit);
}

// Sort categories: known backends first, then alphabetical, then Other last
const knownBackends = ['CUDA', 'SYCL', 'Vulkan', 'Metal', 'OpenCL', 'Hexagon', 'Quantization', 'Speculative', 'Server', 'Tools', 'App', 'UI', 'GGML', 'MTMD', 'Fit', 'Docker', 'Vendor', 'CI'];
const sortedKeys = Object.keys(groups).sort((a, b) => {
  const aIdx = knownBackends.indexOf(a);
  const bIdx = knownBackends.indexOf(b);
  if (a === 'Other') return 1;
  if (b === 'Other') return -1;
  if (aIdx !== -1 && bIdx !== -1) return aIdx - bIdx;
  if (aIdx !== -1) return -1;
  if (bIdx !== -1) return 1;
  return a.localeCompare(b);
});

console.log('\nPerformance-related commits since ' + REPO + ':' + TAG + ' -> ' + TARGET);
console.log('(prioritized by your swap-settings if provided)');

if (BRIEF) {
  for (const c of [...priorityMatched, ...matched]) printEntry(c);
} else {
  if (priorityMatched.length > 0) {
    console.log('\n== High relevance to your configuration ==');
    for (const c of priorityMatched) printEntry(c);
    console.log();
  }
  
  for (const area of sortedKeys) {
    if (groups[area].length > 0) {
      console.log('== ' + area + ' ==');
      for (const c of groups[area]) printEntry(c);
      console.log();
    }
  }
}

process.stderr.write('Total commits scanned: ' + totalCommits + '\n');
process.exit(0);
