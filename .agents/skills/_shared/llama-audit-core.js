'use strict';

/**
 * llama-audit-core — shared logic for performance-audit skills.
 *
 * Extracted from the original llama-performance-audit skill so that both the
 * Nix-config-based auditor and the Windows-manifest-based auditor can reuse
 * the same GitHub comparison, swap-settings parsing, commit filtering, and
 * output formatting without duplication.
 *
 * Each caller is responsible for:
 *   - parsing its own CLI arguments
 *   - extracting the "base" tag from its source (Nix config or Windows manifest)
 *
 * then calling audit({ repo, tag, target?, swapSettings?, brief? }).
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// ── Constants ──────────────────────────────────────────────────────────

const BASE_KEYWORDS =
  '(perf|performance|speed|optimi|tune|throughput|latency|cuda|pdl|' +
  'flash-attn|flash|vulkan|metal|opencl|sycl|hexagon|adreno|rdna|bf16|fp16|' +
  'quantiz|moe|mtp|speculat|draft|sampling|d2h|gpu|server|bench|' +
  'batched-bench|fit-params|ggml-cuda|ggml-zendnn|pdl)';

const STOPWORDS = new Set([
  'on', 'off', 'the', 'and', 'for', 'with',
  'from', 'into', 'not', 'yes', 'no',
]);

const KNOWN_BACKENDS = [
  'CUDA', 'SYCL', 'Vulkan', 'Metal', 'OpenCL', 'Hexagon',
  'Quantization', 'Speculative', 'Server', 'Tools',
  'App', 'UI', 'GGML', 'MTMD', 'Fit',
  'Docker', 'Vendor', 'CI',
];

// ── Helpers ────────────────────────────────────────────────────────────

/**
 * Resolve a project path, handling the `@`-prefix convention.
 *
 * Paths starting with `@` are relative to the project root (process.cwd()),
 * a convention used throughout the pi agent tooling.  This lets callers
 * write `@modules/llama-swap-settings.nix` and have it resolve correctly
 * when the script is invoked from the repo root.
 *
 * Paths without an `@` prefix are returned as-is so that Node can resolve
 * them against cwd in the usual way.
 */
function resolveProjectPath(p) {
  if (!p) return p;
  if (p.startsWith('@')) {
    return path.join(process.cwd(), p.slice(1));
  }
  return p;
}

function runGh(argsStr) {
  try {
    return execSync(`gh ${argsStr}`, {
      encoding: 'utf8',
      maxBuffer: 10 * 1024 * 1024,
    });
  } catch (e) {
    process.stderr.write(`gh command failed: ${e.message}\n`);
    process.exit(2);
  }
}

/**
 * Decide whether a cleaned-up token is worth keeping as a priority term.
 *
 * Filters out file paths, Nix interpolation fragments, and pure numbers —
 * these would otherwise flood the term list with noise from model paths.
 */
function isKeepableTerm(term) {
  if (STOPWORDS.has(term)) return false;
  if (term.includes('/') || term.includes('\\')) return false;  // file paths
  if (term.includes('$')) return false;                          // Nix \${...}
  if (/^\d+(\.\d+)?$/.test(term)) return false;                  // pure numbers
  return true;
}

/**
 * Extract priority terms from an arbitrary text blob containing llama.cpp
 * command-line flags.
 *
 * Returns flag names (without the leading dashes), flag values that look
 * meaningful (e.g. `cuda0`, `on`), and quantization-type patterns
 * (e.g. `q4_k_m`, `ud-q5_0`).
 *
 * This is a pure function — it operates on a string, not a file, so callers
 * can feed it the contents of a Nix module, a YAML `cmd:` block, or anything
 * else.
 */
function extractFlagsFromString(text) {
  const terms = [];

  // 1. Long flags: --flag value  (or --flag=value)
  for (const m of text.matchAll(/--[a-zA-Z0-9_-]+(?:\s+[^"'\s]+)?/g)) {
    for (const word of m[0].trim().split(/\s+/)) {
      const clean = word.replace(/^-+/, '').toLowerCase();
      if (clean.length >= 3 && isKeepableTerm(clean)) terms.push(clean);
    }
  }

  // 2. Short flags: -flag  (must be preceded by whitespace / start-of-line
  //    so we don't match hyphens inside model paths like bge-m3-Q8_0-GGUF)
  for (const m of text.matchAll(/(?:^|\s)(-[a-zA-Z0-9_-]+)/g)) {
    const clean = m[1].replace(/^-+/, '').toLowerCase();
    if (clean.length >= 2 && isKeepableTerm(clean)) terms.push(clean);
  }

  // 3. Quantization patterns  Q4_K_M, UD-Q5_0, etc.
  for (const m of text.matchAll(/Q\d+_[A-Z0-9_]+|UD-Q\d+_[A-Z0-9_]+/gi)) {
    terms.push(m[0].toLowerCase());
  }

  return [...new Set(terms)];
}

/**
 * Read a swap-settings file (Nix module) and return priority terms.
 *
 * The entire file content is scanned for llama.cpp flag patterns.  For
 * YAML configs produced by the Windows llama-swap install, use
 * `extractPriorityTermsFromYaml` instead so only `cmd:` blocks are parsed.
 */
function extractPriorityTerms(swapSettingsPath) {
  const resolved = resolveProjectPath(swapSettingsPath);
  if (!resolved || !fs.existsSync(resolved)) return [];
  const content = fs.readFileSync(resolved, 'utf8').slice(0, 40000);
  return extractFlagsFromString(content);
}

/**
 * Read a Windows llama-swap YAML config and return priority terms.
 *
 * Unlike `extractPriorityTerms` (which scans the entire file), this extracts
 * only the `cmd:` continuation lines — those starting with `--` after
 * optional whitespace — so YAML comments and structure don't produce noise.
 *
 * Expected file: `~/winhome/scoop/persist/llama-swap/config.yaml`
 */
function extractPriorityTermsFromYaml(yamlPath) {
  const resolved = resolveProjectPath(yamlPath);
  if (!resolved || !fs.existsSync(resolved)) return [];
  const content = fs.readFileSync(resolved, 'utf8');

  const cmdText = content
    .split('\n')
    .filter((line) => line.trimStart().startsWith('--'))
    .join('\n');

  return extractFlagsFromString(cmdText);
}

/**
 * Resolve the latest published release tag from GitHub.
 *
 * We fetch the *most recently published* release (including prereleases)
 * rather than GitHub's "releases/latest" endpoint.  That endpoint skips
 * prereleases, which is wrong for projects like llama.cpp whose b<N> build
 * tags are marked as prereleases.
 */
function resolveLatestRelease(repo) {
  const resp = runGh(
    `api -H "Accept: application/vnd.github+json" "repos/${repo}/releases?per_page=10"`,
  );
  const releases = JSON.parse(resp);
  if (!Array.isArray(releases) || releases.length === 0) {
    throw new Error('No releases returned');
  }
  releases.sort(
    (a, b) => new Date(b.published_at) - new Date(a.published_at),
  );
  return releases[0].tag_name || 'master';
}

/**
 * Fetch all commits between two tags (base → target) using the GitHub
 * compare API with automatic pagination.
 */
function fetchCommits(repo, baseTag, targetTag) {
  const all = [];
  let page = 1;
  let totalPages = 1;
  let totalCommits = 0;

  while (page <= totalPages) {
    const respStr = runGh(
      `api -H "Accept: application/vnd.github+json" ` +
      `"repos/${repo}/compare/${baseTag}...${targetTag}?per_page=30&page=${page}"`,
    );
    const resp = JSON.parse(respStr);

    if (page === 1) {
      totalCommits = resp.total_commits || 0;
      if (totalCommits === 0) {
        process.stderr.write(
          `gh compare failed or no commits found. Ensure the repo and tag exist ` +
          `and you have gh auth set up.\n`,
        );
        process.exit(3);
      }
      totalPages = Math.ceil(totalCommits / 30);
      if (totalPages > 1)
        process.stderr.write(
          `Found ${totalCommits} commits across ${totalPages} pages, fetching...\n`,
        );
    }

    if (resp.commits) {
      for (const c of resp.commits) {
        all.push({
          sha: c.sha,
          message: c.commit.message.replace(/\n/g, ' '),
          url: c.html_url,
        });
      }
    }
    page++;
  }

  return { commits: all, totalCommits };
}

/**
 * Categorize a commit message into a backend/area label.
 */
function categorize(msg) {
  // 1. Try standard llama.cpp commit prefix, e.g. "cuda:", "server :", "[SYCL] "
  const prefixMatch = msg.match(/^(\[[\w-]+\]|[\w-]+)\s*[:\-]\s*/i);
  if (prefixMatch) {
    let cat = prefixMatch[1].replace(/[\[\]]/g, '').trim();
    const normalized = cat.toLowerCase();
    if (normalized === 'spec') return 'Speculative';
    if (normalized === 'quantize') return 'Quantization';
    return cat.toUpperCase();
  }

  // 2. Fallback keyword matching for commits without a prefix
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
  if (/app\s*:|unified executable|llama unified/.test(lmsg)) return 'App';
  return 'Other';
}

/**
 * Build the keyword + priority-regex pair from a priority-terms array.
 */
function buildRegexes(priorityTerms) {
  const priorityRegexStr =
    priorityTerms.length > 0
      ? `(${priorityTerms.join('|')})`
      : '';
  const keywordsRegex = new RegExp(
    `${BASE_KEYWORDS}${priorityRegexStr ? '|' + priorityRegexStr : ''}`,
    'i',
  );

  const priorityMatchRegex =
    priorityTerms.length > 0
      ? new RegExp(
          `\\b(${priorityTerms
            .map((t) => t.replace(/[-_]/g, '[-_ ]'))
            .join('|')})\\b`,
          'i',
        )
      : null;

  return { keywordsRegex, priorityMatchRegex };
}

/**
 * Filter and categorize an array of commits.
 *
 * @param {Array<{sha:string,message:string,url:string}>} commits
 * @param {string[]} priorityTerms
 * @returns {{ priorityMatched: Array, matched: Array, groups: Object }}
 */
function filterAndCategorize(commits, priorityTerms) {
  const { keywordsRegex, priorityMatchRegex } = buildRegexes(priorityTerms);

  const matched = [];
  const priorityMatched = [];

  for (const commit of commits) {
    if (keywordsRegex.test(commit.message)) {
      const isPriority = priorityMatchRegex
        ? priorityMatchRegex.test(commit.message)
        : false;
      if (isPriority) priorityMatched.push(commit);
      else matched.push(commit);
    }
  }

  const groups = {};
  for (const commit of matched) {
    const cat = categorize(commit.message);
    if (!groups[cat]) groups[cat] = [];
    groups[cat].push(commit);
  }

  return { priorityMatched, matched, groups };
}

// ── Output ─────────────────────────────────────────────────────────────

function printEntry(c, brief) {
  let msg = c.message.replace(/\s+/g, ' ').trim();
  if (brief) {
    msg = msg.slice(0, 200);
  } else {
    msg = msg.replace(/\s*\(.*?\)\s*/g, '').slice(0, 300);
  }
  console.log(`- ${msg} — ${c.url}`);
}

function sortGroupKeys(groups) {
  return Object.keys(groups).sort((a, b) => {
    if (a === 'Other') return 1;
    if (b === 'Other') return -1;
    const aIdx = KNOWN_BACKENDS.indexOf(a);
    const bIdx = KNOWN_BACKENDS.indexOf(b);
    if (aIdx !== -1 && bIdx !== -1) return aIdx - bIdx;
    if (aIdx !== -1) return -1;
    if (bIdx !== -1) return 1;
    return a.localeCompare(b);
  });
}

function formatReport(tag, target, repo, result, totalCommits, brief, priorityTerms) {
  const { priorityMatched, matched, groups } = result;
  const totalMatched = matched.length + priorityMatched.length;

  if (totalMatched === 0) {
    process.stderr.write(
      'No performance-related commits detected in the diff (by keyword).\n',
    );
    console.log(
      `You can inspect the full commit list at: https://github.com/${repo}/compare/${tag}...${target}`,
    );
    return;
  }

  console.log(
    `\nPerformance-related commits since ${repo}:${tag} -> ${target}`,
  );
  const note = priorityTerms.length > 0
    ? '(prioritized by your swap-settings)'
    : '(no swap-settings provided for prioritization)';
  console.log(note);

  if (brief) {
    for (const c of [...priorityMatched, ...matched]) printEntry(c, true);
  } else {
    if (priorityMatched.length > 0) {
      console.log('\n== High relevance to your configuration ==');
      for (const c of priorityMatched) printEntry(c, false);
      console.log();
    }

    const sortedKeys = sortGroupKeys(groups);
    for (const area of sortedKeys) {
      if (groups[area].length > 0) {
        console.log(`== ${area} ==`);
        for (const c of groups[area]) printEntry(c, false);
        console.log();
      }
    }
  }

  process.stderr.write(`Total commits scanned: ${totalCommits}\n`);
}

// ── Public API ─────────────────────────────────────────────────────────

/**
 * Run the full audit pipeline:
 *
 *   1. (optional) resolve latest release as the target
 *   2. fetch commits between base tag and target
 *   3. extract priority terms from swap-settings (or use caller-supplied terms)
 *   4. filter + categorize
 *   5. print the report
 *
 * @param {Object} opts
 * @param {string} opts.repo    - GitHub owner/repo
 * @param {string} opts.tag     - base tag (e.g. "b11429")
 * @param {string} [opts.target]    - comparison target; omitted = latest release
 *   (fetched via GitHub API incl. prereleases), "master", or an explicit tag
 * @param {string} [opts.swapSettings]    - path to a swap-settings file.
 *   The format is auto-detected by extension: `.nix` uses full-file scanning,
 *   `.yaml`/`.yml` uses `extractPriorityTermsFromYaml`.
 * @param {string[]} [opts.priorityTerms] - pre-extracted priority terms.
 *   When provided, takes precedence over `swapSettings` so callers can
 *   choose their extraction strategy (Strategy pattern).
 * @param {boolean} [opts.brief] - condensed one-line output
 */
function audit(opts) {
  const { repo, tag, target, swapSettings, priorityTerms: explicitTerms, brief } = opts;

  let resolvedTarget = target;
  if (!resolvedTarget) {
    try {
      resolvedTarget = resolveLatestRelease(repo);
      process.stderr.write(`Latest release: ${resolvedTarget}\n`);
    } catch (e) {
      process.stderr.write(
        `Could not fetch latest release; defaulting to master\n`,
      );
      resolvedTarget = 'master';
    }
  }

  process.stderr.write(`Comparing ${repo}:${tag} -> ${resolvedTarget}...\n`);

  const { commits, totalCommits } = fetchCommits(repo, tag, resolvedTarget);

  let priorityTerms;
  if (explicitTerms && explicitTerms.length > 0) {
    priorityTerms = explicitTerms;
  } else {
    priorityTerms = extractPriorityTerms(swapSettings);
  }

  const result = filterAndCategorize(commits, priorityTerms);
  formatReport(tag, resolvedTarget, repo, result, totalCommits, brief, priorityTerms);
}

module.exports = {
  audit,
  extractFlagsFromString,
  extractPriorityTerms,
  extractPriorityTermsFromYaml,
  isKeepableTerm,
  resolveProjectPath,
  resolveLatestRelease,
  fetchCommits,
  filterAndCategorize,
  categorize,
  buildRegexes,
  formatReport,
  printEntry,
  sortGroupKeys,
  runGh,
};
