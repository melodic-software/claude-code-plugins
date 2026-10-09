// Team-row admission rules: one describe per rule, named by the rule, so a change to a rule fails
// the test that carries its name.
import { strict as assert } from "node:assert";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const { rules, rejections } = await import(join(dirname(fileURLToPath(import.meta.url)), "../scripts/lib/team-policy.mjs"));
const rule = (name) => rules.find((r) => r.name === name);

// Hand-written rows in the routing.json shape; the rules see only these, never the shipped file.
const bundled = [
  { job: "synthesis", rank: 1, id: "/product-management:synthesize-research", kind: "skill", detect: "product-management@knowledge-work-plugins" },
  { job: "synthesis", rank: 3, id: "dovetail", kind: "mcp", detect: "dovetail" },
  { job: "evaluation", rank: 1, id: "lighthouse", kind: "tool", detect: "lighthouse" },
];
const ctx = { bundled, installed: ["/product-management:write-spec", "posthog@claude-plugins-official", "/team-notes", "statsig"] };

describe("id-matches-bundled-or-installed", () => {
  const check = (row, c = ctx) => rule("id-matches-bundled-or-installed").test(row, c);

  test("admits a re-rank of a bundled id", () => {
    assert.equal(check({ ...bundled[1], rank: 1 }).admit, true);
  });

  test("admits a bundled id added under another job", () => {
    assert.equal(check({ ...bundled[1], job: "research-instruments" }).admit, true);
  });

  test("admits an installed plugin skill whose detect names its plugin", () => {
    assert.equal(check({ job: "flows-ia", id: "/product-management:write-spec", kind: "skill", detect: "product-management@knowledge-work-plugins" }).admit, true);
  });

  test("admits an installed plugin", () => {
    assert.equal(check({ job: "analytics", id: "posthog@claude-plugins-official", kind: "plugin", detect: "posthog@claude-plugins-official" }).admit, true);
  });

  test("admits an installed standalone skill", () => {
    assert.equal(check({ job: "synthesis", id: "/team-notes", kind: "skill", detect: "team-notes" }).admit, true);
  });

  test("rejects an unknown id", () => {
    const r = check({ job: "synthesis", id: "/unknown:thing", kind: "skill", detect: "unknown@nowhere" });
    assert.equal(r.admit, false);
    assert.equal(r.rule, "id-matches-bundled-or-installed");
    assert.ok(typeof r.reason === "string" && r.reason.length > 0);
  });

  test("rejects an installed id whose detect names another plugin", () => {
    const r = check({ job: "flows-ia", id: "/product-management:write-spec", kind: "skill", detect: "design@knowledge-work-plugins" });
    assert.equal(r.admit, false);
    assert.equal(r.rule, "id-matches-bundled-or-installed");
  });

  test("rejects an installed MCP server that is not bundled: only plugins and skills may be added", () => {
    const r = check({ job: "measurement", id: "statsig", kind: "mcp", detect: "statsig" });
    assert.equal(r.admit, false);
  });

  test("rejects a new id when the installed list is unknown, and says so", () => {
    const r = check({ job: "flows-ia", id: "/product-management:write-spec", kind: "skill", detect: "product-management@knowledge-work-plugins" }, { bundled, installed: null });
    assert.equal(r.admit, false);
    assert.match(r.reason, /installed list is unavailable/);
  });
});

describe("no-new-tool-rows", () => {
  const check = (row) => rule("no-new-tool-rows").test(row, ctx);

  test("rejects an added kind tool row", () => {
    const r = check({ job: "evaluation", id: "axe", kind: "tool", detect: "axe" });
    assert.equal(r.admit, false);
    assert.equal(r.rule, "no-new-tool-rows");
    assert.ok(typeof r.reason === "string" && r.reason.length > 0);
  });

  test("rejects a bundled non-tool row changed to kind tool", () => {
    assert.equal(check({ ...bundled[1], kind: "tool" }).admit, false);
  });

  test("admits a re-rank of a bundled tool row", () => {
    assert.equal(check({ ...bundled[2], rank: 2 }).admit, true);
  });

  test("admits a row of another kind", () => {
    assert.equal(check({ job: "flows-ia", id: "/product-management:write-spec", kind: "skill", detect: "product-management" }).admit, true);
  });
});

describe("rejections", () => {
  test("lists every rule a row fails, in rule order", () => {
    const failed = rejections({ job: "evaluation", id: "axe", kind: "tool", detect: "axe" }, ctx);
    assert.deepEqual(failed.map((r) => r.rule), ["id-matches-bundled-or-installed", "no-new-tool-rows"]);
  });

  test("is empty for a row every rule admits", () => {
    assert.deepEqual(rejections({ ...bundled[0], rank: 2 }, ctx), []);
  });
});
