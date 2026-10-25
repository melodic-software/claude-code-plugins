// edges.mjs: the `Blocked by:` verdict line and the native blocked-by edges
// apply-verdict writes from it. No model.
//
// The line starts its own line as exactly `Blocked by: `, once, and holds
// `none` or a comma list of `#<digits>` tokens; anything else in it is model
// output and names no issue. A missing line names none.
//
// Each named issue gets an edge on the triaged issue only when it is an open
// issue in this repository, not a pull request and not the issue itself, and
// the edge is not there yet. The POST body's `issue_id` is the blocker's REST
// `id`, read from the blocker itself. GitHub answering 403, 429 or 5xx on a
// read or write for an edge leaves that edge missed, not the run stopped.
import { GitHubError, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const BLOCKED_BY = "Blocked by";
export const MAX_EDGES = 50;
const TOKEN = /^#([1-9][0-9]{0,9})$/;

// {numbers, problem}: numbers is the list of named issues (empty for none or a
// missing line), problem is null or why the line named nothing.
export function parseBlockedBy(lines) {
  const found = lines.filter((line) => line.startsWith(`${BLOCKED_BY}: `)).map((line) => line.slice(BLOCKED_BY.length + 2).trim());
  if (found.length === 0) {
    return { numbers: [], problem: null };
  }
  if (found.length > 1) {
    return { numbers: [], problem: `more than one \`${BLOCKED_BY}:\` line` };
  }
  if (found[0] === "none") {
    return { numbers: [], problem: null };
  }
  const matches = found[0].split(",").map((token) => TOKEN.exec(token.trim()));
  if (matches.some((match) => match === null)) {
    return { numbers: [], problem: `the \`${BLOCKED_BY}:\` line is not none or a list of #<number>` };
  }
  return { numbers: [...new Set(matches.map((match) => Number(match[1])))], problem: null };
}

const here = (url, repository) => String(url ?? "").endsWith(`/repos/${repository}`);
// A refusal (a missing permission or a rate limit) or a server error.
const unwritable = (error) => error instanceof GitHubError && (error.status === 403 || error.status === 429 || error.status >= 500);

// Writes the edges; returns {written, skipped: [{number, why}], missed:
// [{number, status}]}. Any other API error stops it.
export async function writeEdges({ github, repository, number, blockers }) {
  const base = `/repos/${repository}/issues/${number}`;
  const result = { written: [], skipped: [], missed: [] };
  const skip = (blocker, why) => result.skipped.push({ number: blocker, why });
  const miss = (blocker, error) => {
    if (!unwritable(error)) {
      throw error;
    }
    result.missed.push({ number: blocker, status: error.status });
  };
  const wanted = blockers.filter((blocker) => blocker !== number);
  if (wanted.length < blockers.length) {
    skip(number, "the issue itself");
  }
  if (wanted.length === 0) {
    return result;
  }
  let existing;
  try {
    existing = new Set((await paginate(github, `${base}/dependencies/blocked_by`)).map((issue) => issue?.number));
  } catch (error) {
    for (const [index, blocker] of wanted.entries()) {
      if (index < MAX_EDGES) {
        miss(blocker, error);
      } else {
        skip(blocker, `past the first ${MAX_EDGES}`);
      }
    }
    return result;
  }
  for (const [index, blocker] of wanted.entries()) {
    if (index >= MAX_EDGES) {
      skip(blocker, `past the first ${MAX_EDGES}`);
      continue;
    }
    if (existing.has(blocker)) {
      skip(blocker, "the edge is already there");
      continue;
    }
    let issue;
    try {
      issue = await github("GET", `/repos/${repository}/issues/${blocker}`);
    } catch (error) {
      if (error instanceof GitHubError && (error.status === 404 || error.status === 410)) {
        skip(blocker, "no such issue");
      } else {
        miss(blocker, error);
      }
      continue;
    }
    if (issue?.pull_request) {
      skip(blocker, "a pull request");
    } else if (!here(issue?.repository_url, repository) || issue?.number !== blocker) {
      skip(blocker, "not an issue in this repository");
    } else if (issue.state !== "open") {
      skip(blocker, "not open");
    } else if (!Number.isInteger(issue.id)) {
      skip(blocker, "no issue id");
    } else {
      try {
        await github("POST", `${base}/dependencies/blocked_by`, { issue_id: issue.id });
        result.written.push(blocker);
      } catch (error) {
        if (error instanceof GitHubError && error.status === 422) {
          skip(blocker, "GitHub refused the edge");
        } else {
          miss(blocker, error);
        }
      }
    }
  }
  return result;
}
