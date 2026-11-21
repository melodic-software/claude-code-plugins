import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { escapeHtml } from "../lib/html-escape.mjs";
import { CSP, mermaidSource, parseDeepening, renderDeepening, validateDeepeningPage } from "./deepening-report.mjs";

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
  assert.ok(page.includes('<script src="https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js"></script>'));
  assert.ok(page.includes('<script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js"></script>'));
  assert.match(page, /securityLevel: "strict"/);
  assert.match(page, /htmlLabels: false/);
  const at = (needle) => page.indexOf(needle);
  assert.ok(at('id="top-recommendation"') < at('id="index"') && at('id="index"') < at('id="band-strong"'));
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

test("the 24-candidate fixture renders every card with a solution, wins and a diagram and no empty part", () => {
  const page = renderDeepening(parseDeepening(fixture));
  const cards = page.split("<article ").slice(1).filter((card) => card.includes('class="card'));
  assert.equal(cards.length, 24);
  for (const card of cards) {
    for (const part of ["solution", "wins", "diagram"]) assert.ok(card.includes(`data-part="${part}"`), part);
  }
  assert.doesNotMatch(page, /class="v\b[^"]*"[^>]*>\s*<\//);
  assert.equal(validateDeepeningPage(page).ok, true);
});
