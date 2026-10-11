#!/usr/bin/env bash
# Behavioral tests for the quiz-me report builder: hostile diff and PR text
# renders as inert text, and the page passes the shared validator.
#
#   bash plugins/education/skills/quiz-me/scripts/build-report.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
# test-scope: plugins/education/skills/quiz-me/SKILL.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-report: node not found on PATH" >&2
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
const builderPath = `${dir}/build-report.mjs`;
const { buildReportPage } = await import(pathToFileURL(builderPath).href);
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
  "</details><script>alert(1)</script>",
  "javascript:alert(1)",
  "&lt;already",
];
const model = {
  title: hostile[0],
  ref: hostile[1],
  context: [hostile[2], hostile[3]],
  intuition: hostile[4],
  decisions: [hostile[5]],
  done: hostile[6],
  references: [hostile[7]],
  questions: [
    { question: hostile[0], choices: [hostile[1], hostile[3]], answer: hostile[5], section: "decisions" },
    { question: hostile[2], answer: hostile[4], section: hostile[0] },
  ],
};

const page = buildReportPage(model);
const verdict = validateRenderedPage(page);
check("the builder is deterministic", page === buildReportPage(model));
check("a hostile model still passes the validator", verdict.ok, verdict.failures.join(","));
check("no live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("no live img tag", !page.includes("<img"));
check("no early details close from input", page.split("</details>").length === 2);
check("no href or event-handler attribute", !page.includes("href=") && !/[ \t\r\n]on[a-z]+=/i.test(page.replace(/>[^<]*</g, "><")));
check(
  "every hostile string appears escaped",
  hostile.every((item) => page.includes(escapeHtml(item))),
);
check("backticks pass through as text", page.includes("`${alert(1)}`"));
check("an unknown section anchor renders as escaped text", page.includes(`If missed, reread: ${escapeHtml(hostile[0])}`));
check("a known section anchor renders its name", page.includes("If missed, reread: Decisions"));
check("the answer key is collapsed", /<details>[ \t\r\n]*<summary>Answer key<\/summary>/.test(page));
check("an empty model still validates", validateRenderedPage(buildReportPage({})).ok);

// Authors put the correct answer first; the rendered order must not keep it there.
const firstAuthored = Array.from({ length: 12 }, (_, i) => ({
  question: `question-${i}`,
  choices: [`right-${i}`, `wrong-${i}-a`, `wrong-${i}-b`, `wrong-${i}-c`],
  answer: `right-${i}`,
  section: "done",
}));
const shuffledPage = buildReportPage({ questions: firstAuthored });
const keyPart = shuffledPage.slice(shuffledPage.indexOf("<summary>Answer key</summary>"));
const positions = firstAuthored.map((row, i) => {
  const block = shuffledPage.match(new RegExp(`<p>question-${i}</p><ol>(.*?)</ol>`));
  const rendered = block ? [...block[1].matchAll(/<li>(.*?)<\/li>/g)].map((m) => m[1]) : [];
  check(
    `question ${i} renders every authored choice once`,
    rendered.length === 4 && [...rendered].sort().join() === [...row.choices].sort().join(),
    rendered.join(","),
  );
  const position = rendered.indexOf(row.answer) + 1;
  check(
    `the key for question ${i} names the choice where its answer rendered`,
    keyPart.includes(`<p>Choice ${position}: right-${i}</p>`),
  );
  return position;
});
check("the correct choice is not always rendered first", positions.some((p) => p !== 1), positions.join(","));
check("rebuilding keeps the same choice order", shuffledPage === buildReportPage({ questions: firstAuthored }));
check(
  "a free-answer key renders the answer alone",
  buildReportPage({ questions: [{ question: "q", answer: "free text" }] }).includes("<p>free text</p>"),
);

const source = readFileSync(builderPath, "utf8");
const pageFn = source.slice(source.indexOf("export function buildReportPage"), source.indexOf("function fail"));
const stray = (pageFn.match(/\$\{[^}]+\}/g) ?? []).filter(
  (item) => !/^\$\{(?:e\(|sectionBlocks\(|referenceItems\(|questionItems\(|keyItems\(|CSS)/.test(item),
);
check("the page template interpolates only escaped calls or built fragments", stray.length === 0, stray.join(" "));

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
  skill.includes("build-report.mjs") && skill.includes("Do not hand-write the HTML"),
);

if (failed > 0) process.exit(1);
NODE

echo "build-report: all cases passed"
