// /visualization:present: the deck gate (root outside a working tree, K2 decks
// text-only, the shared publish gate over every file) and the skill's contract
// (quickstart at run time, no hard-coded type_url, gate before the create call).
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const SKILL = join(PLUGIN, "skills/present");
const CHECK = join(SKILL, "scripts/check-deck.mjs");
const { checkDeck, k2Refusals } = await import(CHECK);

const scratch = realpathSync(mkdtempSync(join(tmpdir(), "present-test-")));
after(() => rmSync(scratch, { recursive: true, force: true }));

let n = 0;
function deck(slides, index = { v: 4, title: "Talk", order: Object.keys(slides) }) {
  const root = join(scratch, `deck-${(n += 1)}`);
  mkdirSync(join(root, "project/slides"), { recursive: true });
  writeFileSync(join(root, "project/deck.json"), JSON.stringify(index));
  for (const [id, html] of Object.entries(slides)) writeFileSync(join(root, `project/slides/${id}.html`), html);
  return root;
}
const slide = (id, body) => `<section id="${id}" style="background:#fbfbf8;padding:128px">${body}</section>`;
const plain = { cover: slide("cover", "<h1 style=\"font-size:96px\">Merge queues</h1><p>a &lt;b&gt; one = 2 url(x)</p><aside>Hi.</aside>") };

describe("check-deck", () => {
  test("a clean deck from a public or repository-free source publishes", () => {
    for (const visibility of ["PUBLIC", "NONE"]) {
      const { exit, result } = checkDeck({ root: deck(plain), visibility, cls: "K0", explicit: false });
      assert.equal(exit, 0);
      assert.equal(result.medium, "artifact");
      assert.equal(result.destination, "a private Artifact on claude.ai");
    }
  });
  test("a private source stays local unless a trusted layer was explicit", () => {
    const root = deck(plain);
    assert.equal(checkDeck({ root, visibility: "PRIVATE", cls: "K1", explicit: false }).result.medium, "file");
    assert.equal(checkDeck({ root, visibility: "PRIVATE", cls: "K1", explicit: true }).result.medium, "artifact");
  });
  test("a credential in any deck file, the title included, stays local", () => {
    const key = `${"sk-"}ant-${"x".repeat(24)}`;
    const root = deck(plain, { v: 4, title: key, order: ["cover"] });
    const { result } = checkDeck({ root, visibility: "PUBLIC", cls: "K0", explicit: false });
    assert.equal(result.medium, "file");
    assert.match(result.reason, /^deck line \d+ looks like a Anthropic key$/);
    assert.ok(!JSON.stringify(result).includes(key));
  });
  const hostile = [
    ["a live embed", '<x-embed style="left:0px">x</x-embed>'],
    ["a script", "<script>alert(1)</script>"],
    ["inline SVG", '<svg aria-label="x"><text>x</text></svg>'],
    ["a link", '<p><a href="https://evil.example/?q=secret">click</a></p>'],
    ["an event handler", '<p onclick="x()">x</p>'],
    ["a CSS url()", '<div style="background:url(https://evil.example/a.png)"></div>'],
    ["an image not uploaded by this session", '<img src="https://evil.example/a.png" alt="x">'],
    ["a style, link, frame, object, form, meta, or base element", "<style>p{}</style>"],
  ];
  for (const [carries, body] of hostile) {
    test(`a K2 deck carrying ${carries} is refused, even when explicit`, () => {
      const { exit, result } = checkDeck({ root: deck({ s1: slide("s1", body) }), visibility: "PUBLIC", cls: "K2", explicit: true });
      assert.equal(exit, 1);
      assert.equal(result.medium, "file");
      assert.deepEqual(result.refused, [{ file: "project/slides/s1.html", carries }]);
    });
  }
  test("a K2 deck of escaped text and uploaded images passes; text that reads like markup does not trip it", () => {
    const body = '<h2>Fix &lt;script&gt; onload = 1 url(x) href=x</h2><img src="/_blob/abc_1" alt="chart" style="width:480px">';
    assert.deepEqual(k2Refusals([["project/slides/s1.html", slide("s1", body)]]), []);
    assert.equal(checkDeck({ root: deck({ s1: slide("s1", body) }), visibility: "PUBLIC", cls: "K2", explicit: false }).exit, 0);
  });
  test("the same markup in a K0 deck is the type's to drop, not a refusal", () => {
    const { exit } = checkDeck({ root: deck({ s1: slide("s1", hostile[0][1]) }), visibility: "PUBLIC", cls: "K0", explicit: false });
    assert.equal(exit, 0);
  });
  test("a root inside a working tree is refused", () => {
    const root = join(scratch, "repo");
    mkdirSync(join(root, ".git"), { recursive: true });
    mkdirSync(join(root, "project"), { recursive: true });
    writeFileSync(join(root, "project/deck.json"), "{}");
    const { exit, result } = checkDeck({ root, visibility: "PUBLIC", cls: "K0", explicit: false });
    assert.equal(exit, 2);
    assert.match(result.reason, /inside the working tree/);
  });
  test("the CLI refuses a missing class or an unknown flag", () => {
    const run = (args) => spawnSync(process.execPath, [CHECK, ...args], { encoding: "utf8" });
    const root = deck(plain);
    assert.equal(run([root, "PUBLIC"]).status, 2);
    assert.equal(run([root, "PUBLIC", "--class", "K3"]).status, 2);
    assert.equal(run([root, "PUBLIC", "--class", "K0", "--force"]).status, 2);
    assert.equal(JSON.parse(run([root, "public", "--class", "K0"]).stdout).medium, "artifact");
    assert.equal(run([join(scratch, "missing"), "PUBLIC", "--class", "K0"]).status, 2);
  });
});

describe("skill contract", () => {
  const skill = readFileSync(join(SKILL, "SKILL.md"), "utf8");
  test("finds the type through the quickstart and never hard-codes a type_url", () => {
    assert.match(skill, /`action: "quickstart"` and `intent: "slides"`/);
    assert.doesNotMatch(skill, /claude\.ai\/artifact\/[A-Za-z0-9]/);
  });
  test("gates before the create call and names the destination", () => {
    assert.match(skill, /Before the type's own create call/);
    assert.match(skill, /publishing as a private Artifact on claude\.ai/);
    assert.match(skill, /`medium: artifact` in\s+`~\/\.claude\/rendered-views\.md`/);
  });
  test("a team layer's artifact is not explicit", () => {
    assert.match(skill, /its `artifact` is not explicit/);
  });
  test("grants only its own script and read-only gh", () => {
    const tools = /^allowed-tools: (.*)$/m.exec(skill)[1];
    assert.doesNotMatch(tools, /Bash\(gh (?:pr|issue|api)|Bash\(\*|Bash\(node/);
  });
});
