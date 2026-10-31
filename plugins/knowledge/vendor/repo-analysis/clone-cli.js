#!/usr/bin/env node
/**
 * Hardened shallow clone from the command line, for a skill that clones an
 * untrusted repository before reading it (`clone.js` holds the hardening).
 *
 * Usage: node clone-cli.js https://github.com/<owner>/<repo>[.git] <new-empty-destination>
 *
 * Only that URL form is accepted (the scheme and host in any case), and the
 * clone is given the URL rebuilt as `https://github.com/<owner>/<repo>`, never
 * the argument itself.
 *
 * Exit: 0 cloned; 1 the clone failed or timed out (private, missing, or slow);
 * 2 usage (a missing argument, a URL not of that form, or a destination that
 * already holds files).
 */

import fs from "node:fs";
import { fileURLToPath } from "node:url";

import { shallowCloneGitHubRepo } from "./clone.js";
import { parseGitHubUrl } from "./repo-analysis.js";

const USAGE = "Usage: node clone-cli.js https://github.com/<owner>/<repo>[.git] <new-empty-destination>\n";
const GITHUB_HTTPS_URL = /^https:\/\/github\.com\/([^/?#\\]+)\/([^/?#\\]+)$/i;

/**
 * The canonical clone URL for `url`, or null when it is not
 * `https://github.com/<owner>/<repo>[.git]` with a valid owner and repository.
 *
 * @param {string} url
 * @returns {string | null}
 */
export function canonicalGitHubUrl(url) {
  const match = GITHUB_HTTPS_URL.exec(url);
  if (!match) return null;
  const [, owner, repo] = match;
  const parsed = parseGitHubUrl(`https://github.com/${owner}/${repo}`);
  // Equal parts rule out anything URL parsing rewrote (dot segments, escapes).
  if (!parsed || parsed.owner !== owner || parsed.repo !== repo.replace(/\.git$/, "")) return null;
  return `https://github.com/${parsed.owner}/${parsed.repo}`;
}

/**
 * @param {string[]} argv arguments after `node clone-cli.js`
 * @param {object} [deps]
 * @param {typeof shallowCloneGitHubRepo} [deps.clone]
 * @param {{ write: (text: string) => unknown }} [deps.stderr]
 * @returns {Promise<number>}
 */
export async function runCloneCli(argv, { clone = shallowCloneGitHubRepo, stderr = process.stderr } = {}) {
  const [url, dest, ...extra] = argv;
  if (!url || !dest || extra.length > 0) {
    stderr.write(USAGE);
    return 2;
  }
  const canonical = canonicalGitHubUrl(url);
  if (!canonical) {
    stderr.write(`clone-cli: only an https URL is cloned, of the form https://github.com/<owner>/<repo>: ${url}\n${USAGE}`);
    return 2;
  }
  if (fs.existsSync(dest) && fs.readdirSync(dest).length > 0) {
    stderr.write(`clone-cli: the destination is not empty: ${dest}\n${USAGE}`);
    return 2;
  }
  if (await clone(canonical, dest)) return 0;
  stderr.write(`clone-cli: the clone of ${canonical} failed (private, missing, or over the time limit)\n`);
  return 1;
}

/** True when this file is the process entry point, compared as real paths (a symlinked plugin root). */
function isMain() {
  try {
    return Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  runCloneCli(process.argv.slice(2)).then((code) => {
    process.exitCode = code;
  });
}
