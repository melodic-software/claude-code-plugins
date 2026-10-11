#!/usr/bin/env bash
# Behavioral tests for the bounded-context view builder: hostile board text
# (sticky content, persona names, evidence) renders as inert text, and the page
# passes the shared validator.
#
#   bash plugins/event-storming/skills/simulation/scripts/build-bc-view.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
# test-scope: plugins/event-storming/skills/simulation/SKILL.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-bc-view: node not found on PATH" >&2
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
const builderPath = `${dir}/build-bc-view.mjs`;
const { buildBoundedContextPage } = await import(pathToFileURL(builderPath).href);
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
  "</title><style>@import 'x'</style>",
  "javascript:alert(1)",
  "&lt;already",
];
const model = {
  title: hostile[0],
  board: hostile[1],
  contexts: [
    { name: hostile[2], events: [hostile[3], hostile[4]], personas: [hostile[5]], evidence: hostile[6] },
    { name: hostile[7], events: [hostile[0]], personas: [hostile[1], hostile[2]], evidence: hostile[3] },
  ],
  target: hostile[4],
};

const page = buildBoundedContextPage(model);
const verdict = validateRenderedPage(page);
check("the builder is deterministic", page === buildBoundedContextPage(model));
check("a hostile model still passes the validator", verdict.ok, verdict.failures.join(","));
check("no live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("no live img tag", !page.includes("<img"));
check("no href or event-handler attribute", !page.includes("href=") && !/\son[a-z]+=/i.test(page.replace(/>[^<]*</g, "><"))); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check(
  "every hostile string appears escaped",
  hostile.every((item) => page.includes(escapeHtml(item))),
);
check("backticks pass through as text", page.includes("`${alert(1)}`"));
check("an empty model still validates", validateRenderedPage(buildBoundedContextPage({})).ok);
check(
  "a malformed model still validates",
  validateRenderedPage(
    buildBoundedContextPage({ title: { a: 1 }, contexts: [{ events: "x", personas: 3 }, 5, null], target: [1] }),
  ).ok,
);

const cli = spawnSync(process.execPath, [builderPath], { input: JSON.stringify(model), encoding: "utf8" });
check("the CLI emits the same page as the function", cli.status === 0 && cli.stdout === page, cli.stderr);
check("invalid JSON exits 2", spawnSync(process.execPath, [builderPath], { input: "{", encoding: "utf8" }).status === 2);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", spawnSync(process.execPath, [builderPath, "--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", spawnSync(process.execPath, [builderPath, "--check", `${work}/hand.html`]).status === 1);

const source = readFileSync(builderPath, "utf8");
const pageFn = source.slice(source.indexOf("export function buildBoundedContextPage"), source.indexOf("function fail"));
const stray = (pageFn.match(/\$\{[^}]+\}/g) ?? []).filter((item) => !/^\$\{(?:e\(|CSS|contextRows\()/.test(item));
check("the page template interpolates only escaped calls or built fragments", stray.length === 0, stray.join(" "));

const skill = readFileSync(`${dir}/../SKILL.md`, "utf8");
check(
  "the lane routes the page through the builder",
  skill.includes("build-bc-view.mjs") && skill.includes("Do not hand-write the HTML"),
);

if (failed > 0) process.exit(1);
NODE

echo "build-bc-view: all cases passed"
