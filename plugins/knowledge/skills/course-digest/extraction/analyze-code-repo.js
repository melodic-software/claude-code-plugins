/**
 * Course code repository analysis tool.
 *
 * Clones the course's companion GitHub repo (shallow), analyzes its structure,
 * detects frameworks, and generates analysis metadata for the course digest.
 *
 * Usage:
 *   node analyze-code-repo.js --course-dir <path> [--verbose] [--quiet] [--skip-clone]
 *
 * Options:
 *   --course-dir    Path to directory containing course.json (required)
 *   --skip-clone    Skip cloning, analyze existing code/ directory
 *   --verbose       Show debug output
 *   --quiet         Show only warnings and errors
 */

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  countFiles,
  detectFrameworks,
  detectRepoStructure,
  diffSections,
  parseGitHubUrl,
} from "@melodic/repo-analysis";
import { createLogger } from "@melodic/video-digestion/shared/logger";

import { loadCourseDir, parseCliArgs, resolveLogLevel } from "./utils.js";

const args = parseCliArgs({
  "skip-clone": { type: "boolean", default: false },
});
const log = createLogger(resolveLogLevel(args));

const MAX_SIZE_KB = 500000;
const WARN_SIZE_KB = 100000;

function checkRepoSize(parsed) {
  const sizeResult = spawnSync(
    "gh",
    ["api", `repos/${parsed.owner}/${parsed.repo}`, "--jq", ".size"],
    {
      encoding: "utf-8",
      timeout: 15000,
    },
  );

  if (sizeResult.status !== 0 || !sizeResult.stdout.trim()) {
    log.warn(
      "  Could not check repo size (gh api failed). Proceeding with clone.",
    );
    log.debug(`  gh stderr: ${sizeResult.stderr?.trim()}`);
    return;
  }

  const sizeKB = Number.parseInt(sizeResult.stdout.trim(), 10);
  const sizeMB = Math.round(sizeKB / 1024);
  log.info(`  Repo size: ~${sizeMB} MB`);

  if (sizeKB > MAX_SIZE_KB) {
    log.error(
      `  Repo too large (${sizeMB} MB > ${MAX_SIZE_KB / 1024} MB limit). Aborting.`,
    );
    process.exit(1);
  }
  if (sizeKB > WARN_SIZE_KB) {
    log.warn(`  Large repo (${sizeMB} MB). Clone may take a while.`);
  }
}

function cloneRepoToTemp(parsed) {
  const cloneDir = join(tmpdir(), `course-repo-${parsed.repo}-${Date.now()}`);
  const githubUrl = `https://github.com/${parsed.owner}/${parsed.repo}`;
  log.info(`  Cloning to temp: ${cloneDir}`);

  const cloneResult = spawnSync(
    "git",
    ["clone", "--depth", "1", "--single-branch", "--", githubUrl, cloneDir],
    { encoding: "utf-8", timeout: 120000 },
  );

  if (cloneResult.status !== 0) {
    log.error(`  Clone failed: ${cloneResult.stderr?.trim()}`);
    process.exit(1);
  }
  log.info("  Clone complete.");
  return cloneDir;
}

function resolveCloneDir(parsed, courseDir) {
  if (args["skip-clone"]) {
    const codeOutputDir = join(courseDir, "code");
    if (!existsSync(codeOutputDir)) {
      log.error("  --skip-clone specified but code/ directory does not exist.");
      process.exit(1);
    }
    log.info("  Using existing code/ directory (--skip-clone).");
    return { cloneDir: codeOutputDir, isTemp: false };
  }

  checkRepoSize(parsed);
  return { cloneDir: cloneRepoToTemp(parsed), isTemp: true };
}

function buildReadme(githubUrl, structure, frameworks, fileCounts) {
  return [
    "# Course Code Repository",
    "",
    `**Source:** ${githubUrl}`,
    `**Cloned:** ${new Date().toISOString()}`,
    "**Method:** `git clone --depth 1 --single-branch`",
    "",
    "## Structure",
    "",
    `Type: **${structure.type}**`,
    structure.sections
      ? `Sections: ${structure.sections.map((s) => s.name).join(", ")}`
      : "",
    "",
    "## Frameworks",
    "",
    ...frameworks.map((fw) => `- **${fw.framework}**: \`${fw.file}\``),
    "",
    "## Files",
    "",
    `Total: ${fileCounts.total}`,
    "",
    "See `analysis.json` for full details.",
    "",
  ]
    .filter(Boolean)
    .join("\n");
}

function main() {
  const { courseDir, course } = loadCourseDir(args, { logger: log });
  const codeOutputDir = join(courseDir, "code");
  const githubUrl = course.resources?.githubUrl;

  log.info(`\n  ${course.title} — Code Repo Analysis`);
  log.debug(`  Node: ${process.version} | OS: ${process.platform}`);

  if (!githubUrl) {
    log.warn(
      "  No githubUrl in course.json resources — skipping code repo analysis.",
    );
    return;
  }

  log.info(`  GitHub: ${githubUrl}`);

  const parsed = parseGitHubUrl(githubUrl);
  if (!parsed) {
    log.error(`  Could not parse GitHub URL: ${githubUrl}`);
    process.exit(1);
  }

  const { cloneDir, isTemp } = resolveCloneDir(parsed, courseDir);

  log.info("  Analyzing structure...");
  const structure = detectRepoStructure(cloneDir);
  log.info(
    `  Structure: ${structure.type}${structure.sections ? ` (${structure.sections.length} sections)` : ""}`,
  );

  log.info("  Detecting frameworks...");
  const frameworks = detectFrameworks(cloneDir);
  for (const fw of frameworks) {
    log.info(`    ${fw.framework}: ${fw.file}`);
  }

  log.info("  Counting files...");
  const fileCounts = countFiles(cloneDir);
  log.info(`  Total files: ${fileCounts.total}`);
  log.debug(`  By extension: ${JSON.stringify(fileCounts.byExtension)}`);

  let sectionDiffs = [];
  if (structure.type === "per-section" && structure.sections.length >= 2) {
    log.info("  Computing section diffs...");
    sectionDiffs = diffSections(cloneDir, structure.sections);
    for (const d of sectionDiffs) {
      log.info(
        `    ${d.from} → ${d.to}: +${d.added} ~${d.modified} -${d.removed}`,
      );
    }
  }

  mkdirSync(codeOutputDir, { recursive: true });

  const analysis = {
    analyzedAt: new Date().toISOString(),
    githubUrl,
    owner: parsed.owner,
    repo: parsed.repo,
    structure: structure.type,
    sections: structure.sections ?? null,
    frameworks,
    fileCounts,
    sectionDiffs: sectionDiffs.length > 0 ? sectionDiffs : null,
  };

  const analysisPath = join(codeOutputDir, "analysis.json");
  writeFileSync(analysisPath, JSON.stringify(analysis, null, 2), "utf-8");
  writeFileSync(
    join(codeOutputDir, "README.md"),
    buildReadme(githubUrl, structure, frameworks, fileCounts),
    "utf-8",
  );

  if (isTemp && cloneDir.startsWith(tmpdir())) {
    log.debug(`  Cleaning up temp clone: ${cloneDir}`);
    rmSync(cloneDir, { recursive: true, force: true });
  }

  log.info("\n  ────────────────────────────────────────────");
  log.info(`  Analysis: ${analysisPath}`);
  log.info(`  README: ${join(codeOutputDir, "README.md")}\n`);
}

main();
