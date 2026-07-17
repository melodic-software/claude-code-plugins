import { describe, expect, it } from "vitest";

import { buildChildEnv, parseRunArgs } from "./run-args.js";

describe("parseRunArgs", () => {
  it("returns no work root when the flag is absent", () => {
    expect(parseRunArgs(["watch/run-watch.js", "https://x"])).toEqual({
      workRoot: undefined,
      script: "watch/run-watch.js",
      rest: ["https://x"],
    });
  });

  it("extracts a leading --work-root and strips it from the script args", () => {
    expect(parseRunArgs(["--work-root", "/proj/docs/knowledge", "transcript/run-transcript.js", "https://x"])).toEqual({
      workRoot: "/proj/docs/knowledge",
      script: "transcript/run-transcript.js",
      rest: ["https://x"],
    });
  });

  it("only honors --work-root in the leading position", () => {
    // A `--work-root` after the script is a script argument, not the launcher flag.
    const parsed = parseRunArgs(["watch/queue-claim.js", "--work-root", "list"]);
    expect(parsed.workRoot).toBeUndefined();
    expect(parsed.script).toBe("watch/queue-claim.js");
    expect(parsed.rest).toEqual(["--work-root", "list"]);
  });

  it("throws when --work-root has no value", () => {
    expect(() => parseRunArgs(["--work-root"])).toThrow(/requires a directory value/);
  });

  it("does not mutate the caller's argv", () => {
    const argv = ["--work-root", "/proj", "watch/run-watch.js"];
    parseRunArgs(argv);
    expect(argv).toEqual(["--work-root", "/proj", "watch/run-watch.js"]);
  });
});

describe("buildChildEnv", () => {
  it("layers YOUTUBE_WORK_ROOT on top of the inherited env when a root is given", () => {
    const base = { PATH: "/usr/bin", CLAUDE_PROJECT_DIR: "/proj" };
    expect(buildChildEnv(base, "/proj/docs/knowledge")).toEqual({
      PATH: "/usr/bin",
      CLAUDE_PROJECT_DIR: "/proj",
      YOUTUBE_WORK_ROOT: "/proj/docs/knowledge",
    });
  });

  it("returns the base env untouched when no work root is given", () => {
    const base = { PATH: "/usr/bin" };
    expect(buildChildEnv(base, undefined)).toBe(base);
    expect(buildChildEnv(base, "")).toBe(base);
  });

  it("does not mutate the base env", () => {
    const base = { PATH: "/usr/bin" };
    buildChildEnv(base, "/proj");
    expect(base).toEqual({ PATH: "/usr/bin" });
  });
});
