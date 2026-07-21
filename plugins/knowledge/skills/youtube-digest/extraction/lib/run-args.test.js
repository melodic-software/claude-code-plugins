import { describe, expect, it } from "vitest";

import { buildChildEnv, expandPathValue, parseRunArgs } from "./run-args.js";

describe("parseRunArgs", () => {
  it("returns no flags when none are present", () => {
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

  it("extracts the yt-dlp / throttle flags in any order ahead of the script", () => {
    const parsed = parseRunArgs([
      "--max-concurrent-acquires",
      "3",
      "--work-root",
      "/proj",
      "--cookies-from-browser",
      "firefox",
      "--js-runtimes",
      "off",
      "--cookies-file",
      "/tmp/cookies.txt",
      "watch/run-watch.js",
      "https://x",
    ]);
    expect(parsed).toEqual({
      workRoot: "/proj",
      jsRuntimes: "off",
      cookiesFile: "/tmp/cookies.txt",
      cookiesFromBrowser: "firefox",
      maxConcurrentAcquires: "3",
      script: "watch/run-watch.js",
      rest: ["https://x"],
    });
  });

  it("only honors flags in the leading position", () => {
    // A flag after the script is a script argument, not a launcher flag.
    const parsed = parseRunArgs(["watch/queue-claim.js", "--work-root", "list"]);
    expect(parsed.workRoot).toBeUndefined();
    expect(parsed.script).toBe("watch/queue-claim.js");
    expect(parsed.rest).toEqual(["--work-root", "list"]);
  });

  it("throws when --work-root has no value", () => {
    expect(() => parseRunArgs(["--work-root"])).toThrow(/requires a directory value/);
  });

  it("throws when a yt-dlp flag has no value", () => {
    expect(() => parseRunArgs(["--js-runtimes"])).toThrow(/requires a value/);
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
    expect(buildChildEnv(base, { workRoot: "/proj/docs/knowledge" })).toEqual({
      PATH: "/usr/bin",
      CLAUDE_PROJECT_DIR: "/proj",
      YOUTUBE_WORK_ROOT: "/proj/docs/knowledge",
    });
  });

  it("layers each supplied yt-dlp / throttle flag as its child env var", () => {
    const base = { PATH: "/usr/bin" };
    expect(
      buildChildEnv(base, {
        jsRuntimes: "off",
        cookiesFile: "/tmp/cookies.txt",
        cookiesFromBrowser: "firefox",
        maxConcurrentAcquires: "3",
      }),
    ).toEqual({
      PATH: "/usr/bin",
      YOUTUBE_YT_DLP_JS_RUNTIMES: "off",
      YOUTUBE_YT_DLP_COOKIES_FILE: "/tmp/cookies.txt",
      YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER: "firefox",
      YOUTUBE_MAX_CONCURRENT_ACQUIRES: "3",
    });
  });

  it("skips empty flags and returns the base env untouched when none are set", () => {
    const base = { PATH: "/usr/bin" };
    expect(buildChildEnv(base, {})).toBe(base);
    expect(buildChildEnv(base, undefined)).toBe(base);
    expect(buildChildEnv(base, { workRoot: "" })).toBe(base);
  });

  it("does not mutate the base env", () => {
    const base = { PATH: "/usr/bin" };
    buildChildEnv(base, { workRoot: "/proj" });
    expect(base).toEqual({ PATH: "/usr/bin" });
  });
});

describe("expandPathValue", () => {
  const home = "/srv/dev-home";

  it("passes literal values through untouched", () => {
    expect(expandPathValue("/data/corpus", {}, home)).toBe("/data/corpus");
    expect(expandPathValue("docs/knowledge", {}, home)).toBe("docs/knowledge");
    expect(expandPathValue("C:\\corpus", {}, home)).toBe("C:\\corpus");
  });

  it("expands a bare tilde and a tilde prefix to the home directory", () => {
    expect(expandPathValue("~", {}, home)).toBe(home);
    expect(expandPathValue("~/corpus", {}, home)).toBe("/srv/dev-home/corpus");
    expect(expandPathValue("~\\corpus", {}, "C:\\dev-home")).toBe("C:\\dev-home\\corpus");
  });

  it("does not treat a ~user form as expandable", () => {
    expect(expandPathValue("~other/corpus", {}, home)).toBe("~other/corpus");
  });

  it("expands ${NAME} and %NAME% references from the supplied env", () => {
    const env = { KNOWLEDGE_CORPUS_DIR: "/data/knowledge-corpus" };
    expect(expandPathValue("${KNOWLEDGE_CORPUS_DIR}", env, home)).toBe("/data/knowledge-corpus");
    expect(expandPathValue("%KNOWLEDGE_CORPUS_DIR%", env, home)).toBe("/data/knowledge-corpus");
    expect(expandPathValue("${KNOWLEDGE_CORPUS_DIR}/youtube", env, home)).toBe(
      "/data/knowledge-corpus/youtube",
    );
    expect(expandPathValue("/mnt/${KNOWLEDGE_CORPUS_DIR}", { KNOWLEDGE_CORPUS_DIR: "kc" }, home)).toBe(
      "/mnt/kc",
    );
  });

  it("keeps Windows backslashes intact in substituted values", () => {
    const env = { KNOWLEDGE_CORPUS_DIR: "D:\\repos\\knowledge-corpus" };
    expect(expandPathValue("${KNOWLEDGE_CORPUS_DIR}", env, home)).toBe("D:\\repos\\knowledge-corpus");
  });

  it("throws on an unset or empty referenced variable", () => {
    expect(() => expandPathValue("${MISSING_DIR}", {}, home)).toThrow(/unset or empty/);
    expect(() => expandPathValue("%MISSING_DIR%", { MISSING_DIR: "" }, home)).toThrow(/unset or empty/);
  });

  it("throws when an expanded form yields a non-absolute path", () => {
    expect(() => expandPathValue("${REL_DIR}", { REL_DIR: "relative/corpus" }, home)).toThrow(
      /non-absolute/,
    );
    expect(() => expandPathValue("~/corpus", {}, "relative-home")).toThrow(/non-absolute/);
  });
});
