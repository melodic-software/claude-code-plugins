import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const TESTS = dirname(fileURLToPath(import.meta.url));
const REVIEW = join(TESTS, "../skills/write-css/scripts/review.mjs");
const FIX = join(TESTS, "fixtures/review");
const at = (name) => join(FIX, name);

/** Runs review.mjs; returns exit status, stdout split into its `## ` sections, and stderr. */
function review(args) {
  const r = spawnSync(process.execPath, [REVIEW, ...args], { encoding: "utf8" });
  const sections = {};
  let current = null;
  for (const line of r.stdout.split("\n")) {
    if (line.startsWith("## ")) sections[(current = line.slice(3).trim())] = [];
    else if (current && line.trim()) sections[current].push(line);
  }
  return { status: r.status, stdout: r.stdout, stderr: r.stderr, sections };
}
/** `line [rule]` pairs from a section's `path:line [rule] message` entries for one file. */
const hits = (entries, file) =>
  entries
    .filter((entry) => entry.startsWith(`${file}:`))
    .map((entry) => entry.slice(file.length + 1).match(/^(\d+) \[([\w-]+)\]/))
    .map(([, line, rule]) => `${line} ${rule}`)
    .sort();

describe("findings", () => {
  test("each upstream rule is reported once under its rule id, and the run exits 1", () => {
    const file = at("all-rules.css");
    const r = review(["--config", "{}", file]);
    assert.equal(r.status, 1, r.stderr);
    assert.deepEqual(Object.keys(r.sections), ["Findings", "Suppressed", "Judgment"]);
    assert.deepEqual(
      hits(r.sections.Findings, file),
      ["13 duration", "13 motion", "2 hover", "3 logical", "6 outline", "7 ease-in", "8 color", "9 transition-all"].sort(),
    );
    assert.ok(r.sections.Findings.includes(`${file}:3 [logical] \`margin-left\` is physical. Write \`margin-inline-start\`.`));
    assert.deepEqual(hits(r.sections.Suppressed, file), []);
  });

  test("an HTML file is checked through its <style> block", () => {
    const file = at("page.html");
    const r = review(["--config", "{}", file]);
    assert.equal(r.status, 1, r.stderr);
    assert.deepEqual(hits(r.sections.Findings, file), ["5 hover", "6 logical"]);
  });

  test("an uppercase .CSS suffix is read as CSS", () => {
    const file = at("UPPER.CSS");
    const r = review(["--config", "{}", file]);
    assert.equal(r.status, 1, r.stderr);
    assert.deepEqual(hits(r.sections.Findings, file), ["2 color"]);
  });

  test("a clean file exits 0 with no findings", () => {
    const r = review(["--config", "{}", at("clean.css")]);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(hits(r.sections.Findings, at("clean.css")), []);
  });

  test("a file with no <style> block is not checked, is named under Judgment, and exits 0", () => {
    const file = at("no-style.html");
    const r = review(["--config", "{}", file]);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(hits(r.sections.Findings, file), []);
    assert.ok(r.sections.Judgment.some((line) => line.includes(file) && /no <style> block/.test(line)));
  });

  test("Judgment names the checks no linter makes", () => {
    const { sections } = review(["--config", "{}", at("clean.css")]);
    const text = sections.Judgment.join("\n");
    assert.match(text, /:active/);
    assert.match(text, /clamp\(\)/);
    assert.match(text, /overflow: hidden/);
  });

  test("a glob expands to the files it matches", () => {
    const r = review(["--config", "{}", join(FIX, "*.css")]);
    assert.equal(r.status, 1, r.stderr);
    assert.deepEqual(hits(r.sections.Findings, at("all-rules.css")).length, 8);
    assert.deepEqual(hits(r.sections.Findings, at("clean.css")), []);
  });
});

describe("suppression", () => {
  test("a rule in css.rules.disable moves its finding to Suppressed with the config reason", () => {
    const file = at("all-rules.css");
    const r = review(["--config", JSON.stringify({ css: { rules: { disable: ["color"] } } }), file]);
    assert.equal(r.status, 1, r.stderr);
    assert.ok(!hits(r.sections.Findings, file).includes("8 color"));
    assert.deepEqual(hits(r.sections.Suppressed, file), ["8 color"]);
    assert.match(r.sections.Suppressed[0], /— reason \(config: rules\.disable\)$/);
  });

  test("a config file in the resolver's output shape is read, and only suppressed findings exit 0", () => {
    const file = at("all-rules.css");
    const r = review(["--config", at("disable-all.json"), file]);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(hits(r.sections.Findings, file), []);
    assert.equal(hits(r.sections.Suppressed, file).length, 8);
  });
});

describe("usage and crash exit 2", () => {
  test("a missing path exits 2, not 1", () => {
    const r = review(["--config", "{}", at("does-not-exist.css")]);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /does-not-exist\.css/);
  });

  test("a glob that matches nothing exits 2", () => {
    assert.equal(review(["--config", "{}", join(FIX, "*.scss")]).status, 2);
  });

  test("no path exits 2", () => {
    assert.equal(review(["--config", "{}"]).status, 2);
  });

  test("a --config that is neither JSON nor a readable file exits 2", () => {
    assert.equal(review(["--config", "{not json", at("clean.css")]).status, 2);
  });

  test("a path that cannot be read as a file exits 2 even beside a file with findings", () => {
    const r = review(["--config", "{}", at("all-rules.css"), FIX]);
    assert.equal(r.status, 2);
  });
});

test("review.mjs never spawns a process or calls the detector", () => {
  const source = readFileSync(REVIEW, "utf8");
  assert.doesNotMatch(source, /detect\.mjs|spawn|child_process/);
});
