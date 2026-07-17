import { describe, expect, it } from "vitest";

import {
  browserCookieFallbackProfiles,
  hasExplicitYtDlpCookieConfig,
  isCookieProfileRetryableError,
  isYoutubeBotChallengeError,
} from "./acquire-yt-dlp-auth.js";

describe("isYoutubeBotChallengeError", () => {
  it("matches sign-in bot challenge text", () => {
    expect(isYoutubeBotChallengeError("ERROR: Sign in to confirm you're not a bot")).toBe(true);
  });

  it("rejects unrelated failures", () => {
    expect(isYoutubeBotChallengeError("HTTP Error 429: Too Many Requests")).toBe(false);
  });
});

describe("isCookieProfileRetryableError", () => {
  it("matches unsupported browser cookie extraction", () => {
    expect(isCookieProfileRetryableError("ERROR: unsupported browser: phantom")).toBe(true);
  });
});

describe("hasExplicitYtDlpCookieConfig", () => {
  it("detects cookies file env", () => {
    expect(hasExplicitYtDlpCookieConfig({ YOUTUBE_YT_DLP_COOKIES_FILE: "/tmp/c.txt" })).toBe(true);
  });

  it("is false when unset", () => {
    expect(hasExplicitYtDlpCookieConfig({})).toBe(false);
  });
});

describe("browserCookieFallbackProfiles", () => {
  it("returns explicit browser when env is set", () => {
    expect(
      browserCookieFallbackProfiles({ YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER: "firefox" }),
    ).toEqual(["firefox"]);
  });

  it("returns platform order when env is unset", () => {
    const profiles = browserCookieFallbackProfiles({});
    expect(profiles.length).toBeGreaterThan(0);
    expect(profiles).toContain("chrome");
  });
});
