import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { checkConcerns } from "../scripts/lib/concerns-validate.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => JSON.parse(readFileSync(join(PLUGIN, p), "utf8"));
const table = read("reference/concerns.json");
const opts = { pluginRoot: PLUGIN, schema: read("reference/concerns.schema.json"), routing: read("reference/routing.json") };
const check = (t) => checkConcerns(t, opts);
/** The table with its first row changed by `edit`. */
const withRow = (edit) => {
  const t = structuredClone(table);
  edit(t.concerns[0], t);
  return t;
};

test("concerns.json validates", () => {
  assert.deepEqual(check(table), []);
});

// Expected values: the motion row the plan's concern-table design names.
test("the motion row reads the four animation spokes and both animation routing concerns", () => {
  const motion = table.concerns.find((c) => c.id === "motion");
  assert.deepEqual(motion.spokes.map((s) => s.path), [
    "reference/animation/catalog.md",
    "reference/animation/behaviors.md",
    "reference/animation/gestures.md",
    "reference/animation/performance.md",
  ]);
  assert.deepEqual(motion.routing_concerns, ["animation-authoring", "animation-audit"]);
  assert.deepEqual(motion.audit, { order: 4, procedure: "skills/audit/reference/motion.md" });
});

test("a missing spoke file is rejected", () => {
  const errors = check(withRow((c) => (c.spokes[0].path = "reference/animation/no-such-spoke.md")));
  assert.deepEqual(errors, ["$.concerns[0].spokes[0].path: no file reference/animation/no-such-spoke.md"]);
});

test("a spoke path that leaves the plugin root is rejected", () => {
  // A real file of a sibling plugin: it exists, so only the root guard rejects it.
  const path = "reference/../../user-experience/reference/flows-ia.md";
  assert.deepEqual(check(withRow((c) => (c.spokes[0].path = path))), [`$.concerns[0].spokes[0].path: ${path} leaves the plugin root`]);
});

test("a missing recipe or procedure file is rejected", () => {
  const errors = check(
    withRow((c) => {
      c.recipes = ["skills/write-css/reference/no-such-recipe.md"];
      c.audit.procedure = "skills/audit/reference/no-such-lane.md";
    }),
  );
  assert.deepEqual(errors, [
    "$.concerns[0].recipes[0]: no file skills/write-css/reference/no-such-recipe.md",
    "$.concerns[0].audit.procedure: no file skills/audit/reference/no-such-lane.md",
  ]);
});

test("a null procedure is accepted and a non-string one rejected", () => {
  assert.deepEqual(check(withRow((c) => (c.audit.procedure = null))), []);
  assert.deepEqual(check(withRow((c) => (c.audit.procedure = 7))), ["$.concerns[0].audit.procedure: must be null or a path"]);
});

test("an unknown routing concern is rejected", () => {
  const errors = check(withRow((c) => c.routing_concerns.push("no-such-concern")));
  assert.deepEqual(errors, ["$.concerns[0].routing_concerns[2]: no routing.json concern no-such-concern"]);
});

test("a duplicate id is rejected", () => {
  const errors = check(withRow((c, t) => t.concerns.push(structuredClone(c))));
  assert.deepEqual(errors, [`$.concerns[${table.concerns.length}].id: duplicate id motion`]);
});

test("an audit.order another row already holds is rejected", () => {
  const errors = check(withRow((c, t) => t.concerns.push({ ...structuredClone(c), id: "motion-copy" })));
  assert.deepEqual(errors, [`$.concerns[${table.concerns.length}].audit.order: duplicate order 4, also motion`]);
});

test("rows with distinct audit.order values are accepted", () => {
  const free = Math.max(...table.concerns.map((r) => r.audit.order)) + 1;
  const errors = check(withRow((c, t) => t.concerns.push({ ...structuredClone(c), id: "motion-copy", audit: { ...c.audit, order: free } })));
  assert.deepEqual(errors, []);
});

test("an unknown type is rejected", () => {
  const errors = check(withRow((c) => c.types.push("hologram")));
  assert.deepEqual(errors, ["$.concerns[0].types[3]: no type file reference/types/hologram.md"]);
});

test("the schema rejects a non-kebab id, an unknown key and an order below 1", () => {
  const errors = check(
    withRow((c) => {
      c.id = "Motion";
      c.extra = true;
      c.audit.order = 0;
    }),
  ).join("\n");
  assert.match(errors, /\.id: must match/);
  assert.match(errors, /unknown key extra/);
  assert.match(errors, /audit\.order: must be an integer >= 1/);
});
