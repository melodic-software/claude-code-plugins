// The YAML subset parser: the cases of plugins/code-metrics/scripts/test_yaml_subset.py, plus the
// guards a reader of consumer-authored files needs in JavaScript.
import { strict as assert } from "node:assert";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const { parse, YamlSubsetError } = await import(join(dirname(fileURLToPath(import.meta.url)), "../scripts/lib/yaml-subset.mjs"));

/** Strips the common leading indentation, as Python's textwrap.dedent does for the ported cases. */
function dedent(text) {
  const lines = text.split("\n");
  const indents = lines.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length);
  const cut = Math.min(...indents);
  return lines.map((l) => l.slice(cut)).join("\n");
}
const doc = (text) => parse(dedent(text));

describe("parse", () => {
  test("nested block mappings with typed scalars", () => {
    const d = doc(`
      # a comment
      complexity:
        cyclomatic:
          reference: 20   # trailing comment
        cognitive:
          reference: null
        halstead:
          difficulty: ~
      size:
        mode: file-lines
        ratio: 2.5
        enabled: true
        disabled: false
        name: "quoted # not a comment"
        other: 'it''s'
        empty:
    `);
    assert.equal(d.complexity.cyclomatic.reference, 20);
    assert.equal(d.complexity.cognitive.reference, null);
    assert.equal(d.complexity.halstead.difficulty, null);
    assert.equal(d.size.mode, "file-lines");
    assert.equal(d.size.ratio, 2.5);
    assert.equal(d.size.enabled, true);
    assert.equal(d.size.disabled, false);
    assert.equal(d.size.name, "quoted # not a comment");
    assert.equal(d.size.other, "it's");
    assert.equal(d.size.empty, null);
  });

  test("flow and block sequences", () => {
    const d = doc(`
      globs: ["*.sh", '*.bash', plain]
      none: []
      registries:
        - scripts/a.txt
        - scripts/b.txt
      lanes:
      - typescript
      - python
    `);
    assert.deepEqual(d.globs, ["*.sh", "*.bash", "plain"]);
    assert.deepEqual(d.none, []);
    assert.deepEqual(d.registries, ["scripts/a.txt", "scripts/b.txt"]);
    assert.deepEqual(d.lanes, ["typescript", "python"]);
  });

  test("sequence of mappings starting on the dash line", () => {
    const d = doc(`
      sites:
        - surface: CLAUDE.md
          anchor/v1: "e:1145aa93c681:070ee98f"
        - surface: other.md
        - name: nested
          values:
            - 1
            - 2
    `);
    assert.deepEqual(d.sites[0], { surface: "CLAUDE.md", "anchor/v1": "e:1145aa93c681:070ee98f" });
    assert.deepEqual(d.sites[1], { surface: "other.md" });
    assert.deepEqual(d.sites[2], { name: "nested", values: [1, 2] });
  });

  test("the contract example round trips", () => {
    const d = doc(`
      lanes:
        typescript:
          enabled: true
          collectors:            # measure -> ordered tool list
            cyclomatic: [lizard, eslint-complexity]
        dotnet:
          enabled: true          # detected, reported as deferred in V1
    `);
    assert.deepEqual(d.lanes.typescript.collectors.cyclomatic, ["lizard", "eslint-complexity"]);
    assert.equal(d.lanes.dotnet.enabled, true);
  });

  test("the team-file disable list in block form", () => {
    const d = doc(`
      routing:
        version: 1
        disable:
          - job: synthesis
            id: dovetail
        deny: []
    `);
    assert.deepEqual(d.routing, { version: 1, disable: [{ job: "synthesis", id: "dovetail" }], deny: [] });
  });

  test("empty document is null", () => {
    assert.equal(parse("# only a comment\n\n"), null);
  });

  test("CRLF line endings and a leading byte-order mark parse as plain lines", () => {
    assert.deepEqual(parse("\uFEFFversion: 1\r\nrouting:\r\n  version: 1\r\n"), { version: 1, routing: { version: 1 } });
  });

  test("a hostile 100k-space key line is handled in linear time (under 200 ms)", () => {
    const line = `a:${" ".repeat(100_000)}x\u2028y\n`;
    const start = performance.now();
    try {
      parse(line);
    } catch (e) {
      assert.ok(e instanceof YamlSubsetError, e);
    }
    const ms = performance.now() - start;
    assert.ok(ms < 200, `took ${Math.round(ms)} ms`);
  });

  test("a __proto__ key is an own data key, never the object's prototype", () => {
    const d = parse("__proto__:\n  polluted: true\n");
    assert.equal(Object.getPrototypeOf(d), Object.prototype);
    assert.ok(Object.hasOwn(d, "__proto__"));
    assert.equal({}.polluted, undefined);
  });
});

describe("constructs outside the subset are named with their line", () => {
  const cases = [
    ["a: 1\nb: { x: 1 }\n", 2, "flow mapping"],
    ["a: &anchor 1\n", 1, "anchors"],
    ["a: 1\nb: *anchor\n", 2, "aliases"],
    ["a: !!str 1\n", 1, "tags"],
    ["a: |\n  text\n", 1, "block scalars"],
    ["---\na: 1\n", 1, "document markers"],
    ["a:\n\tb: 1\n", 2, "tab indentation"],
    ["a: 1\na: 2\n", 2, "duplicate key"],
    ["a: [1, [2]]\n", 1, "nested flow sequences"],
    ["a: 'unterminated\n", 1, "unterminated"],
    ["a:\n  b: 1\n c: 2\n", 3, "unexpected indent"],
    ["routing:\n  disable:\n    - {job: synthesis, id: dovetail}\n", 3, "flow mapping"],
  ];
  for (const [text, line, fragment] of cases) {
    test(`${fragment} on line ${line}: ${JSON.stringify(text)}`, () => {
      assert.throws(
        () => parse(text),
        (e) => e instanceof YamlSubsetError && e.line === line && e.message.includes(fragment) && e.message.startsWith(`line ${line}: `),
      );
    });
  }
});
