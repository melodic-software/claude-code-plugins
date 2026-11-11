import { describe, expect, it } from "vitest";

import { recheckCaptions, recheckExitCode } from "./caption-recheck.js";

const URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const DEADLINE = "2026-11-12T00:00:00.000Z";

/**
 * @param {object} outcome
 * @param {object[]} calls
 */
const fakeAcquire = (outcome, calls = []) =>
  /** @type {any} */ (
    async (/** @type {string} */ url, /** @type {object} */ options) => {
      calls.push({ url, options });
      return outcome;
    }
  );

describe("recheckCaptions", () => {
  it("runs only a caption pass, carrying the row's deadline", async () => {
    /** @type {any[]} */
    const calls = [];
    await recheckCaptions(URL, { deadline: DEADLINE, acquire: fakeAcquire({ success: true }, calls) });
    expect(calls).toHaveLength(1);
    expect(calls[0].options).toMatchObject({ mode: "transcript", captionWaitDeadline: DEADLINE });
  });

  it("reports captions ready when the caption pass succeeds", async () => {
    const outcome = await recheckCaptions(URL, {
      deadline: DEADLINE,
      acquire: fakeAcquire({ success: true }),
    });
    expect(outcome).toEqual({ result: "captions-ready" });
    expect(recheckExitCode(outcome.result)).toBe(0);
  });

  it("reports captions still pending with the next check time", async () => {
    const wait = {
      state: "wait",
      liveStatus: "post_live",
      nextCheckAt: "2026-11-11T12:30:00.000Z",
      deadline: DEADLINE,
    };
    const outcome = await recheckCaptions(URL, {
      deadline: DEADLINE,
      acquire: fakeAcquire({ success: false, error: "captions pending", captionWait: wait }),
    });
    expect(outcome).toMatchObject({
      result: "captions-pending",
      nextCheckAt: wait.nextCheckAt,
      deadline: DEADLINE,
    });
    expect(recheckExitCode(outcome.result)).toBe(3);
  });

  it("reports the ended wait with the notes the row keeps", async () => {
    const outcome = await recheckCaptions(URL, {
      deadline: DEADLINE,
      acquire: fakeAcquire({
        success: false,
        error: "ladder exhausted",
        captionWait: { state: "expired", liveStatus: "post_live", deadline: DEADLINE },
      }),
    });
    expect(outcome.result).toBe("wait-ended");
    expect(outcome).toMatchObject({
      notes: expect.stringContaining(`deadline ${DEADLINE}`),
    });
    expect(recheckExitCode(outcome.result)).toBe(0);
  });

  it("reports any other failure before the deadline with the next check time", async () => {
    const outcome = await recheckCaptions(URL, {
      deadline: DEADLINE,
      acquire: fakeAcquire({ success: false, error: "HTTP 429" }),
      now: () => Date.parse("2026-11-11T12:00:00.000Z"),
    });
    expect(outcome).toEqual({
      result: "failed",
      error: "HTTP 429",
      nextCheckAt: "2026-11-11T12:30:00.000Z",
      deadline: DEADLINE,
    });
    expect(recheckExitCode(outcome.result)).toBe(1);
  });

  it("ends the wait when a re-check fails past the deadline", async () => {
    const outcome = await recheckCaptions(URL, {
      deadline: DEADLINE,
      acquire: fakeAcquire({ success: false, error: "Video unavailable" }),
      now: () => Date.parse(DEADLINE),
    });
    expect(outcome.result).toBe("wait-ended");
    expect(outcome).toMatchObject({
      notes: expect.stringContaining(`deadline ${DEADLINE}; last re-check failed (Video unavailable)`),
    });
  });
});
