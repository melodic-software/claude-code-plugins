// Deterministic HTML escape for text and double-quoted attribute positions,
// plus the generator marker a rendered page must carry so a page assembled
// without this module is detectable after the fact.
//
// Claim: the five HTML-significant characters encode as &amp; &lt; &gt; &quot;
// &#x27;, ampersand first, and a double-quoted attribute value must not contain
// a raw quotation mark. Apostrophe uses the semicolon form from the OWASP
// example table. A numeric reference without the semicolon would keep consuming
// hex digits (WHATWG character-reference parsing).
// Basis: OWASP XSS Prevention Cheat Sheet, HTML entity example table and the
// "Output Encoding Rules Summary" HTML Entity row, fetched 2026-09-28 from
// https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
// (the example table writes &#x27;; the summary row names the same mapping).
// WHATWG HTML living standard, last updated 25 September 2026, text and
// double-quoted attribute restrictions:
// https://html.spec.whatwg.org/multipage/syntax.html#elements-2
// https://html.spec.whatwg.org/multipage/syntax.html#attributes-2
// Recheck: that OWASP table or those WHATWG restrictions change what a quoted
// attribute or a text node may contain.
//
// This encoding is the text and quoted-attribute rule only. It does not make
// a URL, an event-handler name, or the contents of script or style safe. The
// page builder never interpolates into those positions, and validateRenderedPage
// rejects them.

import { createHash } from "node:crypto";

const MARKER_PREFIX = "<!-- rv-gen:escape-helper-v1 sha256:";
const MARKER_SUFFIX = " -->";

const ALLOWED_TAGS = new Set([
  "html",
  "head",
  "meta",
  "title",
  "style",
  "body",
  "p",
  "h1",
  "h2",
  "h3",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
  "section",
  "code",
  "ol",
  "li",
]);

const ALLOWED_ATTRS = new Set([
  "charset",
  "class",
  "content",
  "id",
  "lang",
  "name",
  "title",
]);

// A value this module emits: raw text, or one of the five entities, and nothing
// else that is HTML-significant. Used on attribute values and on the text left
// after tags and comments are removed.
const ESCAPED_TEXT =
  /^(?:[^&<>"']|&(?:amp|lt|gt|quot|#x27);)*$/;

/**
 * Escape for HTML text and for a quoted attribute. Ampersand is replaced
 * first so an existing entity is not double-decoded. Null and undefined
 * become the empty string. The same input always produces the same output.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#x27;");
}

/**
 * @param {string} html page bytes before the marker is inserted
 * @returns {string}
 */
export function pageDigest(html) {
  return createHash("sha256").update(html, "utf8").digest("hex");
}

/**
 * Insert the generator marker immediately after the first `<head>`. The digest
 * covers the page before insertion, so stripping that one comment restores the
 * digested bytes.
 *
 * @param {string} html
 * @returns {string}
 */
export function stampPage(html) {
  const marker = `${MARKER_PREFIX}${pageDigest(html)}${MARKER_SUFFIX}`;
  const token = "<head>";
  const at = html.indexOf(token);
  if (at < 0) {
    return marker + html;
  }
  const cut = at + token.length;
  return html.slice(0, cut) + marker + html.slice(cut);
}

/**
 * @param {string} raw attribute source inside a tag, excluding the tag name
 * @returns {{ name: string, value: string }[]}
 */
function parseAttributes(raw) {
  const attrs = [];
  const re =
    /([^\s"'>=/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  let match = re.exec(raw);
  while (match) {
    attrs.push({
      name: match[1].toLowerCase(),
      value: match[2] ?? match[3] ?? match[4] ?? "",
    });
    match = re.exec(raw);
  }
  return attrs;
}

/**
 * @param {string} html
 * @param {string[]} failures
 */
function scanStructure(html, failures) {
  const tagRe = /<\/?([A-Za-z][A-Za-z0-9]*)\b([^>]*)>/g;
  let match = tagRe.exec(html);
  while (match) {
    const name = match[1].toLowerCase();
    const closing = match[0].startsWith("</");
    if (!ALLOWED_TAGS.has(name)) {
      failures.push(`tag:${name}`);
    }
    if (!closing) {
      for (const attr of parseAttributes(match[2])) {
        if (!ALLOWED_ATTRS.has(attr.name)) {
          failures.push(`attr:${attr.name}`);
        }
        if (!ESCAPED_TEXT.test(attr.value)) {
          failures.push("unescaped");
        }
      }
    }
    match = tagRe.exec(html);
  }

  let rest = html.replace(/<!--[\s\S]*?-->/g, "");
  rest = rest.replace(/<!doctype html>/gi, "");
  rest = rest.replace(/<\/?[A-Za-z][A-Za-z0-9]*\b[^>]*>/g, "");
  if (rest.includes("<")) {
    failures.push("raw-lt");
  }
  if (!ESCAPED_TEXT.test(rest)) {
    failures.push("unescaped");
  }
}

/**
 * A page produced by stampPage passes. A page assembled by concatenating
 * input, or a hand-written page that never went through stampPage, fails.
 * Structural failures stand even when a digest was forged around hostile tags.
 *
 * @param {string} html
 * @returns {{ ok: boolean, failures: string[] }}
 */
export function validateRenderedPage(html) {
  const failures = [];
  const markerPattern = /<!-- rv-gen:escape-helper-v1 sha256:([0-9a-f]{64}) -->/g;
  const markers = html.match(markerPattern) ?? [];
  if (markers.length !== 1) {
    failures.push("marker");
  } else {
    const digest = markers[0].slice(MARKER_PREFIX.length, MARKER_PREFIX.length + 64);
    const stripped = html.replace(markers[0], "");
    if (pageDigest(stripped) !== digest) {
      failures.push("marker-digest");
    }
  }
  scanStructure(html, failures);
  return { ok: failures.length === 0, failures };
}
