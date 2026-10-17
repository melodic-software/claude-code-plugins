---
description: "Verify instruction-placement's prerequisites, resolve its effective configuration for this repository, and register its rules-index git pre-commit entry. Confirm that the index target exists AND that nothing in the repository stops Claude Code loading it (a root CLAUDE.md is read instead of the AGENTS.md beside it, so an unimported AGENTS.md index is inert while every other gate reports green), that `git` backs tracked-file discovery, and that the Claude Code CLI plus `jq` are present for the optional empirical load probe. Reports the resolved index target, breadth ceiling, and index row cap, naming which came from configuration and which from a default. Use when: 'set up instruction-placement', 'configure instruction-placement', 'where will the index go', 'why is my index not loading', 'is instruction-placement working', or before a first audit on a new repository. Actions: check (read-only, default) | apply (point at each remediation) | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply [install-git-hooks [scope=local|shared]]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" audit 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`, "Setup is
explicit and repeatable"): `check` inspects and reports, `apply` points at what it found.

The warrant is all three criteria, but one carries the weight. **The index target is an external
referent whose validity cannot be established by a configuration prompt.** A prompt stores the path
you typed; it cannot tell you that Claude Code will never read it. A `CLAUDE.md`, `.claude/CLAUDE.md`
or `CLAUDE.local.md` at the root is read *instead of* the `AGENTS.md` beside it, so a repository
carrying both with no import between them gets a perfectly generated, perfectly in-sync index that
never enters context, with every other gate green. Verifying that before a first audit is this
skill's job; `/instruction-placement:check` asks the same question again on every gate run.

This skill treats the root `AGENTS.md` as shadowed wherever a `CLAUDE.md`, `.claude/CLAUDE.md` or
`CLAUDE.local.md` sits in the working directory or above it, and treats direct `AGENTS.md` reading
as dependent on the CLI floor and session recorded in `skills/migrate/reference/sources.md`, "The
minimum CLI version". Canary runs on Claude Code 2.1.278 observed the shadowing.

- **Pointer**: for when Claude Code reads `AGENTS.md` and when that support is unavailable, see
  <https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md> and
  <https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable>.
- **As of**: 2026-09-29
- **Recheck trigger**: those sections change which file names shadow `AGENTS.md`, or a release note
  names `AGENTS.md` or instruction-file loading.

Secondary warrants: `git` backs tracked-file discovery for nested instruction files, `node` runs the
git-hook installer and the session-start drift probe, and the optional empirical load probe needs
the Claude Code CLI plus `jq`. The only consumer-project files this plugin owns are its git-hook
entry copies, which `apply install-git-hooks` writes.

## Action: check (default)

Read-only. Report each item with a verdict, and never repair anything.

**1. Index target, the one that matters.** Resolve it the way `check` does (explicit argument,
then root `AGENTS.md`, then root `CLAUDE.md`), then verify reachability:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" reachable --file <resolved target>
```

| Verdict | Meaning | Say |
|---|---|---|
| `LOADED` | Claude Code reaches it | Name the file and the path it was reached by |
| `NATIVE` | nothing in the repository blocks it | Report it as **unblocked, never as loaded**: no `CLAUDE.md` on its path displaces it, and whether Claude Code read it also depends on version and session kind, which no static check sees. `verify-load.sh` is the only thing that proves it loaded |
| `UNREACHABLE` | it exists and is never read | **The headline finding.** Name the missing import |
| target absent | no index home yet | Not a failure. Say which file `apply` would propose |

**2. `git`.** Present and this is a work tree? Nested-instruction discovery is tracked-only, so
without git it falls back to a plain walk and cannot honor the tracked-only corpus rule. Report the
degradation rather than implying full behavior.

**3. `node`.** Probe it through the Bash tool: `command -v node && node --version`. The
git-hook installer and the session-start probe run on it, so without `node` on `PATH` the
pre-commit entry cannot be installed or verified. FAIL when absent, with that consequence. The
skills and scripts still work, and an already-installed entry keeps running at commit.

**4. Empirical probe prerequisites.** `jq` on `PATH`, and a Claude Code CLI. Both are optional: the
static gates work without them and only `verify-load.sh` degrades. Say "optional, absent" rather
than "missing". An absent optional prerequisite is not a failure.

**5. Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is INFO
(this clone said no; silent at session start), and `missing`, `stale` or `modified` is a FAIL
whose remediation is `apply install-git-hooks`. The entry needs no external tool. Outside a git
repository, report INFO and skip the step.

**6. Effective configuration.** Print each value with its **source**, so a surprising number is
traceable:

| Setting | Default | Source to report |
|---|---|---|
| index target | root `AGENTS.md`, else root `CLAUDE.md` | resolved-from |
| `breadth_max` | 75 | `user_config` or default |
| `index_max_rows` | 40 | `user_config` or default |

A value equal to the default is still reported with its source. "40 (default)" and "40 (configured)"
are different facts about a repository.

## Action: apply

**Writes nothing on its own.** Every remediation here edits a file that steers agent behavior, and
that is the operator's call, not a setup skill's. `apply` presents the exact change and asks. The
one write path is `apply install-git-hooks`, which writes only files this plugin owns.

| Finding | Proposed remediation |
|---|---|
| Index target `UNREACHABLE` | Add `@AGENTS.md` as the first line of the root `CLAUDE.md`, or symlink `CLAUDE.md` → `AGENTS.md`. Show the exact line and its position. Removing the root `CLAUDE.md` instead is a repository-wide decision, not a setup remediation: route it to `/instruction-placement:migrate` |
| Index target `NATIVE` | Nothing to do. No root `CLAUDE.md` blocks the target, so Claude Code reads it where `AGENTS.md` support is available. Report it as unblocked, never as verified loaded: run the empirical probe if the operator wants proof |
| No index home | Name the file `render-index.sh write` would target, and offer to create the block |
| `git` absent | State the degradation; there is nothing to install on the consumer's behalf |
| `node` absent | Name it and the consequence (the git-hook entry cannot be installed or verified); install nothing |
| Git entry `missing`, `stale` or `modified` | `apply install-git-hooks` |
| `jq` or CLI absent | Name the tool and that only `verify-load.sh` is affected |

After an accepted change, re-run the reachability check and report the new verdict. An `apply` that
does not re-verify has not finished.

## Action: apply install-git-hooks [scope=local|shared]

Registers the plugin's git-hook entry (`git-hooks/entries.json`) with the repository's hook manager.
The installer script only detects, renders and writes files the plugin owns; every step that needs
judgment comes back to you as a `decisions[]` item, which you reason about and apply with your own
edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local` (this
   clone only, nothing committed) or `shared` (committed under `.githooks/instruction-placement/`,
   so every teammate and agent gets it). When nobody can answer, use `local`.
2. **Plan.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" plan --scope <scope>` and
   read the JSON: `manager`, `actions[]`, `decisions[]`.
3. **Manager conflict.** A `manager-conflict` decision lists the evidence (two managers, or one this
   installer does not drive, such as the pre-commit framework). Show it and ask which manager should
   carry the entry; rerun `plan` with `--manager lefthook|husky|plain`. Without an answer, stop here
   and report.
4. **Actions.** When `actions[]` holds `copy` items, run
   `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" copy --scope <scope>` (plus the same
   `--manager` when you passed one). It prints `installed`, `refreshed`, `unchanged`, `refused` or
   `blocked` per entry; `refused` means a locally edited copy, which the `modified` decision covers,
   and `blocked` means another tool owns the local hooks directory, which the `hooks-path-owned`
   decision covers.
5. **Decisions.** Read [reference/git-hook-decisions.md](reference/git-hook-decisions.md) for what
   each kind asks of you, apply each one, then rerun `plan` until only the decisions you chose to
   leave remain.
6. **Verify.** Run `verify` and report its lines as `check` step 5 does.

The entry rewrites nothing: at commit it fails when a staged path is under `.claude/rules/` or is
the index file and the generated rules index no longer matches, and prints the regenerate command.
A repository with no index block is never failed.

When the user does not want the entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry index-check`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in.

## Hard rules

- **Idempotent.** Re-running changes nothing that is already correct, and says so rather than
  reporting work it did not do.
- **`check` never writes.** Not settings, not `CLAUDE.md`, not the index.
- **Never install anything.** Name the tool and the reason; the operator's machine is theirs.
- **Never report a prerequisite verified without probing it.** An absent probe is `unknown`, and
  `unknown` is never reported as `ok`.
- **An optional prerequisite's absence is not a failure.** Only the index-target verdict can make
  this skill report a problem with the repository itself.

## Next

- Prerequisites report ready: `/instruction-placement:audit`.
- `UNREACHABLE`, and the repository wants `AGENTS.md` to be the content home rather than another
  import: `/instruction-placement:migrate`.
- Rules or an index already exist and only need gating: `/instruction-placement:check`.

## Gotchas

- **`UNREACHABLE` is the finding people do not expect.** Everything else can be green while the
  index does nothing. Lead with it when it fires; it is the reason this skill exists. It fires only
  where a root `CLAUDE.md` is read instead of the target; `NATIVE` is the other outcome and is not a
  finding.
- **A target that does not exist yet is not unreachable.** Those are different states with different
  remedies. Do not collapse them into one verdict.
- **Reachability is not sync.** A reachable index can still be stale, and a stale index can still be
  reachable. `/instruction-placement:check` gates both on every run. This skill asks only the
  reachability question, as a prerequisite before the first audit.
- **The plugin works with no configuration.** Every setting has a default that behaves. Do not
  present configuration as a prerequisite to a first audit.
