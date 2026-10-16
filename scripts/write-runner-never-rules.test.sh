#!/usr/bin/env bash
# Structure test: pr-run-activity-write.yml keeps every clause of the
# resolve-conflicts `never` row in .github/actions/resolve-config/activity-rules.json
# ("Force-pushes, pushes .github/workflows changes, or runs head code"), and
# hands the report-escalation script the base's tracker config.
#
# Reads the workflow as YAML (the runner-policy `yaml` package, which CI
# installs for check-read-caller-keys.test.sh) and asserts on step order,
# conditions and step bodies. What it cannot assert from this file:
#   - The skill's own allowed-tools Bash grant (its SKILL.md) and its token:
#     with a contents-write token the model could push or run head code
#     itself. The backstops are the App's missing `workflows` permission and
#     ADR 0055's accepted residual, not this file.
#   - That post.sh detects every workflow change; its own .test.sh owns that.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/actions/resolve-config/activity-rules.json .github/actions/collect-base-activity/action.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

results=$(
  cd "$ROOT" && node --input-type=module - <<'EOF'
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(`${process.cwd()}/.github/standards/runner-policy/package.json`);
const YAML = require("yaml");

const say = (good, text) => console.log(`${good ? "ok" : "fail"}\t${text}`);
const rules = JSON.parse(readFileSync(".github/actions/resolve-config/activity-rules.json", "utf8"));
const never = rules["resolve-conflicts"]?.never ?? "";
// The row this suite guards; a reworded row needs this suite reread.
say(never === "Force-pushes, pushes .github/workflows changes, or runs head code",
  `the resolve-conflicts never row is the one this suite asserts (got ${JSON.stringify(never)})`);

const wf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-write.yml", "utf8"));
const steps = wf.jobs.run.steps;
const at = (pred) => steps.findIndex(pred);
const byId = (id) => steps.find((s) => s.id === id) ?? {};
const checkout = at((s) => s.name === "Check out the PR head");
const mint = at((s) => s.id === "lane-token");
const body = (s) => `${s.run ?? ""}${s.with?.script ?? ""}`;
const after = steps.slice(checkout + 1);

// Clause 1: no force-push.
const updates = steps.flatMap((s) => body(s).match(/updateRef\([^)]*\)/g) ?? []);
say(updates.length >= 2, `the run job updates refs through updateRef (${updates.length} calls)`);
say(updates.every((u) => /force: false/.test(u)), "every updateRef call passes force: false");
say(!steps.some((s) => /git\s+push|--force|\+refs\//.test(body(s))), "no step runs git push or a forced refspec"); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
say(!steps.some((s) => /(update|create)Ref\(/.test(body(s)) && /Ref\([^)]*force:\s*true/.test(body(s))), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "no ref update sets force: true");

// Clause 2: no .github/workflows change is pushed by the runner.
const post = byId("post");
const commit = byId("commit");
say(/bash "\$BIN\/post\.sh"/.test(post.run ?? ""), "the post step runs the base copy of post.sh");
say(/workflow-staged\)?[^\n]*\n?[^\n]*skip-reason=awaiting-human|unresolved-conflict \| workflow-staged\)/.test(post.run ?? ""),
  "the post step turns workflow-staged into an escalation (awaiting-human)");
say(/tree=""/.test(post.run ?? ""), "an escalating post step clears its tree output");
const commitIf = String(commit.if ?? "");
say(/steps\.post\.outcome == 'success'/.test(commitIf) && /steps\.post\.outputs\.escalation-reason == ''/.test(commitIf)
  && /steps\.post\.outputs\.tree != ''/.test(commitIf),
  "the commit step runs only after post.sh succeeded with no escalation reason and a tree");
say(at((s) => s.id === "post") < at((s) => s.id === "commit") && at((s) => s.id === "commit") < at((s) => s.id === "promote"),
  "post, commit and promote run in that order");
say(/tree !== TREE/.test(commit.with?.script ?? ""), "the commit step refuses a tree other than post.sh's");
const prepare = byId("prepare");
say(/protected-path-conflict/.test(prepare.run ?? ""), "a conflicted workflow path escalates before any model turn");

// Clause 3: no head code runs with the write token.
say(mint >= 0 && checkout > mint, "the lane token is minted before the head checkout");
const recheck = at((s) => s.id === "head-recheck");
say(recheck >= 0 && recheck < mint, "the head re-read runs before the mint");
for (const id of ["merge-bin", "hold-label", "stage"]) {
  const i = at((s) => s.id === id);
  say(i >= 0 && i < checkout, `step ${id} copies from the base before the head checkout`);
}
const copy = byId("merge-bin").run ?? "";
say(/\.base\/\.github\/scripts\/merge-base\//.test(copy) && /\.base\/plugins\/source-control\/scripts\/resolve-version-bump-conflict\.sh/.test(copy)
  && /sha256sum/.test(copy), "the merge scripts and the version-bump script are copied from .base with their SHA-256");
for (const [id, scripts] of [["prepare", ["prepare", "resolve-version-bump-conflict"]], ["post", ["post"]]]) {
  const run = byId(id).run ?? "";
  for (const name of scripts) {
    const checked = run.search(new RegExp(`(check "\\$BIN/${name}\\.sh"|sha256sum <"\\$BIN/${name}\\.sh")`));
    const runs = run.search(new RegExp(`bash "\\$BIN/prepare\\.sh"|bash "\\$BIN/${name}\\.sh"`));
    say(checked >= 0 && runs > checked, `step ${id} checks ${name}.sh's SHA-256 before running it`);
  }
}
const cs = commit.with?.script ?? "";
const treeCheck = cs.search(/createHash\('sha256'\)\.update\(readFileSync\(script\)\)\.digest\('hex'\) !== TREE_ENTRIES_SHA256\) \{\n[^\n]*setFailed[^\n]*\n\s*return;/); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
say(treeCheck >= 0 && treeCheck < cs.indexOf("execFileSync('/usr/bin/bash'"),
  "the commit step checks tree-entries.sh's SHA-256 before running it");
// No step after the head checkout runs a program the head supplies.
const headRun = /(^|[\s;&|(])(\.\/|npm |npx |yarn |pnpm |make\b|pytest|python |node \.|bash \.|sh \.)/m; // portability-ok: embedded node JavaScript regex, not a shell tool pattern
const offenders = after.filter((s) => s.run && headRun.test(s.run)).map((s) => s.name);
say(offenders.length === 0, `no run step after the head checkout runs head code (${offenders.join(", ") || "none"})`);
const script = byId("act-script").run ?? "";
say(/"\$RUNNER_TEMP\/base-script\/\$\(basename "\$SCRIPT"\)"/.test(script), "a script activity runs from its base copy");
const skill = byId("act-skill");
const args = String(skill.with?.claude_args ?? "");
// The action admits only github-actions, and only on a dispatcher-sent run the
// trigger gate verified.
say(skill.with?.allowed_bots === "${{ inputs.dispatcher-run-id != '' && 'github-actions' || '' }}",
  `the skill admits github-actions only with a dispatcher-run-id (got ${JSON.stringify(skill.with?.allowed_bots)})`);
say(/--setting-sources user/.test(args) && /--permission-mode dontAsk/.test(args) && !/bypass/i.test(args),
  "the skill loads user settings only, under dontAsk");
const stage = readFileSync(".github/actions/collect-base-activity/action.yml", "utf8");
// The three exceptions: an activity's `checks`, each a read-only base-copy
// wrapper the skill may run with no arguments; under web-access `any`, the
// read-only base copy of the two docs scripts; and under prepare:
// review-threads, the read-only review-thread tool wrapper.
const docsRule = String.raw`allowed="$allowed,Bash(bash $DOCS_DIR/$script *),Bash(bash \\\"$DOCS_DIR/$script\\\" *)"`;
const allowedLines = stage.split("\n").filter((l) => /allowed="\$allowed|allowed="Skill/.test(l));
say(allowedLines.length > 0 && allowedLines.every((l) => !/Bash/.test(l) || ['allowed="$allowed,Bash($wrapper)"', docsRule, 'allowed="$allowed,Bash($tool *)"'].includes(l.trim())),
  "the runner grants the skill no Bash but its check wrappers, the docs scripts and the review-thread tool");
say(/chmod -R a-w "\$FEEDBACK_DIR"/.test(stage) && /Edit\(\/\$FEEDBACK_DIR\/\*\*\),Write\(\/\$FEEDBACK_DIR\/\*\*\),Edit\(\/\$FEEDBACK_STATE\/\*\*\),Write\(\/\$FEEDBACK_STATE\/\*\*\)/.test(stage),
  "the review-thread tool, its thread file and its log are out of the skill's Edit and Write");
// review-threads decides before the mint with the job token. After the
// skill, a pinned action (no PATH lookup the activity could redirect) records
// the gated head and kept threads beside the model's replies; no step of the
// model run holds a reply or resolve call.
const select = at((s) => s.id === "feedback-select");
say(select >= 0 && select < mint && byId("feedback-select").env?.GITHUB_TOKEN === "${{ github.token }}",
  "the review-threads select step runs before the mint, with the job's read-only token");
say(/proceed != 'false'/.test(byId("head-recheck").if ?? ""), "a select step that does not proceed skips the mint");
const feedbackCollect = byId("feedback-collect");
say(String(feedbackCollect.uses ?? "").startsWith("actions/github-script@") && at((s) => s.id === "feedback-collect") > at((s) => s.id === "promote")
  && feedbackCollect.env?.HEAD_SHA === "${{ steps.gate.outputs.head-sha }}" && !("github-token" in (feedbackCollect.with ?? {})),
  "the replies are collected by a pinned action after the promote step, with the gated head and no lane token");
const runSteps = JSON.stringify(steps);
say(!/resolveReviewThread|\/replies['"`]|record-round/.test(runSteps) && !/feedback-round/.test(JSON.stringify(steps.map((s) => s.id))),
  "no step of the write runner replies on or resolves a review thread");
const promoteScript = String(byId("promote").with?.script ?? "");
const promoteThreads = String(byId("promote").env?.THREAD_FILE ?? "");
say(promoteThreads.includes("prepare == 'review-threads'") && promoteThreads.includes("lane-feedback/threads.json"),
  "review-threads mode hands the promote step the kept threads' paths");
say(promoteScript.indexOf("if (THREAD_FILE)") >= 0 && promoteScript.indexOf("if (THREAD_FILE)") < promoteScript.indexOf("updateRef"),
  "the promote step checks the lane branch's paths before it moves the PR branch");
say(/run-sha256/.test(String(feedbackCollect.with?.script ?? "")) && byId("act-script").env?.RUN_SHA256 === "${{ inputs.review-run-sha256 }}",
  "the reply script gets the SHA-256 of the run.json the collect step wrote");
// "Re-run failed jobs" on the reply job alone bumps github.run_attempt but
// keeps the model job's outputs, so the replies artifact is named by the
// model job's attempt on both sides, never by the downloading job's own.
const replyUpload = steps.find((s) => s.name === "Upload the review-thread replies");
const replyDownload = steps.find((s) => s.name === "Download the review-thread replies");
say(replyUpload?.with?.name === "feedback-replies-${{ github.run_attempt }}"
  && replyDownload?.with?.name === "feedback-replies-${{ inputs.review-run-attempt }}"
  && wf.jobs.run.outputs["feedback-run-attempt"] === "${{ steps.feedback-collect.outcome == 'success' && github.run_attempt || '' }}",
  "the reply job downloads the replies by the model job's attempt, so a re-run of it alone still finds them");
const actors = at((s) => s.id === "reply-actors");
say(actors >= 0 && actors < checkout && /\.base\/\.github\/standards\/trusted-actors\/trusted-actors\.json/.test(byId("reply-actors").run ?? ""),
  "the reply script's trusted-actors list is copied from the base before the head checkout");
say(/\?\*:feedback-uncertain \| \?\*:feedback-not-landed \| \?\*:feedback-invalid\)/.test(byId("act-script").run ?? "")
  && /\?\*:feedback-partial \| \?\*:feedback-incomplete \| \?\*:feedback-disputed\)/.test(byId("act-script").run ?? ""),
  "a script escalates only with the reply script's own reasons, and only in review-replies mode");
say(/chmod -R a-w "\$CHECKS_DIR"/.test(stage) && /disallowed="\$\{disallowed:\+\$disallowed,\}Edit\(\/\$CHECKS_DIR\/\*\*\),Write\(\/\$CHECKS_DIR\/\*\*\)"/.test(stage),
  "the check wrappers and their base copy are read-only to the skill");
say(/chmod -R a-w "\$DOCS_DIR"/.test(stage) && /disallowed="Edit\(\/\$DOCS_DIR\/\*\*\),Write\(\/\$DOCS_DIR\/\*\*\)"/.test(stage),
  "the docs script copy is read-only to the skill");

// The report-escalation script reads the base's tracker config.
const tracker = at((s) => s.id === "tracker-config");
say(tracker >= 0 && tracker < checkout && /\.base\/\.work-item-tracker\.json/.test(byId("tracker-config").run ?? ""),
  "the base tracker config is copied before the head checkout");
say(/sha256/.test(byId("tracker-config").run ?? ""), "the tracker config copy records its SHA-256");
const scriptEnv = byId("act-script").env ?? {};
say(/base-script/.test(String(scriptEnv.TRACKER_CONFIG ?? "")), "the script step gets TRACKER_CONFIG from the base copy");
const trackerCheck = script.search(/sum=\$\(sha256sum <"\$TRACKER_CONFIG"\)\n\s*if \[ "\$\{sum%% \*\}" != "\$TRACKER_SHA256" \]; then\n[^\n]*\n\s*exit 1/); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
say(trackerCheck >= 0 && trackerCheck < script.indexOf('"$RUNNER_TEMP/base-script/$(basename'),
  "the script step fails on a tracker config whose SHA-256 differs, before running the script");

// Hash checks compare and fail, not merely run.
const prepRun = byId("prepare").run ?? "";
say(/check\(\) \{[^}]*sum=\$\(sha256sum <"\$1"\)[^}]*if \[ "\$\{sum%% \*\}" != "\$2" \]; then[^}]*exit 1/s.test(prepRun),
  "the prepare step's hash check fails on a differing SHA-256");
say(/if \[ "\$\{sum%% \*\}" != "\$POST_SHA256" \]; then\n[^\n]*\n\s*exit 1/.test(post.run ?? ""), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "the post step fails on a post.sh whose SHA-256 differs");

// Head file names reach git's output: workflow commands are stopped while a
// merge script runs, and resumed before the step's own ::error:: lines.
for (const [id, name] of [["prepare", "prepare"], ["post", "post"]]) {
  const run = byId(id).run ?? "";
  const stop = run.indexOf('echo "::stop-commands::$token"');
  const call = run.indexOf(`bash "$BIN/${name}.sh"`);
  const resume = run.indexOf('echo "::$token::"');
  const firstError = run.indexOf("::error::", call);
  say(stop >= 0 && stop < call && resume > call && (firstError < 0 || resume < firstError),
    `step ${id} stops workflow commands around ${name}.sh`);
  say(/^\s*echo "skip-reason=\$skip"( >>"\$GITHUB_OUTPUT")?$/m.test(run) && !/skip-reason=awaiting-human/.test(run), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
    `step ${id} writes skip-reason unconditionally`);
  say(String(byId(id).env?.GIT_NO_REPLACE_OBJECTS) === "1", `step ${id} sets GIT_NO_REPLACE_OBJECTS=1`);
}
say(/stop-commands/.test(cs), "the commit step stops workflow commands while tree-entries.sh and git run");

// The commit step's git runs with an allowlisted environment.
say(!/\.\.\.process\.env/.test(cs) && /PATH: '\/usr\/bin:\/bin'/.test(cs) && /GIT_NO_REPLACE_OBJECTS: '1'/.test(cs),
  "the commit step's git environment is an allowlist");
say(/'\/usr\/bin\/git'/.test(cs) && /'\/usr\/bin\/bash'/.test(cs) && !/execFileSync\('(git|bash)'/.test(cs),
  "the commit step calls /usr/bin/git and /usr/bin/bash");

// Holds placed mid-run stop the commit.
const labels = cs.search(/fetch\(\s*`\$\{process\.env\.GITHUB_API_URL\}\/repos\/[^`]*\/issues\/\$\{Number\(PR_NUMBER\)\}\/labels/); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
say(/Authorization: `Bearer \$\{READ_TOKEN\}`/.test(cs) && /if \(!labelsResponse\.ok\) \{\n[^\n]*setFailed/.test(cs),
  "the label re-read uses the read-only token and fails the step when the read fails");
// Only page 1 is read, so a PR with more labels fails rather than missing a hold.
const nextPage = cs.search(/if \(\/rel="next"\/\.test\(labelsResponse\.headers\.get\('link'\)[^\n]*\) \{\n[^\n]*setFailed[^\n]*\n\s*return;/); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
say(nextPage >= 0 && nextPage < cs.indexOf("createCommit"), "the label re-read fails the step when the labels span a second page");
// actions/github-script v8.0.0 passes no getOctokit to the script.
const octokitCallers = steps.filter((s) => /getOctokit/.test(s.with?.script ?? "")).map((s) => s.name);
say(octokitCallers.length === 0, `no github-script step calls getOctokit (${octokitCallers.join(", ") || "none"})`);
say(labels >= 0 && labels < cs.indexOf("createCommit") && /do-not-merge/.test(cs) && /HOLD_LABEL/.test(cs),
  "the commit step re-reads the PR's hold labels before creating the commit");
const holdLabel = byId("hold-label").run ?? "";
const promoteEnv = byId("promote").env ?? {};
say(/\.base\/\.work-item-tracker\.json/.test(holdLabel) && /labels-absent/.test(holdLabel) && /echo "labels=\$labels"/.test(holdLabel)
  && [commit.env, promoteEnv].every((env) => /^\$\{\{ steps\.hold-label\.outputs\.labels \}\}$/.test(String(env?.HOLD_LABELS))
    && String(env?.READ_TOKEN) === "${{ github.token }}")
  && /^\$\{\{ steps\.gate\.outputs\.pr-number \}\}$/.test(String(promoteEnv.PR_NUMBER)),
  "the hold labels are resolved from the base before the head checkout and reach the commit and promote steps with the read-only token");

// Promote moves the PR branch only to the commit the commit step made.
const promote = byId("promote");
const ps = promote.with?.script ?? "";
say(/COMMIT_SHA/.test(JSON.stringify(promote.env ?? {})) && /lane !== COMMIT_SHA/.test(ps) && /COMMIT_OUTCOME !== 'success'/.test(ps),
  "in merge-base mode promote requires the commit step's success and its commit at the lane ref");

// Issue mode: only the skill run writes the outcome artifact, so the
// report-outcome run downloads what the skill run left, never its own copy.
const outcomeWriters = steps.filter((s) => /upload-artifact/.test(s.uses ?? "") && /work-outcome/.test(JSON.stringify(s.with ?? {})));
const collect = steps.find((s) => s.name === "Collect the issue outcome");
say(outcomeWriters.length === 1 && collect !== undefined
  && [...outcomeWriters, collect].every((s) => /steps\.config\.outputs\.kind == 'skill'/.test(String(s.if ?? ""))),
  "issue mode collects and uploads the outcome artifact only in a skill run");
EOF
)
if [[ -z "$results" ]]; then
  fail "the structure check printed nothing; is .github/standards/runner-policy installed?"
fi
while IFS=$'\t' read -r verdict text; do
  [[ -n "$verdict" ]] || continue
  if [[ "$verdict" == ok ]]; then ok "$text"; else fail "$text"; fi
done <<<"$results"

test_harness::report
