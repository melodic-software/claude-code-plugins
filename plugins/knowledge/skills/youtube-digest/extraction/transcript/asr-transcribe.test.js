import { afterEach, describe, expect, it, vi } from "vitest";

import {
  ASR_BATCH_SIZE,
  ASR_MODEL,
  detectAsrCapability,
  resetAsrDetectionCache,
  runAsrTranscription,
} from "./asr-transcribe.js";

/**
 * @param {Partial<{success: boolean, code: number|null, stdout: string, stderr: string, error: string}>} overrides
 */
function spawnResult(overrides = {}) {
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

afterEach(() => {
  resetAsrDetectionCache();
});

describe("detectAsrCapability", () => {
  it("reports available via the first interpreter that imports faster-whisper", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValueOnce(spawnResult({ error: "ENOENT" }))
      .mockResolvedValueOnce(spawnResult({ success: true, code: 0, stdout: "1.1.0\n" }));
    const detection = await detectAsrCapability({ spawn });
    expect(detection.available).toBe(true);
    expect(detection.python).toBe("python3");
    expect(detection.version).toBe("1.1.0");
    expect(spawn).toHaveBeenCalledTimes(2);
  });

  it("reports absent (never installs) when no interpreter imports it", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValue(spawnResult({ stderr: "ModuleNotFoundError: faster_whisper" }));
    const detection = await detectAsrCapability({ spawn });
    expect(detection.available).toBe(false);
    expect(detection.python).toBeNull();
    expect(detection.detail).toContain("not detected");
    expect(spawn).toHaveBeenCalledTimes(3);
  });

  it("caches the detection per process", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValue(spawnResult({ success: true, code: 0, stdout: "1.1.0" }));
    await detectAsrCapability({ spawn });
    await detectAsrCapability({ spawn });
    expect(spawn).toHaveBeenCalledTimes(1);
  });
});

describe("runAsrTranscription", () => {
  it("invokes the helper with the pinned model and batch size and parses cues", async () => {
    const payload = {
      model: ASR_MODEL,
      language: "en",
      segments: [
        {
          start: 0,
          end: 2.5,
          text: " hello world ",
          words: [
            { start: 0, end: 1, word: " hello" },
            { start: 1, end: 2.5, word: " world" },
          ],
        },
      ],
    };
    const spawn = vi
      .fn()
      .mockResolvedValue(
        spawnResult({ success: true, code: 0, stdout: JSON.stringify(payload) }),
      );

    const result = await runAsrTranscription({
      mediaPath: "/w/clip.mp4",
      python: "python",
      initialPrompt: "Claude Code, MySkills",
      spawn,
    });

    const [command, args] = spawn.mock.calls[0];
    expect(command).toBe("python");
    expect(args).toContain("--media");
    expect(args).toContain("/w/clip.mp4");
    expect(args).toContain(ASR_MODEL);
    expect(args).toContain(String(ASR_BATCH_SIZE));
    expect(args).toContain("--initial-prompt");
    expect(args[0]).toMatch(/asr_transcribe\.py$/);

    expect(result.success).toBe(true);
    expect(result.cues).toEqual([{ startSec: 0, endSec: 2.5, text: "hello world" }]);
    expect(result.words).toHaveLength(2);
    expect(result.language).toBe("en");
  });

  it("omits --initial-prompt when no prompt is given", async () => {
    const spawn = vi.fn().mockResolvedValue(
      spawnResult({ success: true, code: 0, stdout: JSON.stringify({ segments: [] }) }),
    );
    await runAsrTranscription({ mediaPath: "/w/clip.mp4", python: "python", spawn });
    const [, args] = spawn.mock.calls[0];
    expect(args).not.toContain("--initial-prompt");
  });

  it("surfaces a helper failure as an error result, never a throw", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValue(spawnResult({ stderr: "faster-whisper not importable: boom", code: 3 }));
    const result = await runAsrTranscription({
      mediaPath: "/w/clip.mp4",
      python: "python",
      spawn,
    });
    expect(result.success).toBe(false);
    expect(result.error).toContain("not importable");
  });

  it("rejects malformed helper output", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValue(spawnResult({ success: true, code: 0, stdout: "not json" }));
    const result = await runAsrTranscription({
      mediaPath: "/w/clip.mp4",
      python: "python",
      spawn,
    });
    expect(result.success).toBe(false);
    expect(result.error).toContain("not valid JSON");
  });
});
