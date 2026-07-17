import { describe, expect, it } from "vitest";

import {
  buildPreflightArgs,
  classifyPreflightFailure,
  escapeTableCell,
  formatChannel,
  PREFLIGHT_FIELD_SEP,
  parsePreflightLine,
  preflightVideo,
  truncateTitle,
} from "./preflight-metadata.js";

const DRIVER_WATCH_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";

/**
 * @param {object} overrides
 * @returns {import('@melodic/video-digestion/shared/process.js').SpawnResult}
 */
function spawnResult(overrides) {
  return {
    success: false,
    code: 1,
    signal: null,
    stdout: "",
    stderr: "",
    timedOut: false,
    ...overrides,
  };
}

describe("escapeTableCell", () => {
  it("escapes pipes so a title cannot break the markdown table", () => {
    expect(escapeTableCell("Rust | Go | C")).toBe("Rust \\| Go \\| C");
  });

  it("collapses newlines and runs of whitespace to a single space", () => {
    expect(escapeTableCell("line one\nline   two\t")).toBe("line one line two");
  });
});

describe("truncateTitle", () => {
  it("leaves short titles untouched", () => {
    expect(truncateTitle("Short title", 60)).toBe("Short title");
  });

  it("truncates long titles with an ellipsis at the cap", () => {
    const long = "x".repeat(80);
    const result = truncateTitle(long, 60);
    expect([...result]).toHaveLength(60);
    expect(result.endsWith("…")).toBe(true);
  });

  it("counts code points, not UTF-16 units", () => {
    const emoji = "😀".repeat(10);
    expect(truncateTitle(emoji, 5)).toBe("😀😀😀😀…");
  });
});

describe("formatChannel", () => {
  it("combines display name and handle", () => {
    expect(formatChannel("Austin Marchese", "@austin.marchese")).toBe(
      "Austin Marchese (@austin.marchese)",
    );
  });

  it("falls back to whichever field is present", () => {
    expect(formatChannel("Austin Marchese", "")).toBe("Austin Marchese");
    expect(formatChannel("", "@austin.marchese")).toBe("@austin.marchese");
    expect(formatChannel("", "")).toBe("");
  });
});

describe("parsePreflightLine", () => {
  it("splits the print template and normalizes yt-dlp NA to empty", () => {
    const line = ["7zZy1QTvokM", "Sample Talk", "Austin Marchese", "@austin.marchese"].join(
      PREFLIGHT_FIELD_SEP,
    );
    expect(parsePreflightLine(line)).toEqual({
      id: "7zZy1QTvokM",
      title: "Sample Talk",
      channel: "Austin Marchese",
      handle: "@austin.marchese",
    });
  });

  it("maps NA fields to empty strings", () => {
    const line = ["abc", "Title", "NA", "NA"].join(PREFLIGHT_FIELD_SEP);
    expect(parsePreflightLine(line)).toEqual({
      id: "abc",
      title: "Title",
      channel: "",
      handle: "",
    });
  });

  it("reads only the first non-empty line", () => {
    const line = `\n${["id", "t", "c", "@h"].join(PREFLIGHT_FIELD_SEP)}\nnoise`;
    expect(parsePreflightLine(line).title).toBe("t");
  });
});

describe("classifyPreflightFailure", () => {
  it("classifies removed/private/unavailable as permanent unavailable", () => {
    expect(classifyPreflightFailure("ERROR: [youtube] xyz: Video unavailable")).toBe("unavailable");
    expect(
      classifyPreflightFailure("ERROR: Private video. Sign in if you've been granted access"),
    ).toBe("unavailable");
    expect(classifyPreflightFailure("This video has been removed by the uploader")).toBe(
      "unavailable",
    );
  });

  it("classifies bot-check / auth / network as transient", () => {
    expect(classifyPreflightFailure("Sign in to confirm you're not a bot")).toBe("transient");
    expect(classifyPreflightFailure("unable to download: HTTP Error 429")).toBe("transient");
    expect(classifyPreflightFailure("")).toBe("transient");
  });
});

describe("buildPreflightArgs", () => {
  it("builds a skip-download print probe with auth args before the url", () => {
    const args = buildPreflightArgs(DRIVER_WATCH_URL, { env: {} });
    expect(args).toContain("--skip-download");
    expect(args).toContain("--no-playlist");
    expect(args).toContain("--print");
    expect(args.at(-1)).toBe(DRIVER_WATCH_URL);
    // default js-runtime auth flag is appended (env has no cookie config)
    expect(args).toContain("--js-runtimes");
  });

  it("threads a cookies-from-browser override into the probe", () => {
    const args = buildPreflightArgs(DRIVER_WATCH_URL, {
      env: {},
      authOverride: { cookiesFromBrowser: "edge" },
    });
    expect(args).toContain("--cookies-from-browser");
    expect(args).toContain("edge");
  });
});

describe("preflightVideo", () => {
  const env = {};

  it("rejects a URL that is not a recognizable YouTube video", async () => {
    const spawn = () => Promise.reject(new Error("spawn must not run for invalid url"));
    const result = await preflightVideo("https://example.com/not-youtube", { spawn, env });
    expect(result.ok).toBe(false);
    expect(result.status).toBe("invalid-url");
    expect(result.action).toBe("reject");
    expect(result.videoId).toBeNull();
  });

  it("returns escaped display cells on a successful probe", async () => {
    const stdout = ["7zZy1QTvokM", "Pipe | Title", "Austin Marchese", "@austin.marchese"].join(
      PREFLIGHT_FIELD_SEP,
    );
    const spawn = () => Promise.resolve(spawnResult({ success: true, code: 0, stdout }));
    const result = await preflightVideo(DRIVER_WATCH_URL, { spawn, env });
    expect(result.ok).toBe(true);
    expect(result.status).toBe("ok");
    expect(result.action).toBe("enqueue");
    expect(result.videoId).toBe("7zZy1QTvokM");
    expect(result.displayTitle).toBe("Pipe \\| Title");
    expect(result.displayChannel).toBe("Austin Marchese (@austin.marchese)");
    expect(result.note).toBe("");
  });

  it("rejects a permanently unavailable video", async () => {
    const spawn = () =>
      Promise.resolve(spawnResult({ stderr: "ERROR: [youtube] zzz: Video unavailable" }));
    const result = await preflightVideo(DRIVER_WATCH_URL, { spawn, env });
    expect(result.ok).toBe(false);
    expect(result.status).toBe("unavailable");
    expect(result.action).toBe("reject");
    expect(result.videoId).toBe("7zZy1QTvokM");
  });

  it("enqueues a transient failure with a note", async () => {
    const spawn = () =>
      Promise.resolve(spawnResult({ stderr: "Sign in to confirm you're not a bot" }));
    const result = await preflightVideo(DRIVER_WATCH_URL, { spawn, env });
    expect(result.ok).toBe(false);
    expect(result.status).toBe("transient");
    expect(result.action).toBe("enqueue");
    expect(result.note).toContain("preflight");
  });
});
