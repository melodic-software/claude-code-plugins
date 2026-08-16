import { describe, expect, it, vi } from "vitest";

import {
  compareObservation,
  isLoginRequiredStderr,
  loadProbes,
  parseArgs,
  resolveCookiesFile,
  runAllProbes,
  runProbe,
} from "./run-source-liveness.js";

describe("resolveCookiesFile", () => {
  it("prefers VIDEO_DIGEST_ over legacy YOUTUBE_ env", () => {
    expect(
      resolveCookiesFile({
        VIDEO_DIGEST_YT_DLP_COOKIES_FILE: "/new/cookies.txt",
        YOUTUBE_YT_DLP_COOKIES_FILE: "/old/cookies.txt",
      }),
    ).toBe("/new/cookies.txt");
  });

  it("falls back to the legacy name", () => {
    expect(resolveCookiesFile({ YOUTUBE_YT_DLP_COOKIES_FILE: "/old/cookies.txt" })).toBe(
      "/old/cookies.txt",
    );
  });

  it("returns null when unset", () => {
    expect(resolveCookiesFile({})).toBeNull();
  });
});

describe("isLoginRequiredStderr", () => {
  it("matches the three X raise_login_required shapes", () => {
    expect(isLoginRequiredStderr("ERROR: [twitter] NSFW tweet requires authentication")).toBe(
      true,
    );
    expect(
      isLoginRequiredStderr("ERROR: [twitter] You are not authorized to view this protected tweet"),
    ).toBe(true);
    expect(isLoginRequiredStderr("ERROR: [twitter] not authorized")).toBe(true);
    expect(isLoginRequiredStderr("ERROR: [twitter] No video could be found in this tweet")).toBe(
      false,
    );
  });
});

describe("compareObservation", () => {
  it("accepts a matching youtube shape", () => {
    const result = compareObservation(
      {
        disposition: "ok",
        metadata: {
          extractor_key: "Youtube",
          id: "7zZy1QTvokM",
          formats: [{ format_id: "18" }],
        },
      },
      { extractorKeys: ["Youtube", "youtube"], id: "7zZy1QTvokM", minFormats: 1 },
    );
    expect(result.ok).toBe(true);
  });

  it("fails loud on extractor drift", () => {
    const result = compareObservation(
      {
        disposition: "ok",
        metadata: { extractor_key: "generic", id: "7zZy1QTvokM", formats: [{}] },
      },
      { extractorKeys: ["Youtube"], id: "7zZy1QTvokM", minFormats: 1 },
    );
    expect(result.ok).toBe(false);
    expect(result.detail).toMatch(/extractor_key/);
  });

  it("accepts expected login-required disposition", () => {
    const result = compareObservation(
      { disposition: "login-required", metadata: null, stderr: "NSFW tweet requires authentication" },
      { disposition: "login-required" },
    );
    expect(result.ok).toBe(true);
  });
});

describe("parseArgs", () => {
  it("defaults to offline", () => {
    expect(parseArgs([]).mode).toBe("offline");
  });

  it("accepts --live", () => {
    expect(parseArgs(["--live"]).mode).toBe("live");
  });

  it("rejects unknown flags", () => {
    expect(() => parseArgs(["--network"])).toThrow(/unknown argument/);
  });
});

describe("runAllProbes offline", () => {
  it("passes every shipped probe against its fixture with no network", async () => {
    const summary = await runAllProbes({ mode: "offline", checkDispatch: false });
    expect(summary.failed).toBe(0);
    expect(summary.passed).toBe(3);
    expect(summary.skipped).toBe(0);
  });

  it("loads the probe manifest with the three planned rows", async () => {
    const { probes } = await loadProbes();
    expect(probes.map((p) => p.id).sort()).toEqual([
      "x-login-required-shape",
      "x-verified-public",
      "youtube-canonical",
    ]);
  });
});

describe("runProbe live auth skip", () => {
  it("skips authRequired probes when cookies are absent (never fails)", async () => {
    const spawn = vi.fn();
    const { probes } = await loadProbes();
    const authProbe = probes.find((p) => p.id === "x-login-required-shape");
    expect(authProbe).toBeTruthy();
    const result = await runProbe(authProbe, {
      mode: "live",
      spawn,
      cookiesFile: null,
      env: {},
      checkDispatch: false,
    });
    expect(result.status).toBe("skip");
    expect(spawn).not.toHaveBeenCalled();
  });

  it("classifies login-required stderr from a live spawn", async () => {
    const { probes } = await loadProbes();
    const authProbe = probes.find((p) => p.id === "x-login-required-shape");
    const spawn = vi.fn(async () => ({
      success: false,
      code: 1,
      signal: null,
      stdout: "",
      stderr: "ERROR: [twitter] 1: NSFW tweet requires authentication. Use --cookies.",
      timedOut: false,
    }));
    const result = await runProbe(authProbe, {
      mode: "live",
      spawn,
      cookiesFile: "/tmp/cookies.txt",
      env: {},
      checkDispatch: false,
    });
    expect(result.status).toBe("skip");
    expect(result.observation?.disposition).toBe("login-required");
  });
});

describe("runProbe live shape check", () => {
  it("passes when injected spawn returns matching metadata", async () => {
    const { probes } = await loadProbes();
    const yt = probes.find((p) => p.id === "youtube-canonical");
    const spawn = vi.fn(async () => ({
      success: true,
      code: 0,
      signal: null,
      stdout: JSON.stringify({
        extractor: "youtube",
        extractor_key: "Youtube",
        id: "7zZy1QTvokM",
        display_id: "7zZy1QTvokM",
        formats: [{ format_id: "18" }],
      }),
      stderr: "",
      timedOut: false,
    }));
    const result = await runProbe(yt, {
      mode: "live",
      spawn,
      cookiesFile: null,
      checkDispatch: false,
    });
    expect(result.status).toBe("pass");
    expect(spawn).toHaveBeenCalledOnce();
  });

  it("fails when extractor drifts", async () => {
    const { probes } = await loadProbes();
    const yt = probes.find((p) => p.id === "youtube-canonical");
    const spawn = vi.fn(async () => ({
      success: true,
      code: 0,
      signal: null,
      stdout: JSON.stringify({
        extractor_key: "generic",
        id: "7zZy1QTvokM",
        formats: [{ format_id: "18" }],
      }),
      stderr: "",
      timedOut: false,
    }));
    const result = await runProbe(yt, {
      mode: "live",
      spawn,
      checkDispatch: false,
    });
    expect(result.status).toBe("fail");
    expect(result.detail).toMatch(/extractor_key/);
  });
});
