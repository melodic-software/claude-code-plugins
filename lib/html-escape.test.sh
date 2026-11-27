#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "html-escape: node not found on PATH" >&2
  exit 2
fi

node --input-type=module - "$REPO_ROOT" <<'NODE'
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const helperUrl = pathToFileURL(`${root}/lib/html-escape.mjs`).href;
const { escapeHtml, stampPage, validateRenderedPage } = await import(helperUrl);
const { buildView } = await import(pathToFileURL(`${root}/lib/view-builder.mjs`).href);
const template = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{{title}}</title>
</head>
<body>
<h1>{{title}}</h1>
<p>{{pr}}</p>
<p>{{summary}}</p>
<table><tbody>{{#each risks}}<tr><td>{{area}}</td><td>{{level}}</td><td>{{why}}</td></tr>{{/each}}</tbody></table>
{{#each files}}<section><h3><code>{{path}}</code></h3><p>{{notes}}</p></section>{{/each}}
<ol>{{#each focus}}<li>{{.}}</li>{{/each}}</ol>
</body>
</html>
`;
const buildPage = (data) => buildView({ profile: "report", template, data });

let failed = 0;
const ok = (name) => console.log(`ok: ${name}`);
const fail = (name, detail) => {
  console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
  failed += 1;
};
const check = (name, cond, detail) => (cond ? ok(name) : fail(name, detail));

const five = `&<>"'`;
check(
  "escapeHtml encodes the five HTML-significant characters, ampersand first",
  escapeHtml(five) === "&amp;&lt;&gt;&quot;&#x27;",
  escapeHtml(five),
);
check(
  "an existing entity is not double-decoded",
  escapeHtml("&lt;") === "&amp;lt;",
  escapeHtml("&lt;"),
);
check(
  "null and undefined escape to empty",
  escapeHtml(null) === "" && escapeHtml(undefined) === "",
);

const hostile = [
  `<img src=x onerror=alert(1)>`,
  `"><script>alert(1)</script>`,
  `'><img src=x onerror=alert(1)>`,
  `" onmouseover="alert(1)`,
  "javascript:alert(1)",
  "data:text/html,<script>alert(1)</script>",
  "&lt;already",
  "https://evil.example/payload",
  "</td></tr><script>alert(1)</script>",
];
const model = {
  title: hostile[0],
  pr: hostile[1],
  summary: hostile[2],
  risks: [{ area: hostile[3], level: hostile[4], why: hostile[5] }],
  files: [{ path: hostile[6], notes: hostile[7] }],
  focus: [hostile[8]],
};
const page = buildPage(model);
check("the builder is deterministic", page === buildPage(model));
const verdict = validateRenderedPage(page);
check(
  "a page routed through the helper passes the validator",
  verdict.ok,
  verdict.failures.join(","),
);
check("hostile markup is not a live img tag", !page.includes("<img"));
check("hostile markup is not a live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check(
  "handler text stays in a text node and is not an attribute name",
  page.includes("onerror=alert") && !verdict.failures.some((item) => item.startsWith("attr:on")),
);
check(
  "no external resource tag is emitted",
  !/<(?:link|iframe|object|embed|img|script|base)\b/i.test(page) && // portability-ok: embedded node JavaScript regex, not a shell tool pattern
    !verdict.failures.some((item) => item.startsWith("attr:")),
);
check(
  "quote and angle-bracket payloads are inert text",
  page.includes(escapeHtml(hostile[0])) &&
    page.includes(escapeHtml(hostile[1])) &&
    page.includes("&#x27;&gt;"),
);
check(
  "a URL in the diff stays text and is not an href",
  page.includes("https://evil.example/payload") && !page.includes("href="),
);

const naive = `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`;
const naiveVerdict = validateRenderedPage(naive);
check(
  "a page assembled without routing input through the helper is flagged",
  !naiveVerdict.ok &&
    naiveVerdict.failures.includes("marker") &&
    naiveVerdict.failures.some((item) => item.startsWith("tag:")),
  naiveVerdict.failures.join(","),
);

const hand = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${escapeHtml("safe")}</title></head><body><h1>${escapeHtml(hostile[0])}</h1></body></html>`;
const handVerdict = validateRenderedPage(hand);
check(
  "a hand-written page that escapes but bypasses the builder is flagged",
  !handVerdict.ok && handVerdict.failures.includes("marker"),
  handVerdict.failures.join(","),
);

const forged = page.replace(
  /sha256:[0-9a-f]{64}/,
  "sha256:0000000000000000000000000000000000000000000000000000000000000000",
);
check(
  "a stale or zeroed marker digest is flagged",
  validateRenderedPage(forged).failures.includes("marker-digest"),
  validateRenderedPage(forged).failures.join(","),
);

// Anyone can recompute the digest, so a restamped page is judged by the
// structural scan alone.
const restampedSafe = validateRenderedPage(stampPage(hand));
check(
  "a hand-written page with a recomputed digest passes on structure alone",
  restampedSafe.ok,
  restampedSafe.failures.join(","),
);
const restampedHostile = validateRenderedPage(
  stampPage(hand.replace("</body>", "<script>alert(1)</script></body>")),
);
check(
  "a hostile page with a recomputed digest fails on structure alone",
  restampedHostile.failures.includes("tag:script") &&
    !restampedHostile.failures.some((item) => item.startsWith("marker")),
  restampedHostile.failures.join(","),
);

// Style text is raw CSS: none of these carries an HTML-significant character,
// yet each fetches a resource or runs code.
const hostileCss = [
  "@import url(https://evil.example/x.css);",
  "body{background:url(//evil.example/p.gif)}",
  "body{background:URL(//evil.example/p.gif)}",
  "body{background:u\\72l(//evil.example/p.gif)}",
  "@IMPORT url(//evil.example/x.css);",
  "body{width:expression(alert(1))}",
  'body{background-image:image-set("https://evil.example/pixel.png" 1x)}',
  "body{background-image:-webkit-image-set('//evil.example/pixel.png' 1x)}",
  'body{background-image:IMAGE-SET("https://evil.example/pixel.png" 1x)}',
  'body{background-image:image("https://evil.example/pixel.png")}',
  'body{background-image:src("https://evil.example/pixel.png")}',
];
for (const css of hostileCss) {
  const styled = stampPage(hand.replace("</head>", `<style>${css}</style></head>`));
  const styledVerdict = validateRenderedPage(styled);
  check(
    `resource-loading CSS is flagged: ${css}`,
    styledVerdict.failures.includes("style"),
    styledVerdict.failures.join(","),
  );
}
// A browser ends style text at `</style` followed by space, slash or `>`, and
// runs an unclosed style element to end of file.
const evilCss = "body{background:url(//evil.example/x)}";
for (const [label, styleBlock] of [
  ["</style x>", `<style>${evilCss}</style x>`],
  ["</style/>", `<style>${evilCss}</style/>`],
  ["no close tag", `<style>${evilCss}`],
]) {
  const verdict = validateRenderedPage(stampPage(hand.replace("</head>", `${styleBlock}</head>`)));
  check(
    `resource-loading CSS is flagged with ${label}`,
    verdict.failures.includes("style"),
    verdict.failures.join(","),
  );
}
const plainCss = validateRenderedPage(
  stampPage(hand.replace("</head>", "<style>body { color: #141413; }</style></head>")),
);
check("plain CSS in a style element passes", plainCss.ok, plainCss.failures.join(","));

const styledHand = (css) => validateRenderedPage(stampPage(hand.replace("</head>", `<style>${css}</style></head>`)));
const png = "url(data:image/png;base64,iVBORw0KGgo=)";
const jpeg = "url(data:image/jpeg;base64,/9j/4AAQ+A==)";
const woff2 = "url(data:font/woff2;base64,d09GMgABAAA=)";
const admittedCss = {
  "quoted font stacks, attribute selectors and child combinators":
    ":root { --mono: ui-monospace, 'SF Mono', Menlo, monospace; } :root[data-theme=\"dark\"] { color-scheme: dark; } section > p { margin: 0; }",
  "a PNG in the logo slot": `.rv-logo { background-image: ${png}; }`,
  "a JPEG in the logo slot after another rule": `body{margin:0}.rv-logo{background-image:${jpeg}}`,
  "the logo slot inside a media block": `@media (prefers-color-scheme: dark) { .rv-logo { background-image: ${png} } }`,
  "the logo slot after a comment": `/* brand */ .rv-logo{background-image:${png}}`,
  "a WOFF2 font in @font-face": `@font-face { font-family: 'Brand Serif'; src: ${woff2}; }`,
  "WOFF, TTF and OTF fonts in @font-face":
    "p{margin:0}@font-face{font-family:Brand;src:url(data:font/woff;base64,d09GRg==),url(data:font/ttf;base64,AAEAAA==),url(data:font/otf;base64,T1RUTw==)}",
};
for (const [name, css] of Object.entries(admittedCss)) {
  const verdict = styledHand(css);
  check(`the validator admits ${name}`, verdict.ok, verdict.failures.join(","));
}
const refusedCss = {
  "an image data URL outside the logo slot": `body{background-image:${png}}`,
  "an image data URL on another logo property": `.rv-logo{background:${png}}`,
  "an image data URL in a selector list with the logo slot": `p,.rv-logo{background-image:${png}}`,
  "an image data URL on a descendant of the logo slot": `.rv-logo p{background-image:${png}}`,
  "a logo slot nested in a style rule": `.evil{.rv-logo{background-image:${png}}}`,
  "a font data URL behind a comment that fakes @font-face": `.x{/*}@font-face{*/background:${woff2}}`,
  "a remote URL inside a comment": "/* url(//evil.example/x) */ p{margin:0}",
  "a logo slot with a declaration before the image": `.rv-logo{color:red;background-image:${png}}`,
  "a logo slot with a declaration after the image": `.rv-logo{background-image:${png};color:red}`,
  "an SVG data URL in the logo slot": ".rv-logo{background-image:url(data:image/svg+xml;base64,PHN2Zz4=)}",
  "a GIF data URL in the logo slot": ".rv-logo{background-image:url(data:image/gif;base64,R0lGODlh)}",
  "a data URL that is not base64 in the logo slot": ".rv-logo{background-image:url(data:image/png,abc)}",
  "a data URL with a parameter in the logo slot": ".rv-logo{background-image:url(data:image/png;charset=x;base64,AA==)}",
  "a remote URL in the logo slot": ".rv-logo{background-image:url(https://evil.example/logo.png)}",
  "a protocol-relative URL in the logo slot": ".rv-logo{background-image:url(//evil.example/logo.png)}",
  "a blob URL in the logo slot": ".rv-logo{background-image:url(blob:x)}",
  "a font data URL outside @font-face": `body{background:${woff2}}`,
  "an image data URL in @font-face": `@font-face{font-family:Brand;src:${png}}`,
  "a text/html data URL in @font-face": "@font-face{src:url(data:text/html;base64,PGI+)}",
  "a font data URL that is not base64 in @font-face": "@font-face{src:url(data:font/woff2,abc)}",
  "a remote URL in @font-face": "@font-face{src:url(https://evil.example/f.woff2)}",
  "a remote URL beside a font data URL in @font-face": `@font-face{src:${woff2},url(//evil.example/f.woff2)}`,
  "an uppercase URL in @font-face": "@font-face{src:URL(data:font/woff2;base64,AA==)}",
  "an @import beside @font-face": `@import x;@font-face{src:${woff2}}`,
  "a raw < inside a style body": "/* <img src=x> */ body{margin:0}",
};
for (const [name, css] of Object.entries(refusedCss)) {
  check(`the validator refuses ${name}`, styledHand(css).failures.includes("style"), styledHand(css).failures.join(","));
}
const dataUrl = "data:image/png;base64,iVBORw0KGgo=";
for (const attr of ["src", "href", "srcset", "poster", "background", "action", "formaction", "data", "cite", "xlink:href", "style"]) {
  const verdict = validateRenderedPage(stampPage(hand.replace("<h1>", `<h1 ${attr}="${dataUrl}">`)));
  check(`a data URL in a ${attr} attribute is refused`, verdict.failures.includes(`attr:${attr}`), verdict.failures.join(","));
}
const imgVerdict = validateRenderedPage(stampPage(hand.replace("</h1>", `</h1><img src="${dataUrl}" alt="logo">`)));
check("an img element with a data URL is refused", imgVerdict.failures.includes("tag:img"), imgVerdict.failures.join(","));

const tampered = page.replace("</body>", "<script>alert(1)</script></body>");
check(
  "editing a stamped page to add a script is flagged",
  validateRenderedPage(tampered).failures.includes("tag:script"),
  validateRenderedPage(tampered).failures.join(","),
);
const smuggled = stampPage(
  '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>t</title></head><body><!-- <style> -->unescaped "payload" & \'quotes\'</style> --></body></html>',
);
check(
  "a comment-smuggled <style> cannot hide unescaped body text",
  validateRenderedPage(smuggled).failures.includes("unescaped"),
  validateRenderedPage(smuggled).failures.join(","),
);

const emptyVerdict = validateRenderedPage(buildPage({}));
check(
  "an empty model still validates",
  emptyVerdict.ok,
  emptyVerdict.failures.join(","),
);

if (failed > 0) process.exit(1);
NODE

echo "html-escape: all cases passed"
