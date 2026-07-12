/**
 * Course code repository analysis functions.
 *
 * Pure functions for detecting repo structure, frameworks, and generating
 * section diffs. No side effects — cloning and file writing are in the
 * orchestrator (analyze-code-repo.js).
 */

import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { extname, join } from "node:path";

const GITHUB_HTTPS_PATH = /github\.com\/([^/]+)\/([^/]+)/;
const GITHUB_SSH_PATH = /github\.com:([^/]+)\/([^/]+)/;
const GIT_SUFFIX_PATTERN = /\.git$/;
const SECTION_DIR_PATTERN = /^(\d{2}-|section-\d+|chapter-?\d+|module-?\d+|part-?\d+|\d+\.\s)/;
const WINDOWS_PATH_SEPARATOR = /\\/g;

const IGNORED_DIRS = new Set([
  "node_modules",
  ".git",
  "bin",
  "obj",
  ".vs",
  ".vscode",
  ".idea",
  "__pycache__",
  ".venv",
  "dist",
  "build",
  "out",
  "coverage",
  ".next",
  ".nuxt",
]);

/**
 * Parse a GitHub URL into owner and repo.
 * Handles: https://github.com/owner/repo, https://github.com/owner/repo.git,
 * git@github.com:owner/repo.git
 *
 * @param {string} url
 * @returns {{ owner: string, repo: string } | null}
 */
export function parseGitHubUrl(url) {
  if (!url) return null;

  const httpsMatch = url.match(GITHUB_HTTPS_PATH);
  if (httpsMatch) {
    return { owner: httpsMatch[1], repo: httpsMatch[2].replace(GIT_SUFFIX_PATTERN, "") };
  }

  const sshMatch = url.match(GITHUB_SSH_PATH);
  if (sshMatch) {
    return { owner: sshMatch[1], repo: sshMatch[2].replace(GIT_SUFFIX_PATTERN, "") };
  }

  return null;
}

/**
 * Detect repo structure: per-section numbered folders or single-state.
 *
 * Per-section repos have top-level dirs matching common patterns:
 *   - /^\d{2}-/          (e.g., 01-intro/)
 *   - /^section-\d+/     (e.g., section-03/)  — Dometrain primary pattern
 *   - /^chapter-?\d+/    (e.g., chapter-01/, chapter1/)
 *   - /^module-?\d+/     (e.g., module-01/)
 *   - /^part-?\d+/       (e.g., part-1/)
 *   - /^\d+\.\s/         (e.g., "2. Async Await")  — Dometrain alternate
 * Some also have /start and /end subdirs within each section.
 *
 * @param {string} codeDir — root of the cloned repo
 * @returns {{ type: 'per-section' | 'single-state', sections?: Array<{ name: string, hasStart: boolean, hasEnd: boolean }> }}
 */
export function detectRepoStructure(codeDir) {
  const entries = readdirSync(codeDir, { withFileTypes: true }).filter(
    (e) => e.isDirectory() && !e.name.startsWith("."),
  );

  const numbered = entries
    .filter((e) => SECTION_DIR_PATTERN.test(e.name))
    .sort((a, b) => a.name.localeCompare(b.name));

  if (numbered.length < 2) {
    return { type: "single-state" };
  }

  const sections = numbered.map((e) => {
    const sectionPath = join(codeDir, e.name);
    return {
      name: e.name,
      hasStart: existsSync(join(sectionPath, "start")),
      hasEnd: existsSync(join(sectionPath, "end")),
    };
  });

  return { type: "per-section", sections };
}

/**
 * Detect frameworks/languages from manifest files.
 *
 * @param {string} dir — directory to scan (recursive up to 6 levels)
 * @returns {Array<{ framework: string, file: string, details: object }>}
 */
export function detectFrameworks(dir) {
  const manifests = {
    "package.json": "node",
    ".csproj": "dotnet",
    "requirements.txt": "python",
    "pyproject.toml": "python",
    "pom.xml": "java",
    "build.gradle": "java",
    "go.mod": "go",
    "Cargo.toml": "rust",
    Gemfile: "ruby",
  };

  const results = [];

  function readPackageDetails(filePath) {
    const details = {};
    try {
      const pkg = JSON.parse(readFileSync(filePath, "utf-8"));
      if (pkg.name) details.name = pkg.name;
      if (pkg.dependencies) details.depCount = Object.keys(pkg.dependencies).length;
    } catch {
      /* ignore parse errors */
    }
    return details;
  }

  function recordManifest(entry, d) {
    for (const [manifest, framework] of Object.entries(manifests)) {
      if (!entry.name.endsWith(manifest)) continue;
      const filePath = join(d, entry.name);
      const details = manifest === "package.json" ? readPackageDetails(filePath) : {};
      results.push({
        framework,
        file: filePath.replace(dir, "").replace(WINDOWS_PATH_SEPARATOR, "/"),
        details,
      });
    }
  }

  function scan(d, depth) {
    if (depth > 6) return;
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (entry.isDirectory() && !IGNORED_DIRS.has(entry.name) && !entry.name.startsWith(".")) {
        scan(join(d, entry.name), depth + 1);
        continue;
      }
      recordManifest(entry, d);
    }
  }

  scan(dir, 0);
  return results;
}

/**
 * Count files by extension, excluding ignored directories.
 *
 * @param {string} dir
 * @returns {{ total: number, byExtension: Record<string, number> }}
 */
export function countFiles(dir) {
  const byExtension = {};
  let total = 0;

  function walk(d) {
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      const fullPath = join(d, entry.name);
      if (entry.isDirectory()) {
        if (!IGNORED_DIRS.has(entry.name) && !entry.name.startsWith(".")) {
          walk(fullPath);
        }
      } else {
        total++;
        const ext = extname(entry.name).toLowerCase() || "(no ext)";
        byExtension[ext] = (byExtension[ext] || 0) + 1;
      }
    }
  }

  walk(dir);
  return { total, byExtension };
}

/**
 * Run `diff -rq` between two directories and parse the output into
 * added/modified/removed counts with sanitized detail lines.
 *
 * @param {string} fromDir
 * @param {string} toDir
 * @param {string} codeDir — base path to strip from detail output
 * @returns {{ added: number, modified: number, removed: number, details: string[] }}
 */
function parseDirDiff(fromDir, toDir, codeDir) {
  const result = spawnSync("diff", ["-rq", fromDir, toDir], {
    encoding: "utf-8",
    timeout: 30000,
  });

  if (result.error) {
    throw new Error(`diff failed: ${result.error.message}`);
  }
  if (result.status !== null && result.status > 1) {
    const detail = (result.stderr || "").trim();
    throw new Error(
      detail.length > 0
        ? `diff exited with status ${result.status}: ${detail}`
        : `diff exited with status ${result.status}`,
    );
  }

  const output = (result.stdout || "").trim();
  const lines = output ? output.split("\n") : [];

  let added = 0;
  let modified = 0;
  let removed = 0;

  for (const line of lines) {
    if (line.startsWith(`Only in ${toDir}`)) added++;
    else if (line.startsWith(`Only in ${fromDir}`)) removed++;
    else if (line.includes("differ")) modified++;
  }

  const details = lines
    .slice(0, 20)
    .map((line) => line.replaceAll(codeDir, ".").replace(WINDOWS_PATH_SEPARATOR, "/"));

  return { added, modified, removed, details };
}

/**
 * Diff adjacent sections in a per-section repo.
 * Uses `diff -rq` to find added/modified/removed files between consecutive sections.
 *
 * @param {string} codeDir
 * @param {Array<{ name: string }>} sections — sorted section list
 * @returns {Array<{ from: string, to: string, added: number, modified: number, removed: number, details: string[] }>}
 */
export function diffSections(codeDir, sections) {
  if (sections.length < 2) return [];

  const diffs = [];

  for (let i = 0; i < sections.length - 1; i++) {
    const fromDir = join(codeDir, sections[i].name);
    const toDir = join(codeDir, sections[i + 1].name);
    const { added, modified, removed, details } = parseDirDiff(fromDir, toDir, codeDir);

    diffs.push({
      from: sections[i].name,
      to: sections[i + 1].name,
      added,
      modified,
      removed,
      details,
    });
  }

  return diffs;
}

/**
 * Diff start/ vs end/ within each section that has both.
 * This shows what code changed during the module — the most valuable comparison.
 *
 * @param {string} codeDir
 * @param {Array<{ name: string, hasStart: boolean, hasEnd: boolean }>} sections
 * @returns {Array<{ section: string, added: number, modified: number, removed: number, details: string[] }>}
 */
export function diffStartEnd(codeDir, sections) {
  const diffs = [];

  for (const section of sections) {
    if (!section.hasStart || !section.hasEnd) continue;

    const startDir = join(codeDir, section.name, "start");
    const endDir = join(codeDir, section.name, "end");
    const { added, modified, removed, details } = parseDirDiff(startDir, endDir, codeDir);

    diffs.push({
      section: section.name,
      added,
      modified,
      removed,
      details,
    });
  }

  return diffs;
}
