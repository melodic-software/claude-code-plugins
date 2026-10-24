#!/usr/bin/env node
// summarize.mjs: the job summary for one `claude plugin eval` JSON result.
//
//   summarize.mjs <results.json> [--plugin <name>]
//
// Prints Markdown: a with-versus-without table with one verdict per case,
// then one health line per case. The verdict is read in the order
// /evals:plugin-eval's reference/ci.md gives: a partial document, then any
// run that skipped its paid graders or errored, then a two-arm case with no
// delta, each NOT COMPARABLE, and only then the score against the run's
// threshold, PASS or FAIL. A NOT COMPARABLE case shows no score. The health
// line reads each with-arm run's kept trace (--keep-temp): whether the
// plugin's skills were loaded (the init message's skill list) and how many
// runs called one of them through the Skill tool. --plugin names the plugin;
// without it, suite.root's last segment does.
//
// The last line is `Result: PASS`, `Result: FAIL` or `Result: NOT COMPARABLE`.
// Exit 0 when every case passes, 1 when any case fails, is not comparable,
// or the result holds no case, 2 on a usage error or an unreadable result.
import { readFileSync } from "node:fs";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const PASS = "PASS";
const FAIL = "FAIL";
const NOT_COMPARABLE = "NOT COMPARABLE";

const list = (value) => (Array.isArray(value) ? value : []);
const num = (value) => (typeof value === "number" && Number.isFinite(value) ? value : null);
const fixed = (value) => (num(value) === null ? "–" : value.toFixed(2));
const signed = (value) => (num(value) === null ? "–" : `${value >= 0 ? "+" : ""}${value.toFixed(2)}`);
// Table cells and health lines carry case names and errors from the result.
const cell = (text) => String(text).replaceAll(/[\r\n]+/g, " ").replaceAll("|", "\\|").replaceAll("@", "@​");

const readTrace = (path) => {
  try {
    return readFileSync(path, "utf8")
      .split("\n")
      .flatMap((line) => {
        try {
          const value = JSON.parse(line);
          return value && typeof value === "object" ? [value] : [];
        } catch {
          return [];
        }
      });
  } catch {
    return null;
  }
};

const ownSkill = (plugin) => (name) => typeof name === "string" && (plugin ? name.startsWith(`${plugin}:`) : true);

// {kept, loaded, fired} over a case's with-arm runs: kept counts the traces
// read, loaded is true, false, or null when no kept trace lists skills.
export function health(runs, { plugin, base }) {
  const own = ownSkill(plugin);
  let kept = 0;
  let fired = 0;
  let loaded = null;
  for (const run of runs) {
    const path = typeof run?.tracePath === "string" && run.tracePath ? (isAbsolute(run.tracePath) ? run.tracePath : resolve(base, run.tracePath)) : "";
    const trace = path ? readTrace(path) : null;
    if (!trace) {
      continue;
    }
    kept += 1;
    const init = trace.find((line) => line.type === "system" && line.subtype === "init");
    if (Array.isArray(init?.skills)) {
      loaded = loaded === true || init.skills.some(own);
    }
    const calls = trace
      .filter((line) => line.type === "assistant")
      .flatMap((line) => list(line.message?.content))
      .filter((part) => part?.type === "tool_use" && part.name === "Skill");
    if (calls.some((part) => own(part.input?.skill))) {
      fired += 1;
    }
  }
  return { kept, loaded, fired };
}

// [{name, verdict, reason, score, without, delta}] for each case.
export function verdicts(result) {
  const twoArm = result.suite?.ablation !== "none";
  const threshold = num(result.suite?.threshold) ?? 1;
  return list(result.cases).map((c, index) => {
    const name = c?.name ?? c?.dir ?? `case ${index + 1}`;
    const aggregates = c?.aggregates ?? {};
    const row = { name, score: num(aggregates.score), without: num(aggregates.scoreWithout), delta: num(aggregates.delta) };
    const runs = Object.entries(c?.arms ?? {}).flatMap(([arm, rows]) => list(rows).map((run, i) => ({ arm, n: i + 1, run })));
    const notComparable = (reason) => ({ ...row, verdict: NOT_COMPARABLE, reason, score: null, without: null, delta: null });
    if (result.partial) {
      return notComparable(`the suite did not finish (partial: ${result.partialReason ?? "no reason given"})`);
    }
    const errored = runs.find(({ run }) => run?.error !== null && run?.error !== undefined);
    if (errored) {
      return notComparable(`${errored.arm}-arm run ${errored.n} errored: ${errored.run.error}`);
    }
    const skipped = runs.find(({ run }) => run?.skippedPaidGraders);
    if (skipped) {
      return notComparable(`${skipped.arm}-arm run ${skipped.n} skipped its paid graders`);
    }
    if (runs.length === 0) {
      return notComparable("the case holds no runs");
    }
    if (twoArm && row.delta === null) {
      return notComparable("the arms are not comparable: the case carries no delta");
    }
    if (row.score === null) {
      return notComparable("the case carries no score");
    }
    return { ...row, verdict: row.score >= threshold ? PASS : FAIL, reason: `score ${fixed(row.score)} against threshold ${fixed(threshold)}` };
  });
}

export function summarize(result, { plugin, base }) {
  const rows = verdicts(result);
  const owner = plugin || (typeof result.suite?.root === "string" ? basename(result.suite.root) : "");
  const lines = [
    `### Plugin eval: ${cell(owner || "unknown plugin")}`,
    "",
    `Claude Code ${cell(result.claudeVersion ?? "unknown")}, ablation ${cell(result.suite?.ablation ?? "with-without")}, threshold ${fixed(num(result.suite?.threshold) ?? 1)}, cost ${num(result.costUsd) === null ? "unknown" : `${result.costUsd.toFixed(2)} USD (list-price estimate)`}.`,
    "",
    "| Case | With | Without | Delta | Verdict |",
    "|---|---|---|---|---|",
    ...rows.map((r) => `| ${cell(r.name)} | ${fixed(r.score)} | ${fixed(r.without)} | ${signed(r.delta)} | ${r.verdict}: ${cell(r.reason)} |`),
    "",
    "Health, with-arm runs:",
    "",
    ...list(result.cases).map((c, index) => {
      const runs = list(c?.arms?.with);
      const h = health(runs, { plugin: owner, base });
      const loaded = h.loaded === null ? "unknown (no kept trace lists skills)" : h.loaded ? "yes" : "no";
      const fired = h.kept === 0 ? `no kept trace of ${runs.length} runs` : `fired in ${h.fired} of ${h.kept} runs with a kept trace (${runs.length} runs)`;
      return `- ${cell(rows[index].name)}: skill loaded: ${loaded}; ${fired}`;
    }),
    "",
  ];
  const result_ = rows.length === 0 || rows.some((r) => r.verdict === NOT_COMPARABLE) ? NOT_COMPARABLE : rows.some((r) => r.verdict === FAIL) ? FAIL : PASS;
  if (rows.length === 0) {
    lines.push("The result holds no case.", "");
  }
  lines.push(`Result: ${result_}`);
  return { text: lines.join("\n"), result: result_ };
}

export function main(argv = process.argv.slice(2)) {
  const [file, flag, plugin] = argv;
  if (!file || (flag !== undefined && (flag !== "--plugin" || !plugin)) || argv.length > 3) {
    console.error("usage: summarize.mjs <results.json> [--plugin <name>]");
    return 2;
  }
  let result;
  try {
    result = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    console.error(`summarize: cannot read ${file}: ${error.message}`);
    return 2;
  }
  if (!result || typeof result !== "object") {
    console.error(`summarize: ${file} is not a result document`);
    return 2;
  }
  const { text, result: verdict } = summarize(result, { plugin, base: dirname(resolve(file)) });
  console.log(text);
  return verdict === PASS ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
