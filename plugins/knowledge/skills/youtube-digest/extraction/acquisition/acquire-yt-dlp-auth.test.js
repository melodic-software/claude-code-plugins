import { describe, expect, it } from "vitest";

import { adapter as youtubeAdapter } from "../adapters/youtube.js";
import {
  browserCookieFallbackProfiles,
  hasExplicitYtDlpCookieConfig,
  isCookieProfileRetryableError,
} from "./acquire-yt-dlp-auth.js";

const NO_PATTERNS = { retryable: [], fatal: [], loginRequired: [] };

describe("isCookieProfileRetryableError", () => {
  it("matches unsupported browser cookie extraction regardless of source patterns", () => {
    expect(isCookieProfileRetryableError("ERROR: unsupported browser: phantom", NO_PATTERNS)).toBe(
      true,
    );
  });

  it("advances on a login-required classification from the adapter's table", () => {
    expect(
      isCookieProfileRetryableError(
        "ERROR: Sign in to confirm you're not a bot",
        youtubeAdapter.errorPatterns,
      ),
    ).toBe(true);
    expect(
      isCookieProfileRetryableError("ERROR: Sign in to confirm you're not a bot", NO_PATTERNS),
    ).toBe(false);
  });

  it("does not advance on unrelated failures", () => {
    expect(
      isCookieProfileRetryableError("HTTP Error 429: Too Many Requests", youtubeAdapter.errorPatterns),
    ).toBe(false);
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
