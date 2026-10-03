// GENERATED from lib/view-builder.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Build a rendered view from a checked-in template plus data, and validate it
// against one of the two profiles in the rendered-views convention
// (docs/conventions/rendered-views/README.md, "The interactive validator profile").
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
// No data value is ever written into markup by the interactive profile.
//
// CLI:
//   node view-builder.mjs --profile report|interactive --template <file> --data <file.json> --out <file>
//   node view-builder.mjs --check <page.html>
// Exit 0 ok, 1 the page or input fails its profile, 2 usage or environment.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { escapeHtml, pageDigest, stampPage, validateRenderedPage } from "./html-escape.mjs";

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
]);
const INPUT_TYPES = new Set(["checkbox", "radio", "search", "range", "text"]);
const FORM_CONTROLS = new Set(["input", "textarea", "select", "option"]);
// Elements whose text is CSS, metadata, or code: data bound into them would stop being page text.
const UNBINDABLE = new Set(["html", "head", "title", "meta", "style", "script"]);
const CONTENT_BINDINGS = new Set(["data-rv-text", "data-rv-count", "data-rv-each"]);

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
 */
export function contentSecurityPolicy(runtime, style) {
  const styleSrc = style === null ? "'none'" : `'sha256-${sha256(style)}'`;
  return [
    "default-src 'none'",
    `script-src 'sha256-${sha256(runtime)}'`,
    `style-src ${styleSrc}`,
    "base-uri 'none'",
    "form-action 'none'",
  ].join("; ");
}

/**
 * @param {{ profile: "report" | "interactive", template: string, data?: unknown, runtime?: string }} input
 * @returns {string} the validated page
 */
export function buildView({ profile, template, data = {}, runtime }) {
  if (profile === "report") {
    return buildReport(lf(template), data);
  }
  if (profile === "interactive") {
    return buildInteractive(lf(template), data, runtime ?? loadRuntime());
  }
  throw new ViewBuildError([`profile:${profile}`]);
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

// ---------------------------------------------------------------- report

function parseSlots(template, failures) {
  const root = { children: [] };
  const stack = [root];
  const parts = template.split(/(\{\{[^}]*\}\})/);
  parts.forEach((part, index) => {
    const top = stack[stack.length - 1];
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

function own(scope, key) {
  if (scope === null || typeof scope !== "object") {
    return undefined;
  }
  return Object.hasOwn(scope, key) ? scope[key] : undefined;
}

function textOf(value) {
  return ["string", "number", "boolean"].includes(typeof value) ? String(value) : "";
}

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

function buildReport(template, data) {
  const failures = [];
  for (const tag of template.match(/<[^>]*>/g) ?? []) {
    if (tag.includes("{{")) {
      failures.push("slot-in-tag");
    }
  }
  for (const style of template.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style/gi)) {
    if (style[1].includes("{{")) {
      failures.push("slot-in-style");
    }
  }
  const tree = parseSlots(template, failures);
  if (failures.length) {
    throw new ViewBuildError(failures);
  }
  const page = stampPage(renderSlots(tree, data));
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

function buildInteractive(template, data, runtime) {
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
  const csp = contentSecurityPolicy(runtime, styles.length ? styles[0][1] : null);
  const meta = `<meta http-equiv="Content-Security-Policy" content="${escapeHtml(csp)}">`;
  const headEnd = head.index + head[0].length;
  const scripts = `${DATA_OPEN}${json}</script><script>${runtime}</script>`;
  const html =
    template.slice(0, headEnd) +
    meta +
    template.slice(headEnd, bodyEnd) +
    scripts +
    template.slice(bodyEnd);
  const page = stamp(html);
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
  const expected = escapeHtml(contentSecurityPolicy(lf(runtime), styles.length ? styles[0][1] : null));
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
      httpEquiv += attr.name === "http-equiv" ? 1 : 0;
      checkAttribute(tag, attr, failures);
    }
  }
  if (httpEquiv !== 1) {
    failures.push("http-equiv-count");
  }

  let text = rest.replace(/<!--[\s\S]*?-->/g, "");
  text = text.replace(/<!doctype html>/gi, "");
  text = text.replace(/<\/?[A-Za-z][A-Za-z0-9]*\b[^>]*>/g, "");
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
      "usage: view-builder.mjs --profile report|interactive --template <file> --data <file.json> --out <file>\n" +
        "       view-builder.mjs --check <page.html>",
    );
    return 2;
  }
  try {
    const page = buildView({
      profile: args.profile,
      template: readFileSync(args.template, "utf8"),
      data: JSON.parse(readFileSync(args.data, "utf8")),
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
