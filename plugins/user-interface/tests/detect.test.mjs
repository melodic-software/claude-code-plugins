import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const TESTS = dirname(fileURLToPath(import.meta.url));
const DETECT = join(TESTS, "../scripts/detect.mjs");
const FIX = join(TESTS, "fixtures");
const PLUGINS = join(FIX, "plugin-list.json");
const MCP = join(FIX, "mcp-list.txt");

const scratch = mkdtempSync(join(tmpdir(), "ui-detect-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
const HOME = join(scratch, "home");
mkdirSync(join(HOME, ".claude/skills/animate"), { recursive: true });

/** Runs detect.mjs as a CLI; `env` replaces the child's environment when given. */
function detect(args, env) {
  const r = spawnSync(process.execPath, [DETECT, ...args], { encoding: "utf8", env });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}
const seams = ["--home", HOME, "--plugin-list-json", PLUGINS, "--mcp-list", MCP];

describe("project signals", () => {
  test("a project with a design system reports each signal", () => {
    const { project } = detect(["--project", join(FIX, "with-ds"), ...seams]);
    assert.deepEqual(project.tokens, ["design-tokens.json"]);
    assert.deepEqual(project.packages, ["@mui/material", "@storybook/react", "chalk"]);
    assert.equal(project.components_json, true);
    assert.equal(project.storybook, true);
    assert.deepEqual(project.docs, ["DESIGN.md"]);
    assert.deepEqual(project.mcp_servers, ["shadcn"]);
  });

  test("a project without one reports nothing", () => {
    const { project } = detect(["--project", join(FIX, "no-ds"), ...seams]);
    assert.deepEqual(project, { tokens: [], packages: [], components_json: false, storybook: false, docs: [], mcp_servers: [] });
  });
});

describe("installed tools", () => {
  const installed = detect(["--project", join(FIX, "with-ds"), ...seams]).installed;

  test("an enabled user-scope plugin counts", () => {
    assert.ok(installed.includes("frontend-design@claude-plugins-official"));
  });

  test("a project or local record counts only when projectEnabled", () => {
    assert.ok(installed.includes("chrome-devtools-mcp@claude-plugins-official"), "disabled at user scope, enabled locally");
    assert.ok(!installed.includes("figma@claude-plugins-official"), "project record enabled elsewhere, not here");
  });

  test("an installed but disabled plugin does not count, nor does an absent one", () => {
    assert.ok(!installed.includes("canva@claude-plugins-official"));
    assert.ok(!installed.includes("superdesign@claude-plugins-official"));
  });

  test("a repo skill counts through its plugin", () => {
    assert.ok(installed.includes("playgrounds:use"));
    assert.ok(!installed.includes("writing:be-concise"));
  });

  test("a skill counts when its directory is in the user or project skills folder", () => {
    assert.ok(installed.includes("animate"));
    assert.ok(!installed.includes("design-taste-frontend"));
    const project = join(scratch, "proj");
    mkdirSync(join(project, ".claude/skills/design-taste-frontend"), { recursive: true });
    assert.ok(detect(["--project", project, ...seams]).installed.includes("design-taste-frontend"));
  });

  test("an mcp server counts from claude mcp list or the project's .mcp.json", () => {
    assert.ok(installed.includes("storybook"), "from mcp list");
    assert.ok(installed.includes("magic"), "plugin-provided server, listed though not connected");
    assert.ok(installed.includes("shadcn"), "from .mcp.json");
    assert.ok(!detect(["--project", join(FIX, "no-ds"), ...seams]).installed.includes("shadcn"));
  });

  test("each id appears once though several concerns route to it", () => {
    assert.equal(installed.filter((id) => id === "frontend-design@claude-plugins-official").length, 1);
  });
});

test("without the claude CLI, installed is null with a reason", () => {
  const out = detect(["--project", join(FIX, "no-ds"), "--home", HOME], { PATH: join(scratch, "empty-path") });
  assert.equal(out.installed, null);
  assert.match(out.reason, /claude/);
  assert.deepEqual(out.project.tokens, []);
});

test("a malformed plugin list is reported, not thrown", () => {
  const bad = join(scratch, "bad.json");
  writeFileSync(bad, "{not json");
  const out = detect(["--project", join(FIX, "no-ds"), "--home", HOME, "--plugin-list-json", bad, "--mcp-list", MCP]);
  assert.equal(out.installed, null);
  assert.match(out.reason, /plugin list/);
});
