#!/usr/bin/env node
// Aggregate one dated results directory into summary.json (machine) and summary.md (human).
//
//   node aggregate.mjs results/<date>
//
// Reads <dir>/l2.jsonl (one graded agent trial per line, from run-l2.mjs grade) and, when present,
// <dir>/l1.json (from run-l1.mjs). Voided trials are counted but excluded from every rate.
//
// Win rule (fixed before the run, see README.md): agent-browser is the better default only if its
// pass^k is higher than playwright-cli's on at least 2 more cases than the reverse AND its pass@1 is
// not lower on any case. Anything else is reported as directional, never as a win.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) throw new Error("usage: node aggregate.mjs results/<date>");
const TOOLS = ["agent-browser", "playwright-cli"];

const median = (xs) => {
  const s = xs.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  if (!s.length) return null;
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
};
const sum = (xs) => xs.reduce((a, b) => a + (b || 0), 0);
const pct = (x) => (x == null ? "–" : `${Math.round(x * 100)}%`);

// ---- L2 -------------------------------------------------------------------------------------
const l2File = join(dir, "l2.jsonl");
const trials = existsSync(l2File)
  ? readFileSync(l2File, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l))
  : [];
// A re-graded run replaces its earlier line.
const byRun = new Map(trials.map((t) => [t.run, t]));
const all = [...byRun.values()];

const cells = new Map(); // `${task}|${tool}|${arm}` -> trials
for (const t of all) {
  const k = `${t.task}|${t.tool}|${t.arm}`;
  if (!cells.has(k)) cells.set(k, []);
  cells.get(k).push(t);
}
function cellStats(ts) {
  const valid = ts.filter((t) => !t.voided);
  const passes = valid.filter((t) => t.pass).length;
  const tr = (f) => valid.map((t) => f(t.transcript ?? {}));
  return {
    trials: ts.length,
    voided: ts.length - valid.length,
    passes,
    passAt1: valid.length ? passes / valid.length : null,
    passAll: valid.length ? passes === valid.length : null, // pass^k over the valid reps
    medianWallMs: median(valid.map((t) => t.usage?.wallMs)),
    medianTurns: median(tr((x) => x.turns)),
    medianBrowserCalls: median(tr((x) => x.browserInvocations)),
    medianContextGrowth: median(tr((x) => x.contextGrowthTokens)),
    medianToolOutputTokens: median(tr((x) => x.toolOutputTokensApprox)),
    toolErrors: sum(tr((x) => x.toolErrors)),
    retries: sum(tr((x) => x.retries)),
    exposure: valid.reduce((acc, t) => {
      for (const [ch, hit] of Object.entries(t.transcript?.exposure ?? {})) acc[ch] = (acc[ch] ?? 0) + (hit ? 1 : 0);
      return acc;
    }, {}),
    failures: valid.filter((t) => !t.pass).map((t) => ({ run: t.run, detail: t.detail, answer: (t.answer ?? "").slice(0, 200) })),
    voids: ts.filter((t) => t.voided).map((t) => ({ run: t.run, why: t.voided })),
  };
}
const tasks = [...new Set(all.map((t) => t.task))].sort();
const arms = [...new Set(all.map((t) => `${t.tool}|${t.arm}`))].sort();
const l2 = {};
for (const [k, ts] of cells) l2[k] = cellStats(ts);

// Paired per-case comparison on the default arm.
const paired = tasks.map((task) => {
  const ab = l2[`${task}|agent-browser|default`];
  const pw = l2[`${task}|playwright-cli|default`];
  const d = (f) => (ab && pw && f(ab) != null && f(pw) != null ? f(ab) - f(pw) : null);
  return {
    task,
    passAt1: { ab: ab?.passAt1 ?? null, pw: pw?.passAt1 ?? null, diff: d((s) => s.passAt1) },
    passAll: { ab: ab?.passAll ?? null, pw: pw?.passAll ?? null },
    wallMsDiff: d((s) => s.medianWallMs),
    browserCallsDiff: d((s) => s.medianBrowserCalls),
    contextGrowthDiff: d((s) => s.medianContextGrowth),
  };
});
const abBetter = paired.filter((p) => p.passAll.ab === true && p.passAll.pw === false).length;
const pwBetter = paired.filter((p) => p.passAll.pw === true && p.passAll.ab === false).length;
const abLosses = paired.filter((p) => p.passAt1.diff != null && p.passAt1.diff < 0).map((p) => p.task);
const verdict =
  abBetter - pwBetter >= 2 && abLosses.length === 0
    ? "agent-browser wins on reliability"
    : pwBetter - abBetter >= 2 && paired.every((p) => p.passAt1.diff == null || p.passAt1.diff <= 0)
      ? "playwright-cli wins on reliability"
      : "no reliability winner; differences are directional only";

// ---- L1 -------------------------------------------------------------------------------------
const l1File = join(dir, "l1.json");
let l1 = null;
if (existsSync(l1File)) {
  const raw = JSON.parse(readFileSync(l1File, "utf8"));
  const groups = new Map();
  for (const r of raw.results) {
    const k = `${r.fixture}${r.variant ?? ""}|${r.tool}|${r.delay}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  const rows = {};
  for (const [k, rs] of groups)
    rows[k] = {
      runs: rs.length,
      passes: rs.filter((r) => r.pass).length,
      medianWallMs: median(rs.map((r) => r.wallMs)),
      medianCommands: median(rs.map((r) => r.commands)),
      medianSnapshotBytes: median(rs.map((r) => r.snapshotBytes)),
      errors: [...new Set(rs.flatMap((r) => r.errors.map((e) => `${e.what}: ${e.msg}`.slice(0, 160))))],
    };
  const byTool = Object.fromEntries(
    TOOLS.map((tool) => {
      const rs = raw.results.filter((r) => r.tool === tool);
      return [tool, { runs: rs.length, passes: rs.filter((r) => r.pass).length, medianWallMs: median(rs.map((r) => r.wallMs)), medianSnapshotBytes: median(rs.map((r) => r.snapshotBytes)) }];
    }),
  );
  l1 = { at: raw.at, versions: raw.versions, delays: raw.delays, repeat: raw.repeat, byTool, rows };
}

const summary = {
  generatedAt: new Date().toISOString(),
  dir,
  l2: { trials: all.length, voided: all.filter((t) => t.voided).length, cells: l2, paired, verdict, abBetterCases: abBetter, pwBetterCases: pwBetter, abPassAt1Losses: abLosses },
  l1,
};
writeFileSync(join(dir, "summary.json"), JSON.stringify(summary, null, 2) + "\n");

// ---- Markdown -------------------------------------------------------------------------------
const md = [];
md.push(`# Browser-tools benchmark summary (${dir.split("/").pop()})`, "");
md.push(`Generated by \`aggregate.mjs\`. Verdict under the pre-registered win rule: **${verdict}**.`, "");
md.push(`L2: ${all.length} agent trials, ${summary.l2.voided} voided. pass^k cases where only agent-browser held: ${abBetter}; only playwright-cli: ${pwBetter}.`, "");
md.push("## L2 per task (default arm)", "");
md.push("| Task | Tool | Pass | pass^k | Median wall s | Median browser calls | Median context growth (tokens) | Tool errors | Retries |");
md.push("|---|---|---|---|---|---|---|---|---|");
for (const task of tasks)
  for (const tool of TOOLS) {
    const s = l2[`${task}|${tool}|default`];
    if (!s) continue;
    md.push(`| ${task} | ${tool} | ${s.passes}/${s.trials - s.voided}${s.voided ? ` (+${s.voided} void)` : ""} | ${s.passAll ? "yes" : "no"} | ${s.medianWallMs == null ? "–" : (s.medianWallMs / 1000).toFixed(1)} | ${s.medianBrowserCalls ?? "–"} | ${s.medianContextGrowth ?? "–"} | ${s.toolErrors} | ${s.retries} |`);
  }
const other = arms.filter((a) => !a.endsWith("|default"));
if (other.length) {
  md.push("", "## L2 extra arms", "");
  for (const a of other)
    for (const task of tasks) {
      const s = l2[`${task}|${a}`];
      if (s) md.push(`- ${task} ${a.replace("|", " / ")}: ${s.passes}/${s.trials - s.voided} pass, median context growth ${s.medianContextGrowth}, exposure ${JSON.stringify(s.exposure)}`);
    }
}
md.push("", "## L2 totals per tool (default arm)", "");
md.push("| Tool | pass@1 | Median wall s | Median browser calls | Median context growth | Tool errors | Retries |");
md.push("|---|---|---|---|---|---|---|");
for (const tool of TOOLS) {
  const ts = all.filter((t) => t.tool === tool && t.arm === "default");
  const s = cellStats(ts);
  md.push(`| ${tool} | ${pct(s.passAt1)} (${s.passes}/${s.trials - s.voided}) | ${s.medianWallMs == null ? "–" : (s.medianWallMs / 1000).toFixed(1)} | ${s.medianBrowserCalls} | ${s.medianContextGrowth} | ${s.toolErrors} | ${s.retries} |`);
}
const fails = Object.entries(l2).flatMap(([k, s]) => s.failures.map((f) => ({ k, ...f })));
if (fails.length) {
  md.push("", "## L2 failures", "");
  for (const f of fails) md.push(`- ${f.k} \`${f.run}\`: detail ${JSON.stringify(f.detail)}; answer: ${f.answer.replace(/\n/g, " ")}`);
}
if (l1) {
  md.push("", "## L1 scripted fixtures", "");
  md.push(`Versions: ${Object.entries(l1.versions).map(([k, v]) => `${k} ${v}`).join(", ")}. Delays ${l1.delays.join(", ")} ms, ${l1.repeat} repeat(s).`, "");
  md.push("| Tool | Pass | Median wall ms | Median snapshot bytes |", "|---|---|---|---|");
  for (const [tool, s] of Object.entries(l1.byTool)) md.push(`| ${tool} | ${s.passes}/${s.runs} | ${s.medianWallMs} | ${s.medianSnapshotBytes} |`);
  const l1Fails = Object.entries(l1.rows).filter(([, s]) => s.passes < s.runs);
  if (l1Fails.length) {
    md.push("", "L1 rows that did not pass every run:", "");
    for (const [k, s] of l1Fails) md.push(`- ${k.replace(/\|/g, " / d")}: ${s.passes}/${s.runs}${s.errors.length ? ` (${s.errors.join("; ")})` : ""}`);
  }
}
writeFileSync(join(dir, "summary.md"), md.join("\n") + "\n");
console.log(`wrote ${join(dir, "summary.json")} and summary.md — ${verdict}`);
