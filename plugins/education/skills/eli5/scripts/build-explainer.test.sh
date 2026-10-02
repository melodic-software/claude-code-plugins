#!/usr/bin/env bash
# Behavioral tests for the eli5 explainer builder: hostile repository text
# renders as inert text, and the page passes the shared validator.
#
#   bash plugins/education/skills/eli5/scripts/build-explainer.test.sh
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
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const dir = process.argv[2];
const work = process.argv[3];
const builderPath = `${dir}/build-explainer.mjs`;
const { buildExplainerPage } = await import(pathToFileURL(builderPath).href);
const { escapeHtml, validateRenderedPage } = await import(
  pathToFileURL(`${dir}/../../../lib/html-escape.mjs`).href
);

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
  "</td></tr></table><script>alert(1)</script>",
  "javascript:alert(1)",
  "&lt;already",
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
  terms: [{ term: hostile[0], plain: hostile[1] }],
  sources: [hostile[7], hostile[6]],
};

const page = buildExplainerPage(model);
const verdict = validateRenderedPage(page);
check("the builder is deterministic", page === buildExplainerPage(model));
check("a hostile model still passes the validator", verdict.ok, verdict.failures.join(","));
check("no live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("no live img or svg tag", !page.includes("<img") && !page.includes("<svg"));
check("no href or event-handler attribute", !page.includes("href=") && !/[ \t\n]on[a-z]+=/i.test(page.replace(/>[^<]*</g, "><")));
check(
  "every hostile string appears escaped",
  hostile.every((item) => page.includes(escapeHtml(item))),
);
check("a flow diagram joins its boxes with arrows", page.split('<td class="arrow">').length === 3);
check("a stack diagram uses one row per box", page.includes('<table class="flow stack">'));
check("an unknown diagram kind falls back to a flow", page.split('<table class="flow">').length === 3);
check("an empty model still validates", validateRenderedPage(buildExplainerPage({})).ok);

const cli = spawnSync(process.execPath, [builderPath], { input: JSON.stringify(model), encoding: "utf8" });
check("the CLI emits the same page as the function", cli.status === 0 && cli.stdout === page, cli.stderr);
check("invalid JSON exits 2", spawnSync(process.execPath, [builderPath], { input: "{", encoding: "utf8" }).status === 2);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", spawnSync(process.execPath, [builderPath, "--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", spawnSync(process.execPath, [builderPath, "--check", `${work}/hand.html`]).status === 1);

const skill = readFileSync(`${dir}/../SKILL.md`, "utf8");
check(
  "the skill routes the page through the builder",
  skill.includes("build-explainer.mjs") && skill.includes("Do not hand-write the HTML"),
);

if (failed > 0) process.exit(1);
NODE

echo "build-explainer: all cases passed"
