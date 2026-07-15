import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { activeProfile, configDir, stateRoot, validateProfileName } from "../lib/paths.js";

function withEnvironment(values, fn) {
  const keys = Object.keys(values);
  const original = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  try {
    for (const [key, value] of Object.entries(values)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    fn();
  } finally {
    for (const [key, value] of Object.entries(original)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test("activeProfile defaults when no explicit process value is passed", () => {
  withEnvironment({ AI_BRIEFING_PROFILE: undefined }, () => {
    assert.equal(activeProfile(), "default");
  });
});

test("activeProfile reads the explicitly passed build-process value", () => {
  withEnvironment({ AI_BRIEFING_PROFILE: "team" }, () => {
    assert.equal(activeProfile(), "team");
  });
});

test("activeProfile does not assume plugin options reach arbitrary subprocesses", () => {
  withEnvironment(
    {
      AI_BRIEFING_PROFILE: undefined,
      CLAUDE_PLUGIN_OPTION_ACTIVE_PROFILE: "not-inherited",
    },
    () => assert.equal(activeProfile(), "default"),
  );
});

test("profile validation accepts a single portable slug", () => {
  assert.equal(validateProfileName("team-alpha-1-2"), "team-alpha-1-2");
});

test("profile validation rejects POSIX and Windows traversal forms", () => {
  for (const value of [
    ".",
    "..",
    "../outside",
    "team/../../outside",
    "/tmp/outside",
    "..\\outside",
    "team\\..\\outside",
    "C:\\outside",
    "C:outside",
    "\\\\server\\share",
    "team.",
    "Team",
    "team_alpha",
    "con",
    "NUL",
    "com1",
    "lpt9",
    "a".repeat(64),
  ]) {
    assert.throws(() => validateProfileName(value), /lowercase-kebab/, value);
  }
});

test("state and project paths remain under their configured roots", () => {
  const dataRoot = path.resolve("test-plugin-data");
  const projectRoot = path.resolve("test-project");
  withEnvironment(
    {
      CLAUDE_PLUGIN_DATA: dataRoot,
      CLAUDE_PROJECT_DIR: projectRoot,
    },
    () => {
      assert.equal(stateRoot("team"), path.join(dataRoot, "team"));
      assert.equal(configDir("team"), path.join(projectRoot, ".claude", "ai-briefing", "team"));
    },
  );
});
