#!/usr/bin/env bash
# Behavioral tests for the teach codebase-mode lesson builder: hostile
# repository text renders as inert text, the concept meta tag carries the raw
# name escaped, and the page passes the shared validator.
#
#   bash plugins/education/skills/teach/scripts/build-lesson.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-lesson: node not found on PATH" >&2
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
const builderPath = `${dir}/build-lesson.mjs`;
const { buildLessonPage } = await import(pathToFileURL(builderPath).href);
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
  "</ol></section><script>alert(1)</script>",
  "javascript:alert(1)",
  "&lt;already",
  `"><meta http-equiv="refresh" content="0;url=https://example.invalid">`,
];
const model = {
  concept: hostile[8],
  mission: hostile[0],
  teach: [
    {
      heading: hostile[1],
      paragraphs: [hostile[2], hostile[3]],
      citations: [hostile[6], hostile[7]],
      quiz: [{ question: hostile[4], choices: [hostile[5], hostile[0]] }],
    },
  ],
  practice: [hostile[5]],
  practiceQuiz: [{ question: hostile[1] }],
  goDeeper: [hostile[3]],
  citations: [hostile[7]],
};

const page = buildLessonPage(model);
const verdict = validateRenderedPage(page);
check("the builder is deterministic", page === buildLessonPage(model));
check("a hostile model still passes the validator", verdict.ok, verdict.failures.join(","));
check("no live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("no live img tag", !page.includes("<img"));
check("no href or event-handler attribute", !page.includes("href=") && !/\son[a-z]+=/i.test(page.replace(/>[^<]*</g, "><")));
check("no injected meta tag", page.split("<meta ").length === 4);
check(
  "every hostile string appears escaped",
  hostile.every((item) => page.includes(escapeHtml(item))),
);
check(
  "the concept meta tag carries the raw name, escaped",
  page.includes(`<meta name="concept" content="${escapeHtml(hostile[8])}">`),
);
check("exactly one concept meta tag", page.split('<meta name="concept"').length === 2);
check("a plain concept name round-trips", buildLessonPage({ concept: "C++" }).includes('<meta name="concept" content="C++">'));
check("an empty model still validates", validateRenderedPage(buildLessonPage({})).ok);

const cli = spawnSync(process.execPath, [builderPath], { input: JSON.stringify(model), encoding: "utf8" });
check("the CLI emits the same page as the function", cli.status === 0 && cli.stdout === page, cli.stderr);
check("invalid JSON exits 2", spawnSync(process.execPath, [builderPath], { input: "{", encoding: "utf8" }).status === 2);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", spawnSync(process.execPath, [builderPath, "--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", spawnSync(process.execPath, [builderPath, "--check", `${work}/hand.html`]).status === 1);

const lessons = readFileSync(`${dir}/../context/lessons.md`, "utf8");
check(
  "the lessons reference routes codebase lessons through the builder",
  lessons.includes("build-lesson.mjs") && lessons.includes("Do not hand-write the HTML"),
);

if (failed > 0) process.exit(1);
NODE

echo "build-lesson: all cases passed"
