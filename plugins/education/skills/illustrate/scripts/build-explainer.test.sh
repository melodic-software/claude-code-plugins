#!/usr/bin/env bash
# Behavioral tests for the illustrate explainer builder: hostile text reaches
# the page only as JSON data, the page passes the interactive profile, and the
# markdown record carries the same content with no raw HTML.
#
#   bash plugins/education/skills/illustrate/scripts/build-explainer.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-explainer: node not found on PATH" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$SCRIPT_DIR" "$work" <<'NODE'
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const dir = process.argv[2];
const work = process.argv[3];
const builderPath = `${dir}/build-explainer.mjs`;
const { buildExplainerPage, buildExplainerRecord } = await import(pathToFileURL(builderPath).href);
const { validateView } = await import(pathToFileURL(`${dir}/../../../lib/view-builder.mjs`).href);

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    failed += 1;
  }
};

const hostile = [
  "</script><img src=x onerror=alert(1)>",
  `"><script>alert(1)</script>`,
  `'><img src=x onerror=alert(1)>`,
  "`${alert(1)}`",
  `" onmouseover="alert(1)`,
  "</li></ol><script>alert(1)</script>",
  "javascript:alert(1)",
  "<!-- open comment",
  "<svg onload=alert(1)>",
];
const model = {
  title: hostile[0],
  summary: [hostile[1], hostile[2]],
  diagrams: [
    { heading: hostile[3], kind: "flow", steps: [hostile[4], hostile[5], hostile[8]], caption: hostile[6], text: [hostile[7]] },
    { heading: hostile[0], kind: "stack", steps: [hostile[1], hostile[5]], caption: hostile[2] },
    { heading: hostile[4], kind: "hub", center: hostile[8], branches: [hostile[0], hostile[1]], steps: [hostile[2]] },
    { heading: hostile[5], kind: "timeline", points: [{ when: hostile[2], label: hostile[3] }, { when: hostile[6], label: "" }, {}] },
    {
      heading: hostile[6],
      kind: "compare",
      columns: [{ heading: hostile[7], items: [hostile[0], hostile[4]] }, { heading: hostile[8], items: [hostile[5]] }, { heading: "" }],
    },
    { heading: hostile[7], kind: "before-after", before: [hostile[1]], after: [hostile[2], hostile[3]] },
  ],
  terms: [{ term: hostile[0], plain: hostile[1] }, { term: "", plain: "dropped" }],
  sources: [hostile[7], hostile[6]],
};

const page = buildExplainerPage(model);
const verdict = validateView(page);
check("the builder is deterministic", page === buildExplainerPage(model));
check("a hostile model passes the interactive profile", verdict.ok, verdict.failures.join(","));
check("the page carries the interactive generator marker", page.includes("rv-gen:view-builder-interactive"));

const block = /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(page); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("the model is carried as one JSON data block", block !== null);
const data = block ? JSON.parse(block[1]) : {};
const markup = block ? page.replace(block[0], "") : page;
check("no hostile string reaches markup outside the data block", hostile.every((item) => !markup.includes(item)));
check("the data block holds no raw less-than sign", block !== null && !block[1].includes("<"));
check("a flow diagram's steps bind to the flow list", data.diagrams?.[0]?.flow?.length === 3 && data.diagrams[0].stack.length === 0);
check("a stack diagram's steps bind to the stack list", data.diagrams?.[1]?.stack?.length === 2 && data.diagrams[1].flow.length === 0);
const LISTS = ["flow", "flowcol", "stack", "branches", "points", "columns", "before", "after"];
const only = (diagram, ...keys) =>
  LISTS.every((key) => Array.isArray(diagram?.[key]) && (keys.includes(key) || diagram[key].length === 0)) &&
  (keys.includes("center") || diagram?.center === "");
check("a flow and a stack carry no other kind's fields", only(data.diagrams?.[0], "flow") && only(data.diagrams?.[1], "stack"));
const hub = data.diagrams?.[2];
check(
  "a hub diagram's center and branches reach the data block",
  hub?.center === hostile[8] && hub.branches.join("|") === [hostile[0], hostile[1]].join("|") && only(hub, "center", "branches"),
  JSON.stringify(hub),
);
const timeline = data.diagrams?.[3];
check(
  "a timeline diagram's dated points reach the data block, an empty point dropped",
  JSON.stringify(timeline?.points) === JSON.stringify([{ when: hostile[2], label: hostile[3] }, { when: hostile[6], label: "" }]) &&
    only(timeline, "points"),
  JSON.stringify(timeline),
);
const compare = data.diagrams?.[4];
check(
  "a compare diagram's columns and their items reach the data block, an empty column dropped",
  JSON.stringify(compare?.columns) ===
    JSON.stringify([{ heading: hostile[7], items: [hostile[0], hostile[4]] }, { heading: hostile[8], items: [hostile[5]] }]) &&
    only(compare, "columns"),
  JSON.stringify(compare),
);
const change = data.diagrams?.[5];
check(
  "a before-after diagram's two lists reach the data block",
  change?.before?.join("|") === hostile[1] && change.after?.join("|") === [hostile[2], hostile[3]].join("|") && only(change, "before", "after"),
  JSON.stringify(change),
);
check("a term with no word is dropped", data.terms?.length === 1);

const dataOf = (html) => JSON.parse(/<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(html)[1]); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("a diagram with no kind builds as a flow", only(dataOf(buildExplainerPage({ diagrams: [{ steps: ["a", "b"] }] })).diagrams[0], "flow"));
const refusal = (diagrams) => {
  try {
    buildExplainerPage({ diagrams });
    return "";
  } catch (error) {
    return error.message;
  }
};
const unknown = refusal([{ kind: "flow", steps: ["a"] }, { kind: "tree", steps: ["a"] }]);
check("an unknown kind is refused, naming the diagram", unknown.startsWith("diagram 2: unknown kind") && unknown.includes("tree"), unknown);
check("a kind that is not a string is refused", refusal([{ kind: ["stack"] }]).startsWith("diagram 1: unknown kind"));
const column = (n) => Array.from({ length: n }, (_, c) => ({ heading: `c${c}`, items: ["x"] }));
check("a compare of one column is refused", refusal([{ kind: "compare", columns: column(1) }]).startsWith("diagram 1: compare needs 2 to 4 columns"));
check("a compare of five columns is refused", refusal([{ kind: "compare", columns: column(5) }]).startsWith("diagram 1: compare needs 2 to 4 columns"));
check("a compare of four columns builds", refusal([{ kind: "compare", columns: column(4) }]) === "");

// The tag path to each binding in the built page: which data-rv-each lists enclose it.
const VOID = new Set(["meta", "input", "br", "hr"]);
const paths = {};
const stack = [];
const tags = page.replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, ""); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
for (const m of tags.matchAll(/<(\/?)([a-z][a-z0-9]*)\b([^>]*)>/g)) { // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  const [, close, tag, attrs] = m;
  if (close) {
    stack.pop();
    continue;
  }
  const lists = stack.filter((frame) => frame.each).map((frame) => frame.each);
  for (const [, name, value] of attrs.matchAll(/(data-rv-[a-z]+)="([^"]*)"/g)) { // portability-ok: embedded node JavaScript regex, not a shell tool pattern
    (paths[`${name}=${value}`] ??= []).push(lists.join(">"));
  }
  if (!VOID.has(tag) && !attrs.trimEnd().endsWith("/")) stack.push({ each: /data-rv-each="([^"]*)"/.exec(attrs)?.[1] }); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
}
const at = (binding) => (paths[binding] ?? []).join(",");
check("the still-unclear tick sits in the diagram card, outside every kind's list", at("data-rv-pick=") === "diagrams", at("data-rv-pick="));
for (const key of LISTS) check(`the ${key} list is one level inside the diagram card`, at(`data-rv-each=${key}`) === "diagrams", at(`data-rv-each=${key}`));
check("a hub center binds against its diagram", at("data-rv-text=center") === "diagrams", at("data-rv-text=center"));
check("a timeline point binds its date and label", at("data-rv-text=when") === "diagrams>points" && at("data-rv-text=label") === "diagrams>points");
check("a compare column's items are a list inside the column", at("data-rv-each=items") === "diagrams>columns", at("data-rv-each=items"));
check("a compare column binds its heading", at("data-rv-text=heading").split(",").includes("diagrams>columns"), at("data-rv-text=heading"));

const seven = ["one", "two", "three", "four", "five", "six", "seven"];
const longFlow = JSON.parse(
  /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec( // portability-ok: embedded node JavaScript regex, not a shell tool pattern
    buildExplainerPage({ diagrams: [{ kind: "flow", steps: seven }, { kind: "flow", steps: seven.slice(0, 4) }] }),
  )[1],
);
check("a flow of 7 steps lands in the vertical list", longFlow.diagrams[0].flowcol?.length === 7 && longFlow.diagrams[0].flow.length === 0);
check("a flow of 4 steps stays on the horizontal list", longFlow.diagrams[1].flow.length === 4 && longFlow.diagrams[1].flowcol?.length === 0);
const css = /<style>([\s\S]*?)<\/style>/.exec(page)?.[1] ?? ""; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const rule = (selector) => new RegExp(`(^|\\n)${selector.replace(".", "\\.")} \\{([^}]*)\\}`).exec(css)?.[2] ?? "";
const flowWraps = [...css.matchAll(/(^|\n)([^{\n]*)\{([^}]*)\}/g)].filter((m) => /\.flow\b/.test(m[2]) && /flex-wrap: wrap/.test(m[3])); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("the horizontal flow never wraps a line", /flex-wrap: nowrap/.test(rule(".flow")) && flowWraps.length === 0, rule(".flow"));
check("the horizontal flow scrolls inside its card", /overflow-x: auto/.test(rule(".flow")));
check("the vertical flow is one step per line", /flex-direction: column/.test(rule(".flowcol")));
const flowRow = /<ol class="flow"[^>]*><li class="step">(.*?)<\/li><\/ol>/.exec(page)?.[1] ?? ""; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const colRow = /<ol class="flowcol"[^>]*><li class="step">(.*?)<\/li><\/ol>/.exec(page)?.[1] ?? ""; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("a flow step's arrow follows its box", flowRow.indexOf("box") >= 0 && flowRow.indexOf("box") < flowRow.indexOf("arrow"), flowRow);
check("a vertical flow step's arrow follows its box", colRow.indexOf("box") >= 0 && colRow.indexOf("box") < colRow.indexOf("arrow"), colRow);
check("the last step of a flow shows no arrow", /\.flow \.step:last-child \.arrow/.test(css) && /\.flowcol \.step:last-child \.arrow/.test(css));
check("an empty vertical flow is hidden", /\.flowcol:empty/.test(css));
check("an empty timeline and an empty compare are hidden", /\.timeline:empty \{ display: none; \}/.test(css) && /\.compare:empty \{ display: none; \}/.test(css));
check("a hub with no center and no branches is hidden", /\.hub:has\(\.hub-center:empty\):has\(\.branches:empty\) \{ display: none; \}/.test(css));
check("a before-after with no items is hidden", /\.change:not\(:has\(li\)\) \{ display: none; \}/.test(css));
check("compare columns stack on a narrow page", /repeat\(auto-fit, minmax\(/.test(rule(".compare")), rule(".compare"));

const wordy = "Gamma Ray (1996): first band name, dropped after a cease-and-desist";
const capModel = { diagrams: [{ heading: "Albums", steps: ["short", wordy] }, { kind: "stack", steps: [wordy, "x".repeat(60)] }] };
const capData = JSON.parse(/<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(buildExplainerPage(capModel))[1]); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const cut = capData.diagrams[0].flow[1];
check("a long step label is cut to the cap", [...cut].length <= 40 && cut.endsWith("…"), cut);
check("a long step label is cut at a word boundary", wordy.startsWith(cut.slice(0, -1)) && wordy[[...cut].length - 1] === " ", cut);
check("a label with no space is cut hard", capData.diagrams[1].stack[1] === `${"x".repeat(39)}…`, capData.diagrams[1].stack[1]);
check("a short step label is unchanged", capData.diagrams[0].flow[0] === "short");
const capRecord = buildExplainerRecord(capModel);
check("the record carries the cut label", capRecord.includes(cut) && !capRecord.includes(wordy), capRecord);
check("an empty model still validates", validateView(buildExplainerPage({})).ok);

const record = buildExplainerRecord(model);
check("the record is deterministic", record === buildExplainerRecord(model));
check("the record holds no raw HTML", !/<[a-z!/]/i.test(record));
check("the record keeps one section per diagram plus words and sources", (record.match(/^## /gm) ?? []).length === 8);
check("a flow step sequence reads with arrows", record.includes(" → "));
check("a stack reads as a list", /^- /m.test(record));

const kinds = buildExplainerRecord({
  diagrams: [
    { heading: "Hub", kind: "hub", center: "Main band", branches: ["Side one", "Side two"] },
    { heading: "Timeline", kind: "timeline", points: [{ when: "1998", label: "First album" }, { when: "2002", label: "Third album" }, { label: "Undated" }] },
    { heading: "Compare", kind: "compare", columns: [{ heading: "A | B", items: ["one", "two"] }, { heading: "C", items: ["three"] }] },
    { heading: "Change", kind: "before-after", before: ["Old way"], after: ["New way", "Fewer steps"] },
  ],
});
const sectionOf = (text, name) => text.split(`## ${name}\n\n`)[1]?.split("\n## ")[0].trimEnd() ?? "";
const section = (name) => sectionOf(kinds, name);
const fence = (...lines) => ["```mermaid", ...lines, "```"].join("\n");
check(
  "a hub reads as its center line then bulleted branches, drawn from the center",
  section("Hub") ===
    `Main band\n\n- Side one\n- Side two\n\n${fence("flowchart LR", '    n1["Main band"]', '    n2["Side one"]', '    n3["Side two"]', "    n1 --> n2", "    n1 --> n3")}`,
  section("Hub"),
);
check(
  "a timeline reads as dated lines, drawn as a top-to-bottom chain",
  section("Timeline") ===
    `- 1998: First album\n- 2002: Third album\n- Undated\n\n${fence(
      "flowchart TB",
      '    n1["1998: First album"]',
      '    n2["2002: Third album"]',
      '    n3["Undated"]',
      "    n1 --> n2 --> n3",
    )}`,
  section("Timeline"),
);
check(
  "a compare reads as a markdown table, a pipe in a cell escaped and a short column padded, drawn as subgraphs",
  section("Compare") ===
    `| A \\| B | C |\n| --- | --- |\n| one | three |\n| two |  |\n\n${fence(
      "flowchart LR",
      '    subgraph s1["A | B"]',
      '        n1["one"]',
      '        n2["two"]',
      "    end",
      '    subgraph s2["C"]',
      '        n3["three"]',
      "    end",
    )}`,
  section("Compare"),
);
check(
  "a before-after reads as two labeled lists, drawn as two linked subgraphs",
  section("Change") ===
    `Before:\n\n- Old way\n\nAfter:\n\n- New way\n- Fewer steps\n\n${fence(
      "flowchart LR",
      '    subgraph s1["Before"]',
      '        n1["Old way"]',
      "    end",
      '    subgraph s2["After"]',
      '        n2["New way"]',
      '        n3["Fewer steps"]',
      "    end",
      "    s1 --> s2",
    )}`,
  section("Change"),
);
const shapes = buildExplainerRecord({
  diagrams: [
    { heading: "Short", kind: "flow", steps: ["Ask", "Answer"], caption: "Takeaway", text: ["More"] },
    { heading: "Long", kind: "flow", steps: seven.slice(0, 5) },
    { heading: "Layers", kind: "stack", steps: ["Top", "Bottom"] },
    { heading: "Nothing" },
  ],
});
check(
  "a flow is drawn left to right after its arrow line, before the caption and text",
  sectionOf(shapes, "Short") === `Ask → Answer\n\n${fence("flowchart LR", '    n1["Ask"]', '    n2["Answer"]', "    n1 --> n2")}\n\n**Takeaway**\n\nMore`,
  sectionOf(shapes, "Short"),
);
check(
  "a flow the page draws one step per line is drawn top to bottom",
  sectionOf(shapes, "Long").endsWith('    n1 --> n2 --> n3 --> n4 --> n5\n```') && sectionOf(shapes, "Long").includes("flowchart TB"),
  sectionOf(shapes, "Long"),
);
check(
  "a stack is drawn top to bottom with plain links",
  sectionOf(shapes, "Layers") === `- Top\n- Bottom\n\n${fence("flowchart TB", '    n1["Top"]', '    n2["Bottom"]', "    n1 --- n2")}`,
  sectionOf(shapes, "Layers"),
);
check("a diagram with nothing to draw gets no mermaid block", !shapes.split("## Nothing")[1]?.includes("```"), shapes);

// Every diagram of the hostile model is followed by exactly one mermaid block.
const blocksPer = record
  .split(/^## /m) // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  .slice(1, 1 + model.diagrams.length)
  .map((part) => (part.match(/^```mermaid$/gm) ?? []).length); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("every diagram is followed by exactly one mermaid block", blocksPer.join(",") === "1,1,1,1,1,1", blocksPer.join(","));
check("words and sources carry no mermaid block", !record.split("## Words used here")[1]?.includes("```"));

// Labels from fetched text cannot leave their quotes, close the fence, add a statement, or open
// a directive.
const evil = [
  'say "hi" now',
  "tick ` here",
  "fence ``` here",
  "line one\nclick n1 call alert()",
  "%%{init: {}}%%",
  "bracket ] here",
  "<b>bold</b> & #quot;",
];
const injected = buildExplainerRecord({
  diagrams: [
    { heading: "Flow", kind: "flow", steps: evil.slice(0, 4) },
    { heading: "Stack", kind: "stack", steps: evil },
    { heading: "Hub", kind: "hub", center: evil[4], branches: evil.slice(5) },
    { heading: "Timeline", kind: "timeline", points: evil.map((label, n) => ({ when: evil[(n + 3) % evil.length], label })) },
    { heading: "Compare", kind: "compare", columns: [{ heading: evil[0], items: evil.slice(1, 3) }, { heading: evil[4], items: [evil[3]] }] },
    { heading: "Change", kind: "before-after", before: [evil[2]], after: [evil[4]] },
  ],
});
const drawn = [...injected.matchAll(/^```mermaid\n([\s\S]*?)^```$/gm)].map((m) => m[1]); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("each hostile diagram is drawn", drawn.length === 6, String(drawn.length));
const body = drawn.join("");
check("no mermaid block holds a percent pair", !body.includes("%%"), body);
check("no mermaid block holds a backtick", !body.includes("`"), body);
const builderLine =
  /^(flowchart (LR|TB)|    n\d+\["[^"]*"\]|        n\d+\["[^"]*"\]|    subgraph s\d+\["[^"]*"\]|    end|    n\d+( (-->|---) n\d+)+|    s1 --> s2)$/; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const stray = body.split("\n").filter((line) => line !== "" && !builderLine.test(line));
check("every mermaid line is one the builder writes, each label inside its own two quotes", stray.length === 0, stray.join(" | "));
check(
  "no mermaid line starts with a statement keyword taken from a label",
  !body.split("\n").some((line) => /^\s*(click|style|classDef|linkStyle|class|call)\b/.test(line)), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  body,
);
const quoted = body.split("\n").filter((line) => line.includes('"'));
check("each quoted line holds exactly its own two quotes", quoted.every((line) => (line.match(/"/g) ?? []).length === 2), quoted.join(" | ")); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check(
  "a hostile label is kept as mermaid entity codes",
  body.includes('["say #quot;hi#quot; now"]') &&
    body.includes('["#37;#37;{init: {}}#37;#37;"]') &&
    body.includes('["line one click n1 call alert()"]') &&
    body.includes('["#lt;b#gt;bold#lt;/b#gt; #amp; #35;quot;"]') &&
    body.includes('["bracket ] here"]') &&
    body.includes('["fence here"]'),
  body,
);
check(
  "a label with nothing printable left is one space, which mermaid accepts",
  buildExplainerRecord({ diagrams: [{ steps: ["```", "\u0007"] }] }).includes('    n1[" "]\n    n2[" "]'),
);
check("the page carries no mermaid source", !page.includes("flowchart") && !page.includes("mermaid"));

const run = (args, input) => spawnSync(process.execPath, [builderPath, ...args], { input, encoding: "utf8" });
const json = JSON.stringify(model);
const both = run(["--record", `${work}/out/r.md`, "--page", `${work}/views/p.html`], json);
check("the CLI writes the record and the page", both.status === 0, both.stderr);
check("the CLI record matches the function", both.status === 0 && readFileSync(`${work}/out/r.md`, "utf8") === record);
check("the CLI page matches the function", both.status === 0 && readFileSync(`${work}/views/p.html`, "utf8") === page);
check("a model with short labels warns nothing", both.stderr === "", both.stderr);
const capped = run(["--record", `${work}/cap/r.md`, "--page", `${work}/capview/p.html`], JSON.stringify(capModel));
const warnings = capped.stderr.split("\n").filter(Boolean);
check("a cut label still exits 0", capped.status === 0, capped.stderr);
check("the CLI warns once per cut label", warnings.length === 3, capped.stderr);
check(
  "each warning names the diagram and the step",
  ["diagram 1 step 2:", "diagram 2 step 1:", "diagram 2 step 2:"].every((name, n) => (warnings[n] ?? "").includes(name)),
  capped.stderr,
);
const kindCap = run(
  ["--record", `${work}/kindcap/r.md`],
  JSON.stringify({
    diagrams: [
      { kind: "hub", center: wordy, branches: ["short", wordy] },
      { kind: "timeline", points: [{ when: "1996", label: wordy }] },
      { kind: "compare", columns: [{ heading: "A", items: [wordy] }, { heading: "B", items: ["b"] }] },
      { kind: "before-after", before: [wordy], after: ["x", wordy] },
    ],
  }),
);
const kindWarnings = kindCap.stderr.split("\n").filter(Boolean);
check(
  "a long label in each new kind is cut and named by its place",
  kindCap.status === 0 &&
    ["diagram 1 center:", "diagram 1 branch 2:", "diagram 2 point 1:", "diagram 3 column 1 item 1:", "diagram 4 before 1:", "diagram 4 after 2:"].every(
      (name, n) => (kindWarnings[n] ?? "").includes(name),
    ) &&
    kindWarnings.length === 6,
  kindCap.stderr,
);
const bad = run(["--record", `${work}/bad-kind/r.md`, "--page", `${work}/bad-kind-view/p.html`], JSON.stringify({ diagrams: [{}, { kind: "cycle" }] }));
check(
  "the CLI exits 2 on an unknown kind, naming the diagram, and writes nothing",
  bad.status === 2 && bad.stderr.includes("diagram 2: unknown kind") && !existsSync(`${work}/bad-kind/r.md`),
  bad.stderr,
);
const narrow = run(["--record", `${work}/narrow/r.md`], JSON.stringify({ diagrams: [{ kind: "compare", columns: [{ heading: "only" }] }] }));
check("the CLI exits 2 on a compare of the wrong width", narrow.status === 2 && narrow.stderr.includes("diagram 1: compare needs"), narrow.stderr);
const recordOnly = run(["--record", `${work}/only/r.md`], json);
check("--record alone writes only the record", recordOnly.status === 0 && !recordOnly.stdout.includes(".html"));
check("a missing --record exits 2", run(["--page", `${work}/x.html`], json).status === 2);
check("invalid JSON exits 2", run(["--record", `${work}/bad.md`], "{").status === 2);
check("an unknown flag exits 2", run(["--format", "html"], json).status === 2);
const clash = run(["--record", `${work}/d/x.md`, "--page", `${work}/d/x.md`], json);
check("the same file for --page and --record exits 2", clash.status === 2 && !existsSync(`${work}/d/x.md`), clash.stderr);
check("a page beside the record exits 2", run(["--record", `${work}/d/y.md`, "--page", `${work}/d/y.html`], json).status === 2);
const linky = buildExplainerRecord({ title: "![i](https://evil/x.png)", summary: ["[x](javascript:alert(1))"], sources: ["[s](https://evil/)"] });
check("the record carries no markdown link or image syntax", !/(^|[^\\])\[/.test(linky) && !/(^|[^\\])\]/.test(linky), linky);
const parity = buildExplainerRecord({ title: "\\[x\\](javascript:alert(1))" });
check("a backslash in model text cannot cancel a bracket escape", parity.split("\n")[0] === "# \\\\\\[x\\\\\\](javascript:alert(1))", parity);
writeFileSync(`${work}/blocker`, "file");
const unpaired = run(["--record", `${work}/u/r.md`, "--page", `${work}/blocker/sub/p.html`], json);
check("a failed page write leaves no unpaired record", unpaired.status === 2 && !existsSync(`${work}/u/r.md`), unpaired.stderr);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", run(["--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", run(["--check", `${work}/hand.html`]).status === 1);
writeFileSync(`${work}/edited.html`, page.replace("Still unclear", "Edited"));
check("--check flags a page edited after it was built", run(["--check", `${work}/edited.html`]).status === 1);

const skill = readFileSync(`${dir}/../SKILL.md`, "utf8");
check(
  "the skill routes the page through the builder",
  skill.includes("build-explainer.mjs") && skill.includes("Do not hand-write the HTML"),
);
check("the skill states the short-label rule", skill.includes("Labels are capped at 40 characters"));
const kindRows = ["flow", "stack", "hub", "timeline", "compare", "before-after"].filter((kind) => skill.includes(`| \`${kind}\` |`));
check("the skill documents every kind the builder accepts", kindRows.length === 6, kindRows.join(","));
check("the skill calls its diagrams diagrams, not pictures", !/small pictures|the pictures|each\s+picture/.test(skill)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern

if (failed > 0) process.exit(1);
NODE

echo "build-explainer: all cases passed"
