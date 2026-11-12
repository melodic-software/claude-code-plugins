import { describe, expect, it } from "vitest";

import { adapter as youtubeAdapter } from "../adapters/youtube.js";
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
 * @returns {import('@melodic/video-digestion/shared/process').SpawnResult}
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

  it("escapes backslashes so a trailing one cannot escape the cell's closing pipe", () => {
    expect(escapeTableCell("C:\\dir\\")).toBe("C:\\\\dir\\\\");
    expect(escapeTableCell("a\\|b")).toBe("a\\\\\\|b");
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
  const patterns = youtubeAdapter.errorPatterns;

  it("classifies removed/private/unavailable as permanent unavailable", () => {
    expect(classifyPreflightFailure("ERROR: [youtube] xyz: Video unavailable", patterns)).toBe(
      "unavailable",
    );
    expect(
      classifyPreflightFailure(
        "ERROR: Private video. Sign in if you've been granted access",
        patterns,
      ),
    ).toBe("unavailable");
    expect(classifyPreflightFailure("This video has been removed by the uploader", patterns)).toBe(
      "unavailable",
    );
  });

  it("classifies bot-check / auth / network as transient", () => {
    expect(classifyPreflightFailure("Sign in to confirm you're not a bot", patterns)).toBe(
      "transient",
    );
    expect(classifyPreflightFailure("unable to download: HTTP Error 429", patterns)).toBe(
      "transient",
    );
    expect(classifyPreflightFailure("", patterns)).toBe("transient");
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

  it("threads a cookies-from-browser override into the probe for a capability-declaring source", () => {
    // Production only supplies this override from the fallback loop, which is
    // itself gated on the same capability the argv gate reads.
    const args = buildPreflightArgs(DRIVER_WATCH_URL, {
      env: {},
      authOverride: { cookiesFromBrowser: "edge" },
      source: { allowBrowserCookieProfileFallback: true },
    });
    expect(args).toContain("--cookies-from-browser");
    expect(args).toContain("edge");
  });

  it("drops a cookies-from-browser override for a source without the capability", () => {
    const args = buildPreflightArgs(DRIVER_WATCH_URL, {
      env: {},
      authOverride: { cookiesFromBrowser: "edge" },
    });
    expect(args).not.toContain("--cookies-from-browser");
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

  it("caps a long title before escaping it, so the cap never leaves a dangling backslash", async () => {
    // 58 characters then a pipe at the cap's last kept position (59 kept + the ellipsis = 60).
    const title = `${"x".repeat(58)}|tail`;
    const stdout = ["7zZy1QTvokM", title, "Austin Marchese", "@austin.marchese"].join(PREFLIGHT_FIELD_SEP);
    const spawn = () => Promise.resolve(spawnResult({ success: true, code: 0, stdout }));
    const result = await preflightVideo(DRIVER_WATCH_URL, { spawn, env });
    expect(result.displayTitle).toBe(`${"x".repeat(58)}\\|…`);
  });

  it("enqueues a just-ended live stream as a valid link and records its live_status", async () => {
    const stdout = [
      "7zZy1QTvokM",
      "Stream",
      "Chan",
      "@chan",
      "D",
      "NA",
      "4",
      "10",
      "post_live",
    ].join(PREFLIGHT_FIELD_SEP);
    const spawn = () => Promise.resolve(spawnResult({ success: true, code: 0, stdout }));
    const result = await preflightVideo(DRIVER_WATCH_URL, { spawn, env });
    expect(result.action).toBe("enqueue");
    expect(result.status).toBe("ok");
    expect(result.liveStatus).toBe("post_live");
    expect(result.note).toContain("captions may follow post-stream processing");
  });

  it("leaves the note empty for a video that is not live-derived", async () => {
    const stdout = ["7zZy1QTvokM", "Talk", "Chan", "@chan", "D", "NA", "4", "10", "not_live"].join(
      PREFLIGHT_FIELD_SEP,
    );
    const spawn = () => Promise.resolve(spawnResult({ success: true, code: 0, stdout }));
    const result = await preflightVideo(DRIVER_WATCH_URL, { spawn, env });
    expect(result.liveStatus).toBe("not_live");
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
