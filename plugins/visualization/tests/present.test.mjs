// /visualization:present: the deck gate (root outside a working tree and reached
// through no symlink, a plain-text title, K2 slides on an allowlist, medium
// resolved from the user's own layers, the shared publish gate over every file)
// and the skill's contract (quickstart at run time, no hard-coded type_url, gate
// before the create call, the create call's title read from the gate).
import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const SKILL = join(PLUGIN, "skills/present");
const CHECK = join(SKILL, "scripts/check-deck.mjs");
const { checkDeck: gate, k2Refusals } = await import(pathToFileURL(CHECK).href);

const scratch = realpathSync(mkdtempSync(join(tmpdir(), "present-test-")));
after(() => rmSync(scratch, { recursive: true, force: true }));
const HOME = join(scratch, "home");
mkdirSync(join(HOME, ".claude"), { recursive: true });
/** The gate with no user layers unless a test names them: an empty home, no project. */
const checkDeck = ({ layers, ...input }) => gate({ ...input, layers: { home: HOME, project: null, ...layers } });

let n = 0;
function deck(slides, index = { v: 4, title: "Talk", order: Object.keys(slides) }, root = join(scratch, `deck-${(n += 1)}`)) {
  mkdirSync(join(root, "project/slides"), { recursive: true });
  writeFileSync(join(root, "project/deck.json"), JSON.stringify(index));
  for (const [id, html] of Object.entries(slides)) writeFileSync(join(root, `project/slides/${id}.html`), html);
  return root;
}
const slide = (id, body) => `<section id="${id}" style="background:#fbfbf8;padding:128px">${body}</section>`;
const plain = { cover: slide("cover", "<h1 style=\"font-size:96px\">Merge queues</h1><p>a &lt;b&gt; one = 2 url(x)</p><aside>Hi.</aside>") };

/** A git working tree holding `files` as [path, text, tracked]. */
function repo(files, ignore = []) {
  const dir = join(scratch, `repo-${(n += 1)}`);
  mkdirSync(join(dir, ".claude"), { recursive: true });
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { stdio: "ignore" });
  git("init", "-q");
  if (ignore.length) writeFileSync(join(dir, ".gitignore"), `${ignore.join("\n")}\n`);
  for (const [path, text, tracked] of files) {
    writeFileSync(join(dir, path), text);
    if (tracked) git("add", "-f", "--", path);
  }
  return dir;
}
function home(text) {
  const dir = join(scratch, `home-${(n += 1)}`);
  mkdirSync(join(dir, ".claude"), { recursive: true });
  writeFileSync(join(dir, ".claude/rendered-views.md"), text);
  return dir;
}

describe("check-deck", () => {
  test("a clean deck from a public or repository-free source publishes, and names the title to create with", () => {
    for (const visibility of ["PUBLIC", "NONE"]) {
      const { exit, result } = checkDeck({ root: deck(plain), visibility, cls: "K0" });
      assert.equal(exit, 0);
      assert.equal(result.medium, "artifact");
      assert.equal(result.destination, "a private Artifact on claude.ai");
      assert.equal(result.title, "Talk");
    }
  });
  test("a private source stays local unless a trusted layer sets artifact", () => {
    const root = deck(plain);
    assert.equal(checkDeck({ root, visibility: "PRIVATE", cls: "K1" }).result.medium, "file");
    assert.equal(checkDeck({ root, visibility: "PRIVATE", cls: "K1", layers: { argument: "artifact" } }).result.medium, "artifact");
  });
  test("a credential in any deck file, the title included, stays local", () => {
    const key = `${"sk-"}ant-${"x".repeat(24)}`;
    const root = deck(plain, { v: 4, title: key, order: ["cover"] });
    const { result } = checkDeck({ root, visibility: "PUBLIC", cls: "K0" });
    assert.equal(result.medium, "file");
    assert.match(result.reason, /^deck line \d+ looks like a Anthropic key$/);
    assert.ok(!JSON.stringify(result).includes(key));
  });
  for (const [what, index] of [
    ["no title", { v: 4, order: ["cover"] }],
    ["a markup title", { v: 4, title: "<img src=x onerror=alert(1)>", order: ["cover"] }],
    ["a multi-line title", { v: 4, title: "Talk\nmore", order: ["cover"] }],
  ]) {
    test(`a deck with ${what} is refused in any class`, () => {
      const { exit, result } = checkDeck({ root: deck(plain, index), visibility: "PUBLIC", cls: "K0", layers: { argument: "artifact" } });
      assert.equal(exit, 1);
      assert.equal(result.medium, "file");
    });
  }

  const hostile = [
    ["a live embed", '<x-embed style="left:0px">x</x-embed>'],
    ["a script", "<script>alert(1)</script>"],
    ["inline SVG", '<svg aria-label="x"><text>x</text></svg>'],
    ["a link", '<p><a href="https://evil.example/?q=secret">click</a></p>'],
    ["an event handler", '<p onclick="x()">x</p>'],
    ["a style value holding (, \\, or &", '<div style="background:url(https://evil.example/a.png)"></div>'],
    ["an image not uploaded by this session", '<img src="https://evil.example/a.png" alt="x">'],
    ["a style, link, frame, object, form, meta, or base element", "<style>p{}</style>"],
    // A `>` inside a quoted value does not end the tag.
    ["an event handler", '<div title=">" onclick="alert(1)">x</div>'],
    ["an image not uploaded by this session", '<img alt=">" src="https://evil.example/x.png">'],
    // `/` is not an attribute separator.
    ["markup the gate cannot parse cleanly", "<img/onerror=alert(1) src=/_blob/abc>"],
    ["an attribute outside the allowlist", '<img srcset="https://evil.example/x.png 1x" src="/_blob/abc">'],
    ["an attribute outside the allowlist", '<img poster="https://evil.example/x.png" src="/_blob/abc">'],
    ["an element outside the text and layout set", '<video poster="https://evil.example/x.png"></video>'],
    ["an attribute outside the allowlist", '<table background="https://evil.example/x.png"><tr><td>x</td></tr></table>'],
    ["an element outside the text and layout set", '<button formaction="https://evil.example/">x</button>'],
    ["a style value holding (, \\, or &", '<div style="background:url&#40;https://evil.example/a.png)">x</div>'],
    ["a style value holding (, \\, or &", '<div style="background:u\\72l(https://evil.example/a.png)">x</div>'],
    ["a style value holding (, \\, or &", "<div style=\"background-image:image-set('https://evil.example/a.png' 1x)\">x</div>"],
    ["an event handler", "<P TITLE=x ONCLICK=alert(1)>x</P>"],
    ["an image not uploaded by this session", '<img src="&#x68;ttps://evil.example/a.png">'],
    ["markup the gate cannot parse cleanly", '<img src="/_blob/abc" src="https://evil.example/a.png">'],
    ["markup the gate cannot parse cleanly", '<img alt="x"src="/_blob/abc">'],
    ["markup the gate cannot parse cleanly", '<img alt="&unknown;" src="/_blob/abc">'],
    ["markup the gate cannot parse cleanly", "<!-- <img src=https://evil.example/a.png> -->"],
    ["markup the gate cannot parse cleanly", "<p>1 < 2</p>"],
    ["markup the gate cannot parse cleanly", '<img src="/_blob/abc'],
    ["markup the gate cannot parse cleanly", "<p>x</p class=y>"],
    ["an image not uploaded by this session", '<img src="project/ds/../../etc/x.png">'],
  ];
  for (const [carries, body] of hostile) {
    test(`a K2 deck carrying ${body} is refused as ${carries}, even when a layer sets artifact`, () => {
      const { exit, result } = checkDeck({ root: deck({ s1: slide("s1", body) }), visibility: "PUBLIC", cls: "K2", layers: { argument: "artifact" } });
      assert.equal(exit, 1);
      assert.equal(result.medium, "file");
      assert.deepEqual(result.refused, [{ file: "project/slides/s1.html", carries }]);
    });
  }
  test("a K2 deck of escaped text and uploaded images passes; text that reads like markup does not trip it", () => {
    const body = [
      "<h2>Fix &lt;script&gt; onload = 1 url(x) href=x &amp; > done</h2>",
      '<img src="/_blob/abc_1" alt="chart &amp; table" style="width:480px">',
      "<img src='project/ds/img/logo.png' alt=logo />",
      '<ul class="points"><li>one<br>two</li></ul><table><tr><td colspan="2">x</td></tr></table>',
    ].join("");
    assert.deepEqual(k2Refusals([["project/slides/s1.html", slide("s1", body)]]), []);
    assert.equal(checkDeck({ root: deck({ s1: slide("s1", body) }), visibility: "PUBLIC", cls: "K2" }).exit, 0);
  });
  test("the same markup in a K0 deck is the type's to drop, not a refusal", () => {
    const { exit } = checkDeck({ root: deck({ s1: slide("s1", hostile[0][1]) }), visibility: "PUBLIC", cls: "K0" });
    assert.equal(exit, 0);
  });

  test("a root inside a working tree is refused", () => {
    const root = join(scratch, "repo");
    mkdirSync(join(root, ".git"), { recursive: true });
    deck(plain, undefined, root);
    const { exit, result } = checkDeck({ root, visibility: "PUBLIC", cls: "K0" });
    assert.equal(exit, 2);
    assert.match(result.reason, /inside the working tree/);
  });
  test("project/ linked into a working tree is refused, not followed", () => {
    const tree = join(scratch, `tree-${(n += 1)}`);
    mkdirSync(join(tree, ".git"), { recursive: true });
    deck(plain, undefined, tree);
    const root = join(scratch, `deck-${(n += 1)}`);
    mkdirSync(root);
    symlinkSync(join(tree, "project"), join(root, "project"), "dir");
    const { exit, result } = checkDeck({ root, visibility: "PUBLIC", cls: "K0" });
    assert.equal(exit, 2);
    assert.match(result.reason, /^project is a symlink/);
  });
  test("a symlinked slide, a symlinked root, or a root through a symlinked folder is refused", () => {
    const linked = deck(plain);
    symlinkSync(join(linked, "project/slides/cover.html"), join(linked, "project/slides/more.html"));
    assert.match(checkDeck({ root: linked, visibility: "PUBLIC", cls: "K0" }).result.reason, /^project\/slides\/more\.html is a symlink/);
    const real = deck(plain);
    const alias = join(scratch, `alias-${(n += 1)}`);
    symlinkSync(real, alias, "dir");
    assert.equal(checkDeck({ root: alias, visibility: "PUBLIC", cls: "K0" }).exit, 2);
    const folder = join(scratch, `folder-${(n += 1)}`);
    symlinkSync(scratch, folder, "dir");
    const { exit, result } = checkDeck({ root: join(folder, real.slice(scratch.length + 1)), visibility: "PUBLIC", cls: "K0" });
    assert.equal(exit, 2);
    assert.match(result.reason, /symlink/);
  });

  describe("medium layers", () => {
    const root = deck(plain);
    const medium = (layers, visibility = "PRIVATE") => checkDeck({ root, visibility, cls: "K1", layers }).result;
    test("a tracked team file cannot force publish", () => {
      const project = repo([[".claude/rendered-views.md", "medium: artifact\n", true]]);
      const result = medium({ project });
      assert.equal(result.medium, "file");
      assert.match(result.reason, /visibility is PRIVATE/);
    });
    test("a team file can keep a deck local", () => {
      const project = repo([[".claude/rendered-views.md", "medium: file\n", true]]);
      const result = medium({ project }, "PUBLIC");
      assert.equal(result.medium, "file");
      assert.match(result.reason, /rendered-views\.md sets medium: file$/);
    });
    test("an overlay publishes only untracked and gitignored", () => {
      const overlay = ".claude/rendered-views.local.md";
      const tracked = medium({ project: repo([[overlay, "medium: artifact\n", true]]) });
      assert.equal(tracked.medium, "file");
      assert.ok(tracked.warnings.some((w) => /tracked in git/.test(w)));
      const unignored = medium({ project: repo([[overlay, "medium: artifact\n", false]]) });
      assert.equal(unignored.medium, "file");
      assert.ok(unignored.warnings.some((w) => /not gitignored.*layer ignored/.test(w)));
      assert.equal(medium({ project: repo([[overlay, "medium: artifact\n", false]], [overlay]) }).medium, "artifact");
    });
    test("the user file, the plugin option, and the argument are trusted; an unset option is not", () => {
      assert.equal(medium({ home: home("medium: artifact\n") }).medium, "artifact");
      assert.equal(medium({ option: "artifact" }).medium, "artifact");
      for (const option of ["auto", "", "${user_config.medium}"]) assert.equal(medium({ option }).medium, "file");
      assert.equal(medium({ home: home("medium: file\n"), argument: "artifact" }).medium, "artifact");
      assert.equal(medium({ argument: "terminal" }, "PUBLIC").medium, "terminal");
    });
    test("hosted is treated as artifact: a deck is never sent to a page host", () => {
      for (const layers of [{ home: home("medium: hosted\n") }, { option: "hosted" }, { argument: "hosted" }]) {
        const result = medium(layers);
        assert.equal(result.medium, "artifact");
        assert.match(result.reason, /sets medium: hosted, treated as artifact$/);
      }
      const team = medium({ project: repo([[".claude/rendered-views.md", "medium: hosted\n", true]]) });
      assert.equal(team.medium, "file");
    });
  });

  // A shell-less spawn on Windows finds only a .exe or .com on PATH, so there the sh fake could never run and the test would prove nothing.
  test("the CLI takes --argument hosted and never runs pages-publish", { skip: process.platform === "win32" && "the fake pages-publish is a sh script" }, () => {
    const bin = join(scratch, "fake-bin");
    const marker = join(scratch, "pages-publish-ran");
    mkdirSync(bin, { recursive: true });
    writeFileSync(join(bin, "pages-publish"), `#!/bin/sh\ntouch "${marker}"\n`);
    chmodSync(join(bin, "pages-publish"), 0o755);
    const env = { ...process.env, HOME, USERPROFILE: HOME, CLAUDE_PROJECT_DIR: join(scratch, "no-project"), PATH: `${bin}${delimiter}${process.env.PATH}` };
    const out = spawnSync(process.execPath, [CHECK, deck(plain), "PUBLIC", "--class", "K0", "--argument", "hosted"], { encoding: "utf8", env });
    assert.equal(out.status, 0, out.stderr);
    assert.equal(JSON.parse(out.stdout).medium, "artifact");
    assert.equal(existsSync(marker), false);
  });

  test("the CLI refuses a missing class or an unknown flag, and reads only the given layers", () => {
    const env = { ...process.env, HOME, USERPROFILE: HOME, CLAUDE_PROJECT_DIR: join(scratch, "no-project") };
    const run = (args) => spawnSync(process.execPath, [CHECK, ...args], { encoding: "utf8", env });
    const root = deck(plain);
    assert.equal(run([root, "PUBLIC"]).status, 2);
    assert.equal(run([root, "PUBLIC", "--class", "K3"]).status, 2);
    assert.equal(run([root, "PUBLIC", "--class", "K0", "--explicit"]).status, 2);
    assert.equal(run([root, "PUBLIC", "--class", "K0", "--argument", "maybe"]).status, 2);
    assert.equal(JSON.parse(run([root, "public", "--class", "K0"]).stdout).medium, "artifact");
    assert.equal(JSON.parse(run([root, "PRIVATE", "--class", "K0", "--option", "${user_config.medium}"]).stdout).medium, "file");
    assert.equal(JSON.parse(run([root, "PRIVATE", "--class", "K0", "--argument", "artifact"]).stdout).medium, "artifact");
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
  test("the script, not the model, resolves the layers; a team layer cannot publish", () => {
    assert.match(skill, /--option "\$\{user_config\.medium\}"/);
    assert.doesNotMatch(skill, /--explicit/);
    assert.match(skill, /never publishes from the\s+team/);
  });
  test("the create call's title is the gated one", () => {
    assert.match(skill, /`title` the gate printed/);
    assert.match(skill, /never type it separately/);
  });
  test("grants only its own script and read-only gh", () => {
    const tools = /^allowed-tools: (.*)$/m.exec(skill)[1];
    assert.doesNotMatch(tools, /Bash\(gh (?:pr|issue|api)|Bash\(\*|Bash\(node/);
  });
});
