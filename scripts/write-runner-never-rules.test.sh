#!/usr/bin/env bash
# Structure test: pr-run-activity-write.yml keeps every clause of the
# apply-conflict-patch `never` row in .github/actions/resolve-config/activity-rules.json
# ("Runs a model or head code, force-pushes, or pushes a model edit outside the
# conflicted paths"), and hands the report-escalation script the base's tracker
# config.
#
# Reads the workflow as YAML (the runner-policy `yaml` package, which CI
# installs for check-read-caller-keys.test.sh) and asserts on step order,
# conditions and step bodies. What it cannot assert from this file:
#   - The skill's own allowed-tools Bash grant (its SKILL.md) and its token:
#     with a contents-write token the model could push or run head code
#     itself. The backstops are the App's missing `workflows` permission and
#     ADR 0055's accepted residual, not this file.
#   - That apply-patch.mjs refuses every workflow change a merge pushes;
#     apply-patch.test.mjs owns that.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/actions/resolve-config/activity-rules.json .github/actions/collect-base-activity/action.yml .github/scripts/merge-base/run-prepare.sh .github/scripts/apply-patch/apply-patch.mjs .github/actions/resolve-config/patch-rules.json .github/standards/runner-policy/package.json
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
const never = rules["apply-conflict-patch"]?.never ?? "";
// The row this suite guards; a reworded row needs this suite reread.
say(never === "Runs a model or head code, force-pushes, or pushes a model edit outside the conflicted paths",
  `the apply-conflict-patch never row is the one this suite asserts (got ${JSON.stringify(never)})`);
// The merge step runs the base copy of run-prepare.sh, which holds the hash
// checks, the stopped workflow commands and the escalation set.
const runPrepare = readFileSync(".github/scripts/merge-base/run-prepare.sh", "utf8");

const wf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-write.yml", "utf8"));
const steps = wf.jobs.run.steps;
const at = (pred) => steps.findIndex(pred);
const byId = (id) => steps.find((s) => s.id === id) ?? {};
const checkout = at((s) => s.name === "Check out the PR head");
const mint = at((s) => s.id === "lane-token");
const body = (s) => `${s.run ?? ""}${s.with?.script ?? ""}`;
const after = steps.slice(checkout + 1);

// Clause 1: no force-push. The promote step moves a skill's lane branch;
// apply-patch.mjs moves the PR branch for a patch, a merge's included.
const applyPatch = readFileSync(".github/scripts/apply-patch/apply-patch.mjs", "utf8");
const updates = steps.flatMap((s) => body(s).match(/updateRef\([^)]*\)/g) ?? []);
say(updates.length >= 1, `the run job updates refs through updateRef (${updates.length} calls)`);
say(/write: \(api, ref, commit\) => api\.updateRef\(`heads\/\$\{ref\}`, commit, false\)/.test(applyPatch)
  && !/updateRef\([^)]*true\)/.test(applyPatch), "apply-patch.mjs moves the PR branch with force: false");
say(updates.every((u) => /force: false/.test(u)), "every updateRef call passes force: false");
say(!steps.some((s) => /git\s+push|--force|\+refs\//.test(body(s))), "no step runs git push or a forced refspec"); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
say(!steps.some((s) => /(update|create)Ref\(/.test(body(s)) && /Ref\([^)]*force:\s*true/.test(body(s))), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "no ref update sets force: true");

// Clause 2: no .github/workflows change is pushed by the runner.
// A merge-base skill runs on the read runner; this file commits a merge only
// as apply-patch, under the merge-base row, which refuses a model edit to a
// workflow and escalates a merged workflow set that is not exactly the base's.
const refuseMerge = at((s) => s.name === "Assert merge-base runs in the read runner");
say(refuseMerge >= 0 && refuseMerge < mint && /steps\.config\.outputs\.prepare == 'merge-base'/.test(steps[refuseMerge].if ?? "") && /exit 1/.test(steps[refuseMerge].run ?? ""),
  "a merge-base skill fails red before the mint");
say(!steps.some((s) => ["post", "commit"].includes(s.id)), "the write runner has no post or commit step of its own");
const mergeRow = JSON.parse(readFileSync(".github/actions/resolve-config/patch-rules.json", "utf8"))["merge-base"];
say(mergeRow?.refuse?.includes("github-workflows") && /if \(!workflowsAreBaseOwn\(git, headSha, merge\.baseSha, tree\)\) \{\n\s*return reason\("workflow-staged"/.test(applyPatch), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "a merge's workflow change pushes only as the base's own, and a model edit to a workflow is refused");
const prepare = byId("prepare");
say(/bash "\$BIN\/run-prepare\.sh"/.test(prepare.run ?? "") && /escalate:protected-path-conflict/.test(runPrepare)
  && prepare.env?.EXPECT_STATE === "${{ inputs.patch-merge-state }}" && prepare.env?.EXPECT_TREE === "${{ inputs.patch-conflict-tree }}",
  "the merge step reaches the select job's state and conflict tree, or fails red");

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
for (const [id, run, scripts] of [
  ["prepare", byId("prepare").run ?? "", ["run-prepare"]],
  ["run-prepare.sh", runPrepare, ["prepare", "resolve-version-bump-conflict"]],
]) {
  for (const name of scripts) {
    const checked = run.search(new RegExp(`(check "\\$BIN/${name}\\.sh"|sha256sum <"\\$BIN/${name}\\.sh")`));
    const runs = run.search(new RegExp(`bash "\\$BIN/prepare\\.sh"|bash "\\$BIN/${name}\\.sh"`));
    say(checked >= 0 && runs > checked, `step ${id} checks ${name}.sh's SHA-256 before running it`);
  }
}
const scriptEnv0 = byId("act-script").env ?? {};
say(scriptEnv0.TREE_ENTRIES_SHA256 === "${{ inputs.patch-prepare == 'merge-base' && steps.merge-bin.outputs.tree-entries-sha256 || '' }}"
  && /sha256Of\(script\) !== merge\.treeEntries\.sha256/.test(applyPatch)
  && applyPatch.indexOf("sha256Of(script) !== merge.treeEntries.sha256") < applyPatch.indexOf('execFileSync("/usr/bin/bash", [merge.treeEntries.script'),
  "apply-patch.mjs checks tree-entries.sh's SHA-256 before running it");
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
  && /:\?\*:dependency-files-truncated \| :\?\*:dependency-control-uncited \| :\?\*:dependency-workflow-unpinned\)/.test(byId("act-script").run ?? "")
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
// apply-patch runs from a base copy, so each sibling-directory module it or
// its predicates import must be copied beside it.
const siblingImports = ["apply-patch.mjs", "predicates.mjs"].flatMap((file) =>
  [...readFileSync(`.github/scripts/apply-patch/${file}`, "utf8").matchAll(/from "\.\.\/([a-z-]+)\/([^"/]+)"/g)].map((m) => [m[1], m[2]]));
say(siblingImports.length > 0 && siblingImports.every(([dir, name]) => (byId("apply-base").run ?? "").includes(`cp .base/.github/scripts/${dir}/${name} "$RUNNER_TEMP/${dir}/"`)
  && new RegExp(`mkdir -p [^\\n]*"\\$RUNNER_TEMP/${dir}"`).test(byId("apply-base").run ?? "")),
  "the apply-patch base copy holds every sibling-directory module apply-patch.mjs and its predicates import");
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
say(/check\(\) \{[^}]*sum=\$\(sha256sum <"\$1"\)[^}]*\[\[ \$\{sum%% \*\} == "\$2" \]\] \|\| fail/s.test(runPrepare) && /fail\(\) \{\n[^\n]*::error::[^\n]*\n\s*exit 1/.test(runPrepare) // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  && /if \[ "\$\{sum%% \*\}" != "\$RUN_PREPARE_SHA256" \]; then\n[^\n]*\n\s*exit 1/.test(byId("prepare").run ?? ""), // portability-ok: embedded node JavaScript regex, not a shell tool pattern
  "the prepare step's hash checks fail on a differing SHA-256");

// Head file names reach git's output: workflow commands are stopped while a
// merge script runs, and resumed before the step's own ::error:: lines.
for (const [id, name, run] of [["prepare", "prepare", runPrepare]]) {
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
// apply-patch.mjs's git, tree-entries.sh's included, runs with an allowlisted
// environment and absolute binaries.
say(/PATH: "\/usr\/bin:\/bin"/.test(applyPatch) && /GIT_NO_REPLACE_OBJECTS: "1"/.test(applyPatch) && /execFileSync\("\/usr\/bin\/bash"/.test(applyPatch),
  "apply-patch.mjs runs git and tree-entries.sh under an allowlisted environment");

// actions/github-script v8.0.0 passes no getOctokit to the script.
const octokitCallers = steps.filter((s) => /getOctokit/.test(s.with?.script ?? "")).map((s) => s.name);
say(octokitCallers.length === 0, `no github-script step calls getOctokit (${octokitCallers.join(", ") || "none"})`);
say(applyPatch.indexOf("await target.held(api, number,", applyPatch.indexOf("async function pushMerge")) < applyPatch.indexOf("await api.createCommit(message, tree, [headSha, merge.baseSha])"),
  "apply-patch.mjs re-reads the PR's holds before creating a merge commit");
const holdLabel = byId("hold-label").run ?? "";
const promoteEnv = byId("promote").env ?? {};
say(/\.base\/\.work-item-tracker\.json/.test(holdLabel) && /labels-absent/.test(holdLabel) && /echo "labels=\$labels"/.test(holdLabel)
  && /^\$\{\{ steps\.hold-label\.outputs\.labels \}\}$/.test(String(promoteEnv.HOLD_LABELS))
  && String(promoteEnv.READ_TOKEN) === "${{ github.token }}"
  && /^\$\{\{ steps\.hold-label\.outputs\.labels \}\}$/.test(String(byId("act-script").env?.HOLD_LABELS))
  && /^\$\{\{ steps\.gate\.outputs\.pr-number \}\}$/.test(String(promoteEnv.PR_NUMBER)),
  "the hold labels are resolved from the base before the head checkout and reach the promote step with the read-only token and the apply-patch script");

// Issue mode runs its skill in the read runner, which holds no lane token:
// these checks read that file. Only the skill run collects the outcome, and
// only the scan job uploads it, after a clean scan of the sealed copy, so the
// report-outcome run downloads what the run left.
const rwf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-read.yml", "utf8"));
const rsteps = rwf.jobs.run.steps;
const rat = (pred) => rsteps.findIndex(pred);
const rById = (id) => rsteps.find((s) => s.id === id) ?? {};
const writesOutcome = (s) => /upload-artifact/.test(s.uses ?? "") && /work-outcome/.test(JSON.stringify(s.with ?? {}));
const outcomeWriters = rwf.jobs.scan.steps.filter(writesOutcome);
const collect = rsteps.find((s) => s.name === "Collect the issue outcome");
say(rsteps.filter(writesOutcome).length === 0 && outcomeWriters.length === 1 && collect !== undefined
  && /steps\.config\.outputs\.kind == 'skill'/.test(String(collect.if ?? ""))
  && /steps\.leak-scan\.outputs\.clean == 'true'/.test(String(outcomeWriters[0].if ?? "")),
  "issue mode collects the outcome only in a skill run, and only the scan job uploads it, after a clean scan");

// Issue mode: the check for an earlier run's work decides before the run
// decides to start and before any model turn, with the job's read-only
// token, and a stop or reuse skips the model.
const prior = rById("issue-prior");
const priorAt = rat((s) => s.id === "issue-prior");
say(priorAt >= 0 && priorAt < rat((s) => s.id === "go") && priorAt < rat((s) => s.id === "act-key") && prior.env?.GH_TOKEN === "${{ github.token }}"
  && !/lane-token/.test(JSON.stringify(prior)),
  "the earlier-work check runs before the run decides to start and before the model, with the job's read-only token and no lane token");
say(/steps\.config\.outputs\.kind == 'skill'/.test(String(prior.if ?? "")) && /inputs\.issue-number != ''/.test(String(prior.if ?? ""))
  && /\.base\/\.github\/scripts\/work-resolve-issue\/report-outcome\.mjs --find-prior/.test(prior.run ?? ""),
  "the earlier-work check runs only for an issue-mode skill, from the base copy");
say(rById("go").env?.PRIOR === "${{ steps.issue-prior.outputs.proceed }}" && /PRIOR" = false/.test(rById("go").run ?? "")
  && /steps\.go\.outputs\.run == 'true'/.test(String(rById("key-present").if ?? "")) && /steps\.go\.outputs\.run == 'true'/.test(String(rById("token-present").if ?? "")),
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
const summaryIds = ["summary-data", "summary-models", "summary-prompt", "summary-key", "summary-token", "summary-collect"];
say(!rsteps.some((s) => summaryIds.includes(s.id) || /claude-code-action/.test(s.uses ?? "")),
  "the run job runs no summary step and no claude-code-action step");
say(JSON.stringify(sjob.needs) === '["run","issue-fields"]' && /needs\.issue-fields\.outputs\.reuse-branch != ''/.test(String(sjob.if ?? ""))
  && /needs\.issue-fields\.outputs\.checked == 'true'/.test(String(sjob.if ?? "")) && /!cancelled\(\)/.test(String(sjob.if ?? "")),
  "the summary job runs after the run and issue-fields jobs, only on the checked reuse branch");
say(JSON.stringify(sjob.permissions) === JSON.stringify({ contents: "read" }),
  "the summary job holds contents: read and nothing else, no id-token");
say(rwf.jobs.run.outputs?.["reuse-branch"] === "${{ steps.issue-prior.outputs.reuse-branch }}",
  "the run job's reuse-branch output is the earlier-work check's");
say(ssteps.length > 0 && ssteps.every((s) => s["continue-on-error"] === true),
  "every summary job step is continue-on-error, so a failed pass turns no job red");
say(summaryIds.every((id) => sById(id).id === id) && !/lane-token/.test(JSON.stringify(sjob)),
  "the summary job has every summary step and reads no lane token");
const sBase = ssteps.find((s) => /actions\/checkout/.test(s.uses ?? "")) ?? {};
say(sBase.with?.ref === "${{ github.event.repository.default_branch }}" && sBase.with?.["persist-credentials"] === false
  && ssteps.filter((s) => /actions\/checkout/.test(s.uses ?? "")).length === 1,
  "the summary job takes its code only from the default branch tip, without persisted credentials");
const summaryData = sById("summary-data");
say(summaryData.env?.GITHUB_TOKEN === "${{ github.token }}" && /GIT_CONFIG_GLOBAL=\/dev\/null/.test(summaryData.run ?? "")
  && /--filter=blob:none/.test(summaryData.run ?? "")
  && /diff --no-ext-diff --no-textconv/.test(summaryData.run ?? "") && !/checkout|worktree|npm |bash "\$SRC|node "\$SRC/.test(summaryData.run ?? ""),
  "the summary data step fetches the branch as objects with the read-only token and diffs it without running anything from it");
// One launcher step per secret: the first call's pass on the API key, a
// fallback call's on the OAuth token.
const summaryLegs = [["summary-key", "api-key", "claude-api-key", "inputs.fallback == ''"], ["summary-token", "subscription-token", "claude-code-oauth-token", "inputs.fallback != ''"]];
say(summaryLegs.every(([id, input, secret, when]) => {
  const leg = sById(id);
  return String(leg.uses ?? "") === String(rById("act-key").uses ?? "") && leg.with?.[input] === "${{ secrets." + secret + " }}"
    && ["api-key", "subscription-token"].filter((name) => name in (leg.with ?? {})).length === 1
    && String(leg.if ?? "") === "steps.isolate.outcome == 'success' && " + when;
}) && sById("isolate").uses === "./.base/.github/actions/setup-runner-isolation" && /\/apply-claude-managed-settings@/.test(sById("summary-settings").uses ?? "")
  && String(sById("isolate").if ?? "") === "steps.summary-settings.outcome == 'success'",
  "the summary model steps run on the launcher, each on one Claude secret, only after the managed settings and runner isolation");
say(summaryLegs.every(([id]) => {
  const w = sById(id).with ?? {};
  return w["permission-mode"] === "dontAsk" && w.tools === "Read" && w["allowed-tools"] === "Read(./.summary/**)"
    && /^Read\(\.\/\.base\/\*\*\)$/m.test(w["disallowed-tools"] ?? "") && /reuse-summary-schema\.json$/.test(w["json-schema-file"] ?? "")
    && !("plugin-dirs" in w) && !("add-dirs" in w);
}) && summaryData.env?.DATA === "${{ github.workspace }}/.summary",
  "the summary model reads the data directory under the workspace and nothing else, under dontAsk, and returns structured output");
const summaryCollect = sById("summary-collect");
say(summaryCollect.env?.REUSE_BRANCH === "${{ needs.issue-fields.outputs.reuse-branch }}"
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
