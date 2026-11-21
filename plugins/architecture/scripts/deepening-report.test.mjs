import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { escapeHtml } from "../lib/html-escape.mjs";
import { CSP, edgeList, legendLines, mermaidSource, parseDeepening, renderDeepening, validateDeepeningPage } from "./deepening-report.mjs";

const fixture = JSON.parse(readFileSync(new URL("./testdata/deepening-candidates.json", import.meta.url), "utf8"));

const candidate = (overrides = {}) => ({
  id: "invoice-export",
  title: "Fold the invoice export steps into one module",
  recommendation: "Strong",
  category: "in-process",
  problem: "Three call sites repeat the load, format, write sequence.",
  solution: "One export module owns loading, formatting and writing an invoice.",
  wins: ["leverage: three callers share one interface", "locality: a format fix touches one file"],
  verified: "reproduced",
  files: ["billing/loader.py", "billing/formatter.py"],
  diagram: {
    before: {
      pattern: "graph",
      nodes: [
        { id: "job", label: "jobs/nightly.py" },
        { id: "loader", label: "InvoiceLoader" },
      ],
      edges: [{ from: "job", to: "loader", leak: true, label: "reads store" }],
    },
    after: { pattern: "stack", layers: ["InvoiceExport"] },
  },
  ...overrides,
});
const record = (overrides = {}, candidates = [candidate()]) => ({
  schema_version: 1,
  repo: "example/billing",
  scope: "billing/",
  commit: "0123456789abcdef0123456789abcdef01234567",
  date: "2026-11-21",
  verification: "standard",
  counts: ["3 call sites repeat the sequence"],
  top: "invoice-export",
  top_why: "Every export path runs through it.",
  candidates,
  ...overrides,
});
const failure = (data) => {
  try {
    parseDeepening(data);
  } catch (err) {
    return err.message;
  }
  return null;
};

test("a win of six words is read and one of seven fails, naming the candidate and field", () => {
  assert.equal(failure(record({}, [candidate({ wins: ["leverage: one two three four five six", "locality: one file"] })])), null);
  const message = failure(record({}, [candidate({ wins: ["leverage: one two three four five six seven"] })]));
  assert.match(message, /invoice-export/);
  assert.match(message, /wins\[0\]/);
});

test("a card needs at least one leverage or locality win, and either one alone is enough", () => {
  assert.equal(failure(record({}, [candidate({ wins: ["locality: one file", "interface: two reads become one"] })])), null);
  assert.equal(failure(record({}, [candidate({ wins: ["leverage: three callers, one interface"] })])), null);
  assert.match(failure(record({}, [candidate({ wins: ["interface: two reads become one", "module: one owner"] })])), /invoice-export: wins.*leverage or locality/);
});

test("a win whose term is not a vocabulary term fails", () => {
  assert.match(failure(record({}, [candidate({ wins: ["maintainability: easier to change"] })])), /wins\[0\]/);
});

test("an empty solution, a missing problem and an unknown key each fail", () => {
  assert.match(failure(record({}, [candidate({ solution: " " })])), /invoice-export: solution/);
  const { problem, ...noProblem } = candidate();
  assert.match(failure(record({}, [noProblem])), /invoice-export: problem/);
  assert.match(failure(record({}, [candidate({ evidence: "x" })])), /invoice-export: unknown key evidence/);
  assert.match(failure(record({ phase15: "x" })), /unknown key phase15/);
});

test("verified takes reproduced, unverified or corrected with one clause, nothing else", () => {
  for (const ok of ["reproduced", "unverified", "corrected: two call sites, not five"]) {
    assert.equal(failure(record({}, [candidate({ verified: ok })])), null, ok);
  }
  for (const bad of ["reproduced: the copy is stale", "corrected:", "corrected: one; two", "signal-verified: true"]) {
    assert.match(failure(record({}, [candidate({ verified: bad })])), /invoice-export: verified/, bad);
  }
});

test("a mermaid label outside letters, digits, spaces and _ . / : - fails", () => {
  const diagram = candidate().diagram;
  const bad = { ...diagram, before: { ...diagram.before, nodes: [{ id: "a", label: 'x"]; click a' }] , edges: [] } };
  assert.match(failure(record({}, [candidate({ diagram: bad })])), /invoice-export: diagram.before.nodes\[0\].label/);
});

test("depends_on and top must name a candidate", () => {
  assert.match(failure(record({}, [candidate({ depends_on: "nope" })])), /depends_on/);
  assert.match(failure(record({ top: "nope" })), /top/);
});

test("the mermaid source quotes every label, styles leaks by edge position and marks deep modules", () => {
  const source = mermaidSource({
    pattern: "graph",
    direction: "LR",
    nodes: [
      { id: "a", label: "A" },
      { id: "b", label: "B", deep: true },
    ],
    edges: [
      { from: "a", to: "b" },
      { from: "b", to: "a", dashed: true, leak: true, label: "reads cache" },
    ],
  });
  assert.equal(
    source,
    [
      "flowchart LR",
      '  n0["A"]',
      '  n1["B"]',
      "  n0 --> n1",
      '  n1 -.->|"reads cache"| n0',
      "  linkStyle 1 stroke:#B04A3F,stroke-width:2px;",
      "  classDef deep fill:#141413,color:#FAF9F5,stroke:#141413,stroke-width:3px;",
      "  class n1 deep;",
    ].join("\n"),
  );
});

test("the page carries the pinned libraries, the policy, strict mermaid and the cards in their order", () => {
  const page = renderDeepening(parseDeepening(record()));
  assert.ok(page.includes(`<meta http-equiv="Content-Security-Policy" content="${escapeHtml(CSP)}">`));
  assert.ok(page.includes('<script src="https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js" integrity="sha256-M234A9h6OLcKAec25mbI92AdLOQvXkfI+v5dchB0uaM=" crossorigin="anonymous"></script>'));
  assert.ok(page.includes('<script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js" integrity="sha256-LQdTYZ03u0RSdhuHT/xq5kKengUesm9ExayDxzYvx7E=" crossorigin="anonymous"></script>'));
  assert.match(page, /securityLevel: "strict"/);
  assert.match(page, /htmlLabels: false/);
  const at = (needle) => page.indexOf(needle);
  assert.ok(at('id="index"') < at('id="top-recommendation"') && at('id="top-recommendation"') < at('<article class="card"'));
  const parts = ["title", "badges", "problem", "solution", "diagram", "wins", "verified", "files"].map((part) => at(`data-part="${part}"`));
  assert.deepEqual([...parts].sort((x, y) => x - y), parts);
  assert.deepEqual(validateDeepeningPage(page), { ok: true, failures: [] });
});

test("hostile record text stays escaped text and the page still validates", () => {
  const hostile = "</script><img src=x onerror=alert(1)>";
  const page = renderDeepening(parseDeepening(record({ repo: hostile }, [candidate({ problem: hostile, files: [hostile] })])));
  assert.ok(!page.includes("<img src=x"));
  assert.ok(page.includes("&lt;img src=x onerror=alert(1)&gt;"));
  assert.deepEqual(validateDeepeningPage(page).ok, true);
});

test("the validator refuses an added script, an event handler or a widened policy", () => {
  const page = renderDeepening(parseDeepening(record()));
  assert.equal(validateDeepeningPage(page.replace("</main>", "<script>alert(1)</script></main>")).ok, false);
  assert.equal(validateDeepeningPage(page.replace("<main>", '<main onclick="x">')).ok, false);
  assert.equal(validateDeepeningPage(page.replace("default-src &#x27;none&#x27;", "default-src *")).ok, false);
  assert.equal(validateDeepeningPage(page.replace('<pre class="mermaid">', '<pre class="mermaid">%%{init: {"securityLevel": "loose"}}%%\n')).ok, false);
});

test("scope and commit are required, and the commit must be a hex SHA", () => {
  const { scope, ...noScope } = record();
  assert.match(failure(noScope), /record: scope is missing/);
  assert.match(failure(record({ scope: " " })), /record: scope/);
  assert.match(failure(record({ commit: "HEAD" })), /record: commit/);
  assert.match(failure(record({ commit: "ABCDEF1" })), /record: commit/);
  assert.equal(failure(record({ commit: "abcdef1" })), null);
  const page = renderDeepening(parseDeepening(record({ commit: "abcdef1" })));
  assert.match(page, /scope: billing\/ · commit <span class="mono">abcdef1<\/span>/);
});

test("verification must start with a level, and the header says what that level checked", () => {
  assert.match(failure(record({ verification: "medium" })), /record: verification/);
  assert.equal(failure(record({ verification: "light (default; no team layer)" })), null);
  const page = renderDeepening(parseDeepening(record({ verification: "light (default; no team layer)" })));
  assert.match(page, /Verification: light \(default; no team layer\): nothing was reproduced/);
});

test("the bars pattern is no longer a diagram pattern", () => {
  const diagram = { ...candidate().diagram, after: { pattern: "bars", modules: [{ label: "x", interface: 1, implementation: 2 }] } };
  assert.match(failure(record({}, [candidate({ diagram })])), /diagram.after.pattern/);
});

test("the text fallback lists each edge as from → to, with its label and its leak or pointer mark", () => {
  const lines = edgeList({
    nodes: [
      { id: "a", label: "jobs/nightly.py" },
      { id: "b", label: "InvoiceExport", deep: true },
      { id: "c", label: "orphan.py" },
    ],
    edges: [
      { from: "a", to: "b", label: null, dashed: false, leak: false },
      { from: "b", to: "a", label: "reads store", dashed: true, leak: true },
    ],
  });
  assert.deepEqual(lines, ["Deep module: InvoiceExport", "jobs/nightly.py → InvoiceExport", "InvoiceExport → jobs/nightly.py: reads store (leak, pointer)", "orphan.py"]);
});

test("a graph with edges goes to Mermaid beside its text fallback; one with no edges is drawn as boxes", () => {
  const page = renderDeepening(parseDeepening(record()));
  assert.match(page, /<pre class="mermaid">[^<]*<\/pre><ul class="edge-list"><li>jobs\/nightly.py → InvoiceLoader: reads store \(leak\)<\/li><\/ul>/);
  const edgeless = { ...candidate().diagram, before: { pattern: "graph", nodes: [{ id: "a", label: "one.md" }, { id: "b", label: "two.md" }] } };
  const boxes = renderDeepening(parseDeepening(record({}, [candidate({ diagram: edgeless })])));
  assert.doesNotMatch(boxes, /class="mermaid"/);
  assert.match(boxes, /<div class="drawn boxes v"><div class="box">one.md<\/div><div class="box">two.md<\/div><\/div>/);
});

const sidebar = (page) => page.slice(page.indexOf('<nav id="index"'), page.indexOf("</nav>", page.indexOf('<nav id="index"')));
const sidebarTargets = (page) => [...sidebar(page).matchAll(/href="#([a-z0-9-]+)"/g)].map((match) => match[1]);
const shownCards = (page) => [...page.matchAll(/<article class="card" id="([a-z0-9-]+)"( hidden="until-found")?/g)].filter((match) => !match[2]).map((match) => match[1]);

test("the sidebar item carries the badge, the Verified word and the solution, and the card links the candidate it depends on", () => {
  const first = candidate({ verified: "corrected: two call sites, not five" });
  const second = candidate({ id: "tax-rounding", title: "Move rounding into TaxCalculator", depends_on: "invoice-export" });
  const page = renderDeepening(parseDeepening(record({}, [first, second])));
  const item = /<a class="reader-item"[^>]*href="#c-invoice-export"[^>]*>([\s\S]*?)<\/a>/.exec(sidebar(page))[1];
  assert.match(item, /INVOICE-EXPORT/);
  assert.match(item, /Fold the invoice export steps into one module/);
  assert.match(item, /<span class="badge badge-strong">Strong<\/span>/);
  assert.match(item, /Verified: corrected/);
  assert.match(item, /2 files/);
  assert.match(item, /Problem:<\/span> Three call sites repeat the load, format, write sequence\./);
  assert.match(item, /Solution:<\/span> One export module owns loading, formatting and writing an invoice\./);
  assert.doesNotMatch(item, /Depends on/);
  assert.match(/<a class="reader-item"[^>]*href="#c-tax-rounding"[^>]*>([\s\S]*?)<\/a>/.exec(sidebar(page))[1], /Depends on INVOICE-EXPORT/);
  assert.match(page, /data-part="depends-on"><h4>Depends on<\/h4><p class="v"><a href="#c-invoice-export">Fold the invoice export steps into one module<\/a><\/p>/);
});

test("the sidebar lists every candidate under its badge, Strong first, with the top recommendation leading its badge", () => {
  const ids = [
    ["maybe", "Speculative"],
    ["first-strong", "Strong"],
    ["worth", "Worth exploring"],
    ["top-pick", "Strong"],
  ];
  const page = renderDeepening(parseDeepening(record({ top: "top-pick" }, ids.map(([id, recommendation]) => candidate({ id, recommendation })))));
  assert.deepEqual(sidebarTargets(page), ["c-top-pick", "c-first-strong", "c-worth", "c-maybe"]);
  const groups = [...sidebar(page).matchAll(/<li class="reader-band">([^<]*)<\/li>/g)].map((match) => match[1]);
  assert.deepEqual(groups, ["Strong · 2", "Worth exploring · 1", "Speculative · 1"]);
  assert.match(sidebar(page), /href="#c-top-pick"[^>]*aria-current="true"/);
});

test("the page opens on the top recommendation with its reason and shows one card at a time", () => {
  const page = renderDeepening(parseDeepening(fixture));
  assert.equal(page.split('<article class="card"').length - 1, 23);
  assert.deepEqual(shownCards(page), ["c-s1"]);
  assert.match(page, /<section id="top-recommendation" class="top">\n<h2>Top recommendation: S1 [^<]+<\/h2>\n<p>Two parsers already read the same ledger differently/);
  assert.match(page, /<article class="card" id="c-s1"[\s\S]*?<p class="badges" data-part="badges">[^\n]*<span class="top-chip">Top recommendation<\/span><\/p>/);
  assert.equal(page.split('<span class="top-chip">').length - 1, 2);
  assert.equal(sidebarTargets(page).filter((target) => target.startsWith("c-")).length, 23);
  assert.equal(sidebarTargets(page)[0], "c-s1");
});

test("previous and next buttons step through the candidates", () => {
  const page = renderDeepening(parseDeepening(fixture));
  assert.match(page, /<button type="button" data-step="-1">Previous candidate<\/button>/);
  assert.match(page, /<button type="button" data-step="1">Next candidate<\/button>/);
  assert.match(page, /<p class="reader-pos" aria-live="polite">1 of 23<\/p>/);
});

test("before and after diagrams carry an enlarge button, and the page has one overlay with a Close button", () => {
  const page = renderDeepening(parseDeepening(fixture));
  assert.equal(page.split("<figure data-enlarge").length - 1, 46);
  assert.equal(page.split('<button type="button" class="zoom-open"').length - 1, 46);
  assert.match(page, /aria-label="Enlarge the before diagram: S1 /);
  assert.equal(page.split("<dialog ").length - 1, 1);
  assert.match(page, /<dialog id="zoom" class="zoom" aria-labelledby="zoom-title">[\s\S]*<button type="button" data-zoom-close>Close<\/button>/);
  assert.ok(validateDeepeningPage(page).ok);
});

test("each CDN script carries crossorigin and the SRI hash of its pinned file, and a page without them fails validation", () => {
  const page = renderDeepening(parseDeepening(record()));
  assert.match(page, /<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/@tailwindcss\/browser@4\.3\.5\/dist\/index\.global\.js" integrity="sha256-LQdTYZ03u0RSdhuHT\/xq5kKengUesm9ExayDxzYvx7E=" crossorigin="anonymous"><\/script>/);
  assert.match(page, /<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/mermaid@12\.3\.0\/dist\/mermaid\.min\.js" integrity="sha256-M234A9h6OLcKAec25mbI92AdLOQvXkfI\+v5dchB0uaM=" crossorigin="anonymous"><\/script>/);
  assert.ok(validateDeepeningPage(page).ok);
  assert.ok(!validateDeepeningPage(page.replace(/ integrity="[^"]*"/, "")).ok);
});

test("a finding kept as it is gets its own section, reached from the sidebar, never a card, a sidebar item or a badge", () => {
  const kept = [{ title: "Leave the export copies alone", reason: "Each copy has one reader and a drift check.", files: ["billing/a.md", "billing/b.md"] }];
  const page = renderDeepening(parseDeepening({ ...record(), kept }));
  assert.match(page, /<a href="#kept">looked at, no change: 1<\/a>/);
  assert.equal(sidebarTargets(page).at(-1), "kept");
  assert.match(sidebar(page), /<a class="reader-kept" href="#kept">Looked at, no change · 1<\/a>/);
  assert.match(page, /<section id="kept" hidden="until-found" tabindex="-1">\n<h2>Looked at, no change<\/h2>/);
  assert.match(page, /<div class="kept-item"><h3>Leave the export copies alone<\/h3><p>Each copy has one reader and a drift check.<\/p><ul class="files"><li>billing\/a.md<\/li><li>billing\/b.md<\/li><\/ul><\/div>/);
  assert.equal(page.split("<article class=\"card\"").length - 1, record().candidates.length);
  assert.ok(!sidebar(page).includes("Leave the export copies alone"));
  assert.ok(validateDeepeningPage(page).ok);
  assert.doesNotMatch(renderDeepening(parseDeepening(record())), /id="kept"|href="#kept"/);
  assert.throws(() => parseDeepening({ ...record(), kept: [{ ...kept[0], reason: " " }] }), /kept\[0\]\.reason/);
  assert.throws(() => parseDeepening({ ...record(), kept: [{ ...kept[0], badge: "Strong" }] }), /unknown key badge/);
});

test("the top recommendation lists every candidate built on it, directly or through another", () => {
  const top = candidate();
  const direct = candidate({ id: "tax-rounding", title: "Move rounding into TaxCalculator", depends_on: "invoice-export" });
  const indirect = candidate({ id: "tax-report", title: "Report tax from one place", depends_on: "tax-rounding" });
  const page = renderDeepening(parseDeepening(record({}, [top, direct, indirect])));
  assert.match(page, /<h4>Built on it<\/h4><ul class="built-on"><li><a href="#c-tax-rounding">TAX-ROUNDING [^<]+<\/a><\/li><li><a href="#c-tax-report">TAX-REPORT [^<]+<\/a>, through TAX-ROUNDING<\/li><\/ul>/);
  assert.equal(page.split('<p class="back"><a href="#index">').length, 4);
});

test("the legend names the drawing styles, badges and terms the page uses and no others", () => {
  const terms = (data) => legendLines(parseDeepening(data)).map(([term]) => term);
  const leakOnly = terms(record());
  for (const term of ["Rust arrow, solid or dotted", "Dark, heavy-bordered box", "Strong", "in-process", "leverage", "locality", "reproduced"]) assert.ok(leakOnly.includes(term), term);
  for (const term of ["Dotted gray arrow", "Solid gray arrow", "Worth exploring", "mock", "interface", "unverified"]) assert.ok(!leakOnly.includes(term), term);
  const before = { pattern: "graph", nodes: [{ id: "a", label: "A" }, { id: "b", label: "B" }], edges: [{ from: "a", to: "b", dashed: true }] };
  const dotted = terms(record({}, [candidate({ category: "mock", diagram: { ...candidate().diagram, before } })]));
  assert.ok(dotted.includes("Dotted gray arrow") && dotted.includes("mock") && !dotted.includes("Rust arrow, solid or dotted"));
});

test("the 23-candidate fixture renders every card with a solution, wins and a diagram and no empty part", () => {
  const page = renderDeepening(parseDeepening(fixture));
  const cards = page.split("<article ").slice(1).filter((card) => card.includes('class="card'));
  assert.equal(cards.length, 23);
  for (const card of cards) {
    for (const part of ["solution", "wins", "diagram"]) assert.ok(card.includes(`data-part="${part}"`), part);
  }
  assert.doesNotMatch(page, /class="v\b[^"]*"[^>]*>\s*<\//);
  assert.equal(validateDeepeningPage(page).ok, true);
});
