# audit-pass — deriving the exclusion set

The exclusion set is **computed from the target's own state on every run**. Nothing here transcribes
a path list or a count: a count written down is wrong on the next commit and wrong in every other
repository, and a transcribed list silently stops matching the registry that owns it.

Each class below is derived, reported in the report's `skipped` section with its reason, and — because
the inventory and the exclusion set are both derived-tier artifacts — subject to exact equality
across runs over an unchanged tree.

## Class 1 — registered byte-identical cluster copies

A cluster is a file deliberately carried byte-identical by several plugins, kept in sync by a
dedicated script. Editing one copy breaks the sync path; a fix-capable pass that edited one would
corrupt the cluster.

**Derivation.** Ask the target whether it documents a shared-source registry. In this marketplace
that is `scripts/cross-plugin-source-registry.txt`, whose entries are paths *within* each plugin;
resolve each entry against every plugin root to get the live copy set. When the target documents no
such registry, **this class is empty** — say so in `skipped` rather than inferring one from
similarity, which would exclude files nobody registered.

**Fallback when the registry is unreadable**: treat the class as unresolved, exclude nothing on this
basis, and report the class as a coverage gap. Silently excluding on a failed read would hide
surfaces; silently including would risk a corrupting edit — so the run reports and the operator
decides.

## Class 2 — vendored upstream materializations

A `vendor/` subtree holds upstream's own content, byte-frozen. A local edit there is a defect, not a
fix: it is overwritten by the next sync and it makes the local copy diverge from the upstream it
claims to mirror.

**Derivation.** Exclude any path with a `vendor/` path component under the inventoried roots. This is
a layout rule, not a list — no vendored file is ever named in this skill.

## Class 3 — worktrees

A linked worktree is a second checkout of the same repository. A filesystem walk that descends into
one double-counts every surface and can apply a fix in a checkout the operator is not looking at.

**Derivation.** `git worktree list` enumerates them; exclude every listed path other than the
resolved target root. Combine with gitignore-awareness (`git check-ignore`, or a git-tracked
enumeration such as `git ls-files`) so an ignored or untracked scratch tree is excluded for free.

A git-tracked enumeration is preferred over a raw walk precisely because it gets this class right
without being told about it.

## Class 4 — the pass's own artifacts

- **The suppression record** (`.claude/audit-pass.md` and its cascade layers). Excluded from the scan
  set: otherwise suppressing a finding changes the tree and perturbs the next run, which would make
  the idempotence property unfalsifiable.
- **A redirected report.** When a previous run used `--report-to <path>`, that path is in the scan
  set's exclusion list for every subsequent run, and the run states this in its output. Scanning your
  own previous report is the failure the rule exists to prevent.

## Suppression against an excluded path is a hard error

Not a warning, not a silent no-op.

An inline suppression marker inside a registered cluster copy would make that copy differ from its
siblings — the exact corruption class 1 exists to prevent, arriving through the suppression channel
instead of the fix channel. So:

**The run refuses the suppression, exits the apply step non-zero for that finding, and names the
canonical source** as the only place the suppression may be recorded. The same refusal applies to a
suppression targeting a `vendor/` path or a worktree path.

The permitted alternative is always available: record the suppression centrally, keyed by
`finding_id`, in the record the
[finding-suppression convention](../../../../../docs/conventions/finding-suppression/README.md)
owns. A central entry names the finding without touching the excluded file at all.

## Reporting

Every excluded surface appears in the report's `skipped` section with the class that excluded it and
the mechanism that derived it (`registry`, `vendor-rule`, `git worktree list`, `own-artifact`). A
silent exclusion reads as coverage; naming the mechanism also makes a wrong exclusion diagnosable
without re-running the pass.
