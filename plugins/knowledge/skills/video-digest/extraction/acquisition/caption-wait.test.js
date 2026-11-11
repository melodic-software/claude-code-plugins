import { describe, expect, it } from "vitest";

import {
  CAPTION_WAIT_CHECK_INTERVAL_MS,
  CAPTION_WAIT_MAX_MS,
  captionsPendingMessage,
  decideCaptionWait,
  liveStreamInfo,
  parseCaptionWaitDeadline,
} from "./caption-wait.js";

const NOW = Date.parse("2026-11-11T12:00:00.000Z");
const HOUR = 60 * 60 * 1000;

describe("liveStreamInfo", () => {
  it("reads live_status and the stream end from release_timestamp plus duration", () => {
    const startSec = (NOW - 3 * HOUR) / 1000;
    expect(
      liveStreamInfo({ live_status: "was_live", release_timestamp: startSec, duration: 3600 }),
    ).toEqual({ liveStatus: "was_live", endedAtMs: NOW - 2 * HOUR });
  });

  it("leaves both unknown when info.json lacks them", () => {
    expect(liveStreamInfo({ duration: 60 })).toEqual({ liveStatus: null, endedAtMs: null });
    expect(liveStreamInfo(null)).toEqual({ liveStatus: null, endedAtMs: null });
  });
});

describe("decideCaptionWait", () => {
  it("never waits on a video that is not live-derived", () => {
    expect(decideCaptionWait({ liveStatus: "not_live", endedAtMs: null }, { nowMs: NOW })).toEqual({
      state: "none",
    });
    expect(decideCaptionWait({ liveStatus: null, endedAtMs: null }, { nowMs: NOW })).toEqual({
      state: "none",
    });
    expect(
      decideCaptionWait({ liveStatus: "is_upcoming", endedAtMs: null }, { nowMs: NOW }),
    ).toEqual({ state: "none" });
  });

  it("waits on a post_live stream from now when its end is unknown", () => {
    expect(decideCaptionWait({ liveStatus: "post_live", endedAtMs: null }, { nowMs: NOW })).toEqual({
      state: "wait",
      liveStatus: "post_live",
      nextCheckAt: new Date(NOW + CAPTION_WAIT_CHECK_INTERVAL_MS).toISOString(),
      deadline: new Date(NOW + CAPTION_WAIT_MAX_MS).toISOString(),
    });
  });

  it("waits on a just-ended was_live stream, bounded by its end", () => {
    const endedAtMs = NOW - 2 * HOUR;
    const decision = decideCaptionWait({ liveStatus: "was_live", endedAtMs }, { nowMs: NOW });
    expect(decision).toMatchObject({
      state: "wait",
      deadline: new Date(endedAtMs + CAPTION_WAIT_MAX_MS).toISOString(),
    });
  });

  it("does not wait on a was_live stream that ended long ago or at an unknown time", () => {
    const longAgo = NOW - CAPTION_WAIT_MAX_MS - HOUR;
    expect(
      decideCaptionWait({ liveStatus: "was_live", endedAtMs: longAgo }, { nowMs: NOW }),
    ).toEqual({ state: "none" });
    expect(decideCaptionWait({ liveStatus: "was_live", endedAtMs: null }, { nowMs: NOW })).toEqual({
      state: "none",
    });
  });

  it("caps the next check at the deadline", () => {
    const deadline = new Date(NOW + 10 * 60 * 1000).toISOString();
    const decision = decideCaptionWait(
      { liveStatus: "post_live", endedAtMs: null },
      { deadline, nowMs: NOW },
    );
    expect(decision).toMatchObject({ state: "wait", nextCheckAt: deadline, deadline });
  });

  it("ends a held wait once its recorded deadline passes", () => {
    const deadline = new Date(NOW - 1).toISOString();
    expect(
      decideCaptionWait({ liveStatus: "post_live", endedAtMs: null }, { deadline, nowMs: NOW }),
    ).toEqual({ state: "expired", liveStatus: "post_live", deadline });
  });
});

describe("captionsPendingMessage", () => {
  it("names the next check time", () => {
    expect(
      captionsPendingMessage({
        liveStatus: "post_live",
        nextCheckAt: "2026-11-11T12:30:00.000Z",
        deadline: "2026-11-12T00:00:00.000Z",
      }),
    ).toContain("captions pending, next check at 2026-11-11T12:30:00.000Z");
  });
});

describe("parseCaptionWaitDeadline", () => {
  it("reads the flag, or null when absent", () => {
    expect(parseCaptionWaitDeadline(["node", "x", "url"])).toEqual({ ok: true, deadline: null });
    expect(
      parseCaptionWaitDeadline(["node", "x", "url", "--caption-wait-deadline", "2026-11-12T00:00:00.000Z"]),
    ).toEqual({ ok: true, deadline: "2026-11-12T00:00:00.000Z" });
  });

  it("normalizes an offset time to the UTC form the queue notes record", () => {
    expect(
      parseCaptionWaitDeadline(["node", "x", "url", "--caption-wait-deadline", "2026-11-12T01:00:00+01:00"]),
    ).toEqual({ ok: true, deadline: "2026-11-12T00:00:00.000Z" });
  });

  it("rejects a missing or unparseable value", () => {
    expect(parseCaptionWaitDeadline(["node", "x", "url", "--caption-wait-deadline"]).ok).toBe(false);
    expect(
      parseCaptionWaitDeadline(["node", "x", "url", "--caption-wait-deadline", "soon"]).ok,
    ).toBe(false);
  });
});
