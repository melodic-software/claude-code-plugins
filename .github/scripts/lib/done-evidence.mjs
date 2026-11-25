// done-evidence.mjs: whether an already-done stop's cited work is on the
// default branch and closes the issue, and how its close comment reads back.
// report-outcome writes the close comment and checks the evidence before it
// closes; check-trusted-trigger's isTrustedClose checks it again when a
// dependent or a split parent counts the lanes App's close.
//
// A lane script that runs from a copy of its own directory imports this as
// `../lib/done-evidence.mjs`: collect-base-activity copies the base
// .github/scripts/lib/ beside that copy. No dependencies.

// A verified-done close (stop-routes.json) instead rests on parentDone: every
// sub-issue of the issue closed as completed by a trusted close.

// The line a stop comment names its stop on, and the heading over the run's
// own words, which report-outcome writes and closeStop reads back.
export const stopLine = (stop) => `The work-resolve-issue lane stopped on this issue (\`${stop}\`):`;
export const RUN_WORDS = "In the run's words:";

// Whether `text` closes issue `number` as GitHub reads a closing keyword:
// close, fix or resolve in any tense and case, an optional colon, then
// `#<number>`. A `Refs:` line, a follow-up or a squash suffix closes nothing.
// branch-cleanup's linkedIssues takes the same keywords and `Refs` too, and a
// script activity runs from a copy of its own directory, so it is restated here.
// A keyword after "not" ("does not fix #<n>") closes nothing here, and neither
// does a revert, whose message repeats the closing line of the work it undoes.
const closesIssue = (text, number) =>
  !/^\s*revert\b/i.test(text) && new RegExp(`(?<!\\bnot\\s+)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\b:?\\s+#${number}(?!\\w)`, "i").test(text);

// Whether the commit or pull request an already-done reason cites is on the
// default branch and closes the issue: a pull request (`#<n>`) merged into
// the default branch, or a commit SHA the default branch contains (the
// compare from it is ahead or identical), merged or committed after the issue
// opened and after it was last reopened, whose commit message closes the
// issue (closesIssue). A pull request is read by its merge commit, which a squash fills from the body, since its
// title and body stay editable after the merge. Lane pull requests carry
// `Closes #N`, so nothing else counts: a release commit once closed an issue
// it never touched (run 40844966342). A read that fails, or a reason that
// cites neither, proves nothing. The first three cited numbers other than the
// issue are tried, so a duplicate cited before the closing pull request is no
// cover. `repo` is the API path prefix, `/repos/<owner>/<name>`.
export async function doneEvidence(github, repo, reason, issueNumber) {
  const text = String(reason ?? "");
  const prs = [...new Set([...text.matchAll(/[#＃]([1-9][0-9]{0,9})\b/g)].map((match) => match[1]))]
    .filter((number) => Number(number) !== issueNumber)
    .slice(0, 3);
  // A SHA holds a letter, so a run id or other number is never read as one;
  // the first three such words are tried, so a hex-looking word is no cover.
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
  // Whether `sha` is on the default branch: its compare with the branch reads
  // ahead (the branch moved past it) or identical.
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
            // An upper layer of a native stack keeps the lower layer's branch
            // as its base when the stack lands together; its merge commit on
            // the default branch is what counts.
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

// Why `children` (an issue's sub-issues as listed) do not all count as done,
// or null when each is closed with state_reason `completed` by a close
// `trusted(number)` accepts: an open sub-issue, or one closed not_planned, as
// a duplicate or with no reason, does not count. Nor does one outside
// `repository` (owner/name) or with no repository_url: `trusted` judges a
// number in this repository only. The one child rule of a split parent's close
// (admit.mjs splitLeftOpen) and of a verified-done close. The listed states
// are checked first, so a sub-issue left open, closed otherwise or elsewhere
// costs no close read.
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

// Whether issue `issueNumber` has sub-issues and every one counts as done
// (subIssueLeftOpen): a verified-done close's evidence, beside the run's check
// of the issue's own done-when. A read that fails, or a listing past
// EVENT_PAGES pages, proves nothing. `repo` is the API path, `/repos/owner/name`.
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

// When issue `issueNumber` was last reopened (-Infinity when never), so work
// merged before a person reopened it is no evidence; NaN when its events do
// not read whole within EVENT_PAGES pages, which fails the check closed.
const EVENT_PAGES = 10;
async function lastReopened(github, repo, issueNumber) {
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

// report-outcome's close marker, alone or after its escalation line.
const CLOSE_MARKER = /^(?:<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r?\n)?<!-- work-resolve-issue outcome=closed(?: [a-z]+=\S+)* -->\r?\n/;
const STOP = /^The work-resolve-issue lane stopped on this issue \(`([a-z]+(?:-[a-z]+)*)`\):/;

// {stop, reason} from a close comment report-outcome wrote, or null for any
// other body: `stop` is the code on its stop line, and `reason` the quoted
// block under RUN_WORDS with its `> ` marks taken off ("" when none).
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
