---
description: "Verify and configure the mutation-testing plugin for this repository. check inspects the ecosystem's mutation tool (installed, runnable, supported test runner), the baseline suite's health, and the tracked .claude/mutation-testing.md config across its merge layers, read-only; apply detects the ecosystem, installs or names the tool, interviews for the diff target and operator set, and writes the config plus an empty arid-node suppression record. Use when: 'set up mutation testing', 'is mutation testing configured', 'which mutation tool for this repo', 'mutation-testing setup', or the audit skill reports missing config or an unavailable tool. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Establish the four things `/mutation-testing:audit` cannot infer safely at run time: **which tool**,
**which diff target**, **which operators**, and **where arid-node suppressions live**.

Configuration is required rather than optional here, which differs from a plugin whose config merely
speeds up inference. A mutation run drives the project's own test runner against deliberately broken
source; guessing the tool or the diff target either does nothing or does something expensive. `check`
inspects read-only; `apply` interviews and writes, then re-runs `check`. No argument or `check` runs
the check; `apply` runs the check first, then the write flow.

## The config merge model

`.claude/mutation-testing.md` resolves across the documented cascade layers — user-global
(`~/.claude/mutation-testing.md`) → team (`${CLAUDE_PROJECT_DIR}/.claude/mutation-testing.md`) →
local overlay (`.claude/mutation-testing.local.md`), later layers overriding scalars and unioning
lists. This skill writes only the **team** file; a higher overlay is the user's to change. Report
explicitly when an overlay changes the team file's effect, and warn — rather than silently
presenting the team file as effective — when a layer cannot be read.

The arid-node suppression record is a **separate** surface, `.claude/mutation-testing-arid.md`,
shaped by the finding-suppression convention. Keeping it separate from the config keeps the config
reviewable: a config diff is a policy change, a suppression diff is an accepted finding.

**Its layering is not the config's, and the difference is the whole point.** The config's later
layers override; the suppression record sits in the cascade's policy-floor precedence-inversion
class, so on a conflict for the same `finding_id` the **team** layer wins, and **a personal-layer
entry for an id the team layer does not carry does not suppress at all** — it is reported
`personal-only, not applied`. A personal layer is a draft surface here. Treating it as "layered the
same way" would let one developer silently hide a finding the team never accepted. The full
contract, including id derivation and the four dispositions, is owned by the audit skill's
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/suppression.md`](../audit/context/suppression.md).

## `check` (read-only)

Report a PASS / FAIL / INFO table with one remediation line per FAIL. Modify nothing, and do **not**
run a mutation analysis — that is `/mutation-testing:audit`.

1. **Ecosystem detected** — identify the stack from manifests that actually exist (`package.json`,
   `*.csproj`/`*.sln`, `pom.xml`/`build.gradle`, `composer.json`, `pyproject.toml`). Report what was
   found and which mutation tool it implies. No recognized ecosystem → INFO naming the manual path
   in the `principles` skill's `tooling.md`, not FAIL.
2. **Tool present and runnable** — invoke the tool's own version command. Absent → FAIL with the
   install line for this ecosystem. Present but erroring → FAIL quoting the error; a tool that
   installs but cannot start is the common case and is worth distinguishing.
3. **Test runner supported** — confirm the project's runner is one the tool drives. Report the
   detected runner and the tool's support status. Unsupported → FAIL; this blocks every later step,
   so report it before anything about scores.
4. **Baseline suite is green** — run the project's test command once, unmutated, and report the
   result. Red → FAIL. A red baseline kills every mutant and reports a perfect score, so no mutation
   result is meaningful until this passes. Record the wall-clock; it is the input to the timeout
   setting and to whether diff-scoping is sufficient.
5. **Known flakiness** — ask, and check for a documented flaky-test list or retry configuration.
   Flakiness present → INFO with the consequence stated plainly: mutants killed by a flaky failure
   inflate the score by an unknown margin.
6. **Config presence (effective, across layers)** — report the merged result and which layer
   contributes what: tool, diff target, operator set, timeout, paths to mutate. Nothing readable →
   FAIL; unlike an inference-speeding config, this one is required.
7. **Diff target resolves** — the configured target must resolve in this repository
   (`git rev-parse --verify <target>`). Unresolvable → FAIL naming it; a stale default here silently
   scopes a run to nothing or to everything.
8. **Suppression record** — report presence and entry count of `.claude/mutation-testing-arid.md`
   across layers. Absent is a valid state (no suppressions) → INFO. Present → validate **every**
   entry against the full contract in
   [`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/suppression.md`](../audit/context/suppression.md), not a subset of it:
   - **All five required keys present** — `check`, `claim`, `sites` (each with `surface` and an
     `anchor/v<N>`), `reason`, `date`. Missing any one → FAIL, naming the entry and the key. A
     partial parse is not offered: an entry with `sites`, `reason`, and `date` but no `check` or
     `claim` is malformed and must not be reported as usable, because the audit would otherwise
     suppress a mutant on a location match the contract never authorized.
   - **Constituents hash to the key** — re-derive `finding_id` from `(check, claim, sites)` and
     compare. A mismatch → FAIL. This is the case a hand-edited constituent beside a stale key
     produces, and it silently stops suppressing if unchecked.
   - **`claim` is a bound canonical id, not prose** — `arid(kind=<node-kind>)` where `<node-kind>` is
     a **member of the enumerated table** in
     `${CLAUDE_PLUGIN_ROOT}/skills/principles/reference/scaling-and-suppression.md`
     ("The node-kind vocabulary"). Validate by membership in
     that table, not by shape: a single-word kind that is not in it is indistinguishable from prose
     that happens to be one word, and passing it would make every suppression self-justifying. Free
     prose, or a kind outside the table → FAIL, listing the accepted kinds.
   - **Personal-only entries** — any id present in a `.local.md` layer but absent from the team layer
     is reported `personal-only, not applied`, with promotion to the team layer named as the remedy.
     This is INFO, not FAIL: the entry is legal, it simply does not suppress.
   - Report the contributing layer for every entry. A malformed layer degrades soft — report it and
     continue, never fail the whole read.
9. **Tracked, not ignored** — both the config and the suppression record must be committed to be
   team-shared, and *not ignored* is only half of that. Run **both** probes per file:
   `git ls-files --error-unmatch <path>` (is it tracked?) and `git check-ignore -v <path>`
   (is it ignored?). Untracked → FAIL, naming the `git add` that fixes it; ignored → FAIL with the
   matching pattern. Checking only `check-ignore` is the trap: immediately after `apply` writes them
   the files are untracked but not ignored, so `check-ignore` is silent and the probe would report
   success on two files no teammate will ever receive. The `.local.md` overlays are expected to be
   both untracked and ignored — INFO, not FAIL.

## `apply` (idempotent)

Run `check`, then interview and write. Proceed non-interactively where the repository makes a value
unambiguous; ask only where the answer is genuinely the user's.

1. **Read the effective config first, across all layers**, and summarize it before proposing
   changes. Nothing is dropped without the user confirming.
2. **Detect and propose the tool.** From the ecosystem, name the tool and the exact install command,
   and ask before installing anything. Installing a dependency into the consumer's project is the
   user's decision, not this skill's — propose, never install unprompted.
3. **Settle the diff target.** Default to the repository's own default branch as resolved from
   `origin/HEAD`, not a hardcoded `main` or `master`. Confirm it resolves.
4. **Settle the operator set.** Default to the tool's defaults, and say why: optional and
   experimental operators raise the mutant count and the unproductive rate together. Offer the
   narrowed set only if the user asks for a cheaper run.
5. **Settle the timeout** from the measured baseline suite time in `check`, not from a guess.
6. **Settle the mutate paths.** Propose source roots, excluding generated code, vendored
   directories, and test code itself. Mutating tests measures nothing.
7. **Write the config** following
   [`${CLAUDE_PLUGIN_ROOT}/skills/setup/templates/config-template.md`](templates/config-template.md).
8. **Create the suppression record empty**, with its header comment and an empty `suppressions:`
   mapping — a **mapping, never a list**, since a list is taken whole and one personal entry would
   discard the team's entire accepted set. An empty record makes the first suppression an edit to a
   reviewed file rather than the creation of a new one.
9. **Stage both files for commit and say so.** They are team-shared surfaces; leaving them untracked
   is the failure probe 9 exists to catch, and `apply` is where it is cheapest to fix. Offer the
   `git add`; never commit on the user's behalf.
10. **Verify after remediation.** Re-run the `check` probes on what was written — including both
    halves of probe 9, tracked *and* not-ignored — then offer the overlay convention: personal
    config overrides in `.claude/mutation-testing.local.md`, and recommend `.claude/*.local.*` in
    `.gitignore` if not already covered. State plainly that the same overlay pattern does **not**
    give personal suppressions effect: an arid entry in a `.local.md` is a draft until promoted to
    the team layer.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

A tracked `.claude/mutation-testing.md` and `.claude/mutation-testing-arid.md` in the consuming repo,
plus a one-paragraph summary of what was written, the measured baseline suite time, and how to
re-run this setup to reconfigure.

## What this skill does NOT do

- Run a mutation analysis — that is `/mutation-testing:audit`. `check` runs the *unmutated* suite
  once to establish the baseline, and nothing more.
- Install anything without asking.
- Write machine-local state — configuration lives in the consumer's tracked files, never in the
  plugin directory or the plugin data directory.
- Set a score threshold. The config template deliberately has no such field; see the `principles`
  skill's `scaling-and-suppression.md` for why gating on the score inverts the incentive.
