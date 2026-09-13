# Arguments

Full semantics for every `audit-pass` argument, the precedence between them, and what `--fix` and
`--resume` change about the phases in [`../SKILL.md`](../SKILL.md). The hub carries the flag names
and their one-line meanings; this file carries the reasoning each refusal and default rests on.

Parse `$ARGUMENTS`:

- **`target`**: the git repository to audit. Default: the project root Claude Code resolved for this
  session; where no such root is available, `git rev-parse --show-toplevel`. Never the working
  directory, since a run launched from a subdirectory must key and scan identically to one launched from
  the root.

  **Do not express this as a condition over `${CLAUDE_PROJECT_DIR}` "when set".** That placeholder is
  substituted inline in skill content before this file reaches you, so the literal token is never
  visible and the test is not yours to make. You would be deciding "is it set?" about a value that
  has already been resolved. Work from what you can observe: the resolved path, or a command you run.
  The sibling `audit-prompting-postures` states this same rule where it derives its report path.

  **`target` must resolve to the active project root, and a path that does not is refused.** The
  delegated interfaces accept no target: `audit-instructions` takes a surface scope and inventories
  the active project, and `claude-memory:audit` takes an action verb. This pass dispatches skills and
  never reads inside one, so there is no channel through which it could tell a delegate to look
  elsewhere. A run given `../other-repo` would key, lock, and report against that path while every
  delegated finding came from the active project. Findings attributed to the wrong repository are
  worse than a refusal, because nothing downstream can detect the mismatch.

  So the argument is validated rather than silently reinterpreted: a `target` that does not resolve
  to the active project root exits non-zero, naming both paths and the reason. Auditing another
  repository means opening it as the project. Lifting the restriction is a change to the
  **delegated** interfaces, each of which would have to accept and honor a target root, and belongs to
  those skills rather than this one. The argument itself survives because the state key, the lock,
  and the report are already keyed on the resolved root.

  **The gate enforces both halves of that first sentence: the active project root, *and* a git
  repository.** A `target` that is not inside a git repository is refused the same way: non-zero,
  before Phase 0 does any work, naming the path and the reason, writing nothing.

  **Name the directory, not an empty string.** In the case this refusal is *for*, the default
  resolution above produces nothing: with no explicit `target` and no session-resolved project root,
  `git rev-parse --show-toplevel` fails outside a repository and there is no resolved root to report.
  So for the diagnostic only, fall back to the current directory and name **that**. A refusal that
  cannot say which path it refused is barely better than a silent one. The fallback is for the message;
  it never becomes a target.
  A non-git directory has no branch in this contract, and a run over one goes quiet in four places
  rather than one:

  - the scan baseline is *the target's HEAD commit and the run's state digest*, and HEAD does not
    exist;
  - Class 3 exclusion derives worktrees from `git worktree list`, and unlike Class 1 it is given no
    fallback;
  - assertion 2.1 is stated over `git status --porcelain`, so the top read-only assertion is
    unevaluable;
  - and, the one that is a permanent capability loss rather than a missing derivation, **only the
    team layer enacts a suppression**, and the team layer is the *tracked* layer. With nothing
    tracked, no suppression is ever enactable on such a target, so an operator could accept a finding
    and have the acceptance silently fail to persist, forever.

  **The refusal says that cost out loud** rather than reading as an arbitrary restriction, and it names
  the suppression consequence in particular. Refusing closes a target class deliberately; it is not a
  side effect. Specifying all four branches is not an alternative: the last of them obliges the
  contract to promise a capability it can never deliver on that class.
  A non-git directory is audited by opening it as a repository, or by the delegated skills directly.
- **`--fix`**: the explicit mutation override. Absent, the pass writes nothing into the target.
- **`--opinion`**: run the `OPINION`-tier checks the delegated catalogs declare default-off.
- **`--resume`**: resume the most recent incomplete run for this target's state key.
- **`--lanes <list>`**: run only the named lanes, comma-separated, with the lane ids the dispatch
  list in [`../SKILL.md`](../SKILL.md) assigns. Full semantics below.
- **`--postures`**: dispatch the opt-in posture lane. Full semantics below.
- **`--report-to <dir>`**: redirect **both** report artifacts into that directory. It takes a
  directory, not a file path, because a run writes two artifacts and a file path names one of them;
  the reasoning is in [report-location-and-schema.md](report-location-and-schema.md) §2, which also
  carries the destination gate. Each resolved path inside the directory is accepted only if it is an
  `audit-pass`-owned artifact or does not exist, and neither may be a recognized instruction
  surface; anything else is refused non-zero, naming the file. Refused on name rather than on
  existence, because a destination inside a directory Claude loads from would *create* a live
  instruction surface out of a report and then hide it from every later scan.

  **The self-exclusion obligation is not this flag's.** It belongs to the predicate
  `report_path ⊆ target_root`, evaluated over **each** resolved artifact path: **any** run whose
  resolved report paths are contained in the target adds them to its own exclusion set before
  writing, not only for later runs, since otherwise the two runs' derived sets could not be equal,
  and says so in its output. `--report-to` is one way containment arises. The
  **default** location is another, because `${CLAUDE_PLUGIN_DATA}` resolves under `~` and is inside any
  target at or above it. Full statement in
  [report-location-and-schema.md](report-location-and-schema.md) §2 and
  [exclusion-set.md](exclusion-set.md) Class 4.

## `--lanes <list>`

**What it narrows is dispatch, never the inventory.** Phase 1 inventories all three scopes on every
run, `--lanes` included. A flag that narrowed the inventory would reintroduce the half-picture the
inventory-before-checks ordering exists to prevent, and the inventory is cheap next to a lane.

- The value is a comma-separated list of lane ids. An id the dispatch list does not assign is
  **refused non-zero, naming the unknown id and listing the ids this run would accept**, rather than
  silently running a smaller set: a typo that quietly drops a lane produces a report that reads clean
  because nothing looked.
- A lane not selected appears in `skipped` with the reason `not selected by --lanes`, on the same
  terms as an absent plugin. The `skipped` section is what keeps "clean" and "not read" apart, and a
  deliberately narrowed run is exactly the case where the two are easiest to confuse.
- **A narrowed run cannot satisfy the determinism gate against a full run.** `--lanes` is a
  behavior-affecting argument, so the two runs are non-comparable and P1-P3 report as not evaluated
  naming it. Two runs naming the same lane set stay comparable with each other, which is what makes
  the flag useful for iterating on one lane. The report header marks a narrowed run
  **partial-scope**. Stated in
  [determinism-tiers.md](determinism-tiers.md) §6 alongside the other comparability inputs.
- It composes with `--resume`: the resumed invocation's argument set enters every lane's input
  digest, so resuming with a different `--lanes` re-runs the affected lanes rather than blending two
  scopes into one report.

## `--postures`

**Opt-in, and off by default for a cost reason rather than a quality one.**
`claude-config:audit-prompting-postures` is the additive lane: it proposes posture text a component
does **not** carry, so its output is a set of proposals rather than defects, and it fans its catalog
out over every instruction component in the target. Default-on would make the commonest invocation
pay for the largest fan-out in the pass to produce the section an operator is least likely to act on
in the same sitting. Default-off with an explicit flag puts that choice where the operator can price
it, which is the same reason `--opinion` exists.

**The flag also settles a live cross-plugin contradiction.** That skill's own body states that the
coordinated pass composes it. This pass names it once, where it derives its report path, and never in
its dispatch list, so the composition it claims had no invocation behind it. The lane is what makes
the claim true.

Its findings are judged tier, like every other delegated catalog's.

## `--paths`: specified as not shipped

**A path-narrowing argument is deliberately absent, and this section is why, so the absence reads as
a decision rather than an oversight.** The delegated interfaces state that a scope *filters findings
and never narrows reads*, and that their own first phase inventories the full comparison set
regardless. A `--paths` matching that behavior would save nothing at all: every shard would pay the
full inventory, and a sharded pass would multiply that cost by the shard count.

Three questions bind it, and it ships when they are answered, not before:

1. **Does `--paths` narrow reads, or only findings?** Read-narrowing is the only version that saves
   anything. It is a deliberate exception to the delegates' filter rule, and it is safe only while
   the whole-repository conflict lane stays unsharded, since a conflict pair spanning two shards is
   invisible to both.
2. **What replaces the claim that a per-run dispatch ceiling "would never bind"?** It is false once a
   pass shards, and the delegated catalogs' own confirmation gate on a large dispatch count would
   fire on every sharded run. Both the sentence and the gate's interaction with sharding need
   restating before a shard count can be chosen.
3. **What does a sharded run claim?** The same non-comparability `--lanes` carries, stated over paths
   rather than lanes.

**The measured cost of a full run does not point at sharding anyway.** What a full pass loses is not
the files it leaves unread; it is the whole check families that decline for lack of a deterministic
seed. If per-shard cost does not fall with shard size, the remedy is a cheaper seeded pre-scan, and
sharding would buy nothing while adding a scope no property can compare.
