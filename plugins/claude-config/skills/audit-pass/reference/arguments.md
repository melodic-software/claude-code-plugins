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
  The sibling `audit-prompting-postures` states this same rule where it derives its report path, and
  the two skills contradicted each other on it until this was fixed.

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
  Requiring only "the active project root" let a non-git directory through into a contract with no
  branch for it, and the run then went quiet in four places rather than one:

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
  side effect. The alternative, specifying all four branches, was considered and rejected, because
  the last of them obliges the contract to promise a capability it can never deliver on that class.
  A non-git directory is audited by opening it as a repository, or by the delegated skills directly.
- **`--fix`**: the explicit mutation override. Absent, the pass writes nothing into the target.
- **`--opinion`**: run the `OPINION`-tier checks the delegated catalogs declare default-off.
- **`--resume`**: resume the most recent incomplete run for this target's state key.
- **`--report-to <path>`**: redirect the report into the target tree. The destination is accepted only
  if it is an `audit-pass`-owned report or a new path that is **not a recognized instruction surface**;
  anything else is refused non-zero, naming the file. Refused on name rather than on existence,
  because `--report-to CLAUDE.md` against a repo that has none would *create* a live instruction
  surface out of a JSON report and then hide it from every later scan.

  **The self-exclusion obligation is not this flag's.** It belongs to the predicate
  `report_path ⊆ target_root`: **any** run whose resolved report path is contained in the target adds
  that path to its own exclusion set before writing, not only for later runs, since otherwise the two
  runs' derived sets could not be equal, and says so in its output. `--report-to` is one way containment arises. The
  **default** path is another, because `${CLAUDE_PLUGIN_DATA}` resolves under `~` and is inside any
  target at or above it. Full statement in
  [reference/report-location-and-schema.md](report-location-and-schema.md) §2 and
  [reference/exclusion-set.md](exclusion-set.md) Class 4.
