import { readFileSync } from "node:fs";
import { escapeHtml } from "../lib/html-escape.mjs";

const TAILWIND = "https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js";
const MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js";
const TAILWIND_SRI = "sha256-LQdTYZ03u0RSdhuHT/xq5kKengUesm9ExayDxzYvx7E=";
const MERMAID_SRI = "sha256-M234A9h6OLcKAec25mbI92AdLOQvXkfI+v5dchB0uaM=";
export const CSP = `default-src 'none'; script-src 'unsafe-inline' ${TAILWIND} ${MERMAID}; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'`;

export const BANDS = [
  ["Strong", "strong", "badge-strong"],
  ["Worth exploring", "explore", "badge-explore"],
  ["Speculative", "speculative", "badge-speculative"],
];
const BAND_MEANING = {
  Strong: "passes the deletion test (a maintainer who found the module gone would rebuild it much the same way) and the two-adapter rule (a seam earns its place only with two real adapters, typically production and test); its signal was reproduced unless marked unverified",
  "Worth exploring": "likely worth doing; the evidence does not yet carry Strong",
  Speculative: "rests on judgment, or on a seam with only one adapter",
};
const CATEGORY_MEANING = {
  "in-process": "a test calls the deepened module directly; no I/O, nothing to substitute",
  "local-substitutable": "a test runs the module against a stand-in started locally, such as an embedded database",
  "ports-and-adapters": "a test plugs an in-memory adapter into a port, where production plugs in a client for a service the organization runs",
  mock: "a test passes a mock adapter for a third-party service through a port",
};
const CATEGORIES = Object.keys(CATEGORY_MEANING);
const TERM_MEANING = {
  module: "whatever a finding is about, at any size, from a function to a package",
  interface: "everything a caller has to get right to use the module",
  implementation: "the lines and logic a module carries",
  seam: "where one adapter comes out and another goes in with no edit at that spot",
  adapter: "the code plugged in at a seam",
  depth: "what a caller gets back for what the interface makes it learn",
  leverage: "the callers' share of depth: many callers, one interface, one test suite",
  locality: "the maintainers' share of depth: a fix and its test stay inside one module",
};
const TERMS = Object.keys(TERM_MEANING);
const VERIFIED_MEANING = {
  reproduced: "checked against the code; it held as stated",
  corrected: "checked against the code; it held after the correction shown",
  unverified: "not checked against the code",
};
const LEVEL_MEANING = {
  strict: "every Strong candidate and every live-defect or dead-code claim was checked against the code, and held as stated or after the correction shown",
  standard: "every Strong candidate and every live-defect or dead-code claim was checked against the code, and held as stated or after the correction shown",
  light: "nothing was reproduced; claims stand as the scan reported them",
  off: "nothing was reproduced; claims stand as the scan reported them",
};
const WIN_WORDS = 6;
const ID = /^[a-z0-9-]{1,32}$/;
const MERMAID_LABEL = /^[A-Za-z0-9 _./:-]+$/;
const VERIFIED = /^(?:reproduced|unverified|corrected: [^;]*\S)$/;
const LEVEL = /^(off|light|standard|strict)\b/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const COMMIT = /^[0-9a-f]{7,40}$/;

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
  if (!VERIFIED.test(verified)) fail(`${name}: verified`, 'must be "reproduced", "unverified" or "corrected: <one clause, with no semicolon>"');
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
  keys(record, "record", ["schema_version", "repo", "scope", "commit", "date", "verification", "counts", "top", "top_why", "candidates"], ["kept"]);
  if (record.schema_version !== 1) fail("record", "schema_version must be 1");
  if (!DATE.test(record.date)) fail("record: date", "must be YYYY-MM-DD");
  if (typeof record.commit !== "string" || !COMMIT.test(record.commit)) fail("record: commit", "must be the scanned commit's SHA, 7 to 40 lowercase hex digits");
  const verification = text(record.verification, "record: verification");
  if (!LEVEL.test(verification)) fail("record: verification", "must start with off, light, standard or strict");
  const candidates = list(record.candidates, "record: candidates", candidateOf);
  const ids = candidates.map((candidate) => candidate.id);
  if (new Set(ids).size !== ids.length) fail("record: candidates", "repeat a candidate id");
  for (const candidate of candidates) {
    if (candidate.dependsOn !== null && (!ids.includes(candidate.dependsOn) || candidate.dependsOn === candidate.id)) fail(`candidate ${candidate.id}: depends_on`, "names no other candidate");
  }
  if (!ids.includes(record.top)) fail("record: top", "names no candidate");
  return {
    repo: text(record.repo, "record: repo"),
    scope: text(record.scope, "record: scope"),
    commit: record.commit,
    date: record.date,
    verification,
    level: LEVEL.exec(verification)[1],
    counts: list(record.counts, "record: counts", text, { min: 0 }),
    top: record.top,
    topWhy: text(record.top_why, "record: top_why"),
    candidates,
    kept: record.kept === undefined ? [] : list(record.kept, "record: kept", (item, at) => {
      keys(item, at, ["title", "reason", "files"]);
      return { title: text(item.title, `${at}.title`), reason: text(item.reason, `${at}.reason`), files: list(item.files, `${at}.files`, text) };
    }, { min: 0 }),
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
    document.documentElement.classList.add("rv-mermaid");
    mermaid.initialize({ startOnLoad: false, theme: "neutral", securityLevel: "strict", htmlLabels: false, flowchart: { htmlLabels: false, useMaxWidth: false, wrappingWidth: 260 } });
  }
  (function () {
    var cards = Array.prototype.slice.call(document.querySelectorAll("article.card"));
    var main = document.getElementById("candidates");
    if (!cards.length || !main) { return; }
    var top = document.getElementById("top-recommendation");
    var kept = document.getElementById("kept");
    var panes = kept ? cards.concat([kept]) : cards;
    var current = cards.filter(function (card) { return !card.hidden; })[0] || cards[0];
    var topCard = current;
    function show(id, how) {
      var target = document.getElementById(id);
      var at = panes.indexOf(target);
      if (at < 0) { return false; }
      panes.forEach(function (pane) { pane.hidden = pane !== target; });
      var pending = target.querySelectorAll("pre.mermaid:not([data-processed])");
      if (window.mermaid && pending.length) { mermaid.run({ nodes: Array.prototype.slice.call(pending) }); }
      top.hidden = target !== topCard;
      document.querySelectorAll(".reader-item, .reader-kept").forEach(function (link) {
        if (link.getAttribute("href") === "#" + id) { link.setAttribute("aria-current", "true"); } else { link.removeAttribute("aria-current"); }
      });
      document.querySelectorAll(".reader-pos").forEach(function (pos) {
        pos.textContent = target === kept ? "Looked at, no change" : (at + 1) + " of " + cards.length;
      });
      document.querySelectorAll("[data-step]").forEach(function (button) {
        var to = at + Number(button.getAttribute("data-step"));
        button.disabled = to < 0 || to >= panes.length;
      });
      current = target;
      var box = main.getBoundingClientRect();
      if (how && (box.top < 0 || box.top > window.innerHeight)) { main.scrollIntoView({ block: "start" }); }
      if (how === "link") { target.focus({ preventScroll: true }); }
      return true;
    }
    var zoom = document.getElementById("zoom");
    var opener = null;
    function enlarge(figure) {
      var button = figure.querySelector(".zoom-open");
      zoom.querySelector(".zoom-body").replaceChildren(figure.querySelector(".v").cloneNode(true));
      var title = button.getAttribute("aria-label").replace(/^Enlarge the /, "");
      document.getElementById("zoom-title").textContent = title.charAt(0).toUpperCase() + title.slice(1);
      opener = button;
      zoom.showModal();
    }
    zoom.addEventListener("click", function (event) {
      if (event.target === zoom || event.target.closest("[data-zoom-close]")) { zoom.close(); }
    });
    zoom.addEventListener("close", function () {
      if (opener) { opener.focus(); }
    });
    document.addEventListener("click", function (event) {
      if (!event.target.closest || zoom.contains(event.target)) { return; }
      var link = event.target.closest('a[href^="#"]');
      if (link) {
        var href = link.getAttribute("href");
        if (show(href.slice(1), "link")) { event.preventDefault(); history.pushState(null, "", href); }
        return;
      }
      var step = event.target.closest("[data-step]");
      if (step) {
        var next = panes[panes.indexOf(current) + Number(step.getAttribute("data-step"))];
        if (next && show(next.id, "step")) { history.replaceState(null, "", "#" + next.id); }
        return;
      }
      var figure = event.target.closest("[data-enlarge]");
      if (figure) { enlarge(figure); }
    });
    window.addEventListener("popstate", function () { show(location.hash.slice(1) || topCard.id, ""); });
    show(location.hash && document.getElementById(location.hash.slice(1)) ? location.hash.slice(1) : topCard.id, "");
  })();
`;
const SCRIPTS = [
  `<script src="${TAILWIND}" integrity="${TAILWIND_SRI}" crossorigin="anonymous"></script>`,
  `<script src="${MERMAID}" integrity="${MERMAID_SRI}" crossorigin="anonymous"></script>`,
  `<script>\n${INLINE_SCRIPT}</script>`,
];

const REPORT_STYLE = `
  :root { --amber: #B45309; --muted: #6B6A64; }
  body { max-width: 1360px; }
  [hidden] { display: none !important; }
  h3 { font-family: var(--serif); font-size: 1.15rem; margin: 0; }
  h4 { font-size: .8rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 0 0 .25rem; }
  header p { margin: .2rem 0; }
  header, .files { overflow-wrap: anywhere; }
  .cid { font-family: var(--mono); font-size: .85em; color: var(--muted); }
  .key summary { cursor: pointer; font-weight: 600; margin-top: .5rem; }
  .built-on { margin: 0; padding-left: 1.2rem; list-style: disc; }
  .back { margin: 0; font-size: .85rem; }
  .kept-item { border-left: 4px solid var(--muted); padding: .25rem 0 .25rem .9rem; margin: 0 0 1.25rem; display: grid; gap: .35rem; }
  .kept-item p, .kept-item ul { margin: 0; }
  .legend { margin: .75rem 0 0; padding-left: 1.2rem; list-style: disc; font-size: .92rem; }
  .reader { display: grid; grid-template-columns: minmax(15rem, 21rem) minmax(0, 1fr); gap: 2rem; align-items: start; margin-top: 1.5rem; }
  .reader-nav { position: sticky; top: .5rem; max-height: calc(100vh - 1rem); overflow-y: auto; padding-right: .25rem; }
  .reader-nav h2 { margin-top: 0; }
  .reader-list { list-style: none; margin: 0; padding: 0; display: grid; gap: .2rem; }
  .reader-band { font-size: .75rem; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); font-weight: 600; margin-top: .8rem; }
  .reader-item { display: grid; gap: .2rem; padding: .45rem .6rem; border: 1px solid transparent; border-radius: var(--radius-row); color: var(--fg); text-decoration: none; }
  .reader-item:hover { border-color: var(--gray-300); }
  .reader-item[aria-current=true] { background: var(--panel); border-color: var(--fg); }
  .reader-title { font-weight: 600; font-size: .9rem; overflow-wrap: anywhere; }
  .reader-meta { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; font-size: .78rem; }
  .reader-solution { font-size: .8rem; color: var(--muted); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .top-chip { font-weight: 600; border: 1px solid var(--fg); border-radius: 999px; padding: 0 .45rem; }
  .reader-kept { display: block; margin-top: 1rem; font-weight: 600; }
  .reader-main { min-width: 0; display: grid; grid-template-columns: minmax(0, 1fr); gap: 1rem; }
  .reader-step { display: flex; justify-content: space-between; align-items: center; gap: 1rem; }
  .reader-step button, .zoom-head button, .zoom-open { font: inherit; font-size: .9rem; padding: .35rem .8rem; border: 1px solid var(--muted); border-radius: 6px; background: transparent; color: var(--fg); cursor: pointer; }
  .reader-step button:disabled { opacity: .45; cursor: default; }
  .reader-pos { margin: 0; color: var(--muted); font-size: .9rem; white-space: nowrap; }
  .card, .top { background: var(--panel); border: var(--border); border-radius: var(--radius-panel); padding: 1.25rem 1.5rem; margin: 0; display: grid; grid-template-columns: minmax(0, 1fr); gap: 1rem; }
  .top { border-width: 3px; gap: .5rem; }
  .top h2, #kept h2 { margin: 0; }
  .top p { margin: 0; }
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
  .panels { display: flex; flex-wrap: wrap; gap: 1rem; }
  figure { margin: 0; flex: 1 1 18rem; min-width: 0; cursor: zoom-in; }
  figure.graph { flex: 1 1 auto; }
  figcaption { display: flex; justify-content: space-between; align-items: baseline; gap: .5rem; font-size: .85rem; color: var(--muted); margin-bottom: .35rem; }
  .zoom-open { font-size: .8rem; padding: .1rem .5rem; cursor: zoom-in; }
  .paper { background: var(--white); color: var(--slate); border: 1px solid var(--gray-300); border-radius: var(--radius-row); padding: .75rem; width: fit-content; max-width: 100%; box-sizing: border-box; }
  .paper svg { display: block; max-width: 100%; height: auto; }
  pre.mermaid { display: none; margin: 0; }
  .rv-mermaid pre.mermaid { display: block; }
  .rv-mermaid .edge-list { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  .edge-list { margin: 0; padding-left: 1.1rem; font-size: .85rem; }
  .drawn { background: var(--white); color: var(--slate); border: 1px solid var(--gray-300); border-radius: var(--radius-row); padding: .75rem; display: grid; gap: .35rem; }
  .drawn .box, .drawn .nest { border-color: #87867F; }
  .drawn .deep { border-color: #141413; }
  .drawn.boxes { display: flex; flex-wrap: wrap; }
  .box { border: 1.5px solid var(--muted); border-radius: 4px; padding: .3rem .5rem; font-size: .8rem; }
  .layer { border-left-width: 6px; }
  .deep { background: #141413; color: #FAF9F5; border: 3px solid #141413; }
  .nest { border: 1.5px solid var(--muted); border-radius: 4px; padding: .3rem .5rem .5rem; font-size: .75rem; }
  .nest .nest { margin-top: .3rem; }
  .faded { opacity: .6; }
  .zoom { width: min(96vw, 1600px); max-width: none; max-height: 92vh; margin: auto; padding: 0; border: var(--border); border-radius: var(--radius-panel); background: var(--panel); color: var(--fg); }
  .zoom::backdrop { background: rgb(20 20 19 / .6); }
  .zoom-head { display: flex; justify-content: space-between; align-items: center; gap: 1rem; padding: .75rem 1rem; border-bottom: var(--border); }
  .zoom-head h2 { margin: 0; padding: 0; border: 0; font-size: 1rem; }
  .zoom-body { padding: 1.25rem; overflow: auto; max-height: calc(92vh - 4rem); box-sizing: border-box; }
  .zoom-body .paper { width: auto; }
  .zoom-body svg { width: 100% !important; max-width: none !important; height: auto !important; max-height: calc(92vh - 9rem); }
  .zoom-body .box, .zoom-body .nest { font-size: 1.15rem; }
  @media (max-width: 900px) {
    .reader { grid-template-columns: minmax(0, 1fr); }
    .reader-nav { position: static; max-height: none; overflow: visible; }
  }
  @media (max-width: 600px) {
    .card, .top { padding: 1rem; }
    .paper { overflow-x: auto; }
    .paper svg { max-width: none; }
  }
`;

const esc = escapeHtml;
const cardId = (id) => `c-${id}`;
const bandOf = (recommendation) => BANDS.find(([word]) => word === recommendation);
const part = (name, heading, body, extra = "") => `<div class="part${extra}" data-part="${name}"><h4>${esc(heading)}</h4>${body}</div>`;

/** The graph as text lines, for a reader the diagram library never reached. */
export function edgeList({ nodes, edges }) {
  const name = new Map(nodes.map((node) => [node.id, node.label]));
  const linked = new Set(edges.flatMap((edge) => [edge.from, edge.to]));
  const marks = (edge) => [edge.leak && "leak", edge.dashed && "pointer"].filter(Boolean);
  return [
    ...nodes.filter((node) => node.deep).map((node) => `Deep module: ${node.label}`),
    ...edges.map((edge) => `${name.get(edge.from)} → ${name.get(edge.to)}${edge.label ? `: ${edge.label}` : ""}${marks(edge).length ? ` (${marks(edge).join(", ")})` : ""}`),
    ...nodes.filter((node) => !linked.has(node.id) && !node.deep).map((node) => node.label),
  ];
}

const isMermaid = (panelData) => panelData.pattern === "graph" && panelData.edges.length > 0;

function drawn(panelData) {
  switch (panelData.pattern) {
    case "graph":
      if (!isMermaid(panelData)) {
        return `<div class="drawn boxes v">${panelData.nodes.map((node) => `<div class="box${node.deep ? " deep" : ""}">${esc(node.label)}</div>`).join("")}</div>`;
      }
      return `<div class="paper v"><pre class="mermaid">${esc(mermaidSource(panelData))}</pre><ul class="edge-list">${edgeList(panelData).map((line) => `<li>${esc(line)}</li>`).join("")}</ul></div>`;
    case "stack":
      return `<div class="drawn v">${panelData.layers.map((layer) => `<div class="box layer${panelData.layers.length === 1 ? " deep" : ""}">${esc(layer)}</div>`).join("")}</div>`;
    case "collapse":
      if (panelData.module !== null) {
        return `<div class="drawn v"><div class="box deep">${esc(panelData.module)}<div class="faded">${panelData.calls.map((call) => `<div>${esc(call)}</div>`).join("")}</div></div></div>`;
      }
      return `<div class="drawn v">${panelData.calls.reduceRight((inner, call) => `<div class="nest">${esc(call)}${inner}</div>`, "")}</div>`;
  }
}

function figure(side, panelData, candidate) {
  const caption = panelData.caption === null ? side : `${side}: ${panelData.caption}`;
  const enlarge = `Enlarge the ${side.toLowerCase()} diagram: ${shortId(candidate.id)} ${candidate.title}`;
  return `<figure data-enlarge${isMermaid(panelData) ? ' class="graph"' : ""}><figcaption><span>${esc(caption)}</span><button type="button" class="zoom-open" aria-label="${esc(enlarge)}">Enlarge</button></figcaption>${drawn(panelData)}</figure>`;
}

function card(candidate, titles, shown) {
  const [word, , badge] = bandOf(candidate.recommendation);
  const p = (value) => `<p class="v">${esc(value)}</p>`;
  return [
    `<article class="card" id="${cardId(candidate.id)}"${shown ? "" : " hidden"} tabindex="-1">`,
    `<h3 class="v" data-part="title"><span class="cid">${esc(shortId(candidate.id))}</span> ${esc(candidate.title)}</h3>`,
    `<p class="badges" data-part="badges"><span class="badge ${badge}">${esc(word)}</span><span class="tag">${esc(candidate.category)}</span></p>`,
    part("problem", "Problem", p(candidate.problem)),
    part("solution", "Solution", p(candidate.solution)),
    part("diagram", "Before and after", `<div class="panels">${figure("Before", candidate.diagram.before, candidate)}${figure("After", candidate.diagram.after, candidate)}</div>`),
    part("wins", "Wins", `<ul class="v">${candidate.wins.map(({ term, gain }) => `<li><strong>${esc(term)}:</strong> ${esc(gain)}</li>`).join("")}</ul>`),
    part("verified", "Verified", p(candidate.verified)),
    part("files", "Files", `<ul class="v files">${candidate.files.map((file) => `<li>${esc(file)}</li>`).join("")}</ul>`),
    candidate.dependsOn === null ? "" : part("depends-on", "Depends on", `<p class="v"><a href="#${cardId(candidate.dependsOn)}">${esc(titles.get(candidate.dependsOn))}</a></p>`),
    candidate.adr === null ? "" : part("adr", "Recorded decision", p(candidate.adr), " adr"),
    `<p class="back"><a href="#index">Back to every candidate</a></p>`,
    "</article>",
  ].join("\n");
}

const verifiedWord = (verified) => verified.split(":")[0];
const shortId = (id) => id.toUpperCase();

/** One line per drawing style, badge and term the page uses, and none it does not. */
export function legendLines(report) {
  const panels = report.candidates.flatMap((candidate) => [candidate.diagram.before, candidate.diagram.after]);
  const graphs = panels.filter((panelData) => panelData.pattern === "graph");
  const edges = graphs.flatMap((graphData) => graphData.edges);
  const used = (values, meaning) => Object.keys(meaning).filter((key) => values.includes(key)).map((key) => [key, meaning[key]]);
  const drawing = [
    [panels.some((p) => (p.pattern === "graph" && p.nodes.some((node) => node.deep)) || (p.pattern === "stack" && p.layers.length === 1) || (p.pattern === "collapse" && p.module !== null)), "Dark, heavy-bordered box", "a deep module, a small interface over a lot of behavior"],
    [true, "Plain box", "any other module"],
    [edges.some((edge) => !edge.dashed && !edge.leak), "Solid gray arrow", "one module calls or reads another"],
    [edges.some((edge) => edge.dashed && !edge.leak), "Dotted gray arrow", "a pointer: one file refers the reader to another, with no call"],
    [edges.some((edge) => edge.leak), "Rust arrow, solid or dotted", "a leak, one module reaching past another's interface; its label says how"],
    [graphs.some((graphData) => graphData.edges.length === 0), "Boxes side by side", "the separate places that hold one thing"],
    [panels.some((p) => p.pattern === "stack" && p.layers.length > 1), "Stacked rows", "the places one rule, step or call runs through, one row each"],
    [panels.some((p) => p.pattern === "collapse" && p.module === null), "Nested boxes", "each part held inside the one around it"],
    [panels.some((p) => p.pattern === "collapse" && p.module !== null), "Faded text in a dark box", "calls the deep module makes internal"],
  ].filter(([shown]) => shown).map(([, term, meaning]) => [term, meaning]);
  return [
    ...drawing,
    ...used(report.candidates.map((candidate) => candidate.recommendation), BAND_MEANING),
    ...used(report.candidates.map((candidate) => candidate.category), CATEGORY_MEANING),
    ...used(report.candidates.flatMap((candidate) => candidate.wins.map(({ term }) => term)), TERM_MEANING),
    ...used(report.candidates.map((candidate) => verifiedWord(candidate.verified)), VERIFIED_MEANING),
  ];
}

/** The report page for a record parseDeepening read. */
export function renderDeepening(report) {
  const titles = new Map(report.candidates.map((candidate) => [candidate.id, candidate.title]));
  const top = report.candidates.find((candidate) => candidate.id === report.top);
  const tally = BANDS.map(([word]) => `${report.candidates.filter((candidate) => candidate.recommendation === word).length} ${word}`).join(", ");
  const order = BANDS.flatMap(([word]) => report.candidates.filter((candidate) => candidate.recommendation === word).sort((a, b) => (b.id === top.id) - (a.id === top.id)));
  const item = (candidate) => `<li><a class="reader-item" href="#${cardId(candidate.id)}"${candidate.id === top.id ? ' aria-current="true"' : ""}><span class="reader-title"><span class="cid">${esc(shortId(candidate.id))}</span> ${esc(candidate.title)}</span><span class="reader-meta"><span class="badge ${bandOf(candidate.recommendation)[2]}">${esc(candidate.recommendation)}</span><span>${esc(verifiedWord(candidate.verified))}</span>${candidate.id === top.id ? '<span class="top-chip">Top recommendation</span>' : ""}</span><span class="reader-solution">${esc(candidate.solution)}</span></a></li>`;
  const sidebar = BANDS.flatMap(([word]) => {
    const cards = order.filter((candidate) => candidate.recommendation === word);
    return cards.length ? [`<li class="reader-band">${esc(word)} · ${cards.length}</li>`, ...cards.map(item)] : [];
  }).join("\n");
  const step = (live) => `<div class="reader-step" role="group" aria-label="Step through the candidates"><button type="button" data-step="-1">Previous candidate</button><p class="reader-pos"${live ? ' aria-live="polite"' : ""}>${order.indexOf(top) + 1} of ${order.length}</p><button type="button" data-step="1">Next candidate</button></div>`;
  const link = (id) => `<a href="#${cardId(id)}">${esc(shortId(id))} ${esc(titles.get(id))}</a>`;
  const dependents = (id) => report.candidates.filter((candidate) => candidate.dependsOn === id);
  const builtOn = (id, seen = new Set([id])) => dependents(id).filter((candidate) => !seen.has(candidate.id)).flatMap((candidate) => {
    seen.add(candidate.id);
    return [`<li>${link(candidate.id)}${candidate.dependsOn === top.id ? "" : `, through ${esc(shortId(candidate.dependsOn))}`}</li>`, ...builtOn(candidate.id, seen)];
  });
  const topDependents = builtOn(top.id);
  const legend = legendLines(report).map(([term, meaning]) => `<li><strong>${esc(term)}:</strong> ${esc(meaning)}</li>`).join("\n");
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
<p>${esc(report.date)} · scope: ${esc(report.scope)} · commit <span class="mono">${esc(report.commit)}</span></p>
${report.counts.length ? `<p>Evidence: ${esc(report.counts.join(" · "))}</p>\n` : ""}<p>Candidates: ${report.candidates.length} (${esc(tally)})${report.kept.length ? ` · <a href="#kept">looked at, no change: ${report.kept.length}</a>` : ""}</p>
<p>Verification: ${esc(report.verification)}: ${esc(LEVEL_MEANING[report.level])}.</p>
<details class="key"><summary>Key: what the badges, tags, terms and diagram styles mean</summary>
<ul class="legend">
${legend}
</ul>
</details>
</header>
<div class="reader">
<nav id="index" class="reader-nav" aria-labelledby="index-title">
<h2 id="index-title">Every candidate</h2>
<ul class="reader-list">
${sidebar}
</ul>
${report.kept.length ? `<a class="reader-kept" href="#kept">Looked at, no change · ${report.kept.length}</a>\n` : ""}</nav>
<div class="reader-main" id="candidates">
${step(true)}
<section id="top-recommendation" class="top">
<h2>Top recommendation</h2>
<p>${esc(report.topWhy)}</p>${topDependents.length ? `<div><h4>Built on it</h4><ul class="built-on">${topDependents.join("")}</ul></div>` : ""}
</section>
${order.map((candidate) => card(candidate, titles, candidate.id === top.id)).join("\n")}
${report.kept.length ? `<section id="kept" hidden tabindex="-1">
<h2>Looked at, no change</h2>
<p>The scan checked these and concluded the code should stay as it is. They are not candidates.</p>
${report.kept.map((item) => `<div class="kept-item"><h3>${esc(item.title)}</h3><p>${esc(item.reason)}</p><ul class="files">${item.files.map((file) => `<li>${esc(file)}</li>`).join("")}</ul></div>`).join("\n")}
</section>
` : ""}${step(false)}
</div>
</div>
</main>
<dialog id="zoom" class="zoom" aria-labelledby="zoom-title"><div class="zoom-head"><h2 id="zoom-title">Diagram</h2><button type="button" data-zoom-close>Close</button></div><div class="zoom-body"></div></dialog>
${SCRIPTS[2]}
</body>
</html>
`;
}


const TAGS = new Set([
  "html", "head", "meta", "title", "style", "body", "main", "header", "section", "article", "nav",
  "h1", "h2", "h3", "h4", "p", "ul", "li", "a", "div", "span", "pre", "strong", "figure", "figcaption",
  "button", "details", "summary", "dialog",
]);
const ATTRS = new Set([
  "lang", "charset", "http-equiv", "content", "name", "class", "id", "href", "role", "type", "hidden", "tabindex",
  "aria-label", "aria-labelledby", "aria-pressed", "aria-current", "aria-live", "data-rv-theme", "data-part", "data-step", "data-enlarge", "data-zoom-close",
]);
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
