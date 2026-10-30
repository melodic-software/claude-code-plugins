// Parity of setup-apply's YAML adapter (flatten(), over yaml-subset.mjs) with yaml-subset.awk:
// each block-style fixture gets the same accept/reject verdict from both, and an accepted one the
// same `path<TAB>value` records, which setup-apply's leaf display and read-back rely on.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const { flatten } = await import("./setup-apply.mjs");

function awk(text) {
  const r = spawnSync("awk", ["-f", join(HERE, "yaml-subset.awk")], { input: text, encoding: "utf8", env: { ...process.env, LC_ALL: "C" } });
  if (r.status !== 0) return { accepted: false, out: r.stdout.split("\n").find((l) => l.startsWith("error\t")) };
  return { accepted: true, out: r.stdout.split("\n").filter(Boolean) };
}

function adapter(text) {
  const r = flatten(text);
  if (r.error) return { accepted: false, out: r.error };
  return { accepted: true, out: r.records.map((x) => `${x.path}\t${x.value}`) };
}

const accepted = {
  "typed scalars keep their source text": "a: 1.0\nb: 075\nc: 1e3\nd: True\ne: 9007199254740993\nf: -0\n",
  "null, ~ and an empty value": "a: null\nb: ~\nc:\nd: Null\n",
  "quoted scalars and an empty quoted string": "a: \"x y\"\nb: 'it''s'\nc: \"\"\nd: ''\ne: \"a\\tb\\\\c\\/d\\\"e\"\n",
  "a double-quoted \\n is kept as written": 'a: "v\\ny"\n"k\\nx": 1\n',
  "quoted keys holding a space or $": "\"a b\": 1\n'$schema': x\n",
  "nested maps": "a:\n  b:\n    c: 1\n  d: 2\ne: 3\n",
  "a sequence at the parent's indent": "a:\n- x\n- y\n",
  "sequences of scalars and maps": "l:\n  - 1\n  - k: v\n    z: 2\n  -\n  - \"\"\n",
  "a nested map under a dash-line key": "l:\n  - k:\n      m: 1\n    n: 2\n",
  "flow sequences of scalars": "a: [1, \"b, c\", 'd''e', ~]\nb: []\nc: [ ]\n",
  "comments and blank lines": "# head\na: 1 # trailing\n\nb: \"#not\" # c\nc: x#y\n",
  "an apostrophe inside a plain value": "a: don't\nb: x 'y'\n",
  "a colon without a following space": "a: http://x\nb: a:b\n",
  "CRLF line endings": "a: 1\r\nb:\r\n  c: 2\r\n",
  "a byte-order mark": "\ufeffa: 1\n",
  "a uniform base indent": "  a: 1\n  b:\n    c: 2\n",
  "an empty document": "",
  "a comment-only document": "# nothing\n\n",
  "the same key under two parents": "a:\n  k: 1\nb:\n  k: 2\n",
  "the same key in two sequence items": "l:\n  - k: 1\n  - k: 2\n",
};

const rejected = {
  "a plain value holding `: `": "pre_confirmed_label: needs: triage\n",
  "a plain key holding a space": "a b: c\n",
  "a plain key holding $": "$schema: x\n",
  "a plain key holding a dot": "a.b: c\n",
  "a quoted key holding a dot": "'c.d': 2\n",
  "a quoted key holding a tab": '"a\\tb": 1\n',
  "an empty quoted key": '"": 1\n',
  "a quoted key holding a dot in a sequence item": 'l:\n  - "x.y": 1\n',
  "a duplicate key": "a: 1\na: 2\n",
  "a duplicate nested key": "m:\n  k: 1\n  k: 2\n",
  "an unknown escape": 'a: "\\q"\n',
  "a nested flow sequence": "a: [[1, 2]]\n",
  "a % directive": "%YAML 1.2\na: 1\n",
  "a sequence-item map indented past its dash column + 2": "l:\n  - a: 1\n      b: 2\n",
  "a flow mapping": "a: {b: 1}\n",
  "a document start marker": "---\na: 1\n",
  "a document end marker": "a: 1\n...\n",
  "a tab indent": "a:\n\tb: 1\n",
  "an anchor": "a: &x 1\n",
  "an alias": "a: *x\n",
  "a tag": "a: !t 1\n",
  "a block scalar": "a: |\n  x\n",
  "an unterminated quote": 'a: "x\n',
  "an unterminated flow sequence": "a: [1, 2\n",
  "an over-indented key": "a: 1\n   b: 2\n",
  "a line that is no mapping entry": "a: 1\njust text\n",
};

for (const [name, text] of Object.entries(accepted)) {
  test(`both accept, with the same records: ${name}`, () => {
    const a = awk(text);
    const m = adapter(text);
    assert.equal(a.accepted, true, `awk refused: ${a.out}`);
    assert.equal(m.accepted, true, `the adapter refused: ${m.out}`);
    assert.deepEqual(m.out, a.out);
  });
}

for (const [name, text] of Object.entries(rejected)) {
  test(`both reject: ${name}`, () => {
    const a = awk(text);
    const m = adapter(text);
    assert.equal(a.accepted, false, `awk accepted: ${JSON.stringify(a.out)}`);
    assert.equal(m.accepted, false, `the adapter accepted: ${JSON.stringify(m.out)}`);
    assert.equal(m.out.split(":")[0], `line ${a.out.split("\t")[1]}`, `different lines: ${m.out} vs ${a.out}`);
  });
}
