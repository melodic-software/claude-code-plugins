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
//   cli-parse  `<binary> -p "/context"` markdown, parsed version-aware —
//              display-rounded values. Headless /context is undocumented as a
//              -p-capable command, so this mode is load-bearing but
//              unsanctioned; the record says so in `caveats`.
//   (neither)  a structured error naming the remediation — never a wrong
//              number.
//
// Subcommands:
//   snapshot          one measured snapshot (optionally under --deny)
//   attribute         baseline + one deny run per tool -> ranked per-tool deltas
//   compare           offline: two snapshot files -> one ledger row
//   ledger            append a row / list rows under a caller-derived data dir
//   parse-context     offline: parse a captured /context markdown file
//   verify-catalogue  grep the stamped binary for each catalogue key/env name
//
// Exit codes: 0 success; 2 usage error; 3 measurement unavailable or
// unparsable (the degradation path — stdout carries a context-budget.error/1
// record with a remediation).
//
// Comparability rules the engine enforces (measured, see the plugin's
// reference/engine.md):
//   - `System tools` deltas are only meaningful between runs whose skill
//     listing is identical (listed skill-frontmatter tokens are subtracted
//     from that bucket). Every record carries a skill-listing signature and
//     compare/attribute refuse to call mismatched runs comparable.
//   - Deltas are computed within one mode and one binary version only.

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

const DEFAULT_CATALOGUE = join(
  dirname(fileURLToPath(import.meta.url)), '..', 'reference', 'levers.json',
);
const INTERACTIVE_ONLY_LISTING = join(
  dirname(fileURLToPath(import.meta.url)), '..', 'reference', 'interactive-only-tools.json',
);
const INTERACTIVE_ONLY_SCHEMA = 'context-budget.interactive-only/1';

// Settings keys and env names the catalogue cites. Env vars are the CLAUDE_CODE_
// / ENABLE_ / DISABLE_ family; settings keys are camelCase identifiers in the
// row's prose fields. A row may override with `binaryTokens`.
const ENV_TOKEN_RE = /\b(?:CLAUDE_CODE|ENABLE|DISABLE)_[A-Z0-9_]+\b/g;

// Linear camelCase scan — no nested quantifiers. The previous
// /\b[a-z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)+\b/g shape is ReDoS-vulnerable
// on a long same-case run that then fails \b (e.g. "a" + "A"*n + "_").
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

// The two /context buckets a bare-name tool deny moves — the buckets the
// attribute pipeline sums per-tool and for the additivity check.
const SYSTEM_TOOL_BUCKETS = ['System tools', 'System tools (deferred)'];

function usageError(msg) {
  process.stderr.write(`ERROR: ${msg}\n`);
  process.stderr.write('Run with --help for usage.\n');
  process.exit(2);
}

function degrade(error, detail, remediation) {
  process.stdout.write(`${JSON.stringify({ schema: ERROR_SCHEMA, error, detail, remediation }, null, 2)}\n`);
  process.exit(3);
}

function nowUtc() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function sha12(text) {
  return createHash('sha256').update(text).digest('hex').slice(0, 12);
}

// ---------------------------------------------------------------------------
// Argument parsing (flat flags; every subcommand shares one parser)
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      args._.push(a);
      continue;
    }
    const key = a.slice(2);
    const flagOnly = ['help', 'verify-additivity', 'list'];
    if (flagOnly.includes(key)) {
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
  measure.mjs attribute --tools <T1,T2,...|from-baseline> [--binary <path>]
                       [--sdk-dir <dir>] [--verify-additivity] [--out <file>]
  measure.mjs compare --before <file> --after <file> [--lever <name>]
                       [--emitted-config <text>]
  measure.mjs ledger (--append <row-file>|--list) --dir <data-dir>
  measure.mjs parse-context --file <captured-context.md>
  measure.mjs verify-catalogue [--binary <path>] [--catalogue <file>] [--out <file>]

Exit: 0 success; 2 usage error; 3 measurement unavailable/unparsable
      (stdout then carries a ${ERROR_SCHEMA} record with a remediation).
`;

// ---------------------------------------------------------------------------
// Binary resolution — pin and report the measured binary
// ---------------------------------------------------------------------------

function resolveBinary(explicit) {
  if (explicit) {
    if (!existsSync(explicit)) {
      degrade('binary-not-found', `--binary path does not exist: ${explicit}`,
        'Pass --binary with the path of the Claude Code executable to measure.');
    }
    return realpathSync(explicit);
  }
  // .exe before .cmd: a real executable spawns everywhere, while a .cmd shim
  // needs a shell (see spawnBinary); prefer the form that works unaided.
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

// Node cannot execute Windows command shims (.cmd/.bat) directly — they need
// a shell. Route those through spawnSync's shell mode; real executables spawn
// unaided on every platform.
function spawnBinary(bin, args, opts) {
  const needsShell = process.platform === 'win32' && /\.(cmd|bat)$/i.test(bin);
  return spawnSync(bin, args, { ...opts, ...(needsShell ? { shell: true } : {}) });
}

function binaryVersion(bin) {
  const r = spawnBinary(bin, ['--version'], { encoding: 'utf8', timeout: 30000 });
  const m = ((r.stdout || '') + (r.stderr || '')).match(/(\d+\.\d+\.\d+)/);
  return m ? m[1] : null;
}

// ---------------------------------------------------------------------------
// SDK resolution
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// /context markdown parsing (cli-parse mode and the offline parse-context
// subcommand). Version-aware: refuses to guess when the expected sections are
// absent — the format has materially changed several times and carries no
// stability guarantee.
// ---------------------------------------------------------------------------

class ParseError extends Error {}

// "11.4k" -> {tokens: 11400, rounded: true}; "8" -> {tokens: 8, rounded: false}
// "~90" -> {tokens: 90, rounded: true}; "< 20" -> {tokens: 20, rounded: true}
function parseTokenCell(cell) {
  const t = cell.trim();
  let m = t.match(/^~?\s*([\d.]+)k$/i);
  if (m) return { tokens: Math.round(parseFloat(m[1]) * 1000), rounded: true };
  m = t.match(/^~\s*(\d+)$/);
  if (m) return { tokens: parseInt(m[1], 10), rounded: true };
  m = t.match(/^<\s*(\d+)$/);
  if (m) return { tokens: parseInt(m[1], 10), rounded: true };
  m = t.match(/^(\d+)$/);
  if (m) return { tokens: parseInt(m[1], 10), rounded: false };
  throw new ParseError(`unrecognized token cell: ${JSON.stringify(cell)}`);
}

function tableRows(lines, startIdx) {
  // startIdx points at the header row `| a | b | ... |`; skip it and the
  // divider, then collect until the first non-row line.
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

function parseContextMarkdown(text) {
  // Trap: unredirected stdin prepends a warning line; anything before the
  // first markdown heading is not /context output.
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
  if (!('System tools' in categories)) {
    throw new ParseError('category table parsed but carries no "System tools" row — refusing to guess');
  }

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

  return { categories, model, skillRows, agents, precision: anyRounded ? 'display-rounded' : 'exact' };
}

// ---------------------------------------------------------------------------
// Skill-listing signature — the comparability key for `System tools`
// ---------------------------------------------------------------------------

function listingSignature(rows) {
  const canon = rows.map((r) => `${r.name} ${r.source}`).sort();
  return sha12(JSON.stringify(canon));
}

// ---------------------------------------------------------------------------
// Measurement — sdk mode
// ---------------------------------------------------------------------------

async function sdkSnapshot({ sdk, sdkVersion, sdkEntry, bin, deny, label }) {
  const { query } = sdk;
  const options = {
    maxTurns: 1,
    pathToClaudeCodeExecutable: bin,
    ...(deny.length ? { disallowedTools: deny } : {}),
  };
  // "/context" is handled by the CLI itself, so the spawned session makes no
  // model API call; the structured usage arrives over the control protocol.
  const q = query({ prompt: '/context', options });

  const result = await new Promise((resolvePromise, rejectPromise) => {
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

  const { init, usage } = result;
  const categories = {};
  for (const c of usage.categories ?? []) categories[c.name] = c.tokens;
  // A deny that empties a bucket makes the SDK omit it rather than report 0.
  // sdk mode's numbers are exact and its category vocabulary is known, so for
  // the attributed buckets that absence IS a measured zero — record it, or a
  // combined deny that empties a bucket yields a null delta downstream where
  // a real one was measured. cli-parse absence stays genuinely ambiguous
  // (format drift vs emptied bucket) and is deliberately not zero-filled.
  // The fill is shared snapshot plumbing (snapshot/compare/ledger see it too);
  // a caveat names every synthesized zero so a raw consumer can tell a real
  // reported 0 from a filled-in omission.
  const caveats = [];
  for (const bucket of SYSTEM_TOOL_BUCKETS) {
    if (!(bucket in categories)) {
      categories[bucket] = 0;
      caveats.push(
        `sdk omitted "${bucket}"; recorded as measured 0 (sdk category vocabulary is known; numbers are exact)`,
      );
    }
  }

  const skillFrontmatter = usage.skills?.skillFrontmatter ?? [];
  const skillRows = skillFrontmatter.map((s) => ({ name: s.name, source: s.source }));

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
    totalTokens: usage.totalTokens ?? null,
    maxTokens: usage.maxTokens ?? null,
    tools: init.tools ?? [],
    agents: usage.agents ?? [],
    mcpTools: usage.mcpTools ?? [],
    memoryFiles: usage.memoryFiles ?? [],
    skillListing: {
      totalSkills: usage.skills?.totalSkills ?? null,
      includedSkills: usage.skills?.includedSkills ?? null,
      tokens: usage.skills?.tokens ?? categories.Skills ?? null,
      signature: listingSignature(skillRows),
      rows: skillRows.length,
    },
    caveats,
  };
}

// ---------------------------------------------------------------------------
// Measurement — cli-parse mode
// ---------------------------------------------------------------------------

function cliSnapshot({ bin, deny, label }) {
  const args = ['-p', '/context'];
  if (deny.length) args.push('--disallowedTools', ...deny);
  const r = spawnBinary(bin, args, { encoding: 'utf8', input: '', timeout: SPAWN_TIMEOUT_MS });
  if (r.error || r.status !== 0 || !r.stdout) {
    throw new ParseError(`headless /context failed (exit ${r.status ?? 'spawn-error'}): `
      + `${(r.stderr || String(r.error || '')).trim().slice(0, 300)}`);
  }
  const parsed = parseContextMarkdown(r.stdout);
  // Match the SDK/renderer headline semantics: deferred pools (any
  // "... (deferred)" category — built-in and MCP alike) are excluded from the
  // context-usage total (they ship in the request but sit outside the context
  // window), as are the free-space and buffer rows.
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
    binary: { path: bin, version: binaryVersion(bin) },
    sdk: null,
    model: parsed.model,
    cwd: process.cwd(),
    deny,
    categories: parsed.categories,
    totalTokens: payloadTotal,
    maxTokens: null,
    tools: [],
    agents: parsed.agents,
    mcpTools: [],
    memoryFiles: [],
    skillListing: {
      totalSkills: null,
      includedSkills: null,
      tokens: parsed.categories.Skills ?? null,
      signature: listingSignature(parsed.skillRows),
      rows: parsed.skillRows.length,
    },
    caveats: [
      'cli-parse mode: values are display-rounded, not exact integers',
      'headless /context is undocumented as a -p-capable command (load-bearing but unsanctioned)',
    ],
  };
}

// ---------------------------------------------------------------------------
// Shared snapshot driver with the degradation ladder
// ---------------------------------------------------------------------------

async function takeSnapshot(args) {
  const deny = args.deny ? args.deny.split(',').map((s) => s.trim()).filter(Boolean) : [];
  const bin = resolveBinary(args.binary);
  if (!bin) {
    degrade('no-binary', 'no `claude` executable found on PATH and no --binary given',
      'Install the Claude Code CLI, or pass --binary <path> naming the executable to measure.');
  }

  const sdkCandidates = [args['sdk-dir'], process.cwd()];
  const found = findSdkEntry(sdkCandidates);
  if (found) {
    try {
      const sdk = await import(pathToFileURL(found.entry).href);
      return await sdkSnapshot({
        sdk, sdkVersion: sdkVersionFromEntry(found.entry), sdkEntry: found.entry, bin, deny, label: args.label,
      });
    } catch (e) {
      // SDK resolved but the measurement failed — fall through to cli-parse,
      // carrying the reason so the record stays honest about the downgrade.
      try {
        const snap = cliSnapshot({ bin, deny, label: args.label });
        snap.caveats.push(`sdk mode failed and was degraded to cli-parse: ${String(e).slice(0, 200)}`);
        return snap;
      } catch (e2) {
        degrade('measurement-failed', `sdk mode failed (${String(e).slice(0, 200)}); `
          + `cli-parse fallback also failed (${String(e2).slice(0, 200)})`,
        'Verify the binary runs (`claude --version`) and that `claude -p "/context"` produces the category table.');
      }
    }
  }
  try {
    return cliSnapshot({ bin, deny, label: args.label });
  } catch (e) {
    degrade('measurement-unavailable',
      `@anthropic-ai/claude-agent-sdk is not resolvable (tried: ${sdkCandidates.filter(Boolean).join(', ')}) `
      + `and cli-parse failed: ${String(e).slice(0, 300)}`,
      'For exact measurement install the Agent SDK (npm install @anthropic-ai/claude-agent-sdk in a directory '
      + 'passed as --sdk-dir). For the fallback, verify `claude -p "/context"` prints the category table at your version.');
  }
  return null; // unreachable — degrade() exits
}

// ---------------------------------------------------------------------------
// compare — two snapshots -> one ledger row
// ---------------------------------------------------------------------------

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
  if (before.mode !== after.mode) reasons.push(`mode differs (${before.mode} vs ${after.mode}) — deltas across modes mix precisions`);
  if (before.binary?.version !== after.binary?.version) reasons.push(`binary version differs (${before.binary?.version} vs ${after.binary?.version})`);
  if (before.binary?.path !== after.binary?.path) reasons.push(`binary path differs (${before.binary?.path} vs ${after.binary?.path})`);
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
  for (const name of names) {
    const b = before.categories?.[name];
    const a = after.categories?.[name];
    if (typeof b === 'number' && typeof a === 'number') delta[name] = a - b;
    else delta[name] = null; // present in one run only — never invent a number
  }
  const totalDelta = (typeof before.totalTokens === 'number' && typeof after.totalTokens === 'number')
    ? after.totalTokens - before.totalTokens : null;

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
    totalDelta,
    comparability: {
      ok: reasons.length === 0,
      // Every recorded mismatch poisons the predicate — a reason the caller
      // could read but a `true` flag would let it ignore is how an
      // acknowledged-incomparable run gets published as attribution.
      systemToolsComparable: sigMatch && skillTokensMatch
        && before.mode === after.mode
        && before.binary?.version === after.binary?.version
        && before.binary?.path === after.binary?.path,
      reasons,
    },
  };
}

// ---------------------------------------------------------------------------
// attribute — per-tool attribution by bare-name deny differencing
// ---------------------------------------------------------------------------

// Saving across the attributed buckets of one comparison, honoring the
// three states a bucket delta can be in:
//   number     measured in both runs — use it;
//   null       present in one run only (a deny can empty a bucket out of the
//              snapshot entirely) — a missing measurement, NEVER zero;
//   undefined  absent from both runs — outside this binary's category
//              vocabulary, a non-event that contributes nothing.
// `saved` is null when any needed bucket vanished; callers publish that as
// incomparable with `vanished` naming the buckets, never coerce it to 0.
function systemBucketSaving(cmp) {
  const vanished = SYSTEM_TOOL_BUCKETS.filter((b) => b in cmp.delta && cmp.delta[b] === null);
  if (vanished.length) return { vanished, saved: null };
  return { vanished, saved: -SYSTEM_TOOL_BUCKETS.reduce((s, b) => s + (cmp.delta[b] ?? 0), 0) };
}

function vanishedReason(vanished) {
  return `${vanished.join(' and ')} present in only one run — the bucket was emptied out of one `
    + 'snapshot, so its delta is unmeasured, not zero';
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

function knownUncoveredRecord(candidates, listing) {
  const seen = new Set(candidates);
  return {
    reason: 'interactive-only — structurally unreachable from a headless candidate list',
    tools: (listing.tools || []).filter((t) => !seen.has(t)),
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
    tools = args.tools.split(',').map((s) => s.trim()).filter(Boolean);
  }
  if (!tools.length) usageError('--tools resolved to an empty list');

  const perTool = [];
  for (const tool of tools) {
    const run = await takeSnapshot({ ...args, deny: tool, label: `deny:${tool}` });
    const cmp = compareSnapshots(baseline, run, { lever: `deny:${tool}` });
    const { vanished, saved } = systemBucketSaving(cmp);
    perTool.push({
      tool,
      // A deny that saves prints as a NEGATIVE delta (after minus before);
      // savedTokens flips the sign for ranking and readability. A vanished
      // bucket makes it null — an unmeasured saving, never a zero.
      prefixDelta: cmp.delta['System tools'] ?? null,
      deferredDelta: cmp.delta['System tools (deferred)'] ?? null,
      savedTokens: saved,
      comparable: cmp.comparability.systemToolsComparable && !vanished.length,
      reasons: vanished.length
        ? [...cmp.comparability.reasons, vanishedReason(vanished)]
        : cmp.comparability.reasons,
    });
  }
  perTool.sort((x, y) => (y.savedTokens ?? 0) - (x.savedTokens ?? 0));

  let additivity = null;
  if (args['verify-additivity']) {
    const savers = perTool.filter((t) => t.comparable && t.savedTokens > 0).map((t) => t.tool);
    if (savers.length >= 2) {
      const combined = await takeSnapshot({ ...args, deny: savers.join(','), label: 'deny:combined' });
      const cmp = compareSnapshots(baseline, combined, { lever: `deny:${savers.join('+')}` });
      // Denying every saver at once can empty a bucket out of the combined
      // snapshot; its delta is then null and the combined saving is
      // unmeasured — published as incomparable, never coerced to zero.
      const { vanished, saved: combinedSaved } = systemBucketSaving(cmp);
      const comparable = cmp.comparability.systemToolsComparable && !vanished.length;
      const sumOfParts = perTool.filter((t) => savers.includes(t.tool))
        .reduce((s, t) => s + t.savedTokens, 0);
      additivity = {
        tools: savers,
        sumOfParts,
        combinedSaved,
        additive: comparable && combinedSaved === sumOfParts,
        comparable,
        reasons: vanished.length
          ? [...cmp.comparability.reasons, vanishedReason(vanished)]
          : cmp.comparability.reasons,
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
    ),
    caveats: baseline.caveats,
  };
}

// ---------------------------------------------------------------------------
// ledger — one file per run plus an appended history line, under a data dir
// the CALLER derives (state key included); this engine never invents the key.
// ---------------------------------------------------------------------------

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
  // One file per run is the contract: a same-second rerun of the same lever
  // must not overwrite the earlier point, so collide into a numbered suffix.
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

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// verify-catalogue — binary-strings existence check (no network).
// Docs fetch remains the authority on semantics; this is the authority on
// whether each catalogue key/env name exists in the measured binary.
// ---------------------------------------------------------------------------

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

// Prefer a sibling .exe over a Windows command shim so the scan reads the
// payload the consumer actually runs, not the wrapper script.
function binaryScanPath(bin) {
  if (!/\.(cmd|bat)$/i.test(bin)) return { path: bin, viaShim: false };
  const exe = bin.replace(/\.(cmd|bat)$/i, '.exe');
  if (existsSync(exe)) return { path: realpathSync(exe), viaShim: true };
  return { path: bin, viaShim: true };
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
  for (const lever of cat.levers ?? []) {
    const names = catalogueTokens(lever);
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

  const caveats = [
    'binary scan is the authority on existence of each key/env name at this binary version',
    'docs fetch remains the authority on semantics',
  ];
  if (scanned.viaShim && scanned.path === bin) {
    caveats.push('scanned a Windows command shim; a sibling .exe was not found, so absence findings may be the wrapper rather than the payload');
  } else if (scanned.viaShim) {
    caveats.push(`resolved Windows command shim ${bin} to sibling ${scanned.path}`);
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
    caveats,
  };
}

function emit(record, outFile) {
  const text = `${JSON.stringify(record, null, 2)}\n`;
  if (outFile) {
    // A fresh audit's derived data dir does not exist yet; failing ENOENT
    // after an expensive measurement would discard the result.
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
