# Topic-docs placement: where this plugin's artifacts land

How `instruction-placement:audit`, `instruction-placement:realign`, and `instruction-placement:delta`
resolve where this plugin's artifacts live in a consuming repo. All three skills read this one
document; none bakes its own paths. `instruction-placement:check` and `instruction-placement:setup`
place no artifact and resolve nothing here.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule: tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive and forked mode. This document records only this plugin's
deltas.

The sibling `artifact-protocol.md` defines the shared lifecycle artifact names and producer/consumer
behavior; this binding and topic-docs remain authoritative for placement. What the artifacts
*contain* belongs to `context/findings-artifact.md`, which is authoritative for their shape and never
for their location.

## What this plugin writes

**Memory tier only, concern-scoped.** A placement audit's axis is the **branch**, not a topic: the
surface it sweeps is whatever this checkout currently loads. So the artifacts sit under the memory
root's `instruction-placement/` concern name rather than inside a topic slice, exactly as
branch-keyed review reports and the sibling `overengineering` findings do.

| Artifact | Type | Location (default) |
|---|---|---|
| Audit findings, written by `instruction-placement:audit`, status fields updated by `instruction-placement:realign` | `instruction-placement-findings` | `.work/instruction-placement/<branch-slug>/findings.md`, never committed |
| Delta baseline, captured by `instruction-placement:delta` at the end of a cycle for the next one to compare against | `instruction-placement-delta-baseline` | `.work/instruction-placement/<branch-slug>/baselines/delta-baseline.md`, never committed |

`baselines/` is the protocol's named memory-tier slot for a cross-run comparison capture, the same
slot `verification` writes its measurements into. One stable path inside it,
`baselines/delta-baseline.md`, because this lane compares against the previous cycle and never
against a history.

What the baseline contains, its frontmatter, its body rules, and its type are owned by
`context/findings-artifact.md` under "The delta baseline"; this binding owns only where it lands.
**The two paths above are the only ones any skill in this plugin resolves for these artifacts.** A
skill that writes the baseline into the home root beside `findings.md`, or reads it from there, finds
nothing and bootstraps from the artifact on every cycle, which collapses the comparison back into
diffing the live artifact, the failure this baseline exists to replace, and produces no error
message. `scripts/artifact-home.test.sh` pins both paths against every shipped surface for that
reason.

Both artifacts are memory tier, and they are the only artifacts this plugin **places** anywhere. It
produces no contract-tier artifact: a placement report is process output that nothing downstream
enforces against, and the one thing that outlives the branch, an applied move, is reconstructable
from the repository's own git history.

**One stable filename per home, rewritten in place.** `findings.md`, never a timestamped sibling: a
re-audit merges into the existing file by stable finding id, and a per-run filename would turn that
merge into a search problem. The run's timestamp lives in the artifact's `date` frontmatter, where a
reader and a diff can both find it. `baselines/delta-baseline.md` is one stable path for the same
reason, overwritten by the next capture, with one exception owned by the capture rules: an
unconsumed baseline is kept rather than overwritten. **A `baselines/delta-baseline.md` in a resolved
home is not stray**;
deleting one destroys the delta lane's only baseline and the declined records it carries.

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present, use its `memory_dir`:
   `<memory_dir>/instruction-placement/<branch-slug>/`.
2. A working-docs location declared in the consumer's `CLAUDE.md` or `.claude/rules`, use it, and
   offer to persist it into the concern file (prose is an inference source, not the runtime
   authority).
3. An existing conforming layout inferred from the repo (a self-ignoring memory root already holding
   this plugin's findings), confirm with the user, persist to the concern file.
4. Ask once: one question, recommended option first; persist the answer to the concern file.
5. The documented default: `.work/instruction-placement/<branch-slug>/`.

**Persisting at rungs 2 to 4 is ask-gated, never automatic.** Each of those rungs persists the
resolution to the concern file only on the user's explicit confirmation; declining is a valid answer
that leaves the resolution session-local, and the run proceeds either way. This is the one sanctioned
tracked write of the audit skill, whose read-only headline is scoped to unasked writes; every unasked
write it makes stays in the memory tier.

Only rungs 1 and 5 compose `instruction-placement/<branch-slug>` themselves. Rungs 2 to 4 yield
whatever location the consumer declared, inferred, or chose. **Resolve the home, never assume its
shape.** A skill that hardcodes the default's shape writes where the other side never looks, and
realign's failure mode for that is a missing-artifact stop indistinguishable from "the audit was
never run".

**Non-interactive and forked mode.** Rungs 2 to 4 can require asking the user or persisting config. A
context that can do neither, a forked subagent, a dispatched worker, a scheduled or headless run,
follows the contract's "Non-interactive / forked mode" section, which is contract-owned and cited
here rather than redefined: skip the ask and persist rungs, take the resolved or documented default,
and surface the assumption in the returned summary. The delta lane runs on a cadence, so this is its
ordinary path rather than an edge case.

**No project root.** The contract's fallback applies unchanged. Every skill here reads something
inside a checkout, so a run outside one has nothing to sweep and stops before any write.

## Branch slug

`<branch-slug>`: the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character
replaced by `-`. This is the branch axis, deliberately distinct from the convention's topic-slug form.

The mapping is **lossy by design** (`feature/foo` and `feature-foo` collide), so what proves an
artifact belongs to a branch is its own `branch:` frontmatter, never the directory it sits in.
Realign refuses an artifact whose `branch:` does not match the current branch, naming the mismatch;
the directory alone is not evidence. The same rule binds the baseline.

**When no branch identity resolves, no home is keyed and nothing is written.** All three skills
resolve the branch with `git symbolic-ref --quiet --short HEAD`, which fails on a detached checkout
rather than answering the literal string `HEAD` the way `git rev-parse --abbrev-ref HEAD` does. Where
that fails and the environment supplies no logical ref naming a branch, there is no `<branch-slug>`
to compose, and **the rung order is not run**: every rung composes a path for an axis that has no
value.

No substitute is admitted. `HEAD` is the same string for every ref, so it would key every detached
run to one directory, precisely the collision this segment exists to prevent, and worst in the runs a
scheduled runner produces most often. The commit sha keys a new home every commit, which never
collides but never resumes either. A fixed literal such as `detached` is `HEAD` under another name.

The consumers state the consequence at their own sites: `instruction-placement:audit` persists no
findings artifact, `instruction-placement:realign` refuses rather than editing, and
`instruction-placement:delta` compares nothing and captures no baseline.

`instruction-placement` is this plugin's concern name under the memory root, alongside the contract's
other reserved first-level names. A topic slug that collides with it takes the contract's `-x` suffix.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory root**
  (whatever `memory_dir` names, never a hardcoded `.work`) contains a `.gitignore` with `*`, creating
  it (announced) when absent. Once per session, per the contract. The contract also defines the
  **invalid roots at which the guard does not run**; they are enumerated in its
  [Runtime guards](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md)
  section and deliberately not listed here, so this binding cannot drift from them.
- **Partial writes are valid.** The audit may write findings as it ranks them, so an interrupted run
  leaves a checkpoint at this path rather than nothing. The guard runs once regardless: it is scoped
  to the session's first memory-tier write, not to each finding's.
- No skill in this plugin ever edits the consumer's root `.gitignore`. The rules index this plugin
  regenerates is a tracked file and a separate concern, gated per item by realign.

## Retired: the plugin-data state key

Before 0.12.0 both artifacts lived at
`${CLAUDE_PLUGIN_DATA}/findings/<state-key>/<branch-slug>/findings.md`, keyed by `lib/state-key.sh`.
That key ends in a **hash of the worktree's absolute root path**, so a second checkout of the same
repository on the same branch was a different home by construction, and every operator decision
recorded in one checkout was invisible from the other. Nothing in this plugin resolves that path any
more, and `lib/state-key.sh` no longer ships here.

**What the move buys, stated exactly, because the neighbouring claim is easy to overstate.** The home
no longer varies with *where* a checkout sits on disk: it varies with the branch and with the memory
root the consumer configures. Two checkouts that resolve the same `memory_dir` on the same branch
therefore share one home, which the worktree hash made impossible by construction. Under the
documented default the memory root is inside the checkout, so two checkouts still hold two homes; the
difference is that a declined decision now lives in one named file an operator can copy, rather than
behind a hash nobody can reproduce. Cross-checkout durability for an operator judgment, in the shape
the sibling `overengineering` plugin gives it, is a tracked suppression surface this plugin does not
yet ship, and it is recorded as a revisit trigger in the plugin README rather than implied here.

**A leftover tree under the old path is inert, not read.** No skill consults it, deliberately: a
read-side fallback would keep the state-key derivation alive as the parallel second way this move
exists to close. A delta run that finds no artifact names the resolved home it looked in, may name
this retired tree as the likely cause, and routes to a full audit; one that finds the artifact and
no baseline bootstraps the baseline from it and says so. Either way the absence is reported rather
than silently treated as a first run. Delete the old tree at leisure; nothing depends on it.
