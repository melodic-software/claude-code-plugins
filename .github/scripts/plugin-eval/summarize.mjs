#!/usr/bin/env node
// summarize.mjs: the job summary for one `claude plugin eval` JSON result.
//
//   summarize.mjs <results.json> [--plugin <name>] [--redact] [--annotation <file>]
//
// Prints Markdown: a with-versus-without table with one verdict per case,
// then one health line per case. The verdict is read in the order
// /evals:plugin-eval's reference/ci.md gives: a partial document, then any
// run that skipped its paid graders or errored, then a two-arm case with no
// delta, each NOT COMPARABLE, and only then the score against the run's
// threshold, PASS or FAIL. A case whose case.yaml (<suite.root>/<dir>) sets
// context.history_file and whose result records no without-arm key ran
// single-arm by design and is scored alone, as run-validity.py reads it. A NOT
// COMPARABLE case shows no score. The health
// line reads each with-arm run's kept trace (--keep-temp): whether the
// plugin's skills were loaded (the init message's skill list) and how many
// runs called one of them through the Skill tool, called one of the plugin's
// agents through the Agent tool, or had a skill slash-invoked by the case
// prompt, which makes no Skill call. --plugin names the plugin;
// without it, suite.root's last segment does.
//
// --redact, for a pull request run whose prompts the pull request supplies,
// prints each case as `case <n>` and leaves out every error and partial
// reason text, so no model output reaches the public job summary.
//
// --annotation writes, when the result is not PASS, one `::error` workflow
// command naming each case that is not PASS with its verdict and reason, so
// a red run says which cases failed; the caller prints it outside any
// stop-commands block. Its title says "Plugin eval verdict", which tells an
// eval result apart from a step that failed.
//
// The last line is `Result: PASS`, `Result: FAIL` or `Result: NOT COMPARABLE`.
// Exit 0 when every case passes, 1 when any case fails, is not comparable,
// or the result holds no case, 2 on a usage error or an unreadable result.
import { readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
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

// The plugin skill a case prompt opens with as a slash command, such as
// improvement:find, else null. A slash-invoked skill makes no Skill tool call.
export const slashSkill = (prompt) => (typeof prompt === "string" ? (/^\s*\/([A-Za-z0-9][\w.-]*:[A-Za-z0-9][\w.-]*)/.exec(prompt)?.[1] ?? null) : null);

// {kept, loaded, fired} over a case's with-arm runs: kept counts the traces
// read, loaded is true, false, or null when no kept trace lists skills. A run
// fires when it calls one of the plugin's skills through the Skill tool or
// one of its agents through the Agent tool, or when the case prompt
// slash-invokes one of its skills (`invoked`) that its init lists.
export function health(runs, { plugin, base, invoked = null }) {
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
      .filter((part) => part?.type === "tool_use");
    const slashed = invoked !== null && own(invoked) && Array.isArray(init?.skills) && init.skills.includes(invoked);
    const called = calls.some((part) => (part.name === "Skill" ? own(part.input?.skill) : part.name === "Agent" && own(part.input?.subagent_type)));
    if (slashed || called) {
      fired += 1;
    }
  }
  return { kept, loaded, fired };
}

// A case.yaml context key in block or flow form, read without a YAML parser
// the way run-validity.py's context_value reads it; any other shape, or an
// empty value continued on the next line, gives null.
const CONTEXT_BLOCK = /^context:\s*(?:#.*)?$/;
const CONTEXT_FLOW = /^context:\s*\{(.*)\}\s*(?:#.*)?$/;
const scalar = (text) => {
  const value = text.trim().replace(/^['"]+|['"]+$/g, "");
  return ["", "null", "~"].includes(value) ? null : value;
};
const indent = (line) => line.length - line.trimStart().length;
const continues = (lines, index) => {
  const next = lines.slice(index + 1).find((line) => line.trim() && !line.trimStart().startsWith("#"));
  return next !== undefined && indent(next) > indent(lines[index]);
};

export function contextValue(text, key) {
  if (typeof text !== "string" || !new RegExp(`^[^#\\n]*${key}`, "m").test(text)) {
    return null;
  }
  const blockKey = new RegExp(`^\\s+${key}:\\s*(.*?)\\s*(?:#.*)?$`);
  const flowKey = new RegExp(`\\b${key}:\\s*([^,}]*)`);
  const lines = text.split(/\r\n|\r|\n/);
  let inContext = false;
  for (const [index, line] of lines.entries()) {
    const flow = CONTEXT_FLOW.exec(line);
    if (flow) {
      const found = flowKey.exec(flow[1]);
      if (found) {
        return scalar(found[1]);
      }
      inContext = false;
    } else if (CONTEXT_BLOCK.test(line)) {
      inContext = true;
    } else if (!["", " ", "\t", "#"].includes(line.slice(0, 1))) {
      inContext = false;
    } else if (inContext) {
      const found = blockKey.exec(line);
      if (found) {
        const value = scalar(found[1]);
        return value === null && continues(lines, index) ? null : value;
      }
    }
  }
  return null;
}

// A reader of <suite.root>/<dir>/case.yaml, a relative root read against base
// (the result file's directory): the text, or null when it cannot be read.
export const caseYamlReader = (result, base) => (dir) => {
  const root = result?.suite?.root;
  if (typeof root !== "string" || !root || typeof dir !== "string" || !dir || (!isAbsolute(root) && !base)) {
    return null;
  }
  try {
    return readFileSync(join(isAbsolute(root) ? root : resolve(base, root), dir, "case.yaml"), "utf8");
  } catch {
    return null;
  }
};

// [{name, verdict, reason, score, without, delta}] for each case. caseYaml
// maps a case dir to its case.yaml text, or null.
export function verdicts(result, { redact = false, caseYaml = () => null } = {}) {
  const said = (text) => (redact ? "(redacted)" : text);
  const twoArm = result.suite?.ablation !== "none";
  const threshold = num(result.suite?.threshold) ?? 1;
  return list(result.cases).map((c, index) => {
    const name = redact ? `case ${index + 1}` : (c?.name ?? c?.dir ?? `case ${index + 1}`);
    const aggregates = c?.aggregates ?? {};
    const row = { name, score: num(aggregates.score), without: num(aggregates.scoreWithout), delta: num(aggregates.delta) };
    const runs = Object.entries(c?.arms ?? {}).flatMap(([arm, rows]) => list(rows).map((run, i) => ({ arm, n: i + 1, run })));
    const notComparable = (reason) => ({ ...row, verdict: NOT_COMPARABLE, reason, score: null, without: null, delta: null });
    if (result.partial) {
      return notComparable(`the suite did not finish (partial: ${said(result.partialReason ?? "no reason given")})`);
    }
    const errored = runs.find(({ run }) => run?.error !== null && run?.error !== undefined);
    if (errored) {
      return notComparable(`${errored.arm}-arm run ${errored.n} errored: ${said(errored.run.error)}`);
    }
    const skipped = runs.find(({ run }) => run?.skippedPaidGraders);
    if (skipped) {
      return notComparable(`${skipped.arm}-arm run ${skipped.n} skipped its paid graders`);
    }
    if (runs.length === 0) {
      return notComparable("the case holds no runs");
    }
    const singleArm = twoArm && !Object.hasOwn(c?.arms ?? {}, "without") && contextValue(caseYaml(c?.dir), "history_file") !== null;
    if (twoArm && !singleArm && row.delta === null) {
      return notComparable("the arms are not comparable: the case carries no delta");
    }
    if (row.score === null) {
      return notComparable("the case carries no score");
    }
    const scored = `score ${fixed(row.score)} against threshold ${fixed(threshold)}`;
    return { ...row, verdict: row.score >= threshold ? PASS : FAIL, reason: singleArm ? `ran single-arm by design (context.history_file), so no delta: ${scored}` : scored };
  });
}

export function summarize(result, { plugin, base, redact = false, caseYaml = caseYamlReader(result, base) }) {
  const rows = verdicts(result, { redact, caseYaml });
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
      const invoked = slashSkill(c?.promptMarkdown);
      const h = health(runs, { plugin: owner, base, invoked });
      const loaded = h.loaded === null ? "unknown (no kept trace lists skills)" : h.loaded ? "yes" : "no";
      const how = invoked && ownSkill(owner)(invoked) ? `; the prompt slash-invokes ${redact ? "a plugin skill" : cell(invoked)}` : "";
      const fired = h.kept === 0 ? `no kept trace of ${runs.length} runs` : `fired in ${h.fired} of ${h.kept} runs with a kept trace (${runs.length} runs${how})`;
      return `- ${cell(rows[index].name)}: skill loaded: ${loaded}; ${fired}`;
    }),
    "",
  ];
  const result_ = rows.length === 0 || rows.some((r) => r.verdict === NOT_COMPARABLE) ? NOT_COMPARABLE : rows.some((r) => r.verdict === FAIL) ? FAIL : PASS;
  if (rows.length === 0) {
    lines.push("The result holds no case.", "");
  }
  lines.push(`Result: ${result_}`);
  const failing = rows.filter((r) => r.verdict !== PASS).map((r) => `${r.verdict}: ${r.name} (${r.reason})`);
  const message = rows.length === 0 ? "the result holds no case" : failing.join("; ");
  const annotation = result_ === PASS ? "" : `::error title=${property(`Plugin eval verdict: ${owner || "unknown plugin"}`)}::${data(`${result_}. ${message}`)}`;
  return { text: lines.join("\n"), result: result_, annotation };
}

// Workflow-command escaping (GitHub's toolkit command.ts): data escapes %, CR
// and LF; a property also escapes : and ,.
const data = (text) => String(text).replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
const property = (text) => data(text).replace(/:/g, "%3A").replace(/,/g, "%2C");

export function main(args = process.argv.slice(2)) {
  const redact = args.includes("--redact");
  let argv = args.filter((arg) => arg !== "--redact");
  const at = argv.indexOf("--annotation");
  const annotationFile = at === -1 ? null : argv[at + 1];
  if (at !== -1) argv = [...argv.slice(0, at), ...argv.slice(at + 2)];
  const [file, flag, plugin] = argv;
  if (!file || (flag !== undefined && (flag !== "--plugin" || !plugin)) || argv.length > 3 || (at !== -1 && !annotationFile)) {
    console.error("usage: summarize.mjs <results.json> [--plugin <name>] [--redact] [--annotation <file>]");
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
  const { text, result: verdict, annotation } = summarize(result, { plugin, base: dirname(resolve(file)), redact });
  console.log(text);
  if (annotationFile) writeFileSync(annotationFile, annotation ? `${annotation}\n` : "");
  return verdict === PASS ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
