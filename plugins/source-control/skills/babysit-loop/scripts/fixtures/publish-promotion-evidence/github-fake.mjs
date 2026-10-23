// A recorded GitHub for the publisher's `gh` seam, shared by the publisher and resolver tests.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { ghFailure } from "../../publish-promotion-evidence.mjs";

// Real `gh api` responses, recorded 2026-10-12 and 2026-10-13 and trimmed to the fields the
// publisher reads: from this repository (PRs #7352 and #7063, a merge commit, a check run, a
// status, an issue event, a review, a comment page, workflow runs, a compare, NOT_FOUND and 422
// answers) and one ConnectedEvent from cli/cli #14616. The comment page's body is trimmed to its
// first line. Each case copies a record and varies number, labels, merger and timestamps.
export const REC = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "recorded.json"), "utf8"));
export const REPO = "melodic-software/claude-code-plugins";
export const LANE = "lane-bot[bot]";
export const MECHANICAL = "work-class: mechanical";
export const SCOPED = "work-class: scoped";
export const MISSED = "ai-review: missed-blocking";
// The recorded check run and status name the post-merge gate in every case.
export const GATE = [REC.checkRun.name, REC.status.context];
export const FULL = "pr-require-checks.yml";
export const CANARY = "post-merge-detect-silent-revert.yml";

export const shaOf = (number) => number.toString(16).padStart(40, "0");
export const later = (at, minutes) => new Date(Date.parse(at) + minutes * 60_000).toISOString().replace(".000Z", "Z");

// GraphQL spells an App as `__typename: Bot` with the bare slug; REST adds `[bot]`.
export const actorOf = (login) => (login === null ? null : login.endsWith("[bot]") ? { __typename: "Bot", login: login.slice(0, -5) } : { __typename: "User", login });
export const page1 = (nodes, hasNextPage = false) => ({ pageInfo: { hasNextPage }, nodes });

export function pr(
  number,
  mergedAt,
  { labels = [], merger = LANE, title = REC.pullListItem.title, body = REC.pullListItem.body, linked = [], timeline = [], lastEditedAt = null, patch = {}, base = "main", head = shaOf(number + 0x100000) } = {},
) {
  const names = labels.map((name) => ({ name }));
  return {
    graph: {
      ...REC.pullGraph.data.repository.pullRequest,
      number,
      headRefOid: head,
      mergedAt,
      lastEditedAt,
      mergeCommit: { oid: shaOf(number) },
      mergedBy: actorOf(merger),
      labels: page1(names),
      closingIssuesReferences: page1(linked),
      timelineItems: page1(timeline),
      autoMerge: { nodes: [] },
      author: actorOf(LANE),
      isCrossRepository: false,
      ...patch,
    },
    list: {
      ...REC.pullListItem,
      base: { ...REC.pullListItem.base, ref: base },
      number,
      title,
      body,
      labels: names,
      created_at: later(mergedAt, -60),
      merged_at: mergedAt,
      updated_at: later(mergedAt, 1),
      merge_commit_sha: shaOf(number),
    },
  };
}

export const wfRun = (id, event, sha, created, { conclusion = "success", status = "completed", attempt = 1, actor = "github-merge-queue[bot]", triggering = actor, updated = later(created, 8) } = {}) => ({
  ...REC.workflowRun,
  id,
  event,
  head_sha: sha,
  created_at: created,
  updated_at: updated,
  status,
  conclusion: status === "completed" ? conclusion : null,
  run_attempt: attempt,
  actor: { login: actor },
  triggering_actor: { login: triggering },
});

// A recorded GitHub: answers only the GET paths the publisher is expected to call, with the
// documented semantics of each (list sort order, check-runs `filter=latest` by default, statuses
// newest first), and throws on any other, so an unexpected or mutating call fails the case.
// A run marked `superseded` was re-run: only `filter=all` returns it.
// `bumpOnPage2` updates that PR (a comment, a label) between the listing's first and second page.
// `workflowRuns`: {<workflow file>: [run]}; `attempts`: {<run id>: {<n>: run}}; `history`: the
// default branch's commits oldest first (linear, as a merge-queue branch is), defaulting to the
// merge commits in merge order.
// `offBranch`: commits not on the default branch that descend from it, as on a tag named main.
// `diverged`: head SHAs a compare reports as diverged. A PR number not in `pulls` answers with the
// recorded NOT_FOUND response.
// The lane posts a pin comment on every PR it enqueues and dispatches a full run after every merge
// (babysit_merge.py --unattended, babysit_postmerge.py), so each PR gets a correct pin and a green
// lane dispatch run on its merge commit an hour after merging, unless `comments` sets that PR's
// comments or `noDefaultDispatch` is set; an explicit run with the same id replaces the default.
// Each workflow's runs carry run_number 1, 2, ... in creation order unless a run sets its own (a
// re-run keeps its number); `deletedRuns` lists run ids GitHub no longer lists, gaps included.
// `demotionIssues`: issue nodes the GraphQL issues query returns, each with an `author` login and
// the `comments` the REST comment listing returns for it (`issueComment` builds one).
// `issueList`: the issues and pulls the REST issue listing returns (none by default, so no number
// is a hole); `goneIssues`: numbers a read of answers 410 Gone; `missingIssues`: numbers it answers
// 404; `discussions`: discussion number to author login, whose numbers also read 404 as issues;
// `lateRuns`: run ids the run listing shows on every page but the first, as if listed mid-read.
export const pinComment = (sha) => ({ author: actorOf(LANE), body: `<!-- babysit-merge-pin sha=${sha} -->\nThe unattended merge path enqueued this pull request at head \`${sha}\`.`, lastEditedAt: null });
export const demotionIssue = (number, createdAt, { author = "github-actions[bot]", body = REC.demotionIssue.body, updatedAt = createdAt, comments = [], edits = [], editCount = edits.length } = {}) => ({
  ...REC.demotionIssue,
  number,
  author,
  comments,
  createdAt,
  updatedAt,
  body,
  userContentEdits: { totalCount: editCount, nodes: edits },
});
export const issueComment = (body, createdAt, login = "github-actions[bot]") => ({
  ...REC.issueComment,
  body,
  created_at: createdAt,
  user: { login, type: login.endsWith("[bot]") ? "Bot" : "User" },
});
export const issueItem = (number, created, { pull = false } = {}) => ({
  ...REC.issueListItem,
  number,
  created_at: created,
  pull_request: pull ? { url: `https://api.github.com/repos/${REPO}/pulls/${number}` } : null,
});
export function github({ pulls = [], commits = [], checkRuns = {}, statuses = {}, issueEvents = {}, reviews = {}, issues = {}, workflowRuns: explicitRuns = {}, attempts = {}, history, diverged = [], comments = {}, noDefaultDispatch = false, bumpOnPage2, deletedRuns = [], demotionIssues = [], issueList = [], goneIssues = [], missingIssues = [], discussions = {}, lateRuns = [], offBranch = [] }) {
  const defaultDispatch = noDefaultDispatch ? [] : pulls.map((p) => wfRun(900000 + p.graph.number, "workflow_dispatch", p.graph.mergeCommit.oid, later(p.graph.mergedAt, 60), { actor: LANE }));
  const explicitIds = new Set(Object.values(explicitRuns).flat().map((r) => r.id));
  const numbered = (runs) =>
    [...runs]
      .sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id - b.id)
      .map((run, index) => ({ run_number: index + 1, ...run }))
      .filter((run) => !deletedRuns.includes(run.id));
  const workflowRuns = Object.fromEntries(
    Object.entries({ ...explicitRuns, [FULL]: [...defaultDispatch.filter((r) => !explicitIds.has(r.id)), ...(explicitRuns[FULL] ?? [])] }).map(([file, runs]) => [file, numbered(runs)]),
  );
  const branch = history ?? [...pulls].sort((a, b) => a.graph.mergedAt.localeCompare(b.graph.mergedAt)).map((p) => p.graph.mergeCommit.oid);
  const page = (items, path) => {
    const n = Number(/[?&]page=(\d+)/.exec(path)[1]);
    return items.slice((n - 1) * 100, n * 100);
  };
  const runsFor = (number) => checkRuns[number] ?? [{ ...REC.checkRun, completed_at: later(pulls.find((p) => p.graph.number === number).graph.mergedAt, 5) }];
  return (path, graphql) => {
    if (path === "graphql") {
      assert.deepEqual([graphql.variables.owner, graphql.variables.name], REPO.split("/"));
      assert.match(graphql.query, /^query\(/);
      assert.doesNotMatch(graphql.query, /mutation/);
      if (/pullRequest\(number:\$number\)\{comments\(/.test(graphql.query)) {
        const pull = pulls.find((p) => p.graph.number === graphql.variables.number);
        const all = comments[graphql.variables.number] ?? [pinComment(pull.graph.headRefOid)];
        const n = Number(graphql.variables.c ?? 0);
        const nodes = all.slice(n * 100, (n + 1) * 100);
        const more = all.length > (n + 1) * 100;
        return { data: { repository: { pullRequest: { comments: { ...REC.commentsPage.data.repository.pullRequest.comments, pageInfo: { hasNextPage: more, endCursor: more ? String(n + 1) : null }, nodes } } } } };
      }
      if (/issues\(/.test(graphql.query)) {
        // filterBy createdBy and since (updated at or after); one page.
        const author = graphql.variables.author.toLowerCase();
        const nodes = demotionIssues.filter((i) => i.author.toLowerCase() === author && Date.parse(i.updatedAt) >= Date.parse(graphql.variables.since)).map(({ author: _, comments: __, ...node }) => node);
        return { data: { repository: { issues: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } };
      }
      if (/discussion\(number:/.test(graphql.query)) {
        // A number no discussion has: GraphQL NOT_FOUND, as measured 2026-10-15 on cli/cli.
        const n = graphql.variables.number;
        if (n in discussions) return { data: { repository: { discussion: { author: actorOf(discussions[n]) } } } };
        const missing = { data: { repository: { discussion: null } }, errors: [{ type: "NOT_FOUND", path: ["repository", "discussion"], message: `Could not resolve to a Discussion with the number of ${n}.` }] };
        return ghFailure(path, graphql, JSON.stringify(missing), `gh: ${missing.errors[0].message}\n`);
      }
      const found = pulls.find((p) => p.graph.number === graphql.variables.number);
      return found ? { data: { repository: { pullRequest: found.graph } } } : REC.pullNotFound;
    }
    if (path === `repos/${REPO}`) return REC.repo;
    const prefix = `repos/${REPO}/`;
    assert.ok(path.startsWith(prefix), path);
    const rest = path.slice(prefix.length);
    let m;
    if ((m = /^pulls\?state=closed(?:&base=([\w.-]+))?&sort=(created|updated)&direction=(asc|desc)&/.exec(rest))) {
      if (bumpOnPage2 && /[?&]page=2\b/.test(rest)) pulls.find((p) => p.list.number === bumpOnPage2).list.updated_at = "2026-10-04T00:00:00Z";
      const key = m[2] === "created" ? "created_at" : "updated_at";
      const sign = m[3] === "asc" ? 1 : -1;
      const listed = pulls.map((p) => p.list).filter((p) => !m[1] || p.base.ref === m[1]);
      return page(listed.sort((a, b) => sign * a[key].localeCompare(b[key])), rest);
    }
    if ((m = /^issues\/(\d+)$/.exec(rest))) {
      // The REST "Get an issue" 410 Gone for a deleted issue, in the shape of the recorded 404.
      if (goneIssues.includes(Number(m[1]))) {
        return ghFailure(path, undefined, REC.issueNotFound.stdout.replace("Not Found", "This issue was deleted").replace('"404"', '"410"'), "gh: This issue was deleted (HTTP 410)\n");
      }
      // The recorded 404, which a discussion number also reads (measured 2026-10-15 on cli/cli).
      if (missingIssues.includes(Number(m[1])) || m[1] in discussions) return ghFailure(path, undefined, REC.issueNotFound.stdout, REC.issueNotFound.stderr);
      return issues[m[1]];
    }
    if (/^issues\?state=all&sort=created&direction=desc&/.test(rest)) {
      return page([...issueList].sort((a, b) => b.created_at.localeCompare(a.created_at) || b.number - a.number), rest);
    }
    if ((m = /^pulls\/(\d+)\/reviews\?/.exec(rest))) return page(reviews[m[1]] ?? [], rest);
    if (/^commits\?since=[^&]+&until=[^&]+&/.test(rest)) return page(commits, rest);
    if ((m = /^commits\/([0-9a-f]{40})\/check-runs\?/.exec(rest))) {
      const runs = runsFor(parseInt(m[1], 16)).filter((r) => /[?&]filter=all\b/.test(rest) || !r.superseded);
      return { total_count: runs.length, check_runs: page(runs, rest) };
    }
    if ((m = /^commits\/([0-9a-f]{40})\/pulls$/.exec(rest))) {
      // A SHA no commit has: the recorded 422, as realGh hands it to ghFailure.
      if (!branch.includes(m[1])) return ghFailure(path, undefined, REC.commitNotFound.stdout, REC.commitNotFound.stderr);
      return pulls.filter((p) => p.graph.mergeCommit.oid === m[1]).map((p) => ({ number: p.graph.number, merged_at: p.graph.mergedAt, merge_commit_sha: m[1] }));
    }
    if ((m = /^commits\/([0-9a-f]{40})\/statuses\?/.exec(rest))) return page(statuses[parseInt(m[1], 16)] ?? [], rest);
    if ((m = /^issues\/(\d+)\/events\?/.exec(rest))) return page(issueEvents[m[1]] ?? [], rest);
    if ((m = /^issues\/(\d+)\/comments\?/.exec(rest))) return page(demotionIssues.find((i) => i.number === Number(m[1]))?.comments ?? [], rest);
    if ((m = /^actions\/workflows\/([\w.-]+)\/runs\?event=(\w+)&branch=main&created=%3E%3D[^&]+&/.exec(rest))) {
      const runs = (workflowRuns[m[1]] ?? []).filter((r) => r.event === m[2]);
      return { total_count: runs.length, workflow_runs: page(runs, rest) };
    }
    if ((m = /^actions\/workflows\/([\w.-]+)\/runs\?created=([^&]+)&per_page=(\d+)&page=(\d+)$/.exec(rest))) {
      // Every event and branch, newest first, but runs created in one second oldest first (measured
      // 2026-10-15: runs 3100 and 3101, created in one second, listed 3100 then 3101). With `created`,
      // GitHub returns at most 1,000 results (REST "List workflow runs for a workflow"); past them, and
      // measured 2026-10-15, a page is empty with total_count 0, and total_count stops at 2,500.
      const [lo, hi] = decodeURIComponent(m[2]).split("..").map(Date.parse);
      const [size, n] = [Number(m[3]), Number(m[4])];
      if (size * n > 1000) return { total_count: 0, workflow_runs: [] };
      const runs = (workflowRuns[m[1]] ?? [])
        .filter((r) => Date.parse(r.created_at) >= lo && Date.parse(r.created_at) <= hi && !(n === 1 && lateRuns.includes(r.id)))
        .sort((a, b) => b.created_at.localeCompare(a.created_at) || a.id - b.id);
      return { total_count: Math.min(runs.length, 2500), workflow_runs: runs.slice((n - 1) * size, n * size) };
    }
    if ((m = /^actions\/runs\/(\d+)\/attempts\/(\d+)$/.exec(rest))) return attempts[m[1]][m[2]];
    if (rest === "git/ref/heads/main") return { ref: "refs/heads/main", object: { sha: branch.at(-1) } };
    if ((m = /^compare\/([0-9a-f]{40})\.\.\.([0-9a-f]{40})\?/.exec(rest))) {
      // An off-branch commit (a tag named main) descends from every branch commit and is
      // diverged from the tip.
      if (offBranch.includes(m[2])) return { ...REC.compare, status: "ahead", ahead_by: 1, total_commits: 1, commits: [] };
      if (offBranch.includes(m[1])) return { ...REC.compare, status: "diverged", ahead_by: 0, total_commits: 0, commits: [] };
      const [base, head] = [branch.indexOf(m[1]), branch.indexOf(m[2])];
      assert.ok(base >= 0 && head >= 0, `compare outside the recorded history: ${rest}`);
      const status = diverged.includes(m[2]) ? "diverged" : head > base ? "ahead" : head === base ? "identical" : "behind";
      const ahead = head > base ? branch.slice(base + 1, head + 1).map((sha) => ({ sha })) : [];
      return { ...REC.compare, status, ahead_by: ahead.length, total_commits: ahead.length, commits: page(ahead, rest) };
    }
    throw new Error(`unrecorded gh api call: ${path}`);
  };
}
