import { describe, expect, it } from "vitest";

import { resolvePluginData, takeDataDirFlag } from "./plugin-data.js";

describe("takeDataDirFlag", () => {
  it("splits a leading --data-dir off the script and its args", () => {
    expect(takeDataDirFlag(["--data-dir", "/d/knowledge-m", "extract-course.js", "--course-dir", "/c"])).toEqual({
      dataDir: "/d/knowledge-m",
      rest: ["extract-course.js", "--course-dir", "/c"],
    });
  });

  it("leaves argv alone when the flag is not leading", () => {
    expect(takeDataDirFlag(["extract-course.js", "--data-dir", "/d"])).toEqual({
      dataDir: undefined,
      rest: ["extract-course.js", "--data-dir", "/d"],
    });
  });

  it("throws when --data-dir has no value", () => {
    expect(() => takeDataDirFlag(["--data-dir"])).toThrow(/`--data-dir` requires a directory value/);
  });
});

describe("resolvePluginData", () => {
  const knowledge = "C:/fixture/claude/plugins/data/knowledge-melodic-software";
  const codex = "C:/fixture/claude/plugins/data/codex-openai-codex";

  it("prefers the flag over an inherited value naming another plugin", () => {
    expect(resolvePluginData(knowledge, { CLAUDE_PLUGIN_DATA: codex })).toBe(knowledge);
  });

  it("ignores an inherited value naming another plugin when no flag is given", () => {
    expect(resolvePluginData(undefined, { CLAUDE_PLUGIN_DATA: codex })).toBeUndefined();
  });

  it("keeps an inherited value naming this plugin when no flag is given", () => {
    expect(resolvePluginData(undefined, { CLAUDE_PLUGIN_DATA: knowledge })).toBe(knowledge);
    const windows = "C:\\fixture\\claude\\plugins\\data\\knowledge-inline\\";
    expect(resolvePluginData(undefined, { CLAUDE_PLUGIN_DATA: windows })).toBe(windows);
  });

  it("does not take a prefix match for this plugin's name", () => {
    const lookalike = "/var/fixture/claude/plugins/data/knowledgebase-other";
    expect(resolvePluginData(undefined, { CLAUDE_PLUGIN_DATA: lookalike })).toBeUndefined();
  });

  it("throws on a placeholder that reached the script unsubstituted", () => {
    expect(() => resolvePluginData("${CLAUDE_PLUGIN_DATA}", {})).toThrow(/unsubstituted placeholder/);
    expect(() => resolvePluginData("<plugin-data>", {})).toThrow(/unsubstituted placeholder/);
  });
});
