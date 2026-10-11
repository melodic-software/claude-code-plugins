/**
 * Shallow-clone GitHub URLs from source/harvested-links.json and write structure analysis.
 */

import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { detectFrameworks, detectRepoStructure, parseGitHubUrl } from "@melodic/repo-analysis";
import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @typedef {Object} HarvestedRepoAnalysis
 * @property {string} url
 * @property {string} owner
 * @property {string} repo
 * @property {ReturnType<typeof detectRepoStructure>} structure
 * @property {ReturnType<typeof detectFrameworks>} frameworks
 */

const CLONE_TIMEOUT_MS = 120_000;

/**
 * Shallow-clone an untrusted harvested URL so that a private, renamed or
 * LFS-heavy repository fails fast instead of prompting or downloading:
 * `credential.helper=` empties the helper list, an empty `GIT_ASKPASS` stops
 * git falling back to `core.askPass` or `SSH_ASKPASS` (which git consults
 * before `GIT_TERMINAL_PROMPT`), `GIT_TERMINAL_PROMPT=0` stops the terminal
 * prompt, `GIT_LFS_SKIP_SMUDGE=1` leaves LFS pointers in place,
 * and a clone that outlives the timeout is killed and counted as failed.
 *
 * @param {string} url
 * @param {string} destDir
 * @param {typeof spawn} [spawnFn]
 * @param {{ timeoutMs?: number }} [options]
 * @returns {Promise<boolean>}
 */
export async function shallowCloneGitHubRepo(
  url,
  destDir,
  spawnFn = spawn,
  { timeoutMs = CLONE_TIMEOUT_MS } = {},
) {
  return new Promise((resolve) => {
    const args = ["-c", "credential.helper=", "clone", "--depth", "1", "--single-branch"];
    const child = spawnFn("git", [...args, "--", url, destDir], {
      stdio: "ignore",
      timeout: timeoutMs,
      env: {
        ...process.env,
        GIT_ASKPASS: "",
        SSH_ASKPASS: "",
        GIT_TERMINAL_PROMPT: "0",
        GIT_LFS_SKIP_SMUDGE: "1",
      },
    });
    child.on("close", (code) => resolve(code === 0));
    child.on("error", () => resolve(false));
  });
}

/**
 * Sanitize an owner/repo segment for use as a filesystem path component.
 * GitHub disallows Windows-reserved chars (`: * ? " < > |`), but a crafted
 * deep link could smuggle them in and break `path.join`/`fs` on Windows.
 *
 * @param {string} segment
 * @returns {string}
 */
export function sanitizePathSegment(segment) {
  return segment.replace(/[^\w.-]/g, "_");
}

/**
 * @param {Array<{ url: string }>} links
 * @returns {string[]}
 */
export function filterGitHubUrls(links) {
  return [...new Set(links.filter((link) => parseGitHubUrl(link.url)).map((link) => link.url))];
}

/**
 * Analyze GitHub repositories referenced in harvested links.
 *
 * @param {string} sliceDir
 * @param {object} [deps]
 * @param {typeof shallowCloneGitHubRepo} [deps.clone]
 * @param {typeof detectRepoStructure} [deps.detectStructure]
 * @param {typeof detectFrameworks} [deps.detectFrameworksFn]
 * @returns {Promise<HarvestedRepoAnalysis[]>}
 */
export async function analyzeHarvestedRepos(
  sliceDir,
  {
    clone = shallowCloneGitHubRepo,
    detectStructure = detectRepoStructure,
    detectFrameworksFn = detectFrameworks,
  } = {},
) {
  const harvestPath = lanePath(sliceDir, LANES.source, "harvested-links.json");
  const links = JSON.parse(await fs.readFile(harvestPath, "utf8"));
  const githubUrls = filterGitHubUrls(links);

  /** @type {HarvestedRepoAnalysis[]} */
  const analyses = [];
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "video-repo-analysis-"));

  try {
    for (const url of githubUrls) {
      const parsed = parseGitHubUrl(url);
      if (!parsed) continue;

      const cloneDir = path.join(
        tempRoot,
        `${sanitizePathSegment(parsed.owner)}-${sanitizePathSegment(parsed.repo)}`,
      );
      // Clone the canonical repo URL, not the harvested deep link (e.g.
      // `.../blob/main/README.md`), which git cannot clone.
      const cloneUrl = `https://github.com/${parsed.owner}/${parsed.repo}`;
      const cloned = await clone(cloneUrl, cloneDir);
      if (!cloned) continue;

      analyses.push({
        url,
        owner: parsed.owner,
        repo: parsed.repo,
        structure: detectStructure(cloneDir),
        frameworks: detectFrameworksFn(cloneDir),
      });
    }
  } finally {
    await fs.rm(tempRoot, { recursive: true, force: true });
  }

  const outputPath = lanePath(sliceDir, LANES.source, "harvested-repo-analysis.json");
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, `${JSON.stringify(analyses, null, 2)}\n`, "utf8");

  return analyses;
}

/**
 * @param {string[]} argv
 * @returns {Promise<number>}
 */
export async function runAnalyzeHarvestedReposCli(argv) {
  const sliceDir = argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node harvesting/analyze-harvested-repos.js <slice-dir>");
    return 1;
  }

  const analyses = await analyzeHarvestedRepos(sliceDir);
  writeStdout(JSON.stringify({ count: analyses.length, analyses }, null, 2));
  return 0;
}

if (isMainModule(import.meta.url)) {
  runAnalyzeHarvestedReposCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      writeStderr(err instanceof Error ? err.message : String(err));
      process.exitCode = 1;
    });
}
