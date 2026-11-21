import { readFileSync } from "node:fs";
import { escapeHtml } from "../lib/html-escape.mjs";

const TAILWIND = "https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js";
const MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js";
export const CSP = `default-src 'none'; script-src 'unsafe-inline' ${TAILWIND} ${MERMAID}; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'`;

export const BANDS = [
  ["Strong", "strong", "badge-strong"],
  ["Worth exploring", "explore", "badge-explore"],
  ["Speculative", "speculative", "badge-speculative"],
];
const CATEGORIES = ["in-process", "local-substitutable", "ports-and-adapters", "mock"];
const TERMS = ["module", "interface", "implementation", "seam", "adapter", "depth", "leverage", "locality"];
const WIN_WORDS = 6;
const ID = /^[a-z0-9-]{1,32}$/;
const MERMAID_LABEL = /^[A-Za-z0-9 _./:-]+$/;
const VERIFIED = /^(?:reproduced|unverified|corrected: [^;]*\S)$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export class DeepeningRecordError extends Error {}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const fail = (at, why) => {
  throw new DeepeningRecordError(`deepening: ${at}: ${why}`);
};

function keys(value, at, required, optional = []) {
  if (!isObject(value)) fail(at, "must be an object");
  for (const key of Object.keys(value)) if (![...required, ...optional].includes(key)) fail(at, `unknown key ${key}`);
  for (const key of required) if (!Object.hasOwn(value, key)) fail(at, `${key} is missing`);
}
function text(value, at) {
  if (typeof value !== "string" || !value.trim()) fail(at, "must be non-empty text");
  return value.trim();
}
function list(value, at, read, { min = 1 } = {}) {
  if (!Array.isArray(value) || value.length < min) fail(at, `must be a list of at least ${min}`);
  return value.map((item, index) => read(item, `${at}[${index}]`));
}
function oneOf(value, at, allowed) {
  if (!allowed.includes(value)) fail(at, `must be one of ${allowed.join(", ")}`);
  return value;
}
function label(value, at) {
  const read = text(value, at);
  if (!MERMAID_LABEL.test(read)) fail(at, "may hold only letters, digits, spaces and _ . / : -");
  return read;
}
function score(value, at) {
  if (!Number.isInteger(value) || value < 0 || value > 10) fail(at, "must be a whole number from 0 to 10");
  return value;
}

function win(value, at) {
  const read = text(value, at);
  const match = /^([a-z]+): (\S.*)$/.exec(read);
  if (!match || !TERMS.includes(match[1])) fail(at, `must be "<term>: <gain>" with a term from ${TERMS.join(", ")}`);
  if (match[2].trim().split(/\s+/).length > WIN_WORDS) fail(at, `the gain holds more than ${WIN_WORDS} words`);
  return { term: match[1], gain: match[2].trim() };
}

function graph(value, at) {
  keys(value, at, ["pattern", "nodes"], ["direction", "edges", "caption"]);
  const nodes = list(value.nodes, `${at}.nodes`, (node, nodeAt) => {
    keys(node, nodeAt, ["id", "label"], ["deep"]);
    if (!ID.test(node.id)) fail(`${nodeAt}.id`, "must match [a-z0-9-]{1,32}");
    if (node.deep !== undefined && typeof node.deep !== "boolean") fail(`${nodeAt}.deep`, "must be true or false");
    return { id: node.id, label: label(node.label, `${nodeAt}.label`), deep: node.deep === true };
  });
  const ids = nodes.map((node) => node.id);
  if (new Set(ids).size !== ids.length) fail(`${at}.nodes`, "repeats a node id");
  const edges = value.edges === undefined ? [] : list(value.edges, `${at}.edges`, (edge, edgeAt) => {
    keys(edge, edgeAt, ["from", "to"], ["label", "dashed", "leak"]);
    for (const end of ["from", "to"]) if (!ids.includes(edge[end])) fail(`${edgeAt}.${end}`, "names no node");
    for (const flag of ["dashed", "leak"]) if (edge[flag] !== undefined && typeof edge[flag] !== "boolean") fail(`${edgeAt}.${flag}`, "must be true or false");
    return {
      from: edge.from,
      to: edge.to,
      label: edge.label === undefined ? null : label(edge.label, `${edgeAt}.label`),
      dashed: edge.dashed === true,
      leak: edge.leak === true,
    };
  }, { min: 0 });
  return { pattern: "graph", direction: value.direction === undefined ? "LR" : oneOf(value.direction, `${at}.direction`, ["LR", "TB"]), nodes, edges };
}

const PATTERNS = {
  graph,
  stack: (value, at) => {
    keys(value, at, ["pattern", "layers"], ["caption"]);
    return { pattern: "stack", layers: list(value.layers, `${at}.layers`, text) };
  },
  bars: (value, at) => {
    keys(value, at, ["pattern", "modules"], ["caption"]);
    return {
      pattern: "bars",
      modules: list(value.modules, `${at}.modules`, (module, moduleAt) => {
        keys(module, moduleAt, ["label", "interface", "implementation"]);
        return { label: text(module.label, `${moduleAt}.label`), interface: score(module.interface, `${moduleAt}.interface`), implementation: score(module.implementation, `${moduleAt}.implementation`) };
      }),
    };
  },
  collapse: (value, at) => {
    keys(value, at, ["pattern", "calls"], ["module", "caption"]);
    return { pattern: "collapse", module: value.module === undefined ? null : text(value.module, `${at}.module`), calls: list(value.calls, `${at}.calls`, text) };
  },
};

function panel(value, at) {
  if (!isObject(value)) fail(at, "must be an object");
  const read = Object.hasOwn(PATTERNS, value.pattern) ? PATTERNS[value.pattern] : fail(`${at}.pattern`, `must be one of ${Object.keys(PATTERNS).join(", ")}`);
  return { ...read(value, at), caption: value.caption === undefined ? null : text(value.caption, `${at}.caption`) };
}

function candidateOf(value, at) {
  if (!isObject(value) || typeof value.id !== "string" || !ID.test(value.id)) fail(`${at}.id`, "must match [a-z0-9-]{1,32}");
  const name = `candidate ${value.id}`;
  keys(value, name, ["id", "title", "recommendation", "category", "problem", "solution", "wins", "verified", "files", "diagram"], ["depends_on", "adr"]);
  keys(value.diagram, `${name}: diagram`, ["before", "after"]);
  const verified = text(value.verified, `${name}: verified`);
  if (!VERIFIED.test(verified)) fail(`${name}: verified`, 'must be "reproduced", "unverified" or "corrected: <one clause>"');
  const wins = list(value.wins, `${name}: wins`, win);
  if (!wins.some(({ term }) => term === "leverage" || term === "locality")) fail(`${name}: wins`, "must hold at least one leverage or locality win");
  return {
    id: value.id,
    title: text(value.title, `${name}: title`),
    recommendation: oneOf(value.recommendation, `${name}: recommendation`, BANDS.map(([word]) => word)),
    category: oneOf(value.category, `${name}: category`, CATEGORIES),
    problem: text(value.problem, `${name}: problem`),
    solution: text(value.solution, `${name}: solution`),
    wins,
    verified,
    files: list(value.files, `${name}: files`, text),
    dependsOn: value.depends_on === undefined ? null : text(value.depends_on, `${name}: depends_on`),
    adr: value.adr === undefined ? null : text(value.adr, `${name}: adr`),
    diagram: { before: panel(value.diagram.before, `${name}: diagram.before`), after: panel(value.diagram.after, `${name}: diagram.after`) },
  };
}

/** The record, read strictly: every part present and non-empty, no unknown key, every reference resolved. */
export function parseDeepening(record) {
  keys(record, "record", ["schema_version", "repo", "date", "verification", "counts", "top", "top_why", "candidates"]);
  if (record.schema_version !== 1) fail("record", "schema_version must be 1");
  if (!DATE.test(record.date)) fail("record: date", "must be YYYY-MM-DD");
  const candidates = list(record.candidates, "record: candidates", candidateOf);
  const ids = candidates.map((candidate) => candidate.id);
  if (new Set(ids).size !== ids.length) fail("record: candidates", "repeat a candidate id");
  for (const candidate of candidates) {
    if (candidate.dependsOn !== null && (!ids.includes(candidate.dependsOn) || candidate.dependsOn === candidate.id)) fail(`candidate ${candidate.id}: depends_on`, "names no other candidate");
  }
  if (!ids.includes(record.top)) fail("record: top", "names no candidate");
  return {
    repo: text(record.repo, "record: repo"),
    date: record.date,
    verification: text(record.verification, "record: verification"),
    counts: list(record.counts, "record: counts", text, { min: 0 }),
    top: record.top,
    topWhy: text(record.top_why, "record: top_why"),
    candidates,
  };
}

/** Mermaid flowchart source for a graph panel: builder ids, quoted labels, leak edges styled by position. */
export function mermaidSource({ direction, nodes, edges }) {
  const id = new Map(nodes.map((node, index) => [node.id, `n${index}`]));
  const arrow = (edge) => `${edge.dashed ? "-.->" : "-->"}${!edge.label ? "" : `|"${edge.label}"|`}`;
  const deep = nodes.filter((node) => node.deep).map((node) => id.get(node.id));
  return [
    `flowchart ${direction}`,
    ...nodes.map((node) => `  ${id.get(node.id)}["${node.label}"]`),
    ...edges.map((edge) => `  ${id.get(edge.from)} ${arrow(edge)} ${id.get(edge.to)}`),
    ...edges.flatMap((edge, index) => (edge.leak ? [`  linkStyle ${index} stroke:#B04A3F,stroke-width:2px;`] : [])),
    ...(deep.length ? ["  classDef deep fill:#141413,color:#FAF9F5,stroke:#141413,stroke-width:3px;", `  class ${deep.join(",")} deep;`] : []),
  ].join("\n");
}


const CHROME = readFileSync(new URL("../reference/html-chrome.html", import.meta.url), "utf8").replace(/\r\n?/g, "\n");
const chromePart = (re, name) => re.exec(CHROME)?.[1] ?? fail("html-chrome.html", `has no ${name}`);
const CHROME_STYLE = chromePart(/<style>\n([\s\S]*?)<\/style>/, "style block");
const CHROME_BAR = chromePart(/^(<div class="rv-bar">.*<\/div>)$/m, "theme toggle");
const CHROME_SCRIPT = chromePart(/<script>\n([\s\S]*?)<\/script>/, "toggle script");
const INLINE_SCRIPT = `${CHROME_SCRIPT}  if (window.mermaid) {
    mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "strict", htmlLabels: false, flowchart: { htmlLabels: false } });
  }
`;
const SCRIPTS = [`<script src="${TAILWIND}"></script>`, `<script src="${MERMAID}"></script>`, `<script>\n${INLINE_SCRIPT}</script>`];

const REPORT_STYLE = `
  :root { --rust: #B04A3F; --amber: #B45309; }
  body { max-width: 1040px; }
  h3 { font-family: var(--serif); font-size: 1.15rem; margin: 0; }
  h4 { font-size: .8rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 0 0 .25rem; }
  header p { margin: .2rem 0; }
  .card, .top { background: var(--panel); border: var(--border); border-radius: var(--radius-panel); padding: 1.25rem 1.5rem; margin: 0 0 2.5rem; display: grid; gap: 1rem; }
  .top { border-width: 3px; }
  .part p, .part ul { margin: 0; }
  .part ul { padding-left: 1.2rem; list-style: disc; }
  .files { font-family: var(--mono); font-size: .85rem; list-style: none; padding-left: 0; }
  .badges { display: flex; gap: .75rem; flex-wrap: wrap; margin: 0; }
  .badge { border-left: 4px solid var(--muted); padding-left: .5rem; font-weight: 600; }
  .badge-strong { border-color: var(--olive); }
  .badge-explore { border-color: var(--amber); }
  .badge-speculative { border-color: var(--muted); }
  .tag { font-family: var(--mono); font-size: .85rem; border: 1px solid var(--muted); border-radius: 6px; padding: 0 .4rem; }
  .adr { border-left: 4px solid var(--amber); padding-left: .75rem; }
  .panels { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
  figure { margin: 0; }
  figcaption { font-size: .85rem; color: var(--muted); margin-bottom: .35rem; }
  .paper { background: var(--white); color: var(--slate); border: 1px solid var(--gray-300); border-radius: var(--radius-row); padding: .75rem; overflow-x: auto; max-height: 360px; }
  .paper pre { margin: 0; font-size: .8rem; }
  .drawn { border: 1px solid var(--gray-300); border-radius: var(--radius-row); padding: .75rem; display: grid; gap: .35rem; }
  .box { border: 1.5px solid var(--muted); border-radius: 4px; padding: .3rem .5rem; font-size: .75rem; text-transform: uppercase; letter-spacing: .05em; }
  .layer { border-left-width: 6px; }
  .deep { background: var(--fg); color: var(--bg); border: 3px solid var(--fg); }
  .nest { border: 1.5px solid var(--muted); border-radius: 4px; padding: .3rem .5rem .5rem; font-size: .75rem; }
  .nest .nest { margin-top: .3rem; }
  .faded { opacity: .6; }
  .bar-row { display: grid; grid-template-columns: 9rem 1fr; gap: .5rem; align-items: center; font-size: .75rem; }
  .bars span { display: block; height: .55rem; border-radius: 2px; margin: .1rem 0; }
  .bar-i { background: var(--clay); }
  .bar-m { background: var(--olive); }
  ${Array.from({ length: 11 }, (_, n) => `.w-${n} { width: ${n * 10}%; }`).join(" ")}
  .seam { border-style: dashed; }
  .leak { color: var(--rust); }
  #index table td:first-child { white-space: nowrap; }
`;

const esc = escapeHtml;
const cardId = (id) => `c-${id}`;
const bandOf = (recommendation) => BANDS.find(([word]) => word === recommendation);
const part = (name, heading, body, extra = "") => `<div class="part${extra}" data-part="${name}"><h4>${esc(heading)}</h4>${body}</div>`;

function drawn(panelData) {
  switch (panelData.pattern) {
    case "graph":
      return `<div class="paper v"><pre class="mermaid">${esc(mermaidSource(panelData))}</pre></div>`;
    case "stack":
      return `<div class="drawn v">${panelData.layers.map((layer) => `<div class="box layer${panelData.layers.length === 1 ? " deep" : ""}">${esc(layer)}</div>`).join("")}</div>`;
    case "bars":
      return `<div class="drawn v">${panelData.modules
        .map((module) => `<div class="bar-row"><span>${esc(module.label)}</span><div class="bars"><span class="bar-i w-${module.interface}"></span><span class="bar-m w-${module.implementation}"></span></div></div>`)
        .join("")}<p class="faded">clay: interface, olive: implementation</p></div>`;
    case "collapse":
      if (panelData.module !== null) {
        return `<div class="drawn v"><div class="box deep">${esc(panelData.module)}<div class="faded">${panelData.calls.map((call) => `<div>${esc(call)}</div>`).join("")}</div></div></div>`;
      }
      return `<div class="drawn v">${panelData.calls.reduceRight((inner, call) => `<div class="nest">${esc(call)}${inner}</div>`, "")}</div>`;
  }
}

function figure(side, panelData) {
  const caption = panelData.caption === null ? side : `${side}: ${panelData.caption}`;
  return `<figure><figcaption>${esc(caption)}</figcaption>${drawn(panelData)}</figure>`;
}

function card(candidate, titles) {
  const [word, , badge] = bandOf(candidate.recommendation);
  const p = (value) => `<p class="v">${esc(value)}</p>`;
  return [
    `<article class="card" id="${cardId(candidate.id)}">`,
    `<h3 class="v" data-part="title">${esc(candidate.title)}</h3>`,
    `<p class="badges" data-part="badges"><span class="badge ${badge}">${esc(word)}</span><span class="tag">${esc(candidate.category)}</span></p>`,
    part("problem", "Problem", p(candidate.problem)),
    part("solution", "Solution", p(candidate.solution)),
    part("diagram", "Before and after", `<div class="panels">${figure("Before", candidate.diagram.before)}${figure("After", candidate.diagram.after)}</div>`),
    part("wins", "Wins", `<ul class="v">${candidate.wins.map(({ term, gain }) => `<li><strong>${esc(term)}:</strong> ${esc(gain)}</li>`).join("")}</ul>`),
    part("verified", "Verified", p(candidate.verified)),
    part("files", "Files", `<ul class="v files">${candidate.files.map((file) => `<li>${esc(file)}</li>`).join("")}</ul>`),
    candidate.dependsOn === null ? "" : part("depends-on", "Depends on", `<p class="v"><a href="#${cardId(candidate.dependsOn)}">${esc(titles.get(candidate.dependsOn))}</a></p>`),
    candidate.adr === null ? "" : part("adr", "Recorded decision", p(candidate.adr), " adr"),
    "</article>",
  ].join("\n");
}

/** The report page for a record parseDeepening read. */
export function renderDeepening(report) {
  const titles = new Map(report.candidates.map((candidate) => [candidate.id, candidate.title]));
  const top = report.candidates.find((candidate) => candidate.id === report.top);
  const tally = BANDS.map(([word]) => `${report.candidates.filter((candidate) => candidate.recommendation === word).length} ${word}`).join(", ");
  const bands = BANDS.map(([word, slug]) => {
    const cards = report.candidates.filter((candidate) => candidate.recommendation === word);
    return cards.length ? `<section class="band" id="band-${slug}">\n<h2>${esc(word)}</h2>\n${cards.map((candidate) => card(candidate, titles)).join("\n")}\n</section>` : "";
  }).filter(Boolean);
  const index = report.candidates
    .map((candidate) => `<tr><td><a href="#${cardId(candidate.id)}">${esc(candidate.title)}</a></td><td><span class="badge ${bandOf(candidate.recommendation)[2]}">${esc(candidate.recommendation)}</span></td><td>${esc(candidate.solution)}</td></tr>`)
    .join("\n");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="${esc(CSP)}">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Deepening review: ${esc(report.repo)}</title>
<style>
${CHROME_STYLE}${REPORT_STYLE}</style>
${SCRIPTS[0]}
${SCRIPTS[1]}
</head>
<body>
${CHROME_BAR}
<main>
<header>
<h1>Deepening review: ${esc(report.repo)}</h1>
<p>${esc(report.date)}</p>
<p>Legend: a dark, heavy-bordered box is a deep module; a plain box is any other module; a dashed line is a seam; a rust-colored arrow is leakage.</p>
${report.counts.length ? `<p>Evidence: ${esc(report.counts.join(" · "))}</p>\n` : ""}<p>Candidates: ${report.candidates.length} (${esc(tally)})</p>
<p>Verification: ${esc(report.verification)}</p>
</header>
<section id="top-recommendation">
<h2>Top recommendation</h2>
<article class="top"><h3><a href="#${cardId(top.id)}">${esc(top.title)}</a></h3><p>${esc(report.topWhy)}</p></article>
</section>
<section id="index">
<h2>Every candidate</h2>
<table>
<thead><tr><th>Candidate</th><th>Badge</th><th>Solution</th></tr></thead>
<tbody>
${index}
</tbody>
</table>
</section>
<section id="candidates">
${bands.join("\n")}
</section>
</main>
${SCRIPTS[2]}
</body>
</html>
`;
}


const TAGS = new Set([
  "html", "head", "meta", "title", "style", "body", "main", "header", "section", "article", "nav",
  "h1", "h2", "h3", "h4", "p", "ul", "li", "a", "div", "span", "pre", "strong", "figure", "figcaption",
  "table", "thead", "tbody", "tr", "th", "td", "button",
]);
const ATTRS = new Set(["lang", "charset", "http-equiv", "content", "name", "class", "id", "href", "role", "type", "aria-label", "aria-pressed", "data-rv-theme", "data-part"]);
const ESCAPED_TEXT = /^(?:[^&<>"']|&(?:amp|lt|gt|quot|#x27);)*$/;
const TOKEN = /^[a-z0-9-]{1,40}$/;
const MERMAID_TEXT = /^[A-Za-z0-9 _./:\-"\n[\]|>;,#]*$/;
const unescape = (value) => value.replaceAll("&quot;", '"').replaceAll("&#x27;", "'").replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");

/** @returns {{ ok: boolean, failures: string[] }} */
export function validateDeepeningPage(html) {
  const failures = [];
  const page = html.replace(/\r\n?/g, "\n");
  const head = `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta http-equiv="Content-Security-Policy" content="${esc(CSP)}">\n`;
  if (!page.startsWith(head)) failures.push("csp");
  let rest = page;
  for (const script of SCRIPTS) {
    if (rest.split(script).length !== 2) failures.push("script-set");
    rest = rest.replace(script, "");
  }
  if (/<script|<\/script/i.test(rest)) failures.push("script-extra");
  const styles = [...rest.matchAll(/<style\b[^>]*>([\s\S]*?)(?:<\/style[\s/>]|$)/gi)];
  if (styles.length !== 1 || /url\(|@import|expression\(|\\/i.test(styles[0][1])) failures.push("style");
  rest = rest.replace(/<style>[\s\S]*?<\/style>/, "");
  for (const [, body] of rest.matchAll(/<pre class="mermaid">([^<]*)<\/pre>/g)) {
    if (!MERMAID_TEXT.test(unescape(body)) || !/^flowchart (LR|TB)\n/.test(unescape(body))) failures.push("mermaid-source");
  }
  for (const match of rest.matchAll(/<\/?([A-Za-z][A-Za-z0-9]*)\b([^>]*)>/g)) {
    const tag = match[1].toLowerCase();
    if (!TAGS.has(tag)) failures.push(`tag:${tag}`);
    if (match[0].startsWith("</")) continue;
    for (const attr of match[2].matchAll(/([^\s"'>=/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g)) {
      const [name, value] = [attr[1].toLowerCase(), attr[2] ?? attr[3] ?? attr[4] ?? ""];
      if (!ATTRS.has(name)) failures.push(`attr:${name}`);
      if (!ESCAPED_TEXT.test(value)) failures.push("unescaped");
      if (name === "href" && !(value.startsWith("#") && TOKEN.test(value.slice(1)))) failures.push("href");
      if ((name === "id" || name === "data-part") && !TOKEN.test(value)) failures.push(`opaque:${name}`);
      if (name === "http-equiv" && value !== "Content-Security-Policy") failures.push("http-equiv");
    }
  }
  const textLeft = rest.replace(/<!doctype html>/i, "").replace(/<\/?[A-Za-z][A-Za-z0-9]*\b[^>]*>/g, "");
  if (textLeft.includes("<") || !ESCAPED_TEXT.test(textLeft)) failures.push("unescaped");
  return { ok: failures.length === 0, failures: [...new Set(failures)] };
}
