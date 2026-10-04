#!/usr/bin/env node
// Build the quiz-me report page: what was done, then the quiz, then the
// answer key collapsed in a details element.
//
// Every interpolated field goes through escapeHtml from the synced helper.
// The page is self-contained: inline style, no script, no image, no link.
// stampPage adds the generator marker. validateRenderedPage refuses a page
// this builder would not accept, including its own output if a template edit
// breaks the allowlist.

import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  escapeHtml,
  stampPage,
  validateRenderedPage,
} from "../../../lib/html-escape.mjs";

const CSS = `
:root {
  --ivory: #faf9f5;
  --slate: #141413;
  --clay-deep: #a0512e;
  --gray-300: #d1cfc5;
  --gray-500: #87867f;
  --serif: ui-serif, Georgia, serif;
  --sans: system-ui, sans-serif;
  --mono: ui-monospace, monospace;
  --bg: var(--ivory);
  --fg: var(--slate);
  --muted: var(--gray-500);
  --focus: var(--clay-deep);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: var(--slate);
    --fg: var(--ivory);
    --muted: var(--gray-300);
    --focus: #e89b7e;
  }
}
@media (prefers-reduced-motion: reduce) {
  * { animation: none !important; transition: none !important; }
}
html { color-scheme: light dark; }
body {
  margin: 0 auto;
  max-width: 860px;
  padding: 2rem 1.25rem 4rem;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--sans);
  line-height: 1.55;
}
h1, h2, h3 { font-family: var(--serif); font-weight: 600; }
summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; border-radius: 2px; }
summary { cursor: pointer; font-weight: 600; }
code { font-family: var(--mono); }
.muted { color: var(--muted); }
`.trim();

const SECTIONS = [
  ["context", "Context"],
  ["intuition", "Intuition"],
  ["decisions", "Decisions"],
  ["done", "What was done"],
];
const SECTION_NAMES = new Map(SECTIONS);

function asText(value) {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

function asList(value) {
  return Array.isArray(value) ? value : [];
}

function e(value) {
  return escapeHtml(asText(value));
}

function paragraphs(value) {
  const items = (Array.isArray(value) ? value : [value])
    .map((item) => asText(item))
    .filter((item) => item !== "");
  if (items.length === 0) return "<p>None.</p>";
  return items.map((item) => `<p>${e(item)}</p>`).join("\n");
}

function sectionBlocks(source) {
  return SECTIONS.map(
    ([id, name]) => `<section id="${id}">\n<h2>${name}</h2>\n${paragraphs(source[id])}\n</section>`,
  ).join("\n");
}

function sectionName(id) {
  return SECTION_NAMES.get(asText(id)) ?? "";
}

function questionRows(source) {
  return asList(source.questions).filter((row) => row && typeof row === "object");
}

// Authors tend to write the correct choice first, and an instruction does not
// stop it, so the builder orders choices itself. The seed comes from the
// question's own text, so rebuilding the same model gives the same page.
function seededRandom(text) {
  let state = 2166136261;
  for (const char of text) state = Math.imul(state ^ char.codePointAt(0), 16777619);
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function choicesOf(row) {
  const choices = asList(row.choices)
    .map((item) => asText(item))
    .filter((item) => item !== "");
  const random = seededRandom(JSON.stringify([asText(row.question), choices]));
  for (let i = choices.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [choices[i], choices[j]] = [choices[j], choices[i]];
  }
  return choices;
}

function questionItems(questions) {
  if (questions.length === 0) return "<li>None.</li>";
  return questions
    .map((row) => {
      const choices = choicesOf(row);
      const choiceList =
        choices.length === 0 ? "" : `<ol>${choices.map((item) => `<li>${e(item)}</li>`).join("")}</ol>`;
      return `<li><p>${e(row.question)}</p>${choiceList}</li>`;
    })
    .join("\n");
}

function keyAnswer(row) {
  const position = choicesOf(row).indexOf(asText(row.answer)) + 1;
  return position === 0 ? e(row.answer) : `Choice ${position}: ${e(row.answer)}`;
}

function keyItems(questions) {
  if (questions.length === 0) return "<li>None.</li>";
  return questions
    .map(
      (row) =>
        `<li><p>${keyAnswer(row)}</p><p class="muted">If missed, reread: ${e(sectionName(row.section) || row.section)}</p></li>`,
    )
    .join("\n");
}

function referenceItems(source) {
  const items = asList(source.references)
    .map((item) => asText(item))
    .filter((item) => item !== "");
  if (items.length === 0) return "";
  return `<h2 id="references">References</h2>\n<ol>${items
    .map((item) => `<li><code>${e(item)}</code></li>`)
    .join("")}</ol>`;
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string}
 */
export function buildReportPage(model) {
  const source = model && typeof model === "object" ? model : {};
  const title = asText(source.title) || "Change report";
  const questions = questionRows(source);
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${e(title)}</title>
<style>
${CSS}
</style>
</head>
<body>
<p class="muted">Quiz-me report</p>
<h1>${e(title)}</h1>
<p class="muted">${e(source.ref)}</p>
${sectionBlocks(source)}
${referenceItems(source)}
<h2 id="quiz">Quiz</h2>
<p>Answer each question in the conversation before opening the key.</p>
<ol>
${questionItems(questions)}
</ol>
<details>
<summary>Answer key</summary>
<ol>
${keyItems(questions)}
</ol>
</details>
</body>
</html>
`;
  return stampPage(html);
}

function fail(message, code) {
  process.stderr.write(`build-report: ${message}\n`);
  process.exit(code);
}

function runCheck(path) {
  let html;
  try {
    html = readFileSync(path, "utf8");
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error), 2);
  }
  const verdict = validateRenderedPage(html);
  if (!verdict.ok) fail(verdict.failures.join(","), 1);
}

function runBuild() {
  let model;
  try {
    model = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${error instanceof Error ? error.message : String(error)})`, 2);
  }
  if (!model || typeof model !== "object" || Array.isArray(model)) {
    fail("JSON root must be an object", 2);
  }
  const page = buildReportPage(model);
  const verdict = validateRenderedPage(page);
  if (!verdict.ok) fail(`refused to emit (${verdict.failures.join(",")})`, 1);
  process.stdout.write(page);
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === "--check") {
    if (!args[1]) fail("usage: build-report.mjs --check <file>", 2);
    runCheck(args[1]);
    return;
  }
  if (args.length > 0) fail("usage: build-report.mjs [< model.json] | --check <file>", 2);
  runBuild();
}

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  try {
    return realpathSync(arg) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (invokedDirectly()) {
  main();
}
