/**
 * Phase-map state for interrupted `/video-digest watch` sessions.
 *
 * Mirrors course-digest `course.json` phase tracking — stored at
 * `.work/<watch-epic>/<video-slug>/watch.json`.
 */

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { normalizePortableTempPath, serializeTempSession } from "../lib/temp-session-paths.js";

/**
 * @typedef {Object} PhaseRecord
 * @property {string} completedAt - ISO-8601 timestamp
 * @property {Record<string, unknown>} [metrics]
 */

/**
 * @typedef {Object} WatchPhases
 * @property {PhaseRecord|null} acquire
 * @property {PhaseRecord|null} transcript
 * @property {PhaseRecord|null} watching
 * @property {PhaseRecord|null} vision
 * @property {PhaseRecord|null} harvest
 * @property {PhaseRecord|null} companion - optional Phase 0b digest of source/companion-sources.md
 * @property {PhaseRecord|null} research
 * @property {PhaseRecord|null} synthesis
 */

/**
 * @typedef {Object} WatchState
 * @property {string} videoId
 * @property {string} videoSlug
 * @property {string} sourceUrl
 * @property {string} title
 * @property {'pending'|'acquiring'|'watching'|'vision'|'researching'|'synthesizing'|'complete'} status
 * @property {WatchPhases} phases
 * @property {Record<string, unknown>} [sourceMetadata] - the envelope metadata's
 *   `source:`-prefixed subset (e.g. `source:snowflakeAliasing`), persisted so
 *   source-specific provenance survives the run; absent when the source set none
 * @property {string} [target] - the `--target <repo>` value resolved at watch start (SKILL.md
 *   "Synthesis target resolution"), a portable repo name/slug never an absolute local-checkout
 *   path. Persisted so an interrupted watch's `resume` recovers it instead of re-asking.
 * @property {boolean} [skipResearch] - user passed --skip-research; research phase is recorded as skipped
 * @property {object} [frameSelection]
 * @property {number} [frameSelection.selectedCount]
 * @property {number} [frameSelection.softCap]
 * @property {boolean} [frameSelection.overCap]
 * @property {number} [frameSelection.candidateCount]
 * @property {number} [frameSelection.targetMinFrames]
 * @property {boolean} [frameSelection.highVolume]
 * @property {object} [artifactPaths]
 * @property {string} [artifactPaths.selectionPath]
 * @property {string} [artifactPaths.coveragePlanPath]
 * @property {number} [artifactPaths.frameCount]
 * @property {number} [artifactPaths.contactSheetCount]
 * @property {object} [tempSession]
 * @property {string} [tempSession.workDir]
 * @property {string} [tempSession.framesDir]
 * @property {string} [tempSession.contactSheetsDir]
 * @property {string} [tempSession.acquiredAt]
 */

export const WATCH_STATE_FILENAME = "watch.json";
export const CONTINUATION_PROMPT_FILENAME = "continuation-prompt.md";

/**
 * Create an empty watch state for a new session.
 *
 * @param {object} meta
 * @param {string} meta.videoId
 * @param {string} meta.videoSlug
 * @param {string} meta.sourceUrl
 * @param {string} meta.title
 * @param {string} [meta.target] - explicit `--target <repo>` value, when the caller resolved
 *   one at watch start; omitted leaves `state.target` unset for the CLAUDE_PROJECT_DIR/ask rungs
 *   to resolve later (out of scope here — see "Synthesis target resolution" in SKILL.md).
 * @param {Record<string, unknown>} [meta.sourceMetadata] - `source:`-prefixed
 *   envelope metadata subset; persisted only when non-empty
 * @returns {WatchState}
 */
export function createWatchState({ videoId, videoSlug, sourceUrl, title, target, sourceMetadata }) {
  return {
    videoId,
    videoSlug,
    sourceUrl,
    title,
    ...(target ? { target } : {}),
    ...(sourceMetadata && Object.keys(sourceMetadata).length > 0 ? { sourceMetadata } : {}),
    status: "pending",
    phases: {
      acquire: null,
      transcript: null,
      watching: null,
      vision: null,
      harvest: null,
      companion: null,
      research: null,
      synthesis: null,
    },
  };
}

/**
 * Mark a phase complete with optional metrics.
 *
 * @param {WatchState} state
 * @param {keyof WatchPhases} phase
 * @param {Record<string, unknown>} [metrics]
 * @returns {WatchState}
 */
export function markPhaseComplete(state, phase, metrics = {}) {
  return {
    ...state,
    phases: {
      ...state.phases,
      [phase]: {
        completedAt: new Date().toISOString(),
        metrics,
      },
    },
  };
}

/**
 * Resolve the next incomplete phase name.
 *
 * @param {WatchPhases} phases
 * @returns {keyof WatchPhases|null}
 */
export function findNextPhase(phases) {
  const order = /** @type {(keyof WatchPhases)[]} */ ([
    "acquire",
    "transcript",
    "watching",
    "vision",
    "harvest",
    "research",
    "synthesis",
  ]);

  for (const phase of order) {
    if (phases[phase] === null) return phase;
  }
  return null;
}

/**
 * Build a continuation prompt for `/video-digest resume`.
 *
 * Prompt paths render from the resolved slice dir the caller already holds —
 * never re-derived from the epic-dir constant — so a non-default `--work-root`
 * always yields resumable paths (storage invariant A1 (4)).
 *
 * @param {WatchState} state
 * @param {string} sliceDir - resolved slice directory
 * @returns {string}
 */
export function buildContinuationPrompt(state, sliceDir) {
  const next = findNextPhase(state.phases);
  const completed = Object.entries(state.phases)
    .filter(([, value]) => value !== null)
    .map(([name, value]) =>
      /** @type {PhaseRecord} */ (value)?.metrics?.skipped ? `${name} (skipped)` : name,
    );

  return `# Continue /knowledge:video-digest watch — ${state.title}

Video slug: \`${state.videoSlug}\`
Source: ${state.sourceUrl}

## Completed phases

${completed.length > 0 ? completed.map((p) => `- ${p}`).join("\n") : "- (none yet)"}

## Next phase

**${next ?? "complete"}** — resume from \`${sliceDir}\` artifacts.

## Synthesis target

${state.target ? `Resolved: \`${state.target}\` — re-run SKILL.md "Synthesis target resolution" against this recorded name; do not re-ask.` : 'Not yet resolved — follow SKILL.md "Synthesis target resolution" when reaching synthesis.'}

## Frame selection

${state.frameSelection ? `- Selected: ${state.frameSelection.selectedCount ?? "?"} (target min ${state.frameSelection.targetMinFrames ?? "?"}${state.frameSelection.highVolume ? ", high volume — fan out vision subagents" : ""})` : "- Not yet computed"}

## Temp session

${state.tempSession ? `- Frames temp: \`${normalizePortableTempPath(state.tempSession.framesDir)}\`\n- Contact sheets temp: \`${normalizePortableTempPath(state.tempSession.contactSheetsDir)}\`\n- Re-run \`run-watch.js\` if temp paths are missing.` : "- Re-run CLI watch phase if temp artifacts expired"}

## Vision pipeline (one pass)

- Triage: one subagent per contact sheet → \`key-frames/triage/batches/sheet_NNN.json\` (agentic \`model\` on every sheet)
- Merge: \`merge-triage-json.js\` → \`validate-triage-json.js\` → \`render-triage-log.js\`
- Promote: agent writes \`key-frames/promotion-decisions.json\` from PNG reads → \`vision-gated-promote.js\`
- Audit: \`key-frame-quality-audit.json\` with honest pass/fail → delete failures
- Close: \`check-watch-outcomes.js --write-report\` must exit 0

## Instructions

1. Read \`${watchStatePath(sliceDir)}\` for phase markers
2. Read \`source/transcript.txt\` and the existing lane deliverables (\`research/\`, \`key-frames/\`, \`recommendations/\`)
3. Continue from the **${next ?? "synthesis"}** phase per SKILL.md watch protocol
4. Default-on research stage unless user passed \`--skip-research\`
5. Emit \`recommendations/\` hub (README + menu/takeaways/questions/interview) — no auto-implement, no auto-filed issues
`;
}

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function watchStatePath(sliceDir) {
  return lanePath(sliceDir, LANES.runState, WATCH_STATE_FILENAME);
}

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function continuationPromptPath(sliceDir) {
  return lanePath(sliceDir, LANES.runState, CONTINUATION_PROMPT_FILENAME);
}

/**
 * @param {string} sliceDir
 * @param {WatchState} state
 * @param {typeof fs.writeFile} [writeFile]
 */
export async function writeWatchState(sliceDir, state, writeFile = fs.writeFile, mkdir = fs.mkdir) {
  const persisted = state.tempSession
    ? { ...state, tempSession: serializeTempSession(state.tempSession) }
    : state;
  await mkdir(lanePath(sliceDir, LANES.runState), { recursive: true });
  await writeFile(watchStatePath(sliceDir), `${JSON.stringify(persisted, null, 2)}\n`, "utf8");
}

/**
 * @param {string} sliceDir
 * @param {typeof fs.readFile} [readFile]
 * @returns {Promise<WatchState|null>}
 */
export async function readWatchState(sliceDir, readFile = fs.readFile) {
  try {
    const raw = await readFile(watchStatePath(sliceDir), "utf8");
    return /** @type {WatchState} */ (JSON.parse(raw));
  } catch {
    return null;
  }
}

/**
 * @param {string} sliceDir
 * @param {WatchState} state
 * @param {typeof fs.writeFile} [writeFile]
 */
export async function writeContinuationPrompt(
  sliceDir,
  state,
  writeFile = fs.writeFile,
  mkdir = fs.mkdir,
) {
  const prompt = buildContinuationPrompt(state, sliceDir);
  await mkdir(lanePath(sliceDir, LANES.runState), { recursive: true });
  await writeFile(continuationPromptPath(sliceDir), prompt, "utf8");
  return prompt;
}

/**
 * Phases that may be marked via the CLI — guards against typo'd phase keys.
 * `companion` is an optional Phase 0b side-marker (not in the sequential
 * {@link findNextPhase} order): markable when `source/companion-sources.md`
 * exists, absent from the next-phase walk so a no-companion watch is unaffected.
 */
const MARKABLE_PHASES = /** @type {(keyof WatchPhases)[]} */ ([
  "acquire",
  "transcript",
  "watching",
  "vision",
  "harvest",
  "companion",
  "research",
  "synthesis",
]);

/**
 * Idempotently mark a phase complete in a persisted watch.json.
 *
 * Skips with a no-op when the phase is already recorded — the guard the
 * in-process `markPhaseComplete` lacks (it overwrites `completedAt` each call).
 * Verify-gated callers can re-invoke without clobbering an earlier timestamp.
 *
 * @param {string} sliceDir
 * @param {keyof WatchPhases} phase
 * @param {object} [io]
 * @param {typeof fs.readFile} [io.readFile]
 * @param {typeof fs.writeFile} [io.writeFile]
 * @param {typeof fs.mkdir} [io.mkdir]
 * @returns {Promise<number>} 0 on success or no-op skip, 1 on error
 */
export async function runMarkPhase(sliceDir, phase, { readFile, writeFile, mkdir } = {}) {
  if (!MARKABLE_PHASES.includes(phase)) {
    writeStderr(`mark-phase: unknown phase "${phase}" (expected ${MARKABLE_PHASES.join(", ")})\n`);
    return 1;
  }

  const state = await readWatchState(sliceDir, readFile);
  if (!state) {
    writeStderr(`mark-phase: no watch.json under ${sliceDir}\n`);
    return 1;
  }

  if (state.phases?.[phase]) {
    writeStdout(`mark-phase: ${phase} already marked — no-op\n`);
    return 0;
  }

  let next = markPhaseComplete(state, phase);
  // Marking the terminal phase closes the slice: flip status to "complete" so
  // validateWatchChecklistForCompleteSlice enforces the blocking checklist
  // (it skips unless status === "complete").
  if (phase === "synthesis") {
    next = { ...next, status: "complete" };
  }
  await writeWatchState(sliceDir, next, writeFile, mkdir);
  writeStdout(`mark-phase: ${phase} marked complete\n`);
  return 0;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const [command, sliceDir, phase] = process.argv.slice(2);
  if (command !== "mark-phase" || !sliceDir || !phase) {
    writeStderr("Usage: node watch/watch-state.js mark-phase <slice-dir> <phase>\n");
    process.exitCode = 2;
  } else {
    runMarkPhase(sliceDir, /** @type {keyof WatchPhases} */ (phase))
      .then((code) => {
        process.exitCode = code;
      })
      .catch((error) => {
        writeStderr(`${error instanceof Error ? error.message : String(error)}\n`);
        process.exitCode = 1;
      });
  }
}
