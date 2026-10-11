import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const stdout = [];
const stderr = [];

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStdout: (...args) => stdout.push(args.join(" ")),
  writeStderr: (...args) => stderr.push(args.join(" ")),
}));

const { runResumeCli } = await import("./run-resume.js");
const { resolveWorkSliceDir } = await import("../transcript/derive-video-slug.js");
const { continuationPromptPath, createWatchState, markPhaseComplete, writeWatchState } =
  await import("./watch-state.js");

const SLUG = "talk-qyPCVqFUyDo";
const PHASES = ["acquire", "transcript", "watching", "vision", "harvest", "research", "synthesis"];

/** @type {string} */
let workRoot;
/** @type {string[]} */
let tempDirs;
const savedEnv = process.env.VIDEO_DIGEST_WORK_ROOT;

beforeEach(async () => {
  stdout.length = 0;
  stderr.length = 0;
  tempDirs = [];
  workRoot = await mkdtemp(path.join(os.tmpdir(), "run-resume-root-"));
  process.env.VIDEO_DIGEST_WORK_ROOT = workRoot;
});

afterEach(async () => {
  if (savedEnv === undefined) delete process.env.VIDEO_DIGEST_WORK_ROOT;
  else process.env.VIDEO_DIGEST_WORK_ROOT = savedEnv;
  for (const dir of [workRoot, ...tempDirs]) await rm(dir, { recursive: true, force: true });
});

/**
 * @param {{ completed: string[], status?: string, tempPresent: boolean }} opts
 * @returns {Promise<string>} slice dir
 */
async function seedSlice({ completed, status = "watching", tempPresent }) {
  const sliceDir = resolveWorkSliceDir(workRoot, SLUG);
  let state = createWatchState({
    videoId: "qyPCVqFUyDo",
    videoSlug: SLUG,
    sourceUrl: "https://www.youtube.com/watch?v=qyPCVqFUyDo",
    title: "Talk",
  });
  for (const phase of completed) state = markPhaseComplete(state, phase);
  let framesDir;
  let contactSheetsDir;
  if (tempPresent) {
    framesDir = await mkdtemp(path.join(os.tmpdir(), "run-resume-frames-"));
    contactSheetsDir = await mkdtemp(path.join(os.tmpdir(), "run-resume-sheets-"));
    tempDirs.push(framesDir, contactSheetsDir);
  } else {
    // Names never created: the reaped-temp case.
    framesDir = path.join(os.tmpdir(), `run-resume-gone-frames-${process.pid}-${Date.now()}`);
    contactSheetsDir = path.join(os.tmpdir(), `run-resume-gone-sheets-${process.pid}-${Date.now()}`);
  }
  state = { ...state, status, tempSession: { framesDir, contactSheetsDir } };
  await writeWatchState(sliceDir, state);
  return sliceDir;
}

const lastJson = () => JSON.parse(stdout.at(-1));

describe("runResumeCli on a complete slice", () => {
  it("reports nothing to resume and leaves the continuation prompt untouched", async () => {
    const sliceDir = await seedSlice({ completed: PHASES, status: "complete", tempPresent: false });
    const promptPath = continuationPromptPath(sliceDir);
    await mkdir(path.dirname(promptPath), { recursive: true });
    await writeFile(promptPath, "SENTINEL committed prompt\n", "utf8");

    const code = await runResumeCli(["node", "run-resume.js", SLUG]);

    expect(code).toBe(0);
    const out = lastJson();
    expect(out.status).toBe("complete");
    expect(out.nextPhase).toBeNull();
    expect(out.nothingToResume).toBe(true);
    expect(await readFile(promptPath, "utf8")).toBe("SENTINEL committed prompt\n");
  });
});

describe("runResumeCli temp-session check", () => {
  it("stops before vision when the recorded temp dirs are gone and says to re-run run-watch.js", async () => {
    const sliceDir = await seedSlice({
      completed: ["acquire", "transcript", "watching"],
      tempPresent: false,
    });

    const code = await runResumeCli(["node", "run-resume.js", SLUG]);

    expect(code).toBe(1);
    expect(stderr.join("\n")).toContain("run-watch.js");
    const out = lastJson();
    expect(out.nextPhase).toBe("vision");
    expect(out.tempSessionPresent).toBe(false);
    expect(existsSync(continuationPromptPath(sliceDir))).toBe(false);
  });

  it("resumes at vision when the temp dirs exist, with no absolute local path in the prompt", async () => {
    const sliceDir = await seedSlice({
      completed: ["acquire", "transcript", "watching"],
      tempPresent: true,
    });

    const code = await runResumeCli(["node", "run-resume.js", SLUG]);

    expect(code).toBe(0);
    const out = lastJson();
    expect(out.nextPhase).toBe("vision");
    expect(out.tempSessionPresent).toBe(true);
    const written = await readFile(continuationPromptPath(sliceDir), "utf8");
    expect(written).toContain("run-state/watch.json");
    expect(written).not.toContain(workRoot);
    expect(written).not.toContain(os.tmpdir());
  });
});

describe("runResumeCli slug validation", () => {
  it("rejects a slug that resolves outside the epic dir, writing nothing there", async () => {
    // `../escape/<slug>` from `.work/youtube-watch/` lands on `.work/escape/<slug>`,
    // inside this test's sandbox root, seeded with a real watch.json so only the
    // slug check can stop the write.
    const escapeDir = path.join(workRoot, ".work", "escape", SLUG);
    let state = createWatchState({
      videoId: "qyPCVqFUyDo",
      videoSlug: SLUG,
      sourceUrl: "https://www.youtube.com/watch?v=qyPCVqFUyDo",
      title: "Talk",
    });
    state = markPhaseComplete(state, "acquire");
    await writeWatchState(escapeDir, state);

    const code = await runResumeCli(["node", "run-resume.js", `../escape/${SLUG}`]);

    expect(code).toBe(1);
    expect(stdout).toEqual([]);
    expect(existsSync(continuationPromptPath(escapeDir))).toBe(false);
  });

  it("names the slug rule when rejecting separators and dot segments", async () => {
    for (const hostile of ["a/b", "a\\b", "..", ".", "a.b"]) {
      stdout.length = 0;
      stderr.length = 0;
      const code = await runResumeCli(["node", "run-resume.js", hostile]);
      expect(code, hostile).toBe(1);
      expect(stdout, hostile).toEqual([]);
      expect(stderr.join("\n"), hostile).toMatch(/Unsafe slice slug/);
    }
  });
});
