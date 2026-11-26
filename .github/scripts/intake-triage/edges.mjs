import { GitHubError, paginate } from "../lib/github-client.mjs";

export const BLOCKED_BY = "Blocked by";
export const MAX_EDGES = 50;
const TOKEN = /^#([1-9][0-9]{0,9})$/;

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

export const MAX_TEXT_BLOCKERS = 10;
const LEAD = /^\s*(?:(?:[-*+]|\d+[.)])\s+)?(?:blocked by|depends on)(?![\w-])\s*:?(.*)$/i;
const HEADING = /^\s{0,3}#{1,6}\s/;
const SECTION = /^\s{0,3}#{1,6}\s+(?:blocked by|depends on)(?![\w-])\s*:?(.*)$/i;
const ITEM = /^\s*(?:[-*+]|\d+[.)])\s+(.*)$/;
const FENCE = /^\s*(`{3,}|~{3,})/;

export function textBlockers(body, repository) {
  const escaped = repository.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const url = `https?://[^/\\s]+/${escaped}/issues/([1-9][0-9]{0,9})(?![\\w-])`;
  const ref = new RegExp(`(?<![\\w&/#])#([1-9][0-9]{0,9})(?![\\w-])|${url}`, "gi");
  const local = new RegExp(`^${url}`, "i");
  const found = [];
  const take = (text) => {
    if (!/^\s*none\b/i.test(text)) {
      for (const match of text.matchAll(ref)) {
        found.push(Number(match[1] ?? match[2]));
      }
    }
  };
  const lines = String(body ?? "").replace(/<!--[\s\S]*?-->/g, "").split(/\r?\n/);
  const defs = new Map();
  for (const line of lines) {
    const def = /^\s{0,3}\[([^\]]+)\]:\s*<?([^\s>]*)/.exec(line);
    if (def && !defs.has(def[1].toLowerCase())) {
      defs.set(def[1].toLowerCase(), def[2]);
    }
  }
  const linked = (target) => (target !== undefined && local.test(target) ? ` ${target} ` : " ");
  let fence = null;
  let inSection = false;
  for (const raw of lines) {
    const opened = FENCE.exec(raw);
    if (fence !== null) {
      if (opened && opened[1][0] === fence[0] && opened[1].length >= fence.length && raw.trim() === opened[1]) {
        fence = null;
      }
      continue;
    }
    if (opened) {
      fence = opened[1];
      continue;
    }
    if (/^\s*>/.test(raw)) {
      continue;
    }
    const line = raw
      .replace(/`[^`]*`/g, "")
      .replace(/^\s{0,3}\[[^\]]+\]:.*$/, "")
      .replace(/\[[^\]]*\]\(\s*<?([^)\s>]*)>?[^)]*\)/g, (_, target) => linked(target))
      .replace(/\[([^\]]*)\]\[([^\]]*)\]/g, (_, text, ref) => linked(defs.get((ref || text).toLowerCase())))
      .replace(/\[([^\]]+)\]/g, (whole, ref) => (defs.has(ref.toLowerCase()) ? linked(defs.get(ref.toLowerCase())) : whole))
      .replace(/\*\*|__/g, "");
    const section = SECTION.exec(line);
    if (section) {
      inSection = true;
      take(section[1]);
      continue;
    }
    if (HEADING.test(line)) {
      inSection = false;
      continue;
    }
    const lead = LEAD.exec(line);
    if (lead) {
      take(lead[1]);
      continue;
    }
    const item = inSection ? ITEM.exec(line) : null;
    if (item) {
      take(item[1]);
    }
  }
  const numbers = [...new Set(found)];
  return { numbers: numbers.slice(0, MAX_TEXT_BLOCKERS), dropped: Math.max(0, numbers.length - MAX_TEXT_BLOCKERS) };
}

const here = (url, repository) => String(url ?? "").endsWith(`/repos/${repository}`);
const unwritable = (error) => error instanceof GitHubError && (error.status === 403 || error.status === 429 || error.status >= 500);

export async function writeEdges({ github, repository, number, blockers, log = console.log }) {
  const { result, ids } = await addEdges({ github, repository, number, blockers, log });
  if (result.missed.length === 0) {
    return result;
  }
  const standing = [];
  for (const { blocker, id } of ids) {
    try {
      await github("DELETE", `/repos/${repository}/issues/${number}/dependencies/blocked_by/${id}`);
      result.unwritten.push(blocker);
    } catch (error) {
      if (error instanceof GitHubError && error.status === 404) {
        result.unwritten.push(blocker);
      } else {
        standing.push(blocker);
        result.undeleted.push({ number: blocker, status: error instanceof GitHubError ? error.status : String(error?.message ?? error) });
      }
    }
  }
  result.written = standing;
  return result;
}

const CYCLE = /\b(cycle|circular)/i;

async function addEdges({ github, repository, number, blockers, log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const ids = [];
  const result = { written: [], skipped: [], missed: [], unwritten: [], undeleted: [] };
  const skip = (blocker, why) => result.skipped.push({ number: blocker, why });
  const wrote = (blocker, id) => {
    result.written.push(blocker);
    ids.push({ blocker, id });
  };
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
    return { result, ids };
  }
  const done = () => {
    wanted.slice(MAX_EDGES).forEach((blocker) => skip(blocker, `past the first ${MAX_EDGES}`));
    return { result, ids };
  };
  let existing;
  try {
    existing = new Set((await paginate(github, `${base}/dependencies/blocked_by`)).map((issue) => issue?.number));
  } catch (error) {
    wanted.slice(0, MAX_EDGES).forEach((blocker) => miss(blocker, error));
    return done();
  }
  for (const blocker of wanted.slice(0, MAX_EDGES)) {
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
        await github("POST", `${base}/dependencies/blocked_by`, { issue_id: issue.id }, {}, { resendOnce: true });
        wrote(blocker, issue.id);
      } catch (error) {
        if (error instanceof GitHubError && error.status === 422 && CYCLE.test(`${error.message} ${error.detail ?? ""}`)) {
          log(`::notice title=apply-verdict::blocked-by edge not written: #${number} blocked by #${blocker}, GitHub refused it as a cycle (the reverse edge exists)`);
          skip(blocker, "GitHub refused it as a cycle");
        } else if (error instanceof GitHubError && error.status === 422) {
          let landed = false;
          try {
            landed = (await paginate(github, `${base}/dependencies/blocked_by`)).some((found) => found?.number === blocker);
          } catch (readError) {
            miss(blocker, readError);
            continue;
          }
          if (landed) {
            wrote(blocker, issue.id);
          } else {
            skip(blocker, "GitHub refused the edge");
          }
        } else {
          miss(blocker, error);
        }
      }
    }
  }
  return done();
}
