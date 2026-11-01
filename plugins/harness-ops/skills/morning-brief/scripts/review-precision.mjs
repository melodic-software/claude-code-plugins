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
// GraphQL query for merged PRs with their review threads, comments and each comment's edit
// history, from which each lane's reviewed heads are read. compute() is a pure function of the
// snapshot: the same snapshot gives the same bytes. Fetch stops at the first rate-limit error
// and says so.
// Exit 0 done, 1 a read failed, 2 usage, 3 rate limited.

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const LANES = Object.freeze(["claude-review", "claude-security-review"]);
// The current lane format (the reviewed-head comment with its counts line, and the
// `claude-lane:` footer) is ci-workflows pr-review-cli (ci-workflows 8778094736, #862, and
// 83b739f625, #865, both 2026-10-23). This repository's security lane moved to it in 5f8c010cab
// (#9307) and its code lane in 0aca16f268 (#9348), both 2026-10-23, so the first full UTC day
// both lanes ran it is 2026-10-24.
export const EARLIEST_SUPPORTED = "2026-10-24T00:00:00Z";
// The round cap: docs/conventions/pr-pipeline.yaml `loop.review-rounds`, read at fetch time.
const CAP_SOURCE = "docs/conventions/pr-pipeline.yaml loop.review-rounds";
const CAP_DEFAULT = 3;
// pr-unblock's round record (.github/scripts/pr-unblock/gate-source.mjs ROUND_MARKER).
const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
// Each lane keeps one summary comment per PR, edited in place on every reviewed head; every
// version opens with the reviewed-head marker and its counts line, so the comment's edit history
// is the lane's review record: `<!-- claude-lane-reviewed-head lane=L sha=S -->` and
// "**L** reviewed `S`: read ...; N finding(s), K as inline comments."
const REVIEWED_HEAD = /<!-- claude-lane-reviewed-head lane=([\w-]+) sha=([0-9a-f]{40}) -->/;
const COUNTS = /\b(\d{1,6}) finding\(s\), (\d{1,6}) as inline comments\b/;
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
// Who wrote the answer an outcome came from. GraphQL's author `__typename` (the Actor interface)
// tells a Bot (the lanes App, any other app) from a User; a User answer that carries the D5 label
// marker line (review-discipline.md, written by agents that follow it) or Claude Code's attribution
// line is an agent session posting as a person. Anything else, or no recorded type, is unknown.
export const AUTHOR_KINDS = Object.freeze(["person", "agent", "bot", "unknown"]);
const AGENT_SIGN = /^\s*(?:<!-- d5 finding=|(?:🤖\s*)?Generated with \[Claude Code\])/mu;
const ANSWERED = BUCKETS.filter((bucket) => bucket !== "unanswered");

export function authorKind(type, body) {
  if (type === "Bot") return "bot";
  if (type !== "User") return "unknown";
  return AGENT_SIGN.test(String(body ?? "")) ? "agent" : "person";
}

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

// The item numbers an answer cites in this repository: a bare `#N`, and this repository's
// `owner/repo#N` and issue or pull URLs; another repository's never count.
function citedItems(text, repo) {
  const out = [...String(text).matchAll(/(?<![\w./-])#(\d+)\b/g)].map((m) => Number(m[1]));
  if (repo) {
    const name = repo.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const own = new RegExp(`(?<![\\w./-])(?:https://github\\.com/${name}/(?:issues|pull)/|${name}#)(\\d+)\\b`, "gi");
    for (const m of String(text).matchAll(own)) out.push(Number(m[1]));
  }
  return out;
}

// One answer's bucket. A VALID (defer) counts as a follow-up only when it cites a tracker id
// newer than the PR (issues and PRs share one numbering); a defer with no forward link is
// answered but unlabeled, and says so.
export function bucketOf(text, prNumber, repo = null) {
  const label = labelOf(text);
  if (label === null) return { bucket: "answered-unlabeled" };
  if (label === "valid") return { bucket: "valid-fixed" };
  if (label === "defer") {
    const forward = citedItems(text, repo).some((n) => n > prNumber);
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

export const answerBucket = (body, prNumber, repo = null) => bucketOf(replyText(body), prNumber, repo);

const lanesNamed = (text) => LANES.filter((lane) => new RegExp(`(?<![\\w-])${lane}(?![\\w-])`).test(text));
const botLogin = (login) => String(login ?? "").replace(/\[bot\]$/, "");

// The summary-answer rows an issue comment carries: { lane|null, sha|null, login|null, text } per
// row. Two shapes: a `<lane> finding (<sha>)` header, and the D5 table
// (`| # | Finding | Classification | ...`, review-discipline.md), whose lane is the one a row or the
// comment names (null when neither names exactly one) and whose `<!-- d5 finding=N ... lane=L -->`
// marker gives the login of the reviewer it answers.
function summaryRows(body) {
  const out = [];
  for (const { header, body: rows } of tables(body)) {
    const col = header.findIndex((cell) => /^(verdict|classification)$/i.test(cell));
    const m = SUMMARY_HEADER.exec(header[0] ?? "");
    const text = (cells) => (col >= 0 ? `${cells[col]} | ${cells.join(" | ")}` : cells.join(" | "));
    if (m) {
      for (const cells of rows) out.push({ lane: m[1], sha: m[2] ?? null, login: null, text: text(cells) });
    } else if (header[0] === "#" && col >= 0) {
      const named = lanesNamed(body);
      for (const cells of rows) {
        const inRow = lanesNamed(cells.join(" "));
        const lane = inRow.length === 1 ? inRow[0] : named.length === 1 ? named[0] : null;
        const marker = new RegExp(`<!-- d5 finding=${cells[0].replace(/\D/g, "")} label=\\S+ lane=(\\S+) -->`).exec(body);
        out.push({ lane, sha: null, login: marker ? marker[1] : null, text: text(cells) });
      }
    }
  }
  return out;
}

function footerLane(body) {
  const lines = String(body).split(/\r?\n/).filter((line) => line.trim() !== "");
  const tag = lines.length ? FOOTER.exec(lines.at(-1)) : null;
  return tag && LANES.includes(tag[1]) ? tag[1] : null;
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
// The answered outcomes per answer author kind; an unanswered finding has no answerer.
const emptyByAuthor = () => Object.fromEntries(AUTHOR_KINDS.map((kind) => [kind, { outcomes: Object.fromEntries(ANSWERED.map((bucket) => [bucket, 0])) }]));
const kindOf = (kind) => (AUTHOR_KINDS.includes(kind) ? kind : "unknown");

function laneRounds(reviews) {
  // Heads in order, up to and including the first clean one after the last head with findings;
  // 0 when the lane reviewed no head, null when it never came clean before the merge.
  if (!reviews.length) return 0;
  const lastDirty = reviews.findLastIndex((r) => r.findings > 0);
  const clean = reviews.findIndex((r, i) => i > lastDirty && r.findings === 0);
  return clean < 0 ? null : new Set(reviews.slice(0, clean + 1).map((r) => r.sha)).size;
}

function computePr(pr, until, repo, roundAuthor) {
  const reviews = {};
  for (const lane of LANES) reviews[lane] = [];
  for (const review of pr.reviews ?? []) {
    if (!(review.at < until) || !LANES.includes(review.lane) || !Number.isInteger(review.findings)) continue;
    reviews[review.lane].push({ sha: review.sha, at: review.at, key: review.sha, findings: review.findings, inline: review.inline });
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
    findings.push({ lane, sha: root.commit ?? null, at: root.createdAt, key: root.id, id: String(root.id), path: thread.path ?? "", first: normalizeFirstLine(root.body), resolved: thread.resolved === true, answers: replies.map((c) => ({ body: c.body, kind: c.author_kind })) });
  }

  // Summary-only findings: N-K per review, answered by the lane's finding table rows in order. A
  // D5 row naming no lane answers the only lane whose latest head before it has summary-only
  // findings; a row whose marker names a reviewer other than the lanes' comment author is skipped.
  const comments = [...(pr.comments ?? [])].filter((c) => c.createdAt < until).map((c) => ({ ...c, at: c.createdAt, key: c.body })).sort(byTime);
  const laneLogins = new Set(comments.filter((c) => REVIEWED_HEAD.test(c.body)).map((c) => botLogin(c.author)));
  const latest = (lane, at) => reviews[lane].filter((r) => r.at <= at).at(-1);
  const rows = [];
  for (const comment of comments) {
    for (const row of summaryRows(comment.body)) {
      if (row.login && laneLogins.size && !laneLogins.has(botLogin(row.login))) continue;
      let lane = row.lane;
      if (!lane) {
        const open = LANES.filter((l) => {
          const r = latest(l, comment.createdAt);
          return r && r.findings > r.inline;
        });
        if (open.length !== 1) continue;
        lane = open[0];
      }
      const head = row.sha ? reviews[lane].find((r) => r.sha.startsWith(row.sha)) : latest(lane, comment.createdAt);
      if (head) rows.push({ ...row, lane, head: head.sha, kind: comment.author_kind });
    }
  }
  for (const [lane, list] of Object.entries(reviews)) {
    for (const review of list) {
      const answers = rows.filter((row) => row.lane === lane && row.head === review.sha);
      for (let i = 0; i < Math.max(0, review.findings - review.inline); i++) {
        findings.push({ lane, sha: review.sha, at: review.at, key: `${review.sha}#${i}`, id: null, path: null, first: null, summary: true, answers: answers[i] ? [{ body: answers[i].text, kind: answers[i].kind }] : [] });
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
    const text = f.answers.map((a) => a.body).join("\n");
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
  for (const lane of LANES) {
    lanes[lane] = { findings: 0, reposts: 0, outcomes: emptyOutcomes(), by_author: emptyByAuthor(), defer_unlinked: 0, resolved_unanswered: 0 };
  }
  for (const f of findings) {
    const stats = lanes[f.lane];
    stats.findings++;
    if (isRepost(f)) {
      stats.reposts++;
      continue;
    }
    const answers = f.answers.map((a) => ({ ...answerBucket(a.body, pr.number, repo), kind: kindOf(a.kind) }));
    const outcome = answers.find((o) => o.bucket !== "answered-unlabeled") ?? answers[0] ?? { bucket: "unanswered" };
    stats.outcomes[outcome.bucket]++;
    if (outcome.kind) stats.by_author[outcome.kind].outcomes[outcome.bucket]++;
    if (outcome.deferUnlinked) stats.defer_unlinked++;
    if (outcome.bucket === "unanswered" && f.resolved) stats.resolved_unanswered++;
  }
  for (const [lane, list] of Object.entries(reviews)) {
    const inline = list.filter((r) => findings.filter((f) => f.lane === lane && !f.summary && f.sha === r.sha).length !== r.inline);
    lanes[lane].inline_mismatch = inline.length;
    lanes[lane].heads_reviewed = list.length;
    finish(lanes[lane]);
  }
  // A round is a comment whose first line is the marker, from the lanes App when the snapshot
  // names it (address-feedback.mjs isRoundMarker); a quote of the marker elsewhere is not one.
  const isRound = (c) => String(c.body).split(/\r?\n/)[0].trim() === ROUND_MARKER && (!roundAuthor || botLogin(c.author) === botLogin(roundAuthor));
  const markers = (pr.comments ?? []).filter((c) => c.createdAt < until && isRound(c)).length;
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
  for (const one of Object.values(stats.by_author ?? {})) finish(one);
  return stats;
}

export function compute(snapshot) {
  const { since, until } = snapshot.window;
  const cap = snapshot.rounds_cap?.value ?? CAP_DEFAULT;
  const prs = [...snapshot.prs]
    .filter((pr) => pr.mergedAt >= since && pr.mergedAt < until)
    .sort((a, b) => a.number - b.number)
    .map((pr) => computePr(pr, until, snapshot.repo, snapshot.round_author ?? null));
  const lanes = {};
  for (const lane of LANES) {
    const total = { findings: 0, reposts: 0, outcomes: emptyOutcomes(), by_author: emptyByAuthor(), defer_unlinked: 0, resolved_unanswered: 0, inline_mismatch: 0, heads_reviewed: 0 };
    for (const pr of prs) {
      const one = pr.lanes[lane];
      for (const key of ["findings", "reposts", "defer_unlinked", "resolved_unanswered", "inline_mismatch", "heads_reviewed"]) total[key] += one[key];
      for (const bucket of BUCKETS) total.outcomes[bucket] += one.outcomes[bucket];
      for (const kind of AUTHOR_KINDS) for (const bucket of ANSWERED) total.by_author[kind].outcomes[bucket] += one.by_author[kind].outcomes[bucket];
    }
    lanes[lane] = finish(total);
  }
  const roundStats = (values) => ({
    prs: values.filter((v) => v !== null && v > 0).length,
    never_clean: values.filter((v) => v === null).length,
    unreviewed: values.filter((v) => v === 0).length,
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
      lane_review_rounds: Object.fromEntries(LANES.map((lane) => [lane, roundStats(prs.map((pr) => pr.lane_review_rounds[lane]))])),
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
  out.push("");
  for (const [lane, s] of Object.entries(result.lanes)) {
    out.push(`- ${lane}: ${s.resolved_unanswered} unanswered on a resolved thread, ${s.defer_unlinked} defers citing no newer item, ${s.inline_mismatch} heads whose inline count differs from the lane's`);
  }
  out.push(
    "",
    "By who answered (agent-labeled precision is an upper bound: the answering agent judged the finding):",
    "",
    "| Lane | Answered by | valid-fixed | valid-follow-up | intentional | incorrect | uncertain | Precision (n labeled) | answered-unlabeled |",
    "|---|---|---|---|---|---|---|---|---|",
  );
  for (const [lane, s] of Object.entries(result.lanes)) {
    for (const [kind, k] of Object.entries(s.by_author)) {
      const o = k.outcomes;
      if (k.labeled + o["answered-unlabeled"] === 0) continue;
      out.push(`| ${lane} | ${kind} | ${o["valid-fixed"]} | ${o["valid-follow-up"]} | ${o.intentional} | ${o.incorrect} | ${o.uncertain} | ${pct(k.precision)} (${k.labeled}) | ${o["answered-unlabeled"]} |`);
    }
  }
  const r = result.rounds;
  out.push("", `Rounds to pass, against the cap of ${r.cap} (${r.cap_source}):`, "");
  for (const [lane, s] of Object.entries(r.lane_review_rounds)) {
    out.push(`- ${lane} lane_review_rounds: ${s.prs} PRs reached a clean head, ${s.over_cap} over the cap, ${s.never_clean} never clean before merge, ${s.unreviewed} unreviewed`);
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
        number createdAt mergedAt updatedAt
        reviewThreads(first:100) {
          pageInfo { hasNextPage }
          nodes {
            path line originalLine isResolved
            comments(first:50) {
              pageInfo { hasNextPage }
              nodes { databaseId createdAt author { __typename login } body originalCommit { oid } replyTo { databaseId } }
            }
          }
        }
        comments(first:100) {
          pageInfo { hasNextPage }
          nodes { createdAt author { __typename login } body userContentEdits(first:100) { totalCount nodes { editedAt diff } } }
        }
      }
    }
  }
}`;

// The lane reviews one comment records: its body when never edited, else each edit's full text
// (the newest edit is the current body). One entry per version that carries the marker and counts.
export function reviewsOf(comment) {
  const edits = comment.userContentEdits?.nodes ?? [];
  const versions = edits.length ? edits.map((e) => ({ at: e.editedAt, text: e.diff ?? "" })) : [{ at: comment.createdAt, text: comment.body ?? "" }];
  const out = [];
  for (const { at, text } of versions) {
    const head = REVIEWED_HEAD.exec(text);
    const counts = COUNTS.exec(text);
    if (head && counts) out.push({ lane: head[1], sha: head[2], at, findings: Number(counts[1]), inline: Number(counts[2]) });
  }
  return out;
}

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
      const reviews = [];
      for (const c of pr.comments.nodes) {
        const found = reviewsOf(c);
        if (found.length && c.userContentEdits.totalCount > c.userContentEdits.nodes.length) truncated.push(`PR ${pr.number}: a lane comment with more than 100 edits`);
        reviews.push(...found.filter((r) => r.at < until));
      }
      prs.push({
        number: pr.number,
        createdAt: pr.createdAt,
        mergedAt: pr.mergedAt,
        threads: pr.reviewThreads.nodes.map((t) => {
          if (t.comments.pageInfo.hasNextPage) truncated.push(`PR ${pr.number}: a thread with more than 50 comments`);
          return {
            path: t.path,
            line: t.line ?? null,
            originalLine: t.originalLine ?? null,
            resolved: t.isResolved === true,
            comments: t.comments.nodes
              .filter((c) => c.createdAt < until)
              .map((c) => ({ id: c.databaseId, author: c.author?.login ?? null, author_kind: authorKind(c.author?.__typename, c.body), createdAt: c.createdAt, body: c.body, commit: c.originalCommit?.oid ?? null, replyTo: c.replyTo?.databaseId ?? null })),
          };
        }),
        comments: pr.comments.nodes.filter((c) => c.createdAt < until).map((c) => ({ author: c.author?.login ?? null, author_kind: authorKind(c.author?.__typename, c.body), createdAt: c.createdAt, body: c.body })),
        reviews: reviews.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : a.lane < b.lane ? -1 : a.lane > b.lane ? 1 : a.sha < b.sha ? -1 : 1)),
      });
    }
    const last = page.nodes.at(-1);
    if (!page.pageInfo.hasNextPage || !last || last.updatedAt < since) break;
    cursor = page.pageInfo.endCursor;
  }
  return prs;
}

const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");

// The round cap and the lanes App login from docs/conventions/pr-pipeline.yaml, read once.
function fetchPipeline(repo) {
  let yaml = "";
  try {
    yaml = gh(["api", "-H", "Accept: application/vnd.github.raw", `repos/${repo}/contents/docs/conventions/pr-pipeline.yaml`]);
  } catch (error) {
    if (error instanceof RateLimited) throw error;
  }
  const cap = /^loop:\n(?:[ \t]+.*\n|\s*\n)*?[ \t]+review-rounds: (\d+)/m.exec(yaml);
  const identity = /^merge:\n(?:[ \t]+.*\n|\s*\n)*?[ \t]+agent-identity: (\S+)/m.exec(yaml);
  return {
    rounds_cap: cap ? { value: Number(cap[1]), source: CAP_SOURCE } : { value: CAP_DEFAULT, source: `${CAP_SOURCE} (unread; the default from that key)` },
    round_author: identity ? identity[1] : null,
  };
}

export function fetchSnapshot({ repo, since, until }) {
  const truncated = [];
  const { rounds_cap, round_author } = fetchPipeline(repo);
  const prs = fetchPrs(repo, since, until, truncated);
  console.error(`review-precision: ${prs.length} merged PRs in the window`);
  prs.sort((a, b) => a.number - b.number);
  return { schema: 3, repo, window: { since, until }, earliest_supported: EARLIEST_SUPPORTED, rounds_cap, round_author, truncated, prs };
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
    throw new UsageError(`windows before ${EARLIEST_SUPPORTED} are not supported: the lanes did not post the current reviewed-head comment and footer format`);
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
