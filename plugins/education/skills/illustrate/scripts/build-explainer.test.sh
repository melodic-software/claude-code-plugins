#!/usr/bin/env bash
# Behavioral tests for the illustrate explainer builder: hostile text reaches
# the page only as JSON data, the page passes the interactive profile, and the
# markdown record carries the same content with no raw HTML.
#
#   bash plugins/education/skills/illustrate/scripts/build-explainer.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-explainer: node not found on PATH" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$SCRIPT_DIR" "$work" <<'NODE'
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const dir = process.argv[2];
const work = process.argv[3];
const builderPath = `${dir}/build-explainer.mjs`;
const { buildExplainerPage, buildExplainerRecord } = await import(pathToFileURL(builderPath).href);
const { validateView } = await import(pathToFileURL(`${dir}/../../../lib/view-builder.mjs`).href);

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    failed += 1;
  }
};

const hostile = [
  "</script><img src=x onerror=alert(1)>",
  `"><script>alert(1)</script>`,
  `'><img src=x onerror=alert(1)>`,
  "`${alert(1)}`",
  `" onmouseover="alert(1)`,
  "</li></ol><script>alert(1)</script>",
  "javascript:alert(1)",
  "<!-- open comment",
  "<svg onload=alert(1)>",
];
const model = {
  title: hostile[0],
  summary: [hostile[1], hostile[2]],
  diagrams: [
    { heading: hostile[3], kind: "flow", steps: [hostile[4], hostile[5], hostile[8]], caption: hostile[6], text: [hostile[7]] },
    { heading: hostile[0], kind: "stack", steps: [hostile[1], hostile[5]], caption: hostile[2] },
    { heading: hostile[4], kind: hostile[0], steps: [hostile[8]] },
  ],
  terms: [{ term: hostile[0], plain: hostile[1] }, { term: "", plain: "dropped" }],
  sources: [hostile[7], hostile[6]],
};

const page = buildExplainerPage(model);
const verdict = validateView(page);
check("the builder is deterministic", page === buildExplainerPage(model));
check("a hostile model passes the interactive profile", verdict.ok, verdict.failures.join(","));
check("the page carries the interactive generator marker", page.includes("rv-gen:view-builder-interactive"));

const block = /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(page); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("the model is carried as one JSON data block", block !== null);
const data = block ? JSON.parse(block[1]) : {};
const markup = block ? page.replace(block[0], "") : page;
check("no hostile string reaches markup outside the data block", hostile.every((item) => !markup.includes(item)));
check("the data block holds no raw less-than sign", block !== null && !block[1].includes("<"));
check("a flow diagram's steps bind to the flow list", data.diagrams?.[0]?.flow?.length === 3 && data.diagrams[0].stack.length === 0);
check("a stack diagram's steps bind to the stack list", data.diagrams?.[1]?.stack?.length === 2 && data.diagrams[1].flow.length === 0);
check("an unknown diagram kind falls back to a flow", data.diagrams?.[2]?.flow?.length === 1);
check("a term with no word is dropped", data.terms?.length === 1);

const seven = ["one", "two", "three", "four", "five", "six", "seven"];
const longFlow = JSON.parse(
  /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec( // portability-ok: embedded node JavaScript regex, not a shell tool pattern
    buildExplainerPage({ diagrams: [{ kind: "flow", steps: seven }, { kind: "flow", steps: seven.slice(0, 4) }] }),
  )[1],
);
check("a flow of 7 steps lands in the vertical list", longFlow.diagrams[0].flowcol?.length === 7 && longFlow.diagrams[0].flow.length === 0);
check("a flow of 4 steps stays on the horizontal list", longFlow.diagrams[1].flow.length === 4 && longFlow.diagrams[1].flowcol?.length === 0);
const css = /<style>([\s\S]*?)<\/style>/.exec(page)?.[1] ?? ""; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const rule = (selector) => new RegExp(`(^|\\n)${selector.replace(".", "\\.")} \\{([^}]*)\\}`).exec(css)?.[2] ?? "";
const flowWraps = [...css.matchAll(/(^|\n)([^{\n]*)\{([^}]*)\}/g)].filter((m) => /\.flow\b/.test(m[2]) && /flex-wrap: wrap/.test(m[3])); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("the horizontal flow never wraps a line", /flex-wrap: nowrap/.test(rule(".flow")) && flowWraps.length === 0, rule(".flow"));
check("the horizontal flow scrolls inside its card", /overflow-x: auto/.test(rule(".flow")));
check("the vertical flow is one step per line", /flex-direction: column/.test(rule(".flowcol")));
const flowRow = /<ol class="flow"[^>]*><li class="step">(.*?)<\/li><\/ol>/.exec(page)?.[1] ?? ""; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const colRow = /<ol class="flowcol"[^>]*><li class="step">(.*?)<\/li><\/ol>/.exec(page)?.[1] ?? ""; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("a flow step's arrow follows its box", flowRow.indexOf("box") >= 0 && flowRow.indexOf("box") < flowRow.indexOf("arrow"), flowRow);
check("a vertical flow step's arrow follows its box", colRow.indexOf("box") >= 0 && colRow.indexOf("box") < colRow.indexOf("arrow"), colRow);
check("the last step of a flow shows no arrow", /\.flow \.step:last-child \.arrow/.test(css) && /\.flowcol \.step:last-child \.arrow/.test(css));
check("an empty vertical flow is hidden", /\.flowcol:empty/.test(css));

const wordy = "Gamma Ray (1996): first band name, dropped after a cease-and-desist";
const capModel = { diagrams: [{ heading: "Albums", steps: ["short", wordy] }, { kind: "stack", steps: [wordy, "x".repeat(60)] }] };
const capData = JSON.parse(/<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(buildExplainerPage(capModel))[1]); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const cut = capData.diagrams[0].flow[1];
check("a long step label is cut to the cap", [...cut].length <= 40 && cut.endsWith("…"), cut);
check("a long step label is cut at a word boundary", wordy.startsWith(cut.slice(0, -1)) && wordy[[...cut].length - 1] === " ", cut);
check("a label with no space is cut hard", capData.diagrams[1].stack[1] === `${"x".repeat(39)}…`, capData.diagrams[1].stack[1]);
check("a short step label is unchanged", capData.diagrams[0].flow[0] === "short");
const capRecord = buildExplainerRecord(capModel);
check("the record carries the cut label", capRecord.includes(cut) && !capRecord.includes(wordy), capRecord);
check("an empty model still validates", validateView(buildExplainerPage({})).ok);

const record = buildExplainerRecord(model);
check("the record is deterministic", record === buildExplainerRecord(model));
check("the record holds no raw HTML", !/<[a-z!/]/i.test(record));
check("the record keeps one section per picture plus words and sources", (record.match(/^## /gm) ?? []).length === 5);
check("a flow step sequence reads with arrows", record.includes(" → "));
check("a stack reads as a list", /^- /m.test(record));

const run = (args, input) => spawnSync(process.execPath, [builderPath, ...args], { input, encoding: "utf8" });
const json = JSON.stringify(model);
const both = run(["--record", `${work}/out/r.md`, "--page", `${work}/views/p.html`], json);
check("the CLI writes the record and the page", both.status === 0, both.stderr);
check("the CLI record matches the function", both.status === 0 && readFileSync(`${work}/out/r.md`, "utf8") === record);
check("the CLI page matches the function", both.status === 0 && readFileSync(`${work}/views/p.html`, "utf8") === page);
check("a model with short labels warns nothing", both.stderr === "", both.stderr);
const capped = run(["--record", `${work}/cap/r.md`, "--page", `${work}/capview/p.html`], JSON.stringify(capModel));
const warnings = capped.stderr.split("\n").filter(Boolean);
check("a cut label still exits 0", capped.status === 0, capped.stderr);
check("the CLI warns once per cut label", warnings.length === 3, capped.stderr);
check(
  "each warning names the diagram and the step",
  ["diagram 1 step 2:", "diagram 2 step 1:", "diagram 2 step 2:"].every((name, n) => (warnings[n] ?? "").includes(name)),
  capped.stderr,
);
const recordOnly = run(["--record", `${work}/only/r.md`], json);
check("--record alone writes only the record", recordOnly.status === 0 && !recordOnly.stdout.includes(".html"));
check("a missing --record exits 2", run(["--page", `${work}/x.html`], json).status === 2);
check("invalid JSON exits 2", run(["--record", `${work}/bad.md`], "{").status === 2);
check("an unknown flag exits 2", run(["--format", "html"], json).status === 2);
const clash = run(["--record", `${work}/d/x.md`, "--page", `${work}/d/x.md`], json);
check("the same file for --page and --record exits 2", clash.status === 2 && !existsSync(`${work}/d/x.md`), clash.stderr);
check("a page beside the record exits 2", run(["--record", `${work}/d/y.md`, "--page", `${work}/d/y.html`], json).status === 2);
const linky = buildExplainerRecord({ title: "![i](https://evil/x.png)", summary: ["[x](javascript:alert(1))"], sources: ["[s](https://evil/)"] });
check("the record carries no markdown link or image syntax", !/(^|[^\\])\[/.test(linky) && !/(^|[^\\])\]/.test(linky), linky);
const parity = buildExplainerRecord({ title: "\\[x\\](javascript:alert(1))" });
check("a backslash in model text cannot cancel a bracket escape", parity.split("\n")[0] === "# \\\\\\[x\\\\\\](javascript:alert(1))", parity);
writeFileSync(`${work}/blocker`, "file");
const unpaired = run(["--record", `${work}/u/r.md`, "--page", `${work}/blocker/sub/p.html`], json);
check("a failed page write leaves no unpaired record", unpaired.status === 2 && !existsSync(`${work}/u/r.md`), unpaired.stderr);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", run(["--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", run(["--check", `${work}/hand.html`]).status === 1);
writeFileSync(`${work}/edited.html`, page.replace("Still unclear", "Edited"));
check("--check flags a page edited after it was built", run(["--check", `${work}/edited.html`]).status === 1);

const skill = readFileSync(`${dir}/../SKILL.md`, "utf8");
check(
  "the skill routes the page through the builder",
  skill.includes("build-explainer.mjs") && skill.includes("Do not hand-write the HTML"),
);
check("the skill states the short-label rule", skill.includes("Step labels are capped at 40 characters."));

if (failed > 0) process.exit(1);
NODE

echo "build-explainer: all cases passed"
