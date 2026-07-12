import { describe, expect, it } from "vitest";

import {
  buildYtDlpArgs,
  resolveYtDlpAuthArgs,
  YT_DLP_EXTRACTOR_ARGS,
  YT_DLP_SUB_FORMAT,
  YT_DLP_SUB_LANGS,
  YT_DLP_VIDEO_FORMAT,
} from "./build-yt-dlp-args.js";

const URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const WORK_DIR = "/tmp/youtube-work";
const OUTPUT = `${WORK_DIR}/%(id)s.%(ext)s`;

describe("buildYtDlpArgs", () => {
  it("includes caption and metadata flags for full mode", () => {
    const args = buildYtDlpArgs(URL, {
      mode: "full",
      outputTemplate: OUTPUT,
      workDir: WORK_DIR,
    });

    expect(args).toContain("--write-subs");
    expect(args).toContain("--write-auto-subs");
    expect(args).toContain("--sub-langs");
    expect(args.indexOf("--sub-langs")).toBeLessThan(args.length - 1);
    expect(args[args.indexOf("--sub-langs") + 1]).toBe(YT_DLP_SUB_LANGS);
    expect(args).toContain("--sub-format");
    expect(args[args.indexOf("--sub-format") + 1]).toBe(YT_DLP_SUB_FORMAT);
    expect(args).toContain("--retries");
    expect(args).toContain("--sleep-requests");
    expect(args).toContain("--sleep-subtitles");
    expect(args).toContain("--write-info-json");
    expect(args).toContain("--write-comments");
    expect(args).toContain("--extractor-args");
    expect(args[args.indexOf("--extractor-args") + 1]).toBe(YT_DLP_EXTRACTOR_ARGS);
    expect(args).toContain("-f");
    expect(args[args.indexOf("-f") + 1]).toBe(YT_DLP_VIDEO_FORMAT);
    expect(args).toContain("--remux-video");
    expect(args[args.indexOf("--remux-video") + 1]).toBe("mp4");
    expect(args.at(-1)).toBe(URL);
  });

  it("omits caption flags in video-only mode", () => {
    const args = buildYtDlpArgs(URL, {
      mode: "video-only",
      outputTemplate: OUTPUT,
      workDir: WORK_DIR,
    });

    expect(args).not.toContain("--write-subs");
    expect(args).not.toContain("--write-auto-subs");
    expect(args).not.toContain("--skip-download");
    expect(args).toContain("-f");
    expect(args).toContain("--remux-video");
  });

  it("skips video download in transcript mode", () => {
    const args = buildYtDlpArgs(URL, {
      mode: "transcript",
      outputTemplate: OUTPUT,
      workDir: WORK_DIR,
    });

    expect(args).toContain("--skip-download");
    expect(args).not.toContain("-f");
    expect(args).not.toContain("--remux-video");
  });

  it("routes temp files through the working directory", () => {
    const args = buildYtDlpArgs(URL, {
      mode: "transcript",
      outputTemplate: OUTPUT,
      workDir: WORK_DIR,
    });

    expect(args).toContain("--paths");
    expect(args[args.indexOf("--paths") + 1]).toBe(`temp:${WORK_DIR}`);
  });

  it("appends default js runtime before the URL", () => {
    const args = buildYtDlpArgs(URL, {
      mode: "transcript",
      outputTemplate: OUTPUT,
      workDir: WORK_DIR,
      env: {},
    });
    expect(args).toContain("--js-runtimes");
    expect(args[args.indexOf("--js-runtimes") + 1]).toBe("node");
    expect(args.at(-1)).toBe(URL);
  });

  it("uses cookies-from-browser when configured", () => {
    const args = resolveYtDlpAuthArgs({ YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER: "chrome" });
    expect(args).toEqual(["--cookies-from-browser", "chrome", "--js-runtimes", "node"]);
  });

  it("prefers cookies file over browser", () => {
    const args = resolveYtDlpAuthArgs({
      YOUTUBE_YT_DLP_COOKIES_FILE: "/tmp/cookies.txt",
      YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER: "chrome",
    });
    expect(args).toEqual(["--cookies", "/tmp/cookies.txt", "--js-runtimes", "node"]);
  });

  it("omits js runtimes when disabled", () => {
    const args = resolveYtDlpAuthArgs({ YOUTUBE_YT_DLP_JS_RUNTIMES: "off" });
    expect(args).toEqual([]);
  });

  it("auth override wins over env for browser cookies", () => {
    const args = resolveYtDlpAuthArgs(
      { YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER: "chrome" },
      { cookiesFromBrowser: "edge" },
    );
    expect(args).toEqual(["--cookies-from-browser", "edge", "--js-runtimes", "node"]);
  });
});
