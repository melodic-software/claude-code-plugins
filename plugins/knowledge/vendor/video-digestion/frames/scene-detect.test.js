import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it } from "node:test";

import { extractSceneFrames } from "./scene-detect.js";

const silentLog = { info() {}, warn() {} };

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function makeOutputDir() {
  const dir = mkdtempSync(join(tmpdir(), "scene-detect-"));
  tempDirs.push(dir);
  return dir;
}

/**
 * Fake ffmpeg: writes `count` numbered PNG files for the output pattern it is given
 * and returns stderr carrying one showinfo line per frame time.
 *
 * @param {Record<string, { times: (number|string)[] }>} byPrefix
 */
function fakeFfmpeg(byPrefix) {
  /** @type {{ command: string, args: string[] }[]} */
  const calls = [];
  const spawn = async (/** @type {string} */ command, /** @type {string[]} */ args) => {
    calls.push({ command, args });
    const pattern = args.at(-1) ?? "";
    const prefix = Object.keys(byPrefix).find((key) => pattern.includes(`${key}_%04d.png`));
    const times = prefix ? byPrefix[prefix].times : [];
    times.forEach((_, i) => {
      writeFileSync(pattern.replace("%04d", String(i + 1).padStart(4, "0")), "");
    });
    const stderr = times
      .map(
        (time, n) =>
          `[Parsed_showinfo_1 @ 0x55d0] n:${String(n).padStart(4)} pts:${n * 1000} pts_time:${time} duration:1`,
      )
      .join("\n");
    return { success: true, code: 0, signal: null, stdout: "", stderr, timedOut: false };
  };
  return { spawn, calls };
}

describe("extractSceneFrames", () => {
  it("reads each scene frame's time from showinfo pts_time", async () => {
    const outputDir = makeOutputDir();
    const { spawn, calls } = fakeFfmpeg({ scene: { times: [12.5, 47.25] } });

    const result = await extractSceneFrames(
      "/videos/talk.mp4",
      outputDir,
      { minFramesForScene: 2 },
      { spawn, log: silentLog },
    );

    assert.deepEqual(
      result.frames.map((frame) => frame.timestampSec),
      [12.5, 47.25],
    );
    assert.deepEqual(
      result.frames.map((frame) => frame.timestampSource),
      ["scene-detection", "scene-detection"],
    );
    const args = calls[0].args;
    assert.ok(args.some((arg) => arg.includes("showinfo")));
    assert.equal(args[args.indexOf("-fps_mode") + 1], "vfr");
    assert.ok(!args.includes("-vsync"));
  });

  it("writes frame-times.json so a later run can reload the times", async () => {
    const outputDir = makeOutputDir();
    const { spawn } = fakeFfmpeg({ scene: { times: [12.5, 47.25] } });

    await extractSceneFrames(
      "/videos/talk.mp4",
      outputDir,
      { minFramesForScene: 2 },
      { spawn, log: silentLog },
    );

    const sidecar = JSON.parse(readFileSync(join(outputDir, "frame-times.json"), "utf8"));
    assert.deepEqual(sidecar["scene_0002.png"], {
      timestampSec: 47.25,
      timestampSource: "scene-detection",
    });
  });

  it("measures interval frames and estimates one whose pts_time is missing", async () => {
    const outputDir = makeOutputDir();
    const { spawn, calls } = fakeFfmpeg({
      scene: { times: [] },
      interval: { times: [0, 30, "NOPTS"] },
    });

    const result = await extractSceneFrames(
      "/videos/talk.mp4",
      outputDir,
      { intervalFps: "1/30" },
      { spawn, log: silentLog },
    );

    assert.equal(result.method, "hybrid");
    assert.deepEqual(
      result.frames.map(({ timestampSec, timestampSource }) => [timestampSec, timestampSource]),
      [
        [0, "interval"],
        [30, "interval"],
        [60, "estimated"],
      ],
    );
    assert.equal(result.frames[2].timestampMethod, "interval-index");
    assert.equal(result.frames[2].timestampErrorSec, 15);
    const intervalArgs = calls[1].args;
    assert.ok(intervalArgs.some((arg) => arg.includes("showinfo")));
    assert.equal(intervalArgs[intervalArgs.indexOf("-fps_mode") + 1], "vfr");
  });

  it("leaves a scene frame untimed when ffmpeg reported no time for it", async () => {
    const outputDir = makeOutputDir();
    const { spawn } = fakeFfmpeg({ scene: { times: [12.5, "NOPTS"] } });

    const result = await extractSceneFrames(
      "/videos/talk.mp4",
      outputDir,
      { minFramesForScene: 2 },
      { spawn, log: silentLog },
    );

    assert.equal(result.frames[1].timestampSec, null);
    assert.equal(result.frames[1].timestampSource, null);
  });

  it("probes nothing for a remote input: only ffmpeg is spawned", async () => {
    const outputDir = makeOutputDir();
    const { spawn, calls } = fakeFfmpeg({ scene: { times: [3, 9] } });

    const result = await extractSceneFrames(
      "https://cdn.example.com/course/lesson.m3u8",
      outputDir,
      { minFramesForScene: 2, referer: "https://course.example.com/" },
      { spawn, log: silentLog },
    );

    assert.deepEqual(
      result.frames.map((frame) => frame.timestampSec),
      [3, 9],
    );
    assert.deepEqual(
      calls.map((call) => call.command),
      ["ffmpeg"],
    );
  });
});
