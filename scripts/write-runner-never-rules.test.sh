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
say(!steps.some((s) => /git\s+push|--force|\+refs\//.test(body(s))), "no step runs git push or a forced refspec");
say(!steps.some((s) => /(update|create)Ref\(/.test(body(s)) && /Ref\([^)]*force:\s*true/.test(body(s))),
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
for (const id of ["merge-bin", "stage"]) {
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
say(cs.indexOf("TREE_ENTRIES_SHA256") >= 0 && cs.indexOf("createHash") < cs.indexOf("execFileSync('bash'"),
  "the commit step checks tree-entries.sh's SHA-256 before running it");
// No step after the head checkout runs a program the head supplies.
const headRun = /(^|[\s;&|(])(\.\/|npm |npx |yarn |pnpm |make\b|pytest|python |node \.|bash \.|sh \.)/m;
const offenders = after.filter((s) => s.run && headRun.test(s.run)).map((s) => s.name);
say(offenders.length === 0, `no run step after the head checkout runs head code (${offenders.join(", ") || "none"})`);
const script = byId("act-script").run ?? "";
say(/"\$RUNNER_TEMP\/base-script\/\$\(basename "\$SCRIPT"\)"/.test(script), "a script activity runs from its base copy");
const skill = byId("act-skill");
const args = String(skill.with?.claude_args ?? "");
say(/--setting-sources user/.test(args) && /--permission-mode dontAsk/.test(args) && !/bypass/i.test(args),
  "the skill loads user settings only, under dontAsk");
const stage = readFileSync(".github/actions/collect-base-activity/action.yml", "utf8");
const allowedLines = stage.split("\n").filter((l) => /allowed="\$allowed|allowed="Skill/.test(l));
say(allowedLines.length > 0 && allowedLines.every((l) => !/Bash/.test(l)),
  "the runner grants the skill no Bash (only the skill's own allowed-tools can)");

// The report-escalation script reads the base's tracker config.
const tracker = at((s) => s.id === "tracker-config");
say(tracker >= 0 && tracker < checkout && /\.base\/\.work-item-tracker\.json/.test(byId("tracker-config").run ?? ""),
  "the base tracker config is copied before the head checkout");
say(/sha256/.test(byId("tracker-config").run ?? ""), "the tracker config copy records its SHA-256");
const scriptEnv = byId("act-script").env ?? {};
say(/base-script/.test(String(scriptEnv.TRACKER_CONFIG ?? "")), "the script step gets TRACKER_CONFIG from the base copy");
say(/TRACKER_SHA256/.test(script) && script.indexOf("TRACKER_SHA256") < script.indexOf('"$RUNNER_TEMP/base-script/$(basename'),
  "the script step checks the tracker config's SHA-256 before running the script");
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
