import { mkdtemp, readFile as realReadFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { describe, expect, it, vi } from "vitest";

import {
  buildContinuationPrompt,
  continuationPromptPath,
  createWatchState,
  findNextPhase,
  markPhaseComplete,
  readWatchState,
  runMarkPhase,
  watchStatePath,
  writeContinuationPrompt,
  writeWatchState,
} from "./watch-state.js";

const sampleTalk = () =>
  createWatchState({
    videoId: "abc",
    videoSlug: "talk-abc",
    sourceUrl: "https://youtube.com/watch?v=abc",
    title: "Talk",
  });

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
    const prompt = buildContinuationPrompt(state);
    expect(prompt).toContain("talk-abc");
    expect(prompt).toContain("transcript");
    expect(prompt).toContain("recommendations/");
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
    const prompt = buildContinuationPrompt(state);
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

describe("watch state persistence (resume scaffolding)", () => {
  it("round-trips watch.json via injected writeFile/readFile", async () => {
    const store = new Map();
    const writeFile = vi.fn(async (path, data) => {
      store.set(path, data);
    });
    const readFile = vi.fn(async (path) => {
      const value = store.get(path);
      if (value === undefined) throw new Error("ENOENT");
      return value;
    });

    const sliceDir = "/tmp/slice";
    const initial = sampleTalk();
    await writeWatchState(
      sliceDir,
      initial,
      writeFile,
      vi.fn(async () => {}),
    );
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
    const store = new Map();
    const writeFile = vi.fn(async (path, data) => {
      store.set(path, data);
    });

    let state = sampleTalk();
    state = markPhaseComplete(state, "acquire");
    state = markPhaseComplete(state, "transcript");
    state = markPhaseComplete(state, "watching", { selectedCount: 42 });

    const prompt = await writeContinuationPrompt(
      "/tmp/slice",
      state,
      writeFile,
      vi.fn(async () => {}),
    );
    expect(prompt).toContain("vision");
    expect(store.has(continuationPromptPath("/tmp/slice"))).toBe(true);
  });
});

describe("watch state temp-path tokenization", () => {
  function stateWithTempSession() {
    const framesDir = path.join(os.tmpdir(), "youtube-frames-abc");
    const contactSheetsDir = path.join(os.tmpdir(), "youtube-sheets-abc");
    let state = createWatchState({
      videoId: "abc",
      videoSlug: "talk-abc",
      sourceUrl: "https://youtube.com/watch?v=abc",
      title: "Talk",
    });
    state = {
      ...state,
      tempSession: {
        workDir: path.join(os.tmpdir(), "youtube-extraction-abc"),
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
    expect(persisted.tempSession.framesDir).toBe("{tmp}/youtube-frames-abc");
    expect(persisted.tempSession.contactSheetsDir).toBe("{tmp}/youtube-sheets-abc");
    expect(persisted.tempSession.workDir).toBe("{tmp}/youtube-extraction-abc");
    // In-memory state stays absolute — the pipeline writes frames there at runtime.
    expect(state.tempSession.framesDir).toBe(framesDir);
  });

  it("tokenizes temp paths embedded in the continuation prompt", () => {
    let { state, framesDir, contactSheetsDir } = stateWithTempSession();
    for (const phase of ["acquire", "transcript", "watching"]) {
      state = markPhaseComplete(state, phase);
    }

    const prompt = buildContinuationPrompt(state);
    expect(prompt).toContain("{tmp}/youtube-frames-abc");
    expect(prompt).toContain("{tmp}/youtube-sheets-abc");
    expect(prompt).not.toContain(framesDir);
    expect(prompt).not.toContain(contactSheetsDir);
  });
});

describe("mark-phase CLI (idempotent)", () => {
  function seededStore() {
    const sliceDir = "/tmp/slice";
    const state = createWatchState({
      videoId: "abc",
      videoSlug: "talk-abc",
      sourceUrl: "https://youtube.com/watch?v=abc",
      title: "Talk",
    });
    const store = new Map([[watchStatePath(sliceDir), `${JSON.stringify(state, null, 2)}\n`]]);
    const readFile = vi.fn(async (p) => {
      const value = store.get(p);
      if (value === undefined) throw new Error("ENOENT");
      return value;
    });
    const writeFile = vi.fn(async (p, data) => {
      store.set(p, data);
    });
    const mkdir = vi.fn(async () => {});
    return { sliceDir, store, readFile, writeFile, mkdir };
  }

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

describe("watch state persistence (real filesystem)", () => {
  it("creates the run-state lane dir when writing into a fresh slice", async () => {
    // Regression: a fresh slice has no run-state/ subdir; the live watch ENOENT'd on
    // run-state/watch.json because writeWatchState joined the lane path without mkdir.
    // Unit tests above inject a fake writeFile, so they never exercised real fs.
    const sliceDir = await mkdtemp(path.join(os.tmpdir(), "watch-state-"));
    try {
      const state = createWatchState({
        videoId: "abc",
        videoSlug: "talk-abc",
        sourceUrl: "https://youtube.com/watch?v=abc",
        title: "Talk",
      });
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
      let state = createWatchState({
        videoId: "abc",
        videoSlug: "talk-abc",
        sourceUrl: "https://youtube.com/watch?v=abc",
        title: "Talk",
      });
      state = markPhaseComplete(state, "acquire");
      await writeContinuationPrompt(sliceDir, state);
      const raw = await realReadFile(continuationPromptPath(sliceDir), "utf8");
      expect(raw).toContain("talk-abc");
    } finally {
      await rm(sliceDir, { recursive: true, force: true });
    }
  });
});
