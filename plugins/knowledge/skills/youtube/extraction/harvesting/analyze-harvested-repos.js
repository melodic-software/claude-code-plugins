/**
 * Shallow-clone GitHub URLs from source/harvested-links.json and write structure analysis.
 */

import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { detectFrameworks, detectRepoStructure, parseGitHubUrl } from "@melodic/repo-analysis";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @typedef {Object} HarvestedRepoAnalysis
 * @property {string} url
 * @property {string} owner
 * @property {string} repo
 * @property {ReturnType<typeof detectRepoStructure>} structure
 * @property {ReturnType<typeof detectFrameworks>} frameworks
 */

/**
 * @param {string} url
 * @param {string} destDir
 * @param {typeof spawn} [spawnFn]
 * @returns {Promise<boolean>}
 */
export async function shallowCloneGitHubRepo(url, destDir, spawnFn = spawn) {
  return new Promise((resolve) => {
    const child = spawnFn("git", ["clone", "--depth", "1", "--single-branch", url, destDir], {
      stdio: "ignore",
    });
    child.on("close", (code) => resolve(code === 0));
    child.on("error", () => resolve(false));
  });
}

/**
 * @param {Array<{ url: string }>} links
 * @returns {string[]}
 */
export function filterGitHubUrls(links) {
  const urls = [];
  for (const link of links) {
    if (parseGitHubUrl(link.url)) urls.push(link.url);
  }
  return [...new Set(urls)];
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
  const raw = await fs.readFile(harvestPath, "utf8");
  const links = JSON.parse(raw);
  const githubUrls = filterGitHubUrls(links);

  /** @type {HarvestedRepoAnalysis[]} */
  const analyses = [];
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-repo-analysis-"));

  try {
    for (const url of githubUrls) {
      const parsed = parseGitHubUrl(url);
      if (!parsed) continue;

      const cloneDir = path.join(tempRoot, `${parsed.owner}-${parsed.repo}`);
      const cloned = await clone(url, cloneDir);
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
    process.stderr.write("Usage: node harvesting/analyze-harvested-repos.js <slice-dir>\n");
    return 1;
  }

  const analyses = await analyzeHarvestedRepos(sliceDir);
  process.stdout.write(`${JSON.stringify({ count: analyses.length, analyses }, null, 2)}\n`);
  return 0;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  runAnalyzeHarvestedReposCli(process.argv)
    .then((code) => process.exit(code))
    .catch((err) => {
      process.stderr.write(`${err instanceof Error ? err.message : String(err)}\n`);
      process.exit(1);
    });
}
