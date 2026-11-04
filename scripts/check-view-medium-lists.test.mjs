import assert from "node:assert/strict";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { after, describe, test } from "node:test";
import { laneDir, listings, main, readRegistry } from "./check-view-medium-lists.mjs";
import { LANES, MEDIUMS } from "../lib/view-registry.mjs";
import { tempDir } from "../lib/test-tmp.mjs";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const IDS = new Set(["terminal", "file", "artifact", "hosted"]);
const hits = (rel, text) => listings(rel, text, IDS).map((h) => `${h.line}:${h.ids.join(",")}`);

describe("readRegistry", () => {
  test("reads the ids lib/view-registry.mjs exports, without importing it", () => {
    const { mediums, lanes } = readRegistry(readFileSync(path.join(REPO, "lib/view-registry.mjs"), "utf8"));
    assert.deepEqual(mediums, Object.keys(MEDIUMS));
    assert.deepEqual(lanes, Object.keys(LANES));
  });

  test("maps a plugin:skill lane to its skill and a bare id to its plugin", () => {
    assert.equal(laneDir("alpha:show"), "plugins/alpha/skills/show");
    assert.equal(laneDir("beta"), "plugins/beta");
  });
});

describe("listings", () => {
  test("flags two distinct backticked ids on one line", () => {
    assert.deepEqual(hits("SKILL.md", "Pick `terminal`, `file` or `artifact`."), ["1:terminal,file,artifact"]);
  });

  test("passes one id, one id twice, and ids written as plain words", () => {
    assert.deepEqual(hits("SKILL.md", "Set `file`.\nThe `file` medium writes a `file`.\nNo artifact surface, file writing useful."), []);
  });

  test("passes a span that only contains an id", () => {
    assert.deepEqual(hits("SKILL.md", "Run `medium: file` or `terminal-ui`."), []);
  });

  test("reads evals.json one JSON string at a time", () => {
    const json = [
      '{"prompt": "visualize it (Fixture: the userConfig medium option is set to `artifact`.)",',
      ' "expected_output": "the team file\'s `file` wins over the configured `artifact`",',
      ' "expectations": ["Uses `file`", "Never `artifact`"]}',
    ].join("\n");
    assert.deepEqual(hits("evals/evals.json", json), ["2:file,artifact"]);
  });
});

const work = tempDir("view-medium-lists-");
after(() => rmSync(work, { recursive: true, force: true }));
let n = 0;

const REGISTRY = [
  "export const MEDIUMS = Object.freeze({",
  '  terminal: entry("terminal", false),',
  '  file: entry("file", false),',
  "});",
  "const lane = (laneId) => laneId;",
  'export const LANES = [lane("alpha:show"), lane("beta")];',
  "",
].join("\n");

// repo({ files, exemptions, shared }) -> root
function repo({ files = {}, exemptions, shared = [] }) {
  const root = path.join(work, `repo${++n}`);
  mkdirSync(path.join(root, "lib"), { recursive: true });
  mkdirSync(path.join(root, "scripts"), { recursive: true });
  writeFileSync(path.join(root, "lib/view-registry.mjs"), REGISTRY);
  writeFileSync(path.join(root, "scripts/shared-copies.txt"), `# header\n${shared.join("\n")}\n`);
  if (exemptions) writeFileSync(path.join(root, "scripts/view-medium-list-exemptions.txt"), `# header\n${exemptions.join("\n")}\n`);
  for (const [rel, text] of Object.entries(files)) {
    mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    writeFileSync(path.join(root, rel), text);
  }
  return root;
}

function gate(root) {
  const lines = { log: [], error: [] };
  const code = main(["--root", root], { log: (s) => lines.log.push(s), error: (s) => lines.error.push(s) });
  return { code, out: lines.log.join("\n"), err: lines.error.join("\n") };
}

const LIST = "Choose `terminal` or `file`.\n";
const SETUP = '{"evals": [{"prompt": "render it (Fixture: the medium option is set to `file`.)"}]}\n';

describe("main", () => {
  test("fails a lane's skill markdown that lists two medium ids", () => {
    const r = gate(repo({ files: { "plugins/alpha/skills/show/context/x.md": LIST } }));
    assert.equal(r.code, 1);
    assert.match(r.err, /plugins\/alpha\/skills\/show\/context\/x\.md:1: `terminal`, `file` \(lane alpha:show/);
  });

  test("fails a list in a bare lane's plugin, outside its skills", () => {
    const r = gate(repo({ files: { "plugins/beta/reference/a.md": LIST } }));
    assert.equal(r.code, 1);
    assert.match(r.err, /lane beta lists media/);
  });

  test("passes a fixture prompt that names one medium as setup", () => {
    const r = gate(repo({ files: { "plugins/alpha/skills/show/evals/evals.json": SETUP } }));
    assert.equal(r.code, 0, r.err);
  });

  test("skips CHANGELOG.md, README.md, shared copies, other files and other skills", () => {
    const r = gate(
      repo({
        files: {
          "plugins/beta/CHANGELOG.md": LIST,
          "plugins/beta/README.md": LIST,
          "plugins/beta/reference/rendered-view.md": LIST,
          "plugins/beta/scripts/x.sh": LIST,
          "plugins/alpha/skills/other/SKILL.md": LIST,
        },
        shared: ["lib/rendered-view.md plugins/beta/reference/rendered-view.md"],
      }),
    );
    assert.equal(r.code, 0, r.err);
  });

  test("passes an exempt lane that still lists media", () => {
    const r = gate(repo({ files: { "plugins/beta/a.md": LIST }, exemptions: ["beta  # #12 beta slice"] }));
    assert.equal(r.code, 0, r.err);
    assert.match(r.out, /1 lane\(s\) exempt/);
  });

  test("fails an exemption row for a clean lane", () => {
    const r = gate(repo({ files: { "plugins/beta/a.md": "Set `file`.\n" }, exemptions: ["beta  # #12"] }));
    assert.equal(r.code, 1);
    assert.match(r.err, /"beta" lists no media any more; delete the row/);
  });

  test("fails an exemption row for a lane the registry does not hold", () => {
    const r = gate(repo({ exemptions: ["gamma  # #12"] }));
    assert.equal(r.code, 1);
    assert.match(r.err, /"gamma" is not a lane/);
  });

  test("fails an exemption row that cites no issue", () => {
    const r = gate(repo({ files: { "plugins/beta/a.md": LIST }, exemptions: ["beta  # slice"] }));
    assert.equal(r.code, 1);
    assert.match(r.err, /"beta" cites no issue/);
  });

  test("exits 2 when the registry yields no medium ids", () => {
    const root = repo({});
    writeFileSync(path.join(root, "lib/view-registry.mjs"), "export const LANES = {};\n");
    assert.equal(gate(root).code, 2);
  });

  test("passes the current tree with its exemption list", () => {
    const r = gate(REPO);
    assert.equal(r.code, 0, r.err);
  });
});
