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
// The case arm naming the reason sets skip=awaiting-human on its next line.
const escalates = (reason) =>
  new RegExp(`^\\s*[a-z| -]*\\b${reason}\\b[a-z| -]*\\)\\s*\\n\\s*tree="" skip=awaiting-human$`, "m").test(post.run ?? ""); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
for (const reason of ["unresolved-conflict", "workflow-staged", "unexpected-path-staged"]) {
  say(escalates(reason), `the post step turns ${reason} into an escalation (awaiting-human)`);
}
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
// A workflow-modified skip ends the mint green with no token (#7732), so no
// step after it may key on the head re-read alone.
const keyed = steps.slice(mint + 1)
  .filter((s) => /steps\.head-recheck\.outputs\.proceed/.test(String(s.if ?? "")) && !/steps\.lane-token\.outputs\.token != ''/.test(String(s.if ?? "")))
  .map((s) => s.name);
say(keyed.length === 0, `no step after the mint keys on the head re-read instead of the token (${keyed.join(", ") || "none"})`);
say(String(steps[checkout]?.if ?? "") === "steps.lane-token.outputs.token != ''", "the head checkout runs only with a minted token");
const mintWith = byId("lane-token").with ?? {};
say(mintWith["pr-workflow-change-ok"] === "${{ inputs.issue-number == '' && github.event_name == 'pull_request' }}" && mintWith["github-token"] === "${{ github.token }}"
  && mintWith["head-sha"] === "${{ steps.gate.outputs.head-sha }}",
  "the workflow-modified skip runs on pull_request only, off issue mode, and compares the gated head with the job's own token");
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
// The action admits the lanes App, which the trigger gate passes only on its
// app-label, and github-actions only on a dispatcher-sent run the gate
// verified; never '*'. cant-fail-ok: the allowed_bots value is the contract.
say(skill.with?.allowed_bots === "${{ inputs.dispatcher-run-id != '' && 'melodic-automation-lanes[bot],github-actions' || 'melodic-automation-lanes[bot]' }}",
  `the skill admits the lanes App, and github-actions only with a dispatcher-run-id (got ${JSON.stringify(skill.with?.allowed_bots)})`);
say(/--setting-sources user/.test(args) && /--permission-mode dontAsk/.test(args) && !/bypass/i.test(args),
  "the skill loads user settings only, under dontAsk");
const stage = readFileSync(".github/actions/collect-base-activity/action.yml", "utf8");
// The five exceptions: an activity's `checks`, each a read-only base-copy
// wrapper the skill may run with no arguments; its `verify-scripts`, each a
// read-only wrapper over a base copy it may run with any arguments; under web-access `any`,
// the read-only base copy of the two docs scripts; under prepare:
// review-threads, nothing here (the read runner's launcher arm grants its
// wrapper); with the commit tool, chmod +x, since commit_files takes each file's mode from disk;
// and under prepare: ci-context, bare Bash for a read skill, which runs in
// pr-run-activity-read.yml with no write token (this file fails a read effect
// before it stages anything).
const docsRule = String.raw`allowed="$allowed,Bash(bash $DOCS_DIR/$script *),Bash(bash \\\"$DOCS_DIR/$script\\\" *)"`;
const ciContextRule = 'allowed="$allowed,Bash,Edit,Write,Agent,Read(/$CI_DIR/**),Edit(/$SCRATCH/**)"';
const allowedLines = stage.split("\n").filter((l) => /allowed="\$allowed|allowed="Skill/.test(l));
say(allowedLines.length > 0 && allowedLines.every((l) => !/Bash/.test(l) || ['allowed="$allowed,Bash($wrapper)"', 'allowed="$allowed,Bash($verifier *)"', docsRule, 'allowed="$allowed,Bash(chmod +x *)"', ciContextRule].includes(l.trim())),
  "the runner grants the skill no Bash but its check wrappers, its verify-scripts, the docs scripts, chmod +x and a read ci-context skill's");
const readBranch = stage.slice(stage.indexOf("          read)\n"), stage.indexOf("          mutate-branch | mutate-tracker"));
say(readBranch.includes(ciContextRule) && /ci-context\) \[ "\$EFFECT" = read \] \|\| fail/.test(stage),
  "the ci-context Bash grant sits in the read effect's branch, and ci-context with any other effect fails red");
say(/chmod -R a-w "\$VERIFY_DIR"/.test(stage) && /disallowed="\$\{disallowed:\+\$disallowed,\}Edit\(\/\$VERIFY_DIR\/\*\*\),Write\(\/\$VERIFY_DIR\/\*\*\)"/.test(stage),
  "the verify-scripts copy is read-only to the skill");
// review-threads runs on the read runner, after its caller's select job: this
// file refuses it before the mint, keeps no threads and collects no replies.
const refuse = at((s) => s.name === "Assert review-threads runs in the read runner");
say(refuse >= 0 && refuse < mint && /steps\.config\.outputs\.prepare == 'review-threads'/.test(steps[refuse].if ?? "") && /exit 1/.test(steps[refuse].run ?? ""),
  "a review-threads activity fails red before the mint");
say(!steps.some((s) => ["feedback-select", "feedback-collect"].includes(s.id)) && !("THREAD_FILE" in (byId("promote").env ?? {})),
  "the write runner keeps no review threads and collects no replies");
say(/proceed != 'false'/.test(byId("head-recheck").if ?? ""), "a select step that does not proceed skips the mint");
const runSteps = JSON.stringify(steps);
say(!/resolveReviewThread|\/replies['"`]|record-round/.test(runSteps) && !/feedback-round/.test(JSON.stringify(steps.map((s) => s.id))),
  "no step of the write runner replies on or resolves a review thread");
const promoteScript = String(byId("promote").with?.script ?? "");
say(byId("act-script").env?.RUN_SHA256 === "${{ inputs.review-run-sha256 }}",
  "the reply script gets the SHA-256 of the run.json the caller's select job wrote");
// "Re-run failed jobs" on the reply job alone bumps github.run_attempt but
// keeps the other jobs' outputs, so each artifact is named by its writer's
// attempt, never by the downloading job's own.
// The round marker names the model attempt whose scanned replies this job
// posts, so a model job re-run at a new attempt counts a new round.
say(byId("act-script").env?.MODEL_RUN_ATTEMPT === "${{ inputs.review-replies-attempt }}",
  "the round marker names the scan job's replies attempt");
const runDownload = steps.find((s) => s.name === "Download the review-thread run record");
const replyDownload = steps.find((s) => s.name === "Download the review-thread replies");
say(runDownload?.with?.name === "feedback-context-${{ inputs.review-run-attempt }}"
  && replyDownload?.with?.name === "feedback-replies-${{ inputs.lane }}-address-feedback-${{ inputs.review-replies-attempt }}",
  "the reply job downloads run.json and the replies by their writers' attempts, so a re-run of it alone still finds them");
const actors = at((s) => s.id === "reply-actors");
say(actors >= 0 && actors < checkout && /\.base\/\.github\/standards\/trusted-actors\/trusted-actors\.json/.test(byId("reply-actors").run ?? ""),
  "the reply script's trusted-actors list is copied from the base before the head checkout");
say(/\?\*:feedback-uncertain \| \?\*:feedback-not-landed \| \?\*:feedback-invalid\)/.test(byId("act-script").run ?? "")
  && /\?\*:feedback-partial \| \?\*:feedback-incomplete \| \?\*:feedback-disputed\)/.test(byId("act-script").run ?? ""),
  "a script escalates only with the reply script's own reasons, and only in review-replies mode");
say(/:\?\*:dependency-invalid \| :\?\*:dependency-fix-not-landed\)/.test(byId("act-script").run ?? "")
  && /:\?\*:dependency-security-close \| :\?\*:dependency-escalate \| :\?\*:dependency-config-unreadable\)/.test(byId("act-script").run ?? "")
  && /:\?\*:dependency-files-truncated \| :\?\*:dependency-control-uncited \| :\?\*:dependency-workflow-held\)/.test(byId("act-script").run ?? "")
  && /:\?\*:dependency-fix-refused\)/.test(byId("act-script").run ?? ""),
  "a script escalates with the verdict script's reasons only in dependency-verdict mode");
// dependency-review runs on the read runner, after its caller's select job:
// this file refuses it before the mint, selects nothing, promotes no fix and
// collects no verdict; apply-patch pushes the fix under the dependency-review row.
const refuseDependency = at((s) => s.name === "Assert dependency-review runs in the read runner");
say(refuseDependency >= 0 && refuseDependency < mint && /steps\.config\.outputs\.prepare == 'dependency-review'/.test(steps[refuseDependency].if ?? "") && /exit 1/.test(steps[refuseDependency].run ?? ""),
  "a dependency-review activity fails red before the mint");
say(!steps.some((s) => ["dependency-select", "dependency-collect"].includes(s.id)) && !/DEPENDENCY_REVIEW|CLASSIFY_SHA256|inFixScope|fixRefusal/.test(promoteScript),
  "the write runner selects no dependency pull request, promotes no dependency fix and collects no verdict");
// apply-patch runs from a base copy, so each pr-unblock module its
// predicates import must be copied beside it.
const predicateImports = [...readFileSync(".github/scripts/apply-patch/predicates.mjs", "utf8").matchAll(/from "\.\.\/pr-unblock\/([^"]+)"/g)].map((m) => m[1]);
say(predicateImports.length > 0 && predicateImports.every((name) => (byId("apply-base").run ?? "").includes(`cp .base/.github/scripts/pr-unblock/${name} "$RUNNER_TEMP/pr-unblock/"`)),
  "the apply-patch base copy holds every pr-unblock module its predicates import");
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

// Issue mode runs its skill in the read runner, which holds no lane token:
// these checks read that file. Only the skill run writes the outcome
// artifact, so the report-outcome run downloads what it left.
const rwf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-read.yml", "utf8"));
const rsteps = rwf.jobs.run.steps;
const rat = (pred) => rsteps.findIndex(pred);
const rById = (id) => rsteps.find((s) => s.id === id) ?? {};
const outcomeWriters = rsteps.filter((s) => /upload-artifact/.test(s.uses ?? "") && /work-outcome/.test(JSON.stringify(s.with ?? {})));
const collect = rsteps.find((s) => s.name === "Collect the issue outcome");
say(outcomeWriters.length === 1 && collect !== undefined
  && [...outcomeWriters, collect].every((s) => /steps\.config\.outputs\.kind == 'skill'/.test(String(s.if ?? ""))),
  "issue mode collects and uploads the outcome artifact only in a skill run");

// Issue mode: the check for an earlier run's work decides before the run
// decides to start and before any model turn, with the job's read-only
// token, and a stop or reuse skips the model.
const prior = rById("issue-prior");
const priorAt = rat((s) => s.id === "issue-prior");
say(priorAt >= 0 && priorAt < rat((s) => s.id === "go") && priorAt < rat((s) => s.id === "act-skill") && prior.env?.GH_TOKEN === "${{ github.token }}"
  && !/lane-token/.test(JSON.stringify(prior)),
  "the earlier-work check runs before the run decides to start and before the model, with the job's read-only token and no lane token");
say(/steps\.config\.outputs\.kind == 'skill'/.test(String(prior.if ?? "")) && /inputs\.issue-number != ''/.test(String(prior.if ?? ""))
  && /\.base\/\.github\/scripts\/work-resolve-issue\/report-outcome\.mjs --find-prior/.test(prior.run ?? ""),
  "the earlier-work check runs only for an issue-mode skill, from the base copy");
say(rById("go").env?.PRIOR === "${{ steps.issue-prior.outputs.proceed }}" && /PRIOR" = false/.test(rById("go").run ?? "")
  && /steps\.go\.outputs\.run == 'true'/.test(String(rById("act-skill").if ?? "")),
  "an earlier run's work skips the model");
say(rwf.jobs.run.outputs["reuse-branch"] === "${{ steps.issue-prior.outputs.reuse-branch }}",
  "the reuse-branch output comes only from the runner's earlier-work check");
const first = steps[0];
say(first.env?.REUSE_BRANCH === "${{ inputs.reuse-branch }}"
  && (first.run ?? "").includes("[[ $REUSE_BRANCH =~ ^work-resolve-issue/issue-${ISSUE_NUMBER}-[1-9][0-9]*-[1-9][0-9]*$ ]]"),
  "the first step refuses a reuse-branch input that is not this issue's lane branch");
say(byId("act-script").env?.REUSE_BRANCH === "${{ inputs.reuse-branch }}", "the script step gets the checked reuse-branch input");

// Issue mode, reuse: the summary pass is the read runner's own job after the
// run job, started only by the earlier-work check's reuse-branch (which skips
// the model). It holds no id-token, reads the branch as data, and no step can
// turn it red.
const sjob = rwf.jobs.summary ?? {};
const ssteps = sjob.steps ?? [];
const sById = (id) => ssteps.find((s) => s.id === id) ?? {};
const summaryIds = ["summary-data", "summary-models", "summary-prompt", "summary-run", "summary-collect"];
say(!rsteps.some((s) => summaryIds.includes(s.id) || /claude-code-action/.test(s.uses ?? "") && s.id !== "act-skill"),
  "the run job runs no summary step and no model step but the skill");
say(sjob.needs === "run" && /needs\.run\.outputs\.reuse-branch != ''/.test(String(sjob.if ?? "")) && /!cancelled\(\)/.test(String(sjob.if ?? "")),
  "the summary job runs after the run job, only on its reuse-branch output");
say(JSON.stringify(sjob.permissions) === JSON.stringify({ contents: "read" }),
  "the summary job holds contents: read and nothing else, no id-token");
say(rwf.jobs.run.outputs?.["reuse-branch"] === "${{ steps.issue-prior.outputs.reuse-branch }}",
  "the run job's reuse-branch output is the earlier-work check's");
say(ssteps.length > 0 && ssteps.every((s) => s["continue-on-error"] === true),
  "every summary job step is continue-on-error, so a failed pass turns no job red");
say(summaryIds.every((id) => sById(id).id === id) && !/lane-token/.test(JSON.stringify(sjob)),
  "the summary job has every summary step and reads no lane token");
const sBase = ssteps.find((s) => /actions\/checkout/.test(s.uses ?? "")) ?? {};
say(sBase.with?.ref === "${{ needs.run.outputs.base-sha }}" && sBase.with?.["persist-credentials"] === false
  && ssteps.filter((s) => /actions\/checkout/.test(s.uses ?? "")).length === 1,
  "the summary job checks out only the run job's trusted base, without persisted credentials");
const summaryData = sById("summary-data");
say(summaryData.env?.GITHUB_TOKEN === "${{ github.token }}" && /GIT_CONFIG_GLOBAL=\/dev\/null/.test(summaryData.run ?? "")
  && /--filter=blob:none/.test(summaryData.run ?? "")
  && /diff --no-ext-diff --no-textconv/.test(summaryData.run ?? "") && !/checkout|worktree|npm |bash "\$SRC|node "\$SRC/.test(summaryData.run ?? ""),
  "the summary data step fetches the branch as objects with the read-only token and diffs it without running anything from it");
const summaryRun = sById("summary-run");
const summaryArgs = String(sById("summary-prompt").run ?? "");
say(String(summaryRun.uses ?? "") === String(rById("act-skill").uses ?? "") && summaryRun.with?.github_token === "${{ github.token }}"
  && !("use_commit_signing" in (summaryRun.with ?? {})) && !("plugins" in (summaryRun.with ?? {}))
  && !("plugin_marketplaces" in (summaryRun.with ?? {})) && sById("isolate").uses === "./.base/.github/actions/setup-runner-isolation"
  && String(summaryRun.if ?? "") === "steps.isolate.outcome == 'success'",
  "the summary model step runs only after runner isolation, with the job's read-only token, no commit signing and no plugins");
say(summaryRun.with?.allowed_bots === "melodic-automation-lanes[bot]",
  `the summary model step admits only the lanes App bot (got ${JSON.stringify(summaryRun.with?.allowed_bots)})`);
say(/--setting-sources user/.test(String(summaryRun.with?.claude_args ?? "")) && /--permission-mode dontAsk/.test(String(summaryRun.with?.claude_args ?? ""))
  && /--allowedTools \\"Read\(\/\$DATA\/\*\*\)\\"/.test(summaryArgs) && /denied="Bash,Edit,Write,/.test(summaryArgs)
  && /mcp__github_file_ops/.test(summaryArgs) && /--json-schema/.test(summaryArgs) && /openssl rand -hex/.test(summaryArgs),
  "the summary model reads the data directory and nothing else, under dontAsk, and returns structured output");
const summaryCollect = sById("summary-collect");
say(summaryCollect.env?.REUSE_BRANCH === "${{ needs.run.outputs.reuse-branch }}"
  && summaryCollect.env?.TIP === "${{ steps.summary-data.outputs.tip }}" && /try fromjson catch null/.test(summaryCollect.run ?? ""),
  "the summary file binds the model's output to the runner's branch and tip");
const summaryDownload = steps.find((s) => s.name === "Download the reused branch's summary");
say(/inputs\.reuse-branch != ''/.test(String(summaryDownload?.if ?? "")) && /steps\.config\.outputs\.kind == 'script'/.test(String(summaryDownload?.if ?? ""))
  && summaryDownload?.["continue-on-error"] === true,
  "only a reuse's report-outcome run downloads the summary, and a missing one fails nothing");
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
