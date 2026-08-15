import { describe, expect, it } from "vitest";

import {
  browserCookieFallbackProfiles,
  hasExplicitYtDlpCookieConfig,
  isCookieProfileRetryableError,
  isLoginRequiredError,
  YOUTUBE_BOT_CHALLENGE_PATTERNS,
} from "./acquire-yt-dlp-auth.js";

describe("isLoginRequiredError", () => {
  it("matches sign-in bot challenge text against the declared patterns", () => {
    expect(
      isLoginRequiredError(
        "ERROR: Sign in to confirm you're not a bot",
        YOUTUBE_BOT_CHALLENGE_PATTERNS,
      ),
    ).toBe(true);
  });

  it("rejects unrelated failures", () => {
    expect(
      isLoginRequiredError("HTTP Error 429: Too Many Requests", YOUTUBE_BOT_CHALLENGE_PATTERNS),
    ).toBe(false);
  });

  it("matches nothing when the source declares no patterns", () => {
    expect(isLoginRequiredError("ERROR: Sign in to confirm you're not a bot", [])).toBe(false);
  });
});

describe("isCookieProfileRetryableError", () => {
  it("matches unsupported browser cookie extraction", () => {
    expect(
      isCookieProfileRetryableError(
        "ERROR: unsupported browser: phantom",
        YOUTUBE_BOT_CHALLENGE_PATTERNS,
      ),
    ).toBe(true);
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
