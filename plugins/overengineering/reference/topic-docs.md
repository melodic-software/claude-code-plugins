# Topic-docs placement — where the findings artifact lands

How `overengineering:audit` and `overengineering:realign` resolve where this plugin's findings
artifact lives in a consuming repo. Both skills read this one document; neither bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode. This document records only this plugin's
deltas.

The sibling `artifact-protocol.md` defines the shared lifecycle artifact names and producer/consumer
behavior; this binding and topic-docs remain authoritative for placement. What the artifact *contains*
belongs to `context/findings-artifact.md`, which is authoritative for its shape and never for its
location.

## What this plugin writes

**Memory tier only, concern-scoped.** An audit's axis is the **branch**, not a topic — the surface it
walks is whatever this checkout currently enforces — so the artifact sits under the memory root's
`overengineering/` concern name rather than inside a topic slice, exactly as branch-keyed review
reports do:

| Artifact | Type | Location (default) |
|---|---|---|
| Audit findings — written by `overengineering:audit`, status fields updated by `overengineering:realign` | `overengineering-findings` | `.work/overengineering/<branch-slug>/findings.md` — never committed |

Nothing else is written. The plugin produces no contract-tier artifact: an audit report is process
output that nothing downstream enforces against, and the one thing that must outlive the branch — an
operator's judgment — is persisted instead as a tracked suppression entry in
`.claude/overengineering.md`, whose keys and layering are owned by `reference/consumer-config.md`.

**One stable filename per home, rewritten in place.** `findings.md`, never a timestamped sibling: a
re-audit merges into the existing file by stable finding id, and a per-run filename would turn that
merge into a search problem. The run's timestamp lives in the artifact's `date` frontmatter, where a
reader and a diff can both find it.

The artifact is therefore lane-local and **ephemeral by design** — a branch switch, a removed
worktree, or a reclaimed container loses it. That is acceptable for evidence and verdicts, which are
recomputed on every run, and is exactly why operator judgments are not kept here.

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present → its `memory_dir`: `<memory_dir>/overengineering/<branch-slug>/`.
2. An audit-artifacts location declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it, and
   offer to persist it into the concern file (prose is an inference source, not the runtime
   authority).
3. An existing conforming layout inferred from the repo (a self-ignoring memory root already holding
   this plugin's findings) → confirm with the user, persist to the concern file.
4. Ask once — one question, recommended option first; persist the answer to the concern file.
5. The documented default: `.work/overengineering/<branch-slug>/`.

Only rungs 1 and 5 compose `overengineering/<branch-slug>` themselves. Rungs 2–4 yield whatever
location the consumer declared, inferred, or chose — **resolve the home, never assume its shape.** A
skill that hardcodes the default's shape writes where the other side never looks, and realign's
failure mode for that is a missing-artifact stop indistinguishable from "the audit was never run".

**Non-interactive / forked mode.** Rungs 2–4 can require asking the user or persisting config. A
context that can do neither — a forked subagent, a dispatched worker, a scheduled or headless run —
follows the contract's "Non-interactive / forked mode" section, which is contract-owned and cited
here rather than redefined: skip the ask and persist rungs, take the resolved or documented default,
and surface the assumption in the returned summary.

**No project root.** The contract's fallback applies unchanged. Both skills read the repository's own
enforcement surface, so a run outside a checkout has nothing to audit and stops before any write.

## Branch slug

`<branch-slug>` — the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character
replaced by `-`. This is the branch axis, deliberately distinct from the convention's topic-slug form.

The mapping is **lossy by design** (`feature/foo` and `feature-foo` collide), so what proves an
artifact belongs to a branch is its own `branch:` frontmatter, never the directory it sits in.
Realign refuses an artifact whose `branch:` does not match the current branch, naming the mismatch —
the directory alone is not evidence.

`overengineering` is this plugin's concern name under the memory root, alongside the contract's own
reserved first-level names. A topic slug that collides with it takes the contract's `-x` suffix.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory root**
  (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with `*`,
  creating it (announced) when absent. Once per session, per the contract. The contract also defines
  the **invalid roots at which the guard does not run**; they are enumerated in its
  [Runtime guards](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md)
  section and deliberately not listed here, so this binding cannot drift from them.
- **Partial writes are valid.** The audit may write per layer as it walks, so an interrupted run
  leaves a checkpoint at this path rather than nothing. The guard runs once regardless — it is scoped
  to the session's first memory-tier write, not to each layer's.
- No skill in this plugin ever edits the consumer's root `.gitignore`.
