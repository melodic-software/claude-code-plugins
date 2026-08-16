# Changelog

All notable changes to the `autonomy` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.21.0]

### Added

- **Deterministic prerequisite resolver** (#2724).
  `skills/setup/scripts/resolve-prerequisites.mjs` resolves the verdict set for every
  `v1` identity on a named scheduling surface, reading
  `generated/identity-prerequisites.json` (never leaf prose). Repo-file and
  harness-context probes compose `.claude/autonomy/binding.json` declarations,
  `.claude/ecosystems/*.yaml` (resolved / `enabled: false` not configured),
  `.work-item-tracker.json` + adapter `capabilities.json`, and `.mcp.json`
  (presence vs enablement). Precedence follows ADR 0011 Decision 2: declaration
  narrows; a ran-negative probe caps declarations (contradiction finding);
  unprobeable stays distinct from absent. Output is wall-clock-free (byte-identical
  consecutive runs). Liveness: engine health-check taxonomy row, fail-loud.
  Seven graded fixtures under `skills/setup/scripts/fixtures/prerequisite-resolution/` with
  co-located `*.test.sh` + manifest.

## [0.20.0]

### Added

- **Generated identity-and-prerequisite emission with drift gate** (#2723).
  `skills/setup/scripts/generate-identity-prerequisites.mjs` derives
  `generated/identity-prerequisites.json` from every `v1` leaf's `## Prerequisites`
  section — one machine-readable record per identity (Access class, isolation floor,
  connector entitlements + rung, structured `needs` with probe class / seam) — so the
  resolver reads structure, never leaf prose. Leaves remain the authored single home;
  `--check` fails CI on drift (wired through `scripts/validate-plugins.sh`). Co-located
  `*.test.sh` + manifest cover clean `--check`, a hand-edited drift fixture, leaf↔emission
  parity, and posture divergence (`dependency-update-wave` L2 vs L3).

## [0.19.1]

### Changed

- **`cant-fail-test-repair` row amended: the detection portion is now built (#2684).** The Judgment
  cell and the class-parameters bullet record the shipped `testing:audit` script detector as the
  `DET` detect portion, which carries the no-agent-session property per the portion-split mapping
  rule. The repair judgment — the routine itself — remains unbuilt, so Status stays
  `join: proven recurring manual pattern`, the row does not flip to `v1`, and no `routines/` leaf
  is added: `v1` means a proven manual pattern, and a detector proves detection, never the repair
  pattern that trigger names.

## [0.19.0]

### Added

- **Per-identity prerequisite sections on every `v1` routine leaf** (#2718). Each of the ten
  leaves under `reference/routines/` gains a `## Prerequisites` section owning Access class,
  isolation floor, connector entitlements (and which rung owns each), `executor_class` merge
  cap, and repo needs — derived through the Phase 1 vocabulary in
  `prerequisite-resolution.md`, with floors and the merge cap cited from the guardrail slice
  rather than re-derived. Posture-divergent classes (`dependency-update-wave`,
  `doc-freshness-sweep`, `ci-health-review`) show distinct prerequisite sets per identity.
  Verdict tokens are `supported` | `conditional` | `unsupported` | `unknown`.

## [0.18.0]

### Added

- **Routine prerequisite resolution contract** (`reference/prerequisite-resolution.md`, #2717).
  Owns the per-repo, per-scheduling-surface question the catalog's Access-to-prerequisites
  section left unanswered: which routine identities can run here, and why. Grain is one
  resolution per routine identity on its bound surface; candidate set is `v1` only, with
  `join:` rows reporting under the `deferred-class` marker (not a verdict) and `not-a-routine`
  rows out of domain. Verdicts are fail-closed — `supported` / `conditional` / `unsupported` /
  `unknown` — with `unknown` first-class and a positive verdict required to be reachable.
  Declared narrows and fills; a probe that ran and returned negative caps every declaration
  (contradiction emitted as a finding). Composes owning seams (toolchain, `claude-config`,
  tracker, setup slices) presence-gated; never admission data; recomputes at every consumption;
  scheduled runs read committed surfaces only. One pointer in `routines.md` §Access to
  prerequisites; one README bullet. Implementation (leaf sections, generated emission, resolver,
  setup slice) remains in follow-on issues.

## [0.17.0]

### Added

- **Nine routine-catalog rows for every class considered, including the ones deliberately not built
  (#2682).** A catalog that lists only what shipped cannot be reasoned from — a reader asking "why
  isn't there a clone unifier?" finds silence, which reads as an oversight rather than a decision.
  Every new row derives its guardrail class **through the mapping rules**, never by hand: three
  Tier-1 classes with join triggers (`formal-logic-modeling`, `cant-fail-test-repair`,
  `layering-enforcement`), two Tier-2 (`clone-trend-gate`, `stale-flag-removal`), and four Tier-3
  recording why they are not built (`logic-simplification-sweep`, `abstraction-flattening`,
  `ant-only-shipper`, `gui-crash-fuzzing`). A tenth class, `dead-code-sweep`, already had a row and
  was amended rather than duplicated — see Changed.
- **A `Class parameters` section**, the contract's third progressive-disclosure tier: normative
  detail a row's six cells cannot hold, binding whether or not the class ever gains a leaf. Most
  load-bearing: `dead-code-sweep`'s quarantine window floor of **30–90 days with staged quarantine,
  never one day**, not tunable downward by an org binding — the bound derives from what the window
  must out-last, since 30 days is the shortest window spanning a monthly invocation cadence at all
  and 90 spans a quarterly one, while a one-day window spans nothing and turns a detector false
  positive into a deletion before anything can contradict it. Also: `clone-trend-gate` is detection
  and trend gating only, with the unify *decision* excluded rather than deferred (no surveyed clone
  tool automates it, so there is nothing to defer to); `stale-flag-removal`'s and
  `ant-only-shipper`'s dispositions never automate, because which branch survives and whether to
  promote are product calls; and `clone-trend-gate` and `coverage-mutation-watch` carry identical
  cells but are distinct classes over distinct observables, which only a parameter can say.
- **A `join (external): …` catalog status** for a class deferred on world state no adopting org can
  act on. The pre-existing `join:` triggers are all conditions an org can satisfy;
  `logic-simplification-sweep` and `abstraction-flattening` wait on published evidence and a
  published validated detector respectively, which no adopter step fires. One token carrying both
  semantics made those two rows read as backlog items rather than records.

### Changed

- **`dead-code-sweep` amended, not duplicated (#2682).** It was `DET detect` only; the
  quarantine-exit judgment makes it a hybrid whose judgment portion derives `C3`, because liveness
  is not mechanically checkable — reflection, dynamic dispatch, and out-of-tree callers all defeat
  the build. `C3` is the **class-level** derivation: deleting a symbol on a published,
  cross-repo-consumed surface is a contract change, so the structural axis fires per item and
  escalates that item to `C4`. The class does not derive `C4` wholesale, or the direct-change
  rule's `C2`/`C3` branch would be nearly unpopulated for repo-scoped deletion work. Its precedent
  pointer was updated in step: the pointer describes deletion pipelines, and the staged quarantine
  is the row's own normative content rather than a property read off them.
- **Four general derivation rules now live in `## Mapping rules` itself**, where an org classifying
  a novel class will actually look — three of them relocated from a per-class note, each a place an
  independent re-derivation showed a careful reader can stop early or over-read. A hybrid row is
  portion-split and so binds a posture-qualified identity, its `Derived row` cell carries the
  judgment portion's class, and it is **never** flagged `not-a-routine` — that flag is reserved for
  a wholly deterministic class. `AGT/HUM` assigns a **disposition, not a class**, so it never
  terminates a derivation; a row stopping there would carry a human-gated disposition with no
  verification topology, checker floor, or cost tier. The structural-blast-radius axis fires on the
  change's **target**, not on the file it lives in — and because no catalog column records a target,
  two rows can carry identical axis cells and derive different classes, which the rule now says
  outright. Fourth and newly stated: a risk-raising axis evaluates **per item** as well as
  class-wide, so a class whose axis fires on only some items derives the lower class and records the
  escalation rather than deriving the higher one wholesale.
- **`gui-crash-fuzzing` re-scored against the GUI-actuation mapping rule.** Its `Derived row` cell
  now applies the rule that unattended GUI actuation requires `L3`, which the `repo` access class
  alone does not give. The `L3` comes from that mapping rule directly and not from the guardrail
  matrix's min-isolation column, which is indexed by work class and which a row deriving no class
  cannot reach. Its class parameter also records that reproducibility
  triage of a filed crash is *excluded* from the class rather than left as an unmodelled judgment
  portion — a filed crash is ordinary queue intake — so the `DET` exit is complete rather than
  skipping a split.
- **Deployment-specific and over-precise claims removed from normative text.** A binding parameter
  no longer rests on this fleet's inventory ("ships no GUI to fuzz"), a two-significant-figure
  reproducibility statistic, or universal negatives over unnamed literature. Surveyed-record
  hedging replaces them throughout both files, matching the register the one well-calibrated claim
  in the section already used. The precedent-pointer scope line likewise no longer implies the list
  is exhaustive, and the reviewer-burden deferral no longer cites a "trust-path" commitment that
  appears nowhere else in the repository.
- **`guardrails/isolation-ladder.md` now names both demands for `L3`.** It scoped kernel separation
  to untrusted-provenance (`C5`) work alone, while the routine catalog's access rule has always also
  required it for unattended GUI actuation — a demand that reaches classes deriving no work class,
  so it cannot travel through the matrix's min-isolation column. The ladder is the contract's source
  of truth for when a level applies, and was incomplete against that charter.
- **`guardrails/work-classes.md` records what may never enter a promotion predicate (#2683).** An
  acceptance or merge rate is never a promotion input and is not an efficacy signal, in either role,
  at any cell. The rule rests on the one finding verified at primary source — Lenarduzzi et al.'s,
  that code quality did not affect pull-request acceptance at all — rather than on the three design
  families the survey found pointing the same way, only one of which was checked against its source.
  The section distinguishes the two shipped terms that sit closest to the line, so the
  new prohibition cannot be misread as contradicting the predicates above it: `0 human-reverted
  merges` is a correctness signal (a human asserting the change was wrong), not an acceptance rate
  (how much got merged); and `≥ 20 autonomous C2 merges over ≥ 14 days` is a **volume floor**, not
  an acceptance rate — the two behave oppositely under the move that makes an acceptance metric
  untrustworthy, since a ratio rises when its denominator shrinks (attempting less, or attempting
  only what is certain to land) while a count has no denominator to shrink. The section also
  enumerates every distinct term type the predicate table actually uses — seven, where the prose
  previously named four.
- **The reviewer-burden term is recorded as deferred with an explicit trigger, not omitted
  (#2683).** It needs a denominator, and a denominator needs three org-scale things this contract
  does not have — a population to divide by, a non-merge outcome signal, and a lookback window with
  a demotion rule. Without them the term moves with volume rather than
  trustworthiness — which would reward a cell for producing less. Recorded because a designated
  planning pass was asked to settle it, and silence would have left that obligation unfilled.
- **Standing constraint on any future tuner:** its signal set stays disjoint from promotion
  evidence. Overlap is a self-dealing loop — a tuner optimizing a signal that also promotes a cell
  can raise that signal to reduce scrutiny of the tuner's own output. Binds the tuner's inputs, not
  its intent, and binds whether or not the reviewer-burden term is ever activated.

## [0.16.12]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.16.11]

### Added

- **Issue-author provenance field test for `C5` untrusted-provenance (#1718).** The class now
  carries an executable test on the issue's provider metadata — `authorAssociation` `OWNER` or
  `MEMBER`, or a structural bot listed in the target repository's team-tracked
  `babysit_loop_trusted_internal_bot_logins` — fail-closed when a field is absent or unreadable,
  never a lookup of issue body text. The PR-side fork and trust tests are recorded alongside it,
  with explicit composition rules so the two surfaces cannot be read as one answer to the same
  question. Reuses the reviewed internal-bot trust signal from #1525 so repository-owned
  automation is not misclassified on the issue surface.

## [0.16.10]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.16.9]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.16.8]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.16.7]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.16.6]

### Fixed

- **Concrete credential paths with dot-traversal segments now fail the expansion-coherence
  check explicitly (#949).** A path like `/configured-root/subdir/../.ssh/id_rsa` that
  repeats verbatim in `host_expanded` no longer passes coherence only to be denied later
  by containment normalization; operators see the canonical-path remediation instead.

## [0.16.5]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

Versions 0.1.0–0.7.0 predate this file (introduced with 0.7.1); their history lives in the
merged work-package PRs (#333, #343, #356, #372, #377, #600, #676).

## [0.16.4]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.16.3]

### Fixed

- **The runner charter now records the three obligations the verification-topology work deferred
  to it.** That work states plainly that per-run verdict aggregation and resolved-instance
  distinctness ship unverified because no runner exists to carry them — but it recorded the
  deferral only on the leaf making it, and a deferral the receiving seam does not name is
  indistinguishable from an obligation nobody owns. The runner's inherited-constraints section
  now carries all three (verdict aggregation under the unanimity invariant including the
  timeout and no-verdict cases, refusing to count two checkers that resolve to one instance, and
  lens drawing), each stated as a hole until the build trigger fires.
- **`lane-stop-gate.test.sh` test-hygiene fixes from the #2065 verification pass (#2086).** The FIFO
  hang case now fails closed when `mkfifo` is unavailable, uses `timeout` instead of `kill -9` on a
  subshell that can orphan a grandchild, and `rc0` rejects an empty exit-code argument. The hook
  comment records that `umask 077` is advisory on MSYS and documents the mid-lane downgrade over-gate
  window.

## [0.16.2]

### Fixed

- **The verification-topology leaf now names `scanner_class`, the field that decides whether a slot
  is deterministic or model-adjudicated.** The schema and the checker both key the whole
  deterministic/model split on it — which constraints are legal, which floor a slot counts toward,
  how distinctness is judged — while the normative leaf described the split only in prose. A binding
  author reading the contract could not tell how to declare a deterministic slot, and the contract
  is the surface that is supposed to answer that.

## [0.16.1]

### Fixed

- **Guardrail matrix names the per-invocation `c3-this-run` widening.** The babysit-loop typed-pair
  exception is now acknowledged in `reference/guardrails.md` with a route to the
  `source-control` config-resolution contract. (#2087)

## [0.16.0]

### Changed — ACTION REQUIRED for anyone with an existing `L2`/`L3` binding, or auto-merge bound

- **Every `L2`/`L3` level binding now carries `component_reachable_hosts`, and a level without it
  is UNPROVEN.** Target selection is what makes the egress assertion mean anything: a probe that
  samples only hosts the surface's installed components never request certifies a boundary that is
  in fact open. Measured, not theorized — 201,961 bytes of origin data crossed a global
  default-deny through a component-installed allow rule. The field is the human-ratified set of
  destinations those components may request, and the probe must cover it in FULL, since each
  destination is a separate policy decision. **The empty list is a valid and meaningful value:** it
  is the explicit claim that the surface installs nothing carrying policy rules of its own. **To
  restore dispatch: ratify the list (or the empty list) on the level entry and re-probe so the
  transcript covers it.**
- **A class bound `auto` merge with a verification layer below `blocking` is now an INVALID
  binding.** An automatic transition requires unanimous agreement among the checkers the class
  declares, and an advisory layer records a dissent without withholding the transition — so the
  configuration promised a gate it could not deliver. Bindings that encoded this are rejected with
  a finding naming the remedy. **To restore: set the layer to `blocking` (ratifying its promotion
  cell where promotable), or bind the class to `human` merge.** Demotion now cascades from the
  `C3` AI-review cell to `C3` auto-merge for the same reason.

### Added

- **Verification topology** (`reference/guardrails/verification-topology.md` + a sixth guardrail
  matrix column): who verifies a change, how those verifiers must differ, and the per-class floor
  for how many there are — expressed as pipeline roles, relational constraints, and predicates a
  binding can actually evaluate, with no capability label anywhere in the contract. Floors ship as
  `min_checkers` and `min_model_checkers` per class, both tighten-only on the agent-unwritable
  security binding. `cross_vendor_required` is never vacuously satisfiable, and vendor disjointness
  holds among the model-adjudicated slots rather than only against the generator.
- **`verification_topology`** as an optional top-level security-binding key modeling all three axes.
  Absent is not a hole — the shipped floors apply, as `escalation_severity` already does — so
  `schema_version` stays `"1.0"` and every existing binding keeps validating.
- **Two `userConfig` options:** `verification_lens_pool` (what angle each model-adjudicated checker
  is asked to take) and `visual_narration_enabled` (an advisory narration lane, default off). Both
  live on the operator surface rather than the security binding because neither counts anything —
  the pool seats no slot and the lane has no binding cell at all, so neither can weaken a floor.
  The lane is structurally incapable of gating: no cell exists anywhere through which authority
  could be granted to it.

## [0.15.1]

### Changed

- **Shared `hook-utils.sh`: the jq gate now has a fail-CLOSED sibling, and the posture reasoning
  lives at the helper (#2146).** `hook::require_jq` is unchanged and still fails OPEN — one visible
  skip notice per session, then exit 0 — which is the correct posture for every hook in this plugin,
  so **nothing in this plugin's behaviour changes**. What is new is `hook::require_jq_blocking`, a
  second named function that denies the tool call instead, for the narrow class of guards whose job
  is blocking an irreversible operation (today only two, both in `guardrails`). A sibling function
  rather than a parameter, because a flag's omitted value would default to fail-open and a guard
  whose flag someone forgot would then fail open *silently* — the exact defect #2146 reports,
  reintroduced at the API. The two postures are now argued together in one block above both
  functions, which is what #2146 asked for: previously each call site asserted a posture in a
  comment and nothing where the decision is made explained it. Synced from `lib/hook-utils.sh`.

## [0.15.0]

### Changed — ACTION REQUIRED for anyone with an existing `L2`/`L3` binding

- **The isolation probe now runs three assertions, and every level bound under the old
  two-assertion recipe must be re-probed.** Transcripts captured before this release do not
  carry the workspace assertion, so the security check leaves those levels UNPROVEN — and the
  ladder's fail-closed rule then BLOCKS autonomous dispatch on that surface until a fresh probe
  lands. Nothing degrades silently and no binding becomes invalid; the affected levels simply
  stop counting toward isolation eligibility, and the check names the missing assertion so the
  remedy is readable from the failure. **To restore dispatch: re-run the probe under the updated
  recipe and re-record `probe_evidence`.** This is a deliberate bar raise — the two-assertion
  recipe certified boundaries it had never measured.

  The prior recipe could pass a boundary that still carried the entire host-execution attack
  class. Its assertions covered egress and credentials; nothing covered the workspace mount,
  which is a deliberate hole through the process boundary the levels describe.

- **A zero exit is accepted where, and only where, the peer was substituted.** Peer identity is the
  verdict and the exit code is evidence, so requiring a non-zero exit unconditionally would leave one
  sealed boundary unprovable: an interception layer whose block page carries a SUCCESSFUL HTTP status
  exits `0`. That target's `transport_outcome` must be `peer-substituted` and its two fingerprints
  must differ; everywhere else a non-zero exit is still required, so the exception cannot excuse a
  target that simply succeeded.

- **Egress denial is proven by peer identity, not by a failed connection.** Two observed
  behaviors defeated the old test: a raw `connect()` SUCCEEDS where an interception layer accepts
  the SYN and then drops the session, and a policy block page is a valid HTTP response that a
  fetch client exits `0` on. Certificate validity does not settle it either — an inspection CA
  trusted inside the boundary makes an interceptor verify cleanly. An interceptor cannot present
  the origin's own key, so the transcript now records and compares peer fingerprints. Three legs
  close the rest: the probe client must be shown to RUN inside the boundary (an absent client
  would satisfy every egress assertion trivially), at least two targets under different operators
  must be denied (one denial is consistent with a policy that allows others), and the exercised
  address families are recorded rather than inferred.

- **`L2` in the isolation ladder now names contained workspace host-writes** alongside
  default-deny egress and credential protection. Scope is WRITE containment, stated explicitly:
  read exposure is not covered, and a copy-on-read workspace leaves reads fully open.

### Added

- **`workspace_host_write_contained`** — the third probe assertion, proven from the OUTER side so
  one rule covers both substrate shapes: a read-only mount rejects the inner write, a
  copy-on-read mount accepts and discards it, and both are contained. The inner exit code is
  recorded but never asserted on, because constraining it would grade copy-on-read substrates
  wrongly. Randomized canaries span an ordinary file, a dotfile, and a version-control path; the
  host re-check runs after teardown so a caching mount cannot propagate a write behind the
  probe's back. Where the host workspace is not observable from the outer context, the assertion
  records `not-applicable` and the level stays UNPROVEN — never a silent pass.

## [0.14.4]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.14.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.14.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.14.2]

### Fixed

- **Shared `hook-utils.sh`: `env -S` / `--split-string` no longer hides a whole command from the
  git guards (#2124).** `-S` exists so a shebang line can pass OPTIONS to env
  (`#!/usr/bin/env -S -i prog`), so the words it splits out are env's own arguments. The resolver
  spliced them back into the scan but resumed at the COMMAND dispatcher, which read a leading
  option in the split string as the command NAME and gave up — `env -S '-C <dir> git push --force'`
  resolved to no git at all, so every guard built on `hook::git_resolve_index` skipped the command
  unexamined. Parsing now resumes inside env's own option loop. That also keeps env's single chdir
  slot last-wins across the splice, so `env -C a -S '-C b git …'` reports `b`, matching GNU env.
  Synced from `lib/hook-utils.sh`.

## [0.14.1]

### Fixed

- **Shared `hook-utils.sh`: a NUL byte inside a payload value no longer makes `hook::jq_fields`
  come back empty (#2120).** The helper delimits its batched fields with NUL, and a JSON string may
  legitimately encode one — a `Write`/`Edit`/`NotebookEdit` content field can. jq emitted the raw
  byte, the read split that value in two, the cardinality check saw one value too many, and the
  helper returned non-zero — which every caller treats as "skip", so the hook exited without doing
  its work. Each value is now NUL-stripped INSIDE the jq filter, so the delimiter provably cannot
  occur in a value. Stripping is not a lesser alternative to an encoding scheme, it is the only
  representable behavior: a bash variable cannot hold a NUL byte, and the per-field command
  substitution this helper replaced dropped the byte and kept the rest of the value — so content
  AFTER a NUL is returned and scanned exactly as it was before the batching. Synced from
  `lib/hook-utils.sh`.

## [0.14.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.13.1]

### Fixed

- **`lane-stop-gate.sh`: the first-session arm claim is atomic, and a record is
  honored only for its persisted owner (#1865).** The claim was a read-then-write of the arm
  record: two Stop invocations presenting the same fresh arm id both read it unclaimed, both wrote,
  and the last rename won — so BOTH honored the arm for that event while the loser, possibly the
  legitimate lane, was refused on every later stop and ran ungated. The claim is now an exclusive
  create (`set -o noclobber` on a `>` redirection, i.e. `O_CREAT|O_EXCL`) of a `<record>.claim`
  sidecar holding the owning session id, the same primitive `statusline-tee.sh` already uses and
  the reason it gives for avoiding `flock` (absent on macOS) applies here too; `GATE_ARM_JSON` is
  assigned only past the ownership verdict, so an unowned record contributes no config at all. A
  claim file exists only because some process won that create, so an EMPTY one is the winner caught
  between its create and its write rather than an ownerless record — reading it in that instant
  would hand one fresh arm to every concurrent presenter and reopen the race a few microseconds
  wide, so the owner read is retried over a bounded budget. The fail direction is unchanged — a
  store the hook cannot write leaves no claim, and a claim whose owner never lands exhausts that
  budget; both honor the arm, because a legitimate lane losing its gate is the harm, not an extra
  gated stop, and refusing a durably ownerless claim would make the record permanently unclaimable.
  A record claimed by an earlier version carries its owner in the record itself and stays bound to
  that session; `lane-stop-gate-arm.sh` clears the sidecar before it (re)writes a record so a
  re-armed id starts unclaimed, and the gate's TTL sweep drops record and sidecar together. The
  clear precedes the write rather than following it, so a crash between the two leaves the old
  record with no claim — an extra gated stop — instead of a fresh record beside a stale claim,
  which refuses the new lane on every stop until the record ages out. And the claim path carries the
  record path's own `[[ -f ]]` asymmetry: anything there that this hook did not write decides
  nothing and the arm is honored, so a planted FIFO cannot take the write with no reader and hang
  the whole Stop event into a permanently allowed stop.

## [0.13.0]

### Added

- **`reference/autonomous-pipeline-reminder.md` — the standing reminder an adopting org drops into
  its own pipeline.** Until now the guidance existed only hand-authored inline in two of this
  repository's three lane launch prompts, which is a launch surface for these lanes and not a
  reusable artifact for anyone else's. The file states the two stopping failures a pipeline cannot
  recover from — a turn ending on unexecuted intent, and a turn stopping to ask permission nobody is
  there to give — then gives the paste-ready clause set: proceed on anything reversible, pause only
  for a destructive or irreversible action, a real scope change, or input only the launcher can
  supply; ask once and never re-ask what is settled; read the final paragraph back before ending a
  turn; and an enumeration of the shapes that are work orders to act on rather than messages to end
  on. The companion checkpoint instruction its source guide asks to be paired with the reminder is
  folded in, so a consumer pastes one block rather than assembling two.

  **Locally authored, not reproduced.** The clause set is this repository's own wording of guidance
  published in Anthropic's Claude Fable 5 prompting guide, "Rare cases of early stopping"
  (<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>,
  fetched 2026-08-08). Copying the upstream text would have violated this repository's own rule
  against hand-copying upstream content; the file carries the pointer and a recheck trigger instead.

  **The block is internally consistent about the two things it is easiest to get wrong**, both
  caught in review of the first draft. An action being visible outside the working tree does not by
  itself make it one to ask about — the pause test is irreversibility, an outward action the request
  did not ask for, a scope change, or user-only input, so authorizing "opening a draft" no longer
  contradicts the pause clause. And naming further work is a *report* once the run is complete but a
  *deferral* mid-run, so the enumerated shape is now "a mid-run offer to do work already within this
  run's scope" rather than any offer at all; the discriminator is whether the run is over, stated in
  the block itself.

  **Two boundaries ship with it**, because an artifact that reads as universally applicable would be
  applied where it does damage. An **attended** lane deliberately does not carry the reminder —
  "recommend, then wait for my direction" is the opposite posture, and pasting the block into one
  converts a working human-in-the-loop review into an agent acting on its own recommendations, which
  is why this repository's two-of-three lane split is the contract rather than an inconsistency. **No
  lane references this file**, and the reference says so rather than implying otherwise: launch
  prompts are pasted into a terminal that may have no plugin installed, so they stay self-contained
  by design. The clauses previously existed only as prose duplicated across two launch surfaces and
  reusable by nobody, which is the gap this file closes. And
  the `lane-stop-gate` hook mechanizes exactly **one** clause: it performs no content classification
  beyond its literal sentinel check, so it cannot tell a blocked-on-user stop from a lazy one, and
  every other clause is carried by instruction alone. That scope is now stated in the hook's own
  header as well, so a reader of the gate does not infer coverage it does not have.

### Changed

- The `loop-lane` convention now points at the new reference for the reminder's clause set instead
  of leaving it implicit in the launch prompts, and keeps only the two boundaries that are
  lane-topology facts rather than reminder content.

## [0.12.3]

### Changed

- **Shared `hook-utils.sh`: a hook invocation spawns three fewer external processes (#1978).**
  Every hook that buffers its stdin paid an `awk` (one float division, to slice the read timeout), a
  `printf | tr -d '\r'` pipeline (a fork and an exec to delete one byte class from a string bash
  rewrites in place), and a `jq -e .` validity probe over a buffer the read loop had already parsed
  with jq. On Windows Git Bash, where process creation is `fork()` emulation, each spawn costs
  ~140 ms. Behavior is unchanged: the slice keeps the three-decimal form `read -t` is given, the
  buffer is CR-stripped as before, and the completeness verdict is reused only when jq itself
  produced it — so a host without jq still fails open exactly as it did. Also adds
  `hook::jq_fields`, which extracts several fields from one payload in a single jq process for
  hooks that read two or three of them. Synced from `lib/hook-utils.sh`.

## [0.12.2]

### Fixed

- **`reference/routines.md`: the `goal` glossary row no longer claims a budget cap ends the
  session.** The row read "until a separate grader judges the condition met or a budget cap trips";
  the official page documents a closed two-item set — "A goal keeps running until the condition is
  met or you run `/goal clear`" — and its own section on bounding a goal's duration offers a turn or
  time clause inside the condition, not a spend cap. The only dollar cap Claude Code's CLI documents
  is the `--max-budget-usd` flag, which is print-mode-only and invocation-scoped, whereas this row
  is `session-scoped`; a cap-stopped invocation also leaves the goal neither achieved nor cleared,
  so it is restored on `--resume`/`--continue` — the cap ends the process while the goal outlives
  it. The replacement clause names the second of the two events that actually change goal state.

## [0.12.1]

### Changed

- **`lane-stop-gate-lib.sh`: the server-managed settings channel's exclusion from the org-veto
  source list is documented as deliberate.** The gate reads only endpoint managed-settings paths
  plus `managed-settings.d/` drop-ins; [server-managed
  settings](https://code.claude.com/docs/en/server-managed-settings) surface on disk only as the
  user-writable cache `~/.claude/remote-settings.json`, which fails the root-owned trust test the
  veto relies on — the page itself calls the channel "a client-side control, not a security
  boundary". Comment at the exclusion site plus a README precedence-list note directing orgs on the
  server channel to also deliver an endpoint `managed-settings.json`; no behavior change.

## [0.12.0]

### Changed

- **`lane-stop-gate.sh`: gate config is honored from trusted sources only — the bare
  `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_*` environment is never authority (#1784).** The enable
  flag (and the sentinel and marker path with it) was read straight off the environment — channel B
  of `docs/conventions/hook-config-delivery`, whose rule 3 requires channel F for a safety-critical
  optional-with-default toggle: for an unconfigured key, a watched repository's own
  `.claude/settings.json` `env` block populates the variable freely (fact 4), so the watched repo
  could decide whether the gate runs, weaken the sentinel to an incidentally-occurring line, or
  point the marker at a file of its choosing. Per-key resolution is now managed settings (fixed
  root-owned paths plus `managed-settings.d/` drop-ins) ▷ the per-session arm record (below) ▷ the
  user `settings.json` located only from the hook's own `plugins/cache` install anchor ▷ the
  in-script defaults. No file path any of these reads is env-derived — and the managed-settings
  platform is read from `uname -s`, not the repo-settable `$OSTYPE`, with the resolved primary
  asserted absolute so it can never become a cwd-relative (repo-plantable) path. An unreadable or
  malformed trusted source contributes no verdict and the default (off) applies — the gate keeps its
  fail-open, never-wedge posture. When the env channel *claims* enablement that no trusted source
  corroborates — a stale launcher still delivering over `--settings`/env, or a repo attempting the
  old attack — the gate emits a visible once-per-session notice instead of disengaging silently.
  **Behavior change:** a `--settings`-only `lane_stop_gate_enabled=true` no longer engages the gate;
  lanes are armed by the claude-ops lane launcher (0.26.0+) instead, and a `--plugin-dir` checkout
  install (no install anchor, hence no trusted user-settings or record location) can be enabled only
  via managed settings.

### Added

- **`hooks/lane-stop-gate-arm.sh` — operator-side per-session arming, and the
  `lane_stop_gate_arm_id` userConfig key that points at it (#1784).** A hook cannot observe
  `--settings` (the channel-F residual), so the per-session opt-in the launcher shipped over
  `--settings` needed a trusted replacement, not deletion. The launcher now generates a random arm
  id, runs this helper — which writes a record (sentinel/marker config, armed-at stamp) under the
  plugin's **own install-derived** data directory, refusing when unanchored or when managed settings
  veto with `lane_stop_gate_enabled: false` — and passes the id to the session through the new
  string option. The env-delivered id is a capability pointer, never authority: the gate
  shape-validates it (`^[A-Za-z0-9_-]{8,64}$` before any path use), looks it up only in the
  install-anchored store (the `CLAUDE_PLUGIN_DATA` fallback is used for the marker-consumption
  ledger only, never for records or enablement), and claims it for the first presenting session so a
  replayed id is refused, expires it after 7 days. The record is **not** consumed on a stop: a lane
  is one session across many `/loop` cycles, each ending in a Stop the gate must still guard, so the
  record lives for the claiming session (bound to it by the claim) and is retired by its TTL plus the
  launcher's relaunch sweep. A repo env block can neither mint a valid id nor clobber a configured
  one (harness injection wins for configured keys). Shared derivation helpers live in
  `hooks/lane-stop-gate-lib.sh`, sourced by both scripts.

### Fixed

- **Managed settings reach a `--plugin-dir` install (#1784).** Keying every settings read on the
  marketplace-qualified id meant the managed scope contributed no verdict without a
  `plugins/cache` anchor — silently disabling the org-mandate path on the one install class for
  which it is the *only* enable path, and on whose availability the arm helper's refusal to arm
  there is premised. An unanchored install now matches on the plugin name from the manifest beside
  the hook (the same `BASH_SOURCE`-derived trust anchor everything else uses), accepting a bare or
  any marketplace-qualified key; anchored installs keep their exact-id match, so another
  marketplace's entry still cannot mask this install's.
- **An empty configured sentinel falls back to `LANE-STOP-OK`.** Emptiness is not a documented way
  to disable the token channel, and honoring it silenced that channel while the block reason still
  instructed the agent to emit an empty token on its own line.

## [0.11.8]

### Fixed

- **`lane-stop-gate.sh`: a completion marker whose deletion fails no longer authorizes a later,
  unrelated lane run (#1784).** The marker's one-shot authorization was latched solely by deleting
  the file, and the marker lives in the watched checkout — a directory the hook is not guaranteed to
  be able to write. An `rm` the OS refused left a file that still satisfied `[[ -f "$MARKER" ]]` on
  the next run, which is exactly the cross-run bypass consuming the marker exists to close; the
  surrounding comment asserted "the next run must not rely on that stale file" while nothing enforced
  it. Consumption is now recorded in this plugin's own persistent data directory — path plus the
  consumed file's identity (mtime and size) — and the deletion is the tidy-up rather than the latch. A
  marker recorded as consumed is not a signal however long it survives on disk. Recreation recovery
  is BEST-EFFORT, not guaranteed: a marker recreated with a different mtime or size reads as a new
  file and authorizes normally, but one recreated at the same size within the same whole second — an
  empty `touch`-style marker being the realistic case — is indistinguishable under a one-second
  `stat`. It then stays latched for as long as it goes unwritten: an mtime does not advance on its
  own, so what clears the record is the marker's NEXT write landing in a different second, not the
  clock passing one. The cost is that single completion signal; the one after it authorizes. That is
  the deliberate direction for a gate: a stop delayed, never a second unearned one. A host where
  neither `stat` form reports an identity holds the record for the same reason. The
  data directory is derived from the hook's own install path (the `plugins/cache` anchor Claude Code
  documents), falling back to `CLAUDE_PLUGIN_DATA` only for a `--plugin-dir` install that carries no
  such anchor: the script's own location is not something a watched repository can redirect. When no
  data directory can be written the deletion remains the only latch, i.e. the behavior that predates
  this ledger.

## [0.11.7]

### Fixed

- **Shared `hook-utils.sh`: the OS temp tree is no longer treated as project content (#1769).**
  `hook::read_file_path` scoped a file to the project by prefix-matching `CLAUDE_PROJECT_DIR`, so a
  session whose project directory is the user's home admitted everything under the OS temp root —
  including Claude Code's own per-session scratchpad, which lives there. Hooks that lint, rewrite, or
  autocorrect then ran on throwaway files that are not project content and carry no project config to
  opt out with; the reported case was `typos-format` autocorrecting a shell variable in a scratch
  script and silently breaking it. The guard now rejects a file inside the OS temp tree when the
  project root is outside it. The exemption is deliberate and load-bearing: when the project root
  itself lives under temp — a `mktemp -d` fixture checkout, which is how this repository's own hook
  suites run — its files are still accepted. Temp roots come from `TMPDIR` / `TMP` / `TEMP` plus the
  POSIX defaults, canonicalized through the same pipeline the membership comparison already uses.
  Synced from `lib/hook-utils.sh`.

## [0.11.6]

### Fixed

- **Shared `hook-utils.sh`: a wrapper's working-directory change is no longer lost when a caller
  parses only git's own global options (#1503).** `hook::git_resolve_index` walks wrapper programs
  (`env`, `sudo`, …) to reach the real `git` token, and a caller that scopes its git-global parsing
  to the slice starting at that token cannot see a relocation the wrapper already performed — GNU env
  documents `-C, --chdir=DIR` as "change working directory to DIR". The resolver now reports those
  directories in a new `HOOK_GIT_RESOLVED_WRAPPER_DIRS` result global, in execution order, so a
  caller composes them ahead of git's own globals instead of dropping them. Five spellings are read
  (`-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered `-vC DIR`), a repeat within one
  `env` is last-wins as env itself resolves it, and sudo's `-D`/`--chdir` is read in its unclustered
  spellings. A chdir spelled inside `-S`/`--split-string` is NOT read; that path already fails open
  for any command on `main` and is tracked in #1814. This plugin does not consume the new global; the sync keeps its copy
  byte-identical with the source. Synced from `lib/hook-utils.sh`.

## [0.11.5]

### Fixed

- **`lane-notify.sh` no longer claims no remote/Slack/push transport exists (#1650).** The header
  stated "there is no remote/Slack/push transport here (none exists as a marketplace primitive
  yet)" — stale on both clauses, since first-party off-machine transports do exist today. The
  comment now says so and points at the loop-lane convention's out-of-band notification seam (§2),
  which owns that seam and its verified grounding, instead of restating the mechanisms and their
  citations here. The primitive's own local-only reach and its closed-laptop/dead-process caveat
  are unchanged. Comment-only — no hook behavior change.

### Changed

- **`reference/runner/escalation.md`: severity fan-out legs grounded in shipped transport surface
  classes (#1650).** The channel-notification and personal-push legs were unbuilt design with no
  named surface class. A new "Fan-out transport grounding" subsection assigns the channel leg to
  the deterministic hook-transport class and the personal-push leg to the model-discretionary
  push-notification surface class, records each class's dependency profile, and states that both
  classes have shipped mechanisms today — so neither leg waits on a primitive that has to be
  invented. Per this plugin's contract boundary the subsection names no vendor and no instance:
  concrete adapters are bound and re-verified at build, and the consuming-side wiring lives in the
  loop-lane convention's seam.

## [0.11.4]

### Fixed

- **Shared `hook-utils.sh`: an in-project file spelled as a Windows 8.3 short name is no longer
  silently skipped by the shared membership guard (#1636).** `hook::physical_path` canonicalized
  with GNU realpath, which under Git Bash resolves symlinks but leaves 8.3 short names
  (`KYLESE~1`) unexpanded, so a short-form `file_path` failed the `CLAUDE_PROJECT_DIR` prefix
  comparison in `hook::read_file_path`. The lib now expands short names on Windows/MSYS hosts
  (new `hook::expand_8dot3`, via `cygpath -l`) before the comparison, and only when the expanded
  form actually differs; a genuinely out-of-project file is still skipped. 8.3 generation is a
  per-volume property (`fsutil 8dot3name query`), so the defect was live only for checkouts on a
  volume that generates short names. Synced from `lib/hook-utils.sh`; this plugin's own hooks do
  not consume the membership guard, so their behavior is unchanged.

## [0.11.3]

### Fixed

- **Shared `hook-utils.sh`: a large tool payload no longer makes this plugin's hooks silently
  skip (#1563).** `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a
  pipe one byte at a time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a
  ~64 KB throughput ceiling rather than the stall detector it was written to be. Past that ceiling
  the read returned a truncated payload and rc 1, and this plugin's hooks took their `|| exit 0`
  branch — the hook did not run at all, with no diagnostic, on exactly the large writes it was
  most wanted for. The read is now chunked (`read -N`), which bash satisfies with block reads, and
  the bound became a true idle bound: `read -t` is a deadline for the whole requested read rather
  than an inactivity timer, so a timed-out read that nevertheless returned bytes is now treated as
  progress — its partial chunk is kept and a fresh window is armed. Only a window that delivers
  nothing at all is a stall. `read -N` is Bash 4.1+, and these hooks support Bash 3.2+ (macOS
  system bash), so the pre-4.1 path falls back to the delimiter read inside the same re-arming
  loop. Measured: 50 KB drops from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms. Synced
  from `lib/hook-utils.sh`; this plugin's own hook behavior is otherwise unchanged.

## [0.11.2]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`lane-stop-gate.test.sh`).

## [0.11.1]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no hook block/allow behavior changes.

## [0.11.0]

### Added

- **Deterministic lane-stop gate (`Stop` hook) — the plugin's first hook** (#535 member 3). "A lane
  that stops itself before its goal is met is a bug" was previously only a prompt admonition. The new
  `hooks/lane-stop-gate.sh` fires on every stop attempt of an opted-in lane and structurally
  intercepts it: unless completion is EXPLICITLY signaled, the first stop is blocked with a
  re-injected completion self-check (`decision:"block"` + reason), converting a silent premature stop
  into "keep going or declare done." It directly counters the fabricated-context-percentage
  premature-stop failure (#576/#577) — the reason states that a self-estimated "~50% context", a turn
  count, or a vague sense of "enough" is not a completion condition. Completion is signaled
  deterministically (a shell hook cannot re-run the `/goal` evaluator model): either the exact
  sentinel token (default `LANE-STOP-OK`, matched only when alone on its own line) in the agent's final message, or
  the existence of a configured marker file — the settings-scoped, cross-session sibling of `/goal`'s
  session-only condition (#481). The marker is consumed (deleted) when it authorizes a stop — one
  marker, one stop — so a file left in the checkout by a prior completed run never authorizes the
  stops of a later lane run. The shipped standing-lane launch flow wires the opt-in per lane: the
  `claude-ops` lane launcher's new per-lane `settings` passthrough (its changelog) carries the
  documented `--settings` override, so lanes get the gate from tracked lane config rather than
  persistent global configuration. **Default OFF**: a Stop-blocking hook must never engage for an
  interactive session, so it is inert unless a lane opts in via `lane_stop_gate_enabled=true`. It is
  **fail-open** on unreadable stdin, missing `jq`, or a non-`Stop` event (a `SubagentStop` never trips
  it), and bounded against runaway: the `stop_hook_active` guard makes the gate block a stop at most
  once before allowing it, with Claude Code's own consecutive-block cap as the ultimate backstop.
  Scope: it catches a graceful **self-stop** only — a closed laptop,
  a killed process, or `/loop` expiry emit no `Stop` event and are out of this member's scope.
- **Operator notification on a genuine lane stop** (#535 member 4, evidence #582). When a lane still
  stops after the one structural nudge, the gate treats it as a down/stuck lane, allows the stop (never
  wedges it), and alerts the operator via the new self-contained `hooks/lane-notify.sh` — an OS-native
  toast (macOS/Linux) plus a best-effort terminal bell + OSC 9. Reach is **local-machine only**: there
  is no remote/Slack/push transport (none exists as a marketplace primitive yet), so it does not cover
  an away operator. It reimplements rather than sources the `desktop-notification` plugin because a
  `Stop` hook's stdout is parsed for `decision`/`reason` and cannot use the `terminalSequence` field
  that plugin's `Notification` hook relies on — a genuinely different emission path (direct `/dev/tty`)
  — and because cache-isolated plugins cannot source each other at runtime. No separate
  repeated-failure counter was built: a lane that keeps stopping simply re-fires this notification each
  time (and API-error telemetry is already owned by `claude-ops`'s `StopFailure` hook).
- **Six `userConfig` options** gating the above: `lane_stop_gate_enabled` (default false),
  `lane_stop_gate_sentinel`, `lane_stop_gate_marker`, `lane_notify_enabled`,
  `lane_notify_os_toast_enabled`, `lane_notify_terminal_enabled`. The plugin now carries the shared
  `hooks/hook-utils.sh` copy (Win32-safe stdin buffering, prerequisite-visibility helpers).
- **Lane-stop telemetry** (hook-telemetry convention). The gate emits one fire-and-forget envelope
  per **evaluated** outcome when the consumer sets `HOOK_TELEMETRY_SINK` — `blocked`/`nudged` for the
  one structural nudge, `ok`/`completion-signaled` (with the signaling channel, `sentinel` or
  `marker`) for a legitimate stop, and `ok`/`stopped-after-nudge` for the down-lane path that fires
  the operator notification — so premature lane stops are measurable and the local alert is
  correlatable in the fleet's hook observability pipeline. Default-off and fail-open exits stay
  silent. The `data` payload is a closed fixed vocabulary (published at
  `docs/conventions/hook-telemetry/data/lane-stop-gate.schema.json`) and never carries the sentinel
  token value, marker path, cwd, or branch.

## [0.10.0]

Tier ratified as **minor**, which under this plugin's `0.x` scheme is the breaking/vocabulary slot —
not the lesser of the two readings. The determinism rule below is contract vocabulary an adopting
org classifies novel routine classes against, and both its wording and its named rule token change,
so it takes that slot. The narrower reading — a **patch** (`0.9.1`), on the grounds that the
classification's substance is unchanged and every derived guardrail row is byte-identical — was
considered and not taken.

### Changed

- **`routines.md`: the determinism rule now fixes a property, not a mechanism.** "Deterministic
  checks are never routines … run as plain cron" prescribed a substrate in a contract whose own
  §Hosting stance holds that hosting is a deployment-owned binding. The invariant is **no agent
  session, zero agent tokens**; the substrate carrying it binds per deployment like every other
  hosting choice. The categorical "never" also concealed the hybrid `DET`-detect / `AGT`-judgment
  split defined two paragraphs below — a split the catalog uses on nearly as many rows as it flags
  `not-a-routine` — so the rule now states that determinism is a per-PORTION verdict and rarely a
  reason to stop classifying. The mapping rules, the catalog status legend, every `routines/` leaf
  that echoed the mechanism, and the setup skill's reconciliation rule and its evals move with it.
  **Bump ambiguity:** the substance of the classification is unchanged and every derived guardrail
  row is identical, which reads as a clarification and a **minor**; but the rule is contract
  vocabulary an adopting org classifies novel routine classes against, and both its wording and its
  named rule token change, which reads as a vocabulary change and a **major**.
- **The one-entrypoint invariant has one canonical statement.** It was restated six ways across
  five documents, and the restatements had already drifted apart — each named a different subset of
  the paths it forbids a second of. `trigger-dispatch.md` §Dispatch now states it canonically, and
  the adapter obligation, the constraints list, `routines.md` §Hosting stance, `guardrails.md`
  §Escalation, `runner.md`, and `runner/seams.md` cite it. The **escalation** channel stays a
  separate, narrower invariant owned by `guardrails.md`, and the runner's single hand-back path
  stays a separate runner-new one — collapsing either into the dispatch invariant would have been a
  regression wearing deduplication's clothes.

### Added

- **The one-entrypoint invariant's scope boundary is written.** The invariant had no stated scope,
  so whether a surface that touches a repository without claiming a queued item fell under it was
  unanswerable from the contract. It now governs the governed-queue path — claiming a queued item,
  or dispatching autonomous execution against one — and the boundary keys on what a surface DOES,
  never on what it is called. The `source-control` babysit lane is outside it today because it
  claims no work items, which its own skill body states; the boundary becomes load-bearing the
  moment a second claiming surface exists, which is why it lands before the runner is built rather
  than after two surfaces disagree.

## [0.9.0]

### Changed

- **Credential-probe validation is now deny-by-default against a configured `--credential-roots`
  allowlist.** The security-binding checker no longer recognizes a probed host-credential path by
  static structural shape. A static checker cannot know an org's real credential locations, and for
  any open-ended structural recognizer an adversary can craft a plausible-but-invented path (an
  invented home user, a mount that need not exist) whose failing read proves nothing while real host
  credentials stay readable. A filesystem credential entry now counts as credential-absence evidence
  only when its recorded host-side expansion resolves — lexically, `..`-safe, filesystem-independent —
  under one of the operator-configured trusted roots passed via the new `--credential-roots
  <path,path,...>` flag, mirroring the `--egress-hosts` seam; with no roots configured, every
  filesystem credential entry is untrusted and the level fails closed. Membership under a configured
  root is the sole test, so the previously non-converging location enumeration is dissolved. A
  cloud-metadata-endpoint route and a well-known credential env token remain bounded closed sets that
  need no allowlist, and the expansion-coherence guard is retained. The egress-side seam is unchanged.

## [0.8.0]

### Added

- **Instruction-provenance clause added to the routines contract.** A new normative clause in
  `reference/routines.md` fixes that a routine's instruction content lives in a
  version-controlled, reviewable artifact and the stored prompt is a thin pointer to it;
  pasted-prose prompts are non-compliant, retaining no history and drifting invisibly against
  the repository state each run executes on. The clause is surface-agnostic — its rationale is
  that a scheduling surface holding the prompt centrally exposes no prompt history, diff, or
  rollback, so behavior change is auditable only where the pointed-to artifact is versioned.
  Surface-class mappings (a cloud scheduling surface → a skill committed to a selected
  repository's skills directory; a desktop scheduling surface → a per-task instruction
  file under the deployment's version-controlled dotfiles) appear only as illustrative
  deployment-owned bindings, consistent with the contract's Hosting stance.

## [0.7.4]

### Changed

- **Boris-intent attribution seams marked across the guardrail contract.** Three surgical
  attributions distinguish this contract's own instantiation from the source playbook's posture,
  closing UNMARKED-EXTENSION seams a Boris-intent audit found (zero violations, three seams). The
  guardrail hub now states that the step-4 sentence it quotes verbatim is the playbook's while the
  five-class taxonomy, blocking knobs, and promotion predicates are this contract's mechanism; the
  security-review leaf marks review-as-merge-gate (the `blocking` knob) as this contract's own
  layer over the playbook's advisory-review-feeding-a-human-merge posture; and the work-classes
  leaf attributes the numeric-predicate promotion/demotion apparatus as this contract's
  quantification of the playbook's qualitative "earned widespread trust" bar. Documentation only —
  no contract semantics change.

## [0.7.3]

### Added

- **Security-binding golden suite is graded (`#662`).** A table-driven runner
  (`check-security-binding.fixtures.test.mjs` + its co-located expectations manifest) runs
  every fixture under `evals/fixtures/security-binding/` through
  `check-security-binding.mjs` and asserts exit code + defect-naming findings: 109 fixtures
  (14 pass-expected, 95 reject-expected), zero quarantined, with the fixtures' 67 probe
  transcripts enumerated as suite inputs. Self-policing in both directions — an ungraded
  new fixture, an unlisted transcript, or a manifest entry whose file vanished all fail the
  suite, and the repo's orphaned-fixture gate no longer grandfathers the set.

## [0.7.2]

### Changed

- **Pillar 3 reconciled with the audited native-surface reality (`#351` audit).** The
  causal-tree contract now states explicitly that `traceparent` propagation binds
  CONTRACT-AUTHORED emissions, and that a native agent surface ignoring inbound context (a
  default surface may, honoring it only behind an opt-in) does not break the tree — its
  session emissions attach query-side through the Pillar 2 join attribute, and relying on
  direct native span joining is a recorded migration trigger, not an assumption. The CI
  OTLP template's trace-context-injection section carries the same surface-specific caveat
  plus the `OTEL_RESOURCE_ATTRIBUTES` injection the setup flow already wires. No emission
  or checker behavior changes.

## [0.7.1]

### Added

- **D1 deferral sweep — every out-of-package note from the WP1–WP7 design rounds now has a
  durable trigger record (`#353`).** The README roadmap gains the fleet guardrail
  materializations, fleet routine stand-up + existing-scheduler reconciliation,
  vendor-binding capability templates, and cost-enforcement rows; the trigger register gains
  the second-binding-consumer cross-repo drift check; `reference/return-accounting.md`
  records the per-work-class precision-graduation deferral beside its band-stability rule.
  Documentation only — no contract semantics change.
