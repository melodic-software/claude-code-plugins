/**
 * A watch killed by SIGHUP, SIGINT or SIGTERM during acquisition removes the temp dirs it
 * made and exits with the conventional signal code. A real child run is used: a
 * fake `yt-dlp` on PATH blocks the acquisition so the signal lands mid-download.
 * POSIX only (the fake yt-dlp is a shell script).
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

const RUN_WATCH = fileURLToPath(new URL("./run-watch.js", import.meta.url));
const URL_UNDER_TEST = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
const TEMP_PREFIXES = ["video-extraction-", "video-frames-", "video-sheets-"];

/** @type {string} */
let sandbox;
/** @type {string} */
let fakeTmp;
/** @type {string} */
let started;

async function watchTempDirs() {
  const names = await fs.readdir(fakeTmp);
  return names.filter((name) => TEMP_PREFIXES.some((prefix) => name.startsWith(prefix)));
}

async function waitFor(predicate, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("timed out waiting for the child to reach acquisition");
}

describe.skipIf(process.platform === "win32")("run-watch interrupted by a signal", () => {
  beforeEach(async () => {
    sandbox = await fs.mkdtemp(path.join(os.tmpdir(), "watch-signal-"));
    fakeTmp = path.join(sandbox, "tmp");
    const bin = path.join(sandbox, "bin");
    started = path.join(sandbox, "yt-dlp-started");
    await fs.mkdir(fakeTmp);
    await fs.mkdir(bin);
    await fs.writeFile(
      path.join(bin, "yt-dlp"),
      // Keeps writing into the work dir, as a real download would, so a signal that
      // leaves it running races the cleanup and recreates files after the rm.
      `#!/bin/sh\ntouch "${started}"\nwhile :; do\n  for d in "$TMPDIR"/video-extraction-*; do\n    [ -d "$d" ] && echo x >> "$d/partial.part"\n  done\n  sleep 0.05\ndone\n`,
      { mode: 0o755 },
    );
  });

  afterEach(async () => {
    await fs.rm(sandbox, { recursive: true, force: true });
  });

  it.each([
    ["SIGTERM", 143],
    ["SIGINT", 130],
  ])("%s removes the temp dirs and exits %i", async (signal, exitCode) => {
    const child = spawn(process.execPath, [RUN_WATCH, URL_UNDER_TEST], {
      env: {
        ...process.env,
        PATH: `${path.join(sandbox, "bin")}${path.delimiter}${process.env.PATH}`,
        TMPDIR: fakeTmp,
        VIDEO_DIGEST_WORK_ROOT: path.join(sandbox, "work"),
      },
      stdio: "ignore",
    });
    const exited = new Promise((resolve) => child.on("exit", (code, sig) => resolve({ code, sig })));

    await waitFor(() => existsSync(started));
    expect(await watchTempDirs()).toHaveLength(3);

    child.kill(signal);
    expect(await exited).toEqual({ code: exitCode, sig: null });
    expect(await watchTempDirs()).toEqual([]);
    // A surviving fake yt-dlp would recreate the work dir's file within one tick.
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(await watchTempDirs()).toEqual([]);
  });

  it.each([
    ["SIGTERM", 143],
    ["SIGHUP", 129],
  ])("%s also ends a grandchild the yt-dlp child started", async (signal, exitCode) => {
    const grandPid = path.join(sandbox, "grandchild.pid");
    // A real yt-dlp runs ffmpeg as its own child; this one leaves a writer looping
    // in the background, which outlives a SIGKILL sent to yt-dlp alone.
    await fs.writeFile(
      path.join(sandbox, "bin", "yt-dlp"),
      `#!/bin/sh\n( while :; do\n  for d in "$TMPDIR"/video-extraction-*; do\n    [ -d "$d" ] && echo x >> "$d/merge.part"\n  done\n  sleep 0.05\ndone ) &\necho $! > "${grandPid}"\ntouch "${started}"\nwait\n`,
      { mode: 0o755 },
    );
    const child = spawn(process.execPath, [RUN_WATCH, URL_UNDER_TEST], {
      env: {
        ...process.env,
        PATH: `${path.join(sandbox, "bin")}${path.delimiter}${process.env.PATH}`,
        TMPDIR: fakeTmp,
        VIDEO_DIGEST_WORK_ROOT: path.join(sandbox, "work"),
      },
      stdio: "ignore",
    });
    const exited = new Promise((resolve) => child.on("exit", (code, sig) => resolve({ code, sig })));

    await waitFor(() => existsSync(started));
    const pid = Number(await fs.readFile(grandPid, "utf8"));
    const alive = () => {
      try {
        process.kill(pid, 0);
        return true;
      } catch {
        return false;
      }
    };
    try {
      child.kill(signal);
      expect(await exited).toEqual({ code: exitCode, sig: null });
      await waitFor(() => !alive(), 2_000).catch(() => {});
      expect(alive()).toBe(false);
      await new Promise((resolve) => setTimeout(resolve, 300));
      expect(await watchTempDirs()).toEqual([]);
    } finally {
      if (alive()) process.kill(pid, "SIGKILL");
    }
    // A surviving grandchild holds yt-dlp's pipes open, so the run waits out its
    // settle window before exiting; the timeout leaves room for that failure.
  }, 30_000);
});
