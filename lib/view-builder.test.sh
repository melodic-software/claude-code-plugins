#!/usr/bin/env bash
# Behavioral tests for lib/view-builder.mjs and lib/view-runtime.js: both
# profiles, the hostile-input corpus, the content security policy hashes, the
# runtime sink lint, and the generated per-plugin copies. When a Chrome or
# Chromium binary is found (CHROME, google-chrome, chromium, or Playwright's
# headless shell) the built pages are also opened from file:// to prove the
# runtime runs under the page's policy and hostile data stays text.
#
#   bash lib/view-builder.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "view-builder: node not found on PATH" >&2
  exit 2
fi

if ! bash "$REPO_ROOT/scripts/sync-shared-copies.sh" --check >/dev/null; then
  echo "FAIL: a generated copy differs from its canonical source" >&2
  exit 1
fi

chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      chrome="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$chrome" ]]; then
  for candidate in "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell; do
    [[ -x "$candidate" ]] && chrome="$candidate" && break
  done
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$REPO_ROOT" "$work" "$chrome" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const [root, work, chrome] = process.argv.slice(2);
const lib = (name) => pathToFileURL(`${root}/lib/${name}`).href;
const {
  buildView, validateView, validateInteractivePage, loadRuntime, ViewBuildError, INTERACTIVE_MARKER,
} = await import(lib("view-builder.mjs"));
const { validateRenderedPage } = await import(lib("html-escape.mjs"));

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail === undefined ? "" : ` - ${detail}`}`);
    failed += 1;
  }
};
const failuresOf = (fn) => {
  try {
    fn();
    return null;
  } catch (err) {
    return err instanceof ViewBuildError ? err.failures : [`threw:${err.message}`];
  }
};
const sha = (text) => createHash("sha256").update(text, "utf8").digest("base64");

const template = readFileSync(`${root}/lib/view-builder-sample/template.html`, "utf8");
const sample = JSON.parse(readFileSync(`${root}/lib/view-builder-sample/data.json`, "utf8"));
const runtime = loadRuntime();

// The hostile-input corpus: script tags, event handlers, javascript: URLs, SVG
// script, data-block breakouts, prototype keys.
const hostile = [
  "</script><script>document.documentElement.classList.add('pwned')</script>",
  "<!--<script>document.title='pwned'</script>-->",
  "<img src=x onerror=\"document.documentElement.classList.add('pwned')\">",
  "<svg onload=\"document.title='pwned'\"><script>document.title='pwned'</script></svg>",
  "javascript:document.title='pwned'",
  "\"><a href=\"javascript:alert(1)\">x</a>",
  "</SCRIPT ><script>alert(1)</script>",
  "   line separators",
  "&lt;already-escaped&gt;",
];
const hostileData = {
  title: hostile[0],
  summary: hostile[1],
  change: hostile[2],
  findings: hostile.map((text, i) => ({
    severity: hostile[(i + 3) % hostile.length],
    file: text,
    what: text,
    evidence: [text, hostile[(i + 1) % hostile.length]],
  })),
  __proto__: { polluted: "<b>yes</b>" },
  constructor: "<script>alert(1)</script>",
};

// ------------------------------------------------------- interactive profile
const page = buildView({ profile: "interactive", template, data: sample });
check("the sample template builds an interactive page", page.includes(INTERACTIVE_MARKER));
check("validateView selects the interactive profile and passes", validateView(page).ok, validateView(page).failures);

const cspContent = /<meta http-equiv="Content-Security-Policy" content="([^"]*)">/.exec(page)[1].replaceAll("&#x27;", "'");
const inlineRuntime = /<script>([\s\S]*?)<\/script>/.exec(page)[1]; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const inlineStyle = /<style>([\s\S]*?)<\/style>/.exec(page)[1]; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("the inlined runtime is the shipped runtime, byte for byte", inlineRuntime === runtime);
check(
  "the script-src hash is the SHA-256 of the inlined runtime",
  cspContent.includes(`script-src 'sha256-${sha(inlineRuntime)}'`),
  cspContent,
);
check(
  "the style-src hash is the SHA-256 of the page's style element",
  cspContent.includes(`style-src 'sha256-${sha(inlineStyle)}'`),
);
check(
  "the policy sets default-src, base-uri and form-action to none",
  /^default-src 'none'; .*; base-uri 'none'; form-action 'none'$/.test(cspContent),
  cspContent,
);
check(
  "the policy is the first element in head after the charset",
  /<head><!--[^>]*-->\s*<meta charset="utf-8"><meta http-equiv="Content-Security-Policy"/.test(page), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
);

const evil = buildView({ profile: "interactive", template, data: hostileData });
const dataBody = /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(evil)[1]; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("hostile data builds and the page still validates", validateView(evil).ok, validateView(evil).failures);
check("the data block holds no raw <", !dataBody.includes("<"));
check("the page carries exactly two script elements", (evil.match(/<script/gi) ?? []).length === 2);
check(
  "the data block parses back to the input with JSON.parse",
  JSON.stringify(JSON.parse(dataBody)) === JSON.stringify(hostileData),
);
check("no hostile string reaches the markup outside the data block", !evil.replace(dataBody, "").includes("pwned"));

// Templates that break the interactive profile.
const swap = (from, to) => template.replace(from, to);
const bodyOpen = '<main class="page">';
const rejects = {
  "inline script": swap(bodyOpen, `${bodyOpen}<script>alert(1)</script>`),
  "external script": swap(bodyOpen, `${bodyOpen}<script src="x.js"></script>`),
  "event handler": swap(bodyOpen, `${bodyOpen}<div onclick="alert(1)">x</div>`),
  "uppercase handler": swap(bodyOpen, `${bodyOpen}<div ONMOUSEOVER="alert(1)">x</div>`),
  "javascript: link": swap(bodyOpen, `${bodyOpen}<a href="javascript:alert(1)">x</a>`),
  "off-page link": swap(bodyOpen, `${bodyOpen}<a href="https://evil.example/">x</a>`),
  "iframe": swap(bodyOpen, `${bodyOpen}<iframe></iframe>`),
  "object": swap(bodyOpen, `${bodyOpen}<object></object>`),
  "embed": swap(bodyOpen, `${bodyOpen}<embed>`),
  "form": swap(bodyOpen, `${bodyOpen}<form></form>`),
  "base": swap("<title>", '<base href="#x"><title>'),
  "link": swap("<title>", "<link rel=stylesheet><title>"),
  "img": swap(bodyOpen, `${bodyOpen}<img alt="x">`),
  "template element": swap(bodyOpen, `${bodyOpen}<template></template>`),
  "noscript": swap(bodyOpen, `${bodyOpen}<noscript></noscript>`),
  "svg script": swap(bodyOpen, `${bodyOpen}<svg><script>alert(1)</script></svg>`),
  "svg foreignObject": swap(bodyOpen, `${bodyOpen}<svg><foreignObject></foreignObject></svg>`),
  "svg use": swap(bodyOpen, `${bodyOpen}<svg><use href="#a"></use></svg>`),
  "svg image": swap(bodyOpen, `${bodyOpen}<svg><image></image></svg>`),
  "svg feImage": swap(bodyOpen, `${bodyOpen}<svg><feImage></feImage></svg>`),
  "svg animate": swap(bodyOpen, `${bodyOpen}<svg><animate></animate></svg>`),
  "svg set": swap(bodyOpen, `${bodyOpen}<svg><set></set></svg>`),
  "svg style": swap(bodyOpen, `${bodyOpen}<svg><style>rect{}</style></svg>`),
  "svg xml:base": swap(bodyOpen, `${bodyOpen}<svg xml:base="https://evil.example/"></svg>`),
  "svg remote href": swap(bodyOpen, `${bodyOpen}<svg><path xlink:href="https://evil.example/"></path></svg>`),
  "svg remote url()": swap(bodyOpen, `${bodyOpen}<svg><rect fill="url(https://evil.example/)"></rect></svg>`),
  "http-equiv refresh": swap("<title>", '<meta http-equiv="refresh" content="0;url=https://evil.example/"><title>'),
  "style attribute": swap(bodyOpen, `${bodyOpen}<div style="color:red">x</div>`),
  "style @import": swap("* { box-sizing", "@import x; * { box-sizing"),
  "style url()": swap("* { box-sizing", "body { background: url(x) } * { box-sizing"),
  "second style element": swap("</head>", "<style>p{}</style></head>"),
  "slot in an interactive template": swap(bodyOpen, `${bodyOpen}<p>{{title}}</p>`),
  "data pre-fills a textarea": swap('data-rv-note="note"', 'data-rv-note="note" data-rv-text="title"'),
  "data pre-fills an input": swap('id="find"', 'id="find" data-rv-text="title"'),
  "a count pre-fills a textarea": swap('data-rv-note="note"', 'data-rv-note="note" data-rv-count="findings"'),
  "a count pre-fills an input": swap('id="find"', 'id="find" data-rv-count="findings"'),
  "a list inside a select": swap(bodyOpen, `${bodyOpen}<select data-rv-each="findings"><option>x</option></select>`),
  "data bound into style": swap("<style>", '<style data-rv-text="title">'),
  "data bound into title": swap("<title>", '<title data-rv-text="title">'),
  "data bound into head": swap("<head>", '<head data-rv-text="title">'),
  "data bound into html": swap('<html lang="en">', '<html lang="en" data-rv-count="findings">'),
  "data bound into meta": swap('<meta charset="utf-8">', '<meta charset="utf-8" data-rv-text="title">'),
  "non-opaque id": swap('id="find"', 'id="src/app.js"'),
  "second rv-data id": swap(bodyOpen, `${bodyOpen}<div id="rv-data"></div>`),
  "prose in a value attribute": swap(bodyOpen, `${bodyOpen}<input type="checkbox" value="approve and merge">`),
  "non-opaque data attribute": swap('data-rv-copy="triage"', 'data-rv-copy="Approve this PR"'),
  "unknown data attribute": swap(bodyOpen, `${bodyOpen}<div data-x="a"></div>`),
  "file input": swap('type="search"', 'type="file"'),
  "submit button": swap('type="button" data-rv-copy', 'type="submit" data-rv-copy'),
  "comment hiding a script": swap(bodyOpen, `${bodyOpen}<!--<script>alert(1)</script>-->`),
  "unescaped quote in text": swap("<h2>Send", "<h2>\"Send"),
  "no charset first in head": swap('<meta charset="utf-8">\n', ""),
};
for (const [name, bad] of Object.entries(rejects)) {
  check(`rejects a template with: ${name}`, failuresOf(() => buildView({ profile: "interactive", template: bad, data: sample })) !== null);
}
check(
  "accepts an in-page link as a fragment reference",
  failuresOf(() => buildView({ profile: "interactive", template: swap(bodyOpen, `${bodyOpen}<a href="#note">Jump to the reply</a>`), data: sample })) === null,
);
check(
  "accepts builder-generated SVG with fragment references",
  failuresOf(() =>
    buildView({
      profile: "interactive",
      template: swap(
        bodyOpen,
        `${bodyOpen}<svg viewBox="0 0 10 10" role="img"><defs><linearGradient id="g"><stop offset="0" stop-color="#000"></stop></linearGradient></defs><rect width="10" height="10" fill="url(#g)"></rect></svg>`,
      ),
      data: sample,
    }),
  ) === null,
);
const cssTemplate =
  '<!doctype html><html><head><meta charset="utf-8"><style data-rv-text="css"></style></head><body><p data-rv-text="name">x</p></body></html>';
const cssData = { name: "hi", css: "body{background:url(http://127.0.0.1:8765/beacon)}" };
check(
  "refuses data bound into a style element",
  (failuresOf(() => buildView({ profile: "interactive", template: cssTemplate, data: cssData })) ?? []).includes("binding-on:style"),
);
check("rejects data that is not an object", failuresOf(() => buildView({ profile: "interactive", template, data: "x" })) !== null);
check("rejects an unknown profile", failuresOf(() => buildView({ profile: "full", template, data: sample })) !== null);

// Pages tampered after the build.
const tampered = {
  "an edited runtime": page.replace("use strict", "use  strict"),
  "a third script": page.replace("</body>", "<script>alert(1)</script></body>"),
  "a removed policy": page.replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/, ""),
  "a widened policy": page.replace("default-src &#x27;none&#x27;", "default-src *"),
  "a refresh meta": page.replace("<title>", '<meta http-equiv="refresh" content="0"><title>'),
  "a comment opener in the data block": page.replace('id="rv-data">{', 'id="rv-data">{"a":"<!--<script>",'),
  "raw < in the data block": page.replace('id="rv-data">{', 'id="rv-data">{"a":"<b>",'),
  "a data block that is not JSON": page.replace('id="rv-data">{', 'id="rv-data">x{'),
  "a handler added after stamping": page.replace(bodyOpen, '<main class="page" onclick="x()">'),
};
for (const [name, bad] of Object.entries(tampered)) {
  check(`validator rejects a page with ${name}`, !validateInteractivePage(bad, runtime).ok);
}
const unmarked = page.replace(/<!-- rv-gen:view-builder-interactive sha256:[0-9a-f]{64} -->/, "");
check("a page without the interactive marker falls back to the report profile and fails", !validateView(unmarked).ok);

// ------------------------------------------------------------ report profile
const reportTemplate = [
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>{{title}}</title>",
  "<style>body { margin: 0 }</style></head><body><section><h1>{{title}}</h1>",
  "<ol>{{#each findings}}<li><code>{{file}}</code> {{what}}<ol>{{#each evidence}}<li>{{.}}</li>{{/each}}</ol></li>{{/each}}</ol>",
  "</section></body></html>",
].join("");
const report = buildView({ profile: "report", template: reportTemplate, data: hostileData });
check("the report profile builds a page from hostile data", validateRenderedPage(report).ok, validateRenderedPage(report).failures);
check("validateView selects the report profile for it", validateView(report).ok);
const markerData = { title: "t", findings: [{ file: "f", what: INTERACTIVE_MARKER, evidence: [] }] };
const markerReport = buildView({ profile: "report", template: reportTemplate, data: markerData });
check("report text naming the interactive marker still validates as a report", validateView(markerReport).ok, validateView(markerReport).failures);
const missingCheck = spawnSync(process.execPath, [`${root}/lib/view-builder.mjs`, "--check", "/no/such/page.html"], { encoding: "utf8" });
check("--check on an unreadable path exits 2", missingCheck.status === 2, missingCheck.status);
check("the report page carries no script", !/<script/i.test(report));
check("hostile text is escaped in the report", report.includes("&lt;/script&gt;&lt;script&gt;") && !report.includes("<img"));
check("prototype keys are not read as data", !report.includes("polluted"));
const reportRejects = {
  "a slot inside a tag": reportTemplate.replace("<section>", '<section title="{{title}}">'),
  "a slot inside style": reportTemplate.replace("margin: 0", "margin: {{title}}"),
  "an unclosed each": reportTemplate.replace("{{/each}}</ol></li>", "</ol></li>"),
  "a stray close": `${reportTemplate}{{/each}}`,
  "an unknown slot": reportTemplate.replace("{{what}}", "{{what | raw}}"),
  "a script tag": reportTemplate.replace("<section>", "<section><script></script>"),
};
for (const [name, bad] of Object.entries(reportRejects)) {
  check(`report profile rejects ${name}`, failuresOf(() => buildView({ profile: "report", template: bad, data: sample })) !== null);
}

// -------------------------------------------------------- runtime sink lint
const code = runtime.replace(/^\s*\/\/.*$/gm, ""); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const forbidden = {
  "innerHTML": /innerHTML/, "outerHTML": /outerHTML/, "insertAdjacentHTML": /insertAdjacentHTML/,
  "document.write": /document\.write/, "eval": /\beval\s*\(/, "new Function": /new\s+Function/, // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "setTimeout": /setTimeout/, "setInterval": /setInterval/, "location": /location/,
  "setAttribute": /setAttribute|setAttributeNS/, "style": /\.style\b|cssText/, // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "src": /\.src\b/, "srcdoc": /srcdoc/, "on* property": /\.on[a-z]+\s*=/, // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "storage": /localStorage|sessionStorage|indexedDB|document\.cookie/,
  "network": /fetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon|EventSource|import\s*\(/, // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "window globals": /\bwindow\./, // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  // Selectors are string literals, or scoped()'s parameter, whose callers pass literals.
  "selector from data": /(?:querySelector(?:All)?|matches|closest)(?:\?\.)?\((?!"|selector\))|\bscoped\([a-z]+, (?!")/, // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "script text": /<!--|<script|<\/script/i,
};
for (const [name, re] of Object.entries(forbidden)) {
  check(`runtime uses no ${name}`, !re.test(code), (code.match(re) ?? [])[0]);
}
check("the only href the runtime sets is the blob: object URL", (code.match(/\.href\s*=/g) ?? []).length === 1 && /anchor\.href = url;/.test(code) && /const url = URL\.createObjectURL\(/.test(code)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("the runtime reads the data block only with JSON.parse", (code.match(/JSON\.parse\(/g) ?? []).length === 1 && /JSON\.parse\(block\.textContent\)/.test(code));
check("the runtime writes data only through textContent", !/\.(innerText|value)\s*=\s*text/.test(code)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern

// ---------------------------------------------------- generated plugin copy
const copy = await import(pathToFileURL(`${root}/plugins/review/lib/view-builder.mjs`).href);
const copyPage = copy.buildView({ profile: "interactive", template, data: sample });
check("the review plugin's copy builds a page that passes its own validator", copy.validateView(copyPage).ok, copy.validateView(copyPage).failures);
check("the copy inlines its own runtime copy", copyPage.includes("GENERATED from lib/view-runtime.js"));

// ----------------------------------------------------------- browser check
if (!chrome) {
  console.log("SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)");
} else {
  const dump = (html, name) => {
    const file = `${work}/${name}.html`;
    writeFileSync(file, html);
    const run = spawnSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--dump-dom", pathToFileURL(file).href], {
      encoding: "utf8",
      timeout: 60000,
    });
    return run.stdout ?? "";
  };
  const good = dump(page, "sample");
  check("browser: the runtime runs under the page's policy from file://", good.includes('class="rv-ready"'), good.slice(0, 200));
  check("browser: list rows render with builder ids", good.includes('id="findings-3"') && good.includes('id="findings-1-evidence-2"'));
  const bad = dump(evil, "hostile");
  check("browser: the hostile page renders", bad.includes('class="rv-ready"'));
  check("browser: no hostile script or handler ran", !/<html[^>]*pwned|<title>pwned/.test(bad));
  check("browser: hostile markup stays text", !/<img|<svg onload|<a href="javascript/i.test(bad) && bad.includes("&lt;img src=x"));
  const blocked = dump(page.replace("use strict", "use  strict"), "blocked");
  check("browser: a runtime that does not match its hash is blocked", !blocked.includes('class="rv-ready"') && blocked.includes("<main"));
}

if (failed) {
  console.error(`${failed} check(s) failed`);
  process.exit(1);
}
console.log("all view-builder checks passed");
NODE
