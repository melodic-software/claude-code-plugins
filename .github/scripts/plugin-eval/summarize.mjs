#!/usr/bin/env node
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

export const slashSkill = (prompt) => (typeof prompt === "string" ? (/^\s*\/([A-Za-z0-9][\w.-]*:[A-Za-z0-9][\w.-]*)/.exec(prompt)?.[1] ?? null) : null);

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
    const skills = trace.find((line) => line.type === "system" && line.subtype === "init")?.skills;
    if (Array.isArray(skills)) {
      loaded = loaded === true || skills.some(own);
    }
    const calls = trace
      .filter((line) => line.type === "assistant")
      .flatMap((line) => list(line.message?.content))
      .filter((part) => part?.type === "tool_use");
    const slashed = invoked !== null && own(invoked) && Array.isArray(skills) && skills.includes(invoked);
    const called = calls.some((part) => (part.name === "Skill" ? own(part.input?.skill) : part.name === "Agent" && own(part.input?.subagent_type)));
    if (slashed || called) {
      fired += 1;
    }
  }
  return { kept, loaded, fired };
}

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
    const indicators = list(c?.arms?.with).flatMap((run) => list(run?.graders).filter((g) => g?.scored === false));
    const shown = indicators.length ? indicators.filter((g) => g?.passed === true).length / indicators.length : 1;
    if (row.score >= threshold && shown < threshold) {
      const missed = [...new Set(indicators.filter((g) => g?.passed !== true).map((g) => String(g?.name)))].join(", ");
      return { ...row, verdict: FAIL, reason: `${scored}, but its unscored with-arm graders passed ${fixed(shown)} (${said(missed)})` };
    }
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
  const overall = rows.length === 0 || rows.some((r) => r.verdict === NOT_COMPARABLE) ? NOT_COMPARABLE : rows.some((r) => r.verdict === FAIL) ? FAIL : PASS;
  if (rows.length === 0) {
    lines.push("The result holds no case.", "");
  }
  lines.push(`Result: ${overall}`);
  const failing = rows.filter((r) => r.verdict !== PASS).map((r) => `${r.verdict}: ${r.name} (${r.reason})`);
  const message = rows.length === 0 ? "the result holds no case" : failing.join("; ");
  const annotation = overall === PASS ? "" : `::error title=${property(`Plugin eval verdict: ${owner || "unknown plugin"}`)}::${data(`${overall}. ${message}`)}`;
  return { text: lines.join("\n"), result: overall, annotation };
}

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
