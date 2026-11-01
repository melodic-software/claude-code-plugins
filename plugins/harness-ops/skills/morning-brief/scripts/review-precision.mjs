#!/usr/bin/env node
// Review-lane precision series: how each claude-review and claude-security-review finding on
// the pull requests merged in a closed window was answered, plus rounds-to-pass per PR.
//
//   review-precision.mjs [--since D] [--until D] [--repo owner/name] [--format json|md] [--save-snapshot FILE]
//                                                      fetch, then compute
//   review-precision.mjs fetch [--since D] [--until D] [--repo owner/name] --out FILE
//                                                      write the snapshot only
//   review-precision.mjs --snapshot FILE [--format json|md]
//                                                      compute from a saved snapshot, no network
//
// D is a UTC date (YYYY-MM-DD) or ISO time. The window is [since, until); the default is the
// 7 complete UTC days ending at today 00:00Z. Fetch reads with the operator's gh: one paged
// GraphQL query for merged PRs with their review threads and comments, then REST for each lane's
// runs, its status job and that job's notices. compute() is a pure function of the snapshot: the
// same snapshot gives the same bytes. Fetch stops at the first rate-limit error and says so.
// Exit 0 done, 1 a read failed, 2 usage, 3 rate limited.

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// The lanes, their workflow, and the status job whose check run carries the completion notice
// (.github/scripts/pr-merge/clear-escalations.mjs LANE_RECORDS).
export const LANES = Object.freeze({
  "claude-review": { file: "pr-review-hosted.yml", job: "pr-review / claude-review-status" },
  "claude-security-review": { file: "pr-review-security-hosted.yml", job: "pr-review-security / security-review" },
});
// The current lane format (the reviewed-head comment, the `claude-lane:` footer and the
// `findings=N inline=K` notice) is ci-workflows pr-review-cli (ci-workflows 8778094736, #862, and
// its notice title, 83b739f625, #865, both 2026-10-23). This repository's security lane moved to
// it in 5f8c010cab (#9307) and its code lane in 0aca16f268 (#9348), both 2026-10-23, so the first
// full UTC day both lanes ran it is 2026-10-24.
export const EARLIEST_SUPPORTED = "2026-10-24T00:00:00Z";
// The round cap: docs/conventions/pr-pipeline.yaml `loop.review-rounds`, read at fetch time.
const CAP_SOURCE = "docs/conventions/pr-pipeline.yaml loop.review-rounds";
const CAP_DEFAULT = 3;
// pr-unblock's round record (.github/scripts/pr-unblock/gate-source.mjs ROUND_MARKER).
const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
const NOTICE =
  /^claude-lane-review-complete lane=([\w-]+) sha=([0-9a-f]{40}) (?:findings=(\d{1,6}) inline=(\d{1,6}) scope=(?:whole|incremental since=[0-9a-f]{40})(?: account=fallback)?|skip=[\w-]+.*)$/;
// A lane comment's last non-blank line (babysit_review_evidence.py LANE_TAG_RE).
const FOOTER = /^\s*`?claude-lane: ([\w-]+)`?\s*$/;
// The D5 labels (plugins/source-control/reference/review-discipline.md), uppercase and whole.
// pr-unblock's reply opens with one of them (`**pr-unblock / address-feedback: VALID (defer), left
// open**`, .github/scripts/pr-unblock/publish-feedback.mjs LABELS), so the first label wins there too.
const LABEL = /\b(?:VALID\s*\((?:defer|deferred)\)|VALID-defer\b|VALID,? (?:filed|deferred)\b|VALID\b|INTENTIONAL\b|INCORRECT\b|UNCERTAIN\b)/;
const FIX_SHA = /\b(?:Fixed in|Fix:)\s*`?[0-9a-f]{7,40}\b/;
const SUMMARY_HEADER = /^(claude-review|claude-security-review) findings? *(?:\(`?([0-9a-f]{7,40})`?\))?$/;
const CITED_COMMENT = /#discussion_r(\d+)/g;
const SAME_AS = /\bsame (?:flag|finding)\b[^\n.]*?\bas on `?([0-9a-f]{7,40})\b/gi;
export const BUCKETS = Object.freeze([
  "valid-fixed",
  "valid-follow-up",
  "intentional",
  "incorrect",
  "uncertain",
  "answered-unlabeled",
  "unanswered",
]);
const LABELED = ["valid-fixed", "valid-follow-up", "intentional", "incorrect", "uncertain"];

// ---------------------------------------------------------------- answer parsing

function tables(text) {
  const out = [];
  let rows = null;
  for (const line of String(text).split(/\r?\n/)) {
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const cells = line.trim().slice(1, -1).split("|").map((cell) => cell.trim());
      if (cells.every((cell) => /^:?-+:?$/.test(cell))) continue;
      (rows ??= []).push(cells);
    } else if (rows) {
      out.push(rows);
      rows = null;
    }
  }
  if (rows) out.push(rows);
  return out.filter((t) => t.length > 1).map(([header, ...body]) => ({ header, body }));
}

// The label a piece of answer text carries, or null. A verdict column wins over the rest of the
// row; prose counts only its uppercase D5 labels, never a paraphrase.
export function labelOf(text) {
  const match = LABEL.exec(text);
  if (match) {
    const word = match[0];
    if (word.startsWith("VALID")) return word === "VALID" ? "valid" : "defer";
    return word.toLowerCase();
  }
  return FIX_SHA.test(text) ? "valid" : null;
}

// One answer's bucket. A VALID (defer) counts as a follow-up only when it cites a tracker id
// newer than the PR (issues and PRs share one numbering); a defer with no forward link is
// answered but unlabeled, and says so.
export function bucketOf(text, prNumber) {
  const label = labelOf(text);
  if (label === null) return { bucket: "answered-unlabeled" };
  if (label === "valid") return { bucket: "valid-fixed" };
  if (label === "defer") {
    const forward = [...String(text).matchAll(/#(\d+)\b/g)].some((m) => Number(m[1]) > prNumber);
    return forward ? { bucket: "valid-follow-up" } : { bucket: "answered-unlabeled", deferUnlinked: true };
  }
  return { bucket: label };
}

// A reply's label-bearing text: the first table row whose verdict column carries a label, else
// the whole reply.
function replyText(body) {
  for (const { header, body: rows } of tables(body)) {
    const col = header.findIndex((cell) => /^(verdict|classification)$/i.test(cell));
    if (col < 0) continue;
    const row = rows.find((cells) => labelOf(cells[col] ?? "") !== null);
    if (row) return `${row[col]} | ${row.join(" | ")}`;
  }
  return body;
}

export const answerBucket = (body, prNumber) => bucketOf(replyText(body), prNumber);

// The summary-answer rows an issue comment carries: { lane, sha|null, text } per row.
function summaryRows(body) {
  const out = [];
  for (const { header, body: rows } of tables(body)) {
    const m = SUMMARY_HEADER.exec(header[0] ?? "");
    if (!m) continue;
    const col = header.findIndex((cell) => /^(verdict|classification)$/i.test(cell));
    for (const cells of rows) {
      out.push({ lane: m[1], sha: m[2] ?? null, text: col >= 0 ? `${cells[col]} | ${cells.join(" | ")}` : cells.join(" | ") });
    }
  }
  return out;
}

function footerLane(body) {
  const lines = String(body).split(/\r?\n/).filter((line) => line.trim() !== "");
  const tag = lines.length ? FOOTER.exec(lines.at(-1)) : null;
  return tag && tag[1] in LANES ? tag[1] : null;
}

export function normalizeFirstLine(body) {
  const first = String(body).split(/\r?\n/).find((line) => line.trim() !== "") ?? "";
  return first
    .toLowerCase()
    .replace(/[`*]/g, "")
    .replace(/:\d+(?:-\d+)?\b/g, "")
    .replace(/\bl\d+(?:-l?\d+)?\b/g, "")
    .replace(/\blines? \d+(?:-\d+)?\b/g, "line")
    .replace(/\s+/g, " ")
    .trim();
}

// ---------------------------------------------------------------- compute

const byTime = (a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : String(a.key) < String(b.key) ? -1 : String(a.key) > String(b.key) ? 1 : 0);
const emptyOutcomes = () => Object.fromEntries(BUCKETS.map((bucket) => [bucket, 0]));

function laneRounds(reviews) {
  // Heads in order, up to and including the first clean one after the last head with findings.
  const lastDirty = reviews.findLastIndex((r) => r.findings > 0);
  const clean = reviews.findIndex((r, i) => i > lastDirty && r.findings === 0);
  return clean < 0 ? null : new Set(reviews.slice(0, clean + 1).map((r) => r.sha)).size;
}

function computePr(pr, until) {
  const reviews = {};
  for (const lane of Object.keys(LANES)) reviews[lane] = [];
  for (const notice of pr.notices ?? []) {
    if (!(notice.completedAt < until)) continue;
    const m = NOTICE.exec(notice.text);
    if (!m || !(m[1] in LANES) || m[3] === undefined) continue;
    reviews[m[1]].push({ sha: m[2], at: notice.completedAt, key: m[2], findings: Number(m[3]), inline: Number(m[4]) });
  }
  for (const lane of Object.keys(reviews)) {
    const seen = new Map();
    for (const r of reviews[lane].sort(byTime)) seen.set(r.sha, r);
    reviews[lane] = [...seen.values()].sort(byTime);
  }

  // Inline findings: lane-footed thread roots, answered by the replies before `until`.
  const findings = [];
  const rootOf = new Map();
  for (const thread of pr.threads ?? []) {
    const comments = [...(thread.comments ?? [])]
      .filter((c) => c.createdAt < until)
      .map((c) => ({ ...c, at: c.createdAt, key: c.id }))
      .sort(byTime);
    const root = comments[0];
    if (!root || root.replyTo) continue;
    for (const c of comments) rootOf.set(String(c.id), String(root.id));
    const lane = footerLane(root.body);
    if (!lane) continue;
    const replies = comments.slice(1).filter((c) => footerLane(c.body) === null);
    findings.push({ lane, sha: root.commit ?? null, at: root.createdAt, key: root.id, id: String(root.id), path: thread.path ?? "", first: normalizeFirstLine(root.body), answers: replies.map((c) => c.body) });
  }

  // Summary-only findings: N-K per review, answered by the lane's finding table rows in order.
  const rows = [];
  for (const comment of [...(pr.comments ?? [])].filter((c) => c.createdAt < until).map((c) => ({ ...c, at: c.createdAt, key: c.body })).sort(byTime)) {
    for (const row of summaryRows(comment.body)) {
      const lane = reviews[row.lane];
      const head = row.sha
        ? lane.find((r) => r.sha.startsWith(row.sha))
        : lane.filter((r) => r.at <= comment.createdAt).at(-1);
      if (head) rows.push({ ...row, head: head.sha });
    }
  }
  for (const [lane, list] of Object.entries(reviews)) {
    for (const review of list) {
      const answers = rows.filter((row) => row.lane === lane && row.head === review.sha);
      for (let i = 0; i < Math.max(0, review.findings - review.inline); i++) {
        findings.push({ lane, sha: review.sha, at: review.at, key: `${review.sha}#${i}`, id: null, path: null, first: null, summary: true, answers: answers[i] ? [answers[i].text] : [] });
      }
    }
  }

  // Reposts: the same lane flagged it on an earlier head (same path and first line), or the
  // answer cites an earlier finding of that lane.
  findings.sort(byTime);
  const byId = new Map(findings.filter((f) => f.id).map((f) => [f.id, f]));
  const isRepost = (f) => {
    const earlier = (g) => g !== f && g.lane === f.lane && g.sha !== f.sha && g.at < f.at;
    if (!f.summary && findings.some((g) => earlier(g) && !g.summary && g.path === f.path && g.first === f.first)) return true;
    const text = f.answers.join("\n");
    for (const [, id] of text.matchAll(CITED_COMMENT)) {
      const g = byId.get(rootOf.get(id) ?? id);
      if (g && earlier(g)) return true;
    }
    for (const [, sha] of text.matchAll(SAME_AS)) {
      if (findings.some((g) => earlier(g) && g.sha?.startsWith(sha.toLowerCase()))) return true;
    }
    return false;
  };

  const lanes = {};
  for (const lane of Object.keys(LANES)) {
    lanes[lane] = { findings: 0, reposts: 0, outcomes: emptyOutcomes(), defer_unlinked: 0 };
  }
  for (const f of findings) {
    const stats = lanes[f.lane];
    stats.findings++;
    if (isRepost(f)) {
      stats.reposts++;
      continue;
    }
    const labeled = f.answers.map((body) => answerBucket(body, pr.number)).find((o) => o.bucket !== "answered-unlabeled");
    const outcome = labeled ?? (f.answers.length ? answerBucket(f.answers[0], pr.number) : { bucket: "unanswered" });
    stats.outcomes[outcome.bucket]++;
    if (outcome.deferUnlinked) stats.defer_unlinked++;
  }
  for (const [lane, list] of Object.entries(reviews)) {
    const inline = list.filter((r) => findings.filter((f) => f.lane === lane && !f.summary && f.sha === r.sha).length !== r.inline);
    lanes[lane].inline_mismatch = inline.length;
    lanes[lane].heads_reviewed = list.length;
    finish(lanes[lane]);
  }
  const markers = (pr.comments ?? []).filter((c) => c.createdAt < until && String(c.body).includes(ROUND_MARKER)).length;
  return {
    number: pr.number,
    lanes,
    lane_review_rounds: Object.fromEntries(Object.entries(reviews).map(([lane, list]) => [lane, laneRounds(list)])),
    fix_rounds: markers || null,
  };
}

function finish(stats) {
  const labeled = LABELED.reduce((sum, bucket) => sum + stats.outcomes[bucket], 0);
  stats.labeled = labeled;
  stats.precision = labeled ? Number(((stats.outcomes["valid-fixed"] + stats.outcomes["valid-follow-up"]) / labeled).toFixed(4)) : null;
  return stats;
}

export function compute(snapshot) {
  const { since, until } = snapshot.window;
  const cap = snapshot.rounds_cap?.value ?? CAP_DEFAULT;
  const prs = [...snapshot.prs]
    .filter((pr) => pr.mergedAt >= since && pr.mergedAt < until)
    .sort((a, b) => a.number - b.number)
    .map((pr) => computePr(pr, until));
  const lanes = {};
  for (const lane of Object.keys(LANES)) {
    const total = { findings: 0, reposts: 0, outcomes: emptyOutcomes(), defer_unlinked: 0, inline_mismatch: 0, heads_reviewed: 0 };
    for (const pr of prs) {
      const one = pr.lanes[lane];
      for (const key of ["findings", "reposts", "defer_unlinked", "inline_mismatch", "heads_reviewed"]) total[key] += one[key];
      for (const bucket of BUCKETS) total.outcomes[bucket] += one.outcomes[bucket];
    }
    lanes[lane] = finish(total);
  }
  const roundStats = (values) => ({
    prs: values.filter((v) => v !== null).length,
    never_clean: values.filter((v) => v === null).length,
    over_cap: values.filter((v) => v !== null && v > cap).length,
  });
  return {
    window: { since, until },
    repo: snapshot.repo,
    earliest_supported: snapshot.earliest_supported ?? EARLIEST_SUPPORTED,
    truncated: [...(snapshot.truncated ?? [])].sort(),
    lanes,
    rounds: {
      cap,
      cap_source: snapshot.rounds_cap?.source ?? CAP_SOURCE,
      lane_review_rounds: Object.fromEntries(Object.keys(LANES).map((lane) => [lane, roundStats(prs.map((pr) => pr.lane_review_rounds[lane]))])),
      fix_rounds: { prs: prs.filter((pr) => pr.fix_rounds !== null).length, over_cap: prs.filter((pr) => pr.fix_rounds > cap).length },
    },
    prs,
  };
}

// JSON with every object's keys sorted, so equal data is equal bytes.
export function stableStringify(value) {
  const sort = (v) =>
    Array.isArray(v) ? v.map(sort) : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sort(v[k])])) : v;
  return `${JSON.stringify(sort(value), null, 2)}\n`;
}

export function renderMarkdown(result) {
  const pct = (p) => (p === null ? "n/a" : `${(p * 100).toFixed(1)}%`);
  const out = [
    `# Review-lane precision, ${result.repo}, [${result.window.since}, ${result.window.until})`,
    "",
    "| Lane | Findings | Reposts | valid-fixed | valid-follow-up | intentional | incorrect | uncertain | Precision (n labeled) | answered-unlabeled | unanswered |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
  ];
  for (const [lane, s] of Object.entries(result.lanes)) {
    const o = s.outcomes;
    out.push(`| ${lane} | ${s.findings} | ${s.reposts} | ${o["valid-fixed"]} | ${o["valid-follow-up"]} | ${o.intentional} | ${o.incorrect} | ${o.uncertain} | ${pct(s.precision)} (${s.labeled}) | ${o["answered-unlabeled"]} | ${o.unanswered} |`);
  }
  const r = result.rounds;
  out.push("", `Rounds to pass, against the cap of ${r.cap} (${r.cap_source}):`, "");
  for (const [lane, s] of Object.entries(r.lane_review_rounds)) {
    out.push(`- ${lane} lane_review_rounds: ${s.prs} PRs reached a clean head, ${s.over_cap} over the cap, ${s.never_clean} never clean before merge`);
  }
  out.push(`- fix_rounds: ${r.fix_rounds.prs} PRs with a pr-unblock round, ${r.fix_rounds.over_cap} over the cap`);
  if (result.truncated.length) out.push("", `PARTIAL: ${result.truncated.join("; ")}`);
  return `${out.join("\n")}\n`;
}

// ---------------------------------------------------------------- fetch

export class RateLimited extends Error {}
let calls = 0;

function gh(args) {
  calls++;
  try {
    return execFileSync("gh", args, { encoding: "utf8", maxBuffer: 1 << 30, stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    const why = `${error.stderr ?? ""}${error.stdout ?? ""}`.trim().split("\n")[0] || error.message;
    if (/rate limit|HTTP 429|secondary rate/i.test(`${error.stderr ?? ""}${error.stdout ?? ""}`)) throw new RateLimited(`gh ${args[1] ?? ""}: ${why}`);
    throw new Error(`gh ${args.slice(0, 2).join(" ")}: ${why}`);
  }
}
const ghJson = (args) => JSON.parse(gh(args));

const PR_QUERY = `query($owner:String!, $name:String!, $endCursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequests(states:MERGED, first:10, orderBy:{field:UPDATED_AT, direction:DESC}, after:$endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number headRefName createdAt mergedAt updatedAt
        reviewThreads(first:100) {
          pageInfo { hasNextPage }
          nodes {
            path line originalLine
            comments(first:50) {
              pageInfo { hasNextPage }
              nodes { databaseId createdAt author { login } body originalCommit { oid } replyTo { databaseId } }
            }
          }
        }
        comments(first:100) { pageInfo { hasNextPage } nodes { createdAt author { login } body } }
      }
    }
  }
}`;

function fetchPrs(repo, since, until, truncated) {
  const [owner, name] = repo.split("/");
  const prs = [];
  let cursor = null;
  for (;;) {
    const args = ["api", "graphql", "-F", `owner=${owner}`, "-F", `name=${name}`, "-f", `query=${PR_QUERY}`];
    if (cursor) args.push("-f", `endCursor=${cursor}`);
    const page = ghJson(args).data.repository.pullRequests;
    for (const pr of page.nodes) {
      if (!(pr.mergedAt >= since && pr.mergedAt < until)) continue;
      if (pr.reviewThreads.pageInfo.hasNextPage) truncated.push(`PR ${pr.number}: more than 100 review threads`);
      if (pr.comments.pageInfo.hasNextPage) truncated.push(`PR ${pr.number}: more than 100 comments`);
      prs.push({
        number: pr.number,
        headRefName: pr.headRefName,
        createdAt: pr.createdAt,
        mergedAt: pr.mergedAt,
        threads: pr.reviewThreads.nodes.map((t) => {
          if (t.comments.pageInfo.hasNextPage) truncated.push(`PR ${pr.number}: a thread with more than 50 comments`);
          return {
            path: t.path,
            line: t.line ?? null,
            originalLine: t.originalLine ?? null,
            comments: t.comments.nodes
              .filter((c) => c.createdAt < until)
              .map((c) => ({ id: c.databaseId, author: c.author?.login ?? null, createdAt: c.createdAt, body: c.body, commit: c.originalCommit?.oid ?? null, replyTo: c.replyTo?.databaseId ?? null })),
          };
        }),
        comments: pr.comments.nodes.filter((c) => c.createdAt < until).map((c) => ({ author: c.author?.login ?? null, createdAt: c.createdAt, body: c.body })),
        notices: [],
      });
    }
    const last = page.nodes.at(-1);
    if (!page.pageInfo.hasNextPage || !last || last.updatedAt < since) break;
    cursor = page.pageInfo.endCursor;
  }
  return prs;
}

const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");

// One lane's pull_request runs created in [from, to), split until each slice is under the
// endpoint's 1,000-result search cap (an hour that still reaches it is reported as truncated).
// Pointer: https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow
// As of: 2026-11-01. Recheck trigger: that section changes the cap or the `created` syntax.
function fetchRuns(repo, file, from, to, truncated) {
  const range = `${iso(from)}..${iso(to - 1000)}`;
  const pages = ghJson(["api", "--paginate", "--slurp", `repos/${repo}/actions/workflows/${file}/runs?event=pull_request&per_page=100&created=${range}`]);
  calls += Math.max(0, pages.length - 1);
  const total = pages[0]?.total_count ?? 0;
  if (total >= 1000) {
    if (to - from > 3_600_000) {
      const mid = from + Math.max(3_600_000, Math.floor((to - from) / 7_200_000) * 3_600_000);
      return [...fetchRuns(repo, file, from, mid, truncated), ...fetchRuns(repo, file, mid, to, truncated)];
    }
    truncated.push(`${file}: more than 1000 runs in ${range}`);
  }
  return pages.flatMap((page) => page.workflow_runs ?? []);
}

function fetchNotices(repo, prs, since, until, truncated) {
  const floor = Math.max(Date.parse(EARLIEST_SUPPORTED), Math.min(...prs.map((pr) => Date.parse(pr.createdAt))));
  const end = Date.parse(until);
  for (const [lane, { file, job }] of Object.entries(LANES)) {
    const runs = [];
    for (let day = floor - (floor % 86_400_000); day < end; day += 86_400_000) {
      runs.push(...fetchRuns(repo, file, Math.max(day, floor), Math.min(day + 86_400_000, end), truncated));
    }
    // Completed runs per PR and head, newest first. A head can run more than once (a re-run, or
    // a later skip=no-change), so runs are read until one carries a review record.
    const heads = new Map();
    for (const run of runs) {
      if (run.status !== "completed") continue;
      const pr = prs.find((p) => p.headRefName === run.head_branch && run.created_at >= p.createdAt && run.created_at <= p.mergedAt);
      if (!pr) continue;
      const key = `${pr.number} ${run.head_sha}`;
      if (!heads.has(key)) heads.set(key, { pr, runs: [] });
      heads.get(key).runs.push(run);
    }
    const multi = [...heads.values()].filter((h) => h.runs.length > 1).length;
    console.error(`review-precision: ${lane}: ${runs.length} runs listed, ${heads.size} PR heads to read (${multi} with more than one run), ${calls} gh calls so far`);
    for (const { pr, runs: list } of [...heads.values()].sort((a, b) => a.runs[0].id - b.runs[0].id)) {
      for (const run of list.sort((a, b) => b.id - a.id)) {
        const jobs = ghJson(["api", `repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`]).jobs ?? [];
        const status = jobs.filter((j) => j.name === job).sort((a, b) => b.id - a.id)[0];
        if (!status?.completed_at || !(status.completed_at < until)) continue;
        const notes = ghJson(["api", `repos/${repo}/check-runs/${status.id}/annotations?per_page=100`]);
        if (notes.length >= 100) truncated.push(`PR ${pr.number}: ${lane} run ${run.id} has 100+ annotations`);
        const records = notes
          .map((note) => (note.annotation_level === "notice" ? String(note.message ?? "") : ""))
          .filter((text) => text.startsWith("claude-lane-review-complete "));
        for (const text of records) pr.notices.push({ lane, run: run.id, completedAt: status.completed_at, text });
        if (records.some((text) => / findings=\d/.test(text))) break;
      }
    }
    console.error(`review-precision: ${lane}: done, ${calls} gh calls so far`);
  }
}

function fetchCap(repo) {
  try {
    const yaml = gh(["api", "-H", "Accept: application/vnd.github.raw", `repos/${repo}/contents/docs/conventions/pr-pipeline.yaml`]);
    const m = /^loop:\n(?:[ \t]+.*\n|\s*\n)*?[ \t]+review-rounds: (\d+)/m.exec(yaml);
    if (m) return { value: Number(m[1]), source: CAP_SOURCE };
  } catch (error) {
    if (error instanceof RateLimited) throw error;
  }
  return { value: CAP_DEFAULT, source: `${CAP_SOURCE} (unread; the default from that key)` };
}

export function fetchSnapshot({ repo, since, until }) {
  const truncated = [];
  const rounds_cap = fetchCap(repo);
  const prs = fetchPrs(repo, since, until, truncated);
  console.error(`review-precision: ${prs.length} merged PRs in the window`);
  if (prs.length) fetchNotices(repo, prs, since, until, truncated);
  for (const pr of prs) pr.notices.sort((a, b) => a.run - b.run || (a.text < b.text ? -1 : 1));
  prs.sort((a, b) => a.number - b.number);
  return { schema: 1, repo, window: { since, until }, earliest_supported: EARLIEST_SUPPORTED, rounds_cap, truncated, prs };
}

// ---------------------------------------------------------------- CLI

function toIso(value, flag) {
  const text = /^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00Z` : value;
  const ms = Date.parse(text);
  if (!text || Number.isNaN(ms) || !/Z$|[+-]\d{2}:?\d{2}$/.test(text)) throw new UsageError(`${flag} needs a UTC date or ISO time, got "${value}"`);
  return iso(ms);
}
class UsageError extends Error {}

export function parseArgs(argv, now = Date.now()) {
  const opts = { action: "run", format: "json" };
  const rest = [...argv];
  if (rest[0] === "fetch") opts.action = rest.shift();
  while (rest.length) {
    const flag = rest.shift();
    const value = rest.shift();
    if (value === undefined) throw new UsageError(`${flag} needs a value`);
    const key = { "--since": "since", "--until": "until", "--repo": "repo", "--format": "format", "--snapshot": "snapshot", "--save-snapshot": "save", "--out": "out" }[flag];
    if (!key) throw new UsageError(`unknown argument ${flag}`);
    opts[key] = value;
  }
  if (!["json", "md"].includes(opts.format)) throw new UsageError("--format is json or md");
  if (opts.action === "fetch" && !opts.out) throw new UsageError("fetch needs --out FILE");
  if (opts.snapshot) return opts;
  const today = now - (now % 86_400_000);
  opts.until = opts.until ? toIso(opts.until, "--until") : iso(today);
  opts.since = opts.since ? toIso(opts.since, "--since") : iso(Date.parse(opts.until) - 7 * 86_400_000);
  if (!(opts.since < opts.until)) throw new UsageError("--since must be before --until");
  if (opts.since < EARLIEST_SUPPORTED) {
    throw new UsageError(`windows before ${EARLIEST_SUPPORTED} are not supported: the lanes did not post the current notice and footer format`);
  }
  if (Date.parse(opts.until) > now) console.error(`review-precision: --until ${opts.until} is in the future; the window is not closed, so a rerun can differ`);
  if (opts.repo && !/^[\w.-]+\/[\w.-]+$/.test(opts.repo)) throw new UsageError("--repo is owner/name");
  return opts;
}

function currentRepo() {
  return gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).trim();
}

export function main(argv) {
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (error) {
    console.error(`review-precision: ${error.message}`);
    console.error("usage: review-precision.mjs [fetch --out FILE] [--since D] [--until D] [--repo owner/name] [--format json|md] [--snapshot FILE] [--save-snapshot FILE]");
    return 2;
  }
  try {
    const snapshot = opts.snapshot
      ? JSON.parse(readFileSync(opts.snapshot, "utf8"))
      : fetchSnapshot({ repo: opts.repo ?? currentRepo(), since: opts.since, until: opts.until });
    if (!opts.snapshot) console.error(`review-precision: ${calls} gh calls`);
    if (opts.action === "fetch" || opts.save) writeFileSync(opts.out ?? opts.save, stableStringify(snapshot));
    if (opts.action === "fetch") return 0;
    const result = compute(snapshot);
    process.stdout.write(opts.format === "md" ? renderMarkdown(result) : stableStringify(result));
    return 0;
  } catch (error) {
    console.error(`review-precision: ${error instanceof RateLimited ? "rate limited, stopped: " : ""}${error.message} (after ${calls} gh calls)`);
    return error instanceof RateLimited ? 3 : 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) process.exitCode = main(process.argv.slice(2));
