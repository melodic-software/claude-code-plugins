---
description: "Emit the file-name gate into a consuming repository: a standalone bash checker plus its own test suite, with the casing rule, roots, and exemptions inlined from the resolved docs-hygiene configuration, and optionally the path-scoped rule file. The emitted pair carries no dependency on this plugin at run time. Refuses to overwrite without --force, and states the wiring it deliberately leaves to the consumer. Use when: 'generate the file-name gate', 'add a CI check for doc filenames', 'enforce the naming rule', 'emit the naming checker', 'we need a gate for this convention', 'write the file-names rule file', or after docs-hygiene:setup apply has written the configuration."
argument-hint: "[--out-dir <dir>] [--rule] [--force]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/emit-gate.sh:*)", "Bash(git rev-parse:*)", "Bash(git status --porcelain:*)", "Read"]
shell: bash
---

# Generate File Name Gate

## Purpose

A naming rule that nothing enforces decays back into a mixed tree, one file at
a time. This skill writes the thing that enforces it: a checker over the tracked
set, plus the suite that proves the checker still means what it says.

The checker is the consumer's file, not this plugin's. The rule, the roots, and
every exemption are inlined at emission, so a checkout with the plugin
uninstalled, or a CI runner that never had it, still enforces what the team
agreed.

**A path-scoped rule file is not a substitute.** Such a rule loads when a
covered file is READ, never when one is created, so it cannot catch the new file
that breaks the convention. That is why the gate is the deliverable and the rule
is the option.

## Emit

```bash
${CLAUDE_SKILL_DIR}/scripts/emit-gate.sh --root <repo> [--out-dir <dir>] [--rule] [--force]
```

- `--out-dir` places the pair somewhere other than `scripts/`. The emitted
  checker resolves the repository from its own location, so any depth works.
- `--rule` also writes `.claude/rules/file-names.md`.
- `--force` overwrites. Without it an existing target refuses the run and
  **nothing** is written, including the files that did not exist yet.

The output is `EMITTED` rows for what it wrote, possibly a `REINDEX` row, and
`NOT-WIRED` rows for what it did not. Report all three kinds; the `NOT-WIRED`
rows are the point of the run as much as the files are.

## What the templates render

| Template | Emitted as | Carries |
|---|---|---|
| [`templates/check-file-names.sh.tmpl`](templates/check-file-names.sh.tmpl) | `<out-dir>/check-file-names.sh` | the rule, the roots, the exemptions, and the case-collision pass |
| [`templates/check-file-names.test.sh.tmpl`](templates/check-file-names.test.sh.tmpl) | `<out-dir>/check-file-names.test.sh` | one case per declared exemption, seeded with a name the rule would reject |
| [`templates/file-names-rule.md.tmpl`](templates/file-names-rule.md.tmpl) | `.claude/rules/file-names.md`, only with `--rule` | the rule in prose, scoped to the roots, naming the gate |

Read a template only when a rendered file looks wrong; the emitted files are
what the operator reviews.

## After emitting, say what is left

Emission writes files. It does not wire them, because each of these is a
repository-shaped decision with no single right answer:

- **A CI step** invoking the checker. Name the emitted path and let the
  operator place it in their own workflow.
- **A registry row**, if the repository keeps a list of its gates.
- **An architecture decision record** for the rule itself. Offer
  `/architecture:record-decision`; do not write one unprompted.

If a `REINDEX` row appeared, the repository's `AGENTS.md` or `CLAUDE.md` carries
a generated instruction-placement rules index, and the new rule file is not in
it yet. Say so and name `/instruction-placement:check`; do not edit the block.

## Verify before handing back

Run the emitted pair once, from the consumer's root:

```bash
bash <out-dir>/check-file-names.sh --check
bash <out-dir>/check-file-names.test.sh
```

The checker's exit is the answer about the tree, not about the emission: a `1`
here means the repository already has offenders, which is a finding to report
and route to `/docs-hygiene:audit-file-names`, not a failed run.

## Completion criteria

The run is done when the `EMITTED` rows name files that exist, the emitted suite
exits 0, the checker has been run once and its verdict reported, and every
`NOT-WIRED` row has been said out loud to the operator.

## What this skill does NOT do

- **Wire the gate into CI, a registry, or a decision record.** It names each one
  and stops.
- **Edit a generated rules index.** It reports that one needs re-rendering.
- **Rename anything.** An existing offender is `/docs-hygiene:audit-file-names`
  to plan and `/docs-hygiene:realign-file-names` to apply.
- **Write the configuration.** That is `/docs-hygiene:setup apply`, which owns
  the plugin's own artifact and nothing else.
- **Overwrite silently.** A target that exists refuses the whole run.
- **Commit, stage, or push.**

## Next

`/architecture:record-decision`

For the rule itself, once the gate is wired and green.

## Gotchas

- **A rule file is a pointer surface a repository may deliberately not carry.**
  Some trees strip pointer rules that already have an owner document and a
  deterministic oracle, on the argument that the gate is the oracle. `--rule` is
  opt-in for exactly that reason; offer it and let the operator decide.
- **A configuration value is untrusted text, and the emitted gate runs in CI.**
  Three hazards, each closed at a different layer: rendering is a literal splice
  rather than a `sed` substitution, so an `&` or a `|` in a regex cannot be
  re-read; values travel through the environment rather than `awk -v`, which
  performs escape processing and would halve a doubled backslash; and every
  value reaching the emitted shell is single-quoted, so a backtick or a
  `$(...)` in a root or an exemption cannot execute on a CI run.
- **A rendered file that bash cannot parse is a refusal, not an `EMITTED` row.**
  Each rendered script goes through `bash -n` before it is claimed, and a
  failure removes it and stops the run.
- **The emitted suite's probe names come from the rule, not from the template.**
  A rule that admits no probe name, or rejects none, is refused at emission
  rather than handed over as a suite that fails on its own clean fixture.
- **Re-emit rather than hand-edit.** The configuration is what the audit and
  realign skills read; an edit made only in the emitted checker drifts from them
  with nothing to catch it.
- **A refused run writes nothing at all.** The overwrite check runs over every
  target before the first write, so a partial emission cannot happen.
- **The emitted checker is only as current as the configuration was.** Changing
  a root or an exemption means emitting again with `--force`.
