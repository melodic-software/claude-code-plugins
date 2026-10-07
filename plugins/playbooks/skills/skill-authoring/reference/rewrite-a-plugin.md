# Rewriting a plugin's skills

The order of work for bringing one plugin's skills to the [skill criteria](skill-criteria.md),
one plugin per pull request. The [rewrite protocol](skill-criteria.md#measurement) decides what
ships; this page says how to run it across a plugin and what the first run (`code-tidying`)
learned. "Step N" below is the protocol's step N.

## Contents

- [Before you start](#before-you-start)
- [Order of work](#order-of-work)
- [Checks eval files trip](#checks-eval-files-trip)

## Before you start

- Run `/evals:plugin-eval preflight <plugin>`. A case that grants `Bash`, `Write` or `Edit` needs a
  sandbox backend, and the skill names the route when this host has none or when the CLI refuses a
  repository with many linked worktrees.
- Each eval pass is a paid run. `/evals:plugin-eval` estimates every pass before it starts and
  stops at the configured ceiling; set the ceiling for the whole plugin before step 4, because a
  pass cut short by the ceiling is not comparable.
- Work on a branch from the default branch and open the pull request as a draft.

## Order of work

1. **Inventory.** List each skill, whether it is model-invoked, its outcome cases under
   `evals/`, and its probe file `probes/<skill>.json`. Run `/skill-quality:check <plugin root>` and
   keep the output as the before state.
2. **Cases (step 2).** A skill with no outcome case gets them from `/evals:design`, written by a
   fresh agent from the before contract. Prefix each case directory with a short tag for its
   skill. Shared fixtures go in `evals/fixtures/`; name each one in a scaffold, or in a seed script
   a scaffold runs. Then:
   - `/evals:validate` the suite, and calibrate each `llm` grader as `/evals:plugin-eval`
     "Calibrating a judge" says.
   - Run one smoke pass on the before version. Hand each failure to a fresh agent that classifies
     it as real, a grader defect, or a case defect. A grader fix must accept every reply that meets
     the case's expected outcome, proved on the observed replies and on a reply written to fail.
   - Freeze the suite: record a digest of the `evals/` tree, and change nothing in it after the
     first after-version run.
3. **Probes (step 3).** Keep the frozen set in `probes/<skill>.json`, checked with
   `/skill-quality:check measure-invocation`. Write the held-out set outside the repository. The
   rewriter's brief forbids reading any probe file, because a rewriter that can read probes tunes
   to them.
4. **Rewrite.** Apply the skill criteria. Keep each description's quoted trigger phrases until a
   held-out run on every target model shows they are not needed. A rule's stated reason can carry
   behavior, so cut a rationale only when a case covers the behavior it explains.
5. **Measure (step 4).** Copy the before and after plugins outside the repository and launch every
   pass together: each version on each target model, with and without the plugin, the same
   `--runs`, judge and threshold, and `--keep-temp`. For triggering, emit cases from the held-out
   probes with `/skill-quality:check measure-invocation` `emit-plugin-eval` and run them with
   `--ablation none`. Write any exclusion rule (a case the harness cannot run, say) before reading a
   number, and apply it to both versions. Then, per suite and model:
   - `/evals:plugin-eval` must judge each result VALID.
   - Read its two-version noise report, after against before, at the protocol's margin.
   - For a `case drop`, restore the cut text and re-run that case against a fresh before control,
     launched together. When no restore closes the gap, the before text ships.
6. **Meaning diff (step 5).** Run `/docs-hygiene:compress compare` with two independent labelers
   and take the union of their losses, since one labeler can miss a loss the other catches.
7. **Decide (step 6).** Decide each skill's description and body separately, and put the per-skill
   decision table, with the numbers behind each row, in the pull request body.
8. **Ship (step 7).** Commit the skills, cases, fixtures and probe files, plus the plugin's version
   or changelog entry in the plugin's release mode. Run `/skill-quality:check <plugin root>` again
   and compare it with the before state.

## Checks eval files trip

- A file that starts with `#!`, fixtures included, must be committed executable:
  `git update-index --chmod=+x <file>`.
- Every file under `evals/fixtures/` must be named by a scaffold, or by a seed script a scaffold
  runs, or the orphaned-fixtures check fails it.
- Scaffolds and seed scripts pass shellcheck with the repository's rc file.
- The spelling check reads grader regexes too: write `behav(?:ior|iour)`, not a truncated stem.
- A `file_exists` grader with `exists: false` fails on every run in which the skill runs git,
  because the harness counts git's own index files as created. Use must-not-call `Write` and `Edit`
  graders instead. Pointer: the `file_exists` grader section of
  <https://code.claude.com/docs/en/plugin-evals>; basis: observed in kept traces at Claude Code
  2.1.289. As of: 2026-10-07. Recheck trigger: that section or a release note changes how created
  files are counted.
- The eval sandbox denied a skill's read of its plugin config and its writes under `.claude/`, so
  a setup-style skill could not be measured there. Name such cases as unmeasured in the pull
  request rather than reading their scores. Pointer: the sandbox and grant-tools sections of
  <https://code.claude.com/docs/en/plugin-evals>; basis: observed at Claude Code 2.1.289. As of:
  2026-10-07. Recheck trigger: either section or a release note changes eval sandbox permissions.
