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

**Memory tier only, and both artifacts are branch-keyed.** Nothing downstream enforces against
either, and both are read again by a later run in the same checkout, which is the memory tier's own
question.

| Artifact | Type | Location (default) |
|---|---|---|
| Findings — written by `instruction-placement:audit`, status fields updated by `instruction-placement:realign` | `instruction-placement-findings` | `.work/instruction-placement/<branch-slug>/findings.md` — never committed |
| Spine baseline — read and captured by `instruction-placement:delta` | `instruction-placement-baseline` | `.work/instruction-placement/<branch-slug>/baselines/spine-baseline.md` — never committed |

`baselines/` is the protocol's named slot for a comparison capture, and this is the plugin's use of
it. What the baseline contains — its frontmatter and its one spine table — is owned by
`context/findings-artifact.md` under "The baseline-capture obligation"; this binding owns only where
it lands.

**One stable filename per home, rewritten in place.** `findings.md`, never a timestamped sibling: a
re-audit merges into the existing file by stable finding id, and a per-run filename would turn that
merge into a search problem. The run's timestamp lives in the artifact's `date` frontmatter, where a
reader and a diff can both find it. `spine-baseline.md` is one stable filename for the same reason,
overwritten by the next capture. **A `spine-baseline.md` in a resolved home is not stray**; deleting
one leaves the delta lane with no comparison input and the next run reports a first run.

## What does not live here: the operator's judgment

Both files above are **checkout-local**. The contract's visibility matrix marks a sibling worktree
`invisible` for the memory tier, states that a memory document is visible only in the checkout that
wrote it, and explicitly refuses to carry this file class across with `.worktreeinclude` — "never
baselines or raw scratch". Nothing configured here changes that.

So a declined finding is **not** stored in either. It is written to the tracked finding-suppression
surface `.claude/instruction-placement.md`
([`consumer-config.md`](consumer-config.md)), where git carries it to every checkout whose branch
holds the commit. That is the mechanism, and it is the only one available: a tracked file crosses
checkouts because git moves it, and a memory-tier file does not because nothing does.

The split is the point. A spine is recomputed by the next run and is worthless outside the checkout
that produced it; a judgment is expensive to reproduce and worthless *inside* only one checkout.
This is the same split the sibling `overengineering` plugin makes, which keeps a branch-keyed spine
baseline in the memory tier and its suppressions on its own tracked surface.

**Both artifacts are branch-keyed, for the same reason.** Every finding cites a source file and a
line range, and `realign` excises by that range; a range derived on one branch points at different
text on another. The artifact carries a `branch:` frontmatter field and `realign` refuses one whose
`branch:` does not match; the baseline carries the same field and `delta` refuses a spine from
another branch rather than reporting the difference between two branches as movement. The directory
alone is never the proof — the frontmatter is.

That is also why the retired `lib/state-key.sh` had to go rather than be re-scoped. Its second
segment was a `<worktree-discriminator>`, a hash of the checkout root, present by design so two
worktrees "must not share a report". Correct for a per-checkout report — which is exactly what these
two files are — but it made the plugin's *judgments* per-checkout too, and no configuration could
join them. The judgments now live on a surface where that question does not arise.

## Slug derivation

Delta from the contract's precedence: the slug is the constant `instruction-placement`, always.
Neither the explicit-argument rung nor the branch-name rung is used at the slug level — this plugin
audits a repository's instruction layer, not a topic, and a topic-derived slug would scatter one
repository's homes across as many slices as an operator has phrasings. The branch axis is the
segment *below* the slug, where it belongs. Form and collision rules are the contract's: a user
topic that derives this same slug takes the contract's `-x` suffix.

`<branch-slug>` — the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character
replaced by `-`. The mapping is lossy by design (`feature/foo` and `feature-foo` collide), which is
why the artifact's own `branch:` frontmatter, never its directory, proves which branch it describes.

**Neither `<branch-slug>/` nor `baselines/` is a child slice.** Both hold kebab-case auxiliary
ledgers and no reserved uppercase stage file, so the contract's child-slice predicate does not fire
and neither level owes an `INDEX.md` of its own.

**The slice root does carry one**, because it is not a single-artifact leaf: it holds two artifact
families — findings and the baselines slot — across one home per branch, and the contract requires
`INDEX.md` in "a slice with child slices, or with more than one artifact family". It is created by
the same skill at the same moment as the self-ignore guard below — the session's first memory-tier
write — and lists the families and the branch homes, so a consumer entering the slice reads it
first, per the contract's normative read-first binding, cited here and not restated.

**Where the branch comes from, and what a detached checkout means.** The branch is the
`- Branch:` line of each skill's pre-compute block, which runs
`git rev-parse --abbrev-ref HEAD`. That command answers the **literal string `HEAD`** on a detached
checkout rather than failing, so `HEAD` is not a branch identity here: it is the same string for
every ref, and keying a home to it would collide every detached run into one directory — which is
the common case, since scheduled runners check out detached. Treat a branch of `HEAD`, or an empty
one, as **no branch identity**: no home is keyed, `audit` persists no artifact, `delta` captures no
baseline, and `realign` refuses rather than comparing. A detached run is not silenced, though —
suppressions live on the tracked surface, whose path has no branch in it, so a scheduled detached
run still reads the declined set and still suppresses what the operator already dismissed.

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present → its `memory_dir`:
   `<memory_dir>/instruction-placement/<branch-slug>/`.
2. An artifact location declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it, and offer
   to persist it into the concern file (prose is an inference source, not the runtime authority).
3. An existing conforming layout inferred from the repo (a self-ignoring memory root already holding
   this plugin's findings) → confirm with the user, persist to the concern file.
4. Ask once — one question, recommended option first; persist the answer to the concern file.
5. The documented default: `.work/instruction-placement/<branch-slug>/`.

**Every rung ends at a branch home, including the ones a consumer supplies.** Rungs 2–4 yield a
root; the branch segment is appended to it, and the spine baseline then sits at
`<that home>/baselines/spine-baseline.md`. A rung that stopped at the slice root would put two
branches' spines in one file: the alternating runs would each report the other branch's sections as
`changed`, its rules as `broken-glob`, and its deleted content as `stale`, then overwrite the
snapshot the other one needs — a delta lane reporting branch differences as movement, with no error
to show for it. **A run with no branch identity resolves no home at all**, per the branch section
above; it does not fall back to the slice root.

**Persisting at rungs 2–4 is ask-gated, never automatic.** Each of those rungs persists the
resolution to the concern file only on the user's explicit confirmation; declining is a valid answer
that leaves the resolution session-local, and the run proceeds either way. Each skill's read-only
headline is scoped to unasked writes, which all stay in the memory tier. This plugin has exactly two
sanctioned tracked writes, both gated on an explicit yes: this resolution, and the suppression entry
`instruction-placement:realign` offers when an operator declines a finding
([`consumer-config.md`](consumer-config.md)).

Only rungs 1 and 5 compose the `instruction-placement/` slug themselves. Rungs 2–4 yield whatever
root the consumer declared, inferred, or chose, and take the branch segment below it —
**resolve the home, never assume its shape.** A skill
that hardcodes the default's shape writes where the other side never looks, and `realign`'s failure
mode for that is a missing-artifact stop indistinguishable from "the audit was never run".

**Non-interactive / forked mode.** Rungs 2–4 can require asking the user or persisting config. A
context that can do neither — a forked subagent, a dispatched worker, a scheduled or headless run —
follows the contract's "Non-interactive / forked mode" section, which is contract-owned and cited
here rather than redefined: skip the ask and persist rungs, take the resolved or documented default,
and surface the assumption in the returned summary.

**No project root.** The contract's fallback applies unchanged. Every skill here reads something
inside a checkout, so a run outside one has nothing to sweep and stops before any write.

## What survives what

Stated plainly, per file, because getting this wrong is what routes a durable judgment into a
disposable home:

| Event | `findings.md` | `baselines/spine-baseline.md` | `.claude/instruction-placement.md` |
|---|---|---|---|
| A re-run in this checkout | kept, merged | overwritten by the capture | kept |
| A branch switch in this checkout | separate home per branch | separate home per branch | kept — no branch in its path |
| Another worktree of this repository | invisible | invisible | **visible once the branch carries the commit** |
| A deleted memory root, a reclaimed container | lost | lost | kept — it is tracked, not memory tier |
| A fresh clone | absent | absent | **present** |

The third and fifth rows are the whole reason the suppression surface exists. Git is the mechanism:
a tracked file reaches another checkout because git moves it, and no `memory_dir` setting makes a
memory-tier file do the same — the contract refuses to carry this class with `.worktreeinclude`
("never baselines or raw scratch"), and marks a sibling worktree `invisible`.

The retired state key reached none of those rows for either kind of state: its
`<worktree-discriminator>` segment made two checkouts of one repository resolve two different homes
unconditionally, with no consumer configuration able to join them.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory root**
  (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with `*`,
  creating it (announced) when absent. Once per session, per the contract. The contract also defines
  the **invalid roots at which the guard does not run**; they are enumerated in its
  [Runtime guards](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md)
  section and deliberately not listed here, so this binding cannot drift from them.
- Create the slice directory, its `INDEX.md`, the branch home, and its `baselines/` subdirectory when
  absent — at the same first memory-tier write the guard above is scoped to.
- No skill in this plugin ever edits the consumer's root `.gitignore`. The suppression surface's
  overlay layer is covered by the cascade's own one recursive line, per
  [`consumer-config.md`](consumer-config.md).
