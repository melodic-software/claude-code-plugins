#!/usr/bin/env node
/**
 * Read-only readiness report for /knowledge:video-digest: one plain command, so the skill's
 * pre-computed context and a by-hand rerun are the same call. It probes the node dependencies
 * (in the data directory `--data-dir` names), yt-dlp, ffmpeg, ImageMagick and faster-whisper,
 * prints where setup-deps.mjs would install and how to relocate that, and always exits 0: a
 * missing prerequisite is reported, never a failure, so the report survives to be read.
 *
 * The data directory resolves like run.mjs resolves it (`resolvePluginData`); an unusable
 * value is reported as a line, not thrown.
 *
 * Usage: node preflight.mjs --data-dir <dir>
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

import { parseRunArgs, resolvePluginData } from "./lib/run-args.js";

/** First line of a tool's version output, or undefined when the tool did not run. */
function probe(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", timeout: 15000 });
  if (result.error || result.status !== 0) return undefined;
  return (result.stdout || result.stderr).split(/\r?\n/)[0].trim() || "found";
}

const lines = [];

let data;
let dataProblem;
try {
  const { dataDir } = parseRunArgs(process.argv.slice(2));
  data = resolvePluginData(dataDir, process.env);
} catch (error) {
  dataProblem = error.message;
}

if (dataProblem) {
  lines.push(`video-extraction deps: UNKNOWN - ${dataProblem}`);
} else if (!data) {
  lines.push(
    'video-extraction deps: UNKNOWN - the plugin data directory was not passed. Run this script with --data-dir "${CLAUDE_PLUGIN_DATA}" as the skill shows it.',
  );
} else {
  const installed = fs.existsSync(path.join(data, "node_modules", "@melodic", "video-digestion"));
  lines.push(
    installed
      ? "video-extraction deps: installed"
      : "video-extraction deps: MISSING - run setup-deps.mjs (see Prerequisites)",
  );
  lines.push(
    `install target: ${path.join(data, "node_modules")} (relocate by passing a different --data-dir to setup-deps.mjs and run.mjs)`,
  );
}

const ytDlp = probe("yt-dlp", ["--version"]);
lines.push(`yt-dlp: ${ytDlp ?? "MISSING - install yt-dlp (see Prerequisites)"}`);

const ffmpeg = probe("ffmpeg", ["-version"]);
lines.push(`ffmpeg: ${ffmpeg ?? "MISSING - install ffmpeg (watch action only)"}`);

const magick = probe("magick", ["-version"]);
lines.push(`ImageMagick: ${magick ?? "MISSING - install ImageMagick 7 (watch action only)"}`);

// Optional ASR rung: detected through whichever Python imports faster_whisper, never installed.
let whisper;
const configuredPython = process.env.CLAUDE_PLUGIN_OPTION_ASR_PYTHON?.trim();
for (const python of [...(configuredPython ? [configuredPython] : []), "python", "python3", "py"]) {
  if (probe(python, ["-c", "import faster_whisper"]) !== undefined) {
    whisper = python;
    break;
  }
}
lines.push(
  `faster-whisper: ${whisper ? `available (via ${whisper})` : "not found (optional; the asr transcript rung degrades)"}`,
);

process.stdout.write(`${lines.join("\n")}\n`);
