import assert from "node:assert/strict";
import { test } from "node:test";

import { homeOf, observerMap, section, team } from "./observer-team.mjs";

const AT = (file) => `default-branch-file: ${file} at origin/main, commit ${"a".repeat(40)}\n`;

test("section returns the Observer guidance body up to the next heading", () => {
  const md = "# Title\n\n## Other\nno\n\n## Observer guidance\n\n- one\n- two\n\n### Sub\nkept\n\n## Next\nno\n";
  assert.equal(section(md), "- one\n- two\n\n### Sub\nkept");
  assert.equal(section("# Title\n"), "");
});

test("observerMap returns the observer map, or an empty one when absent or not a map", () => {
  assert.deepEqual(observerMap("observer:\n  skill_check: true\n  defer_kinds:\n    - improvement\n"), { skill_check: true, defer_kinds: ["improvement"] });
  assert.deepEqual(observerMap("verification: light\n"), {});
  assert.deepEqual(observerMap("observer: off\n"), {});
});

test("homeOf reads the convention home from the reader's stderr line", () => {
  assert.equal(homeOf(AT("docs/conventions/session-flow.yaml")), "docs/conventions");
  assert.equal(homeOf(AT("conv/session-flow.yaml")), "conv");
  assert.equal(homeOf("default-branch-file: no origin remote answered\n"), undefined);
});

test("team reads the yaml map and the guidance beside it, with the yaml absent too", () => {
  const calls = [];
  const fake = (files) => (args) => {
    calls.push(args);
    if (args[0] === "--plugin") return files.yaml === undefined ? { code: 1, out: "", err: AT("docs/conventions/session-flow.yaml") } : { code: 0, out: files.yaml, err: AT("docs/conventions/session-flow.yaml") };
    return files.md === undefined ? { code: 1, out: "", err: "" } : { code: 0, out: files.md, err: "" };
  };
  assert.deepEqual(team(fake({ yaml: "observer:\n  codify_threshold: 4\n", md: "## Observer guidance\nRule.\n" })), { observer: { codify_threshold: 4 }, guidance: "Rule.", notes: [] });
  assert.deepEqual(calls[1], ["--path", "docs/conventions/session-flow.md"]);
  assert.deepEqual(team(fake({ md: "## Observer guidance\nOnly prose.\n" })), { observer: {}, guidance: "Only prose.", notes: [] });
});

test("team reports an unreadable default branch or a broken yaml and keeps going", () => {
  const unreadable = team(() => ({ code: 2, out: "", err: "default-branch-file: no origin remote answered\n" }));
  assert.deepEqual(unreadable, { observer: {}, guidance: "", notes: ["default-branch-file: no origin remote answered"] });
  const broken = team((args) => (args[0] === "--plugin" ? { code: 0, out: "observer: [\n", err: AT("docs/conventions/session-flow.yaml") } : { code: 1, out: "", err: "" }));
  assert.equal(broken.notes.length, 1);
  assert.match(broken.notes[0], /^session-flow\.yaml: /);
});
