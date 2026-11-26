export const stopLine = (stop) => `The work-resolve-issue lane stopped on this issue (\`${stop}\`):`;
export const RUN_WORDS = "In the run's words:";

const closesIssue = (text, number) =>
  !/^\s*revert\b/i.test(text) && new RegExp(`(?<!\\bnot\\s+)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\b:?\\s+#${number}(?!\\w)`, "i").test(text);

export async function doneEvidence(github, repo, reason, issueNumber) {
  const text = String(reason ?? "");
  const prs = [...new Set([...text.matchAll(/[#＃]([1-9][0-9]{0,9})\b/g)].map((match) => match[1]))]
    .filter((number) => Number(number) !== issueNumber)
    .slice(0, 3);
  const shas = [...text.matchAll(/\b[0-9a-f]{7,40}\b/g)].map((match) => match[0]).filter((word) => /[a-f]/.test(word)).slice(0, 3);
  if (prs.length === 0 && shas.length === 0) {
    return false;
  }
  const issue = await github("GET", `${repo}/issues/${issueNumber}`).catch(() => null);
  const base = await github("GET", repo).then((answer) => answer?.default_branch, () => "");
  const opened = Math.max(Date.parse(issue?.created_at), await lastReopened(github, repo, issueNumber));
  if (!Number.isFinite(opened) || typeof base !== "string" || base === "") {
    return false;
  }
  const tied = (commit, at) => Date.parse(at) > opened && closesIssue(String(commit?.commit?.message ?? ""), issueNumber);
  const onBase = async (sha) => {
    const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(sha)}...${encodeURIComponent(base)}`).catch(() => null);
    return comparison?.status === "ahead" || comparison?.status === "identical";
  };
  for (const pr of prs) {
    if (
      await github("GET", `${repo}/pulls/${pr}`)
        .then(
          async (pull) =>
            Boolean(pull?.merged_at) &&
            /^[0-9a-f]{40}$/.test(pull.merge_commit_sha ?? "") &&
            (pull.base?.ref === base || (await onBase(pull.merge_commit_sha))) &&
            tied(await github("GET", `${repo}/commits/${pull.merge_commit_sha}`), pull.merged_at),
        )
        .catch(() => false)
    ) {
      return true;
    }
  }
  for (const sha of shas) {
    if (
      (await onBase(sha)) &&
      (await github("GET", `${repo}/commits/${encodeURIComponent(sha)}`)
        .then((commit) => tied(commit, commit?.commit?.committer?.date))
        .catch(() => false))
    ) {
      return true;
    }
  }
  return false;
}

export async function subIssueLeftOpen(children, trusted, repository) {
  const left = (child) => `sub-issue #${child?.number} is not closed as completed by a listed human or a merge`;
  const elsewhere = children.find((child) => !String(child?.repository_url ?? "").toLowerCase().endsWith(`/repos/${repository}`.toLowerCase()));
  if (elsewhere !== undefined) {
    return `sub-issue #${elsewhere?.number} is not in this repository`;
  }
  const undone = children.find((child) => child?.state !== "closed" || child.state_reason !== "completed");
  if (undone !== undefined) {
    return left(undone);
  }
  for (const child of children) {
    if (!(await trusted(child.number))) {
      return left(child);
    }
  }
  return null;
}

export async function parentDone(github, repo, issueNumber, trusted) {
  const children = [];
  for (let page = 1; page <= EVENT_PAGES; page += 1) {
    const listed = await github("GET", `${repo}/issues/${issueNumber}/sub_issues?per_page=100&page=${page}`).catch(() => null);
    if (!Array.isArray(listed)) {
      return false;
    }
    children.push(...listed);
    if (listed.length < 100) {
      return children.length > 0 && (await subIssueLeftOpen(children, trusted, repo.replace(/^\/repos\//, "")).catch(() => "unread")) === null;
    }
  }
  return false;
}

const EVENT_PAGES = 10;
export async function lastReopened(github, repo, issueNumber) {
  let last = -Infinity;
  for (let page = 1; page <= EVENT_PAGES; page += 1) {
    const events = await github("GET", `${repo}/issues/${issueNumber}/events?per_page=100&page=${page}`).catch(() => null);
    if (!Array.isArray(events)) {
      return Number.NaN;
    }
    for (const event of events) {
      if (event?.event === "reopened") {
        last = Math.max(last, Date.parse(event.created_at));
      }
    }
    if (events.length < 100) {
      return last;
    }
  }
  return Number.NaN;
}

const CLOSE_MARKER = /^(?:<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r?\n)?<!-- work-resolve-issue outcome=closed(?: [a-z]+=\S+)* -->\r?\n/;
const STOP = /^The work-resolve-issue lane stopped on this issue \(`([a-z]+(?:-[a-z]+)*)`\):/;

export function closeStop(body) {
  const text = String(body ?? "");
  const marker = CLOSE_MARKER.exec(text);
  if (!marker) {
    return null;
  }
  const lines = text.slice(marker[0].length).split(/\r?\n/);
  const stop = STOP.exec(lines[0] ?? "")?.[1];
  if (!stop) {
    return null;
  }
  const start = lines.indexOf(RUN_WORDS);
  const quoted = [];
  for (const line of start < 0 ? [] : lines.slice(start + 2)) {
    if (!line.startsWith(">")) {
      break;
    }
    quoted.push(line.replace(/^> ?/, ""));
  }
  return { stop, reason: quoted.join("\n") };
}
