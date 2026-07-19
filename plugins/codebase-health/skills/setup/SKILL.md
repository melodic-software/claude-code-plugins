---
name: setup
description: "Verify and configure the codebase-health plugin for this repository. check inspects the tracked .claude/codebase-health.md config read-only across its merge layers (presence, dimension source lists, tracked-not-ignored); apply interviews the user, infers audit targets from the repo layout, and writes the config. Use when: 'set up codebase-health', 'is codebase-health configured', 'configure the audit', 'codebase-health setup', the audit skill reports missing or thin config, or audit dimensions need tuning. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and manage the consuming repo's tracked audit-dimension config at `.claude/codebase-health.md`
so `/codebase-health:audit` runs deterministically instead of re-inferring targets every run.

The config is optional: with none, the audit re-infers its targets each run, so its absence is a
reported INFO, never a FAIL. `check` inspects the effective merged config read-only; `apply` interviews
and writes it, then re-runs `check`. No argument or `check` runs the check; `apply` runs the check
first, then the interview-and-write flow. Idempotent: re-running reads the existing config and offers
updates rather than overwriting blind.

## The config merge model

The audit config resolves as an additive merge of the documented layers — user-global
(`~/.claude/codebase-health.md`) → team (`.claude/codebase-health.md`) → local overlay
(`.claude/codebase-health.local.md`) — where a later layer's globs union with (not replace) the
earlier layer's and example-claims concatenate, **except** that a later layer declaring a dimension
with empty source lists is an explicit opt-out that *removes* that inherited dimension. This skill
writes only the **team** file; changes to a higher overlay are the user's to make.

## `check` (read-only)

Inspect the effective merged config and report a PASS/FAIL/INFO table with one remediation line per
FAIL. Modify nothing, and do NOT run an audit — that is `/codebase-health:audit`.

1. **Config presence (effective, across layers)** — load every layer you can access and report the
   *effective merged* result honoring opt-outs (dimensions present, glob counts, example-claim counts),
   and which layer contributes what. No layer readable and no team file → INFO: the audit re-infers
   targets each run; `apply` writes `.claude/codebase-health.md` to make the run deterministic. When a
   higher layer (a user-global base outside the repo) cannot be read, WARN it was not considered rather
   than presenting the team file alone as the effective config.
2. **Dimension source lists** — for each dimension present in the team file, its declared source lists
   parse and name real paths/globs. A dimension whose source list is malformed or fails to parse is
   FAIL, naming it. A dimension deliberately zeroed (empty source lists) by an overlay is INFO (an opt-out),
   reported as removed, not broken.
3. **Tracked, not ignored** — a present team file must be committed to be team-shared: run
   `git check-ignore -v .claude/codebase-health.md`; a non-empty result is FAIL with the matching
   pattern. The `.local.md` overlay is expected to be ignored — INFO, not FAIL.
4. **Overlay divergence** — INFO: when a local or user-global overlay changes the team file's effect
   (adds globs, or opts a dimension out with empty source lists), say so explicitly, since `apply`
   writes only the team file.

## `apply` (idempotent)

Run `check`, then interview and write the config. Proceed non-interactively where the invocation and
the repo make the values unambiguous; ask only where a dimension's targets genuinely need the user.

1. **Read the effective config first, across all layers.** Load every layer you can access and present a
   short summary of the *effective merged* result — honoring opt-outs, so a dimension a higher layer
   deliberately zeroed out is reported as removed, not present — and report which layer contributes what.
   When a local or user-global layer changes the team file's effect — whether it *adds* globs or *opts a
   dimension out* with empty source lists — **say so explicitly**, because this step writes only the
   *team* file. A team-scope edit alone will not account for what a higher overlay contributes; in
   particular, when a local (or user-global) opt-out zeroes a dimension, accepting a team-scope
   *re-enable* here will not restore that dimension on this machine — the overlay keeps removing it — so
   prompt the user to also remove or update the opt-out in that overlay, not just re-enable it in the
   team file. When a higher layer cannot be read (a user-global base is often outside the repo and
   OS-specific), **warn that it was not considered** rather than presenting the team file alone as the
   effective config. The interview then proposes changes against that baseline; nothing is dropped
   without the user confirming.
2. **Explore the repo to draft defaults.** Before asking anything, infer candidates:
   - **documentation** primary-sources: doc directories (`docs/`, `README.md`), agent-instruction
     files (`AGENTS.md`, `CLAUDE.md`), ADR directories, convention docs.
   - **configuration** primary-sources: build config, lint config, CI workflows, git-hook config —
     detected from what actually exists (e.g. `Directory.Build.props`, `pyproject.toml`,
     `package.json`, `.github/workflows/`, `lefthook.yml`, `.editorconfig`).
   - **code-quality** primary-sources: source roots; verification-sources: test roots **plus the
     same source roots** — a cross-file DRY/SOLID claim is validated by reading peer source files,
     which a discovery agent can only read when they are in `verification-sources` (the fence forbids
     the other primary-source files). Omitting them makes cross-file findings unreachable.
   - **architecture** primary-sources: dependency manifests + architecture docs;
     verification-sources: analyzers / architecture tests where present **plus the dependency
     manifests and source roots** — dependency-direction and boundary claims need peer manifests
     readable, for the same fence reason.
3. **Interview, one decision at a time.** Present each dimension's drafted globs with a
   recommendation; let the user accept, edit, or remove the dimension. Offer custom dimensions
   last ("anything else this repo should audit as its own lane?").
4. **Draft example-claims.** For each accepted dimension, read one or two representative
   primary-source files and propose 2–4 concrete `{ claim, verify-via }` rows drawn from real
   sentences in them. Concrete rows teach the discovery pass what drift looks like in THIS repo —
   the highest-value part of the config. The user approves or edits each row.
5. **Write the config.** Materialize `.claude/codebase-health.md` following the structure in
   [`${CLAUDE_PLUGIN_ROOT}/skills/setup/templates/config-template.md`](templates/config-template.md) (replace every placeholder comment
   with real values; drop unused placeholder rows).
6. **Verify after remediation.** Re-run the `check` probes on the written file — dimension source lists
   parse and name real paths, and `git check-ignore -v .claude/codebase-health.md` confirms it is
   tracked, not ignored (surface the matching pattern and offer to fix `.gitignore` before reporting
   success). Then **offer the overlay convention**: personal overrides go in
   `.claude/codebase-health.local.md`; recommend the consumer add `.claude/*.local.*` to `.gitignore`
   if not already covered. A user-global base at `~/.claude/codebase-health.md` is also honored. Layers
   resolve user-global → team → local overlay, additively.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

A tracked `.claude/codebase-health.md` in the consuming repo, plus a one-paragraph summary of what
was written and how to re-run this setup to reconfigure.

## What this skill does NOT do

- Run an audit — that is `/codebase-health:audit`. `check` only inspects config.
- Write machine-local state — configuration lives in the consumer's tracked file, never in the
  plugin directory or the plugin data directory.
