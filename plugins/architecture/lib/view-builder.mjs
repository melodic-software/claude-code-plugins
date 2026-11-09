// GENERATED from lib/view-builder.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Build a rendered view from a checked-in template plus data, and validate it
// against one of the two profiles in the rendered-views convention
// (docs/contracts/rendered-views/README.md, "The interactive validator profile").
//
//   report       the template's {{key}} and {{#each key}}...{{/each}} slots are
//                filled with escaped text; no script. Validated by
//                validateRenderedPage in html-escape.mjs.
//   interactive  the template is static markup with data-rv-* bindings. The data
//                goes only into a JSON data block; view-runtime.js, inlined and
//                pinned by hash in the page's content security policy, renders it
//                through textContent.
//
// The template is checked-in markup; the data may be attacker-controlled (K2).
// No data value is ever written into markup by the interactive profile. The one
// exception, in both profiles, is the optional page title (rule 5): the builder
// writes it as one escaped, capped line of text into the head's <title>.
//
// View kinds: VIEW_KINDS holds one entry per kind, { id, parse(record) -> data, template, tier },
// the template path relative to the root of the plugin carrying this file. render(laneId, kind,
// record) builds a kind the lane registers (lib/view-registry.mjs). Adding a kind is an addition
// here and in the lane's registration, never a skill edit.
//
// CLI:
//   node view-builder.mjs --profile report|interactive --template <file> --data <file.json> --out <file>
//                         [--connect http://127.0.0.1:<port>]   (interactive: the session-bridge origin)
//                         [--title <text>]                      (the page title)
//   node view-builder.mjs --check <page.html>
// Exit 0 ok, 1 the page or input fails its profile, 2 usage or environment.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { escapeHtml, pageDigest, stampPage, validateRenderedPage } from "./html-escape.mjs";
import { LANES } from "./view-registry.mjs";

export const INTERACTIVE_MARKER = "rv-gen:view-builder-interactive";
const MARKER_RE = /<!-- rv-gen:view-builder-interactive sha256:([0-9a-f]{64}) -->/g;
const DATA_ID = "rv-data";
const DATA_OPEN = `<script type="application/json" id="${DATA_ID}">`;

// An opaque token: every id, for, value, data-* value and data key the
// template names. Never derived from data, so no payload can carry data text.
const KEY = /^[a-z0-9-]{1,32}$/;
const FRAGMENT = /^#[a-z0-9-]{1,32}$/;
const URL_FRAGMENT = /^url\(#[a-z0-9-]{1,32}\)$/;
const ESCAPED_TEXT = /^(?:[^&<>"']|&(?:amp|lt|gt|quot|#x27);)*$/;

const HTML_TAGS = [
  "html", "head", "meta", "title", "style", "body",
  "p", "h1", "h2", "h3", "h4", "table", "thead", "tbody", "tr", "th", "td", "caption",
  "section", "code", "pre", "ol", "ul", "li", "dl", "dt", "dd", "details", "summary",
  "div", "span", "header", "main", "footer", "nav", "article", "aside", "figure",
  "figcaption", "strong", "em", "small", "kbd", "mark", "hr", "br", "a",
  "button", "label", "input", "select", "option", "textarea", "fieldset", "legend", "output",
];
// Shape, path, text, group and definition elements only (rule 6). Refused by
// omission: foreignObject, script, image, feImage, use, a-in-SVG navigation,
// mpath, discard, the SMIL animation elements, and SVG style.
const SVG_TAGS = [
  "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
  "text", "tspan", "desc", "defs", "lineargradient", "radialgradient", "stop",
  "marker", "clippath", "mask", "pattern",
];
const TAGS = new Set([...HTML_TAGS, ...SVG_TAGS]);

const ATTRS = new Set([
  "charset", "class", "content", "http-equiv", "id", "lang", "name", "title",
  "role", "hidden", "open", "type", "for", "value", "placeholder", "checked",
  "min", "max", "step", "href",
  // SVG geometry and presentation
  "xmlns", "viewbox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy",
  "r", "rx", "ry", "d", "points", "fill", "stroke", "stroke-width", "stroke-linecap",
  "stroke-linejoin", "stroke-dasharray", "opacity", "fill-opacity", "stroke-opacity",
  "transform", "text-anchor", "dominant-baseline", "font-size", "font-weight",
  "offset", "stop-color", "stop-opacity", "gradientunits", "gradienttransform",
  "marker-start", "marker-mid", "marker-end", "markerwidth", "markerheight", "refx",
  "refy", "orient", "markerunits", "clip-path", "mask", "preserveaspectratio",
  "focusable", "patternunits",
]);
const DATA_RV = new Set([
  "data-rv-text", "data-rv-each", "data-rv-count", "data-rv-filter", "data-rv-pick",
  "data-rv-copy", "data-rv-download", "data-rv-note", "data-rv-status", "data-rv-out",
  "data-rv-choice", "data-rv-send", "data-rv-session", "data-rv-replies",
  "data-rv-theme", "data-rv-shows", "data-rv-example", "data-rv-record",
]);
// The one origin a Claude-interactive page may reach: a session-bridge server on loopback (rule 9).
const BRIDGE_ORIGIN = /^http:\/\/127\.0\.0\.1:([1-9][0-9]{0,4})$/;
const CSP_CONNECT = /; connect-src (http:\/\/127\.0\.0\.1:[0-9]{1,5})$/;
const INPUT_TYPES = new Set(["checkbox", "radio", "search", "range", "text"]);
const FORM_CONTROLS = new Set(["input", "textarea", "select", "option"]);
// Elements whose text is CSS, metadata, or code: data bound into them would stop being page text.
const UNBINDABLE = new Set(["html", "head", "title", "meta", "style", "script"]);
const CONTENT_BINDINGS = new Set(["data-rv-text", "data-rv-count", "data-rv-each"]);
export const TITLE_MAX = 80;
const HEAD_TITLE = /<title>[^<]*<\/title>/gi;

export class ViewBuildError extends Error {
  /** @param {string[]} failures */
  constructor(failures) {
    super(`view-builder: page fails its profile: ${failures.join(", ")}`);
    this.failures = failures;
  }
}

const lf = (text) => String(text).replace(/\r\n?/g, "\n");
const sha256 = (text) => createHash("sha256").update(text, "utf8").digest("base64");

/** The shipped runtime, line endings normalized as the HTML parser will see them. */
export function loadRuntime() {
  return lf(readFileSync(new URL("./view-runtime.js", import.meta.url), "utf8"));
}

/**
 * @param {string} runtime
 * @param {string | null} style the body of the page's one style element
 * @param {string | null} [connect] the session-bridge origin a Claude-interactive page reaches
 */
export function contentSecurityPolicy(runtime, style, connect = null) {
  const styleSrc = style === null ? "'none'" : `'sha256-${sha256(style)}'`;
  return [
    "default-src 'none'",
    `script-src 'sha256-${sha256(runtime)}'`,
    `style-src ${styleSrc}`,
    "base-uri 'none'",
    "form-action 'none'",
    ...(connect === null ? [] : [`connect-src ${connect}`]),
  ].join("; ");
}

const bridgeOriginOk = (origin) => {
  const m = BRIDGE_ORIGIN.exec(origin);
  return m !== null && Number(m[1]) <= 65535;
};

/**
 * @param {{ profile: "report" | "interactive", template: string, data?: unknown, runtime?: string, connect?: string | null, title?: string | null }} input
 *   connect: the session-bridge origin (http://127.0.0.1:<port>) that makes the page Claude-interactive
 *   title: the page title, replacing the template's <title> text; null or blank keeps the template's
 * @returns {string} the validated page
 */
export function buildView({ profile, template, data = {}, runtime, connect = null, title = null }) {
  if (connect !== null && (profile !== "interactive" || !bridgeOriginOk(connect))) {
    throw new ViewBuildError(["connect"]);
  }
  if (title !== null && typeof title !== "string") {
    throw new ViewBuildError(["title"]);
  }
  if (profile === "report") {
    return buildReport(lf(template), data, title);
  }
  if (profile === "interactive") {
    return buildInteractive(lf(template), data, runtime ?? loadRuntime(), connect, title);
  }
  throw new ViewBuildError([`profile:${profile}`]);
}

/**
 * One line of plain text: format characters (bidi overrides, zero-width marks) dropped,
 * whitespace and control-character runs made one space, cut to TITLE_MAX.
 */
function plainTitle(title) {
  const chars = [...title.replace(/\p{Cf}/gu, "").replace(/[\s\p{Cc}]+/gu, " ").trim()];
  return chars.length <= TITLE_MAX ? chars.join("") : `${chars.slice(0, TITLE_MAX - 1).join("").trimEnd()}…`;
}

// The only text the builder writes outside the data block or a report slot (rule 5).
// It goes in as escaped text, so it cannot end the element or add markup.
function withTitle(html, title) {
  const text = title === null ? "" : plainTitle(title);
  if (text === "") {
    return html;
  }
  const headEnd = html.search(/<\/head>/i);
  const found = [...html.slice(0, Math.max(headEnd, 0)).matchAll(HEAD_TITLE)];
  if (found.length !== 1) {
    throw new ViewBuildError(["title-element"]);
  }
  const { index, 0: element } = found[0];
  return `${html.slice(0, index)}<title>${escapeHtml(text)}</title>${html.slice(index + element.length)}`;
}

/**
 * Select the profile from the page's generator marker. A page without the
 * interactive marker is judged by the report profile, so an unknown or missing
 * marker fails closed.
 *
 * @param {string} html
 * @param {string} [runtime]
 */
export function validateView(html, runtime) {
  return html.match(MARKER_RE)
    ? validateInteractivePage(html, runtime ?? loadRuntime())
    : validateRenderedPage(html);
}

// ------------------------------------------------------------ view kinds

const isText = (value) => typeof value === "string";
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

/** A record that is one JSON object (or its text): top-level text fields, then one list of rows whose fields are text. */
const jsonRecord = (shape) => (record) => {
  const data = isText(record) ? JSON.parse(record) : record;
  if (!isObject(data)) throw new ViewBuildError(["data is not an object"]);
  const failures = shape.text.filter((key) => !isText(data[key])).map((key) => `${key} must be text`);
  if (!Array.isArray(data[shape.list])) throw new ViewBuildError([...failures, `${shape.list} must be a list`]);
  for (const [index, row] of data[shape.list].entries()) {
    const at = `${shape.list}[${index}]`;
    if (!isObject(row)) {
      failures.push(`${at} must be an object`);
      continue;
    }
    for (const key of shape.row) if (!isText(row[key])) failures.push(`${at}.${key} must be text`);
  }
  if (failures.length) throw new ViewBuildError(failures);
  return data;
};

const trimBlank = (lines) => {
  let [start, end] = [0, lines.length];
  while (start < end && !lines[start].trim()) start += 1;
  while (end > start && !lines[end - 1].trim()) end -= 1;
  return lines.slice(start, end);
};

/**
 * Each line of a markdown record, with its heading `level` and `text` when it is a heading, and its
 * fence `role`: `open` (with the opening `info` string), `body`, `close`, or null outside a fence.
 * A heading inside a code fence is text; a fence closes only on a bare run of its own character at
 * least as long as the opening run (CommonMark), so a fence quoted inside a longer one is body.
 */
function markdownLines(record) {
  let fence = null;
  return lf(record).split("\n").map((line) => {
    const heading = fence ? null : /^(#{1,6})[ \t]+(.+?)[ \t]*$/.exec(line);
    const run = /^[ \t]*(`{3,}(?=[^`]*$)|~{3,})(.*)$/.exec(line);
    let [role, info] = [fence ? "body" : null, ""];
    if (!fence && run) [fence, role, info] = [run[1], "open", run[2].trim()];
    else if (fence && run && run[1][0] === fence[0] && run[1].length >= fence.length && !run[2].trim()) [fence, role] = [null, "close"];
    return { line, level: heading?.[1].length, text: heading?.[2], role, info };
  });
}

/**
 * A markdown record's `## Design` section: the title from the record's first `# ` heading, the
 * text before the first `### ` subsection, and each subsection's lines as written.
 */
function parseDesign(record) {
  if (!isText(record)) throw new ViewBuildError(["the design record must be markdown text"]);
  let [inDesign, found, title] = [false, false, null];
  const intro = [];
  const sections = [];
  for (const { line, level, text } of markdownLines(record)) {
    if (level === 1) title ??= text;
    if (level <= 2) {
      inDesign = level === 2 && text === "Design";
      found ||= inDesign;
    } else if (inDesign && level === 3) {
      sections.push({ name: text, lines: [] });
    } else if (inDesign) {
      (sections.at(-1)?.lines ?? intro).push(line);
    }
  }
  if (!found) throw new ViewBuildError(["the record has no ## Design section"]);
  return { title: title ?? "Design", intro: trimBlank(intro).join("\n"), sections: sections.map(({ name, lines }) => ({ name, lines: trimBlank(lines) })) };
}

const PLAN_HEADING = /^Plan(?::[ \t]*(.*))?$/;
const BRIEF_HEADING = /^Brief$/;
const LIST_ITEM = /^[ \t]*(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?/;
const STATUS_TAG = /[ \t]*\[(TODO|DOING|DONE)\][ \t]*$/;
const BEHAVIOR = /^[ \t]*[-*+][ \t]+(B\d+):[ \t]*(.*?)(?:[ \t]*\(([^()]*)\))?[ \t]*$/;
const CRITERION = /^([A-Z]+\d+):[ \t]*(.*)$/;
const PROCESS = /^Process criteria:[ \t]*(.*)$/;
const GOAL_LINE = /^Goal:[ \t]*(.*)$/;
const BLAST = /blast[- ]radius/i;
const BLAST_LINE = /^[ \t*_-]*blast[- ]radius[ \t*_]*:/i;
const BLAST_LEVEL = /\b(LOW|MEDIUM|HIGH|CRITICAL)\b/;
const SATISFIES = /^[ \t]*\*\*Satisfies:\*\*[ \t]*(.*)$/;
const DELIVERS = /^[ \t]*\*\*Delivers:\*\*[ \t]*(.*)$/;
const SANITY = /\*\*Sanity Check:\*\*[ \t]*(.*)$/;
const TABLE_ROW = /^[ \t]*\|/;
const TABLE_RULE = /^[ \t|:-]*-[ \t|:-]*$/;

const unlisted = (line) => line.replace(LIST_ITEM, "").trim();
const cells = (row) =>
  row.trim().replace(/^\|/, "").replace(/(?<!\\)\|$/, "").split(/(?<!\\)\|/).map((cell) => cell.trim().replaceAll("\\|", "|"));
/** The lines up to the first blank line or list item after the first, as one line. */
const firstParagraph = (lines) => {
  const kept = trimBlank(lines);
  const end = kept.findIndex((line, index) => index > 0 && (!line.trim() || LIST_ITEM.test(line)));
  return kept.slice(0, end < 0 ? kept.length : end).map(unlisted).join(" ");
};

/** Each list item joined with its indented continuation lines, as one line; other lines are dropped. */
const listItems = (lines) => {
  const items = [];
  let open = false;
  for (const line of lines) {
    if (LIST_ITEM.test(line)) {
      items.push(line.trimEnd());
      open = true;
    } else if (open && /^[ \t]+\S/.test(line)) items[items.length - 1] += ` ${line.trim()}`;
    else open = false;
  }
  return items;
};

/** The record's lines grouped under their `##` and `###` headings, in order: [{ h2, h3, lines }]. */
function outline(entries) {
  const parts = [{ h2: "", h3: "", lines: [] }];
  for (const entry of entries) {
    if (entry.level === 2 || entry.level === 3) {
      parts.push({ h2: entry.level === 2 ? entry.text : parts.at(-1).h2, h3: entry.level === 3 ? entry.text : "", lines: [] });
    } else {
      parts.at(-1).lines.push(entry);
    }
  }
  return parts;
}

/** The first blast-radius level a Blast radius heading, a `Blast radius:` line or a line under that heading names. */
function blastOf(entries) {
  let inBlast = false;
  for (const { line, level, text, role } of entries) {
    if (level) inBlast = BLAST.test(text);
    const named = level ? inBlast : role === null && (inBlast || BLAST_LINE.test(line));
    const found = named ? BLAST_LEVEL.exec(line) : null;
    if (found) return found[1];
  }
  return "";
}

/** One `### Phase` section: its Satisfies and Delivers lines, its Sanity Check lines as criteria, its outermost `shape` fences, and the rest as `what`. */
function phaseOf({ h3, lines }) {
  const phase = { status: STATUS_TAG.exec(h3)?.[1] ?? "", name: h3.replace(STATUS_TAG, ""), what: "", satisfies: "", delivers: "", criteria: [], shapes: [] };
  const what = [];
  let [shape, checks] = [null, false];
  for (const { line, role, info } of lines) {
    if (shape) {
      if (role === "close") shape = null;
      else shape.lines.push(line);
      continue;
    }
    const anchor = role === "open" ? /^shape[ \t]+(.+)$/.exec(info)?.[1] : undefined;
    const [satisfies, delivers, sanity] = role === null ? [SATISFIES, DELIVERS, SANITY].map((re) => re.exec(line)?.[1].trim()) : [];
    if (anchor) {
      shape = { anchor, lines: [] };
      phase.shapes.push(shape);
    } else if (satisfies !== undefined) {
      phase.satisfies = satisfies;
    } else if (delivers !== undefined) {
      phase.delivers = delivers;
    } else if (sanity !== undefined) {
      if (sanity) phase.criteria.push(sanity);
      checks = !sanity;
      continue;
    } else if (checks && role === null && (LIST_ITEM.test(line) || !line.trim())) {
      if (line.trim()) phase.criteria.push(unlisted(line));
      continue;
    } else {
      what.push(line);
    }
    checks = false;
  }
  phase.what = trimBlank(what).join("\n");
  phase.shapes = phase.shapes.map(({ anchor, lines: body }) => ({ anchor, body: body.join("\n") }));
  return phase;
}

/**
 * A PLAN.md record (plan SKILL.md "PLAN.md anatomy"): the title from its first `# ` heading or a
 * `## Plan: <title>` heading; the Brief's Goal paragraph, or for a `No Brief:` plan its `Goal:`
 * line; the blast-radius level; the Brief's Problem, Constraints and Out-of-scope lines; and from
 * `## Plan` its behaviors, Process criteria line, acceptance criteria (the Brief's, then any the
 * plan adds), Decisions made table rows and phases. A missing list is [] and a missing text "".
 */
export function parsePlan(record) {
  if (!isText(record)) throw new ViewBuildError(["the plan record must be markdown text"]);
  const entries = markdownLines(record);
  const plan = entries.find(({ level, text }) => level === 2 && PLAN_HEADING.test(text));
  if (!plan) throw new ViewBuildError(["the record has no ## Plan section"]);
  const parts = outline(entries);
  const under = (h2, h3) => parts.filter((part) => h2.test(part.h2) && h3.test(part.h3)).flatMap((part) => part.lines);
  const text = (h2, h3) => under(h2, h3).filter(({ role }) => role === null).map(({ line }) => line);
  const listed = (h3) => text(BRIEF_HEADING, h3).filter((line) => line.trim()).map(unlisted);
  const noBrief = entries.findIndex(({ line, role }) => role === null && line.startsWith("No Brief:"));
  const goalLine = noBrief < 0 ? undefined : entries.slice(noBrief).find(({ line, role }) => role === null && GOAL_LINE.test(line));
  const rows = text(PLAN_HEADING, /^Decisions made/i).filter((line) => TABLE_ROW.test(line));
  return {
    title: entries.find(({ level }) => level === 1)?.text ?? PLAN_HEADING.exec(plan.text)[1] ?? "",
    goal: firstParagraph(text(BRIEF_HEADING, /^Goal$/)) || (goalLine ? GOAL_LINE.exec(goalLine.line)[1].trim() : ""),
    blast: blastOf(entries),
    brief: { problem: listed(/^Problem$/), constraints: listed(/^Constraints$/), outOfScope: listed(/^Out[- ]of[- ]scope$/i) },
    behaviors: listItems(text(PLAN_HEADING, /^Behav(?:ior|iour)s?$/))
      .map((line) => BEHAVIOR.exec(line))
      .filter(Boolean)
      .map(([, id, claim, cites]) => ({ id, text: claim, cites: cites?.trim() ?? "" })),
    process: text(PLAN_HEADING, /^/).map((line) => PROCESS.exec(line)?.[1].trim()).find((found) => found !== undefined) ?? "",
    criteria: [...listItems(text(BRIEF_HEADING, /^Acceptance criteria$/i)), ...listItems(text(PLAN_HEADING, /^Acceptance criteria$/i))]
      .map((line) => {
        const [, id = "", rest = unlisted(line)] = CRITERION.exec(unlisted(line)) ?? [];
        return { id, text: rest };
      }),
    decisions: (TABLE_RULE.test(rows[1] ?? "") ? rows.slice(2) : rows)
      .filter((row) => !TABLE_RULE.test(row))
      .map((row) => {
        const [decision = "", changes = "", basis = "", source = ""] = cells(row);
        return { decision, changes, basis, source };
      }),
    phases: parts.filter((part) => PLAN_HEADING.test(part.h2) && /^Phase[ \t]+(?:\d+(?:\.\d+)?[A-Za-z]?|[IVXLC]+)[ \t]*:/.test(part.h3)).map(phaseOf),
  };
}

/**
 * The plan view's data: the plan record with its Brief lists as top-level keys, since a template
 * names only lowercase keys, and `Plan` as the title of a record that names none.
 */
const planView = (record) => {
  const { brief, ...plan } = parsePlan(record);
  return { ...plan, title: plan.title || "Plan", problem: brief.problem, constraints: brief.constraints, "out-of-scope": brief.outOfScope };
};

const kindEntry = (id, parse, template, tier) => Object.freeze({ id, parse, template, tier });

/** One entry per view kind: `tier` is the rendered-views view tier; `static` builds the report profile. */
export const VIEW_KINDS = Object.freeze({
  plan: kindEntry("plan", planView, "skills/plan/templates/plan-view.html", "client-interactive"),
  brainstorm: kindEntry(
    "brainstorm",
    jsonRecord({ text: ["title", "problem"], list: "candidates", row: ["effort", "name", "what", "where", "impact"] }),
    "skills/brainstorm/templates/brainstorm-view.html",
    "client-interactive",
  ),
  design: kindEntry("design", parseDesign, "skills/design/templates/design-view.html", "client-interactive"),
});

const PLUGIN_ROOT = fileURLToPath(new URL("../", import.meta.url));

/**
 * Build the `kind` view of `record` for the lane `laneId`, which must register that kind.
 * A record the kind cannot read throws ViewBuildError; an unknown lane or kind throws Error.
 * @param {{lanes?: object, kinds?: object, root?: string, connect?: string | null, title?: string | null}} [options]
 *   lanes and kinds replace the registries; root is the directory the kind's template path is under
 */
export function render(laneId, kind, record, { lanes = LANES, kinds = VIEW_KINDS, root = PLUGIN_ROOT, connect = null, title = null } = {}) {
  const lane = Object.hasOwn(lanes, laneId) ? lanes[laneId] : undefined;
  if (!lane) throw new Error(`view-builder: unknown lane ${JSON.stringify(laneId)}`);
  if (!lane.kinds.includes(kind)) throw new Error(`view-builder: lane ${laneId} does not register the view kind ${JSON.stringify(kind)}`);
  const entry = Object.hasOwn(kinds, kind) ? kinds[kind] : undefined;
  if (!entry) throw new Error(`view-builder: no view kind ${JSON.stringify(kind)}`);
  return buildView({
    profile: entry.tier === "static" ? "report" : "interactive",
    template: readFileSync(join(root, entry.template), "utf8"),
    data: entry.parse(record),
    connect,
    title,
  });
}

// ---------------------------------------------------------------- report

function parseSlots(template, failures) {
  const root = { children: [] };
  const stack = [root];
  const parts = template.split(/(\{\{[^}]*\}\})/);
  parts.forEach((part, index) => {
    const top = stack.at(-1);
    if (index % 2 === 0) {
      if (part.includes("{{") || part.includes("}}")) {
        failures.push("slot-syntax");
      }
      top.children.push({ text: part });
      return;
    }
    const body = part.slice(2, -2).trim();
    const each = /^#each ([a-z0-9-]{1,32})$/.exec(body);
    if (each) {
      const node = { each: each[1], children: [] };
      top.children.push(node);
      stack.push(node);
    } else if (body === "/each") {
      if (stack.length === 1) {
        failures.push("slot-unbalanced");
      } else {
        stack.pop();
      }
    } else if (body === "." || KEY.test(body)) {
      top.children.push({ slot: body });
    } else {
      failures.push("slot-syntax");
    }
  });
  if (stack.length !== 1) {
    failures.push("slot-unbalanced");
  }
  return root;
}

const own = (scope, key) => (scope !== null && typeof scope === "object" && Object.hasOwn(scope, key) ? scope[key] : undefined);

const textOf = (value) => (["string", "number", "boolean"].includes(typeof value) ? String(value) : "");

function renderSlots(node, scope) {
  return node.children
    .map((child) => {
      if ("text" in child) {
        return child.text;
      }
      if ("slot" in child) {
        return escapeHtml(textOf(child.slot === "." ? scope : own(scope, child.slot)));
      }
      const items = own(scope, child.each);
      return Array.isArray(items) ? items.map((item) => renderSlots(child, item)).join("") : "";
    })
    .join("");
}

function buildReport(template, data, title) {
  const failures = (template.match(/<[^>]*>/g) ?? []).filter((tag) => tag.includes("{{")).map(() => "slot-in-tag");
  for (const [, css] of template.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style/gi)) {
    if (css.includes("{{")) {
      failures.push("slot-in-style");
    }
  }
  const tree = parseSlots(template, failures);
  if (failures.length) {
    throw new ViewBuildError(failures);
  }
  const page = stampPage(withTitle(renderSlots(tree, data), title));
  const result = validateRenderedPage(page);
  if (!result.ok) {
    throw new ViewBuildError(result.failures);
  }
  return page;
}

// ----------------------------------------------------------- interactive

function styleBodies(html) {
  return [...html.matchAll(/<style\b[^>]*>([\s\S]*?)(?:<\/style[\s/>]|$)/gi)];
}

function buildInteractive(template, data, runtime, connect, title) {
  const failures = [];
  if (template.includes("{{")) {
    failures.push("slot-in-interactive");
  }
  if (/<!--|<script|<\/script/i.test(runtime)) {
    failures.push("runtime-script-text");
  }
  if (data === null || typeof data !== "object") {
    failures.push("data-not-object");
  }
  const styles = styleBodies(template);
  const head = /<head>\s*<meta charset="utf-8">/i.exec(template);
  const bodyEnd = template.toLowerCase().lastIndexOf("</body>");
  if (!head) {
    failures.push("head");
  }
  if (bodyEnd < 0) {
    failures.push("body");
  }
  if (styles.length > 1) {
    failures.push("style-count");
  }
  if (failures.length) {
    throw new ViewBuildError(failures);
  }
  // `<` as < keeps `</script` and `<!--` out of the block (rule 2).
  const json = JSON.stringify(data).replaceAll("<", "\\u003c");
  const csp = contentSecurityPolicy(runtime, styles.length ? styles[0][1] : null, connect);
  const meta = `<meta http-equiv="Content-Security-Policy" content="${escapeHtml(csp)}">`;
  const headEnd = head.index + head[0].length;
  const scripts = `${DATA_OPEN}${json}</script><script>${runtime}</script>`;
  const html =
    template.slice(0, headEnd) +
    meta +
    template.slice(headEnd, bodyEnd) +
    scripts +
    template.slice(bodyEnd);
  const page = stamp(withTitle(html, title));
  const result = validateInteractivePage(page, runtime);
  if (!result.ok) {
    throw new ViewBuildError(result.failures);
  }
  return page;
}

function stamp(html) {
  const marker = `<!-- ${INTERACTIVE_MARKER} sha256:${pageDigest(html)} -->`;
  const at = html.indexOf("<head>");
  return at < 0 ? marker + html : html.slice(0, at + 6) + marker + html.slice(at + 6);
}

function parseAttributes(raw) {
  const attrs = [];
  const re = /([^\s"'>=/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  for (const m of raw.matchAll(re)) {
    attrs.push({ name: m[1].toLowerCase(), value: m[2] ?? m[3] ?? m[4] ?? "" });
  }
  return attrs;
}

// Finds each script element and removes the two permitted ones. A body holding
// `<!--` or `<script` fails closed: there the browser's tokenizer would not end
// the element at the first `</script`, so this scan would check another page.
function extractScripts(html, runtime, failures) {
  const opens = [...html.matchAll(/<script(?=[\s/>])/gi)];
  if (opens.length !== 2) {
    failures.push("script-count");
    return html;
  }
  const spans = [];
  for (const open of opens) {
    const tagEnd = html.indexOf(">", open.index);
    const close = html.slice(tagEnd).search(/<\/script/i);
    if (tagEnd < 0 || close < 0) {
      failures.push("script-unclosed");
      return html;
    }
    const bodyEnd = tagEnd + close;
    const closeTag = /^<\/script\s*>/i.exec(html.slice(bodyEnd));
    if (!closeTag) {
      failures.push("script-close");
      return html;
    }
    spans.push({
      tag: html.slice(open.index, tagEnd + 1),
      body: html.slice(tagEnd + 1, bodyEnd),
      start: open.index,
      end: bodyEnd + closeTag[0].length,
    });
  }
  const [data, code] = spans;
  for (const span of spans) {
    if (/<!--|<script/i.test(span.body)) {
      failures.push("script-body");
    }
  }
  if (data.tag !== DATA_OPEN) {
    failures.push("data-block-tag");
  } else if (data.body.includes("<")) {
    failures.push("data-block-lt");
  } else {
    try {
      JSON.parse(data.body);
    } catch {
      failures.push("data-block-json");
    }
  }
  if (code.tag !== "<script>") {
    failures.push("runtime-tag");
  } else if (sha256(code.body) !== sha256(runtime)) {
    failures.push("runtime-hash");
  }
  return html.slice(0, data.start) + html.slice(data.end, code.start) + html.slice(code.end);
}

function checkAttribute(tag, attr, failures) {
  const { name, value } = attr;
  if (name.startsWith("data-")) {
    if (!DATA_RV.has(name)) {
      failures.push(`attr:${name}`);
    }
    if (value !== "" && !KEY.test(value)) {
      failures.push(`opaque:${name}`);
    }
    if (UNBINDABLE.has(tag)) {
      failures.push(`binding-on:${tag}`);
    }
    if (CONTENT_BINDINGS.has(name) && FORM_CONTROLS.has(tag)) {
      failures.push("prefill");
    }
    return;
  }
  if (!ATTRS.has(name) && !name.startsWith("aria-") && name !== "xlink:href") {
    failures.push(`attr:${name}`);
    return;
  }
  if (!ESCAPED_TEXT.test(value)) {
    failures.push("unescaped");
  }
  if ((name === "id" || name === "for") && (!KEY.test(value) || value === DATA_ID)) {
    failures.push(`opaque:${name}`);
  }
  if (name === "value" && !KEY.test(value)) {
    failures.push("opaque:value");
  }
  if (name === "href" || name === "xlink:href") {
    if (!FRAGMENT.test(value)) {
      failures.push("href");
    }
    if (tag !== "a" && !SVG_TAGS.includes(tag)) {
      failures.push(`href-on:${tag}`);
    }
  }
  if (/url\(/i.test(value) && !URL_FRAGMENT.test(value)) {
    failures.push("url");
  }
  if (name === "type" && tag === "input" && !INPUT_TYPES.has(value)) {
    failures.push(`input-type:${value}`);
  }
  if (name === "type" && tag === "button" && value !== "button") {
    failures.push(`button-type:${value}`);
  }
  if (name === "http-equiv" && (tag !== "meta" || value !== "Content-Security-Policy")) {
    failures.push("http-equiv");
  }
}

/**
 * The interactive profile (rendered-views README rules 1 to 8).
 *
 * @param {string} html
 * @param {string} runtime the shipped runtime body
 * @returns {{ ok: boolean, failures: string[] }}
 */
export function validateInteractivePage(html, runtime) {
  const failures = [];
  const markers = html.match(MARKER_RE) ?? [];
  if (markers.length !== 1) {
    failures.push("marker");
  } else if (pageDigest(html.replace(markers[0], "")) !== markers[0].slice(-68, -4)) {
    failures.push("marker-digest");
  }

  const rest = extractScripts(lf(html), lf(runtime), failures);

  const styles = styleBodies(rest);
  const headClose = rest.toLowerCase().indexOf("</head>");
  if (styles.length > 1 || (styles.length === 1 && styles[0].index > headClose)) {
    failures.push("style-count");
  }
  for (const style of styles) {
    if (/url\(|@import|expression\(|\\/i.test(style[1])) {
      failures.push("style");
    }
  }

  const csp = /^(?:<!doctype html>\s*)?<html[^>]*>\s*<head>\s*(?:<!--[^>]*-->\s*)?<meta charset="utf-8">\s*<meta http-equiv="Content-Security-Policy" content="([^"]*)">/i.exec(
    rest.trimStart(),
  );
  // A connect-src passes only as the last directive naming one loopback origin.
  const connect = csp ? (CSP_CONNECT.exec(csp[1])?.[1] ?? null) : null;
  if (connect !== null && !bridgeOriginOk(connect)) {
    failures.push("connect");
  }
  const expected = escapeHtml(contentSecurityPolicy(lf(runtime), styles.length ? styles[0][1] : null, connect));
  if (!csp) {
    failures.push("csp-position");
  } else if (csp[1] !== expected) {
    failures.push("csp");
  }

  let httpEquiv = 0;
  for (const m of rest.matchAll(/<\/?([A-Za-z][A-Za-z0-9]*)\b([^>]*)>/g)) {
    const tag = m[1].toLowerCase();
    if (!TAGS.has(tag)) {
      failures.push(`tag:${tag}`);
      continue;
    }
    if (m[0].startsWith("</")) {
      continue;
    }
    for (const attr of parseAttributes(m[2])) {
      if (attr.name === "http-equiv") httpEquiv += 1;
      checkAttribute(tag, attr, failures);
    }
  }
  if (httpEquiv !== 1) {
    failures.push("http-equiv-count");
  }

  const text = rest
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<!doctype html>/gi, "")
    .replace(/<\/?[A-Za-z][A-Za-z0-9]*\b[^>]*>/g, "");
  if (text.includes("<")) {
    failures.push("raw-lt");
  }
  if (!ESCAPED_TEXT.test(text)) {
    failures.push("unescaped");
  }
  return { ok: failures.length === 0, failures: [...new Set(failures)] };
}

// ------------------------------------------------------------------- CLI

function main(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    args[argv[i].replace(/^--/, "")] = argv[i + 1];
  }
  if (args.check) {
    let html;
    try {
      html = readFileSync(args.check, "utf8");
    } catch (err) {
      console.error(err.message);
      return 2;
    }
    const result = validateView(html);
    console.log(result.ok ? "ok" : `FAIL: ${result.failures.join(", ")}`);
    return result.ok ? 0 : 1;
  }
  if (!args.profile || !args.template || !args.data || !args.out) {
    console.error(
      "usage: view-builder.mjs --profile report|interactive --template <file> --data <file.json> --out <file> [--connect <origin>] [--title <text>]\n" +
        "       view-builder.mjs --check <page.html>",
    );
    return 2;
  }
  try {
    const page = buildView({
      profile: args.profile,
      template: readFileSync(args.template, "utf8"),
      data: JSON.parse(readFileSync(args.data, "utf8")),
      connect: args.connect ?? null,
      title: args.title ?? null,
    });
    writeFileSync(args.out, page);
    console.log(`wrote ${args.out}`);
    return 0;
  } catch (err) {
    console.error(err.message);
    return err instanceof ViewBuildError ? 1 : 2;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
