# `check` (read-only)

The probe set behind the `check` action of [`../SKILL.md`](../SKILL.md), in the order it runs.
`apply` runs the same probes before it writes anything, and consumes these results rather than
re-deriving them.

Probe the binding, the schedule config, and the seam's entry gates, and report a PASS/FAIL/INFO table
with one remediation line per FAIL. Modify nothing, and do NOT bind, file items, or run a recurring
check.

1. **`jq` entry gate**, the authoritative check is
   [`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
   "entry-point presence checks"; probe it (`command -v jq`), don't restate it. Absent is FAIL with that
   reference's install remediation, the schedule snippets parse with `jq` unconditionally.
2. **Tracker provider binding**, resolve `BINDING` (above). Absent → INFO: the tracker seam is not
   bound, so every seam verb hard-errors (exit 3) until `apply` seeds it, and the role remap has nothing
   to configure; the remediation is `/work-items:setup apply`. Present → validate without mutating: it
   parses as JSON, carries `schema_version` and a `provider`, and that provider resolves to a bundled
   adapter (`github`, `local-markdown`, `jira`, `gitea`, `linear`) or a consumer-local one at
   `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/adapters/<provider>/`; `config.lease_ttl_hours` is
   present, `local-markdown` additionally carries `config.storage_dir`, and `jira` additionally carries
   `config.jira` (`site`, non-empty `project_keys[]`, `auth_email`, `auth_env`). A malformed shape, an
   unknown/unresolvable provider, or a missing required config key is FAIL, naming what is wrong.
   The ignore rule is required whether or not the overlay file exists. A present overlay
   (`.work-item-tracker.local.json`) must parse as JSON, carry only allowlisted keys
   (CONTRACT.md "Setup (binding file)"), and be gitignored, never tracked. Otherwise FAIL.
   Ignored and untracked are **two independent probes**: run the same pair `apply` step 5 uses, per
   [`reference/overlay-ignore-probes.md`](overlay-ignore-probes.md). A bare
   `git check-ignore` is silent for an already-tracked overlay. Tracked is the more serious FAIL;
   name it as such when both hold.
   A `github` binding must additionally be **addressable from this checkout**, because everything
   above is shape and owner/repo are never recorded in the binding, every repo-scoped verb derives
   them here (`gh repo view --json owner,name`, per the tracker CONTRACT's "Setup (binding file)"),
   so a shape-valid `github` binding in a non-GitHub checkout would otherwise PASS every probe and
   surface only when a verb fails at call time. Probe that same call **unconditionally**, never
   behind a `gh auth status` precheck, which tests every account on every known host and exits 1 if
   any has an issue (`gh auth status --help`), so an unrelated stale credential would skip the probe
   and let the very binding this exists to catch go unreported. Verdict on *why* the call failed
   rather than on failure alone:
   - Resolves → INFO naming the `owner/repo` the seam will address.
   - No remote, or no remote pointing at a known GitHub host → FAIL: nothing here can derive a repo,
     so every repo-scoped verb that is not handed the CONTRACT's explicit `--repo <owner>/<repo>`
     override fails at call time. Remediation is `/work-items:setup apply` with a user present,
     since re-choosing a provider needs a decision.
   - `gh` not installed or not authenticated, a 401/403, a not-found, a rate limit, or a network
     failure → INFO, never FAIL. Those are availability and credential facts, not verdicts on the
     binding. Unauthenticated is one of them and not a gate: the call fails that way even against a
     public repository, so it says nothing about where this checkout is hosted. A not-found
     belongs here and not above: an under-scoped token on a private repository returns exactly what
     a deleted one does, and condemning a correct binding is the worse error. Say in the INFO which
     it could be.
   - Any other failure → INFO, naming the message verbatim. The partition above is not provably
     total. `gh` owns these messages and adds to them, so an unrecognized one must never reach
     FAIL by default and stop `apply` on a repository that is bound correctly.
3. **Schedule presence**. Resolve `SCHEDULE` (above). Absent → INFO: `due` / `recheck` / `work`
   degrade to "no recurring schedule configured"; `apply` seeds it. Present → continue.
4. **Schedule validity**, a present file parses as JSON with the root `{"items": [ ... ]}` shape
   (FAIL otherwise), and **both reconciliation keys are unique across the whole `items` array, every
   `id` AND every `title`**. A duplicate `id` (the key `recheck <id>` resolves against) or duplicate
   `title` (the key `due` / `work` match `[Maintenance] {title}` against) silently breaks
   reconciliation, FAIL, naming the collision. A valid file whose `items` array is empty is the
   skipped first-time bind's skeleton, INFO: the schedule carries no rows, so `due` / `recheck` /
   `work` have nothing to act on; `apply --seed-schedule` seeds it. (Report this only once the root
   shape validates, probe 3 establishes file presence alone and cannot tell empty from malformed.)
5. **Tracked, not ignored**, a present schedule (and a present binding) must be committed to be
   team-shared: `git check-ignore -v` on the resolved paths; a non-empty result is FAIL with the
   matching pattern.
6. **Recurring-maintenance role label**. Role-label resolution is an action-entry invariant per the
   tracker-seam reference; probe it. With no binding (probe 2 INFO) the role remap has nothing to
   configure. INFO. With a binding present, resolve
   `config.role_labels["recurring-maintenance"]` (default `recurring` when the entry is absent; a
   malformed, empty, or non-string configured value is FAIL); missing `cadence:{cadence}` labels are
   taxonomy niceties, INFO. **That resolution FAIL settles probe 6 outright**, it is a binding
   error, independent of any schedule, and `apply` step 9 calls the same value "an error, not a
   fallback" at any row count. The branches below decide only whether a *resolved* label's absence is
   a gate, so reach them only once the role resolves; the probe emits one verdict, and letting a row
   count that is zero, absent, or unreadable pick INFO would drop the binding error from the table
   entirely. With the role resolved, branch on the schedule's **row count**, exactly as `apply` step 9
   does, never on whether the schedule file exists. The skipped first-time bind leaves a
   present-but-empty `{"items": []}` on disk, so a file-presence gate hard-FAILs the expected
   post-bind steady state over an item that can never be created:
   - **Schedule carries ≥1 item**. Verify the resolved label is present via the adapter's label
     listing (GitHub adapter: `gh label list`): an absent label means a seeded `[Maintenance]` item
     lands unlabeled and goes invisible to the next `due` / `work` pass. FAIL, with the remediation
     being the repo's declared label provisioning process (never `gh label create` ad hoc).
   - **Schedule absent, or present with an empty `items` array**, no `[Maintenance]` item can be
     created from a schedule with no rows, so an absent label is INFO, not a gate: report it, and
     note it must exist before the schedule is ever seeded.
   - **Schedule present but not parseable as the `{"items": [ ... ]}` root**. It has no readable row
     count, so the label requirement cannot be evaluated at all: INFO naming probe 4's FAIL as the
     reason, so the table carries a row for every probe, and probe 4's FAIL is the gate. Never read
     an unparsable schedule as zero rows, and never raise the ≥1-row FAIL on a guess about what it
     holds, either would substitute this probe's own verdict for probe 4's.
7. **Work-class label axis**, when probe 2 found a present, shape-valid binding whose provider
   exposes label listing (the `github` adapter: `gh label list`), verify all five canonical
   `work-class:` members from
   [`${CLAUDE_PLUGIN_ROOT}/reference/work-class-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/work-class-labels.md)
   exist. Any missing member is FAIL. Triage cannot apply autonomous-eligible outcomes until the
   axis is provisioned; remediation is `/work-items:setup apply` on repos without label-as-code,
   or the repo's declared label-as-code owner when one exists (never `gh label create` ad hoc there).
   Providers without a label listing (`local-markdown`, read-only `jira`) → INFO: verify at triage
   time via the item store. When probe 2 is INFO (no binding) or FAIL (malformed binding), skip this
   probe, there is no addressable provider yet.
8. **Capability-tier label axis**, when probe 2 found a present, shape-valid binding whose provider
   exposes label listing (the `github` adapter: `gh label list`), verify the canonical
   `capability-tier: frontier` member from
   [`${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md)
   exists. Absent is FAIL. Triage cannot stamp frontier-tier quota guard and the work-loop reader
   fails closed to general tier until the label exists; remediation is `/work-items:setup apply` on
   repos without label-as-code, or the repo's declared label-as-code owner when one exists (never
   `gh label create` ad hoc there). Providers without a label listing (`local-markdown`, read-only
   `jira`) → INFO: verify at triage time via the item store. When probe 2 is INFO (no binding) or
   FAIL (malformed binding), skip this probe. There is no addressable provider yet.
