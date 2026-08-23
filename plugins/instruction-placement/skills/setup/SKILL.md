---
description: "Verify instruction-placement's prerequisites and resolve its effective configuration for this repository — that the index target exists AND is actually reachable by Claude Code (it reads CLAUDE.md, not AGENTS.md, so an unimported AGENTS.md index is inert while every other gate reports green), that `git` backs tracked-file discovery, and that the Claude Code CLI plus `jq` are present for the optional empirical load probe. Reports the resolved index target, breadth ceiling, and index row cap, naming which came from configuration and which from a default. Use when: 'set up instruction-placement', 'configure instruction-placement', 'where will the index go', 'why is my index not loading', 'is instruction-placement working', or before a first audit on a new repository. Actions: check (read-only verification, default) | apply (point at each remediation; writes nothing on its own). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" audit 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`, "Setup is
explicit and repeatable"): `check` inspects and reports, `apply` points at what it found.

The warrant is all three criteria, but one carries the weight. **The index target is an external
referent whose validity cannot be established by a configuration prompt.** A prompt stores the path
you typed; it cannot tell you that Claude Code will never read it. Claude Code loads `CLAUDE.md`, not
`AGENTS.md`, so a repository carrying both with no import between them gets a perfectly generated,
perfectly in-sync index that never enters context — with every other gate green. Verifying that is
this skill's main job, and nothing else in the plugin can do it before a migration has already
happened.

Secondary warrants: `git` backs tracked-file discovery for nested instruction files, and the
optional empirical load probe needs the Claude Code CLI plus `jq`.

## Action: check (default)

Read-only. Report each item with a verdict, and never repair anything.

**1. Index target — the one that matters.** Resolve it the way `check` does (explicit argument,
then root `AGENTS.md`, then root `CLAUDE.md`), then verify reachability:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" reachable --file <resolved target>
```

| Verdict | Meaning | Say |
|---|---|---|
| `LOADED` | Claude Code reaches it | Name the file and the path it was reached by |
| `UNREACHABLE` | it exists and is never read | **The headline finding.** Name the missing import |
| target absent | no index home yet | Not a failure — say which file `apply` would propose |

**2. `git`.** Present and this is a work tree? Nested-instruction discovery is tracked-only, so
without git it falls back to a plain walk and cannot honor the tracked-only corpus rule. Report the
degradation rather than implying full behavior.

**3. Empirical probe prerequisites.** `jq` on `PATH`, and a Claude Code CLI. Both are optional: the
static gates work without them and only `verify-load.sh` degrades. Say "optional, absent" rather
than "missing" — an absent optional prerequisite is not a failure.

**4. Effective configuration.** Print each value with its **source**, so a surprising number is
traceable:

| Setting | Default | Source to report |
|---|---|---|
| index target | root `AGENTS.md`, else root `CLAUDE.md` | resolved-from |
| `breadth_max` | 75 | `user_config` or default |
| `index_max_rows` | 40 | `user_config` or default |

A value equal to the default is still reported with its source — "40 (default)" and "40 (configured)"
are different facts about a repository.

## Action: apply

**Writes nothing on its own.** Every remediation here edits a file that steers agent behavior, and
that is the operator's call, not a setup skill's. `apply` presents the exact change and asks.

| Finding | Proposed remediation |
|---|---|
| Index target `UNREACHABLE` | Add `@AGENTS.md` as the first line of the root `CLAUDE.md`, or symlink `CLAUDE.md` → `AGENTS.md`. Show the exact line and its position |
| No index home | Name the file `render-index.sh write` would target, and offer to create the block |
| `git` absent | State the degradation; there is nothing to install on the consumer's behalf |
| `jq` or CLI absent | Name the tool and that only `verify-load.sh` is affected |

After an accepted change, re-run the reachability check and report the new verdict. An `apply` that
does not re-verify has not finished.

## Hard rules

- **Idempotent.** Re-running changes nothing that is already correct, and says so rather than
  reporting work it did not do.
- **`check` never writes.** Not settings, not `CLAUDE.md`, not the index.
- **Never install anything.** Name the tool and the reason; the operator's machine is theirs.
- **Never report a prerequisite verified without probing it.** An absent probe is `unknown`, and
  `unknown` is never reported as `ok`.
- **An optional prerequisite's absence is not a failure.** Only the index-target verdict can make
  this skill report a problem with the repository itself.

## Gotchas

- **`UNREACHABLE` is the finding people do not expect.** Everything else can be green while the
  index does nothing. Lead with it when it fires; it is the reason this skill exists.
- **A target that does not exist yet is not unreachable.** Those are different states with different
  remedies — do not collapse them into one verdict.
- **Reachability is not sync.** A reachable index can still be stale, and a stale index can still be
  reachable. `/instruction-placement:check` owns sync; this owns whether the file is read at all.
- **The plugin works with no configuration.** Every setting has a default that behaves. Do not
  present configuration as a prerequisite to a first audit.
