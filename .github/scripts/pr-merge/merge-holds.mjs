#!/usr/bin/env node
// merge-holds.mjs: the merge holds a pull request's own text carries, by the
// rules pr-merge's gate reads them. enable-auto-merge.mjs arms nothing they
// hold, and ci-status runs this file alone, fetched from the base commit, on
// every lanes App pull request, so it imports no other file of the repository.
//
// - A body hold (babysit_merge_policy.BODY_MERGE_HOLD_RE): a line opening with
//   `Hold:`, or "do not merge" anywhere, in a body a person wrote
//   (personWrote), or the lane's own hold line (LANE_HOLD, report-outcome's
//   HOLD_LINE for untrusted-provenance work, a person's `merge: human` and a
//   denied path) in any body. Other lanes App text holds nothing. Removing
//   that text lifts it.
// - A member veto (babysit_merge.human_veto_logins): each OWNER, MEMBER or
//   COLLABORATOR person's newest comment, review or inline comment with text
//   decides, and holds when it says "do not merge"
//   (babysit_merge.HUMAN_MERGE_VETO_RE). A later one by the same person
//   lifts it; an item with no text lifts nothing.
// - A hold path: a changed file, or a renamed file's old path, matching the
//   config's merge.diff-check.denied-paths or HOLD_PATH_FLOOR (the floor's
//   `trust` and `gate` globs; its `enforcement` globs are the merge gate's,
//   which a clean security review clears). A person on the trusted-actor
//   list lifts it by approving the head (their newest review of the head
//   that approves, requests changes or was dismissed must approve), or by
//   approving an earlier head that carries to it (liftersOf): their newest
//   review approves that head, or is that approval GitHub dismissed as stale
//   on a later push (autoDismissed), and every change since is a merge of the
//   base that leaves the net change against the base's tip the same over
//   every file, or that brought exactly the base's changes (approvalCarry).
//   No other path is held for being trusted alone: the review lanes judge it.
// - A trusted-actor list widening (actorsHold, the rule of
//   babysit_risk._actors_widened): TRUSTED_ACTORS_PATH read at the base commit
//   (BASE_SHA) and the head and compared; only removing entries passes. The
//   approval that lifts a hold path lifts it.
// - A cost path (COST_PATHS): a changed file the gate holds for the owner's
//   cost decision. An approval does not lift it; only the decision the gate
//   reads does (costDecision), linked from the body: on the pull request, or
//   on its linked issue naming it, for the head it decided or a later one
//   whose every change since is a base merge with the same net change
//   (baseMergeCarry).
// - No verifier pass, when a verdicts file is given (ci-status gives one in
//   the merge queue only): the head merges on a PASS or PASS-NOTES that
//   pr-verify.yml uploaded from a completed, successful run on main
//   (verdictHold). The same approval of the head lifts it, the human merge
//   path for a pull request pr-merge's gate sends to a person; an approval
//   carried from an earlier head does not.
// - A FAIL the gate's reader counts, when an evidence file is given with the
//   verdicts: babysit_verify_evidence.py `evidence`'s report for the head,
//   which ci-status runs from main's checkout in the merge queue
//   (evidenceHold). It holds on every refusal but the three a pass decides
//   (verify:missing, verify:spec-changed, verify:untrusted-spec, which
//   verdictHold and linkHold judge here): the FAIL classes, verify:unreadable,
//   verify:too-old and any refusal this module does not know. A report that
//   does not read, or is for another head, holds. The same approval lifts it.
// - A changed issue link, when a link file is given with the verdicts: the
//   pass binds only while the live link is the one its verdict judged
//   (linkHold), as pr-merge's reader binds it (babysit_verify_evidence.py
//   `_pass_refusal`), so a body edited after arming to close or name another
//   issue does not merge on a pass for the old one. The same approval lifts it.
//
// Command line: merge-holds.mjs <number> <body-file> <discussion-file>
// <files-file> <denied-paths-file> <trusted-actors-file> <head-sha>
// [<verdicts-file> <link-file> [<evidence-file>]]. The link file holds {record, closing}: the
// verdict.json of the pass verdictHold counts (null when none was read) and
// the pull request's closingIssuesReferences (totalCount, nodes with number
// and repository.nameWithOwner). The verdicts file holds one {name, verdict, runId, run}
// per line, run as GET actions/runs/{runId} gives it, for each unexpired artifact
// named a pass at the head; GITHUB_REPOSITORY names the repository. The
// evidence file holds the reader's one JSON line (Evidence.report); with
// verdicts and no evidence file, the FAIL check holds as unreadable. The
// discussion file holds one REST issue comment, review or review comment per
// line; the files file one changed file per line, its path, renamed-from
// path and status (changeOf); the denied-paths file the config's
// merge.diff-check.denied-paths as JSON; the trusted-actors file
// trusted-actors.json. PATH_HOLDS "false" turns the hold paths off
// (pathHoldsOf). Each hold prints as an ::error:: and exits 1; no hold
// exits 0. Who wrote a body that holds, a changed trusted-actor list, a
// cost path with a decision link in the body, and the approvals of earlier
// heads when no approval of the head lifts a hold path, are read with
// GH_TOKEN.
import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";
import { posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// enable-auto-merge.test.mjs checks both agree with the gate's Python on every
// text it tries.
export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
// "the do-not-merge label" (backticks allowed) names the label and vetoes
// nothing. Any other do-not-merge vetoes: a comma list cannot be told from a
// comma clause, so it fails closed.
export const HUMAN_VETO =
  /\bdo(?:n['’]?t| not)[\s-]*merge\b|\bdo-not(?!-merge\b)[\s-]*merge\b|(?<!the )(?<!the `)\bdo-not-merge\b|(?<=the )do-not-merge\b(?!\s*labels?\b)|(?<=the `)do-not-merge\b(?!`\s*labels?\b)/i;
// The lanes App's bot login. A `Hold:` line on its own pull request holds the
// merge, not a fix pushed to it (apply-patch.mjs's held()).
export const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
// report-outcome.mjs HOLD_LINE on a line of its own, which
// enable-auto-merge.test.mjs checks; it holds whoever wrote the body.
export const LANE_HOLD = /(?:^|[\r\n])Hold: a human merges this[^\S\r\n]*(?:[\r\n]|$)/;
// Whether `body` holds: the lane's hold line, or hold text a person wrote.
export const bodyHolds = (body, byPerson) => LANE_HOLD.test(String(body ?? "")) || (byPerson && BODY_HOLD.test(String(body ?? "")));

// babysit_merge_policy.refs_issue, which test_verify_rules_sync.py keeps equal:
// the one issue the visible `Refs: #<n>` lines of a pull request body name,
// else null. A line counts only from its first column, outside an HTML comment
// and a fenced code block; a `Refs:` line in any other form, or two numbers,
// name none.
const HTML_COMMENT = /<!--[\s\S]*?(?:-->|$)/g;
const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const REFS_LINE = /^[Rr][Ee][Ff][Ss]:/;
const REFS_PLAIN = /^Refs:[ \t]*#([1-9][0-9]{0,8})[ \t]*$/;
export function refsIssue(body) {
  const numbers = refsNumbers(body);
  return numbers?.size === 1 ? [...numbers][0] : null;
}

// The issues the visible plain `Refs: #<n>` lines of `body` name, as
// refsIssue reads them, or null when such a line is in any other form.
function refsNumbers(body) {
  const numbers = new Set();
  let fence = "";
  for (const line of String(body ?? "").replace(HTML_COMMENT, "").split(/\r\n|\r|\n/)) {
    const marker = FENCE.exec(line);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && line.slice(marker[0].length).replace(/[ \t]/g, "") === "") {
        fence = "";
      }
      continue;
    }
    if (marker) {
      fence = marker[1];
      continue;
    }
    if (!REFS_LINE.test(line)) {
      continue;
    }
    const plain = REFS_PLAIN.exec(line);
    if (!plain) {
      return null;
    }
    numbers.add(Number(plain[1]));
  }
  return numbers;
}

// Why the pass `record` (its verdict.json) does not bind the pull request's
// live link, or null when it does. The live link is its closing issues in
// `repo`, or, with no closing issue at all, the one issue its plain `Refs:`
// lines name (refsNumbers). The pass binds unless the live link drops the
// issue it judged (a link removed, or closing issues all in another
// repository, drop it), or names that issue linked another way (its
// `spec_kind`, `closes` when absent, as the reader reads an older record). A
// link of several issues that still names the judged one binds: the fix loop
// rewrites it.
export function linkHold(record, body, closing, repo) {
  if (record === null || typeof record !== "object" || !Array.isArray(record.linked_issues)) {
    return "its verifier pass's record could not be read";
  }
  const kind = record.spec_kind ?? "closes";
  if (!["closes", "refs"].includes(kind)) {
    return `its verifier pass judged a spec of kind '${String(kind)}', not a linked issue`;
  }
  if (!Array.isArray(closing?.nodes) || !Number.isSafeInteger(closing.totalCount) || closing.totalCount !== closing.nodes.length) {
    return "its closing issues could not be read";
  }
  const own = (issue) => String(issue?.repository?.nameWithOwner).toLowerCase() === String(repo).toLowerCase();
  const linked = closing.totalCount > 0 ? "closes" : "refs";
  const live = linked === "closes" ? closing.nodes.filter(own).map((issue) => issue.number) : [...(refsNumbers(body) ?? [])];
  const judged = record.linked_issues.map((issue) => issue?.number);
  const [only] = judged;
  if (judged.length !== 1 || !live.includes(only) || kind !== linked) {
    const named = linked === "closes" ? closing.nodes.map((issue) => `${own(issue) ? "" : issue?.repository?.nameWithOwner}#${issue?.number}`) : live.map((n) => `#${n}`);
    return `its link changed since pr-verify passed it: it ${linked} ${named.join(", ") || "no issue"}, and the pass judged ${judged.map((n) => `#${n}`).join(", ") || "no issue"} (${kind})`;
  }
  return null;
}
// babysit_merge_policy.BLOCKER_ASSOCIATIONS.
const MEMBERS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);

// The pull request's author and the editors of its body, for personWrote.
export const BODY_WRITERS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { author { __typename } userContentEdits(first: 100) { totalCount nodes { editor { __typename } } } }
  }
}`;

// Whether a person wrote any of the body of `pull` (BODY_WRITERS_QUERY's
// pullRequest, or a listing's with the same fields): its author or an editor
// of its body is not a Bot account. A deleted account, an edit list not read
// whole or a pull request that did not read counts as a person, so a hold an
// unknown hand wrote still holds.
export function personWrote(pull) {
  const edits = pull?.userContentEdits;
  if (!pull?.author || !Array.isArray(edits?.nodes) || !(edits.totalCount <= edits.nodes.length)) {
    return true;
  }
  return [pull.author, ...edits.nodes.map((edit) => edit?.editor)].some((who) => who?.__typename !== "Bot");
}

// babysit_risk.COST_PATHS, matched case-folded as its glob_match does. Each
// one is a real charge.
export const COST_PATHS = Object.freeze([
  // BEGIN hold-floor COST_PATHS: generated by scripts/sync-hold-floor.py
  "**/Pulumi.yaml",
  "**/Pulumi.yml",
  "**/Pulumi.json",
  "**/Pulumi.*.yaml",
  "**/Pulumi.*.yml",
  "**/Pulumi.*.json",
  "**/*.tf",
  "**/*.tf.json",
  "**/*.tfvars",
  "**/*.tfvars.json",
  "**/*.bicep",
  "**/*.bicepparam",
  "**/azuredeploy.json",
  "**/azuredeploy.*.json",
  "**/*.azuredeploy.json",
  "**/*.azuredeploy.*.json",
  // END hold-floor COST_PATHS
]);

// The members whose newest item with text vetoes the merge, sorted. Each item
// is { login, isUser, association, at, body }, `at` an ISO 8601 UTC time.
export function vetoers(items) {
  const newest = new Map();
  for (const { login, isUser, association, at, body } of items) {
    if (!isUser || !MEMBERS.has(String(association).toUpperCase()) || !String(body ?? "").trim()) {
      continue;
    }
    if (!newest.has(login) || at >= newest.get(login).at) {
      newest.set(login, { at, body: String(body) });
    }
  }
  return [...newest]
    .filter(([, { body }]) => HUMAN_VETO.test(body))
    .map(([login]) => login)
    .sort();
}

// One REST issue comment, review or review comment as a vetoers item.
export const fromRest = (row) => ({
  id: row?.id,
  login: String(row?.user?.login ?? ""),
  userId: row?.user?.id,
  state: row?.state,
  commitId: row?.commit_id,
  isUser: row?.user?.type === "User",
  association: row?.author_association,
  at: String(row?.submitted_at ?? row?.created_at ?? ""),
  body: String(row?.body ?? ""),
});

// Whether `path` matches the hold-path `glob`, case-folded as glob_match
// folds it: a lane host on a case-insensitive filesystem reads `.github/codeowners`
// as CODEOWNERS. path.matchesGlob has no `dot` option, so `*` and `**` skip a
// segment opening with "."; both sides mark such a segment alike first, so
// `.github/**` holds `.github/a/.x` too.
const undot = (text) => String(text).toLowerCase().replaceAll(/(^|\/)\./g, "$1\u0001");
export const matchesHoldPath = (path, glob) => posix.matchesGlob(undot(path), undot(glob));

// The narrow floor every hold path check adds to the configured globs, each
// glob with its class (owner decisions Q-FLOOR (B), Q-ENFORCE (A) and Q26
// option B): `trust`, what mints and scopes lane tokens and judges triggers
// (request-lane-token, resolve-config with the rule files the token broker
// loads, the pipeline config, check-trusted-trigger, check-kill-switch), code
// owners, submodules, and the code that computes the author lift and the hold
// tables (babysit_merge*, babysit_risk.py and babysit_review_evidence.py,
// which compute the review's clear condition, this module, and
// scripts/sync-hold-floor.py, which writes this list); `gate`, the rest of the
// merge gate's own code (the other pr-merge scripts and the rate guard), and
// the review's own surface, which never takes the author lift: every workflow
// holding a secret or a lane token or granting `actions: write`, the review
// workflows and ci-status among them, the main-run review's scripts, and the
// agent settings and instruction files; `enforcement`, the other modules the
// floored scripts import and the Python that decides the holds
// (test_merge_holds_sync.py derives both closures and requires them here),
// and the scripts that act on a pr-unblock stop's route (report-escalation.sh,
// adjudicate-feedback.mjs, publish-feedback.mjs, apply-patch.mjs) with every
// module they import and the routing table they read.
// the floor, written here by scripts/sync-hold-floor.py. A
// constant of the module ci-status and enable-auto-merge run from the base
// commit, so a pull request cannot rewrite it.
export const HOLD_PATH_CLASSES = Object.freeze([
  // BEGIN hold-floor HOLD_PATH_CLASSES: generated by scripts/sync-hold-floor.py
  ["**/CODEOWNERS", "trust"],
  ["docs/conventions/pr-pipeline.yaml", "trust"],
  ["**/.gitmodules", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_check_inputs.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_checks.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_classify.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_feedback.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_repo_config.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_review_trigger.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_run_cache.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_state.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_tracker_binding.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_util.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py", "enforcement"],
  ["**/.claude/**", "gate"],
  ["**/.claude-lane/**", "gate"],
  ["**/.mcp.json", "gate"],
  ["**/CLAUDE.md", "gate"],
  ["**/CLAUDE.local.md", "gate"],
  ["**/AGENTS.md", "gate"],
  ["REVIEW.md", "gate"],
  [".github/actions/check-trusted-trigger/**", "trust"],
  [".github/actions/resolve-config/**", "trust"],
  [".github/actions/check-kill-switch/**", "trust"],
  [".github/actions/request-lane-token/**", "trust"],
  [".github/actions/log-api-budget/rate-guard.mjs", "gate"],
  [".github/actions/log-api-budget/rate-limits.json", "gate"],
  [".github/scripts/pr-merge/merge-holds.mjs", "trust"],
  [".github/scripts/pr-merge/enable-auto-merge.mjs", "trust"],
  [".github/scripts/pr-merge/superseded.mjs", "trust"],
  [".github/scripts/pr-merge/clear-escalations.mjs", "trust"],
  [".github/scripts/pr-merge/carry-run-cache.mjs", "gate"],
  [".github/scripts/pr-merge/gate-check.mjs", "trust"],
  [".github/scripts/pr-merge/head-ref-map.mjs", "trust"],
  [".github/scripts/pr-merge/lane-records.mjs", "gate"],
  [".github/scripts/pr-merge/last-report.mjs", "gate"],
  [".github/scripts/pr-merge/rate-stop.bash", "gate"],
  [".github/scripts/pr-merge/retry-call.bash", "gate"],
  [".github/scripts/pr-merge/refire-refused.mjs", "gate"],
  [".github/scripts/pr-merge/rotation.mjs", "gate"],
  [".github/scripts/pr-merge/sweep-summary.mjs", "gate"],
  [".github/scripts/pr-merge/who.mjs", "gate"],
  [".github/scripts/pr-merge/post-unarmed-status.mjs", "gate"],
  [".github/scripts/pr-merge/verify-answers.mjs", "gate"],
  [".github/scripts/pr-merge/listing-carry.mjs", "gate"],
  [".github/actions/report-check-run/posting-run.mjs", "gate"],
  ["scripts/sync-hold-floor.py", "trust"],
  [".github/scripts/pr-unblock/address-feedback.mjs", "enforcement"],
  [".github/scripts/pr-unblock/escalation-routes.mjs", "enforcement"],
  [".github/scripts/pr-unblock/escalation-routes.json", "enforcement"],
  [".github/scripts/pr-unblock/gate-source.mjs", "enforcement"],
  [".github/scripts/pr-unblock/thread-scope.mjs", "enforcement"],
  [".github/scripts/pr-unblock/retry-fetch.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/report-outcome.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/limits.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/retry-fetch.mjs", "enforcement"],
  [".github/scripts/pr-unblock/report-escalation.sh", "enforcement"],
  [".github/scripts/pr-unblock/adjudicate-feedback.mjs", "enforcement"],
  [".github/scripts/pr-unblock/publish-feedback.mjs", "enforcement"],
  [".github/scripts/pr-unblock/request-budget.mjs", "enforcement"],
  [".github/scripts/pr-verify/resolve-pr.mjs", "enforcement"],
  [".github/scripts/pr-verify/write-verdict.mjs", "enforcement"],
  [".github/scripts/intake-triage/admit.mjs", "enforcement"],
  [".github/actions/select-trusted-text/select-trusted-text.mjs", "enforcement"],
  ["lib/publish-gate.mjs", "enforcement"],
  [".github/recurring-schedule.json", "enforcement"],
  ["plugins/work-items/scripts/charge-words.json", "enforcement"],
  [".github/scripts/pr-unblock/dependency-classify.mjs", "enforcement"],
  [".github/scripts/apply-patch/apply-patch.mjs", "enforcement"],
  [".github/scripts/apply-patch/predicates.mjs", "enforcement"],
  [".github/scripts/apply-patch/protected-paths.mjs", "enforcement"],
  [".github/scripts/apply-patch/retry-fetch.mjs", "enforcement"],
  [".github/scripts/pr-unblock/fix-ci-context.mjs", "enforcement"],
  [".github/scripts/pr-unblock/feedback-dispatch.mjs", "enforcement"],
  [".github/scripts/pr-unblock/verify-notes.mjs", "enforcement"],
  [".github/scripts/pr-unblock/limit-stop.mjs", "enforcement"],
  [".github/scripts/pr-unblock/dispatch-record.mjs", "enforcement"],
  [".github/scripts/pr-unblock/verify-cap.mjs", "enforcement"],
  [".github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/stop-routes.json", "enforcement"],
  [".github/scripts/work-resolve-issue/stop-routes.mjs", "enforcement"],
  [".github/scripts/lib/stop-reason.mjs", "enforcement"],
  [".github/scripts/lib/admission-comment.mjs", "enforcement"],
  [".github/scripts/lib/done-evidence.mjs", "trust"],
  [".github/scripts/pr-review-main/**", "gate"],
  ["docs/conventions/instruction-exception-register/**", "gate"],
  ["docs/conventions/untrusted-content/**", "gate"],
  ["docs/standards/**", "gate"],
  [".github/workflows/dependabot-fragments.yml", "gate"],
  [".github/workflows/eval-browser-dispatch.yml", "gate"],
  [".github/workflows/intake-reenter.yml", "gate"],
  [".github/workflows/intake-triage.yml", "gate"],
  [".github/workflows/maintenance-audit-lane-runs.yml", "gate"],
  [".github/workflows/maintenance-reconcile-lost-runs.yml", "gate"],
  [".github/workflows/post-merge-demotion-alert.yml", "gate"],
  [".github/workflows/post-merge-test-mutation.yml", "gate"],
  [".github/workflows/pr-feedback-dispatch.yml", "gate"],
  [".github/workflows/pr-merge.yml", "gate"],
  [".github/workflows/pr-refine.yml", "gate"],
  [".github/workflows/pr-require-checks.yml", "gate"],
  [".github/workflows/pr-review-approved.yml", "gate"],
  [".github/workflows/pr-review-hosted.yml", "gate"],
  [".github/workflows/pr-review-main.yml", "gate"],
  [".github/workflows/pr-review-security-hosted.yml", "gate"],
  [".github/workflows/pr-run-activity-read.yml", "gate"],
  [".github/workflows/pr-run-activity-write.yml", "gate"],
  [".github/workflows/pr-unblock-dispatch.yml", "gate"],
  [".github/workflows/pr-unblock.yml", "gate"],
  [".github/workflows/pr-verify.yml", "gate"],
  [".github/workflows/release-publish-plugins.yml", "gate"],
  [".github/workflows/work-resolve-issue.yml", "gate"],
  [".github/workflows/work-unblock.yml", "gate"],
  // END hold-floor HOLD_PATH_CLASSES
]);
// The `trust` and `gate` globs (babysit_risk `Floor.high`), which hold for a
// person. An `enforcement` glob (`Floor.review`) holds nothing here: the merge
// gate holds it (babysit_risk `review-path:`) until a clean security review
// binds to the head, and enable-auto-merge arms only a head the gate passed.
export const HOLD_PATH_FLOOR = Object.freeze(HOLD_PATH_CLASSES.filter(([, kind]) => kind !== "enforcement").map(([glob]) => glob));
export const REVIEW_FLOOR = Object.freeze(HOLD_PATH_CLASSES.filter(([, kind]) => kind === "enforcement").map(([glob]) => glob));

// Why the head's changed `files` hold it, or null: one matching `holdPaths`
// or HOLD_PATH_FLOOR. Null `holdPaths` or `files` (unreadable) holds it.
// `on` false (pathHoldsOf) matches no hold path.
export const pathHold = (files, holdPaths, on = true) => pathHoldKind(files, holdPaths, on)?.reason ?? null;

// merge.diff-check.path-holds (owner decision Q15): absent or false, no
// changed path holds for its path alone; any other value keeps every hold
// path, as babysit_merge_policy's switch() reads it.
export const pathHoldsOf = (value) => ![undefined, null, false, "false"].includes(value);

// The switch from a resolve-config output file; unreadable keeps the holds.
export function readPathHolds(path) {
  try {
    return pathHoldsOf(JSON.parse(readFileSync(path, "utf8"))?.merge?.["diff-check"]?.["path-holds"]);
  } catch {
    return true;
  }
}

// pathHold's answer with its kind: `hold-path` for a changed file a hold
// path matches, `unread` for a list that could not be read or checked.
// With `on` false a readable list matches nothing.
export function pathHoldKind(files, holdPaths, on = true) {
  if (!Array.isArray(holdPaths)) {
    return { kind: "unread", reason: "the hold paths could not be read" };
  }
  if (!Array.isArray(files)) {
    return { kind: "unread", reason: "its changed files could not all be read" };
  }
  if (typeof posix.matchesGlob !== "function") {
    return { kind: "unread", reason: "this Node has no path.matchesGlob, so its hold paths cannot be checked" };
  }
  if (on === false) {
    return null;
  }
  const globs = [...holdPaths, ...HOLD_PATH_FLOOR];
  const held = files.find((path) => globs.some((glob) => matchesHoldPath(path, glob)));
  return held === undefined ? null : { kind: "hold-path", reason: `it changes ${held}, a hold path` };
}

// Why the changed `files` hold it for the owner's cost decision, or null when
// none is a cost path or `decision` (costDecision's link) clears it. As
// glob_match does, a glob also covers everything under it, and `*` matches a
// segment's leading "." (so `*.tf` holds `.tf`).
export function costHold(files, decision) {
  const held = (Array.isArray(files) ? files : []).find((path) => {
    const folded = String(path).toLowerCase().replaceAll(/(^|\/)\./g, "$1\u0001.");
    return COST_PATHS.some((glob) => [glob, `${glob}/**`].some((each) => posix.matchesGlob(folded, each.toLowerCase())));
  });
  return held === undefined || decision ? null : `it changes ${held}, a cost path`;
}

// babysit_risk._manifest: the parsed object as a node tree, or null when the
// text is not a string, not JSON, not an object, or repeats a key. A node is
// { object: Map }, { array: [] } or { text }, a scalar's text telling values
// apart as Python's json.loads does: an integer and a float differ (1 and
// 1.0), so canonical (json.dumps with sort_keys) compares them as the gate.
function parseStrict(text) {
  if (typeof text !== "string") {
    return null;
  }
  try {
    JSON.parse(text);
  } catch {
    return null;
  }
  // The text is valid JSON, so the walk below needs no error handling.
  let at = 0;
  const space = () => {
    while (" \t\n\r".includes(text[at] ?? "x")) at += 1;
  };
  const string = () => {
    const start = at;
    for (at += 1; text[at] !== '"'; at += 1) {
      if (text[at] === "\\") at += 1;
    }
    at += 1;
    return JSON.parse(text.slice(start, at));
  };
  const items = (close, read) => {
    at += 1;
    for (space(); text[at] !== close; space()) {
      read();
      space();
      if (text[at] === ",") at += 1;
    }
    at += 1;
  };
  const value = () => {
    space();
    if (text[at] === "{") {
      const object = new Map();
      items("}", () => {
        const key = string();
        if (object.has(key)) throw new Error("duplicate key");
        space();
        at += 1;
        object.set(key, value());
      });
      return { object };
    }
    if (text[at] === "[") {
      const array = [];
      items("]", () => array.push(value()));
      return { array };
    }
    if (text[at] === '"') return { text: JSON.stringify(string()), string: true };
    const token = /^(?:true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(at))[0];
    at += token.length;
    if (!/^-?\d/.test(token)) return { text: token };
    if (!/[.eE]/.test(token)) {
      // json.loads refuses an integer past int_max_str_digits (4300), so the
      // gate reads that side as malformed.
      if (token.replace("-", "").length > 4300) throw new Error("integer too long");
      return { text: `${BigInt(token)}` };
    }
    const number = Number(token);
    return { text: `${Object.is(number, -0) ? "-0" : String(number)}.f` };
  };
  try {
    const root = value();
    return root.object ? root : null;
  } catch {
    return null;
  }
}

const canonical = (node) =>
  node.object
    ? `{${[...node.object]
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
        .map(([key, child]) => `${JSON.stringify(key)}:${canonical(child)}`)
        .join(",")}}`
    : node.array
      ? `[${node.array.map(canonical).join(",")}]`
      : node.text;
// babysit_risk.TRUSTED_ACTORS_PATH, matched case-folded as glob_match does.
export const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";

// babysit_risk._actors_widened: why one change of the trusted-actor list
// widens trust, or null when it only removes entries; test_merge_holds_sync.py
// checks the two agree. `change` is { status, previous, contents }, contents
// [base text, head text]. Anything but a file modified in place, a side that
// does not read or parse or repeats a key, an `actors` that is no list, or a
// change to any other key holds, and so does an entry added or changed.
export function actorsWidened({ status, previous = null, contents } = {}) {
  if (status !== "modified" || previous !== null) {
    return `${status ?? "unknown"} trusted-actor list`;
  }
  if (!Array.isArray(contents) || contents.length !== 2) {
    return "contents unreadable";
  }
  const [base, head] = contents.map(parseStrict);
  if (base === null || head === null) {
    return "unreadable, malformed or a repeated key";
  }
  const [old, now] = [base, head].map((node) => node.object.get("actors"));
  if (!old?.array || !now?.array) {
    return "actors is not a list";
  }
  const rest = (node) => canonical({ object: new Map([...node.object].filter(([key]) => key !== "actors")) });
  if (rest(base) !== rest(head)) {
    return "a key other than actors changed";
  }
  const gained = new Map();
  for (const [entries, step] of [[now.array, 1], [old.array, -1]]) {
    for (const entry of entries) {
      const key = canonical(entry);
      gained.set(key, (gained.get(key) ?? 0) + step);
    }
  }
  const added = [...gained].filter(([, n]) => n > 0).map(([key]) => key).sort();
  return added.length ? `entries added or changed: ${added.join(", ")}` : null;
}

// Why the changes (changeOf's, with withActorContents's contents) widen the
// trusted-actor list, or null. A change whose path or renamed-from path is the
// list counts.
export function actorsHold(changes) {
  if (!Array.isArray(changes)) {
    return "its changed files could not all be read";
  }
  const found = changes
    .filter(({ path, previous }) => [path, previous].some((each) => each != null && matchesHoldPath(each, TRUSTED_ACTORS_PATH)))
    .map((change) => [change.path, actorsWidened(change)])
    .filter(([, why]) => why);
  return found.length ? `it widens the trusted-actor list (${found.map(([path, why]) => `${path}: ${why}`).join("; ")})` : null;
}

// `changes` with the trusted-actor list's [base text at `base`, head text at
// `head`] on a change that modifies it in place; a read that fails, or a base
// that is not a commit SHA, leaves its contents out, so it holds.
export async function withActorContents(github, repo, changes, base, head) {
  const text = async (path, ref) => {
    const file = await github("GET", `/repos/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${ref}`);
    if (file?.type !== "file" || file.encoding !== "base64" || typeof file.content !== "string") {
      throw new Error(`${path} at ${ref} did not read`);
    }
    // Strict, as the gate's decode("utf-8"): invalid UTF-8 throws, so it
    // holds, and a BOM stays, so the parse refuses it as json.loads does.
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.from(file.content, "base64"));
  };
  return Promise.all(
    changes.map(async (change) => {
      if (!matchesHoldPath(change.path, TRUSTED_ACTORS_PATH) || change.status !== "modified" || change.previous !== null || !/^[0-9a-f]{40}$/.test(String(base))) {
        return change;
      }
      try {
        return { ...change, contents: [await text(change.path, base), await text(change.path, head)] };
      } catch {
        return change;
      }
    }),
  );
}

// babysit_merge_policy COST_DECISION_LINK, DECISION_LINE and HTML_COMMENT.
const DECISION_LINK = /https:\/\/github\.com\/([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)\/(?:issues|pull)\/([0-9]+)#issuecomment-([0-9]+)/g;
const DECISION_LINE = /^\*\*Decision recorded\.\*\*[ \t]+Cost:/;
export const PULL_OPENED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { createdAt baseRefName headRefName closingIssuesReferences(first: 2) { totalCount nodes { number repository { nameWithOwner } } } }
  }
}`;
export const COMMENT_EDITED_QUERY = "query($id: ID!) { node(id: $id) { ... on IssueComment { lastEditedAt } } }";

// Whether `text` names pull request `number` as `#<number>`: not part of a
// longer number, and not after a letter, digit, `_`, `#`, `&`, `/`, `.` or
// `-`, so neither `owner/repo#<number>` nor `&#<number>` counts
// (babysit_merge_policy.names_pull; the review lanes' hold step excludes the
// same characters but `.` and `-`).
export function namesPull(text, number) {
  return Number.isSafeInteger(number) && new RegExp(`(?:^|[^A-Za-z0-9_#&/.-])#${number}(?:[^0-9]|$)`).test(String(text ?? ""));
}

// The review lanes whose status job records a `claude-lane-hold` notice, as
// [workflow file, status job name] (ci-status's cost-hold step reads the same
// two). The notice's head and criteria, and the base branch name a compare
// takes, as the hold step reads it.
export const REVIEW_LANES = [
  ["pr-review-hosted.yml", "pr-review / claude-review-status"],
  ["pr-review-security-hosted.yml", "pr-review-security / security-review"],
];
const HOLD_NOTICE = /^claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=([a-z,-]+) label=/;
const BRANCH = /^(?!-)(?!.*\.\.)[A-Za-z0-9._/-]{1,255}$/;

// Why a compare answer (base...head) shows a head whose lane runs cannot be
// trusted, else null: it changes a review-lane workflow, which a
// pull_request run takes from the head and so could write the notice, or it
// lists 300 files or more (the compare API's cap), or no file list.
export function laneChange(compare) {
  const files = compare?.files;
  if (!Array.isArray(files)) return "no file list";
  if (files.length >= 300) return "too many files";
  const lanes = REVIEW_LANES.map(([file]) => `.github/workflows/${file}`);
  return files.some((f) => lanes.includes(f?.filename)) ? "a review-lane workflow" : null;
}

// The cost hold notices among one status job's `annotations`, as { sha, at }
// with `at` the job's completion: only those naming `head`, the head its run
// ran on, so a notice can speak for no other commit.
export function costNotices(annotations, head, at) {
  return (Array.isArray(annotations) ? annotations : []).flatMap((a) => {
    const notice = a?.annotation_level === "notice" ? HOLD_NOTICE.exec(String(a.message ?? "")) : null;
    return notice && notice[1] === head && notice[2].split(",").includes("cost") ? [{ sha: notice[1], at }] : [];
  });
}

// The decided head: the sha of the newest of `notices` before `at`, else
// null; null too when two heads share that time
// (babysit_merge_policy.decided_head, and ci-status's cost-hold step).
export function decidedHead(notices, at) {
  const cutoff = Date.parse(at);
  const before = notices.filter((n) => Date.parse(n.at) < cutoff);
  const newest = Math.max(...before.map((n) => Date.parse(n.at)));
  const heads = new Set(before.filter((n) => Date.parse(n.at) === newest).map((n) => n.sha));
  return heads.size === 1 ? [...heads][0] : null;
}

// Why the head branch's push history shows a lane run missing before a
// decision made at `at`, else null (babysit_merge_policy.unran_head, and
// ci-status's cost-hold step). `activity` is the repository activity API for
// the branch read to its end (branchActivity), newest first, which deleting a
// run leaves; `ran` lists, per REVIEW_LANES entry, the heads of its runs
// started before `at`. Every head the branch moved to after its last push of
// `decided` before `at` needs a run of every lane: with one deleted, an older
// notice would become the decided head (#10437). No push of `decided` before
// `at` keeps the hold too.
export function unranHead(activity, ran, decided, at) {
  if (!Array.isArray(activity)) {
    return "the branch's push history is unreadable";
  }
  if (!Array.isArray(ran) || ran.length !== REVIEW_LANES.length || !ran.every(Array.isArray)) {
    return "the lane runs do not cover every review lane";
  }
  const moves = [];
  for (const move of activity) {
    const after = String(move?.after ?? "");
    if (/^[0-9a-f]{40}$/.test(after) && !/^0{40}$/.test(after)) {
      const made = Date.parse(move.timestamp);
      if (!Number.isFinite(made)) {
        return "the branch's push history is unreadable";
      }
      moves.push({ after, made });
    }
  }
  const cutoff = Date.parse(at);
  const before = moves.filter((m) => m.made < cutoff);
  const last = Math.max(...before.filter((m) => m.after === decided).map((m) => m.made));
  if (!Number.isFinite(last)) {
    return `the branch shows no push of ${decided} before the decision`;
  }
  const gap = before.find((m) => m.after !== decided && m.made >= last && !ran.every((heads) => heads.includes(m.after)));
  return gap ? `${gap.after} was pushed after the decided head with no run of every review lane before the decision` : null;
}

// Every item of the REST list at `path` whose answer holds it under `key`.
async function listed(read, path, key) {
  const rows = [];
  for (let page = 1; ; page += 1) {
    const answer = await read("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    const items = answer?.[key];
    if (!Array.isArray(items)) {
      throw new Error(`${path} has no ${key} list`);
    }
    rows.push(...items);
    if (items.length < 100) {
      return rows;
    }
  }
}

// The head a decision made at `at` decided, from the review lanes' check-run
// annotations, never a comment (any GITHUB_TOKEN workflow posts as
// github-actions[bot]): every pull_request run of a REVIEW_LANES workflow on
// the head `branch` of `repo` started before `at` (a run from another
// repository's same-named branch speaks for another pull request), each
// run's head vetted against
// `base`, the base branch's tip commit (laneChange), its status job's cost notices (costNotices) from jobs
// done before `at`, then decidedHead, kept only while the branch's push
// history shows no lane run missing since the decided head (unranHead). A
// run on a head that fails the vet, or a read that fails, decides nothing.
// `read` holds contents: read, actions: read and checks: read.
async function noticedHead(read, repo, branch, base, at) {
  const cutoff = Date.parse(at);
  if (!Number.isFinite(cutoff) || typeof branch !== "string" || !BRANCH.test(branch)) {
    return null;
  }
  const notices = [];
  const vetted = new Set();
  const ran = [];
  for (const [file, check] of REVIEW_LANES) {
    const runs = await listed(read, `/repos/${repo}/actions/workflows/${file}/runs?event=pull_request&branch=${encodeURIComponent(branch)}`, "workflow_runs");
    const heads = [];
    ran.push(heads);
    for (const run of runs) {
      if (run?.head_repository?.full_name !== repo || !(Date.parse(run.created_at) < cutoff)) {
        continue;
      }
      const head = String(run.head_sha ?? "");
      if (!/^[0-9a-f]{40}$/.test(head)) {
        return null;
      }
      heads.push(head);
      if (!vetted.has(head)) {
        if (laneChange(await read("GET", `/repos/${repo}/compare/${base}...${head}`)) !== null) {
          return null;
        }
        vetted.add(head);
      }
      for (const job of await listed(read, `/repos/${repo}/actions/runs/${run.id}/jobs?filter=all`, "jobs")) {
        if (job?.name === check && Date.parse(job.completed_at) < cutoff) {
          notices.push(...costNotices(await pages(read, `/repos/${repo}/check-runs/${job.id}/annotations`), head, job.completed_at));
        }
      }
    }
  }
  const decided = decidedHead(notices, at);
  if (decided === null) {
    return null;
  }
  return unranHead(await branchActivity(read, repo, branch), ran, decided, at) === null ? decided : null;
}

// The Link header a reader (fetchGitHub, check-trusted-trigger's
// createGitHub) keeps on a list answer, under a registered symbol so this
// file imports no repository file.
export const LINK = Symbol.for("github.link");
export const ACTIVITY_PAGES = 20;

// The head `branch`'s activity in `repo`, newest first, read to its end: the
// API keeps a branch name's history across deletions, so a name recreated
// for each sync fills any one page. It ignores `page`, so each next page is
// the `after` cursor of the answer's Link rel="next"; only a short page ends
// it. A page that is no list gives null (unranHead's unreadable); a full page
// with no next link, a next link with no new cursor, or more than
// ACTIVITY_PAGES pages throws, as a failed read does.
export async function branchActivity(read, repo, branch) {
  const path = `/repos/${repo}/activity?ref=${encodeURIComponent(`refs/heads/${branch}`)}&direction=desc&per_page=100`;
  const rows = [];
  const cursors = new Set();
  for (let after = null; cursors.size < ACTIVITY_PAGES; ) {
    const page = await read("GET", after === null ? path : `${path}&after=${after}`);
    if (!Array.isArray(page)) {
      return null;
    }
    rows.push(...page);
    if (page.length < 100) {
      return rows;
    }
    const next = /<([^>]*)>;\s*rel="next"/.exec(String(page[LINK] ?? ""));
    if (!next) {
      throw new Error("the branch's push history has a full page with no next link");
    }
    // The cursor as the link spells it, encoded: decoding would read a `+` as a space.
    after = /[?&]after=([^&#]+)/.exec(next[1])?.[1];
    if (!after || cursors.has(after)) {
      throw new Error("the branch's push history names no new page");
    }
    cursors.add(after);
  }
  throw new Error(`the branch's push history runs past ${ACTIVITY_PAGES} pages`);
}

// Whether a COMMENT_EDITED_QUERY answer's node was never edited.
const unedited = (node) => Boolean(node) && "lastEditedAt" in node && node.lastEditedAt === null;

// Whether two compare answers (base...head) show the same net change of the
// pull request: the same filenames, each with the same status,
// previous_filename and patch. A list of 300 files or more (the compare
// API's cap), a file with no patch, a filename listed twice, or an answer
// with no file list is not the same (babysit_merge_policy.same_net_change).
// The compare API reports no file mode, so a change that only flips a
// file's mode (such as making it executable) reads as the same: a known
// residual a merge can carry.
export function sameNetChange(decided, current) {
  const net = (compare) => {
    const files = compare?.files;
    if (!Array.isArray(files) || files.length >= 300) return null;
    const byName = new Map();
    for (const f of files) {
      if (typeof f?.filename !== "string" || typeof f.patch !== "string" || byName.has(f.filename)) return null;
      byName.set(f.filename, JSON.stringify([f.status ?? null, f.previous_filename ?? null, f.patch]));
    }
    return byName;
  };
  const [then, now] = [net(decided), net(current)];
  return then !== null && now !== null && then.size === now.size && [...then].every(([name, value]) => now.get(name) === value);
}

// A compare answer's commits, or null when the list is not read whole
// (shorter than total_commits, the compare API's 250).
const listedCommits = (compare) =>
  Array.isArray(compare?.commits) && Number.isInteger(compare.total_commits) && compare.total_commits === compare.commits.length ? compare.commits : null;

// The commits a compare answer `now` (base...H') lists beyond `then`
// (base...H), or null when either list is not read whole.
function newCommits(then, now) {
  const [before, after] = [listedCommits(then), listedCommits(now)];
  if (before === null || after === null) return null;
  const old = new Set(before.map((c) => c?.sha));
  return after.filter((c) => !old.has(c?.sha));
}

// The parents other than the first of each commit `now` lists beyond `then`
// (newCommits), the ones a base merge must take from the base; a parent
// that is not a 40-hex sha is left out, so it is never in the base.
export function mergedParents(then, now) {
  const parents = (newCommits(then, now) ?? []).flatMap((c) => (Array.isArray(c?.parents) ? c.parents.slice(1).map((p) => p?.sha) : []));
  return [...new Set(parents.filter((sha) => /^[0-9a-f]{40}$/.test(String(sha))))];
}

// Whether every commit `now` (base...H') lists beyond `then` (base...H) is a
// merge whose every parent but the first is in `inBase` (the parents the
// base holds, read by baseParents), with `from` (H) among `now`'s commits, so
// H' descends from H by merges of the base alone
// (babysit_merge_policy.base_merges_only). A non-merge commit, a merge of
// another branch, a force push that drops H, or a list not read whole
// carries nothing.
export function baseMergesOnly(then, now, from, inBase = new Set()) {
  const added = newCommits(then, now);
  return (
    added !== null &&
    now.commits.some((c) => c?.sha === from) &&
    added.every((c) => Array.isArray(c?.parents) && c.parents.length >= 2 && c.parents.slice(1).every((p) => inBase.has(p?.sha)))
  );
}

// The one base-merge carry: whether what a person or the owner decided at
// head `from` covers the head `now` was read at, from the compares
// base...from (`then`) and base...head (`now`) against the base's tip commit
// and the merged parents the base holds (`inBase`, from baseParents; an
// array, as ci-status's cost step passes it as JSON, or a Set): every commit
// since is a merge of the base (baseMergesOnly) and the net change is the
// same over every file (sameNetChange), so a merge that writes any change of
// its own carries nothing (babysit_merge_policy.base_merge_carry).
export function baseMergeCarry(then, now, from, inBase = []) {
  return baseMergesOnly(then, now, from, new Set(inBase)) && sameNetChange(then, now);
}

// Whether the merges brought exactly the base's changes (the owner's decision
// of 2026-10-28, part b): `merges` is the compare H...H', what the merges
// brought into the approved head, and `based` the compare M...M' between the
// merge bases of H and of H' with the base's tip, what the base changed over
// that range. H' must be ahead of H and M' of (or at) M, each commit list read
// whole, and the two file lists the same file for file (sameNetChange, so
// each list is under 300 files and every file has a patch). A file the merges
// changed beyond the base, or a base change they dropped, carries nothing.
// This assumes GitHub omits no file from a compare's list of fewer than 300
// files; nothing here reads a second listing to check that. The compare API
// reports no file mode, so `trees` ([H' tree, M' tree], each a recursive
// git/trees answer) decide it (sameModes): every brought file must have the
// same mode at H' as at M', and the trees cross-check that each path is
// present (or, removed or renamed away, absent) in both.
export function exactBaseCarry(merges, based, trees = null) {
  const forward = (compare, statuses) => statuses.includes(compare?.status) && compare.behind_by === 0 && listedCommits(compare) !== null;
  return forward(merges, ["ahead"]) && forward(based, ["ahead", "identical"]) && sameNetChange(merges, based) && sameModes(merges, trees);
}

// Whether each file a compare `merges` lists has one mode at both trees of
// `trees` (two recursive git/trees answers, read whole: `truncated` false;
// an entry whose mode is not text counts as absent):
// present in both at one mode, or, for a removed file and a renamed file's
// old path, in neither (babysit_merge_policy._same_modes).
function sameModes(merges, trees) {
  const modes = (tree) => {
    if (tree?.truncated !== false || !Array.isArray(tree.tree)) return null;
    const byPath = new Map();
    for (const entry of tree.tree) {
      if (typeof entry?.path === "string" && typeof entry.mode === "string" && entry.type !== "tree") byPath.set(entry.path, entry.mode);
    }
    return byPath;
  };
  if (!Array.isArray(trees) || trees.length !== 2) return false;
  const [head, base] = trees.map(modes);
  if (head === null || base === null) return false;
  return merges.files.every((f) => {
    const gone = [...(f.status === "removed" ? [f.filename] : []), ...(typeof f.previous_filename === "string" ? [f.previous_filename] : [])];
    const kept = f.status === "removed" ? [] : [f.filename];
    return gone.every((path) => !head.has(path) && !base.has(path)) && kept.every((path) => head.has(path) && head.get(path) === base.get(path));
  });
}

// Whether an approval of `from` carries to the head `now` was read at
// (babysit_merge_policy.approval_carry), by either of two paths:
// - every commit since is a merge of the base (baseMergesOnly), and the net
//   change is the same (sameNetChange) or the merges brought exactly the
//   base's changes (exactBaseCarry over `merges`, `based` and `trees`, null
//   when not read);
// - the owner's decision Q10 of 2026-10-28: `merges`, the compare from...H',
//   touches no hold path (ungatedSince, with `holdPaths` the configured
//   globs; undefined, as a caller that read none passes, skips this path).
// An approval GitHub dismissed as stale (autoDismissed) passes its
// `dismissal` commit, which must be one of the commits pushed since `from`,
// so the push the carry checks dismissed it.
export function approvalCarry(then, now, from, inBase, merges, based, dismissal = null, trees = null, holdPaths = undefined) {
  const pushed = (commits) => dismissal === null || (commits ?? []).some((c) => c?.sha === dismissal);
  const merged = baseMergesOnly(then, now, from, new Set(inBase)) && pushed(newCommits(then, now)) && (sameNetChange(then, now) || exactBaseCarry(merges, based, trees));
  return merged || (holdPaths !== undefined && ungatedSince(merges, holdPaths) && pushed(listedCommits(merges)));
}

// The code a hold-path file loads that is no hold path itself: every file of
// each local action a hold-path workflow uses, every tracked script it names
// by path in any directory (from the head checkout or `.base/`, the lint and
// test scripts ci-status runs included), and the JS and Python those import
// (test_merge_holds_sync.py derives that closure and fails on a member these
// globs and HOLD_PATH_CLASSES miss; a shell script's own `source` is not
// walked).
// Holding them for a person would hold most pull requests, so a push that
// touches one only stops an approval carrying (ungatedSince); the review
// lanes still judge it. babysit_merge_policy.CARRY_REFUSES is the same list.
// The trusted-actor list and the pipeline config are read too: a widening the
// approver never saw is lifted by the same approval (actorsHold).
export const CARRY_REFUSES = Object.freeze([".github/workflows/**", ".github/actions/**", ".github/scripts/**", ".github/standards/**", "docs/conventions/pr-pipeline/**", "scripts/**", "lib/**", "plugins/source-control/skills/babysit-prs/scripts/**", "plugins/performance/scripts/**", "plugins/harness-ops/skills/inventory/scripts/**", "plugins/ai-briefing/skills/generate/scripts/**", "plugins/harness-config/skills/audit-permission-state/scripts/**", "plugins/knowledge/skills/course-digest/scripts/**", "plugins/knowledge/skills/video-digest/scripts/**", "plugins/skill-quality/scripts/**", "plugins/source-control/scripts/**", "plugins/testing/skills/check-visual-parity/scripts/**", ".github/recurring-schedule.json", "plugins/evals/skills/validate/scripts/**", "plugins/testing/evals/browser-probe/**", "plugins/work-items/scripts/**", "plugins/work-items/tools/work-item-tracker/**"]);

// Whether the compare from...H' `merges` touches no hold path and no file a
// hold path loads, old paths of renames included: pathHold with `holdPaths`
// and HOLD_PATH_FLOOR, REVIEW_FLOOR's enforcement globs (the floored code the
// gate holds for a security review, which a person's approval never
// covered) and CARRY_REFUSES. H' must be ahead of `from` with nothing behind,
// its commit list read whole, and fewer than the compare API's 300 files
// listed, each named. Any edit to such a file, a test or a comment included,
// needs a new approval.
export function ungatedSince(merges, holdPaths) {
  const files = merges?.files;
  if (merges?.status !== "ahead" || merges.behind_by !== 0 || listedCommits(merges) === null || !Array.isArray(files) || files.length >= 300) return false;
  if (!files.every((f) => typeof f?.filename === "string")) return false;
  const paths = files.flatMap((f) => [f.filename, ...(typeof f.previous_filename === "string" ? [f.previous_filename] : [])]);
  const loaded = [...REVIEW_FLOOR, ...CARRY_REFUSES];
  return Array.isArray(holdPaths) && pathHold(paths, holdPaths) === null && !paths.some((path) => loaded.some((glob) => matchesHoldPath(path, glob)));
}

// The reviews GitHub dismissed as stale, from the pull request's issue
// timeline `events`, as a Map of review id (a string) to the dismissal
// commit: a review_dismissed event of an approval with a null message, by a
// Bot (the account whose push dismissed it), naming a commit SHA. A
// dismissal whose actor is a User revokes: a person's own dismissal, or the
// stale dismissal a person's push caused. That a Bot's deliberate dismissal
// always carries a message is UNVERIFIED (the dismissal API documents the
// message as required), so the null message is a second filter, not the
// one that tells GitHub's dismissal from an App's. A review with any other
// dismissal event is left out.
// A review id as text, from a string or a safe integer (as JSON may give
// either), else null (babysit_merge_policy._review_key).
const reviewKey = (value) => (typeof value === "string" ? value : Number.isSafeInteger(value) ? String(value) : null);

export function autoDismissed(events) {
  const found = new Map();
  const revoked = new Set();
  for (const e of Array.isArray(events) ? events : []) {
    if (e?.event !== "review_dismissed") continue;
    const d = e.dismissed_review;
    const id = reviewKey(d?.review_id);
    if (id === null) continue;
    const stale = d?.state === "approved" && d.dismissal_message === null && e.actor?.type === "Bot" && /^[0-9a-f]{40}$/.test(String(d.dismissal_commit_id));
    if (stale && !found.has(id)) found.set(id, d.dismissal_commit_id);
    else revoked.add(id);
  }
  for (const id of revoked) found.delete(id);
  return found;
}

// The merged parents (mergedParents) the base holds, through `compare` (a
// GET of /repos/<repo>/compare/<range>) against `tip`, the base branch's
// tip commit (baseTip): those whose compare is `ahead` or `identical`. A
// read that fails throws, which carries nothing.
export async function baseParents(compare, tip, then, now) {
  const inBase = new Set();
  for (const sha of mergedParents(then, now)) {
    if (["ahead", "identical"].includes((await compare(`${sha}...${tip}`))?.status)) inBase.add(sha);
  }
  return inBase;
}

// The tip commit of the base branch `base`, read once by its full ref so no
// tag or other ref of the same name stands in for it; a throw when it does
// not read as a commit SHA.
export async function baseTip(github, repo, base) {
  const sha = (await github("GET", `/repos/${repo}/git/ref/heads/${base}`))?.object?.sha;
  if (!/^[0-9a-f]{40}$/.test(String(sha))) throw new Error(`the base branch ${base} did not resolve`);
  return sha;
}

// Each trusted person's standing approval, as { login, sha, dismissal }:
// their newest review (REST, fromRest shape) that approves, requests changes
// or was dismissed, when it approves a commit, with `dismissal` null; or when
// it is an approval GitHub dismissed as stale (`dismissed`, autoDismissed's
// Map), with `dismissal` its dismissal commit, which lifts only through the
// carry (babysit_merge_policy.lifts_of). Only ids in `humans` count; any
// other dismissed approval does not.
export function liftsOf(reviews, humans, dismissed = new Map()) {
  const newest = new Map();
  for (const r of reviews ?? []) {
    if (!r?.isUser || !humans.has(r.userId) || !["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(r.state)) continue;
    const made = Date.parse(r.at);
    if (Number.isFinite(made) && (!newest.has(r.userId) || made >= newest.get(r.userId).made)) newest.set(r.userId, { ...r, made });
  }
  return [...newest.values()].flatMap((r) => {
    const key = reviewKey(r.id);
    const restored = r.state === "DISMISSED" && key ? (dismissed.get(key) ?? null) : null;
    if (!/^[0-9a-f]{40}$/.test(String(r.commitId)) || (r.state !== "APPROVED" && restored === null)) return [];
    return [{ login: r.login, sha: r.commitId, dismissal: restored }];
  });
}

// The trusted people whose approval (liftsOf) of pull request `number`'s
// `head`, or of an earlier head that carries to it over merges of its base
// branch (approvalCarry against the base's tip, baseTip, with baseParents),
// lifts its hold paths, as { lifters }, sorted. An approval GitHub dismissed
// as stale on a push (autoDismissed, from the issue timeline, read only when
// a trusted person's newest review was dismissed) counts, but only through
// the carry, never as an approval of the head. It lifts the hold path and the
// trusted-actor list widening only, never the holds an approving review of
// the head itself lifts. Reads: the pull request (a head that is no longer
// `head`, or is in a fork, lifts nothing), the reviews, the timeline, the
// repository's default branch (a base that is not it carries nothing), the
// base's tip, and the compares per approved head: against the tip, and when
// the net change differs, H...H', the range between the two merge bases and
// the recursive trees of H' and M' (exactBaseCarry). A read that fails lifts nothing (a timeline that does not
// read restores no dismissed approval): the caller keeps the exact-head
// approvals it read (pathLifters).
export async function liftersOf(github, repo, number, head, humans, holdPaths = undefined) {
  try {
    const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
    const base = pull?.base?.ref;
    if (pull?.head?.sha !== head || pull?.head?.repo?.full_name !== repo || !BRANCH.test(String(base))) return { lifters: [] };
    const reviews = (await pages(github, `/repos/${repo}/pulls/${number}/reviews`)).map(fromRest);
    const dismissed = reviews.some((r) => r.isUser && humans.has(r.userId) && r.state === "DISMISSED")
      ? await pages(github, `/repos/${repo}/issues/${number}/timeline`).then(autoDismissed, () => new Map())
      : new Map();
    const lifts = liftsOf(reviews, humans, dismissed);
    // A carry runs only into the repository's default branch: another base
    // may be non-linear, with criss-cross merge bases.
    const carrying = lifts.some(({ sha }) => sha !== head) && (await github("GET", `/repos/${repo}`))?.default_branch === base;
    const tip = carrying ? await baseTip(github, repo, base) : null;
    const compares = new Map();
    const compare = async (range) => {
      if (!compares.has(range)) compares.set(range, await github("GET", `/repos/${repo}/compare/${range}`));
      return compares.get(range);
    };
    const treeReads = new Map();
    const tree = async (sha) => {
      if (!treeReads.has(sha)) treeReads.set(sha, await github("GET", `/repos/${repo}/git/trees/${sha}?recursive=1`));
      return treeReads.get(sha);
    };
    const sha40 = (value) => (/^[0-9a-f]{40}$/.test(String(value)) ? value : null);
    const lifters = new Set();
    for (const { login, sha, dismissal } of lifts) {
      if (sha === head) {
        if (dismissal === null) lifters.add(login);
        continue;
      }
      if (!carrying) continue;
      const [then, now] = [await compare(`${tip}...${sha}`), await compare(`${tip}...${head}`)];
      // A compare listing fewer files than the pull request changes is
      // cut short, so it carries nothing.
      if (!Array.isArray(now?.files) || now.files.length !== pull.changed_files) continue;
      const inBase = await baseParents(compare, tip, then, now);
      let [merges, based, trees] = [null, null, null];
      const [from, to] = [sha40(then?.merge_base_commit?.sha), sha40(now?.merge_base_commit?.sha)];
      if (baseMergesOnly(then, now, sha, inBase) && !sameNetChange(then, now) && from && to) {
        [merges, based] = [await compare(`${sha}...${head}`), await compare(`${from}...${to}`)];
        trees = [await tree(head), await tree(to)];
      }
      if (approvalCarry(then, now, sha, inBase, merges, based, dismissal, trees)) {
        lifters.add(login);
        continue;
      }
      // Q10's path reads from...H' when the base-merge path did not; a read
      // that fails carries nothing by it.
      if (holdPaths !== undefined && merges === null) {
        merges = await compare(`${sha}...${head}`).catch(() => null);
      }
      if (holdPaths !== undefined && approvalCarry(then, now, sha, inBase, merges, based, dismissal, trees, holdPaths)) lifters.add(login);
    }
    return { lifters: [...lifters].sort() };
  } catch {
    return { lifters: [] };
  }
}

// Every page of the REST list at `path`.
async function pages(github, path) {
  const rows = [];
  for (let page = 1; ; page += 1) {
    const read = await github("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    if (!Array.isArray(read)) {
      throw new Error(`${path} is not a list`);
    }
    rows.push(...read);
    if (read.length < 100) {
      return rows;
    }
  }
}

// Whether the decision `comment` covers the pull request at `head` (owner
// decisions Q17 c and Q18 d on #9436): its decided head (noticedHead, read
// with `actions` from the head branch `branch`'s lane runs) is `head`, or
// every change since is a merge of the base branch `base`, so the net change
// against it is the same at both (baseMergeCarry). The base is resolved once
// to its tip commit (baseTip), which the lane-change vet and every compare
// name, so no tag of the same name stands in for it. No decided head, an
// unusable base name or a read that fails carries nothing.
async function carries(github, actions, repo, comment, head, base, branch) {
  try {
    if (typeof base !== "string" || !BRANCH.test(base)) {
      return false;
    }
    const tip = await baseTip(github, repo, base);
    const decided = await noticedHead(actions, repo, branch, tip, comment.created_at);
    if (decided === null) {
      return false;
    }
    if (decided === head) {
      return true;
    }
    const compare = (range) => github("GET", `/repos/${repo}/compare/${range}`);
    const then = await compare(`${tip}...${decided}`);
    const now = await compare(`${tip}...${head}`);
    return baseMergeCarry(then, now, decided, await baseParents(compare, tip, then, now));
  } catch {
    return false;
  }
}

// The comment link in `body`, outside HTML comments, that records the
// owner's cost decision for pull request `number` of `repo` at `head`, else
// null: the rule of babysit_merge_policy.cost_decision, with the owner a
// person whose id is in `humans` (trusted-actors.json), as ci-status's
// cost-only review hold step names one. The comment is on the pull request,
// or on its linked issue in `repo` (the one closing issue, else with none the
// one refsIssue names, read to be an issue and not a pull request), newer
// than the pull request and naming it (namesPull); by a User, not through an
// App; never edited; its first line `**Decision recorded.** Cost:`. Of
// those, the decision is the newest on the pull request, else the newest on
// the issue, as the review lanes' hold step picks it; it covers the head it
// decided and a later one only when every change since is a base merge
// (carries, against the pull request's base branch). `github(method, path,
// body)` reads; `actions`, the same shape, reads the lane runs, their jobs,
// annotations and compares (it needs actions: read and checks: read). A
// failed read of the pull request or the Refs target decides nothing, and one
// of a comment or its edit state skips that comment.
export async function costDecision(github, repo, number, body, humans, head, actions = github) {
  const links = [...String(body ?? "").replaceAll(HTML_COMMENT, "").matchAll(DECISION_LINK)].filter(
    (link) => `${link[1]}/${link[2]}`.toLowerCase() === String(repo).toLowerCase(),
  );
  if (!links.length) {
    return null;
  }
  const [owner, name] = repo.split("/");
  let pull;
  try {
    pull = (await github("POST", "/graphql", { query: PULL_OPENED_QUERY, variables: { owner, name, number } }))?.data?.repository?.pullRequest;
  } catch {
    return null;
  }
  const opened = Date.parse(pull?.createdAt);
  const closing = pull?.closingIssuesReferences;
  const refs = closing?.totalCount === 0 ? refsIssue(body) : null;
  let issue =
    refs ??
    (closing?.totalCount === 1 && closing.nodes?.length === 1 && String(closing.nodes[0]?.repository?.nameWithOwner).toLowerCase() === repo.toLowerCase()
      ? closing.nodes[0].number
      : null);
  let checked = refs === null;
  const decisions = [];
  for (const link of links) {
    const target = Number(link[3]);
    if (target !== number && target !== issue) {
      continue;
    }
    if (target !== number && !checked) {
      // A Refs number may name a pull request; only an issue is consulted.
      try {
        const read = await github("GET", `/repos/${repo}/issues/${refs}`);
        issue = read?.number === refs && read.pull_request == null ? refs : null;
      } catch {
        return null;
      }
      checked = true;
      if (issue === null) {
        continue;
      }
    }
    try {
      const comment = await github("GET", `/repos/${repo}/issues/comments/${link[4]}`);
      if (
        !String(comment?.issue_url ?? "").endsWith(`/issues/${target}`) ||
        comment.user?.type !== "User" ||
        comment.performed_via_github_app != null ||
        !humans.has(comment.user.id) ||
        !DECISION_LINE.test(String(comment.body ?? "").trimStart()) ||
        (target !== number && !(Date.parse(comment.created_at) > opened && namesPull(comment.body, number)))
      ) {
        continue;
      }
      const node = (await github("POST", "/graphql", { query: COMMENT_EDITED_QUERY, variables: { id: String(comment.node_id) } }))?.data?.node;
      if (unedited(node)) {
        decisions.push({ link: link[0], comment, own: target === number });
      }
    } catch {
      // An unreadable comment clears nothing.
    }
  }
  const at = (d) => {
    const made = Date.parse(d.comment.created_at);
    return Number.isNaN(made) ? -Infinity : made;
  };
  // The newest; of two at one time, the first linked.
  const newest = (own) => decisions.filter((d) => d.own === own).reduce((best, d) => (best === undefined || at(d) > at(best) ? d : best), undefined);
  const decision = newest(true) ?? newest(false);
  return decision && (await carries(github, actions, repo, decision.comment, head, pull?.baseRefName, pull?.headRefName)) ? decision.link : null;
}

// A GitHub REST and GraphQL reader on fetch, for costDecision.
const fetchGitHub = (env) => async (method, path, body) => {
  const response = await fetch(`${env.GITHUB_API_URL || "https://api.github.com"}${path}`, {
    method,
    headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GH_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = response.ok ? await response.json() : null;
  if (json === null || json.errors?.length) {
    throw new Error(`${method} ${path} failed with status ${response.status}`);
  }
  if (Array.isArray(json)) {
    Object.defineProperty(json, LINK, { value: response.headers.get("link") });
  }
  return json;
};

// The config's denied paths, or null unless a list of strings; pathHold adds
// the floor.
export function holdPathsOf(denied) {
  return Array.isArray(denied) && denied.every((glob) => typeof glob === "string") ? denied : null;
}

// The trusted people (numeric `humans` ids) whose newest deciding review of
// `head` among `items` approves it, sorted by login.
export function pathLifters(items, humans, head) {
  const newest = new Map();
  for (const item of items) {
    if (!item.isUser || !humans.has(item.userId) || item.commitId !== head) {
      continue;
    }
    if (!["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(item.state)) {
      continue;
    }
    if (!newest.has(item.userId) || item.at >= newest.get(item.userId).at) {
      newest.set(item.userId, item);
    }
  }
  return [...newest.values()]
    .filter(({ state }) => state === "APPROVED")
    .map(({ login }) => login)
    .sort();
}

// Why the pull request's `body`, discussion `items` and changed `files` hold
// it; empty when nothing does. `lifters` approved the head (pathLifters, or
// liftersOf over base merges), which lifts a
// hold path but not an unreadable file list or hold-path list, nor a cost
// path, which only the owner's `decision` lifts. It lifts `widened`
// (actorsHold's reason) too. `byPerson` (personWrote) says whether the body
// can hold; `pathHolds` false (pathHoldsOf) holds no hold path.
export function holds(body, items, files, holdPaths, lifters = [], decision = null, byPerson = true, widened = null, pathHolds = true) {
  const reasons = [];
  if (widened && !lifters.length) {
    reasons.push(`${widened}; an approving review of this head by a person on the trusted-actor list lifts it, and the approval carries over later merges that bring only the base's changes; then re-run ci-status`);
  }
  const pathReason = pathHold(files, holdPaths, pathHolds);
  const readable = Array.isArray(files) && Array.isArray(holdPaths);
  if (pathReason && !(readable && lifters.length)) {
    reasons.push(
      readable
        ? `${pathReason}; an approving review of this head by a person on the trusted-actor list lifts it, and the approval carries over later merges that bring only the base's changes; then re-run ci-status`
        : pathReason,
    );
  }
  const cost = costHold(files, decision);
  if (cost) {
    reasons.push(
      `${cost}; the owner's unedited comment opening '**Decision recorded.** Cost:' on this pull request, or on its linked issue naming this pull request, linked from the body, lifts it for the head it decided and a later head that only merges the base`,
    );
  }
  if (bodyHolds(body, byPerson)) {
    reasons.push("its body holds it (a line opening with 'Hold:', or 'do not merge'); removing that text lifts it");
  }
  const vetoes = vetoers(items);
  if (vetoes.length) {
    reasons.push(`${vetoes.join(", ")} asked not to merge it; a later comment by the same person lifts it, then re-run ci-status`);
  }
  return reasons;
}

// The verifier workflow (resolve-pr.mjs VERIFY_PATH).
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
const PASSES = Object.freeze(["pass", "pass-notes"]);

// Why the head has no verifier pass, or null when a record shows one: a pass
// or pass-notes artifact whose run is pr-verify.yml's, event workflow_run, on
// `branch` of `repo` with its head in `repo`, completed with success: the
// fields of babysit_verify_evidence `_origin` and a counted run, without its
// compare read that main holds the run's commit, since main's ruleset
// forbids the force push that could drop it. The records are
// read for the head alone, by exact name, so a record of another head never
// reaches here.
export function verdictHold(records, repo, branch = "main") {
  if (!Array.isArray(records) || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(String(repo))) {
    return "its pr-verify verdicts could not be read";
  }
  const pass = records.find(
    ({ verdict, runId, run } = {}) =>
      PASSES.includes(verdict) &&
      Number.isSafeInteger(runId) &&
      run?.id === runId &&
      run.path === VERIFY_PATH &&
      run.event === "workflow_run" &&
      run.head_branch === branch &&
      run.repository?.full_name === repo &&
      run.head_repository?.full_name === repo &&
      run.status === "completed" &&
      run.conclusion === "success",
  );
  return pass ? null : "pr-verify has not passed this head";
}

// The refusals of babysit_verify_evidence.py a pass decides: verdictHold and
// linkHold judge the pass here, and an approval lifts them as it lifts this.
const PASS_REFUSALS = Object.freeze(["verify:missing", "verify:spec-changed", "verify:untrusted-spec"]);

// Why the reader's report for `head` holds it, or null: a refusal outside
// PASS_REFUSALS (a FAIL class, verify:unreadable, verify:too-old or one this
// module does not know) holds, and so does a report that does not read or
// names another head.
export function evidenceHold(report, head) {
  if (
    report === null ||
    typeof report !== "object" ||
    Array.isArray(report) ||
    report.head !== head ||
    !("refusal" in report) ||
    (report.refusal !== null && typeof report.refusal !== "string")
  ) {
    return "its pr-verify FAILs could not be read";
  }
  const { refusal, detail } = report;
  if (refusal === null || PASS_REFUSALS.includes(refusal)) {
    return null;
  }
  return `pr-verify's reader refuses this head (${refusal}${typeof detail === "string" && detail ? `: ${detail}` : ""})`;
}

// The evidence file's verdict, a file that does not read included.
function evidenceOf(file, head) {
  try {
    return evidenceHold(JSON.parse(readFileSync(file, "utf8")), head);
  } catch {
    return "its pr-verify FAILs could not be read";
  }
}

// A log line can carry a changed file's name: escape what would start a
// workflow command on a new line.
const escape = (text) => String(text).replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");

// The numeric ids of trusted-actors.json's people.
export const humansOf = (actors) =>
  new Set(actors.filter((actor) => actor?.kind === "human" && Number.isInteger(actor?.id)).map(({ id }) => id));

// The link file's verdict, a file that does not read included.
function linkOf(file, body, repo) {
  try {
    const { record, closing } = JSON.parse(readFileSync(file, "utf8"));
    return linkHold(record, body, closing, repo);
  } catch {
    return "its issue link could not be checked against its verifier pass";
  }
}

// One files-file line as { path, previous, status }: [filename,
// previous_filename or null, status] from the pull request files API, or an
// object of those keys. An older line of one path and any renamed-from path
// has no status. A module older than this one reads every entry of a line as
// a path, null and the status matching no hold path.
export function changeOf(line) {
  if (Array.isArray(line)) {
    const [path, previous = null, status = null] = line;
    return {
      path: String(path),
      previous: previous === null ? null : String(previous),
      status: line.length === 3 && typeof status === "string" ? status : null,
    };
  }
  if (line === null || typeof line !== "object" || typeof line.filename !== "string") {
    throw new Error("a changed file does not read");
  }
  const previous = line.previous_filename;
  return { path: line.filename, previous: typeof previous === "string" && previous ? previous : null, status: typeof line.status === "string" ? line.status : null };
}

// A HEAD A PR-UNBLOCK LANE STOPPED: each `pr-unblock/*` context whose newest
// status by github-actions[bot] is `failure` or `error`, as
// { context, state, description }. `statuses` are a commit's REST statuses,
// newest first as GitHub lists them, so a later `success` on the head
// supersedes a failure, and another account's status neither holds nor
// clears. ci-status's pr-unblock step and enable-auto-merge both judge a head
// by this; a list that is not an array throws.
export function unblockStops(statuses) {
  if (!Array.isArray(statuses)) {
    throw new Error("the head's statuses are not a list");
  }
  const seen = new Set();
  const stops = [];
  for (const status of statuses) {
    const context = status?.context;
    if (typeof context !== "string" || !context.startsWith("pr-unblock/") || status?.creator?.login !== "github-actions[bot]" || seen.has(context)) {
      continue;
    }
    seen.add(context);
    if (status.state === "failure" || status.state === "error") {
      stops.push({ context, state: status.state, description: String(status.description ?? "").replaceAll(/[\t\r\n]/g, " ") });
    }
  }
  return stops;
}

// Every REST status of `head`, 100 a page, newest first. A page that is not a
// list, or more than 10 pages, throws.
export async function readStatuses(github, repo, head) {
  const statuses = [];
  for (let page = 1; page <= 10; page += 1) {
    const rows = await github("GET", `/repos/${repo}/commits/${head}/statuses?per_page=100&page=${page}`);
    if (!Array.isArray(rows)) {
      throw new Error("the head's statuses did not read");
    }
    statuses.push(...rows);
    if (rows.length < 100) {
      return statuses;
    }
  }
  throw new Error("more than 1000 statuses on the head");
}

// The tracker config's human-gated role label (.work-item-tracker.json
// config.role_labels["human-gated"], trimmed), `needs-human` when it names
// none, as ci-status reads it.
export function humanGatedLabel(tracker) {
  const label = tracker?.config?.role_labels?.["human-gated"];
  return typeof label === "string" && label.trim() ? label.trim() : "needs-human";
}

// The label report-outcome puts on a lanes App pull request that holds for a
// person (report-outcome.mjs HUMAN_MERGE_HOLD). Only a listed person's own
// removal lifts it (ci-status's `Fail a human-merge hold` step).
export const HUMAN_MERGE_HOLD = "human-merge-hold";

// The label security-outside-actor.yml puts on an item someone outside the
// organization wrote on. It holds wherever the human-gated label holds, and
// only a person removes it: no lane or sweep takes it off.
export const OUTSIDE_ACTOR_LABEL = "security: outside-actor";

// The label a pr-verify fail puts on a person's pull request; a pass at a new
// commit removes it.
export const PR_VERIFY_FAILED_LABEL = "pr-verify-failed";

// The hold labels on pull request `number`: `do-not-merge`, the tracker's
// human-gated label, `pr-verify-failed`, HUMAN_MERGE_HOLD and
// OUTSIDE_ACTOR_LABEL, one reason each. `labels` are
// names or label objects; a list that is not an array throws.
export function labelHolds(labels, tracker, number) {
  if (!Array.isArray(labels)) {
    throw new Error("the labels are not a list");
  }
  const names = new Set(labels.map((label) => (typeof label === "string" ? label : label?.name)));
  const gated = humanGatedLabel(tracker);
  return [
    names.has("do-not-merge") && `#${number} carries the 'do-not-merge' label; the merge queue removes it. Remove the label and re-queue to merge.`,
    names.has(gated) && `#${number} carries '${gated}'; the merge queue removes it. Removing the label approves this pull request; re-queue it to merge.`,
    names.has(PR_VERIFY_FAILED_LABEL) &&
      `#${number} carries '${PR_VERIFY_FAILED_LABEL}': pr-verify failed its head, and a pass at a new commit removes the label. The merge queue removes it; re-queue it once the label is off.`,
    names.has(HUMAN_MERGE_HOLD) &&
      `#${number} carries '${HUMAN_MERGE_HOLD}': a person merges it. The merge queue removes it; a person on the trusted-actor list removing the label approves it, then re-queue it to merge.`,
    names.has(OUTSIDE_ACTOR_LABEL) &&
      `#${number} carries '${OUTSIDE_ACTOR_LABEL}': someone outside the organization wrote on it, and only a person removes the label. Re-queue it once the label is off.`,
  ].filter(Boolean);
}

// The lanes kill switch on a lanes App pull request: while CLAUDE_LANES_DISABLED
// or CLAUDE_LANES_REPO_DISABLED is anything but the exact value `false`, a pull
// request whose author is the Bot of numeric id `appId` holds. Any other
// author, or an `appId` that is not a numeric id, holds nothing here.
export function switchHold(pull, { appId, disabled, repoDisabled } = {}) {
  const id = Number(appId);
  if (!/^[1-9][0-9]*$/.test(String(appId)) || pull?.user?.type !== "Bot" || pull?.user?.id !== id) {
    return null;
  }
  if (disabled === "false" && repoDisabled === "false") {
    return null;
  }
  return `#${pull.number}: the lanes kill switch is on (CLAUDE_LANES_DISABLED or CLAUDE_LANES_REPO_DISABLED is not 'false'), so no lanes App pull request merges; it merges once both read 'false' and ci-status is re-run, which the lost-runs reconciler does when this is the run's only failure.`;
}

// THE HOLDS THAT COST NO LANE WORK, for a queued pull request: its hold labels,
// its head's pr-unblock stops and the lanes kill switch, from the pull request
// as the pulls API returns it, its head's statuses newest first, the tracker
// config (or null) and the kill switch's { appId, disabled, repoDisabled }.
// select-tests runs this before the lanes; ci-status keeps judging each hold.
export function queueHolds({ pull, statuses, tracker = null, lanes = {} } = {}) {
  const head = pull?.head?.sha;
  if (!Number.isInteger(pull?.number) || typeof head !== "string") {
    throw new Error("the pull request does not read");
  }
  return [
    ...labelHolds(pull.labels, tracker, pull.number),
    ...unblockStops(statuses).map(
      ({ context, state, description }) =>
        `'${context}' is ${state} on ${head}: ${description}. The lane that stopped clears it by running again on this head, or a new head carries none.`,
    ),
    switchHold(pull, lanes),
  ].filter(Boolean);
}

// Whether a person wrote the body of pull request `number` (personWrote); a
// read that fails counts as a person.
async function bodyByPerson(github, repo, number) {
  const [owner, name] = repo.split("/");
  try {
    return personWrote((await github("POST", "/graphql", { query: BODY_WRITERS_QUERY, variables: { owner, name, number } }))?.data?.repository?.pullRequest);
  } catch {
    return true;
  }
}

export async function main(argv = process.argv.slice(2), { env = process.env, github = fetchGitHub(env) } = {}) {
  const [number, bodyFile, discussionFile, filesFile, deniedFile, actorsFile, head, verdictsFile, linkFile, evidenceFile] = argv;
  try {
    if (
      !/^[1-9][0-9]*$/.test(String(number)) ||
      !bodyFile ||
      !discussionFile ||
      !filesFile ||
      !deniedFile ||
      !actorsFile ||
      !/^[0-9a-f]{40}$/.test(String(head))
    ) {
      throw new Error(
        "usage: merge-holds.mjs <number> <body-file> <discussion-file> <files-file> <denied-paths-file> <trusted-actors-file> <head-sha> [<verdicts-file> <link-file> [<evidence-file>]]",
      );
    }
    const lines = (file) => readFileSync(file, "utf8").split("\n").filter((line) => line.trim());
    const items = lines(discussionFile).map((line) => fromRest(JSON.parse(line)));
    const changes = lines(filesFile).map((line) => changeOf(JSON.parse(line)));
    const files = changes.flatMap(({ path, previous }) => [path, ...(previous === null ? [] : [previous])]);
    const holdPaths = holdPathsOf(JSON.parse(readFileSync(deniedFile, "utf8")));
    const actors = JSON.parse(readFileSync(actorsFile, "utf8"))?.actors;
    if (!Array.isArray(actors)) {
      throw new Error("the trusted-actor list has no actors");
    }
    const humans = humansOf(actors);
    // Exact-head approvals lift every hold an approval lifts; an approval
    // carried over base merges lifts only the hold path and the trusted-actor
    // list widening.
    const approved = pathLifters(items, humans, head);
    const body = readFileSync(bodyFile, "utf8");
    const repo = String(env.GITHUB_REPOSITORY);
    const decision =
      costHold(files, null) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await costDecision(github, repo, Number(number), body, humans, head) : null;
    if (decision) {
      console.log(`#${number}: ${decision} records the owner's cost decision, which lifts its cost hold.`);
    }
    const byPerson = BODY_HOLD.test(body) && !LANE_HOLD.test(body) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await bodyByPerson(github, repo, Number(number)) : true;
    if (!byPerson) {
      console.log(`#${number}: its body's hold text is the lanes App's own, which holds nothing.`);
    }
    const widened = actorsHold(await withActorContents(github, repo, changes, env.BASE_SHA, head));
    // PATH_HOLDS, merge.diff-check.path-holds as the base has it: only
    // "false" turns the hold paths off.
    const pathHolds = env.PATH_HOLDS !== "false";
    const skipped = pathHolds ? null : pathHoldKind(files, holdPaths);
    if (skipped?.kind === "hold-path") {
      console.log(`#${number}: path holds are off (merge.diff-check.path-holds), so nothing holds it for this: ${escape(skipped.reason)}.`);
    }
    const held = pathHold(files, holdPaths, pathHolds);
    let lifted = { lifters: [] };
    if (!approved.length && ((held && Array.isArray(holdPaths)) || widened) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
      lifted = await liftersOf(github, repo, Number(number), head, humans, holdPaths);
    }
    const lifters = approved.length ? approved : lifted.lifters;
    const reasons = holds(body, items, files, holdPaths, lifters, decision, byPerson, widened, pathHolds);
    const how = approved.length ? "approved this head" : "approved an earlier head whose every change since is a base merge";
    if (held && lifters.length && Array.isArray(holdPaths)) {
      console.log(`#${number}: ${lifters.join(", ")} ${how}, which lifts its hold path (${escape(held)}).`);
    }
    if (widened && lifters.length) {
      console.log(`#${number}: ${lifters.join(", ")} ${how}, which lifts its trusted-actor list hold (${escape(widened)}).`);
    }
    if (verdictsFile) {
      const unverified = verdictHold(lines(verdictsFile).map((line) => JSON.parse(line)), env.GITHUB_REPOSITORY);
      // An approval lifts the verifier hold whole, the link with it.
      const relinked = unverified || approved.length ? null : linkFile ? linkOf(linkFile, body, repo) : "its issue link could not be checked against its verifier pass";
      if (!unverified && !relinked) {
        console.log(`#${number}: no verifier hold: pr-verify passed this head.`);
      } else if (!unverified && approved.length === 0) {
        // pr-verify skips a head it already passed (resolve-pr.mjs `judged`),
        // so only a new head or an approval recovers it.
        reasons.push(`${relinked}; pr-verify does not judge this head again, so push a new head for it to judge, after which enable-auto-merge arms it again, or an approving review of this head by a person on the trusted-actor list lifts it, then re-queue`);
      } else if (approved.length) {
        console.log(`#${number}: no verifier hold: ${approved.join(", ")} approved this head, which lifts '${unverified}'.`);
      } else {
        reasons.push(
          `${unverified}; wait for pr-verify to pass it, after which enable-auto-merge arms it again, or an approving review of this head by a person on the trusted-actor list lifts it, then re-queue`,
        );
      }
      const failed = evidenceFile ? evidenceOf(evidenceFile, head) : "its pr-verify FAILs could not be read";
      if (!failed) {
        const refusal = JSON.parse(readFileSync(evidenceFile, "utf8")).refusal;
        console.log(`#${number}: no pr-verify FAIL hold: ${refusal ? `the reader refuses this head only on its pass (${refusal})` : "the reader allows this head"}.`);
      } else if (approved.length) {
        console.log(`#${number}: no pr-verify FAIL hold: ${approved.join(", ")} approved this head, which lifts '${escape(failed)}'.`);
      } else {
        reasons.push(`${failed}; push a new head for pr-verify to judge, after which enable-auto-merge arms it again, or an approving review of this head by a person on the trusted-actor list lifts it, then re-queue`);
      }
    }
    for (const reason of reasons) {
      console.log(`::error::#${number}: ${escape(reason)}.`);
    }
    if (!reasons.length) {
      console.log(`#${number}: no body hold, no member veto and no hold path.`);
    }
    return reasons.length ? 1 : 0;
  } catch (error) {
    console.log(`::error::merge-holds: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
