# Topic-docs placement — where this plugin's artifacts land

How `instruction-placement:audit`, `instruction-placement:realign`, and `instruction-placement:delta`
resolve where this plugin's artifacts live in a consuming repo. All three skills read this one
document; none bakes its own paths. `instruction-placement:check` reads no artifact at all — it
verifies the repository's state directly — and `instruction-placement:setup` writes none.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode. This document records only this plugin's
deltas.

The sibling `artifact-protocol.md` defines the shared lifecycle artifact names and producer/consumer
behavior; this binding and topic-docs remain authoritative for placement. What the artifacts
*contain* belongs to `context/findings-artifact.md`, which is authoritative for their shape and
never for their location.

## What this plugin writes

**Memory tier only.** Nothing downstream enforces against either artifact, and both are read again
by a later run in the same checkout, which is the memory tier's own question.

| Artifact | Type | Location (default) |
|---|---|---|
| Findings — written by `instruction-placement:audit`, status fields updated by `instruction-placement:realign` | `instruction-placement-findings` | `.work/instruction-placement/<branch-slug>/findings.md` — never committed |
| Placement baseline — read and captured by `instruction-placement:delta`, one per repository | `instruction-placement-baseline` | `.work/instruction-placement/baselines/placement-baseline.md` — never committed |

`baselines/` is the protocol's named slot for a comparison capture, and this is the plugin's use of
it. What the baseline contains — its frontmatter, its records, its declined set — is owned by
`context/findings-artifact.md` under "The baseline-capture obligation"; this binding owns only where
it lands.

**One stable filename per home, rewritten in place.** `findings.md`, never a timestamped sibling: a
re-audit merges into the existing file by stable finding id, and a per-run filename would turn that
merge into a search problem. The run's timestamp lives in the artifact's `date` frontmatter, where a
reader and a diff can both find it. `placement-baseline.md` is one stable filename for the same
reason, overwritten by the next capture. **A `placement-baseline.md` in a resolved home is not
stray**; deleting one destroys the delta lane's only baseline and, with it, the declined set.

## The two axes, and why they differ

**The findings artifact is branch-keyed.** Every finding cites a source file and a line range, and
`realign` excises by that range. A range derived on one branch points at different text on another,
so the artifact carries a `branch:` frontmatter field, `realign` refuses an artifact whose `branch:`
does not match the current branch, and the branch segment keeps two concurrent branches from
clobbering each other's evidence. The directory alone is never the proof — the frontmatter is.

**The baseline is not branch-keyed, and that is the point.** It carries the operator's declined
decisions, and a decline is a judgment about content rather than about a line number: an operator
who declined demoting a section on one branch has not agreed to be asked again from the next
checkout. So the baseline sits at one path per repository, resolved from the repo's own tracked
concern file and a constant slug, with **no branch segment and no checkout discriminator anywhere in
the formula**. Two runs of the same repository that resolve the same `memory_dir` resolve the same
baseline.

That is the whole reason this plugin's persistence moved off `lib/state-key.sh`. That key's second
segment is a `<worktree-discriminator>` — a hash of the checkout root, present by design so two
worktrees "must not share a report". Correct for a per-checkout report; wrong for an operator's
judgment, which is what the declined set is.

## Slug derivation

Delta from the contract's precedence: the slug is the constant `instruction-placement`, always.
Neither the explicit-argument rung nor the branch-name rung is used — this plugin audits a
repository's instruction layer, not a topic, and a topic- or branch-derived slug would fragment the
one declined set successive runs must respect. Form and collision rules are the contract's: a user
topic that derives this same slug takes the contract's `-x` suffix.

`<branch-slug>` — the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character
replaced by `-`. The mapping is lossy by design (`feature/foo` and `feature-foo` collide), which is
why the artifact's own `branch:` frontmatter, never its directory, proves which branch it describes.

**Neither `<branch-slug>/` nor `baselines/` is a child slice.** Both hold kebab-case auxiliary
ledgers and no reserved uppercase stage file, so the contract's child-slice predicate does not fire
and no `INDEX.md` is owed at either level.

**When no branch identity resolves, no findings home is keyed.** All three skills resolve the branch
with `git symbolic-ref --quiet --short HEAD`, which fails on a detached checkout rather than
answering the literal string `HEAD` the way `git rev-parse --abbrev-ref HEAD` does. Where that fails,
there is no `<branch-slug>` to compose: `audit` persists no artifact and `realign` refuses. The
baseline is unaffected — its path has no branch segment — so a detached scheduled run still reads the
declined set and still suppresses what the operator already dismissed.

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present → its `memory_dir`:
   `<memory_dir>/instruction-placement/`.
2. An artifact location declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it, and offer
   to persist it into the concern file (prose is an inference source, not the runtime authority).
3. An existing conforming layout inferred from the repo (a self-ignoring memory root already holding
   this plugin's findings) → confirm with the user, persist to the concern file.
4. Ask once — one question, recommended option first; persist the answer to the concern file.
5. The documented default: `.work/instruction-placement/`.

**Persisting at rungs 2–4 is ask-gated, never automatic.** Each of those rungs persists the
resolution to the concern file only on the user's explicit confirmation; declining is a valid answer
that leaves the resolution session-local, and the run proceeds either way. This is the one sanctioned
tracked write of any skill here, and each skill's read-only headline is scoped to unasked writes,
which all stay in the memory tier.

Only rungs 1 and 5 compose `instruction-placement/…` themselves. Rungs 2–4 yield whatever location
the consumer declared, inferred, or chose — **resolve the home, never assume its shape.** A skill
that hardcodes the default's shape writes where the other side never looks, and `realign`'s failure
mode for that is a missing-artifact stop indistinguishable from "the audit was never run".

**Non-interactive / forked mode.** Rungs 2–4 can require asking the user or persisting config. A
context that can do neither — a forked subagent, a dispatched worker, a scheduled or headless run —
follows the contract's "Non-interactive / forked mode" section, which is contract-owned and cited
here rather than redefined: skip the ask and persist rungs, take the resolved or documented default,
and surface the assumption in the returned summary.

**No project root.** The contract's fallback applies unchanged. Every skill here reads something
inside a checkout, so a run outside one has nothing to sweep and stops before any write.

## What the memory tier does and does not survive

Stated plainly, because the declined set's durability is the reason this home was chosen:

- **Survives** a re-run, a branch switch, a `realign` pass, and any later session in this checkout.
  The baseline has no branch segment, so a decline recorded on one branch is honored on every other.
- **Survives across checkouts exactly as far as the resolved `memory_dir` reaches.** A repository
  whose tracked `.claude/topic-docs.yaml` names a shared or absolute memory root shares one baseline
  across every checkout of that repository. On the documented default the root is `.work/` inside the
  checkout, so a *newly created* linked worktree starts without it unless the repository's
  `.worktreeinclude` carries the memory root in (one-way, at worktree-creation time, per the
  contract).
- **Does not survive** a deleted memory root or a reclaimed container. That is the memory tier's own
  bargain, and the next run then legitimately has no baseline and says so.

The state key this replaced could not reach even the first of those: its `<worktree-discriminator>`
segment made two checkouts of one repository resolve two different homes unconditionally, with no
consumer configuration able to join them.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory root**
  (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with `*`,
  creating it (announced) when absent. Once per session, per the contract. The contract also defines
  the **invalid roots at which the guard does not run**; they are enumerated in its
  [Runtime guards](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md)
  section and deliberately not listed here, so this binding cannot drift from them.
- Create the slice directory, and the `baselines/` subdirectory, when absent.
- No skill in this plugin ever edits the consumer's root `.gitignore`.
