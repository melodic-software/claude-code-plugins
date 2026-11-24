#!/usr/bin/env node
// context-budget measurement engine.
//
// Measures a Claude Code session's fixed startup context payload on THIS
// machine, at a pinned binary, and attributes the un-itemized built-in tool
// pools per tool by A/B differencing. Ships no token values of its own: every
// number it reports was measured by the run that reports it.
//
// Modes, in fixed preference order (the degradation ladder):
//   sdk        Agent SDK getContextUsage() — exact integers. Requires
//              @anthropic-ai/claude-agent-sdk to be resolvable (see --sdk-dir).
//   cli-parse  `<binary> -p "/context"` markdown, parsed version-aware, with
//              display-rounded values. Headless /context is undocumented as a
//              -p-capable command, so this mode depends on unsanctioned
//              behavior. The record says so in `caveats`.
//   (neither)  a structured error naming the remediation, never a wrong
//              number.
//
// Subcommands:
//   snapshot          one measured snapshot (optionally under --deny);
//                     --measure-only: sdk mode only, stdout only, no file written
//   attribute         baseline + one deny run per tool -> ranked per-tool deltas
//   compare           offline: two snapshot files -> one ledger row
//   ledger            append a row / list rows under a caller-derived data dir
//   parse-context     offline: parse a captured /context markdown file
//   verify-catalogue  grep the stamped binary for each catalogue key/env name
//
// Exit codes: 0 success; 2 usage error; 3 measurement unavailable or
// unparsable (the degradation path — stdout carries a context-budget.error/1
// record with a remediation); 4 `snapshot --measure-only` found the Agent SDK
// absent (no cli-parse fallback, no install offer).

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  appendFileSync, existsSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync,
} from 'node:fs';
import { createRequire } from 'node:module';
import { delimiter, dirname, isAbsolute, join, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SNAPSHOT_SCHEMA = 'context-budget.snapshot/1';
const ATTRIBUTION_SCHEMA = 'context-budget.attribution/1';
const LEDGER_SCHEMA = 'context-budget.ledger/1';
const ERROR_SCHEMA = 'context-budget.error/1';
const CATALOGUE_SCHEMA = 'context-budget.levers/1';
const CATALOGUE_VERIFY_SCHEMA = 'context-budget.catalogue-verify/1';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CATALOGUE = join(SCRIPT_DIR, '..', 'reference', 'levers.json');
const INTERACTIVE_ONLY_LISTING = join(SCRIPT_DIR, '..', 'reference', 'interactive-only-tools.json');
const INTERACTIVE_ONLY_SCHEMA = 'context-budget.interactive-only/1';

const ENV_TOKEN_RE = /\b(?:CLAUDE_CODE|ENABLE|DISABLE)_[A-Z0-9_]+\b/g;

function extractCamelKeys(text) {
  const out = [];
  const s = String(text);
  let i = 0;
  while (i < s.length) {
    const c = s.charCodeAt(i);
    if (c >= 97 && c <= 122) {
      const start = i;
      i += 1;
      let sawUpper = false;
      while (i < s.length) {
        const k = s.charCodeAt(i);
        const isLower = k >= 97 && k <= 122;
        const isUpper = k >= 65 && k <= 90;
        const isDigit = k >= 48 && k <= 57;
        if (!isLower && !isUpper && !isDigit) break;
        if (isUpper) sawUpper = true;
        i += 1;
      }
      if (sawUpper) out.push(s.slice(start, i));
      continue;
    }
    i += 1;
  }
  return out;
}

const SPAWN_TIMEOUT_MS = 180000;

const SYSTEM_TOOL_BUCKETS = ['System tools', 'System tools (deferred)'];
const [PREFIX_BUCKET, DEFERRED_BUCKET] = SYSTEM_TOOL_BUCKETS;

function usageError(msg) {
  process.stderr.write(`ERROR: ${msg}\n`);
  process.stderr.write('Run with --help for usage.\n');
  process.exit(2);
}

function degrade(error, detail, remediation, code = 3) {
  process.stdout.write(`${JSON.stringify({ schema: ERROR_SCHEMA, error, detail, remediation }, null, 2)}\n`);
  process.exit(code);
}

const EXIT_SDK_ABSENT = 4;

function nowUtc() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function sha12(text) {
  return createHash('sha256').update(text).digest('hex').slice(0, 12);
}

const FLAG_ONLY = ['help', 'verify-additivity', 'list', 'find-unstored', 'measure-only'];

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      args._.push(a);
      continue;
    }
    const key = a.slice(2);
    if (FLAG_ONLY.includes(key)) {
      args[key] = true;
      continue;
    }
    if (i + 1 >= argv.length) usageError(`--${key} needs a value`);
    args[key] = argv[++i];
  }
  return args;
}

const HELP = `context-budget measurement engine

Usage:
  measure.mjs snapshot [--deny <T1,T2>] [--binary <path>] [--sdk-dir <dir>]
                       [--label <text>] [--out <file>]
  measure.mjs snapshot --measure-only [--binary <path>] [--sdk-dir <dir>]
                       (sdk mode only; stdout only, no file; takes no --out/--deny/--label)
  measure.mjs attribute --tools <T1,T2,...|from-baseline> [--binary <path>]
                       [--sdk-dir <dir>] [--verify-additivity]
                       [--operator-deny <T1,T2>] [--out <file>]
  measure.mjs compare --before <file> --after <file> [--lever <name>]
                       [--emitted-config <text>]
  measure.mjs ledger (--append <row-file>|--list) --dir <data-dir>
  measure.mjs parse-context --file <captured-context.md>
  measure.mjs verify-catalogue [--binary <path>] [--catalogue <file>]
                       [--find-unstored] [--out <file>]

Exit: 0 success; 2 usage error; 3 measurement unavailable/unparsable
      (stdout then carries a ${ERROR_SCHEMA} record with a remediation);
      4 --measure-only and the Agent SDK is absent (same record, no fallback).
`;

function resolveBinary(explicit) {
  if (explicit) {
    if (!existsSync(explicit)) {
      degrade('binary-not-found', `--binary path does not exist: ${explicit}`,
        'Pass --binary with the path of the Claude Code executable to measure.');
    }
    return realpathSync(explicit);
  }
  const exts = process.platform === 'win32' ? ['.exe', '.cmd', ''] : [''];
  for (const dir of (process.env.PATH || '').split(delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = join(dir, `claude${ext}`);
      try {
        if (existsSync(candidate) && statSync(candidate).isFile()) return realpathSync(candidate);
      } catch { /* unreadable PATH entry — keep looking */ }
    }
  }
  return null;
}

function spawnBinary(bin, args, opts) {
  const needsShell = process.platform === 'win32' && /\.(cmd|bat)$/i.test(bin);
  return spawnSync(bin, args, { ...opts, ...(needsShell ? { shell: true } : {}) });
}

function binaryVersion(bin) {
  const r = spawnBinary(bin, ['--version'], { encoding: 'utf8', timeout: 30000 });
  const m = ((r.stdout || '') + (r.stderr || '')).match(/(\d+\.\d+\.\d+)/);
  return m ? m[1] : null;
}

function findSdkEntry(dirs) {
  for (const dir of dirs) {
    if (!dir) continue;
    try {
      const req = createRequire(join(resolve(dir), 'resolve-anchor.js'));
      const entry = req.resolve('@anthropic-ai/claude-agent-sdk');
      return { entry, anchor: resolve(dir) };
    } catch { /* not resolvable from this anchor — next rung */ }
  }
  return null;
}

function sdkVersionFromEntry(entry) {
  // The package's exports map hides package.json from resolve(); walk up from
  // the resolved entry file to the package directory instead.
  let dir = dirname(entry);
  const marker = `${sep}@anthropic-ai${sep}claude-agent-sdk`;
  while (dir.includes(marker) && !existsSync(join(dir, 'package.json'))) dir = dirname(dir);
  try {
    return JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')).version ?? null;
  } catch {
    return null;
  }
}


class ParseError extends Error {}

function parseTokenCell(cell) {
  const t = cell.trim();
  let m = t.match(/^~?\s*([\d.]+)k$/i);
  if (m) return { tokens: Math.round(parseFloat(m[1]) * 1000), rounded: true };
  m = t.match(/^[~<]\s*(\d+)$/);
  if (m) return { tokens: parseInt(m[1], 10), rounded: true };
  m = t.match(/^(\d+)$/);
  if (m) return { tokens: parseInt(m[1], 10), rounded: false };
  throw new ParseError(`unrecognized token cell: ${JSON.stringify(cell)}`);
}

function tableRows(lines, startIdx) {
  const rows = [];
  for (let i = startIdx + 2; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line.startsWith('|')) break;
    const cells = line.split('|').slice(1, -1).map((c) => c.trim());
    rows.push(cells);
  }
  return rows;
}

function findSection(lines, heading) {
  const at = lines.findIndex((l) => l.trim().toLowerCase() === heading.toLowerCase());
  if (at < 0) return null;
  for (let i = at + 1; i < lines.length; i++) {
    if (lines[i].trim().startsWith('|')) return i;
    if (lines[i].trim().startsWith('#')) break;
  }
  return null;
}

function absentRowPhrase(bucket) {
  return `"${bucket}" row absent`;
}

function parseContextMarkdown(text, { binaryVersion: version = null } = {}) {
  const firstHeading = text.search(/^#/m);
  if (firstHeading < 0) throw new ParseError('no markdown heading found in output');
  const lines = text.slice(firstHeading).split(/\r?\n/);

  const catTable = findSection(lines, '### Estimated usage by category');
  if (catTable === null) {
    throw new ParseError('category table ("### Estimated usage by category") not found — '
      + 'the /context output format has no stability guarantee and appears to have changed');
  }

  const categories = {};
  let anyRounded = false;
  for (const cells of tableRows(lines, catTable)) {
    if (cells.length < 2) throw new ParseError(`malformed category row: ${JSON.stringify(cells)}`);
    const { tokens, rounded } = parseTokenCell(cells[1]);
    categories[cells[0]] = tokens;
    anyRounded = anyRounded || rounded;
  }
  const missingBuckets = SYSTEM_TOOL_BUCKETS.filter((b) => !(b in categories));
  if (missingBuckets.length === SYSTEM_TOOL_BUCKETS.length) {
    throw new ParseError('category table parsed but carries neither a "System tools" nor a '
      + '"System tools (deferred)" row; refusing to guess');
  }
  const absenceCaveats = missingBuckets.map((b) => `cli-parse: ${absentRowPhrase(b)}`
    + `${version ? ` at ${version}` : ''}; recorded as unmeasured, not zero`);

  const model = (text.match(/\*\*Model:\*\*\s*(\S+)/) || [])[1] ?? null;

  const skillRows = [];
  const skillsTable = findSection(lines, '### Skills');
  if (skillsTable !== null) {
    for (const cells of tableRows(lines, skillsTable)) {
      if (cells.length >= 3) skillRows.push({ name: cells[0], source: cells[1] });
    }
  }

  const agents = [];
  const agentsTable = findSection(lines, '### Custom Agents');
  if (agentsTable !== null) {
    for (const cells of tableRows(lines, agentsTable)) {
      if (cells.length >= 3) {
        let tokens = null;
        try { tokens = parseTokenCell(cells[2]).tokens; } catch { /* keep null */ }
        agents.push({ agentType: cells[0], source: cells[1], tokens });
      }
    }
  }

  const caveats = [...absenceCaveats];
  for (const line of lines) {
    const match = /^Caveat:\s+(.+)$/.exec(line);
    if (match) caveats.push(match[1].trim());
  }

  return {
    categories,
    model,
    skillRows,
    agents,
    precision: anyRounded ? 'display-rounded' : 'exact',
    caveats,
  };
}

function listingSignature(rows) {
  const canon = rows.map((r) => `${r.name} ${r.source}`).sort();
  return sha12(JSON.stringify(canon));
}

function skillFrontmatterRow(entry) {
  const row = { name: entry?.name ?? null, source: entry?.source ?? null };
  if (typeof entry?.tokens === 'number') row.tokens = entry.tokens;
  if (typeof entry?.pluginName === 'string' && entry.pluginName.length) row.pluginName = entry.pluginName;
  return row;
}

function collapsedSkillCount(total, included) {
  if (typeof total !== 'number' || typeof included !== 'number' || total < included) return null;
  return total - included;
}

function splitCsv(value) {
  if (!value) return [];
  return String(value).split(',').map((s) => s.trim()).filter(Boolean);
}

async function sdkSnapshot({ sdk, sdkVersion, sdkEntry, bin, deny, label }) {
  const { query } = sdk;
  const options = {
    maxTurns: 1,
    pathToClaudeCodeExecutable: bin,
    ...(deny.length ? { disallowedTools: deny } : {}),
  };
  const q = query({ prompt: '/context', options });

  const { init, usage } = await new Promise((resolvePromise, rejectPromise) => {
    const timer = setTimeout(() => {
      rejectPromise(new Error(`SDK session produced no init message within ${SPAWN_TIMEOUT_MS / 1000}s`));
      q.interrupt().catch(() => {});
    }, SPAWN_TIMEOUT_MS);
    (async () => {
      for await (const msg of q) {
        if (msg.type === 'system' && msg.subtype === 'init') {
          const usage = await q.getContextUsage();
          clearTimeout(timer);
          resolvePromise({ init: msg, usage });
          try { await q.interrupt(); } catch { /* session may have ended */ }
          break;
        }
      }
    })().catch((e) => { clearTimeout(timer); rejectPromise(e); });
  });

  const categories = {};
  for (const c of usage.categories ?? []) categories[c.name] = c.tokens;
  const caveats = [];
  const synthesizedZeroBuckets = [];
  for (const bucket of SYSTEM_TOOL_BUCKETS) {
    if (!(bucket in categories)) {
      categories[bucket] = 0;
      synthesizedZeroBuckets.push(bucket);
      caveats.push(
        `sdk omitted "${bucket}"; recorded as measured 0 (sdk category vocabulary is known; numbers are exact)`,
      );
    }
  }

  const skillFrontmatter = usage.skills?.skillFrontmatter ?? [];
  const skillRows = skillFrontmatter.map(skillFrontmatterRow);
  const totalSkills = usage.skills?.totalSkills ?? null;
  const includedSkills = usage.skills?.includedSkills ?? null;

  return {
    schema: SNAPSHOT_SCHEMA,
    timestampUtc: nowUtc(),
    mode: 'sdk',
    precision: 'exact',
    sessionKind: 'headless',
    label: label ?? null,
    binary: { path: bin, version: init.claude_code_version ?? null },
    sdk: { version: sdkVersion, entry: sdkEntry },
    model: usage.model ?? init.model ?? null,
    cwd: process.cwd(),
    deny,
    categories,
    synthesizedZeroBuckets,
    totalTokens: usage.totalTokens ?? null,
    maxTokens: usage.maxTokens ?? null,
    tools: init.tools ?? [],
    agents: usage.agents ?? [],
    mcpTools: usage.mcpTools ?? [],
    memoryFiles: usage.memoryFiles ?? [],
    slashCommands: usage.slashCommands ?? [],
    skillListing: {
      totalSkills,
      includedSkills,
      collapsedSkills: collapsedSkillCount(totalSkills, includedSkills),
      tokens: usage.skills?.tokens ?? categories.Skills ?? null,
      signature: listingSignature(skillRows),
      rows: skillRows.length,
      frontmatter: skillRows,
    },
    caveats,
  };
}

function cliSnapshot({ bin, deny, label }) {
  const args = ['-p', '/context'];
  if (deny.length) args.push('--disallowedTools', ...deny);
  const r = spawnBinary(bin, args, { encoding: 'utf8', input: '', timeout: SPAWN_TIMEOUT_MS });
  if (r.error || r.status !== 0 || !r.stdout) {
    throw new ParseError(`headless /context failed (exit ${r.status ?? 'spawn-error'}): `
      + `${(r.stderr || String(r.error || '')).trim().slice(0, 300)}`);
  }
  const version = binaryVersion(bin);
  const parsed = parseContextMarkdown(r.stdout, { binaryVersion: version });
  const synthesizedZeroBuckets = [];
  for (const match of r.stdout.matchAll(/<!--\s*synthesized-zero:\s*([^>]+?)\s*-->/g)) {
    const name = match[1].trim();
    if (name && !synthesizedZeroBuckets.includes(name)) synthesizedZeroBuckets.push(name);
  }
  const payloadTotal = Object.entries(parsed.categories)
    .filter(([name]) => !name.endsWith('(deferred)') && !['Free space', 'Autocompact buffer'].includes(name))
    .reduce((sum, [, v]) => sum + v, 0);
  return {
    schema: SNAPSHOT_SCHEMA,
    timestampUtc: nowUtc(),
    mode: 'cli-parse',
    precision: parsed.precision,
    sessionKind: 'headless',
    label: label ?? null,
    binary: { path: bin, version },
    sdk: null,
    model: parsed.model,
    cwd: process.cwd(),
    deny,
    categories: parsed.categories,
    synthesizedZeroBuckets,
    totalTokens: payloadTotal,
    maxTokens: null,
    tools: [],
    agents: parsed.agents,
    mcpTools: [],
    memoryFiles: [],
    slashCommands: [],
    skillListing: {
      totalSkills: null,
      includedSkills: null,
      collapsedSkills: null,
      tokens: parsed.categories.Skills ?? null,
      signature: listingSignature(parsed.skillRows),
      rows: parsed.skillRows.length,
      frontmatter: parsed.skillRows,
    },
    caveats: [
      'cli-parse mode: values are display-rounded, not exact integers',
      'headless /context is undocumented as a -p-capable command, so this rung depends on unsanctioned behavior',
      ...(parsed.caveats || []),
    ],
  };
}

const GIT_BASH_CONTEXT_HINT = '(from Git Bash run it as `MSYS_NO_PATHCONV=1 claude -p "/context"`, '
  + 'or path conversion rewrites the command).';

async function takeSnapshot(args) {
  const deny = splitCsv(args.deny);
  const bin = resolveBinary(args.binary);
  if (!bin) {
    degrade('no-binary', 'no `claude` executable found on PATH and no --binary given',
      'Install the Claude Code CLI, or pass --binary <path> naming the executable to measure.');
  }

  const sdkCandidates = [args['sdk-dir'], process.cwd()];
  const found = findSdkEntry(sdkCandidates);
  const triedSdkDirs = sdkCandidates.filter(Boolean).join(', ');
  const sdkRun = async () => sdkSnapshot({
    sdk: await import(pathToFileURL(found.entry).href),
    sdkVersion: sdkVersionFromEntry(found.entry),
    sdkEntry: found.entry,
    bin,
    deny,
    label: args.label,
  });
  if (args['measure-only']) {
    if (!found) {
      process.stderr.write('measure-only: @anthropic-ai/claude-agent-sdk is not installed; nothing was measured or installed.\n');
      degrade('sdk-absent',
        `@anthropic-ai/claude-agent-sdk is not resolvable (tried: ${triedSdkDirs})`,
        'Measure-only never installs the Agent SDK. Run /context-budget:audit once to set it up, or pass --sdk-dir '
        + 'naming a directory where it is installed.',
        EXIT_SDK_ABSENT);
    }
    try {
      return await sdkRun();
    } catch (e) {
      degrade('measurement-failed', `sdk mode failed: ${String(e).slice(0, 300)}`,
        'Verify the binary runs (`claude --version`); measure-only does not fall back to cli-parse.');
    }
  }
  if (found) {
    try {
      return await sdkRun();
    } catch (e) {
      try {
        const snap = cliSnapshot({ bin, deny, label: args.label });
        snap.caveats.push(`sdk mode failed and was degraded to cli-parse: ${String(e).slice(0, 200)}`);
        return snap;
      } catch (e2) {
        degrade('measurement-failed', `sdk mode failed (${String(e).slice(0, 200)}); `
          + `cli-parse fallback also failed (${String(e2).slice(0, 200)})`,
        'Verify the binary runs (`claude --version`) and that `claude -p "/context"` produces the category table '
        + GIT_BASH_CONTEXT_HINT);
      }
    }
  }
  try {
    return cliSnapshot({ bin, deny, label: args.label });
  } catch (e) {
    degrade('measurement-unavailable',
      `@anthropic-ai/claude-agent-sdk is not resolvable (tried: ${triedSdkDirs}) `
      + `and cli-parse failed: ${String(e).slice(0, 300)}`,
      'For exact measurement install the Agent SDK (npm install @anthropic-ai/claude-agent-sdk in a directory '
      + 'passed as --sdk-dir). For the fallback, verify `claude -p "/context"` prints the category table at your version '
      + GIT_BASH_CONTEXT_HINT);
  }
}

function summarize(snap) {
  return {
    timestampUtc: snap.timestampUtc,
    label: snap.label ?? null,
    deny: snap.deny ?? [],
    categories: snap.categories,
    totalTokens: snap.totalTokens,
    skillListing: {
      signature: snap.skillListing?.signature ?? null,
      tokens: snap.skillListing?.tokens ?? null,
      rows: snap.skillListing?.rows ?? null,
    },
  };
}

function compareSnapshots(before, after, { lever = null, emittedConfig = null } = {}) {
  const reasons = [];
  const modeMatch = before.mode === after.mode;
  const versionMatch = before.binary?.version === after.binary?.version;
  const pathMatch = before.binary?.path === after.binary?.path;
  if (!modeMatch) reasons.push(`mode differs (${before.mode} vs ${after.mode}) — deltas across modes mix precisions`);
  if (!versionMatch) reasons.push(`binary version differs (${before.binary?.version} vs ${after.binary?.version})`);
  if (!pathMatch) reasons.push(`binary path differs (${before.binary?.path} vs ${after.binary?.path})`);
  const sigMatch = before.skillListing?.signature === after.skillListing?.signature;
  const skillTokensMatch = before.skillListing?.tokens === after.skillListing?.tokens;
  if (!sigMatch) {
    reasons.push('skill listing differs between runs — `System tools` has listed skill-frontmatter tokens '
      + 'subtracted from it, so its delta is not attributable to tools');
  } else if (!skillTokensMatch) {
    reasons.push('skill listing matches but the Skills bucket moved — treat the System tools delta with caution');
  }

  const names = new Set([...Object.keys(before.categories || {}), ...Object.keys(after.categories || {})]);
  const delta = {};
  const unmeasured = {};
  for (const name of names) {
    const b = before.categories?.[name];
    const a = after.categories?.[name];
    if (typeof b === 'number' && typeof a === 'number') {
      delta[name] = a - b;
    } else {
      delta[name] = null;
      unmeasured[name] = `"${name}" present in only one run, so its delta is unmeasured, not zero`;
    }
  }
  const caveats = [...(before.caveats || []), ...(after.caveats || [])];
  if (!names.has(PREFIX_BUCKET)
    && caveats.some((c) => typeof c === 'string' && c.includes(absentRowPhrase(PREFIX_BUCKET)))) {
    unmeasured[PREFIX_BUCKET] = `"${PREFIX_BUCKET}" row absent from both runs' /context tables, so its delta is unmeasured, not zero`;
  }
  const totalDelta = (typeof before.totalTokens === 'number' && typeof after.totalTokens === 'number')
    ? after.totalTokens - before.totalTokens : null;

  const sharedOk = modeMatch && versionMatch && pathMatch;
  const listingOk = sigMatch && skillTokensMatch;
  return {
    schema: LEDGER_SCHEMA,
    timestampUtc: nowUtc(),
    lever,
    emittedConfig,
    mode: after.mode,
    precision: before.precision === 'exact' && after.precision === 'exact' ? 'exact' : 'display-rounded',
    binary: after.binary,
    before: summarize(before),
    after: summarize(after),
    delta,
    unmeasured,
    totalDelta,
    comparability: {
      ok: reasons.length === 0,
      systemToolsComparable: listingOk && sharedOk,
      modeBinaryComparable: sharedOk,
      reasons,
    },
  };
}

function systemBucketSaving(cmp) {
  const unmeasured = cmp.unmeasured || {};
  const vanished = SYSTEM_TOOL_BUCKETS.filter((b) => b in unmeasured
    || (b in cmp.delta && cmp.delta[b] === null));
  return {
    saved: vanished.length ? null : -SYSTEM_TOOL_BUCKETS.reduce((s, b) => s + (cmp.delta[b] ?? 0), 0),
    comparable: cmp.comparability.systemToolsComparable && !vanished.length,
    reasons: vanished.length
      ? [...cmp.comparability.reasons, ...vanished.map((b) => unmeasured[b] ?? vanishedReason(b))]
      : cmp.comparability.reasons,
  };
}

function vanishedReason(bucket) {
  return `${bucket} present in only one run — the bucket was emptied out of one `
    + 'snapshot, so its delta is unmeasured, not zero';
}

const BUCKET_ROW_FIELD = {
  [PREFIX_BUCKET]: 'prefixDelta',
  [DEFERRED_BUCKET]: 'deferredDelta',
};

const ADDITIVITY_EPSILON = 1;

function withinAdditivityEpsilon(combinedSaved, sumOfParts) {
  return Math.abs(combinedSaved - sumOfParts) <= ADDITIVITY_EPSILON;
}

function bucketAdditivity(rows, cmp, synthesized) {
  const perBucket = {};
  for (const bucket of SYSTEM_TOOL_BUCKETS) {
    if (!(bucket in cmp.delta)) continue;
    const parts = rows.map((r) => r[BUCKET_ROW_FIELD[bucket]]);
    const sumOfParts = parts.some((d) => typeof d !== 'number')
      ? null
      : -parts.reduce((sum, d) => sum + d, 0);
    const combinedDelta = cmp.delta[bucket];
    const combinedSaved = typeof combinedDelta === 'number' ? -combinedDelta : null;
    const runComparable = bucket === PREFIX_BUCKET
      ? cmp.comparability.systemToolsComparable
      : cmp.comparability.modeBinaryComparable;
    const saturated = synthesized.has(bucket);
    const measured = runComparable && sumOfParts !== null && combinedSaved !== null && !saturated;
    const reasons = [];
    if (saturated) {
      reasons.push(`${bucket} is a synthesized zero on the combined run (the SDK omitted the `
        + 'bucket and the engine filled 0), so additivity is not measurable');
    }
    if (!runComparable) {
      const gateReasons = bucket === PREFIX_BUCKET
        ? cmp.comparability.reasons
        : cmp.comparability.reasons.filter((r) => !r.startsWith('skill listing'));
      reasons.push(...gateReasons);
    }
    if (combinedSaved === null) reasons.push(vanishedReason(bucket));
    if (sumOfParts === null) {
      reasons.push(`${bucket} is unmeasured on at least one per-tool row, so the sum of parts `
        + 'for this bucket is unmeasured, not zero');
    }
    perBucket[bucket] = {
      sumOfParts,
      combinedSaved,
      additive: measured ? withinAdditivityEpsilon(combinedSaved, sumOfParts) : null,
      reasons,
    };
  }
  return perBucket;
}

function loadInteractiveOnly() {
  let data;
  try {
    data = JSON.parse(readFileSync(INTERACTIVE_ONLY_LISTING, 'utf8'));
  } catch (e) {
    usageError(`interactive-only listing unreadable: ${e.message}`);
  }
  if (data.schema !== INTERACTIVE_ONLY_SCHEMA) {
    usageError(`interactive-only listing expects ${INTERACTIVE_ONLY_SCHEMA}; got ${JSON.stringify(data.schema)}`);
  }
  return data;
}

function knownUncoveredRecord(candidates, listing, operatorDeny) {
  const seen = new Set(candidates);
  const denied = new Set(operatorDeny);
  const tools = [];
  const deniedAbsent = [];
  for (const tool of listing.tools || []) {
    if (seen.has(tool)) continue;
    if (denied.has(tool)) deniedAbsent.push(tool);
    else tools.push(tool);
  }
  return {
    reason: 'interactive-only — structurally unreachable from a headless candidate list',
    tools,
    deniedAbsent,
    notes: listing.notes || [],
  };
}

async function runAttribute(args) {
  if (!args.tools) usageError('attribute needs --tools <T1,T2,...|from-baseline>');
  const baseline = await takeSnapshot({ ...args, deny: undefined, label: 'baseline' });

  let tools;
  if (args.tools === 'from-baseline') {
    tools = baseline.tools;
    if (!tools.length) {
      degrade('no-tool-inventory', 'from-baseline needs the live tool list, which only sdk mode provides '
        + `(this run is ${baseline.mode})`,
      'Install the Agent SDK for tool enumeration, or pass --tools with an explicit comma-separated list.');
    }
  } else {
    tools = splitCsv(args.tools);
  }
  if (!tools.length) usageError('--tools resolved to an empty list');

  const measured = [baseline];
  const perTool = [];
  for (const tool of tools) {
    const run = await takeSnapshot({ ...args, deny: tool, label: `deny:${tool}` });
    measured.push(run);
    const cmp = compareSnapshots(baseline, run, { lever: `deny:${tool}` });
    const { saved, comparable, reasons } = systemBucketSaving(cmp);
    perTool.push({
      tool,
      prefixDelta: cmp.delta[PREFIX_BUCKET] ?? null,
      deferredDelta: cmp.delta[DEFERRED_BUCKET] ?? null,
      savedTokens: saved,
      comparable,
      reasons,
    });
  }
  perTool.sort((x, y) => (y.savedTokens ?? 0) - (x.savedTokens ?? 0));

  let additivity = null;
  if (args['verify-additivity']) {
    const savers = perTool.filter((t) => t.comparable && t.savedTokens > 0).map((t) => t.tool);
    if (savers.length >= 2) {
      const combined = await takeSnapshot({ ...args, deny: savers.join(','), label: 'deny:combined' });
      measured.push(combined);
      const cmp = compareSnapshots(baseline, combined, { lever: `deny:${savers.join('+')}` });
      const { saved: combinedSaved, comparable, reasons: savingReasons } = systemBucketSaving(cmp);
      const saverRows = perTool.filter((t) => savers.includes(t.tool));
      const sumOfParts = saverRows.reduce((s, t) => s + t.savedTokens, 0);
      const synthesized = new Set(combined.synthesizedZeroBuckets || []);
      const saturated = SYSTEM_TOOL_BUCKETS.some((bucket) => synthesized.has(bucket));
      const reasons = [...savingReasons];
      if (saturated) {
        reasons.push('a combined-run bucket is a synthesized zero, so the summed additivity '
          + 'verdict is not measurable');
      }
      additivity = {
        tools: savers,
        sumOfParts,
        combinedSaved,
        additive: comparable && !saturated && typeof combinedSaved === 'number'
          ? withinAdditivityEpsilon(combinedSaved, sumOfParts) : null,
        comparable: comparable && !saturated,
        perBucket: bucketAdditivity(saverRows, cmp, synthesized),
        reasons,
      };
    }
  }

  return {
    schema: ATTRIBUTION_SCHEMA,
    timestampUtc: nowUtc(),
    mode: baseline.mode,
    precision: baseline.precision,
    binary: baseline.binary,
    model: baseline.model,
    cwd: baseline.cwd,
    baseline: summarize(baseline),
    skillListingSignature: baseline.skillListing.signature,
    perTool,
    additivity,
    knownUncovered: knownUncoveredRecord(
      [...tools, ...(baseline.tools || [])],
      loadInteractiveOnly(),
      splitCsv(args['operator-deny']),
    ),
    caveats: mergeCaveats(measured),
  };
}

function mergeCaveats(snapshots) {
  const seen = new Set();
  const merged = [];
  for (const snap of snapshots) {
    const list = Array.isArray(snap?.caveats) ? snap.caveats : [];
    for (const caveat of list) {
      if (typeof caveat !== 'string' || caveat.length === 0 || seen.has(caveat)) continue;
      seen.add(caveat);
      merged.push(caveat);
    }
  }
  return merged;
}

function ledgerAppend(dir, rowFile) {
  let row;
  try {
    row = JSON.parse(readFileSync(rowFile, 'utf8'));
  } catch (e) {
    usageError(`--append file is not readable JSON: ${e.message}`);
  }
  if (row.schema !== LEDGER_SCHEMA) {
    usageError(`--append expects a ${LEDGER_SCHEMA} row (from \`compare\`); got schema ${JSON.stringify(row.schema)}`);
  }
  const slug = String(row.lever ?? 'compare').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'compare';
  const base = `${(row.timestampUtc || nowUtc()).replace(/[:-]/g, '')}-${slug}`;
  const runsDir = join(dir, 'runs');
  mkdirSync(runsDir, { recursive: true });
  let runId = base;
  let runPath = join(runsDir, `${runId}.json`);
  for (let n = 2; existsSync(runPath); n++) {
    runId = `${base}-${n}`;
    runPath = join(runsDir, `${runId}.json`);
  }
  writeFileSync(runPath, `${JSON.stringify(row, null, 2)}\n`);
  appendFileSync(join(dir, 'ledger.jsonl'), `${JSON.stringify({ runId, ...row })}\n`);
  process.stdout.write(`${JSON.stringify({ appended: true, runId, runPath, ledger: join(dir, 'ledger.jsonl') }, null, 2)}\n`);
}

function ledgerList(dir) {
  const path = join(dir, 'ledger.jsonl');
  if (!existsSync(path)) {
    process.stdout.write(`${JSON.stringify({ rows: [], note: `no ledger at ${path} — nothing measured for this project yet` }, null, 2)}\n`);
    return;
  }
  const rows = readFileSync(path, 'utf8').split('\n').filter(Boolean).map((l) => {
    try { return JSON.parse(l); } catch { return { unparsableLine: l.slice(0, 120) }; }
  });
  process.stdout.write(`${JSON.stringify({ rows }, null, 2)}\n`);
}


function catalogueTokens(lever) {
  if (Array.isArray(lever.binaryTokens) && lever.binaryTokens.length) {
    return [...new Set(lever.binaryTokens.filter((t) => typeof t === 'string' && t.length))];
  }
  const tokens = new Set();
  const texts = [lever.title, lever.mechanism, lever.emittedConfig, lever.scope, lever.detection]
    .filter((t) => typeof t === 'string')
    .join('\n');
  for (const m of texts.matchAll(ENV_TOKEN_RE)) tokens.add(m[0]);
  for (const key of extractCamelKeys(texts)) tokens.add(key);
  if (typeof lever.emittedConfig === 'string') {
    try {
      const obj = JSON.parse(lever.emittedConfig);
      if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
        for (const k of Object.keys(obj)) {
          if (extractCamelKeys(k).includes(k)) tokens.add(k);
        }
      }
    } catch { /* emittedConfig is not JSON — prose fields still contribute */ }
  }
  return [...tokens];
}

function binaryScanPath(bin) {
  if (!/\.(cmd|bat)$/i.test(bin)) return { path: bin, viaShim: false };
  const exe = bin.replace(/\.(cmd|bat)$/i, '.exe');
  return { path: existsSync(exe) ? realpathSync(exe) : bin, viaShim: true };
}

function countTokenHits(buf, token) {
  const needle = Buffer.from(token, 'utf8');
  let count = 0;
  let idx = 0;
  while ((idx = buf.indexOf(needle, idx)) !== -1) {
    count += 1;
    idx += needle.length;
  }
  return count;
}

function runVerifyCatalogue(args) {
  const cataloguePath = args.catalogue || DEFAULT_CATALOGUE;
  let cat;
  try {
    cat = JSON.parse(readFileSync(cataloguePath, 'utf8'));
  } catch (e) {
    usageError(`--catalogue unreadable JSON: ${e.message}`);
  }
  if (cat.schema !== CATALOGUE_SCHEMA) {
    usageError(`--catalogue expects ${CATALOGUE_SCHEMA}; got ${JSON.stringify(cat.schema)}`);
  }

  const bin = resolveBinary(args.binary);
  if (!bin) {
    degrade('no-binary', 'no `claude` executable found on PATH and no --binary given',
      'Pass --binary <path> naming the Claude Code executable whose strings to grep.');
  }
  const scanned = binaryScanPath(bin);
  let buf;
  try {
    buf = readFileSync(scanned.path);
  } catch (e) {
    degrade('binary-unreadable', `could not read binary ${scanned.path}: ${e.message}`,
      'Pass --binary with a readable Claude Code executable.');
  }

  const rows = [];
  const absent = [];
  const storedEnv = new Set();
  for (const lever of cat.levers ?? []) {
    const names = catalogueTokens(lever);
    for (const name of names) {
      if (/^(?:CLAUDE_CODE|ENABLE|DISABLE)_[A-Z0-9_]+$/.test(name)) storedEnv.add(name);
    }
    const tokens = names.map((name) => {
      const hits = countTokenHits(buf, name);
      const present = hits > 0;
      if (!present) absent.push({ id: lever.id, name });
      return { name, present, hits };
    });
    rows.push({
      id: lever.id,
      tokens,
      skipped: tokens.length === 0,
    });
  }

  let unstored = null;
  if (args['find-unstored']) {
    const seen = new Set();
    const text = buf.toString('latin1');
    for (const match of text.matchAll(ENV_TOKEN_RE)) {
      if (!storedEnv.has(match[0])) seen.add(match[0]);
    }
    unstored = [...seen].sort();
  }

  const caveats = [
    'binary scan is the authority on existence of each key/env name at this binary version',
    'docs fetch remains the authority on semantics',
  ];
  if (scanned.viaShim && scanned.path === bin) {
    caveats.push('scanned a Windows command shim; a sibling .exe was not found, so absence findings may be the wrapper rather than the payload');
  } else if (scanned.viaShim) {
    caveats.push(`resolved Windows command shim ${bin} to sibling ${scanned.path}`);
  }
  if (unstored) {
    caveats.push('unstored lists env names found in the binary that no catalogue row cites; existence only, not a claim that each is an operator switch');
  }

  return {
    schema: CATALOGUE_VERIFY_SCHEMA,
    timestampUtc: nowUtc(),
    method: 'binary-scan',
    binary: { path: scanned.path, version: binaryVersion(bin), resolvedFrom: bin },
    catalogue: {
      path: cataloguePath,
      verifiedAgainst: cat.meta?.verifiedAgainst ?? null,
    },
    rows,
    checked: rows.reduce((n, r) => n + r.tokens.length, 0),
    missing: absent.length,
    absent,
    ...(unstored ? { unstored } : {}),
    caveats,
  };
}

function emit(record, outFile) {
  const text = `${JSON.stringify(record, null, 2)}\n`;
  if (outFile) {
    mkdirSync(dirname(resolve(outFile)), { recursive: true });
    writeFileSync(outFile, text);
  }
  process.stdout.write(text);
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  if (!cmd || cmd === '--help' || args.help) {
    process.stdout.write(HELP);
    process.exit(cmd || args.help ? 0 : 2);
  }

  switch (cmd) {
    case 'snapshot': {
      if (args['measure-only']) {
        for (const flag of ['out', 'deny', 'label']) {
          if (args[flag] !== undefined) usageError(`snapshot --measure-only takes no --${flag} (it measures once and writes no file)`);
        }
      }
      emit(await takeSnapshot(args), args.out);
      break;
    }
    case 'attribute': {
      emit(await runAttribute(args), args.out);
      break;
    }
    case 'compare': {
      if (!args.before || !args.after) usageError('compare needs --before <file> and --after <file>');
      let before; let after;
      try {
        before = JSON.parse(readFileSync(args.before, 'utf8'));
        after = JSON.parse(readFileSync(args.after, 'utf8'));
      } catch (e) {
        usageError(`snapshot file unreadable: ${e.message}`);
      }
      for (const [name, snap] of [['--before', before], ['--after', after]]) {
        if (snap.schema !== SNAPSHOT_SCHEMA) usageError(`${name} is not a ${SNAPSHOT_SCHEMA} record`);
      }
      emit(compareSnapshots(before, after, { lever: args.lever ?? null, emittedConfig: args['emitted-config'] ?? null }), args.out);
      break;
    }
    case 'ledger': {
      if (!args.dir) usageError('ledger needs --dir <data-dir> (derive it with the plugin\'s state key — see SKILL.md)');
      if (!isAbsolute(args.dir)) usageError('--dir must be an absolute path');
      if (args.append) ledgerAppend(args.dir, args.append);
      else if (args.list) ledgerList(args.dir);
      else usageError('ledger needs --append <row-file> or --list');
      break;
    }
    case 'verify-catalogue': {
      emit(runVerifyCatalogue(args), args.out);
      break;
    }
    case 'parse-context': {
      if (!args.file) usageError('parse-context needs --file <captured-context.md>');
      let text;
      try {
        text = readFileSync(args.file, 'utf8');
      } catch (e) {
        usageError(`--file unreadable: ${e.message}`);
      }
      try {
        const parsed = parseContextMarkdown(text);
        emit({
          schema: `${SNAPSHOT_SCHEMA}-partial`,
          source: 'parse-context',
          ...parsed,
          skillListing: { signature: listingSignature(parsed.skillRows), rows: parsed.skillRows.length },
        }, args.out);
      } catch (e) {
        if (e instanceof ParseError) {
          degrade('unparsable', e.message,
            'The /context output format has changed; update the plugin or use sdk mode.');
        }
        throw e;
      }
      break;
    }
    default:
      usageError(`unknown subcommand: ${cmd}`);
  }
}

main().catch((e) => {
  degrade('unexpected-failure', String(e && e.stack ? e.stack : e).slice(0, 800),
    'This is an engine defect or an environment change; re-run with a known-good binary or file an issue.');
});
