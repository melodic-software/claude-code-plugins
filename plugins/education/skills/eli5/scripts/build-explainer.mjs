#!/usr/bin/env node
// Build the eli5 explainer page: a one-line answer, then a series of small
// diagrams, each with a caption that states what to conclude from it.
//
// Every interpolated field goes through escapeHtml from the synced helper. A
// diagram is a flow (boxes joined by arrows) or a stack (boxes one above the
// next), drawn as a table, so no diagram needs markup the validator refuses.
// The page has no script, image, or link.

import { asText, e, pageShell, paragraphs, rows, runCli, textList } from "../../../lib/page-kit.mjs";

const KINDS = new Set(["flow", "stack"]);

function flowTable(steps) {
  const cells = steps.map((step) => `<td>${e(step)}</td>`).join('<td class="arrow">→</td>');
  return `<table class="flow"><tbody><tr>${cells}</tr></tbody></table>`;
}

function stackTable(steps) {
  return `<table class="flow stack"><tbody>${steps.map((step) => `<tr><td>${e(step)}</td></tr>`).join("")}</tbody></table>`;
}

function diagramBlock(diagram) {
  const steps = textList(diagram.steps);
  const kind = KINDS.has(asText(diagram.kind)) ? asText(diagram.kind) : "flow";
  const table = steps.length === 0 ? "" : kind === "stack" ? stackTable(steps) : flowTable(steps);
  const caption = asText(diagram.caption) === "" ? "" : `<p class="caption">${e(diagram.caption)}</p>`;
  return `<section>\n<h2>${e(diagram.heading)}</h2>\n${table}\n${caption}\n${paragraphs(diagram.text)}\n</section>`;
}

function termsBlock(terms) {
  const items = rows(terms).filter((row) => asText(row.term) !== "");
  if (items.length === 0) return "";
  const body = items.map((row) => `<tr><th>${e(row.term)}</th><td>${e(row.plain)}</td></tr>`).join("");
  return `<section>\n<h2>Words used here</h2>\n<table><tbody>${body}</tbody></table>\n</section>`;
}

function sourcesBlock(sources) {
  const items = textList(sources);
  if (items.length === 0) return "";
  return `<section>\n<h2>Where this came from</h2>\n<ol>${items.map((item) => `<li><code>${e(item)}</code></li>`).join("")}</ol>\n</section>`;
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string}
 */
export function buildExplainerPage(model) {
  const source = model && typeof model === "object" ? model : {};
  const title = asText(source.title) || "Explainer";
  const body = `<h1>${e(title)}</h1>
${paragraphs(source.summary)}
${rows(source.diagrams).map(diagramBlock).join("\n")}
${termsBlock(source.terms)}
${sourcesBlock(source.sources)}`;
  return pageShell(title, body);
}

runCli(import.meta.url, "build-explainer", buildExplainerPage);
