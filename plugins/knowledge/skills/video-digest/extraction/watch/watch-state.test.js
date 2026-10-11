import { existsSync, symlinkSync, writeFileSync } from "node:fs";
import { mkdir, mkdtemp, readFile as realReadFile, rm, writeFile } from "node:fs/promises";
import fsPromises from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { describe, expect, it, vi } from "vitest";

import { checkWatchOutcomes } from "../evals/check-watch-outcomes.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import {
  buildContinuationPrompt,
  computeVisionMetrics,
  continuationPromptPath,
  createWatchState,
  findNextPhase,
  markPhaseComplete,
  readWatchState,
  runClose,
  runMarkPhase,
  watchStatePath,
  writeContinuationPrompt,
  writeWatchState,
} from "./watch-state.js";

/** @param {Partial<Parameters<typeof createWatchState>[0]>} [overrides] */
const sampleTalk = (overrides = {}) =>
  createWatchState({
    videoId: "abc",
    videoSlug: "talk-abc",
    sourceUrl: "https://youtube.com/watch?v=abc",
    title: "Talk",
    ...overrides,
  });

// Resolved slice dir passed to the prompt builder — deliberately free of the
// epic-dir literal so the prompt tests prove paths come from the caller's
// resolved dir, not from the storage constant.
const SLICE_DIR = path.join("/custom-root", ".work", "any-epic", "talk-abc");

// In-memory fs fakes: a Map-backed readFile/writeFile/mkdir triple, optionally
// pre-seeded so a test can read a watch.json it never wrote.
/** @param {Iterable<[string, string]>} [seed] */
function memoryStore(seed = []) {
  const store = new Map(seed);
  const readFile = vi.fn(async (p) => {
    const value = store.get(p);
    if (value === undefined) throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
    return value;
  });
  const writeFile = vi.fn(async (p, data) => {
    store.set(p, data);
  });
  const mkdir = vi.fn(async () => {});
  return { store, readFile, writeFile, mkdir };
}

// Seeded with a fresh sample watch.json, for runMarkPhase tests.
function seededStore() {
  const sliceDir = "/tmp/slice";
  return {
    sliceDir,
    ...memoryStore([[watchStatePath(sliceDir), `${JSON.stringify(sampleTalk(), null, 2)}\n`]]),
  };
}

describe("watch state phase map", () => {
  it("creates empty phase map", () => {
    const state = sampleTalk();
    expect(state.phases.acquire).toBeNull();
    expect(findNextPhase(state.phases)).toBe("acquire");
  });

  it("advances to next incomplete phase", () => {
    let state = sampleTalk();
    state = markPhaseComplete(state, "acquire", { mode: "full" });
    state = markPhaseComplete(state, "transcript", { paragraphCount: 12 });
    expect(findNextPhase(state.phases)).toBe("watching");
  });

  it("builds continuation prompt with next phase", () => {
    let state = sampleTalk();
    state = markPhaseComplete(state, "acquire");
    const prompt = buildContinuationPrompt(state, SLICE_DIR);
    expect(prompt).toContain("talk-abc");
    expect(prompt).toContain("transcript");
    expect(prompt).toContain("recommendations/");
  });

  it("renders resume paths from the resolved slice dir, never the epic constant", () => {
    let state = createWatchState({
      videoId: "1001551417340022785",
      videoSlug: "post-1001551623938805763",
      sourceUrl: "https://x.com/lispower1/status/1001551623938805763",
      title: "Post",
    });
    state = markPhaseComplete(state, "acquire");
    const sliceDir = path.join("/custom-root", ".work", "any-epic", "post-1001551623938805763");
    const prompt = buildContinuationPrompt(state, sliceDir);
    expect(prompt).toContain(sliceDir);
    expect(prompt).toContain(watchStatePath(sliceDir));
    expect(prompt).not.toContain("youtube-watch");
  });

  it("emits the renamed /knowledge:video-digest command in the resume prompt", () => {
    const prompt = buildContinuationPrompt(sampleTalk(), SLICE_DIR);
    expect(prompt).toContain("# Continue /knowledge:video-digest watch");
    expect(prompt).not.toContain("youtube-digest");
  });

  it("surfaces high-volume frame selection in continuation prompt", () => {
    let state = sampleTalk();
    state = {
      ...state,
      frameSelection: { selectedCount: 180, targetMinFrames: 40, highVolume: true, overCap: false },
    };
    for (const phase of ["acquire", "transcript", "watching"]) {
      state = markPhaseComplete(state, phase);
    }
    const prompt = buildContinuationPrompt(state, SLICE_DIR);
    expect(prompt).toContain("high volume");
    expect(findNextPhase(state.phases)).toBe("vision");
  });

  it("resumes at vision after watching completes", () => {
    let state = createWatchState({
      videoId: "7zZy1QTvokM",
      videoSlug: "stop-prompting-claude-use-karpathy-s-met-7zZy1QTvokM",
      sourceUrl: "https://www.youtube.com/watch?v=7zZy1QTvokM",
      title: "Driver",
    });
    for (const phase of ["acquire", "transcript", "watching"]) {
      state = markPhaseComplete(state, phase);
    }
    expect(findNextPhase(state.phases)).toBe("vision");
  });
});

describe("synthesis target (resolved --target, resume recovery)", () => {
  it("omits target when none was resolved at watch start", () => {
    const state = sampleTalk();
    expect(state.target).toBeUndefined();
    expect(JSON.stringify(state)).not.toContain('"target"');
  });

  it("persists an explicit --target on the created state", () => {
    const state = sampleTalk({ target: "melodic-software/claude-code-plugins" });
    expect(state.target).toBe("melodic-software/claude-code-plugins");
  });

  it("tells a resumed session to reuse the recorded target instead of re-asking", () => {
    let state = sampleTalk({ target: "acme/webapp" });
    state = markPhaseComplete(state, "acquire");
    const prompt = buildContinuationPrompt(state, SLICE_DIR);
    expect(prompt).toContain("Resolved: `acme/webapp`");
    expect(prompt).toContain("do not re-ask");
  });

  it("tells a resumed session to resolve the target when none was recorded", () => {
    let state = sampleTalk();
    state = markPhaseComplete(state, "acquire");
    const prompt = buildContinuationPrompt(state, SLICE_DIR);
    expect(prompt).toContain("Not yet resolved");
  });

  it("round-trips target through writeWatchState/readWatchState", async () => {
    const { readFile, writeFile, mkdir } = memoryStore();
    const sliceDir = "/tmp/slice";
    const initial = sampleTalk({ target: "acme/webapp" });
    await writeWatchState(sliceDir, initial, writeFile, mkdir);
    const loaded = await readWatchState(sliceDir, readFile);
    expect(loaded?.target).toBe("acme/webapp");
  });
});

describe("source metadata persistence (source:* envelope subset)", () => {
  it("persists a flagged snowflake aliasing to disk", async () => {
    const { writeFile, readFile, mkdir } = memoryStore();
    const aliasing = { deltaMs: 4_000_000, suspectedKind: "quote-or-retweet" };
    const initial = createWatchState({
      videoId: "1001551417340022785",
      videoSlug: "post-1001551623938805763",
      sourceUrl: "https://x.com/lispower1/status/1001551623938805763",
      title: "Post",
      sourceMetadata: {
        "source:displayId": "1001551623938805763",
        "source:snowflakeAliasing": aliasing,
      },
    });
    await writeWatchState("/tmp/slice", initial, writeFile, mkdir);
    const loaded = await readWatchState("/tmp/slice", readFile);
    expect(loaded?.sourceMetadata?.["source:snowflakeAliasing"]).toEqual(aliasing);
    expect(loaded?.sourceMetadata?.["source:displayId"]).toBe("1001551623938805763");
  });

  it("writes no sourceMetadata key for an unflagged run", async () => {
    const { writeFile, readFile, mkdir } = memoryStore();
    const initial = sampleTalk({ sourceMetadata: {} });
    expect(JSON.stringify(initial)).not.toContain('"sourceMetadata"');
    await writeWatchState("/tmp/slice", initial, writeFile, mkdir);
    const loaded = await readWatchState("/tmp/slice", readFile);
    expect(loaded && "sourceMetadata" in loaded).toBe(false);
  });
});

describe("watch state persistence (resume scaffolding)", () => {
  it("round-trips watch.json via injected writeFile/readFile", async () => {
    const { readFile, writeFile, mkdir } = memoryStore();
    const sliceDir = "/tmp/slice";
    const initial = sampleTalk();
    await writeWatchState(sliceDir, initial, writeFile, mkdir);
    const loaded = await readWatchState(sliceDir, readFile);
    expect(loaded?.videoSlug).toBe("talk-abc");
    expect(writeFile).toHaveBeenCalledWith(
      watchStatePath(sliceDir),
      expect.stringContaining('"videoSlug": "talk-abc"'),
      "utf8",
    );
  });

  it("returns null when watch.json is missing", async () => {
    const readFile = vi.fn(async () => {
      throw new Error("ENOENT");
    });
    const loaded = await readWatchState("/tmp/missing", readFile);
    expect(loaded).toBeNull();
  });

  it("writes continuation-prompt.md from interrupted state", async () => {
    const { store, writeFile, mkdir } = memoryStore();

    let state = sampleTalk();
    state = markPhaseComplete(state, "acquire");
    state = markPhaseComplete(state, "transcript");
    state = markPhaseComplete(state, "watching", { selectedCount: 42 });

    const prompt = await writeContinuationPrompt("/tmp/slice", state, writeFile, mkdir);
    expect(prompt).toContain("vision");
    expect(store.has(continuationPromptPath("/tmp/slice"))).toBe(true);
  });
});

describe("watch state temp-path tokenization", () => {
  function stateWithTempSession() {
    const framesDir = path.join(os.tmpdir(), "video-frames-abc");
    const contactSheetsDir = path.join(os.tmpdir(), "video-sheets-abc");
    let state = sampleTalk();
    state = {
      ...state,
      tempSession: {
        workDir: path.join(os.tmpdir(), "video-extraction-abc"),
        framesDir,
        contactSheetsDir,
        acquiredAt: "2026-06-16T00:00:00.000Z",
      },
    };
    return { state, framesDir, contactSheetsDir };
  }

  it("tokenizes tempSession in persisted watch.json without mutating in-memory state", async () => {
    const { state, framesDir } = stateWithTempSession();

    let captured;
    const writeFile = vi.fn(async (_p, data) => {
      captured = data;
    });
    await writeWatchState(
      "/tmp/slice",
      state,
      writeFile,
      vi.fn(async () => {}),
    );

    const persisted = JSON.parse(captured);
    expect(persisted.tempSession.framesDir).toBe("{tmp}/video-frames-abc");
    expect(persisted.tempSession.contactSheetsDir).toBe("{tmp}/video-sheets-abc");
    expect(persisted.tempSession.workDir).toBe("{tmp}/video-extraction-abc");
    // In-memory state stays absolute — the pipeline writes frames there at runtime.
    expect(state.tempSession.framesDir).toBe(framesDir);
  });

  it("tokenizes temp paths embedded in the continuation prompt", () => {
    let { state, framesDir, contactSheetsDir } = stateWithTempSession();
    for (const phase of ["acquire", "transcript", "watching"]) {
      state = markPhaseComplete(state, phase);
    }

    const prompt = buildContinuationPrompt(state, SLICE_DIR);
    expect(prompt).toContain("{tmp}/video-frames-abc");
    expect(prompt).toContain("{tmp}/video-sheets-abc");
    expect(prompt).not.toContain(framesDir);
    expect(prompt).not.toContain(contactSheetsDir);
  });
});

describe("mark-phase CLI (idempotent)", () => {
  it("marks an unset phase complete", async () => {
    const { sliceDir, store, readFile, writeFile, mkdir } = seededStore();
    const code = await runMarkPhase(sliceDir, "research", { readFile, writeFile, mkdir });
    expect(code).toBe(0);
    const persisted = JSON.parse(store.get(watchStatePath(sliceDir)));
    expect(persisted.phases.research).not.toBeNull();
    expect(persisted.phases.research.completedAt).toBeDefined();
  });

  it("is a no-op on the second call for an already-marked phase", async () => {
    const { sliceDir, readFile, writeFile, mkdir } = seededStore();
    const first = await runMarkPhase(sliceDir, "research", { readFile, writeFile, mkdir });
    const second = await runMarkPhase(sliceDir, "research", { readFile, writeFile, mkdir });
    expect(first).toBe(0);
    expect(second).toBe(0);
    // The second invocation must not overwrite completedAt — proven by writeFile
    // firing exactly once across both calls (timestamp equality would be flaky).
    expect(writeFile).toHaveBeenCalledTimes(1);
  });

  it("rejects an unknown phase without writing", async () => {
    const { sliceDir, readFile, writeFile } = seededStore();
    const code = await runMarkPhase(sliceDir, "bogus", { readFile, writeFile });
    expect(code).toBe(1);
    expect(writeFile).not.toHaveBeenCalled();
  });

  it("returns 1 when watch.json is missing", async () => {
    const readFile = vi.fn(async () => {
      throw new Error("ENOENT");
    });
    const writeFile = vi.fn();
    const code = await runMarkPhase("/tmp/missing", "research", { readFile, writeFile });
    expect(code).toBe(1);
    expect(writeFile).not.toHaveBeenCalled();
  });
});

describe("companion phase (optional side-marker)", () => {
  it("accepts mark-phase companion", async () => {
    const { sliceDir, store, readFile, writeFile, mkdir } = seededStore();
    const code = await runMarkPhase(sliceDir, "companion", { readFile, writeFile, mkdir });
    expect(code).toBe(0);
    const persisted = JSON.parse(store.get(watchStatePath(sliceDir)));
    expect(persisted.phases.companion).not.toBeNull();
  });

  it("does not appear in the sequential next-phase walk", () => {
    let state = sampleTalk();
    // A no-companion watch that completed acquire..harvest must advance to research,
    // never stall on an unmarked optional companion slot.
    for (const phase of ["acquire", "transcript", "watching", "vision", "harvest"]) {
      state = markPhaseComplete(state, phase);
    }
    expect(state.phases.companion).toBeNull();
    expect(findNextPhase(state.phases)).toBe("research");
  });
});

describe("closing the slice (close, and mark-phase synthesis)", () => {
  const sliceDir = "/tmp/slice";

  /** @param {{ synthesisMarked?: boolean }} [options] */
  function closingStore({ synthesisMarked = false } = {}) {
    let state = { ...sampleTalk(), status: "synthesizing" };
    for (const phase of ["acquire", "transcript", "watching", "vision", "harvest", "research"]) {
      state = markPhaseComplete(state, phase);
    }
    if (synthesisMarked) state = markPhaseComplete(state, "synthesis");
    return memoryStore([[watchStatePath(sliceDir), `${JSON.stringify(state, null, 2)}\n`]]);
  }

  /**
   * Outcome-check double that records the watch.json it saw on disk when it ran.
   *
   * @param {Map<string, string>} store
   * @param {number} exitCode
   */
  function outcomeCheck(store, exitCode) {
    /** @type {{ status: string, synthesisMarked: boolean }[]} */
    const seen = [];
    const verifyOutcomes = vi.fn(async () => {
      const onDisk = JSON.parse(store.get(watchStatePath(sliceDir)));
      seen.push({ status: onDisk.status, synthesisMarked: Boolean(onDisk.phases.synthesis) });
      return exitCode;
    });
    return { verifyOutcomes, seen };
  }

  /** @param {Map<string, string>} store */
  const persisted = (store) => JSON.parse(store.get(watchStatePath(sliceDir)));

  it("marking synthesis runs the close checks: complete on a pass", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    const { verifyOutcomes, seen } = outcomeCheck(store, 0);

    const code = await runMarkPhase(sliceDir, "synthesis", {
      readFile,
      writeFile,
      mkdir,
      verifyOutcomes,
    });

    expect(code).toBe(0);
    expect(seen).toEqual([{ status: "synthesizing", synthesisMarked: true }]);
    expect(persisted(store).status).toBe("complete");
  });

  it("marking synthesis leaves status unchanged and exits non-zero when the checks fail", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    const { verifyOutcomes } = outcomeCheck(store, 1);

    const code = await runMarkPhase(sliceDir, "synthesis", {
      readFile,
      writeFile,
      mkdir,
      verifyOutcomes,
    });

    expect(code).toBe(1);
    expect(persisted(store).status).toBe("synthesizing");
    expect(persisted(store).phases.synthesis).not.toBeNull();
  });

  it("close writes complete only after the checks pass", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    const { verifyOutcomes, seen } = outcomeCheck(store, 0);

    const code = await runClose(sliceDir, { readFile, writeFile, mkdir, verifyOutcomes });

    expect(code).toBe(0);
    expect(seen).toEqual([{ status: "synthesizing", synthesisMarked: true }]);
    expect(persisted(store).status).toBe("complete");
  });

  it("close leaves status unchanged and exits 1 when the checks fail", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    const { verifyOutcomes } = outcomeCheck(store, 1);

    const code = await runClose(sliceDir, { readFile, writeFile, mkdir, verifyOutcomes });

    expect(code).toBe(1);
    expect(persisted(store).status).toBe("synthesizing");
  });

  it("close completes a slice whose synthesis was already marked", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore({ synthesisMarked: true });
    const markedAt = persisted(store).phases.synthesis.completedAt;
    const { verifyOutcomes } = outcomeCheck(store, 0);

    const code = await runClose(sliceDir, { readFile, writeFile, mkdir, verifyOutcomes });

    expect(code).toBe(0);
    expect(verifyOutcomes).toHaveBeenCalledTimes(1);
    expect(persisted(store).status).toBe("complete");
    expect(persisted(store).phases.synthesis.completedAt).toBe(markedAt);
  });

  it("re-running mark-phase synthesis after a failed close retries the close", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore({ synthesisMarked: true });
    const { verifyOutcomes } = outcomeCheck(store, 0);

    const code = await runMarkPhase(sliceDir, "synthesis", {
      readFile,
      writeFile,
      mkdir,
      verifyOutcomes,
    });

    expect(code).toBe(0);
    expect(persisted(store).status).toBe("complete");
  });

  const readmePath = path.join(sliceDir, "README.md");
  const readmeAt = (/** @type {string} */ status) =>
    `---\r\nstatus: ${status}\r\ncreated: 2026-10-01T00:00:00Z\r\nupdated: 2026-10-02T00:00:00Z\r\n---\r\n\r\n# Talk\r\n\r\nstatus: in-progress\r\n`;

  it("close sets the README frontmatter status to complete and changes nothing else", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    store.set(readmePath, readmeAt("in-progress"));
    const { verifyOutcomes } = outcomeCheck(store, 0);

    const code = await runClose(sliceDir, { readFile, writeFile, mkdir, verifyOutcomes });

    expect(code).toBe(0);
    expect(store.get(readmePath)).toBe(readmeAt("complete"));
  });

  it("re-running close on a complete slice repairs a README left in-progress", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore({ synthesisMarked: true });
    store.set(
      watchStatePath(sliceDir),
      `${JSON.stringify({ ...persisted(store), status: "complete" }, null, 2)}\n`,
    );
    store.set(readmePath, readmeAt("in-progress"));
    const verifyOutcomes = vi.fn(async () => 0);

    const code = await runClose(sliceDir, { readFile, writeFile, mkdir, verifyOutcomes });

    expect(code).toBe(0);
    expect(verifyOutcomes).not.toHaveBeenCalled();
    expect(store.get(readmePath)).toBe(readmeAt("complete"));
  });

  it("close fails when the README exists but cannot be read", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    const { verifyOutcomes } = outcomeCheck(store, 0);
    const denied = Object.assign(new Error("EACCES"), { code: "EACCES" });
    const failingRead = vi.fn(async (/** @type {string} */ p, /** @type {any} */ enc) => {
      if (p === readmePath) throw denied;
      return readFile(p, enc);
    });

    await expect(
      runClose(sliceDir, { readFile: failingRead, writeFile, mkdir, verifyOutcomes }),
    ).rejects.toBe(denied);
    expect(persisted(store).status).not.toBe("complete");
  });

  it("a failed close leaves the README status in-progress", async () => {
    const { store, readFile, writeFile, mkdir } = closingStore();
    store.set(readmePath, readmeAt("in-progress"));
    const { verifyOutcomes } = outcomeCheck(store, 1);

    const code = await runClose(sliceDir, { readFile, writeFile, mkdir, verifyOutcomes });

    expect(code).toBe(1);
    expect(store.get(readmePath)).toBe(readmeAt("in-progress"));
  });

  it("close returns 1 without running the checks when watch.json is missing", async () => {
    const { readFile, writeFile } = memoryStore();
    const verifyOutcomes = vi.fn(async () => 0);

    const code = await runClose(sliceDir, { readFile, writeFile, verifyOutcomes });

    expect(code).toBe(1);
    expect(verifyOutcomes).not.toHaveBeenCalled();
    expect(writeFile).not.toHaveBeenCalled();
  });
});

describe("skip-research phase map (resume routing)", () => {
  it("advances past research to synthesis when research is marked skipped", () => {
    let state = sampleTalk();
    for (const phase of ["acquire", "transcript", "watching", "vision", "harvest"]) {
      state = markPhaseComplete(state, phase);
    }
    state = markPhaseComplete(state, "research", { skipped: true });
    expect(findNextPhase(state.phases)).toBe("synthesis");
  });

  it("annotates a skipped research phase in the continuation prompt", () => {
    let state = { ...sampleTalk(), skipResearch: true };
    for (const phase of ["acquire", "transcript", "watching", "vision", "harvest"]) {
      state = markPhaseComplete(state, phase);
    }
    state = markPhaseComplete(state, "research", { skipped: true });
    expect(buildContinuationPrompt(state, SLICE_DIR)).toContain("research (skipped)");
  });
});

describe("mark-phase vision metrics", () => {
  it("records triage and promotion counts so vision-metrics-honesty appears", async () => {
    const sliceDir = await mkdtemp(path.join(os.tmpdir(), "watch-vision-"));
    try {
      const state = sampleTalk();
      state.artifactPaths = { contactSheetCount: 2 };
      state.status = "vision";
      await writeWatchState(sliceDir, state);

      const triageDir = lanePath(sliceDir, LANES.keyFrames, "triage");
      await mkdir(triageDir, { recursive: true });
      const cells = [{ cell: "R1C1" }, { cell: "R1C2" }];
      await writeFile(
        path.join(triageDir, "manifest.json"),
        `${JSON.stringify({
          sheetCount: 2,
          sheets: [
            { sheetId: "sheet_001", cells },
            { sheetId: "sheet_002", cells: [{ cell: "R3C2" }] },
          ],
        })}\n`,
      );
      await writeFile(
        lanePath(sliceDir, LANES.keyFrames, "promotion-map.json"),
        `${JSON.stringify({
          "opening-slide.png": { sourceFile: "scene_0001.png" },
          "diagram.png": { sourceFile: "scene_0004.png" },
        })}\n`,
      );
      await writeFile(
        lanePath(sliceDir, LANES.keyFrames, "frame-triage-log.md"),
        "## sheet_001\n\n## sheet_002\n",
      );

      const code = await runMarkPhase(sliceDir, "vision");
      expect(code).toBe(0);

      const persisted = JSON.parse(await realReadFile(watchStatePath(sliceDir), "utf8"));
      expect(persisted.phases.vision.metrics.contactSheetsTriaged).toBe(2);
      expect(persisted.phases.vision.metrics.cellsTriaged).toBe(3);
      expect(persisted.phases.vision.metrics.promotedCount).toBe(2);
      expect(Object.keys(persisted.phases.vision.metrics).length).toBeGreaterThan(0);

      const honesty = checkWatchOutcomes(sliceDir).checks.find(
        (check) => check.id === "vision-metrics-honesty",
      );
      expect(honesty).toBeDefined();
      expect(honesty?.pass).toBe(true);
    } finally {
      await rm(sliceDir, { recursive: true, force: true });
    }
  });

  it("records numeric zeros when the triage manifest and promotion map are absent", () => {
    const metrics = computeVisionMetrics(path.join(os.tmpdir(), "watch-vision-missing"));
    expect(metrics).toEqual({ contactSheetsTriaged: 0, cellsTriaged: 0, promotedCount: 0 });
  });
});

/** A junction needs no Developer Mode or admin rights on Windows; a "dir" symlink does. */
const DIR_LINK_TYPE = process.platform === "win32" ? "junction" : "dir";

describe("close removes recorded tempSession directories", () => {
  /** @param {number} outcomeCode */
  async function closeWithTemps(outcomeCode) {
    const sliceDir = await mkdtemp(path.join(os.tmpdir(), "watch-close-slice-"));
    const workDir = await mkdtemp(path.join(os.tmpdir(), "video-extraction-"));
    const framesDir = await mkdtemp(path.join(os.tmpdir(), "video-frames-"));
    const sheetsDir = await mkdtemp(path.join(os.tmpdir(), "video-sheets-"));
    const leftover = await mkdtemp(path.join(os.tmpdir(), "video-extraction-leftover-"));
    let state = sampleTalk();
    for (const phase of ["acquire", "transcript", "watching", "vision", "harvest", "research"]) {
      state = markPhaseComplete(state, phase);
    }
    state.status = "synthesizing";
    state.tempSession = {
      workDir,
      framesDir,
      contactSheetsDir: sheetsDir,
      acquiredAt: "2026-10-03T00:00:00.000Z",
    };
    await writeWatchState(sliceDir, state);
    const code = await runClose(sliceDir, { verifyOutcomes: async () => outcomeCode });
    return { code, sliceDir, workDir, framesDir, sheetsDir, leftover };
  }

  it("deletes only the directories named in that slice's tempSession", async () => {
    const dirs = await closeWithTemps(0);
    try {
      expect(dirs.code).toBe(0);
      expect(existsSync(dirs.workDir)).toBe(false);
      expect(existsSync(dirs.framesDir)).toBe(false);
      expect(existsSync(dirs.sheetsDir)).toBe(false);
      expect(existsSync(dirs.leftover)).toBe(true);
      const persisted = JSON.parse(await realReadFile(watchStatePath(dirs.sliceDir), "utf8"));
      expect(persisted.status).toBe("complete");
    } finally {
      await rm(dirs.sliceDir, { recursive: true, force: true });
      await rm(dirs.workDir, { recursive: true, force: true });
      await rm(dirs.framesDir, { recursive: true, force: true });
      await rm(dirs.sheetsDir, { recursive: true, force: true });
      await rm(dirs.leftover, { recursive: true, force: true });
    }
  });

  it("completes and warns when a recorded directory cannot be removed", async () => {
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    const busyRm = vi.spyOn(fsPromises, "rm").mockImplementation(async (target, options) => {
      if (path.basename(String(target)).startsWith("video-extraction-")) {
        throw Object.assign(new Error("resource busy or locked"), { code: "EBUSY" });
      }
      return rm(target, options);
    });
    let dirs;
    let warnings = "";
    try {
      dirs = await closeWithTemps(0);
    } finally {
      warnings = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
      busyRm.mockRestore();
      stderr.mockRestore();
    }
    try {
      expect(dirs.code).toBe(0);
      const persisted = JSON.parse(await realReadFile(watchStatePath(dirs.sliceDir), "utf8"));
      expect(persisted.status).toBe("complete");
      expect(existsSync(dirs.workDir)).toBe(true);
      expect(existsSync(dirs.framesDir)).toBe(false);
      expect(existsSync(dirs.sheetsDir)).toBe(false);
      expect(warnings).toContain("could not remove temp dir");
      expect(warnings).toContain(path.basename(dirs.workDir));
      expect(warnings).toContain("EBUSY");
    } finally {
      await rm(dirs.sliceDir, { recursive: true, force: true });
      await rm(dirs.workDir, { recursive: true, force: true });
      await rm(dirs.framesDir, { recursive: true, force: true });
      await rm(dirs.sheetsDir, { recursive: true, force: true });
      await rm(dirs.leftover, { recursive: true, force: true });
    }
  });

  it("deletes the directory a recorded symlink resolves to", async () => {
    const sliceDir = await mkdtemp(path.join(os.tmpdir(), "watch-close-slice-"));
    const target = await mkdtemp(path.join(os.tmpdir(), "video-extraction-target-"));
    const framesDir = await mkdtemp(path.join(os.tmpdir(), "video-frames-"));
    const sheetsDir = await mkdtemp(path.join(os.tmpdir(), "video-sheets-"));
    const link = path.join(os.tmpdir(), `video-extraction-link-${path.basename(target)}`);
    writeFileSync(path.join(target, "keep.txt"), "x");
    symlinkSync(target, link, DIR_LINK_TYPE);
    let state = sampleTalk();
    for (const phase of ["acquire", "transcript", "watching", "vision", "harvest", "research"]) {
      state = markPhaseComplete(state, phase);
    }
    state.status = "synthesizing";
    state.tempSession = {
      workDir: link,
      framesDir,
      contactSheetsDir: sheetsDir,
      acquiredAt: "2026-10-03T00:00:00.000Z",
    };
    await writeWatchState(sliceDir, state);
    try {
      expect(await runClose(sliceDir, { verifyOutcomes: async () => 0 })).toBe(0);
      expect(existsSync(target)).toBe(false);
      expect(existsSync(path.join(target, "keep.txt"))).toBe(false);
    } finally {
      await rm(sliceDir, { recursive: true, force: true });
      await rm(target, { recursive: true, force: true });
      await rm(link, { recursive: true, force: true });
      await rm(framesDir, { recursive: true, force: true });
      await rm(sheetsDir, { recursive: true, force: true });
    }
  });

  it("keeps a directory outside the OS temp dir that a recorded symlink points to", async () => {
    const outer = await mkdtemp(path.join(os.tmpdir(), "watch-close-root-"));
    const fakeTmp = path.join(outer, "tmp");
    const outside = path.join(outer, "outside");
    await mkdir(fakeTmp);
    await mkdir(outside);
    writeFileSync(path.join(outside, "keep.txt"), "x");
    const link = path.join(fakeTmp, "video-extraction-link");
    symlinkSync(outside, link, DIR_LINK_TYPE);
    const framesDir = path.join(fakeTmp, "video-frames-abc");
    await mkdir(framesDir);
    const savedEnv = { TMPDIR: process.env.TMPDIR, TEMP: process.env.TEMP, TMP: process.env.TMP };
    process.env.TMPDIR = fakeTmp;
    process.env.TEMP = fakeTmp;
    process.env.TMP = fakeTmp;
    try {
      const sliceDir = path.join(outer, "slice");
      let state = sampleTalk();
      for (const phase of ["acquire", "transcript", "watching", "vision", "harvest", "research"]) {
        state = markPhaseComplete(state, phase);
      }
      state.status = "synthesizing";
      state.tempSession = { workDir: link, framesDir, acquiredAt: "2026-10-03T00:00:00.000Z" };
      await writeWatchState(sliceDir, state);
      expect(await runClose(sliceDir, { verifyOutcomes: async () => 0 })).toBe(0);
      expect(existsSync(path.join(outside, "keep.txt"))).toBe(true);
      expect(existsSync(framesDir)).toBe(false);
    } finally {
      for (const [key, value] of Object.entries(savedEnv)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
      await rm(outer, { recursive: true, force: true });
    }
  });

  it("leaves tempSession directories in place when the outcome checks fail", async () => {
    const dirs = await closeWithTemps(1);
    try {
      expect(dirs.code).toBe(1);
      expect(existsSync(dirs.workDir)).toBe(true);
      expect(existsSync(dirs.framesDir)).toBe(true);
      expect(existsSync(dirs.sheetsDir)).toBe(true);
      expect(existsSync(dirs.leftover)).toBe(true);
      const persisted = JSON.parse(await realReadFile(watchStatePath(dirs.sliceDir), "utf8"));
      expect(persisted.status).not.toBe("complete");
    } finally {
      await rm(dirs.sliceDir, { recursive: true, force: true });
      await rm(dirs.workDir, { recursive: true, force: true });
      await rm(dirs.framesDir, { recursive: true, force: true });
      await rm(dirs.sheetsDir, { recursive: true, force: true });
      await rm(dirs.leftover, { recursive: true, force: true });
    }
  });
});

describe("watch state persistence (real filesystem)", () => {
  it("creates the run-state lane dir when writing into a fresh slice", async () => {
    // Regression: a fresh slice has no run-state/ subdir; the live watch ENOENT'd on
    // run-state/watch.json because writeWatchState joined the lane path without mkdir.
    // Unit tests above inject a fake writeFile, so they never exercised real fs.
    const sliceDir = await mkdtemp(path.join(os.tmpdir(), "watch-state-"));
    try {
      const state = sampleTalk();
      await writeWatchState(sliceDir, state);
      const raw = await realReadFile(watchStatePath(sliceDir), "utf8");
      expect(JSON.parse(raw).videoSlug).toBe("talk-abc");
    } finally {
      await rm(sliceDir, { recursive: true, force: true });
    }
  });

  it("creates the run-state lane dir when writing the continuation prompt", async () => {
    const sliceDir = await mkdtemp(path.join(os.tmpdir(), "watch-state-"));
    try {
      let state = sampleTalk();
      state = markPhaseComplete(state, "acquire");
      await writeContinuationPrompt(sliceDir, state);
      const raw = await realReadFile(continuationPromptPath(sliceDir), "utf8");
      expect(raw).toContain("talk-abc");
    } finally {
      await rm(sliceDir, { recursive: true, force: true });
    }
  });
});
