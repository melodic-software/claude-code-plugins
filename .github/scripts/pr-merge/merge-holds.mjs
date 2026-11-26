#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const isSha = (value) => /^[0-9a-f]{40}$/.test(String(value));
const isRepo = (value) => /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(String(value));

export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
export const HUMAN_VETO =
  /\bdo(?:n['’]?t| not)[\s-]*merge\b|\bdo-not(?!-merge\b)[\s-]*merge\b|(?<!the )(?<!the `)\bdo-not-merge\b|(?<=the )do-not-merge\b(?!\s*labels?\b)|(?<=the `)do-not-merge\b(?!`\s*labels?\b)/i;
export const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
export const baselineOnly = (author, files, appId, baselineFile) =>
  typeof baselineFile === "string" &&
  baselineFile !== "" &&
  author?.type === "Bot" &&
  String(author.login).toLowerCase() === LANES_APP_LOGIN &&
  /^[1-9][0-9]*$/.test(String(appId)) &&
  String(author.id) === String(appId) &&
  Array.isArray(files) &&
  files.length === 1 &&
  files[0] === baselineFile;
export const DEPENDENCY_MANAGERS = Object.freeze(["dependabot", "dependabot-preview", "renovate", "renovate-bot"]);
export const isDependencyManager = (user) =>
  user?.type === "Bot" &&
  DEPENDENCY_MANAGERS.includes(String(user.login ?? "").toLowerCase().replace(/^app\//, "").replace(/\[bot\]$/, ""));
export const loginKey = (login) => String(login ?? "").trim().toLowerCase().replace(/\[bot\]$/, "");
export const VERIFY_AUTHORS = Object.freeze(["lane", "lane-or-owner", "any"]);
export function authorSkip(user, verifyAuthors, laneIdentity, ownerIds) {
  const lane = () => loginKey(laneIdentity) !== "" && user?.type === "Bot" && loginKey(user.login) === loginKey(laneIdentity);
  const owner = () => (user?.type === "User" || user?.type === "Bot") && ownerIds.includes(user.id);
  if (isDependencyManager(user)) return "dependency-manager";
  if (!VERIFY_AUTHORS.includes(verifyAuthors)) return "verify-authors-invalid";
  if (verifyAuthors === "lane" && !lane()) return "author-not-lane";
  if (verifyAuthors === "lane-or-owner" && !lane() && !owner()) return "author-not-lane-or-owner";
  return null;
}
export const baselineNote = (baselineFile) =>
  `the lanes App's pull request changes only ${baselineFile} (merge.baseline-file), which merges with no linked issue or pr-verify verdict`;
export const LANE_HOLD = /(?:^|[\r\n])Hold: a human merges this[^\S\r\n]*(?:[\r\n]|$)/;
export const bodyHolds = (body, byPerson) => LANE_HOLD.test(String(body ?? "")) || (byPerson && BODY_HOLD.test(String(body ?? "")));

const HTML_COMMENT = /<!--[\s\S]*?(?:-->|$)/g;
const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const REFS_LINE = /^[Rr][Ee][Ff][Ss]:/;
const REFS_PLAIN = /^Refs:[ \t]*#([1-9][0-9]{0,8})[ \t]*$/;
export function refsIssue(body) {
  const numbers = refsNumbers(body);
  return numbers?.size === 1 ? [...numbers][0] : null;
}

export function* visibleLines(body) {
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
    yield line;
  }
}

function refsNumbers(body) {
  const numbers = new Set();
  for (const line of visibleLines(body)) {
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
export const MEMBERS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);

export const BODY_WRITERS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { author { __typename } userContentEdits(first: 100) { totalCount nodes { editor { __typename } } } }
  }
}`;

export function personWrote(pull) {
  const edits = pull?.userContentEdits;
  if (!pull?.author || !Array.isArray(edits?.nodes) || !(edits.totalCount <= edits.nodes.length)) {
    return true;
  }
  return [pull.author, ...edits.nodes.map((edit) => edit?.editor)].some((who) => who?.__typename !== "Bot");
}

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
  nodeId: row?.node_id,
});

export const PIN_RE = /^<!-- babysit-merge-pin sha=([0-9a-f]{40})(?: rung=(C2|C3))? -->$/;

const APPROVAL_LIFTS = "an approving review of this head by a person on the trusted-actor list lifts it";
const APPROVAL_CARRIES = `${APPROVAL_LIFTS}, and the approval carries over later merges that bring only the base's changes; then re-run ci-status`;

export function pinHold(items, head) {
  const pin = newestPin(items);
  if (pin === undefined) {
    return null;
  }
  const again = `enable-auto-merge judges and pins this head before it arms it again, or ${APPROVAL_LIFTS}, then re-queue`;
  if (!unedited(pin)) {
    return `the lanes App's newest pin comment was edited, or its edit time did not read, so the head its arm judged does not read; ${again}`;
  }
  const sha = PIN_RE.exec(pinLine(pin))[1];
  return sha === head ? null : `its head is not ${sha}, the head the lanes App pinned when it armed auto-merge, so the arm's checks never judged this head; ${again}`;
}

const pinLine = (item) => item.body.split("\n", 1)[0].replace(/\r$/, "");
const newestPin = (items) =>
  items
    .filter((item) => item.login === LANES_APP_LOGIN && PIN_RE.test(pinLine(item)))
    .sort((a, b) => a.at.localeCompare(b.at))
    .at(-1);

export async function withPinEdit(github, items) {
  const pin = newestPin(items);
  if (pin === undefined || typeof pin.nodeId !== "string" || !pin.nodeId) {
    return items;
  }
  let node;
  try {
    node = (await github("POST", "/graphql", { query: COMMENT_EDITED_QUERY, variables: { id: pin.nodeId } }))?.data?.node;
  } catch {
    return items;
  }
  if (!node || typeof node !== "object" || !("lastEditedAt" in node)) {
    return items;
  }
  return items.map((item) => (item === pin ? { ...item, lastEditedAt: node.lastEditedAt } : item));
}

const undot = (text) => String(text).toLowerCase().replaceAll(/(^|\/)\./g, "$1\u0001");
export const matchesHoldPath = (path, glob) => posix.matchesGlob(undot(path), undot(glob));

export const HOLD_PATH_CLASSES = Object.freeze([
  // BEGIN hold-floor HOLD_PATH_CLASSES: generated by scripts/sync-hold-floor.py
  ["**/CODEOWNERS", "trust"],
  ["docs/conventions/pr-pipeline.yaml", "trust"],
  ["**/.gitmodules", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/diff_risk.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_check_inputs.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_checks.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_classify.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_feedback.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_lane_binding.py", "enforcement"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py", "trust"],
  ["plugins/source-control/skills/babysit-prs/scripts/babysit_merge_settings.py", "trust"],
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
  ["docs/conventions/source-control.yaml", "gate"],
  ["**/.claude-lane/**", "gate"],
  ["**/.mcp.json", "gate"],
  ["**/CLAUDE.md", "gate"],
  ["**/CLAUDE.local.md", "gate"],
  ["**/AGENTS.md", "gate"],
  ["REVIEW.md", "gate"],
  [".github/actions/check-trusted-trigger/**", "trust"],
  [".github/scripts/lib/github-client.mjs", "trust"],
  [".github/scripts/lib/trusted-actors.mjs", "trust"],
  [".github/actions/resolve-config/**", "trust"],
  [".github/actions/check-kill-switch/**", "trust"],
  [".github/actions/request-lane-token/**", "trust"],
  [".github/source-control-settings.json", "trust"],
  [".github/verify-legacy-fails.json", "trust"],
  [".github/actions/log-api-budget/rate-guard.mjs", "gate"],
  [".github/actions/log-api-budget/api-budget.bash", "gate"],
  [".github/actions/log-api-budget/rate-limits.json", "gate"],
  [".github/scripts/pr-merge/merge-holds.mjs", "trust"],
  [".github/scripts/pr-merge/enable-auto-merge.mjs", "trust"],
  [".github/scripts/lib/lane-vocabulary.mjs", "trust"],
  [".github/scripts/pr-merge/superseded.mjs", "trust"],
  [".github/scripts/pr-merge/clear-escalations.mjs", "trust"],
  [".github/scripts/pr-merge/release-eval-hold.mjs", "trust"],
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
  [".github/scripts/lib/run-title.mjs", "gate"],
  [".github/scripts/lib/lane-branch.mjs", "gate"],
  [".github/scripts/lib/lane-registry.mjs", "gate"],
  [".github/lane-registry.json", "gate"],
  [".github/scripts/pr-merge/merge-risk-line.mjs", "gate"],
  [".github/scripts/pr-merge-risk/input.mjs", "gate"],
  [".github/scripts/pr-merge-risk/write-rating.mjs", "gate"],
  [".github/actions/report-check-run/posting-run.mjs", "gate"],
  [".github/scripts/pr-dispatch-feedback/rerun-ci-status.sh", "gate"],
  [".github/scripts/post-merge-demotion-alert/file-demotion-issue.sh", "gate"],
  ["scripts/sync-hold-floor.py", "trust"],
  [".github/scripts/pr-unblock/address-feedback.mjs", "enforcement"],
  [".github/scripts/pr-unblock/escalation-routes.mjs", "enforcement"],
  [".github/scripts/pr-unblock/escalation-routes.json", "enforcement"],
  [".github/scripts/pr-unblock/gate-source.mjs", "enforcement"],
  [".github/scripts/pr-unblock/thread-scope.mjs", "enforcement"],
  [".github/scripts/lib/retry-fetch.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/report-outcome.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/limits.mjs", "enforcement"],
  [".github/scripts/lib/lane-hold-marker.mjs", "enforcement"],
  [".github/scripts/pr-unblock/report-escalation.sh", "enforcement"],
  [".github/scripts/pr-unblock/adjudicate-feedback.mjs", "enforcement"],
  [".github/scripts/pr-unblock/publish-feedback.mjs", "enforcement"],
  [".github/scripts/pr-unblock/resolve-threads.mjs", "enforcement"],
  [".github/scripts/pr-unblock/request-budget.mjs", "enforcement"],
  [".github/scripts/pr-verify/resolve-pr.mjs", "enforcement"],
  [".github/scripts/pr-verify/spec-source.mjs", "enforcement"],
  [".github/scripts/pr-verify/write-verdict.mjs", "enforcement"],
  [".github/scripts/intake-triage/admit.mjs", "enforcement"],
  [".github/scripts/intake-triage/size-split.mjs", "enforcement"],
  [".github/scripts/intake-triage/issue-spec.mjs", "enforcement"],
  [".github/actions/select-trusted-text/select-trusted-text.mjs", "enforcement"],
  ["lib/publish-gate.mjs", "enforcement"],
  [".github/recurring-schedule.json", "enforcement"],
  ["docs/upstream/**", "enforcement"],
  ["scripts/upstream-drift-vendored-report.sh", "enforcement"],
  [".github/scripts/recurring-schedule/file-due.mjs", "enforcement"],
  [".github/scripts/maintenance-monitor-signals/issues.mjs", "enforcement"],
  [".github/scripts/lib/github-rest.mjs", "enforcement"],
  ["plugins/work-items/scripts/charge-words.json", "enforcement"],
  [".github/scripts/pr-unblock/dependency-classify.mjs", "enforcement"],
  [".github/scripts/apply-patch/apply-patch.mjs", "enforcement"],
  [".github/scripts/apply-patch/predicates.mjs", "enforcement"],
  [".github/scripts/apply-patch/protected-paths.mjs", "enforcement"],
  [".github/scripts/apply-patch/cdn-paths.mjs", "enforcement"],
  ["lib/cdn-pins/pins.json", "enforcement"],
  ["lib/cdn-pins/sync.mjs", "enforcement"],
  [".github/scripts/lib/run-main.mjs", "enforcement"],
  [".github/scripts/pr-unblock/fix-ci-context.mjs", "enforcement"],
  [".github/scripts/pr-unblock/feedback-dispatch.mjs", "enforcement"],
  [".github/scripts/pr-unblock/verify-notes.mjs", "enforcement"],
  [".github/scripts/pr-unblock/earlier-fail-notes.mjs", "enforcement"],
  [".github/scripts/pr-unblock/limit-stop.mjs", "enforcement"],
  [".github/scripts/lib/lane-outcome.mjs", "enforcement"],
  [".github/scripts/lib/lane-binding.mjs", "enforcement"],
  [".github/scripts/pr-unblock/lane-record-cache.mjs", "enforcement"],
  [".github/scripts/pr-unblock/dispatch-record.mjs", "enforcement"],
  [".github/scripts/pr-unblock/verify-cap.mjs", "enforcement"],
  [".github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/stop-routes.json", "enforcement"],
  [".github/scripts/work-resolve-issue/stop-routes.mjs", "enforcement"],
  [".github/scripts/work-resolve-issue/known-names.json", "enforcement"],
  [".github/scripts/lib/stop-reason.mjs", "enforcement"],
  [".github/scripts/lib/admission-comment.mjs", "enforcement"],
  [".github/scripts/lib/admission-record.mjs", "enforcement"],
  [".github/scripts/lib/done-evidence.mjs", "trust"],
  [".github/scripts/pr-review-main/**", "gate"],
  [".github/scripts/diff-chunking/**", "gate"],
  ["docs/conventions/instruction-exception-register/**", "gate"],
  ["docs/conventions/untrusted-content/**", "gate"],
  ["docs/standards/**", "gate"],
  ["docs/review/**", "gate"],
  [".github/scripts/intake-triage/triage-rubric.txt", "gate"],
  [".github/scripts/intake-triage/refine-schema.json", "gate"],
  [".github/scripts/plugin-eval/policy-probe-prompt.txt", "gate"],
  [".github/scripts/pr-unblock/test-scope.mjs", "gate"],
  [".github/scripts/pr-unblock/declare-test-scope.mjs", "gate"],
  [".github/workflows/intake-reenter.yml", "gate"],
  [".github/workflows/intake-triage.yml", "gate"],
  [".github/workflows/maintenance-audit-lane-runs.yml", "gate"],
  [".github/workflows/maintenance-measure-skill-edit-pass.yml", "gate"],
  [".github/workflows/maintenance-measure-skill-edit.yml", "gate"],
  [".github/workflows/maintenance-reconcile-lost-runs.yml", "gate"],
  [".github/workflows/maintenance-tidy-code-upkeep.yml", "gate"],
  [".github/workflows/post-merge-file-demotion-issues.yml", "gate"],
  [".github/workflows/post-merge-test-mutation.yml", "gate"],
  [".github/workflows/pr-dispatch-feedback.yml", "gate"],
  [".github/workflows/pr-merge.yml", "gate"],
  [".github/workflows/pr-rate-merge-risk.yml", "gate"],
  [".github/workflows/pr-refine.yml", "gate"],
  [".github/workflows/pr-require-checks.yml", "gate"],
  [".github/workflows/pr-review-approved.yml", "gate"],
  [".github/workflows/pr-review-comment-relay.yml", "gate"],
  [".github/workflows/pr-review-hosted.yml", "gate"],
  [".github/workflows/pr-review-main.yml", "gate"],
  [".github/workflows/pr-review-security-hosted.yml", "gate"],
  [".github/workflows/pr-run-activity-read.yml", "gate"],
  [".github/workflows/pr-run-activity-write.yml", "gate"],
  [".github/workflows/pr-run-plugin-evals.yml", "gate"],
  [".github/workflows/pr-unblock-dispatch.yml", "gate"],
  [".github/workflows/pr-unblock.yml", "gate"],
  [".github/workflows/pr-verify.yml", "gate"],
  [".github/workflows/release-generate-dependabot-changelog-fragments.yml", "gate"],
  [".github/workflows/release-publish-plugins.yml", "gate"],
  [".github/workflows/upstream-apply-changelog.yml", "gate"],
  [".github/workflows/work-resolve-issue.yml", "gate"],
  [".github/workflows/work-unblock.yml", "gate"],
  // END hold-floor HOLD_PATH_CLASSES
]);
export const HOLD_PATH_FLOOR = Object.freeze(HOLD_PATH_CLASSES.filter(([, kind]) => kind !== "enforcement").map(([glob]) => glob));
export const REVIEW_FLOOR = Object.freeze(HOLD_PATH_CLASSES.filter(([, kind]) => kind === "enforcement").map(([glob]) => glob));

export const pathHold = (files, holdPaths, on = true) => pathHoldKind(files, holdPaths, on)?.reason ?? null;

export const pathHoldsOf = (value) => ![undefined, null, false, "false"].includes(value);

export function readPathHolds(path) {
  try {
    return pathHoldsOf(JSON.parse(readFileSync(path, "utf8"))?.merge?.["diff-check"]?.["path-holds"]);
  } catch {
    return true;
  }
}

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

export function costHold(files, decision) {
  const held = (Array.isArray(files) ? files : []).find((path) => {
    const folded = String(path).toLowerCase().replaceAll(/(^|\/)\./g, "$1\u0001.");
    return COST_PATHS.some((glob) => [glob, `${glob}/**`].some((each) => posix.matchesGlob(folded, each.toLowerCase())));
  });
  return held === undefined || decision ? null : `it changes ${held}, a cost path`;
}

const DECISION_LINK = /https:\/\/github\.com\/([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)\/(?:issues|pull)\/([0-9]+)#issuecomment-([0-9]+)/g;
const DECISION_LINE = /^\*\*Decision recorded\.\*\*[ \t]+Cost:/;
const DECISION_ROW =
  /https:\/\/github\.com\/melodic-software\/architecture\/blob\/(?:main|[0-9a-f]{40})\/docs\/owner-decisions\.md(?:\?plain=1)?#L[1-9][0-9]*(?:-L[1-9][0-9]*)?/;
const DECISION_QUOTE = /(?<![A-Za-z0-9_])verbatim:[ \t]*"[^"\n]*[^" \t\r\n][^"\n]*"/;
const DECISION_GAPS = {
  row: "a link to its row in the owner-decisions record (https://github.com/melodic-software/architecture/blob/<commit or main>/docs/owner-decisions.md#L<line>)",
  quote: 'the owner\'s words quoted verbatim (`verbatim: "<his words>"`)',
};

export function decisionGaps(body) {
  const text = String(body ?? "").replaceAll(HTML_COMMENT, "");
  return [...(DECISION_ROW.test(text) ? [] : [DECISION_GAPS.row]), ...(DECISION_QUOTE.test(text) ? [] : [DECISION_GAPS.quote])];
}
export const PULL_OPENED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { createdAt baseRefName headRefName closingIssuesReferences(first: 2) { totalCount nodes { number repository { nameWithOwner } } } }
  }
}`;
export const COMMENT_EDITED_QUERY = "query($id: ID!) { node(id: $id) { ... on IssueComment { lastEditedAt } } }";

export function namesPull(text, number) {
  return Number.isSafeInteger(number) && new RegExp(`(?:^|[^A-Za-z0-9_#&/.-])#${number}(?:[^0-9]|$)`).test(String(text ?? ""));
}

export const REVIEW_LANES = [
  ["pr-review-hosted.yml", ["PR Review / review-status", "pr-review / review-status", "PR Review / Status", "pr-review / Status", "PR Review / Publish Review", "pr-review / Publish Review"]],
  [
    "pr-review-security-hosted.yml",
    [
      "PR Review Security / review-status",
      "pr-review-security / review-status",
      "PR Review Security / Status",
      "pr-review-security / Status",
      "PR Review Security / Publish Review",
      "pr-review-security / Publish Review",
    ],
  ],
];
const HOLD_NOTICE = /^claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=([a-z,-]+) label=/;
const BRANCH = /^(?!-)(?!.*\.\.)[A-Za-z0-9._/-]{1,255}$/;

export function laneChange(compare) {
  const files = compare?.files;
  if (!Array.isArray(files)) return "no file list";
  if (files.length >= 300) return "too many files";
  const lanes = REVIEW_LANES.map(([file]) => `.github/workflows/${file}`);
  return files.some((f) => lanes.includes(f?.filename)) ? "a review-lane workflow" : null;
}

// https://docs.github.com/en/rest/commits/commits#compare-two-commits
const COMPARE_FILES_CAP = 300;
// https://docs.github.com/en/rest/repos/contents#get-repository-content
const DIRECTORY_CAP = 1000;

const shasOf = (entries) => (Array.isArray(entries) && entries.length < DIRECTORY_CAP ? new Map(entries.map((entry) => [String(entry?.name), String(entry?.sha)])) : null);

async function objectShas(read, repo, dir, ref) {
  return shasOf(await read("GET", `/repos/${repo}/contents/${dir}?ref=${ref}`));
}

export async function changedPaths(read, repo, compare, to, paths) {
  const files = compare?.files;
  if (!Array.isArray(files)) return null;
  if (files.length < COMPARE_FILES_CAP) {
    const names = files.flatMap((f) => [f?.filename, f?.previous_filename]).filter((name) => typeof name === "string");
    return paths.flatMap((path) => names.filter((name) => name === path || name.startsWith(`${path}/`)).slice(0, 1));
  }
  const from = compare?.merge_base_commit?.sha;
  if (!isSha(from) || !isSha(to)) return null;
  const changed = [];
  const listings = new Map();
  for (const path of paths) {
    const dir = posix.dirname(path);
    if (!listings.has(dir)) {
      const ends = [await objectShas(read, repo, dir, from), await objectShas(read, repo, dir, to)];
      listings.set(dir, ends.includes(null) ? null : ends);
    }
    const ends = listings.get(dir);
    if (ends === null) return null;
    const name = posix.basename(path);
    if (ends[0].get(name) !== ends[1].get(name)) changed.push(path);
  }
  return changed;
}

export function laneChangeListed(compare, from, to) {
  const why = laneChange(compare);
  const ends = [shasOf(from), shasOf(to)];
  if (why !== "too many files" || !isSha(compare?.merge_base_commit?.sha) || ends.includes(null)) return why;
  return REVIEW_LANES.some(([file]) => ends[0].get(file) !== ends[1].get(file)) ? "a review-lane workflow" : null;
}

export async function laneChangeIn(read, repo, compare, head) {
  const why = laneChange(compare);
  const from = compare?.merge_base_commit?.sha;
  if (why !== "too many files" || !isSha(from) || !isSha(head)) return why;
  const listing = (ref) => read("GET", `/repos/${repo}/contents/.github/workflows?ref=${ref}`);
  return laneChangeListed(compare, await listing(from), await listing(head));
}

export function costNotices(annotations, head, at) {
  return (Array.isArray(annotations) ? annotations : []).flatMap((a) => {
    const notice = a?.annotation_level === "notice" ? HOLD_NOTICE.exec(String(a.message ?? "")) : null;
    return notice && notice[1] === head && notice[2].split(",").includes("cost") ? [{ sha: notice[1], at }] : [];
  });
}

export function decidedHead(notices, at) {
  const cutoff = Date.parse(at);
  const before = notices.filter((n) => Date.parse(n.at) < cutoff);
  const newest = Math.max(...before.map((n) => Date.parse(n.at)));
  const heads = new Set(before.filter((n) => Date.parse(n.at) === newest).map((n) => n.sha));
  return heads.size === 1 ? [...heads][0] : null;
}

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
    if (isSha(after) && !/^0{40}$/.test(after)) {
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

async function noticedHead(read, repo, branch, base, at) {
  const cutoff = Date.parse(at);
  if (!Number.isFinite(cutoff) || typeof branch !== "string" || !BRANCH.test(branch)) {
    return null;
  }
  const notices = [];
  const vetted = new Set();
  const ran = [];
  for (const [file, checks] of REVIEW_LANES) {
    const runs = await pages(read, `/repos/${repo}/actions/workflows/${file}/runs?event=pull_request&branch=${encodeURIComponent(branch)}`, "workflow_runs");
    const heads = [];
    ran.push(heads);
    for (const run of runs) {
      if (run?.head_repository?.full_name !== repo || !(Date.parse(run.created_at) < cutoff)) {
        continue;
      }
      const head = String(run.head_sha ?? "");
      if (!isSha(head)) {
        return null;
      }
      heads.push(head);
      if (!vetted.has(head)) {
        if ((await laneChangeIn(read, repo, await read("GET", `/repos/${repo}/compare/${base}...${head}`), head)) !== null) {
          return null;
        }
        vetted.add(head);
      }
      for (const job of await pages(read, `/repos/${repo}/actions/runs/${run.id}/jobs?filter=all`, "jobs")) {
        if (checks.includes(job?.name) && Date.parse(job.completed_at) < cutoff) {
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

export const LINK = Symbol.for("github.link");
export const ACTIVITY_PAGES = 20;

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
    after = /[?&]after=([^&#]+)/.exec(next[1])?.[1];
    if (!after || cursors.has(after)) {
      throw new Error("the branch's push history names no new page");
    }
    cursors.add(after);
  }
  throw new Error(`the branch's push history runs past ${ACTIVITY_PAGES} pages`);
}

const unedited = (node) => Boolean(node) && "lastEditedAt" in node && node.lastEditedAt === null;

export function sameNetChange(decided, current, diffs = null) {
  const net = (files, capped) => {
    if (!Array.isArray(files) || (capped && files.length >= COMPARE_FILES)) return null;
    const byName = new Map();
    for (const f of files) {
      if (typeof f?.filename !== "string" || typeof f.patch !== "string" || byName.has(f.filename)) return null;
      byName.set(f.filename, JSON.stringify([f.status ?? null, f.previous_filename ?? null, f.patch, f.modes ?? null]));
    }
    return byName;
  };
  let [then, now] = [net(decided?.files, true), net(current?.files, true)];
  if (Array.isArray(diffs) && diffs.length === 2) {
    const parsed = diffs.map(diffFiles);
    if (!diffCovers(decided, parsed[0]) || !diffCovers(current, parsed[1])) return false;
    [then, now] = parsed.map((files) => net(files, false));
  }
  return then !== null && now !== null && then.size === now.size && [...then].every(([name, value]) => now.get(name) === value);
}

// https://docs.github.com/en/rest/commits/commits#compare-two-commits
export const COMPARE_FILES = 300;

export const needsDiff = (compare) =>
  Array.isArray(compare?.files) && (compare.files.length >= COMPARE_FILES || compare.files.some((f) => typeof f?.patch !== "string"));

export const DIFF = "application/vnd.github.diff";

export function diffCovers(compare, files) {
  if (!Array.isArray(files) || !Array.isArray(compare?.files) || files.length < compare.files.length) return false;
  const byName = new Map(files.map((f) => [f.filename, f]));
  return compare.files.every((f) => byName.has(f?.filename) && (f.previous_filename ?? null) === (byName.get(f.filename).previous_filename ?? null));
}

export async function wholeCompare(read, readDiff, path) {
  const whole = { ...(await read(`${path}?per_page=100&page=1`)) };
  if (Array.isArray(whole.commits)) {
    whole.commits = [...whole.commits];
    for (let page = 2; whole.commits.length < whole.total_commits && whole.commits.length === (page - 1) * 100; page += 1) {
      const more = (await read(`${path}?per_page=100&page=${page}`))?.commits;
      if (Array.isArray(more)) whole.commits.push(...more);
    }
  }
  if (readDiff && Array.isArray(whole.files) && whole.files.length >= COMPARE_FILES) {
    const files = diffFiles(await readDiff(path));
    if (files === null) throw new Error(`the diff of ${path} does not parse`);
    if (!diffCovers(whole, files)) throw new Error(`the diff of ${path} names fewer files than its listing`);
    whole.files = files;
  }
  return whole;
}

// https://docs.github.com/en/rest/commits/commits#compare-two-commits
export const wholeCommits = async (read, path, answer) =>
  Array.isArray(answer?.commits) && Number.isInteger(answer.total_commits) && answer.commits.length < answer.total_commits ? wholeCompare(read, null, path) : answer;

const capDiffs = async (github, repo, ranges, compares) =>
  compares.some(needsDiff) ? Promise.all(ranges.map((range) => github("GET", `/repos/${repo}/compare/${range}`, undefined, { Accept: DIFF }))) : null;

export function diffFiles(text) {
  if (typeof text !== "string") return null;
  const lines = text.split("\n");
  if (lines.at(-1) === "") lines.pop();
  const sections = [];
  for (const line of lines) {
    if (line.startsWith("diff --git ")) sections.push([line.slice("diff --git ".length)]);
    else if (sections.length) sections.at(-1).push(line);
    else return null;
  }
  const files = [];
  for (const [names, ...rest] of sections) {
    const file = { status: "modified", modes: [] };
    const sides = {};
    let at = 0;
    for (; at < rest.length && !rest[at].startsWith("@@"); at += 1) {
      const line = rest[at];
      const [, key, value] = /^(old mode|new mode|new file mode|deleted file mode|rename from|rename to|copy from|copy to|similarity index|dissimilarity index|index|---|\+\+\+|Binary files|GIT binary patch)(?: (.*))?$/.exec(line) ?? [];
      if (key === undefined) return null;
      if (key.endsWith("mode")) file.modes.push(line);
      if (key === "new file mode") file.status = "added";
      if (key === "deleted file mode") file.status = "removed";
      if (/^(rename|copy) /.test(key)) {
        if (!value || value.startsWith('"')) return null;
        file.status = key.startsWith("rename") ? "renamed" : "copied";
        sides[key.endsWith("from") ? "from" : "to"] = value;
      }
      if (key === "---" || key === "+++") {
        const path = value?.includes(" ") ? value.replace(/\t$/, "") : value;
        const prefix = key === "---" ? "a/" : "b/";
        if (path !== "/dev/null" && !path?.startsWith(prefix)) return null;
        if (path !== "/dev/null") sides[key === "---" ? "old" : "new"] = path.slice(2);
      }
      if (key === "Binary files" || key === "GIT binary patch") {
        at = rest.length;
        file.binary = true;
      }
    }
    const half = (names.length - 5) / 2;
    const same = names.slice(2, 2 + half);
    const symmetric = names === `a/${same} b/${same}` && !same.startsWith('"') ? same : undefined;
    file.filename = sides.to ?? sides.new ?? sides.old ?? symmetric;
    if (typeof file.filename !== "string") return null;
    if (sides.from !== undefined) file.previous_filename = sides.from;
    const hunks = file.binary ? [] : rest.slice(at);
    if (!file.binary) file.patch = hunks.join("\n");
    if (!hunks.length && file.status === "modified" && file.modes.length) file.status = "changed";
    delete file.binary;
    files.push(file);
  }
  return files;
}

export const listedCommits = (compare) =>
  Array.isArray(compare?.commits) && Number.isInteger(compare.total_commits) && compare.total_commits === compare.commits.length ? compare.commits : null;

function newCommits(then, now) {
  const [before, after] = [listedCommits(then), listedCommits(now)];
  if (before === null || after === null) return null;
  const old = new Set(before.map((c) => c?.sha));
  return after.filter((c) => !old.has(c?.sha));
}

export function mergedParents(then, now) {
  const parents = (newCommits(then, now) ?? []).flatMap((c) => (Array.isArray(c?.parents) ? c.parents.slice(1).map((p) => p?.sha) : []));
  return [...new Set(parents.filter(isSha))];
}

export function baseMergesOnly(then, now, from, inBase = new Set()) {
  const added = newCommits(then, now);
  return (
    added !== null &&
    now.commits.some((c) => c?.sha === from) &&
    added.every((c) => Array.isArray(c?.parents) && c.parents.length >= 2 && c.parents.slice(1).every((p) => inBase.has(p?.sha)))
  );
}

export function baseMergeCarry(then, now, from, inBase = [], diffs = null, changed = undefined) {
  const whole = diffs === null || (Array.isArray(diffs) && Number.isInteger(changed) && diffFiles(diffs[1])?.length === changed);
  return whole && baseMergesOnly(then, now, from, new Set(inBase)) && sameNetChange(then, now, diffs);
}

export function exactBaseCarry(merges, based, trees = null, diffs = null) {
  const forward = (compare, statuses) => statuses.includes(compare?.status) && compare.behind_by === 0 && listedCommits(compare) !== null;
  return forward(merges, ["ahead"]) && forward(based, ["ahead", "identical"]) && sameNetChange(merges, based, diffs) && sameModes(diffs === null ? merges : { files: diffFiles(diffs[0]) }, trees);
}

function sameModes(merges, trees) {
  const modes = (tree) => {
    if (tree?.truncated !== false || !Array.isArray(tree.tree)) return null;
    const byPath = new Map();
    for (const entry of tree.tree) {
      if (typeof entry?.path === "string" && typeof entry.mode === "string" && entry.type !== "tree") byPath.set(entry.path, entry.mode);
    }
    return byPath;
  };
  if (!Array.isArray(trees) || trees.length !== 2 || !Array.isArray(merges?.files)) return false;
  const [head, base] = trees.map(modes);
  if (head === null || base === null) return false;
  return merges.files.every((f) => {
    const gone = [...(f.status === "removed" ? [f.filename] : []), ...(typeof f.previous_filename === "string" ? [f.previous_filename] : [])];
    const kept = f.status === "removed" ? [] : [f.filename];
    return gone.every((path) => !head.has(path) && !base.has(path)) && kept.every((path) => head.has(path) && head.get(path) === base.get(path));
  });
}

export function approvalCarry(then, now, from, inBase, merges, based, dismissal = null, trees = null, holdPaths = undefined, diffs = null, mergeDiffs = null) {
  const pushed = (commits) => dismissal === null || (commits ?? []).some((c) => c?.sha === dismissal);
  const merged = baseMergesOnly(then, now, from, new Set(inBase)) && pushed(newCommits(then, now)) && (sameNetChange(then, now, diffs) || exactBaseCarry(merges, based, trees, mergeDiffs));
  return merged || (holdPaths !== undefined && ungatedSince(merges, holdPaths, mergeDiffs?.[0] ?? null) && pushed(listedCommits(merges)));
}

export const CARRY_REFUSES = Object.freeze([".github/workflows/**", ".github/actions/**", ".github/scripts/**", ".github/standards/**", "docs/conventions/pr-pipeline/**", "scripts/**", "lib/**", "plugins/source-control/skills/babysit-prs/scripts/**", "plugins/performance/scripts/**", "plugins/harness-ops/skills/inventory/scripts/**", "plugins/ai-briefing/skills/generate/scripts/**", "plugins/harness-config/skills/audit-permission-state/scripts/**", "plugins/knowledge/skills/course-digest/scripts/**", "plugins/knowledge/skills/video-digest/scripts/**", "plugins/skill-quality/scripts/**", "plugins/source-control/scripts/**", "plugins/testing/skills/check-visual-parity/scripts/**", "plugins/testing/skills/run-e2e/scripts/**", "plugins/testing/scripts/**", ".github/recurring-schedule.json", "docs/upstream/**", "plugins/evals/skills/validate/scripts/**", "plugins/evals/skills/plugin-eval/scripts/**", "plugins/testing/evals/browser-probe/**", "plugins/work-items/scripts/**", "plugins/work-items/tools/work-item-tracker/**", "plugins/harness-ops/skills/changelog/scripts/**", "plugins/instruction-placement/scripts/**", "plugins/app-control/scripts/**", "plugins/formal-verification/scripts/**", "plugins/formal-verification/lib/**", "plugins/formal-verification/defaults.json", "plugins/formal-verification/schemas/**", "plugins/code-metrics/scripts/**", "plugins/code-metrics/skills/audit/scripts/**", "plugins/work-items/skills/triage/scripts/**", "plugins/work-items/skills/triage/schemas/**", "plugins/guardrails/git-hooks/reference-verify.sh", "plugins/bash-format/git-hooks/lint-full.sh", "plugins/code-tidying/git-hooks/comment-lint-ci.sh"]);

export function ungatedSince(merges, holdPaths, diff = null) {
  const listed = merges?.files;
  if (merges?.status !== "ahead" || merges.behind_by !== 0 || listedCommits(merges) === null || !Array.isArray(listed)) return false;
  const files = listed.length >= COMPARE_FILES ? diffFiles(diff) : listed;
  if (files !== listed && !diffCovers(merges, files)) return false;
  if (!files.every((f) => typeof f?.filename === "string")) return false;
  const paths = files.flatMap((f) => [f.filename, ...(typeof f.previous_filename === "string" ? [f.previous_filename] : [])]);
  const loaded = [...REVIEW_FLOOR, ...CARRY_REFUSES];
  return Array.isArray(holdPaths) && pathHold(paths, holdPaths) === null && !paths.some((path) => loaded.some((glob) => matchesHoldPath(path, glob)));
}

const reviewKey = (value) => (typeof value === "string" ? value : Number.isSafeInteger(value) ? String(value) : null);

export function autoDismissed(events) {
  const found = new Map();
  const revoked = new Set();
  for (const e of Array.isArray(events) ? events : []) {
    if (e?.event !== "review_dismissed") continue;
    const d = e.dismissed_review;
    const id = reviewKey(d?.review_id);
    if (id === null) continue;
    const stale = d?.state === "approved" && d.dismissal_message === null && e.actor?.type === "Bot" && isSha(d.dismissal_commit_id);
    if (stale && !found.has(id)) found.set(id, d.dismissal_commit_id);
    else revoked.add(id);
  }
  for (const id of revoked) found.delete(id);
  return found;
}

export async function baseParents(compare, tip, then, now) {
  const inBase = new Set();
  for (const sha of mergedParents(then, now)) {
    if (["ahead", "identical"].includes((await compare(`${sha}...${tip}`))?.status)) inBase.add(sha);
  }
  return inBase;
}

export async function baseTip(github, repo, base, mainTip = undefined) {
  if (base === "main" && isSha(mainTip)) return mainTip;
  const sha = (await github("GET", `/repos/${repo}/git/ref/heads/${base}`))?.object?.sha;
  if (!isSha(sha)) throw new Error(`the base branch ${base} did not resolve`);
  return sha;
}

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
    if (!isSha(r.commitId) ||(r.state !== "APPROVED" && restored === null)) return [];
    return [{ login: r.login, sha: r.commitId, dismissal: restored }];
  });
}

export async function liftersOf(github, repo, number, head, humans, holdPaths = undefined, { mainTip } = {}) {
  try {
    const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
    const base = pull?.base?.ref;
    if (pull?.head?.sha !== head || pull?.head?.repo?.full_name !== repo || !BRANCH.test(String(base))) return { lifters: [] };
    const reviews = (await pages(github, `/repos/${repo}/pulls/${number}/reviews`)).map(fromRest);
    const dismissed = reviews.some((r) => r.isUser && humans.has(r.userId) && r.state === "DISMISSED")
      ? await pages(github, `/repos/${repo}/issues/${number}/timeline`).then(autoDismissed, () => new Map())
      : new Map();
    const lifts = liftsOf(reviews, humans, dismissed);
    const carrying = lifts.some(({ sha }) => sha !== head) && (await github("GET", `/repos/${repo}`))?.default_branch === base;
    const tip = carrying ? await baseTip(github, repo, base, mainTip) : null;
    const compares = new Map();
    const compare = async (range) => {
      if (!compares.has(range)) compares.set(range, await github("GET", `/repos/${repo}/compare/${range}`));
      return compares.get(range);
    };
    const whole = async (range) => wholeCommits((path) => github("GET", path), `/repos/${repo}/compare/${range}`, await compare(range));
    const treeReads = new Map();
    const tree = async (sha) => {
      if (!treeReads.has(sha)) treeReads.set(sha, await github("GET", `/repos/${repo}/git/trees/${sha}?recursive=1`));
      return treeReads.get(sha);
    };
    const sha40 = (value) => (isSha(value) ? value : null);
    const lifters = new Set();
    for (const { login, sha, dismissal } of lifts) {
      if (sha === head) {
        if (dismissal === null) lifters.add(login);
        continue;
      }
      if (!carrying) continue;
      const [then, now] = [await whole(`${tip}...${sha}`), await whole(`${tip}...${head}`)];
      const diffs = await capDiffs(github, repo, [`${tip}...${sha}`, `${tip}...${head}`], [then, now]);
      const listed = diffs ? diffFiles(diffs[1])?.length : now?.files?.length;
      if (!Array.isArray(now?.files) || listed !== pull.changed_files) continue;
      const inBase = await baseParents(compare, tip, then, now);
      let [merges, based, trees, mergeDiffs] = [null, null, null, null];
      const [from, to] = [sha40(then?.merge_base_commit?.sha), sha40(now?.merge_base_commit?.sha)];
      if (baseMergesOnly(then, now, sha, inBase) && !sameNetChange(then, now, diffs) && from && to) {
        [merges, based] = [await whole(`${sha}...${head}`), await whole(`${from}...${to}`)];
        mergeDiffs = await capDiffs(github, repo, [`${sha}...${head}`, `${from}...${to}`], [merges, based]);
        trees = [await tree(head), await tree(to)];
      }
      if (approvalCarry(then, now, sha, inBase, merges, based, dismissal, trees, undefined, diffs, mergeDiffs)) {
        lifters.add(login);
        continue;
      }
      if (holdPaths !== undefined && merges === null) {
        merges = await whole(`${sha}...${head}`).catch(() => null);
      }
      if (holdPaths !== undefined && mergeDiffs === null && merges !== null) {
        mergeDiffs = await capDiffs(github, repo, [`${sha}...${head}`], [merges]).catch(() => null);
      }
      if (holdPaths !== undefined && approvalCarry(then, now, sha, inBase, merges, based, dismissal, trees, holdPaths, diffs, mergeDiffs)) lifters.add(login);
    }
    return { lifters: [...lifters].sort() };
  } catch {
    return { lifters: [] };
  }
}

async function pages(github, path, key = null) {
  const rows = [];
  for (let page = 1; ; page += 1) {
    const answer = await github("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    const items = key === null ? answer : answer?.[key];
    if (!Array.isArray(items)) {
      throw new Error(key === null ? `${path} is not a list` : `${path} has no ${key} list`);
    }
    rows.push(...items);
    if (items.length < 100) {
      return rows;
    }
  }
}

async function carries(github, actions, repo, comment, head, base, branch, number) {
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
    const whole = async (range) => wholeCommits((path) => github("GET", path), `/repos/${repo}/compare/${range}`, await compare(range));
    const then = await whole(`${tip}...${decided}`);
    const now = await whole(`${tip}...${head}`);
    const diffs = await capDiffs(github, repo, [`${tip}...${decided}`, `${tip}...${head}`], [then, now]);
    const changed = diffs ? (await github("GET", `/repos/${repo}/pulls/${number}`))?.changed_files : undefined;
    return baseMergeCarry(then, now, decided, await baseParents(compare, tip, then, now), diffs, changed);
  } catch {
    return false;
  }
}

export async function costDecision(github, repo, number, body, humans, head, actions = github, missing = null) {
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
    }
  }
  const at = (d) => {
    const made = Date.parse(d.comment.created_at);
    return Number.isNaN(made) ? -Infinity : made;
  };
  const newest = (own) => decisions.filter((d) => d.own === own).reduce((best, d) => (best === undefined || at(d) > at(best) ? d : best), undefined);
  const decision = newest(true) ?? newest(false);
  const gaps = decision ? decisionGaps(decision.comment.body) : [];
  missing?.push(...gaps);
  return decision && !gaps.length && (await carries(github, actions, repo, decision.comment, head, pull?.baseRefName, pull?.headRefName, number)) ? decision.link : null;
}

const fetchGitHub = (env) => async (method, path, body, headers = {}) => {
  const response = await fetch(`${env.GITHUB_API_URL || "https://api.github.com"}${path}`, {
    method,
    headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GH_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (headers.Accept === DIFF) {
    if (!response.ok) throw new Error(`${method} ${path} failed with status ${response.status}`);
    return response.text();
  }
  const json = response.ok ? await response.json() : null;
  if (json === null || json.errors?.length) {
    throw new Error(`${method} ${path} failed with status ${response.status}`);
  }
  if (Array.isArray(json)) {
    Object.defineProperty(json, LINK, { value: response.headers.get("link") });
  }
  return json;
};

export function holdPathsOf(denied) {
  return Array.isArray(denied) && denied.every((glob) => typeof glob === "string") ? denied : null;
}

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

export function holds(body, items, files, holdPaths, lifters = [], decision = null, byPerson = true, pathHolds = true, missing = []) {
  const reasons = [];
  const pathReason = pathHold(files, holdPaths, pathHolds);
  const readable = Array.isArray(files) && Array.isArray(holdPaths);
  if (pathReason && !(readable && lifters.length)) {
    reasons.push(readable ? `${pathReason}; ${APPROVAL_CARRIES}` : pathReason);
  }
  const cost = costHold(files, decision);
  if (cost) {
    reasons.push(
      `${cost}; the owner's unedited comment opening '**Decision recorded.** Cost:' on this pull request, or on its linked issue naming this pull request, linked from the body and carrying a link to its row in the owner-decisions record and the owner's words quoted verbatim, lifts it for the head it decided and a later head that only merges the base${missing.length ? `; the linked decision comment lacks ${missing.join(" and ")}` : ""}`,
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

export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
const PASSES = Object.freeze(["pass", "pass-notes"]);

export function verdictHold(records, repo, branch = "main") {
  if (!Array.isArray(records) || !isRepo(repo)) {
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

export const VERIFIER_TITLE = "pr-verify hold";

const PASS_REFUSALS = Object.freeze(["verify:missing", "verify:spec-changed", "verify:untrusted-spec"]);

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

export function passRefusalOf(evidence, head) {
  return evidence?.head === head && PASS_REFUSALS.includes(evidence.refusal) ? evidence.refusal : null;
}

const STALE = "verify:spec-changed";

const escape = (text) => String(text).replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");

export const humansOf = (actors) =>
  new Set(actors.filter((actor) => actor?.kind === "human" && Number.isInteger(actor?.id)).map(({ id }) => id));

function linkOf(file, body, repo) {
  try {
    const { record, closing } = JSON.parse(readFileSync(file, "utf8"));
    return linkHold(record, body, closing, repo);
  } catch {
    return "its issue link could not be checked against its verifier pass";
  }
}

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

export const TRACKER_BINDING_PATH = "docs/conventions/work-items.yaml";

export function trackerBindingText(path) {
  const text = readFileSync(path, "utf8");
  if (!String(path).endsWith(".yaml")) {
    return text;
  }
  try {
    return execFileSync("yq", ["-o=json", "-I=0", ".tracker", "-"], { input: text, encoding: "utf8", timeout: 30_000, maxBuffer: 1 << 20 });
  } catch (error) {
    throw new Error(`yq could not read ${path}: ${error.code ?? error.message}`);
  }
}

export function humanGatedLabel(tracker) {
  const label = tracker?.config?.role_labels?.["human-gated"];
  return typeof label === "string" && label.trim() ? label.trim() : "needs-human";
}

export const OUTSIDE_ACTOR_LABEL = "security: outside-actor";

export const UNTRUSTED_LABEL = "provenance: untrusted";
export const UNTRUSTED_LABELS = Object.freeze([UNTRUSTED_LABEL]);

export const PR_VERIFY_FAILED_LABEL = "pr-verify-failed";

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
      `#${number} carries '${PR_VERIFY_FAILED_LABEL}': pr-verify failed its head, and a pr-verify pass removes the label, at a new commit or at the same head: once a trusted person edits the body, and only trusted people have edited it since the fail, that head is judged again, so a fail on the body or the issues it links needs only the body fixed, no new commit. The merge queue removes it; re-queue it once the label is off.`,
    names.has(OUTSIDE_ACTOR_LABEL) &&
      `#${number} carries '${OUTSIDE_ACTOR_LABEL}': someone outside the organization wrote on it, and only a person removes the label. Re-queue it once the label is off.`,
  ].filter(Boolean);
}

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

export function queueHolds({ pull, tracker = null, lanes = {} } = {}) {
  const head = pull?.head?.sha;
  if (!Number.isInteger(pull?.number) || typeof head !== "string") {
    throw new Error("the pull request does not read");
  }
  return [...labelHolds(pull.labels, tracker, pull.number), switchHold(pull, lanes)].filter(Boolean);
}

function pullAuthor(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"))?.user ?? null;
  } catch {
    return null;
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
      !isSha(head)
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
    const approved = pathLifters(items, humans, head);
    const body = readFileSync(bodyFile, "utf8");
    const repo = String(env.GITHUB_REPOSITORY);
    const missing = [];
    const decision = costHold(files, null) && isRepo(repo) ? await costDecision(github, repo, Number(number), body, humans, head, github, missing) : null;
    if (decision) {
      console.log(`#${number}: ${decision} records the owner's cost decision, which lifts its cost hold.`);
    }
    const pathHolds = env.PATH_HOLDS !== "false";
    const skipped = pathHolds ? null : pathHoldKind(files, holdPaths);
    if (skipped?.kind === "hold-path") {
      console.log(`#${number}: path holds are off (merge.diff-check.path-holds), so nothing holds it for this: ${escape(skipped.reason)}.`);
    }
    const held = pathHold(files, holdPaths, pathHolds);
    let lifted = { lifters: [] };
    if (!approved.length && held && Array.isArray(holdPaths) && isRepo(repo)) {
      lifted = await liftersOf(github, repo, Number(number), head, humans, holdPaths);
    }
    const lifters = approved.length ? approved : lifted.lifters;
    const reasons = holds("", items, files, holdPaths, lifters, decision, true, pathHolds, missing);
    const how = approved.length ? "approved this head" : "approved an earlier head whose every change since is a base merge";
    if (held && lifters.length && Array.isArray(holdPaths)) {
      console.log(`#${number}: ${lifters.join(", ")} ${how}, which lifts its hold path (${escape(held)}).`);
    }
    const verifier = [];
    if (verdictsFile && baselineOnly(pullAuthor(env.BABYSIT_VERIFY_PULL), files, env.LANES_APP_ID, env.BASELINE_FILE)) {
      console.log(`#${number}: no verifier hold: ${baselineNote(env.BASELINE_FILE)}.`);
      console.log(`#${number}: no pr-verify FAIL hold: ${baselineNote(env.BASELINE_FILE)}.`);
    } else if (verdictsFile) {
      const records = lines(verdictsFile).map((line) => JSON.parse(line));
      let unverified = verdictHold(records, env.GITHUB_REPOSITORY);
      let evidence;
      if (evidenceFile) {
        try {
          evidence = JSON.parse(readFileSync(evidenceFile, "utf8"));
        } catch {
          evidence = undefined;
        }
      }
      const refused = passRefusalOf(evidence, head);
      if (refused === STALE) {
        unverified = `pr-verify's pass on this head is stale (${STALE}): its linked issue changed after pr-verify judged it`;
      } else if (unverified && records.length === 0 && refused) {
        unverified = `pr-verify's reader refuses this head's pass (${refused})`;
      }
      const relinked = unverified || approved.length ? null : linkFile ? linkOf(linkFile, body, repo) : "its issue link could not be checked against its verifier pass";
      if (!unverified && !relinked) {
        console.log(`#${number}: no verifier hold: pr-verify passed this head.`);
      } else if (!unverified && approved.length === 0) {
        verifier.push(`${relinked}; pr-verify does not judge this head again, so push a new head for it to judge, after which enable-auto-merge arms it again, or ${APPROVAL_LIFTS}, then re-queue`);
      } else if (approved.length) {
        console.log(`#${number}: no verifier hold: ${approved.join(", ")} approved this head, which lifts '${unverified}'.`);
      } else {
        verifier.push(`${unverified}; wait for pr-verify to pass it, after which enable-auto-merge arms it again, or ${APPROVAL_LIFTS}, then re-queue`);
      }
      const failed = evidenceHold(evidence, head);
      if (!failed) {
        const { refusal } = evidence;
        console.log(`#${number}: no pr-verify FAIL hold: ${refusal ? `the reader refuses this head only on its pass (${refusal})` : "the reader allows this head"}.`);
      } else if (approved.length) {
        console.log(`#${number}: no pr-verify FAIL hold: ${approved.join(", ")} approved this head, which lifts '${escape(failed)}'.`);
      } else {
        verifier.push(`${failed}; push a new head for pr-verify to judge, after which enable-auto-merge arms it again, or ${APPROVAL_LIFTS}, then re-queue`);
      }
    }
    const unpinned = verdictsFile ? pinHold(await withPinEdit(github, items), head) : null;
    if (unpinned && approved.length) {
      console.log(`#${number}: no pin hold: ${approved.join(", ")} approved this head, which lifts '${escape(unpinned)}'.`);
    }
    const pinHeld = unpinned !== null && approved.length === 0;
    for (const reason of reasons) {
      console.log(`::error::#${number}: ${escape(reason)}.`);
    }
    if (pinHeld) {
      console.log(`::error::#${number}: ${escape(unpinned)}.`);
    }
    for (const reason of verifier) {
      console.log(`::error title=${VERIFIER_TITLE}::#${number}: ${escape(reason)}.`);
    }
    if (!reasons.length) {
      console.log(`#${number}: no member veto and no hold path.`);
    }
    return reasons.length || verifier.length || pinHeld ? 1 : 0;
  } catch (error) {
    console.log(`::error::merge-holds: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
