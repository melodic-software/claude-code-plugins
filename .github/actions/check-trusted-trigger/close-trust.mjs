import { paginate } from "../../scripts/lib/github-client.mjs";

const ISSUE_NUMBER = /^[1-9][0-9]{0,9}$/;

const CLOSER_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      timelineItems(itemTypes: CLOSED_EVENT, last: 1) {
        nodes { ... on ClosedEvent { closer {
          __typename
          ... on PullRequest { merged repository { nameWithOwner } }
          ... on Commit { repository { nameWithOwner } }
        } } }
      }
    }
  }
}`;
/**
 * Whether a close counts: (a) a listed human made it, matched by id; (b) the
 * issue's last ClosedEvent `closer` is a merged pull request or a commit in
 * this repository, whoever merged it (GraphQL, since the REST close event
 * carries no pull request link); or (c) the lanes App closed it, when the
 * caller names the App with `isApp`, and the App's own outcome close comment
 * (appCloseKind) postdates the issue's last reopen (owner Q300), and an
 * already-done or verified-done close's evidence still re-checks true (owner
 * Q9). Any other
 * close, such as a workflow's GITHUB_TOKEN, an App close with no such comment,
 * or an outside author closing their own issue, counts for nothing.
 */
export async function isTrustedClose(github, repo, closedIssue, humans, isApp = () => false) {
  const closer = closedIssue?.closed_by;
  if (humans.has(closer?.id)) {
    return true;
  }
  if (closedIssue?.state !== "closed" || !ISSUE_NUMBER.test(String(closedIssue.number))) {
    return false;
  }
  const [owner, name] = repo.split("/");
  const answer = await github("POST", "/graphql", {
    query: CLOSER_QUERY,
    variables: { owner, name, number: Number(closedIssue.number) },
  });
  const by = answer?.data?.repository?.issue?.timelineItems?.nodes?.at(-1)?.closer;
  const here = String(by?.repository?.nameWithOwner ?? "").toLowerCase() === repo.toLowerCase();
  if (here && (by.__typename === "Commit" || (by.__typename === "PullRequest" && by.merged === true))) {
    return true;
  }
  return isApp(closer) && appMarkedClose(github, repo, Number(closedIssue.number), humans, isApp);
}

async function appMarkedClose(github, repo, number, humans, isApp) {
  try {
    const close = await appCloseKind(github, repo, number, isApp);
    if (!close) {
      return false;
    }
    const { doneEvidence, lastReopened, parentDone } = await import(new URL("../../scripts/lib/done-evidence.mjs", import.meta.url).href);
    if (!(Date.parse(close.at) > (await lastReopened(github, `/repos/${repo}`, number)))) {
      return false;
    }
    if (close.stop === "verified-done") {
      const trusted = async (child) => isTrustedClose(github, repo, await github("GET", `/repos/${repo}/issues/${child}`), humans, isApp);
      return (await parentDone(github, `/repos/${repo}`, number, trusted)) === true;
    }
    if (close.stop === "already-done") {
      return (await doneEvidence(github, `/repos/${repo}`, close.reason, number)) === true;
    }
    return true;
  } catch {
    return false;
  }
}

/**
 * The lanes App's last close comment on issue `number` (report-outcome's,
 * read back by closeStop): {stop, reason, url, at}, or null when none parses
 * or a read fails. It says what kind of close the App made, never that the
 * work is done.
 */
export async function appCloseKind(github, repo, number, isApp) {
  try {
    const { closeStop } = await import(new URL("../../scripts/lib/done-evidence.mjs", import.meta.url).href);
    const comments = await paginate(github, `/repos/${repo}/issues/${number}/comments`);
    const found = comments
      .filter((comment) => isApp(comment?.user))
      .map((comment) => ({ comment, close: closeStop(comment.body) }))
      .findLast(({ close }) => Boolean(close));
    return found ? { ...found.close, url: found.comment.html_url ?? null, at: found.comment.created_at ?? null } : null;
  } catch {
    return null;
  }
}
