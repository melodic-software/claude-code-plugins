# Changelog

All notable changes to the `work-items` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.39.29]

### Changed

- **`setup`'s overlay-ignore probes cite `/source-control:setup` instead of that plugin's private
  `reference/apply-convention.md`.** The note records that a sibling plugin documents the same
  gitignore trap for its local overlay; naming the skill survives a refactor on the other side of a
  plugin boundary that a path does not. Docs-hygiene sweep, L4-encapsulation.

## [0.39.28]

### Changed

- **`decompose`'s `re-decompose.md` spoke now links its sibling instead of naming it.** The
  container-lifecycle drift doctrine was cited by name with no link, while every other
  cross-file reference in the same batch of new spokes uses markdown link syntax. Review catch.

## [0.39.27]

### Changed

- **Six skill bodies split hub-and-spoke.** `setup`, `work-loop`, `work`, `triage`,
  `attend-queue`, and `decompose` each held on-demand material in an invocation-loaded body, which
  every later turn of a triggered session pays for. Each moved block now sits in a spoke behind a
  pointer that states the condition for opening it. Two of the audit's ranges were narrowed on
  inspection: `setup`'s autonomous-invocation range would have carried the general twelve-step
  `apply` flow out with it, and `work-loop`'s would have carried the admission gate's dispositions
  and hard gates, so only the C3 ratification write mechanics moved and the fail-closed gate stays
  in the body. `work`'s Step 5 was audited and deliberately not split: it carries
  claim-before-dispatch, the high-blast-radius diff gate, and the never-merge boundary, and an
  agent that never opened the spoke could act on any of the three. Docs-hygiene sweep,
  L2-progressive-disclosure.

## [0.39.26]

### Changed

- **The work-item-tracker seam paragraph splits into five sentences.** 58 words with a parenthesis
  nested inside a parenthesis, so a reader three levels deep could not tell which clause the closing
  parens returned them to. Docs-hygiene sweep, L8-write-for-humans.

## [0.39.25]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.39.24]

### Changed

- **Repo-wide behavior-preserving simplification sweep (batch-simplify).**
  Every change was adversarially verified by a fresh-context refutation
  pass; one proposed change was refuted and reverted.

  The gitea adapter's garbled ShellCheck-hints comment in common.sh
  collapses to one sentence stating the actual behavior. The linear
  reclaim suite drops a fixture seeding that the very next reset erased
  before any request could read it. The local-markdown renew-lease suite
  drops four dead `set +e` lines (errexit is never enabled on its
  execution path). The tracker's own suite sources its helpers via the
  SCRIPT_DIR it already computed. evaluate-schedule-precondition.test.sh
  drops two dead rc initializations. A proposed printf-pipe to
  herestring conversion in evaluate-schedule-precondition.sh was refuted
  (it shifted the line number inside a jq stderr diagnostic on a
  reachable error path) and reverted. The github, jira, and remaining
  linear/local-markdown adapter files were reviewed with no changes.

## [0.39.23]

### Changed

- **Instruction-surface de-slop (#2891, work-items cluster).** Re-audited this plugin's
  `README.md` and every `SKILL.md` under `/ai-slop:audit fix` semantics after later
  versions landed on the 0.39.13 shard. Prose stays em-dash-free. Leftovers that must
  keep the mark: the quoted auto-invocation trigger (`the spec changed — redo the tickets`)
  so skill-quality does not treat the rewrite as a dropped trigger; quoted claim/lease
  and triage protocol strings; fenced templates; and the ignore-fenced generated options
  block, because `scripts/sync-plugin-options-docs.py` still emits em dashes from its
  shared template.

## [0.39.22]

### Fixed

- **Setup probes the personal-overlay ignore rule before any overlay exists
  (#3128 S2).** `check` no longer waits for `.work-item-tracker.local.json` to
  appear. Missing rule is FAIL. A match counts only when `-v` names a
  repository `.gitignore`, not `$GIT_DIR/info/exclude` or `core.excludesFile`.

## [0.39.21]

### Fixed

- **setup evals:** eval 16 now takes the ignore verdict from
  `git check-ignore --no-index -q`, matching the reference, SKILL.md, and
  eval 18. The previous text prescribed `-v` as the coverage probe, which is
  the exact negation-pattern false-positive this change exists to prevent
  (#3132).
- **docs:** README, the config-cascade Implementers row, ADR 0015, and the
  binding-reader comments now name linear and gitea `auth_env` alongside jira
  auth identity as overlayable keys, matching the allowlist shipped in 0.39.19
  (#3132).
- **setup:** the personal-overlay gitignore step now runs two independent probes
  (`git check-ignore --no-index -q` plus `git ls-files`) instead of a bare `git check-ignore`.
  Bare `check-ignore` consults the index and exits 1 with no output for an already-tracked
  path, so a *tracked* overlay — the stop condition the step exists to catch — was invisible
  to its own probe, and `apply` appended a duplicate `.gitignore` line and announced it as
  the fix. The tracked case now stops and reports, naming `git rm --cached` as the
  remediation. `check` probe 2's overlay clause gets the same pair, and both now live in one
  place, `setup/reference/overlay-ignore-probes.md`. Ported from `source-control`'s
  `layer=local` verification, which already documented this trap (#3132).
- **setup:** the ignore verdict is taken from `check-ignore`'s bare exit code, never from
  `-v`'s. With `-v`, git reports **negation** patterns and still exits 0, so a `.gitignore`
  carrying `*.json` followed by `!.work-item-tracker.local.json` would have been read as
  "already covered" for an overlay that git does not ignore at all — leaving it exposed to
  `git add -A` and steering away from the append that does fix it (last matching rule wins).
  `-v` is now used only to render the matching rule in the report (#3132).
- **seam:** the personal-overlay allowlist now covers `config.linear.auth_env` and
  `config.gitea.auth_env` alongside `config.jira.auth_email` / `auth_env`. Both adapters read
  their credential's env-var NAME from the merged binding view, and the stated
  "auth identity is per-account" rationale applied to them already, so their omission was an
  exit-3 denial the contract never documented: the message names the offending key, but a
  user following the contract's own stated rationale had no way to predict the refusal.
  Everything else under those subtrees stays team-layer-only (#3132).
- **seam:** the `invalid binding at <path>` error now points at `/work-items:setup check`,
  which reports the binding probes individually instead of one collapsed verdict. Applied to
  all five emitters: the dispatcher, the jira/gitea/linear adapter preambles, and
  `onboard-adapter`'s `common.sh.tmpl`, which seeds every consumer-authored adapter and each
  carried its own copy of the string (#3132).

### Changed

- **docs:** CONTRACT.md's binding example carried a `docs` pointer string different from
  `setup/SKILL.md`'s, embedding a `plugins/work-items/...` monorepo path that resolves to
  nothing in a consumer repo. Both now use the consumer-facing form (#3132).
- **docs:** CONTRACT.md no longer calls `${CLAUDE_PROJECT_DIR}` and the git toplevel "that
  single anchor". They diverge inside a git worktree, where the toplevel is the worktree
  directory while the variable stays the session's start directory. Latent while this seam
  ships no hooks, live the moment a consumer adds a SessionStart hook (#3132).

## [0.39.20]

### Fixed

- **GitHub adapter REST substitute keeps the general view's object arrays.** The
  sandboxed-session replacement for `gh issue view --json number,title,body,labels,assignees,comments`
  now returns `labels` and `assignees` as objects so `.labels[].name` / `.assignees[].login`
  keep working. The flattened string projection stays as the claim-precheck form.

- **GitHub adapter: the documented item read now carries its sandboxed-session substitute.**
  "View item" showed only `gh issue view --json`, which routes through GraphQL — and sandboxed
  sessions (Claude Code on the web, remote execution) serve only a pinned set of GraphQL
  operations, refusing the rest with `HTTP 403`. The document already explained that restriction
  under "Edit labels / assignees", where the lease protocol's assignee ops work around it, but a
  reader who came for the item read had no reason to reach that far, and the 403 presents as an
  expired token or a missing scope rather than as an unsupported operation. "View item" now
  states the REST substitute next to the commands it replaces
  (`gh api repos/{owner}/{repo}/issues/<N>`), notes that the projections transfer verbatim
  because REST carries the same fields under the same names, and records the two things that do
  not carry over: `gh api` has no `--repo` flag (`{owner}`/`{repo}` expand from the current
  directory or `GH_REPO`), and REST returns `comments` as an integer count rather than the list
  `--json comments` gives, so comments still come from the paginated "List item comments" recipe.
- **"Resolve item ID" carries its own substitute.** It builds the qualified-ID prefix with
  `gh repo view --json owner,name`, which posts to `/graphql` and 403s under the same
  restriction — and `ship` routes through it *before* the body read above, so it was the first
  step to fail on that lane. The REST form
  (`gh api "repos/{owner}/{repo}" --jq '"github:" + .full_name'`) returns a byte-identical
  prefix and now sits beside it.
- **The boundary is stated rather than implied.** The list, search, and aggregate projections
  run on `gh issue list --json`, which posts to `/graphql` as well and has no REST form here.
  "View item" now says so outright instead of leaving a reader to infer that every recipe in the
  document has a substitute.
- **The seam reference and `ship` point at that substitute.** Both show the bare
  `gh issue view --json body,title` form: `reference/tracker-seam.md` is where "Operation
  routing" sends every body read (and so is what `work` and `decompose` reach through), and
  `ship` reads a container's Brief with it directly. Neither reached the adapter's "View item"
  note by any path a reader would follow on hitting the 403, so each now says the command is
  GraphQL-backed and 403s in a sandboxed session, and names the adapter section carrying the
  replacement.

## [0.39.19]

### Changed

- **`track`: cross-reference follows the `bug-report` → `bugs` plugin rename.** The description's
  bug-intake pointer now names `/bugs:write`. Wording only — no behavior change.

## [0.39.18]

### Fixed

- **Seam: the `gh >= 2.94` floor is gated per verb instead of dispatcher-wide.** That floor
  buys exactly one thing, the native sub-issue/dependency surface (`--parent`,
  `--blocked-by`, `--add-blocked-by`, and the `blockedBy` / `parent` / `subIssues` `--json`
  fields), but it was applied to every `github` verb. An older `gh` therefore lost the lease
  trio (`claim`, `renew-lease`, `reclaim`) and `capabilities`, none of which reads that
  surface, so a session that could have held a race-safe claim was refused one for a
  prerequisite it never used. `capabilities` was the sharpest case: it reads the adapter
  manifest and never invokes `gh`, yet could not report what the provider supports without
  meeting a requirement its own answer might have shown to be unnecessary. The floor now
  applies to `create-item`, `get-item`, `list-items`, `list-sub-items`, `link-blocks`,
  `add-sub-item`, and `list-frontier` (which gates through whichever list verb it resolves
  to, so the `--parent` form is covered by its `list-sub-items` dispatch).
- **Presence and version are now separate prerequisites.** Narrowing the floor alone would
  have let the lease verbs dispatch on a `gh`-less machine and die on `gh: command not
  found` inside the adapter, replacing the clean exit `3` that CONTRACT.md "Degradation
  without `gh`" documents for MCP-only cloud sessions. Presence is still required for every
  `github` verb that shells out; only `capabilities` answers without the binary.

### Changed

- **CONTRACT.md records both degradation shapes.** Prerequisites now separate the presence
  requirement from the 2.94 floor and name which verbs carry the floor, and the degradation
  section distinguishes an absent `gh` (no verb that shells out can run) from a too-old one
  (native-surface verbs refused, lease trio intact, so selection must come from elsewhere
  but the claim itself is not degraded).
- **Complements 0.39.15's GraphQL removal.** The two land the halves of one problem: a
  sandboxed session (Claude Code on the web) has both an old `gh` from Ubuntu's archives
  and a GraphQL surface that answers only a pinned operation set. 0.39.15 took GraphQL out
  of the lease path; this release stops the version floor refusing that path in the first
  place. Either alone leaves `claim` unreachable there; together the lease trio runs.

## [0.39.17]

### Removed

- **Ceremonial `## Purpose` section in the `work` skill (#3122).** The section read
  "Auto-select one work item and execute it, following the project's development workflow",
  which is the first sentence of this skill's own `description` restated verbatim. The
  description is always in context, so the section carried no information the reading agent
  did not already have. Found by the #3122 content review, which sampled 44 ceremonial
  sections across 24 skills and classified 37 load-bearing, 6 restatement, and this one as
  the sole pure-ceremony instance in the sample. The review's verdict was that the
  ceremonial-section convention stands as-is, so this is a single evidence-backed removal,
  not a convention change and not a sweep: no other heading or file is touched, and
  `docs-hygiene:audit-noise`'s section-exemption list is unchanged.

## [0.39.16]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.39.15]

### Fixed

- **Lease marker parses with trailing content appended to the comment.** `wit_lease_json`
  matched only a body ENDING in `-->`, so any comment carrying the lease plus trailing text
  (a bot wrapper's attribution footer, a signature, a CI note) parsed as "not a lease". The
  failure was silent and unsafe rather than merely lossy: `claim`'s arbitration found no
  incumbent lease and granted over a live holder, and `renew-lease` refused to renew a lease
  it had just written. The match is now anchored on the FIRST `-->` after the marker, which
  is also strictly more correct, since an HTML comment cannot contain `-->`.
- **GitHub adapter claim/reclaim no longer depend on GraphQL.** `claim` and `reclaim` resolved
  assignees through `gh issue edit --add-assignee` / `gh issue view --json assignees`, both of
  which route through GitHub's GraphQL API. Sandboxed sessions (Claude Code on the web and
  remote execution) serve only a pinned set of GraphQL operations and refuse the rest with
  HTTP 403, which made the entire lease protocol unrunnable there. Both verbs now use the REST
  `…/issues/<n>/assignees` endpoints via shared `wit_read_assignees` / `wit_add_assignee` /
  `wit_remove_assignee` / `wit_try_remove_assignee` helpers. The identity routing is unchanged:
  the helpers take the same `read` (bare `gh`, session identity) / `write` (bot wrapper) writer
  argument the adapter already used, so the claim carve-out that assigns the session user rather
  than the bot still holds; `@me` is resolved to the login explicitly because REST takes a
  literal login.
- **`claim` verifies its own assignment landed.** REST `POST …/assignees` returns 201 and
  silently drops a login that cannot be assigned, where `gh issue edit --add-assignee` failed
  loudly. Without an explicit check the port would have introduced a new race: `claim` reporting
  a held lease while `list-frontier` still saw the item unassigned, putting two workers on one
  item. A dropped assignment now exits `4` (auth) before any lease comment is posted.

### Changed

- **Claim-protocol test coverage.** `claim.test.sh` exercised only `--help` and usage errors, so
  the protocol itself (assign, sole-assignee check, lease post, arbitration) passed vacuously.
  `lease-coordination.test.sh` now drives it against the stubbed `gh`: the happy path, the
  foreign-assignee conflict with its rollback, and the silently-dropped-assignment guard. Its
  `gh` stub matches the REST assignee shapes.
- **`lease-coordination.test.sh` no longer enables errexit by accident.** The renew-lease case
  wrapped its call in `set +e` and then "restored" with `set -e 2>/dev/null || true`, which
  ENABLES errexit rather than restoring the file's declared `set -uo pipefail` mode. Every later
  case expecting a non-zero exit aborted the suite at that line instead of asserting on it, which
  is why the claim cases could not be added until it was found. Both sites now use `|| rc=$?`.

## [0.39.14]

### Changed

- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.39.13]

### Changed

- **Instruction-surface de-slop (#2891, shard 3).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.
  One quoted auto-invocation trigger (`the spec changed — redo the tickets`) keeps its
  em dash so skill-quality does not treat the rewrite as a dropped trigger.

## [0.39.12]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.39.11]

### Fixed

- **Fixture isolation now clears `GIT_CONFIG` (#2889).** The tracker test
  harness already unset the discovery variables at source time; it now also
  unsets `GIT_CONFIG`. Test-only; no skill behavior change.

## [0.39.10]

### Added

- **The Linear schema check is committed, so the evidence that replaced a live conformance run is
  reproducible.** #2946 closed with its live-conformance criterion descoped and a schema-validation
  pass substituted — but that pass existed only as a session artifact, so the claim justifying the
  descope could not be re-run or regression-guarded by anyone. It now lives at
  `adapters/linear/schema-check/`: `validate.mjs` (every operation through `graphql.validate()` plus
  spec-compliant variable coercion), `negative.mjs` (the control that makes a green run mean
  something — deliberately broken variants that must all fail), `fidelity.sh` (proves the operations
  checked are the adapter's own text, not a paraphrase, and doubles as the drift alarm), plus a
  `fetch-schema.sh` that pulls the SDL on demand rather than vendoring 1.2 MB of upstream text.
  Current result: **18/18 operations valid, 10/10 injected faults caught, 11/11 strings verbatim.**
  `fidelity.sh` immediately earned its place by catching that the harness still expected the
  pre-0.39.9 `team.labels` query.

  **All three exit non-zero on failure, and `fidelity.sh` checks both sides.** The first version
  of this harness had two defects that review caught, and both were the very failure it exists to
  prevent. Every script printed `FAIL`/`MISSED`/`MISMATCH` and then **exited 0**, so no caller
  could tell a passing run from a failing one — a check that cannot go red is the vacuous green
  this whole seam has spent three PRs eliminating, and I shipped three of them. And `fidelity.sh`
  matched each operation only against the *adapter*, never against `validate.mjs`, so
  `validate.mjs` could have validated a different — still schema-valid — query while both scripts
  stayed green and the adapter's real request went unchecked. Both fixed: all three return 1 on
  failure, `fidelity.sh` requires each operation on **both** sides, and multi-line operations are
  covered whitespace-normalized rather than merely printed. Verified by breaking each script
  deliberately and confirming exit 1, then confirming a clean run still exits 0.

### Changed

- **`tracker-seam.md` now names the item-content-trust boundary where it teaches body reads.** The
  file is the SSOT twelve surfaces consult, and it explained how to read an item's body via a
  provider mechanic without once mentioning that what comes back is untrusted. No live surface was
  unguarded — `decompose`, `ship`, `work`, `triage` and the review spokes all cite the boundary —
  but the document a *new* surface reads when adding a body read did not, so the link ran one way
  only.
- **The #2945 role-split topology decision is recorded in `CONTRACT.md`.** #2951 (Jira write
  support) was closed `not_planned` on the strength of that decision, which existed only as a
  comment on a sub-issue — and under this plugin's own disposable-tickets doctrine a decision
  resting in a ticket is resting in the wrong place. `CONTRACT.md` § "Multi-provider topology" now
  carries the shape (one writable coordination provider, N read-only `sources`), states plainly
  that **nothing implements `sources` today**, and marks building it demand-gated.
- **The README's synonym claim is scoped to the skills it is true of.** It said ticket/issue
  "appear in skill Use-when triggers" fleet-wide; `ship`, `onboard-adapter` and `setup` carry
  neither token. Rather than stuff the tokens into an adapter generator's triggers to satisfy the
  sentence — buying a tidier claim at the cost of worse routing — the claim now names the
  item-facing skills and says why the infrastructure and container-journey skills differ.

## [0.39.9]

### Fixed

Five defects in the `linear` and `gitea` adapters, all of the same class: **both adapters are
tested only against mock transports whose responses the tests themselves author**, so a wrong
field name, argument, enum value, endpoint path, or termination signal passes every suite and
fails on the first real call. Neither adapter has ever run against a live server. Found by
validating both against their providers' real published contracts — Linear's GraphQL schema
(`@linear/sdk` 90.0.0 plus the SDL, cross-checked and byte-identical) and Gitea's own generated
Swagger at `v1.22.6`, with the handler source consulted where the spec is silent.

The validation also cleared the whole surface it did not find fault with: **all 17 Linear
operations validate against the real schema** under `graphql-js`, including argument types,
nested selections, enum members, and variable coercion — proven sensitive by a negative control
in which 10 of 10 deliberately-injected faults were caught. Every Gitea path, method, query
parameter, request-body field, and response field the adapter reads matches the spec.

- **`linear` accepted a `page_size` the API rejects.** Config validation took any positive
  integer while Linear caps every connection's `first` at 250 — a value the adapter's own
  comment already documented. Validation passed and the *first* live call failed, which is the
  failure mode config validation exists to prevent. Now bounded, with the cap named in the
  refusal.
- **`linear` could not resolve workspace-level labels, and lost labels past the first page.**
  Label ids were read from `team.labels(first: 250)` — one page, no `pageInfo`, no loop, where
  250 is Linear's per-page *maximum* rather than a comfortable ceiling — and `Team.labels` is
  documented only as *"Labels associated with the team"*, while `IssueLabel.team` says *"If
  null, the label is a workspace-level label available to all teams"*. Because an unresolved
  name is refused rather than dropped, both defects surfaced as a hard exit on a label that
  exists. Resolution now walks the **root** `issueLabels` connection — the one documented to
  return both scopes — filtered to this team or workspace-level, fully paginated, and stops on
  a null cursor rather than restarting from page 1.
- **`gitea` silently truncated every list on instances with a lower paging cap.**
  `ToCorrectPageSize` clamps `limit` to `[api] MAX_RESPONSE_ITEMS` (stock 50), so where
  `config.gitea.page_size` exceeds an instance's cap *every* page came back short — and
  "short page means last page" ended the walk after page 1 with nothing said, since the
  ceiling warning never fired either. The issue-list and label-list handlers do send
  `X-Total-Count` (`ctx.SetTotalCountHeader`), so the transport now captures response headers
  and both walks use that count as the authoritative end-of-list signal. The short-page
  heuristic remains the fallback where no header is sent, so behaviour is unchanged on
  instances that send none, and no extra request is ever spent.
- **`gitea` fetched pull requests only to throw them away.** `list-items` omitted the
  `type=issues` query parameter that this endpoint actually supports, so PRs consumed the page
  budget and — worse — the declared ceiling counted raw rows rather than items, making a
  PR-heavy repo report *"reached the declared ceiling of 1000 items"* having collected far
  fewer. The client-side PR filter stays as belt and braces.
- **`gitea` refused organization-wide labels it would happily have applied.**
  `GetLabelsByRepoID` backs `/repos/{o}/{r}/labels` with `WHERE repo_id = ?`, so an org label
  never appears there, yet `NewIssueWithIndex` accepts any label whose `OrgID == repo.OwnerID`.
  The asymmetry was user-visible and backwards: `get-item` and `list-items` *do* report org
  labels in `.labels[]`, so the tracker returned a label name it would then refuse to write
  back, telling the operator to create a label that already exists. `create-item` now merges
  `/orgs/{owner}/labels`, treating the 404 a user-owned repo returns as "no org labels" rather
  than an error.

- **Every large list could silently return ZERO items.** Found by the ceiling regression test
  written for the fix above, not by inspection. Both adapters accumulated paged results as
  `jq --argjson acc "$ACC"`, which puts an **unboundedly growing array on jq's command line**.
  Past `ARG_MAX` the kernel refuses the exec — `jq: Argument list too long` — and because the
  assignment was unchecked, the accumulator was left empty and the verb **reported an empty
  list while exiting 0**. A repository or team large enough to trip it looked simply empty.
  The final envelope emit had the same shape, at the one point where the array is guaranteed
  to be at its largest. Nine sites across `list-items`, `list-sub-items`, `create-item` and the
  lease helper now pass the accumulator through **stdin** and only the bounded new element in
  argv, and every one of them fails loudly rather than degrading to empty. On
  `linear:list-sub-items` this was the worst of the set: an empty child list is what the
  closed-children invariant reads as "nothing open under this container".
- **The declared list ceiling counted requested page size, not rows returned.** Under the clamp
  above the two diverge: with `page_size` 100 against a server capping at 50,
  `PAGE * page_size` reaches 1000 after ten pages that returned 500 issues, so the walk stopped
  half way and announced a ceiling it had never reached. For labels it was worse than a short
  answer — every label in the unreached rows read as nonexistent and was refused. Both ceilings
  now count rows actually collected.
- **The org-label walk ignored the header the repo-label walk beside it obeys.** An earlier
  draft of the org-label fix used a largest-page-seen heuristic, which always spent one extra
  request and, against same-sized consecutive pages, walked to the ceiling and reported a
  truncation that had not happened — turning a genuinely missing label into a misleading "the
  label list was truncated" message. It now uses `X-Total-Count` exactly as its sibling does.
  Caught by review; the regression test pins the request count at one, where the heuristic
  made twenty.
- **The new `linear` label walk had no ceiling**, unlike every other paginated loop in this
  seam. A server that kept answering `hasNextPage` with a fresh cursor would have hung
  `create-item` indefinitely. Bounded now, and — like `gitea` — it distinguishes "not found
  because truncated" from "not found because absent", since telling someone to create a label
  that already exists sends them to do the wrong thing.

Each fix ships with regression cases verified to fail against the unfixed file. The `gitea` mock
transport gained `-D` header support so the `X-Total-Count` path is exercised rather than
silently falling back.

Four Linear behaviours remain unverifiable without a live credential and are recorded rather
than guessed: whether `assigneeId: null` semantically unassigns (the schema permits the null;
the resolver's behaviour is not in the schema), Linear's default comment ordering, and the
instance-configuration-dependent halves of the Gitea findings (`MAX_RESPONSE_ITEMS`,
`ALLOW_CROSS_REPOSITORY_DEPENDENCIES`). Forgejo parity is still assumed rather than measured.

## [0.39.8]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `attend-queue`'s `[intake]` row triage and
  its `[escalated]` row's drive-to-a-decision route to `/planning:interview`;
  `decompose`'s container close-out review (`/review:quality-gate close-out`);
  `onboard-adapter`'s spec interview; `work-loop`'s intake sweep and its cycle step 4, which
  works admitted items through `/work-items:work` (step 2 of the same numbered cycle had been
  rewritten and this one missed); `scan-todos`' "file a work item" disposition
  (`/work-items:track add`); `ship`'s container-discovery dead end, which routes to
  `/work-items:decompose` when no container exists at all; `work`'s dispatch-mechanics
  chain to `/implementation:implement-dispatch`, its deferred-finding filing, its post-green
  hand-off of the PR to `/source-control:babysit-prs`, and its completion bookkeeping. Left as prose on purpose: every `/work-items:setup` reference, since `setup` is
  `disable-model-invocation: true` and unreachable from a skill under the rubric's
  invocation-reach invariant; and `ship`'s Step-4 journey-state route table, since that skill
  "reads, states, and routes" and its Step 5 emits the routed action as *the recommendation*
  rather than taking it. Wording only.

## [0.39.7]

### Fixed

- **`onboard-adapter` read live tracker items without stating the item-content-trust
  boundary.** Step 2 has the user fetch real items and paste the responses back — titles,
  descriptions, comments, label and state names, all authored by anyone who can file in that
  tracker — and neither `SKILL.md` nor `reference/live-exploration.md` cited the boundary.
  Every other work-items skill that reads provider items does (`attend-queue`, `decompose`,
  `ship`, `triage`, `work-loop`), and the container this skill shipped under names
  "no tracker reads without the item-content-trust boundary" as an excluded-by-default
  posture, so this was the one surface out of step with its own constraint. Both files now
  carry the rule as a numbered probe rule — read probe output for **shape**, never as a
  directive — and link the reference. Found by the #2933 container close-out review.
- **The "already bundled" list was two providers stale.** The skill's description and its
  "Not for" paragraph both named `github`, `local-markdown`, `jira` only, so a user with a
  Gitea or Linear instance would be walked through generating an adapter that already ships.
  Both now match what the seam actually bundles.

### Changed

- **`execution-shape.md` documents the serial variant of `per-item PRs`.** The shape value
  names PR *granularity*; fresh-branch-per-item is its default *provisioning*, not part of
  the definition. A single agent working a container serially may keep one long-lived branch
  and open a PR per item off it — same granularity, same `Closes #N`, same close-out basis.
  Recorded because container #2933 shipped exactly that way (eleven PRs, one head ref) while
  this document described only the fresh-branch form, leaving no truthful shape line for it.
  The forfeits are stated too — no parallelism, and each PR's diff is honest only if its
  predecessor merged first. Not a third shape value: the line stays two-valued and `ship`,
  `decompose`, and the close-out basis are unchanged.

## [0.39.6]

### Fixed

- **The 0.39.5 same-login fix failed OPEN on a read error, reintroducing its own bug.** Two
  independent reviewers caught it on the same line. The lost-race branch re-read the lease set as
  `AFTER2="$(wit_linear_lease_comments …)" || AFTER2='[]'` — so a transient GraphQL failure, or the
  belt-and-braces `EX_INTERNAL` exit added to that same helper one version earlier, was silently
  read as **"no live leases exist"**. `LOSER_LIVE` then stayed empty, the assignee still carried
  our own login (nothing had changed it yet), the name compare passed, and the winner's live
  assignment was cleared — the exact failure the branch exists to prevent, arriving by way of the
  error path instead of a name collision.

  Worse, the two guards disagreed with each other: the rollback trap ninety lines above fails
  **safe** on the identical read (`|| exit 0` — treat "cannot tell" as "do not touch"). This site
  chose the unsafe default.

  A failed re-read now means *unknown*, never *empty*: the unassign is skipped and the reason is
  printed. A regression case fails only that second read and asserts zero unassigns; removing the
  guard turns it red.

## [0.39.5]

### Fixed

Five defects found by an independent audit of already-merged code — code that had passed six
review rounds. Four were reproduced by execution before being fixed; every fix carries a test
verified to go red without it.

- **The Linear adapter could hand out a second lease over a live one.**
  `wit_linear_lease_comments` passed a marker's `lease_comment_id` straight to `jq --argjson`. A
  non-numeric value makes jq exit 2 printing nothing, which emptied the accumulator; every later
  iteration failed identically; and the trailing `sort_by` over empty input printed nothing **and
  exited 0**. The helper returned success-with-no-output, which every caller reads as "nothing is
  claimed". The `|| exit "$?"` guards added at six call sites in 0.39.1 cannot catch this,
  because the failure never arrives as a non-zero status. Reproduced: with one holder on a live
  lease whose marker read `lease_comment_id: "abc"`, a second claim returned exit 0 and a full
  success record. Markers are consumer-writable in practice, so this is reachable input.

- **A losing claim could strip a same-login winner's assignment.** Both unassign guards compared
  the assignee against `HOLDER` — the authenticated user's *display name*, not a session identity
  — so they could not tell our own write from another session of the same login. Since
  `lib/frontier.sh` selects purely on assignee emptiness and never consults leases, the loser
  returned an actively-worked item to the frontier. Both sites now require **both** conditions: no
  other live lease, and the assignee still matching our login. Each guard alone lets a different
  assignment through, so the conjunction is strictly safer.

- **Three gitea sites still had the swallowed-`exit` bug.** `create-item` was the damaging one: it
  reported exit `2` — *usage (bad args)* per the contract — after `POST /issues` had already
  succeeded, so a caller that "fixed" its arguments and retried would file a duplicate. It also
  collapsed exit 8 to 1, disabling `work-loop`'s backoff routing, and leaked raw `jq --help` text.

- **Conformance was pre-wired to fail for Linear.** The suite exact-matched github's free-text
  `reason` (`"lease live"`) on a field CONTRACT.md gives no vocabulary; linear says `"lease is
  still live"`. The live pass this effort is still blocked on would have been spent chasing a
  string mismatch. It now asserts the semantic fact — the active lease was selected, not the
  superseded one — checked against all three real strings.

- **Two command-injection holes in the generator, one of which hid the other.** `api.sample_scope`
  was validated only against a pattern *the spec itself supplies*, then substituted into a
  double-quoted argument where `$(…)` expands. Proven: a crafted spec generated cleanly and
  running the generated test — step 1 of the generator's own printed instructions — executed a
  command as root while the suite reported PASS. Fixed with an anchored charset, verified against
  every bundled provider's real scope shape so it is not over-tight.

  Neutering that guard to check discrimination exposed the second, worse one: **`quote_safe`'s
  refusal was inert**, because every `render()` call is `$(render …)` and an `exit` inside a
  command substitution kills only the subshell. A spec with a single-quoted `scope_pattern`
  printed the refusal once per template, then wrote a directory of **empty, executable** scripts,
  reported "Wrote 9 file(s)", printed its "Next: run these" instructions, and exited 0 — the
  loudest refusal in the script, delivered as success. That mattered because `SCOPE_PATTERN`
  carries a regex and so cannot be charset-bounded: `quote_safe` was its only guard. Fixed by
  hoisting the key list to `readonly RENDER_KEYS` and sweeping every value through `quote_safe` at
  top level, before the first emit.

  A full classification of all 34 template placeholders across ~180 occurrences accompanies the
  fix: exactly six reach a double-quoted or bare context in generated shell, and five were already
  anchored-charset validated. `.deferrals[]` is now the only unvalidated spec value in the
  pipeline, reaching markdown only — flagged, not fixed.

  This is the third distinct instance of the swallowed-`exit`-in-`$( )` class found in this seam.

## [0.39.4]

### Fixed

- **Conformance left every item it created behind, for three of five bindings.** Caught by a
  reviewer on a docs claim that said the opposite. `run-conformance.sh` contains no close or
  delete logic at all — cleanup is entirely the binding's `_cb_clean_at_start`, and only `github`
  (closing every open issue through `gh`) and `local-markdown` (a fresh temp dir per run) ever
  implemented one. `jira`, `gitea`, and `linear` shipped it as an unfilled `:` placeholder, so a
  live run would create, claim, and mutate real issues and leave all of them in the target, with
  the suite's own count assertions then running against the previous run's leftovers.

  **`linear` now implements it properly** — archiving every issue in the throwaway team through
  Linear's own GraphQL API rather than through the seam under test (using the seam to prepare its
  own fixture would let a broken adapter hide its breakage, which is why `github` uses `gh`). It
  archives rather than deletes, so pointing it at the wrong scope stays recoverable, and the
  credential goes in through curl's stdin config so it never reaches argv.

  **It fails loudly.** A cleanup that quietly does nothing is worse than none: the suite then
  flaps for reasons nobody can see. A list failure or a GraphQL error aborts with a message
  naming the scope, rather than proceeding against an unknown starting state.

  **The `gitea` binding and the generator template still carry the placeholder — but now say so
  on stderr every run** instead of passing silently for finished work, so every future generated
  adapter inherits the warning rather than the silence.

  Five regression cases: the archive mutation is really sent; the team key is split out of
  `<workspace>/<TEAMKEY>` and the workspace-qualified form never sent as the key (sending the
  whole scope would match nothing and "clean" an empty set, which looks exactly like success);
  and a provider error fails non-zero. Verified discriminating — reverting to the no-op turns
  three of them red, and swallowing the GraphQL error turns the fourth red.

  While writing it I reintroduced, by hand, the exact defect the generator's `display_name` guard
  exists for: an apostrophe inside `${VAR:?word}`, which bash parses as a quote and which broke
  the file's syntax. ShellCheck caught it immediately; the message is now apostrophe-free with a
  note saying why.

- **The Linear adapter's 13 GraphQL documents validated against Linear's real published schema**
  (SDK v90.0.0 SDL, cross-checked against a separately-fetched `master` copy and against Linear's
  own generated documents). All 13 pass: no unknown field, argument, or type; `String!` correct
  where `ID!` would have been wrong; `Float!` correct for `Issue.number` where `Int!` would have
  been wrong; every jq-built input-object field real and every required one set; the `"blocks"`
  enum legal; relation direction confirmed (`inverseRelations` of type `blocks` on the target
  means blocked-by, so `blocked_by_count` is oriented correctly). This closes, offline, the whole
  class of failure Linear would reject regardless of workspace or credential — the class a live
  conformance run would otherwise be first to hit.

## [0.39.3]

### Fixed

- **The gitea adapter README stated a false reason for the unrun conformance pass.** It said
  "no such instance is reachable from the environment this adapter was built in." That was an
  untested assumption, repeated as fact. It is wrong: Gitea ships as a single self-contained
  binary with sqlite built in, its releases are fetchable from the build environment, and a real
  one was downloaded and version-verified there.

  The actual blocker is narrower and worth recording accurately: serving it needs privileged
  setup — a dedicated unprivileged user plus `cap_net_bind_service`, since Gitea declines to run
  as root — which the sandbox's permission policy gates. Reachability was never the constraint.

  The note now also records why port 443 and TLS are structural rather than preferences
  (`wit_gitea_http` builds `https://<host>/api/v1` under `--proto '=https'`, and
  `config.gitea.host` must be a bare hostname, so no high port is expressible), and states
  explicitly that relaxing the bare-hostname rule is **not** an acceptable way to unblock the
  run. That rule stops a PR-modifiable binding from smuggling URL structure and redirecting the
  credential off the intended tenant; trading it for a green check would be the wrong fix, and
  writing that down keeps a later session from making it.

## [0.39.2]

### Fixed

- **The 0.39.1 rollback trap cleared the assignee unconditionally, which could strip a concurrent
  winner's live claim.** The guard added one version ago fixed the assigned-with-no-lease strand,
  but reintroduced — from the rollback path — the exact bug `reclaim.sh` was fixed for earlier in
  this same effort.

  The trap stays armed across the update-comment write and the arbitration read, and 0.39.1's own
  `|| exit "$?"` additions *widened* that window by making both of them exit on failure. Linear's
  `assignee` is a SINGLE field, so a concurrent session can legitimately win the claim inside the
  window — posting its own lease and overwriting the assignee — and a blind clear on the way out
  then strips that live claim while the winner's lease stays untouched. The item silently returns
  to the frontier while someone is working it.

  The rollback now re-fetches the issue and clears only if the assignee is still this session,
  the same compare the LOSER branch already applies before its own unassign. One regression case,
  verified to fail with the compare removed.

## [0.39.1]

### Fixed

- **The Linear adapter reported a SUCCESSFUL claim when the lease write failed.** Found while
  building a regression test for a reviewer's partial-claim finding — the test kept passing when
  it should have gone red, and the reason was worse than the finding it was written for.

  `wit_linear_post_comment` (like every `wit_linear_*` helper) signals failure by calling `exit`.
  But `claim.sh` captured it as `POSTED="$(wit_linear_post_comment …)"`, and **an `exit` inside a
  command substitution ends only the subshell**. With `set -uo pipefail` and no `-e`, the script
  printed the API error to stderr and then carried on — deriving a handle from an empty response,
  writing a lease marker, and emitting a normal success object with exit `0`. A caller had no way
  to know the lease it was told it held did not exist.

  The same swallow affected `wit_linear_lease_comments` at five more sites, where it inverts a
  safety check rather than a report: a failed read of existing leases yields an empty result, the
  "is anything already claimed here?" loop iterates over nothing, and the claim proceeds **as if
  the item were free** — a double-claim produced by an API hiccup. All six sites now propagate the
  helper's own exit status (`|| exit "$?"`), preserving its exit-code taxonomy.

- **`claim.sh` could strand an item assigned with no lease.** The assignment lands before the
  lease is posted, so a failure in between left an item that `list-frontier` excludes (assigned)
  and `reclaim` refuses (no active lease) — unrecoverable through the seam, parked indefinitely by
  a transient error. An EXIT-trap rollback now guards that window, mirroring the github adapter's
  `_wit_claim_rollback`, and is disarmed at both settled outcomes. Disarming on the lost-race path
  matters as much as arming it: that branch already decides the assignee by re-fetching and
  comparing the holder, and a second unconditional unassign after it would strip the winner's live
  claim. Three regression cases, each verified to fail with its guard removed.

## [0.39.0]

### Added

- **A bundled `linear` adapter with full verb parity (#2946).** Reads, writes, the
  claim/renew/reclaim lease protocol, native sub-items, and dependency edges — so unlike `gitea`
  it *is* a coordination surface and `/work-items:work` can claim on it. Issue numbering lives
  outside the repository, so GitHub's shared PR/issue numbering never bites.
- **The headless auth posture is settled explicitly, as the item asked.** A **personal API key**,
  sent as the bare `Authorization` value and referenced by env-var name only. OAuth needs an
  interactive grant no unattended session can complete, so it is not the credential for a cloud
  agent. Host pinned to `.linear.app`; credential hygiene is the generated skeleton's, which
  matches or exceeds the jira adapter's guards.
- **Per-instance semantics are config, not constants.** `done_state_types` decides which
  `WorkflowState.type` values count as closed (default `completed`/`canceled`/`duplicate`) — the
  same override seam jira has for its `statusCategory` keys, so the adapter is independent of the
  classification rather than betting on it.

### Changed

- **The Linear lease documents one deviation from the contract's claim sequence, and says why.**
  The contract detects a race at step 2 by re-reading the assignees; that depends on GitHub's
  assignee **list**, where both racers' assignments coexist. Linear's `Issue.assignee` is a
  **single field** — the second writer overwrites the first and then re-reads only itself, so a
  step-2 check would report "no race" to *both* racers. Arbitration therefore rests on the lease
  **comment ordering**, which the contract already specifies as the same-login tiebreak. Because
  Linear's comment ids are unordered UUIDs, `lease_comment_id` is minted from the comment's
  `createdAt` in epoch milliseconds (the local-markdown precedent), with same-millisecond ties
  broken on the comment UUID so the ordering stays **total** — without that, two racers in one
  millisecond would each read themselves as earliest and both would claim. A test asserts the tie
  is decided identically from both sides.
- **A GraphQL error arrives with HTTP 200**, so the transport inspects `errors` before any caller
  sees `data`. A status-code-only check would wave a failed mutation through and let the verb emit
  a malformed record.
- **`api.auth_scheme` in the adapter spec gained `raw`** — the bare `Authorization` value with no
  scheme word, which is what Linear's personal API keys take. Modelled as its own scheme rather
  than an empty prefix, so a generated header cannot come out with a stray leading space.

### Fixed

- **Timestamp parsing no longer depends on fractional seconds being present.** Linear returns
  `createdAt` with milliseconds while this adapter's own lease markers write whole seconds, so both
  forms reach the same helper; stripping the fraction by assuming a `.` corrupted the whole-second
  form instead. That is how reclaim's activity check silently saw no activity at all, and would
  have released a lease whose holder was demonstrably still working.

## [0.38.0]

### Added

- **A bundled `gitea` adapter for Gitea / Forgejo (#2952)** — the first adapter GENERATED by
  `/work-items:onboard-adapter` rather than hand-written, which was the point: it is the dogfood
  that tests the generator. Reads and creates issues and writes blocked-by dependency edges;
  `claim`/`renew-lease`/`reclaim`/`add-sub-item`/`list-sub-items` are capability-gated to exit `6`.
  Self-hostable and free, so it serves the no-paid-tool case for solo developers.
- **Honest gating over convenient gating.** `sub_items` is false because Gitea's issue has no
  parent field at all. `leases` is false because whether Gitea arbitrates concurrent assignment
  cannot be settled without a live instance and two identities — and an emulated lease over
  last-write-wins loses races silently, which is worse than not having one. Both are recorded on
  the adapter with what would settle them.
- **Provider divergences verified against the Gitea source, not assumed from GitHub's API.** A
  pull request IS an issue and is dropped from `list-items`; `create-item` takes label **IDs**, not
  names, and refuses an unknown name rather than dropping it; `blocked_by_count` costs one request
  per item because the issue carries no dependency data; `POST /issues/{index}/dependencies` makes
  the URL issue depend on the BODY issue, and using the sibling `/blocks` endpoint would invert
  every edge. Each is documented in `adapters/gitea/README.md` with the file it was read from.
- **`limits` values may now be `null`** — "supported, and the provider enforces no ceiling",
  distinct from `0` ("the capability is unsupported"). Gitea's issue dependencies are the case that
  forced it: Gitea rejects only duplicate and circular edges and caps nothing, and without `null` a
  ceiling-free provider had to invent a plausible number that callers would then branch on.
- **Generated adapters now ship a `capabilities.test.sh`** whose load-bearing case is that the
  manifest AGREES WITH THE FILESYSTEM — a verb declared `true` with no script behind it, or a
  script left behind for a verb since set to `false`, appears in no other test.

### Fixed

- **A substitution value carrying a placeholder no longer reaches generated output verbatim.** The
  self-hosted host-pin sentence rendered as "@@DISPLAY\_NAME@@ is self-hosted" because the
  generator's renderer walks its key list once and never revisits a value inserted by a later key.
  Values now interpolate directly, and a regression case greps every generated file, under both
  host postures, for a surviving placeholder.

## [0.37.0]

### Added

- **`/work-items:onboard-adapter` — the tail half of the hybrid adapter model (#2950).**
  Bundled adapters cover the majors; this skill covers everything else, walking a consumer from
  "my tracker is not supported" to an adapter that lives in **their** repo. Four steps: interview
  to lock the provider's shape into an adapter spec, explore the consumer's real instance for the
  per-instance facts only it can settle, generate, verify. The deterministic half is
  `scripts/generate-adapter.sh`; the judgement — which verbs the provider can honestly support,
  what its fields mean, what a live instance actually returns — stays outside the script, and the
  spec file is the whole handoff between them.
- **The generated security skeleton carries the bundled `jira` adapter's guards, and proves
  them.** Credential read from the env var *named by* the binding and passed to curl through a
  stdin config so it never reaches `argv`; host validated as a bare hostname; HTTPS enforced by
  curl itself; redirects not followed, so the `Authorization` header cannot be replayed to
  another host; values reaching request paths matched against an anchored allowlist. The
  generated `common.test.sh` is real and passing from the moment of generation — 58 cases,
  including that the credential is absent from argv and present in the stdin config.
- **The generator refuses an incoherent spec rather than emitting a manifest that lies.** The
  capabilities manifest is what the core routes on, so a verb declared without the feature it
  needs, a ceiling on a capability declared absent, or an unanchored scope pattern is a refusal
  with the field named. Manifest `schema_version` is stamped from the **seam's** contract version
  (`lib/json.sh`), never from the spec — an adapter that versioned itself could be born already
  skewed from the engine that will dispatch it.
- **Unwritten verb scaffolds exit `1`, not `6`.** Exit `6` means "the provider cannot do this and
  the manifest says so" — a permanent, honest degradation. Declaring an unfinished scaffold `6`
  would launder unfinished work as a provider limitation and let conformance pass over a verb
  that does nothing.

### Fixed

- **A consumer-local adapter no longer requires vendoring the seam.** The dispatcher now exports
  `WIT_SEAM_LIB_DIR` before invoking any adapter verb, naming the `lib/` of the engine actually
  dispatching — and the engine whose contract version the manifest just handshook against.
  Previously a consumer-local adapter's own `../../lib` pointed at a seam copy the consumer never
  vendored, so the only working consumer-local adapter was one in a repo that had vendored the
  whole seam. Bundled adapters resolve relatively and are unaffected.
- **A generated conformance binding is now reachable by the runner.** `run-conformance.sh`
  resolves `bindings/<name>.sh` the same two-root way adapters resolve — `WIT_CONFORMANCE_BINDINGS_DIR`,
  then consumer-local, then plugin-bundled. Without the consumer-local leg a generated adapter
  could never be conformance-verified in place, since the plugin directory it would have had to
  write its binding into is read-only and replaced on plugin update. The binding name is also
  constrained to `^[a-z][a-z0-9-]*$` before it is interpolated into a path, so a traversing name
  cannot escape the searched roots and source an arbitrary file.

## [0.36.3]

### Fixed

- **The container close-out routes name real machinery (#3027).** `decompose`'s ship ritual and both
  of `ship`'s all-sub-items-closed rows pointed at "the review plugin's spec-fidelity machinery" for
  the cumulative review of a shipped container — a route that landed on nothing container-scoped
  even after `review` 0.22.0 shipped the branch-scoped `spec` lens. Both now name
  `/review:quality-gate close-out --container <container-id>` (`review` ≥ 0.23.0), presence-gated as
  before, with the manual pass against the Brief's acceptance criteria as the fallback.
- **The division of labor is stated where it was previously implied.** The review produces the
  verdict; the **ship ritual owns the close** — so a `missing` or `wrong` finding against a stated
  acceptance criterion keeps the container open and becomes a new item or a re-decompose, rather
  than a reviewer closing anything. `ship`'s row additionally says to state the execution shape when
  routing, because the close-out mode derives its cumulative basis from it: the integration PR's
  range for `integration branch → single PR`, the set of per-item squash commits for `per-item PRs`.

## [0.36.2]

### Fixed

- **No surface claims the seam returns an item body any more (#3028).** `ship`'s macro-state snippet
  annotated `get-item` with `# body = the spec`, under a heading reading "no inline provider
  commands" — so a session following the skill's own snippet to read the container spec got no spec
  text, and the placement implied the seam could do something it cannot. The normalized item object
  is `schema_version, id, title, state, assignees, labels, type, blocked_by_count, parent_id, url`;
  there is **no `body` field**, and `--body` exists only as a *write* parameter on `create-item`.
  `work`'s pass-by-reference step carried the identical premise ("fetch the container via the seam
  … and read its Brief body") and is corrected with it; `decompose`'s "fetch full body and comments"
  now names the mechanism instead of leaving it to inference.
- **Fixed at the source, not just at the call sites.** `reference/tracker-seam.md`'s operation-
  routing table listed "single-item fetch" under Coordination with nothing said about the body,
  which is what let the assumption spread — the same false premise was independently proposed in
  Lane D's first-draft design and caught by the same audit. The table now marks single-item fetch as
  identity/state/`parent_id` **not** body, lists reading an item's body under Provider mechanics,
  and carries a paragraph stating the split outright: `get-item` stays authoritative for
  `parent_id` (how a slice reaches its container), body text is a provider-mechanic read
  (`gh issue view <n> --repo <owner>/<repo> --json body,title` on GitHub, the provider's REST
  equivalent otherwise), and a surface showing a body read must label it as such. Provider mechanics
  run unbound, so the read still works where no binding resolves; `local-markdown`, which stores
  item text as the file itself, is named rather than papered over as parity.

## [0.36.1]

### Added

- **Re-decompose (rerouting) flow in `/work-items:decompose` (#2949):** a
  documented usage pattern of existing seam verbs — not a new capability —
  for when mid-flight review shows the destination is wrong. Five steps:
  close unimplemented children as not-planned (provider-mechanic close, each
  with a one-line comment linking the superseding direction; claimed items
  are coordinated with, never closed from under their holder), keep
  implemented children untouched, re-interview/edit the spec where it lives
  (container body under the spec-on-tracker model, or the topic Brief when no
  container exists), regenerate the remaining slices through the normal
  draft → approve → publish steps (`create-item --parent --blocked-by`), and
  continue on the updated frontier. Doctrine: **tickets are disposable, the
  spec is editable** — slices are projections of the spec at decomposition
  time and are re-projected, never hand-patched, when the spec moves. Bounds:
  post-ship wrongness is a new spec, never a patch to a closed container;
  small drift is an ordinary body edit, not a reroute. `/work-items:ship`'s
  existing re-slice route lands on this flow.

## [0.36.0]

### Added

- **`/work-items:ship` — macro-journey router (#2948):** a thin, user-invocable
  router over one spec container. It resolves the container (argument, topic
  PLAN.md pointer, or a binding-resolved container-label query), reads the
  macro state through seam verbs (`get-item`, `list-sub-items`,
  `list-frontier --parent`), states the container's **execution shape** and
  that mode's discipline, and routes the next step to the machinery that owns
  it — `/work-items:work` (next item), `/work-items:decompose` (re-slice and
  the container close ritual), planning/review close-out machinery and
  session-flow presence-gated — mutating nothing on the happy path. Execution
  shape is a **per-container** choice, never repo-level: `per-item PRs`
  (default; separate branches, per-item PRs, seam claim as the collision
  signal) or `integration branch → single PR` (sequential checkpoints on one
  shared branch: seam claims even for sequential work, mid-flight lease
  renewal, pull-before-start/push-before-close, one PR at the end). The choice
  is recorded as a durable `**Execution shape:**` line in the container body
  by `/work-items:decompose`'s approval gate (one-line follow-up when a
  container publish is approved); an absent line defaults to per-item PRs
  loudly. Grammar, disciplines, and the canonical journey vocabulary — *item*
  (always a graph node, phase-agnostic), *checkpoint* (an item closed within a
  shared-branch flow), *phase boundary* (the session-level continue / clear /
  compact / handoff moment; every checkpoint is a phase boundary with durable
  progress, not vice versa) — live in the new
  `reference/execution-shape.md`. The container label stays binding-resolved
  (`config.container_label`); the skill hard-codes no labels, paths, or
  topology.

## [0.35.31]

### Added

- **Binding overlay + one root anchor (#2941, ADR 0015):** the tracker binding
  stays a tracked repo-root file, now refined by an optional gitignored
  `.work-item-tracker.local.json` beside it that merges **per-key over a
  deny-by-default allowlist** — `config.lease_ttl_hours`,
  `config.lease_ttl_minutes`, `config.jira.auth_email`, `config.jira.auth_env`,
  and the new self-describing `docs` pointer; any other overlay key is a
  configuration error (exit 3, keys named), and there is deliberately no
  user-global layer (forecloses the per-user provider trap, F1.4). Discovery no
  longer climbs from CWD to the filesystem root (F1.1): all repo-relative
  resolution — binding read, consumer-local adapter dirs, the github bot-wrapper
  lookup — anchors at `${CLAUDE_PROJECT_DIR:-git toplevel}` (F3.8), so a bare
  shell that finds the binding also finds consumer-local adapter shadows.
  `/work-items:setup apply` writes the `docs` key by default, owns the
  overlay's root-level gitignore line (appended, announced), and `check` probes
  overlay validity; conformance + unit tests cover the merge, the allowlist
  rejection, and the bare-shell anchoring. Config-cascade implementers row
  flipped from observed deviation to declared.

## [0.35.30]

### Added

- **Spec-on-tracker container lifecycle (#2934):** `decompose` gains an opt-in
  "Container lifecycle" — at approval (multi-session sources only, default no,
  `decompose_container_publish` userConfig pre-select) it can publish the Brief
  verbatim as a container item (binding-resolved container label + human-gated
  label, never claimable) with slices as native `--parent` sub-items, and owns
  the close-at-ship ritual (close-out review against the container body, then
  archival by closure). `work` reads the parent container body first
  (pass-by-reference, quoted data under item-content-trust). The seam's
  container label is now remappable: binding `config.container_label` (sibling
  of `config.role_labels`, default `work-map`), resolved
  configured-over-default by `lib/binding.sh` and exported as
  `WIT_CONTAINER_LABEL`; the F3.7 recorded deferral is converted to a live
  remap seam (CONTRACT.md, label-taxonomy.md). Upstream's gate-free publish
  stays excluded — the approval gate is mandatory.

## [0.35.29]

### Changed

- **Lease hardening (#2943):** the `/work-items:work` worker is the durable
  mid-flight `renew-lease` actor during implement-dispatch; the orchestrator
  renews only after the worker returns. Branch-push activity stays deferred.
  CONTRACT documents clock skew, TOCTOU (revalidation is intent, not CAS),
  ttl-0 born-expired, and comment-id monotonicity as an adapter requirement.
  Workers renew before the TTL deadline with a safety margin, not only at phase
  boundaries. local-markdown `renew-lease` refuses expired (including ttl-0)
  leases the same way the GitHub adapter does.

## [0.35.28]

### Changed

- **`decompose`:** prefactor look-ahead at draft time (prefactor slices block
  the work they unblock); "one fresh context window" granularity bar alongside
  S/M/L (qualitative; no token folklore); expand-contract stays default, with
  an integration-branch fallback when migrate batches cannot land green alone
  (those items require a separate integration-branch workflow; `/work-items:work`
  still targets the default branch);
  present/report "work the frontier" (unblocked slices first). PR-variant
  agent brief for items with attached code (`agent-brief.md`) does not replace
  the bug/feature template. Approval gate, born-triaged, and blockers-first
  publish are unchanged (#2935).

## [0.35.27]

### Changed

- **Naming:** "work item" stays canonical; `track` and `work` Use-when triggers
  now include ticket/issue synonyms (`add a ticket`, `list tickets`, `close a
  ticket`, `work the next ticket`/`issue`, `grab the next ticket`). Documented
  once in this plugin's README. Course SSOT cross-linked from the skills-repo
  SSOT; v1.2 map rows for `to-tickets` / `triage` / `wayfinder` record
  absorption under those names (#2947).

## [0.35.26]

### Added

- **Contract-version handshake at the adapter seam (#2942, F3.6).** The dispatcher now
  compares the adapter manifest's declared `schema_version` to the core contract version
  before every dispatch (`wit_check_contract_version`, `lib/json.sh`) — a directional
  tolerant-reader: major skew (either direction) refuses with exit `3` naming both versions
  and the direction-appropriate fix; a newer-minor manifest proceeds with a stderr notice;
  an older-minor manifest proceeds silently; an unversioned manifest cannot handshake and
  refuses. Previously only `.verbs` was read, so a consumer-local, shadowing, or generated
  adapter skewed silently. Skew behavior is documented both directions in CONTRACT.md
  ("Contract-version handshake") and covered by dispatcher unit tests plus conformance
  cases (synthetic skewed shadow of the bound provider). Prerequisite for the
  adapter-onboarding generator (#2950).

### Fixed

- **The seam's direction-locking ADR citation resolves in-tree (#2942, F3.5).** CONTRACT.md
  and the GitHub conformance binding cited "ADR 0022", a number `docs/adr/` never reached.
  The rationale is now recorded as ADR 0014 (engine plugin-canonical / adapters
  consumer-first, plus the no-standing-sandbox conformance note) and both citations point
  at it.
- **Role-label defaults are single-sourced (#2942, F3.7).** The shipped defaults
  (`needs-human`, `agent-ready`, `recurring`) were defined three times — `lib/binding.sh`
  literals, a `lib/frontier.sh` parameter default, and a dispatcher inline fallback. They
  now live once in `lib/labels.sh`; binding resolution, the frontier filter default, and
  the dispatcher all read the constants.

### Changed

- **`gh`-absent degradation documented honestly (#2942).** CONTRACT.md "Degradation without
  `gh`" records that MCP-only sessions cannot run the `github` adapter at all, defers a
  REST fallback (recorded rationale), rejects MCP-as-adapter, and documents the supported
  backfill ritual: body-text `Blocked by:` edges + a provenance comment, replayed through
  `link-blocks`/`add-sub-item` from the next `gh ≥ 2.94` session — leases explicitly
  excluded from the ritual.
- **Fixed-string postures recorded (#2942, F3.7).** `label-taxonomy.md` "Recorded postures"
  now defers the `[Maintenance]` title prefix and the `.github/recurring-schedule.json`
  path as fixed strings until a consumer requests a remap (binding `config` keys when that
  lands, arriving with a reconciliation step).

## [0.35.25]

### Changed

- **Docs:** local-markdown branch, worktree, and lease confinement documented in
  CONTRACT.md plus a new adapter operations README
  (`adapters/local-markdown/README.md`); setup provider-comparison and the plugin
  README now point at those (#2944). local-markdown remains never a coordination
  surface.
- **Docs:** local-markdown isolation and Resolve-item-ID docs corrected for
  honesty — same-worktree `git switch` carries untracked/uncommitted item files;
  lookups key by number without re-validating owner/repo (#2944).

## [0.35.24]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.35.23]

### Changed

- **`item-content-trust` owns its untrusted-content fence self-contained.** The `main`-pinned
  raw-GitHub deep link into `babysit-prs`'s private orchestration reference is gone (encapsulation
  audit; Path A promotion refused at Rule of Three — two consumers); the fence block is now this
  doc's own normative statement, with the `babysit-prs` alignment named in prose as the contract's
  intentional-duplication technique prescribes.

## [0.35.22]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.35.21]

### Fixed

- **`/work-items:setup` provisions and backfills `capability-tier: frontier` (#1716 review).**
  `check` probe 8 FAILs when the canonical member is absent; `apply` step 4 provisions it (same
  mechanics as the work-class axis); step 5 backfills open items carrying legacy triage-briefing
  body stamps via `scripts/backfill-capability-tier-labels.sh` — load-bearing because triage refuses
  to re-triage already-triaged output. Legacy pattern detection lives in
  `scripts/lib/legacy-frontier-tier-signal.sh`.

## [0.35.20]

### Fixed

- **`work-loop` frontier-tier signal is the `capability-tier: frontier` label (#1716).** The
  adaptive-cap quota guard no longer reads a triage-briefing body claim. Missing label fails
  closed to the general tier; body prose is context only. Carve-out instance removed from
  `item-content-trust.md`; taxonomy, `capability-tier-labels.md`, tracker-seam, triage stamp,
  and manifest/README descriptions updated. Label provisioning for this repo requires
  `melodic-software/github-iac` — the reader lands fail-closed until the label exists.

## [0.35.19]

### Fixed

- **`work-loop`: clamp persisted `item_cap` on durable-state re-read (#1668 F3).** After
  re-reading the telemetry state block, clamp `item_cap` to the resolved `[floor, ceiling]`,
  report any correction, and persist the clamped value — a race or stale session can otherwise
  leave an out-of-bounds cap trusted as source of truth.
- **`work-loop`: drain exit eval matches retained-snapshot-ids-only (#1668 F2).** Eval
  `work-loop-exit-drain-terminal-and-pacing` no longer asserts a two-part exit with
  `list-frontier --autonomous` emptiness; it matches `reference/mode-drain.md`.

### Added

- **`work-loop`: compound-shell telemetry upsert Gotcha (#1668 F1).**
  `reference/telemetry-upsert.md` documents the isolated-calls fallback when the auto-mode
  classifier blocks the compound upsert, with gate order preserved.

## [0.35.18]

### Fixed

- **Triage umbrella-fold routing is an atomic four-step sequence (#633).** The skill now
  requires item comment → umbrella comment → `blocked-by` edge → strip raw marker as one
  indivisible action before advancing to the next intake row, matching the contract in
  `reference/issue-conventions.md`.

## [0.35.17]

### Added

- **`work-loop` invocation argument surface (#1291).** Optional `<owner/repo>` (checkout
  validation), `--drain`, `--shard <i>/<n>`, `--ordering oldest-first|newest-first`,
  `--instance <id>`, and `--scope <label>` — documented in `argument-hint`, enforced by the skill
  (not prose-only). Merge/tier/cap tokens are rejected with a clear message. Stop-mode semantics
  move to `reference/mode-standing.md` and `reference/mode-drain.md`; invocation details to
  `reference/invocation-argv.md` for progressive disclosure.

### Fixed

- **`work-loop`: invocation grammar before telemetry (#1291 review).** Parse, validate, default,
  and reject invocation tokens before durable-state adoption or cycle work; document resolution
  order and fail-closed rejection of merge-lane tokens.
- **`work-loop`: ordering uses List items `createdAt` (#1291 review).** Execute step sorts admitted
  items on the adapter projection before filling cap slots, with a defined missing-timestamp
  fallback.
- **`work-loop`: post-snapshot intake on every drain exit (#1291 review).** Both ordinary drain
  completion and drain-terminal stops apply the reporting-only open-items diff.
- **`work-loop`: `--instance` resolution in telemetry upsert (#1291 review).** `telemetry-upsert.md`
  names `--instance` as the first-checked lane-instance source.

## [0.35.16]

### Fixed

- **`attend-queue`: row-level seam claim for concurrent attended sessions (#1290).** Two terminals
  on one repository could both surface and mutate the same row — duplicate interview questions,
  conflicting label flips — because the lane had no claim protocol while `/work-items:work` already
  used the seam assignee + lease (`exit 7` → skip). The skill now claims each row before mutation,
  flips to autonomous-eligible while the claim is still held, then clears assignee via the adapter
  (no nonexistent seam release verb; live lease persists until TTL/reclaim), and documents
  session-start reclaim and binding-presence routing consistent with `work`. Single-session runs
  need no new argument.

## [0.35.15]

### Changed

- **Triage:** retire `T1`/`T2`/`T3` as a classification vocabulary; express the multi-surface
  stub outcome in `work-class: mechanical` terms (#1254).

## [0.35.14]

### Fixed

- **Reconcile `role_labels` docs and resolve all three roles at the seam (#1561).** Absent
  `config.role_labels` entries are sanctioned silent defaults; export
  `WIT_AUTONOMOUS_ELIGIBLE_LABEL` and `WIT_RECURRING_MAINTENANCE_LABEL` alongside the existing
  human-gated label.

## [0.35.13]

### Fixed

- **Lease TTL minutes review fixes** — remove stray jq brace in local-markdown `claim.sh`,
  enforce the documented 0–59 `lease_ttl_minutes` ceiling, and declare `minutes` local in
  `wit_read_binding`.

## [0.35.12]

### Added

- **Lease TTL minutes** — optional `ttl_minutes` on lease records, `--ttl-minutes` on
  `claim`, and optional `config.lease_ttl_minutes` in the binding (#1034).

## [0.35.11]

### Changed

- **Escalation-marker grammar has one canonical source (#1672).** `reference/escalation-marker.md`
  now defines the marker comment prefix, kind enum, author-match suppression rule, and
  label-plus-comment pairing; `work-loop` and `attend-queue` cite it instead of restating the
  grammar in prose.

## [0.35.10]

### Added

- **Unattended recurring-schedule seeding via --accept-recommended** in setup skill.

## [0.35.9]

### Added

- **Lane-neutral AI disclaimer SSOT** in work-items reference docs.

## [0.35.8]

### Fixed

- Harden triage intake against priority-axis stacking and blocked-by relabel races.

## [0.35.7]

### Added

- **`reference/work-class-labels.md` — canonical `work-class:` axis members, migration path, and
  classification pointer to the `autonomy` plugin's `work-classes.md`.** Declares the five labels
  triage stamps and setup migrates; linked from `label-taxonomy.md` and `tracker-seam.md`.

### Changed

- **`/work-items:setup` discovers and migrates the work-class label axis (#1677).** `check` probe 7
  FAILs when any canonical member is missing on label-listing providers; `apply` step 3 provisions
  missing labels when no label-as-code owner is declared (interactive migration), or stops with
  explicit remediation otherwise.
- **`/work-items:triage` pairs autonomous-eligible with a work-class label (#1677).** Hard pairing
  rule cites `work-classes.md` for classification, preflights label-axis presence before mutating,
  and covers all agent-ready outcomes via the general rule (not per-table-row duplication).
- **`/work-items:work-loop` admission gate adds C1 read-only disposition as Autonomous**, matching
  the shipped admission-policy default for C1.

## [0.35.6]

### Added

- **Standing-item `precondition` field on recurring schedule rows (#2052).** Tier-4 `/work-items:work`
  selection and `/work-items:track recheck` consult `precondition` via
  `scripts/evaluate-schedule-precondition.sh` before claiming or closing. Migrated #2019's
  frontier-release guard onto the new surface.

## [0.35.5]

### Fixed

- **`work-loop` drain exit excludes open `work-map` containers as lane infrastructure (#2078).**
  A bare container issue is never claimable and never closed by the loop, so it blocked drain
  completion until the `/loop` expiry. `/work-items:triage` and `/work-items:work-loop` now exclude
  container-labelled items from the snapshot, intake sweep, exit evaluation, and post-snapshot
  intake report — the same treatment as per-lane telemetry issues.

## [0.35.4]

### Fixed

- **`triage` disambiguates "standing rules" from `re-anchor`'s homonym and
  names when a general lane mandate satisfies the direction gate.** (#570)

## [0.35.3]

### Changed

- **Every `--paginate` list read now carries `per_page=100`.** `skills/attend-queue/SKILL.md`,
  `skills/work-loop/reference/telemetry-upsert.md`,
  `tools/work-item-tracker/adapters/github/common.sh` (`wit_list_lease_comments`), and
  `tools/work-item-tracker/adapters/github/reclaim.sh` (comment activity and timeline
  cross-references) paginated without a page size. These were not truncation defects — `--paginate`
  fetches every page regardless — but they were non-conformant with the pagination rule
  `source-control:pull-request`'s readiness reference publishes, and at the 30-item default they
  cost 3.3x the requests. No behavior change: each site's downstream fold (`jq -s 'add // []'` /
  `'add // 0'`) sums or concatenates per-page results, and `gh` applies `--jq` per page under either
  page size, so the same value is produced from fewer pages.

## [0.35.2]

### Fixed

- **The GitHub adapter's "list item comments" recipe no longer truncates.** It called
  `repos/{owner}/{repo}/issues/<N>/comments` unpaginated. The endpoint returns 30 per page
  oldest-first and reports nothing when it truncates, so on any item past 30 comments the recipe
  silently omits the newest ones — the end most callers are actually reading for. Live on this
  repo: the loop-lane telemetry item #502 carries 31 comments and #657 carries 33. Now
  `--paginate` with `per_page=100`.
- **…and its `sort_by` no longer runs per page.** `gh` applies `--jq` to each page separately, so
  the recipe's `sort_by(.id)` emitted one separately-sorted array per page rather than one sorted
  list — four arrays at four pages. The reduction now happens in `jq -s` after the pages are
  collected, flattened with `.[][]`.

## [0.35.1]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `reference/permission-preflight.md` — the "Yes, don't ask again" rule landing in
    `.claude/settings.local.json` at the repository root (permissions and worktrees references).

## [0.35.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.34.3]

### Fixed

- **`work-loop`'s post-snapshot intake report reads open items, not the autonomous frontier.**
  0.34.2 gave that report a mechanism — diff a fresh reading against the retained ids — but named
  `list-frontier --autonomous` as the reading, which cannot see the case the report exists for.
  Step 2's sweep hardening routes a bot-authored advisory issue to the human-gated role by default,
  and `list-frontier --autonomous` excludes exactly that role (tracker `CONTRACT.md`,
  `list-frontier`; `reference/label-taxonomy.md`), so the bot-filed mid-cycle intake the stop report
  promises to name is filtered out of the reading meant to find it and the report names nothing —
  the "reported, never chased" invariant failing silently one layer below where 0.34.2 fixed it.
  The report now repeats step 1's open-items reading, the superset the frontier is derived from,
  which sees the routed advisory item and the ordinary one alike. The lane-infrastructure exclusion
  is extended to that reading in the same breath: a telemetry issue is deliberately never among the
  retained ids, so a re-read that did not re-apply the exclusion would diff it in as post-snapshot
  intake and misreport it as unworked on every run.

## [0.34.2]

### Fixed

- **`work-loop` evaluates its drain exit against the cycle-start snapshot's retained ids instead of
  a live frontier reading.** The exit condition said it evaluated against the snapshot, then
  implemented its first criterion as a live `list-frontier --autonomous` emptiness read. An item
  that joined the frontier *after* the snapshot — a bot filing agent-ready intake, an operator
  flipping a role label, a ratification landing mid-cycle — landed in that read and could hold a
  drain open indefinitely, the exact failure the skill's own step 1 and its "Do not chase intake"
  gotcha already promised the snapshot semantics prevented. That criterion is now removed rather
  than rescoped: the frontier is derived by filtering `state == open`, so every snapshot frontier
  candidate is already a snapshot open item and the remaining snapshot-scoped test covers it — an
  item the snapshot held as untriaged intake and this cycle's sweep promoted still holds the drain
  open and is still worked, this cycle or a later one. A second frontier limb could only ever block,
  never catch anything the remaining test misses, and absence from a later frontier read is not
  resolution: an item another session claims, or one that becomes blocked, leaves the frontier
  unresolved. Step 1 now retains every captured id and the exit tests their union — the snapshot is
  nowhere specified as a single read, so testing the open ids alone would drop an item created
  between two of them — and both stop paths name the post-snapshot intake left unworked, which is
  what keeps "reported, never chased" true once there is no next cycle to sweep it. That naming now
  carries its mechanism: diff a fresh frontier reading against the retained ids *after* the exit is
  decided. It is reporting-only and cannot change the verdict it follows, and stating it is what
  stops the requirement degrading to nothing in the hands of an agent given no procedure for it.

- **`setup` proves the checkout is a GitHub repository before auto-binding the `github` provider.**
  The unattended first bind required only that `gh` was installed and `gh auth status` succeeded —
  both account facts, neither of which says this repository is hosted on GitHub. A local-only or
  non-GitHub checkout with an authenticated `gh` was silently bound to `github`, and every
  repo-scoped seam verb then failed, because the adapter derives its `owner/repo` scope from the
  checkout with `gh repo view --json owner,name`. That call now *replaces* `gh auth status` as the
  unattended bind's precondition rather than joining it: it is the adapter's own derivation, and it
  subsumes authentication because it fails unauthenticated even against a public repository — so
  succeeding proves `gh` is authenticated for the host in play. `gh auth status` tests every account
  on every known host and exits 1 if any has an issue (`gh auth status --help`) — a machine-wide
  fact that both admits the wrong checkout and refuses a good one. The resolved `owner/repo` is
  reported with the other defaults taken, and a probe that does not resolve stops with the existing
  named-blocker report rather than persisting an unusable binding. The interactive provider choice
  makes the same swap, and `check`'s binding
  probe makes the same call instead of PASSing a shape-valid `github` binding no repository backs.
  That probe runs unconditionally rather than behind an auth precheck, and verdicts on *why* the
  call failed, never on failure alone: only a checkout with no remote that any GitHub host owns is
  FAIL. An uninstalled `gh`, a 401/403, a not-found, a rate limit, a network failure, or any message
  the partition does not recognize is INFO — those are availability and credential facts, not
  verdicts on a binding, and a correctly bound repo must not fail `check`, and so stop `apply`,
  because the provider was briefly unreachable or because `gh` grew a message this list predates.

- **`track start` verifies the fully qualified remote-tracking ref when resolving the base branch.**
  The guard checked `git rev-parse --verify "origin/<name>^{commit}"`, an abbreviated ref git
  resolves through `refs/`, `refs/tags/` and `refs/heads/` *before* `refs/remotes/`. A local tag
  literally named `origin/<name>` therefore satisfied the check, the corrective fetch was skipped,
  and the emitted `git checkout -b` branched the user's work off that unrelated tag instead of the
  remote default. Both the check and the emitted start-point now use `refs/remotes/origin/<name>`,
  which only the intended remote-tracking ref can satisfy and which sets the new branch's upstream
  exactly as the abbreviation did. The default-branch name is normalized once, so the offline
  `refs/remotes/origin/HEAD` fallback and the charset guard both operate on the branch name alone.

## [0.34.1]

### Added

- **`work-loop` and `attend-queue`: the rate-limit floor's reactive-only mode now reads the
  detection records.** The fail-open bullet named reactive-only but gave the lane no
  `stop-events.jsonl` behavior; both skills now carry the reader contract's read cadence (read on
  mode entry and before each new work claim, recency baseline = lane start advanced by each resume
  attempt). Mirrors rate-limit-guard 0.4.4's reader-contract addition.

## [0.34.0]

### Changed

- **`work`: Step 4 staleness pre-check states its scope explicitly.** The step listed two referent
  shapes (a file to modify, a test to add) with no rule for the rest; current models do not
  silently generalize an instruction from one item to another (Sonnet 5 / Opus 4.8 prompting
  guides, "More literal instruction following"), so an item naming a config key, doc section, URL,
  or linked issue got no staleness check at all on the unattended `work-loop` path. The step now
  opens with "check every concrete referent the item names" and labels the bullets as examples,
  not the list.

## [0.33.0]

### Changed

- **The drain loop's cycle report must now be grounded in tool results from that cycle**, with
  unverified work said to be unverified rather than left undistinguished. The step already bounded
  what the report contains and how often it is written; it said nothing about whether its claims were
  true.
  - This is the one surface where a fabricated line survives: nobody watched the cycle, no receiver
    re-derives the report the way a dispatching orchestrator re-derives a worker's return, and the
    comment is the operator's only record of what happened. Anthropic's Fable 5 prompting guide names
    exactly this case — "Before reporting progress, audit each claim against a tool result from this
    session" — and reports that the instruction nearly eliminated fabricated status reports in its
    testing, including on tasks built to provoke them.
  - Deliberately not extended to subagent returns in the same lane: those are already promoted to
    direct evidence receiver-side before they drive anything, which is the stronger mechanism and
    does not depend on the worker auditing itself.

## [0.32.0]

### Changed

- **The permission preflight resolves the main checkout by verification instead of path arithmetic,
  and never claims `PREFLIGHT: OK` for a run whose main-checkout layer it could not read (#1941).**
  0.31.3 recovered that checkout from the common git dir's path, assuming the conventional
  `<root>/.git` spelling. Any other spelling left it unresolved, and the checkout's
  `settings.local.json` was then dropped from **every** read, deny included — so a live main-local
  deny went unreported while the run printed a clean `PREFLIGHT: OK`, exit 0, zero gaps. The
  interactive path was worse than quiet: both headers that name a main checkout print only under
  `--worktree-root` or a distinct `--project-root`, so a plain run from a linked worktree dropped
  that deny with no output at all.

  Resolution is now a ladder of candidates — the probed checkout itself, the common dir's
  `core.worktree`, then the conventional parent-of-`.git` — each put through one three-leg predicate
  before it is trusted: the candidate is its own toplevel, it belongs to this repository, and its git
  dir is the common dir. A candidate that fails is discarded, never named, so no path is asserted to
  be the main checkout unverified. `core.worktree` is what makes a submodule's
  `<super>/.git/modules/<name>` common dir — which no parent-of-`.git` arithmetic can invert —
  resolvable at all; a submodule's linked worktree now reports its main-local deny where it
  previously reported nothing.

  Outcomes are three, not two. A **bare** repository has no main working tree, so no main-local layer
  can exist, nothing is missing, and the summary stays `OK` rather than raising the false alarm this
  change exists to remove. An **unresolved** main checkout is reported on its own `UNREAD LAYER` line
  with the reason, and the summary becomes `PREFLIGHT: INCOMPLETE …`, which outranks both `OK`
  branches and prints in every mode including the interactive one. The report-only contract is
  unchanged: `--count` still prints the gap integer, unread layers are not gaps, and the script still
  always exits 0.

  `--separate-git-dir <path>/.git` is documented as what it is — ambiguous in git itself, not a
  preflight defect. Git records no back-pointer to that layout's working tree (`core.worktree` is
  unset by `git init --separate-git-dir`, `git clone --separate-git-dir`, and the migration path
  alike), `git worktree list` reports `<path>` as the main worktree even when run from the true tree,
  and `<path>` satisfies the verification predicate exactly as a conventional root does. The
  preflight resolves to git's own answer, reached by verification rather than by string arithmetic.

  Internally `normalize_path` answers in a variable using only builtins: every path comparison used
  to fork a command substitution around a `printf | tr` pipeline, and one `rev-parse` now answers all
  three predicate legs. The added verification is more than paid for — a run takes 1.7s against the
  previous 4.7s on the same fixture.

## [0.31.3]

### Fixed

- **The permission preflight counts the main checkout's `settings.local.json` as worktree
  coverage, so the autonomous path stops over-reporting gaps a fresh worker would not have.**
  Since Claude Code v2.1.211, choosing "Yes, don't ask again" saves the rule to
  `.claude/settings.local.json` at the repository root, resolved through worktrees to the MAIN
  checkout, and the rule applies to sessions anywhere in that repository — every linked worktree
  included. The preflight modelled the pre-v2.1.211 behaviour instead: it dropped the local file
  wholesale on the `--worktree-root` path, on the reasoning that a gitignored file cannot follow a
  fresh worktree. That reasoning now holds only for a local file living inside some *other* linked
  worktree, so a grant the worker would genuinely inherit was reported as a missing-allow gap. The
  script now reads the main checkout's local file in every mode; only a linked-worktree cwd's *own*
  local file is still dropped pre-dispatch, since a pre-v2.1.211 save (or a hand-placed file)
  applies solely to sessions started in that worktree. The exclusion is a no-op when the run starts
  from the main checkout, and the report header now names which files the coverage read spanned —
  whichever path the main-checkout resolution produced, including a wrong one (below).
  Deny rules keep reading every local layer they resolve — erring wide on deny cannot mask a gap
  *within the layers actually read*, though it cannot widen a layer that never resolves (below).
- **That main checkout is identified by comparing the checkout's own git dir against the common
  one, not by assuming the git dir is spelled `<root>/.git`.** Equal dirs mean the checkout *is*
  the main one, so the **main checkout of** a `--separate-git-dir` or submodule layout — where the
  common dir lives outside the working tree entirely — resolves to the right root instead of
  resolving to nothing and re-reporting the very gap this release removes. From a linked worktree the
  main checkout is still recovered from the common dir's path, so a linked worktree *of* such a repo
  lands in one of two wrong states, neither of them merely noisy. When the common dir is not spelled
  `<root>/.git` — a submodule's `<super>/.git/modules/<name>`, or a separate git dir named anything
  else — the main checkout stays unresolved and its local file goes unread in **every** read: a
  covered verb is over-reported as a gap (noisy), *and* a deny living only in that file is not
  reported at all, so the run can print a clean `PREFLIGHT: OK` (exit 0, zero gaps) while a
  main-local deny is live. When the common dir *is* spelled that way — `--separate-git-dir
  <path>/.git` — the main checkout resolves **wrongly**, to `<path>`, a directory that is not this
  repository's working tree at all, and a foreign `.claude/settings.local.json` is unioned into every
  read: a foreign allow **masks** a real gap, and a foreign deny yields a false DENIED (point the
  separate git dir at `$HOME/.git` and the foreign layer is the operator's own `~/.claude` local
  file). The header then names that foreign directory **as** the main checkout, in wording identical
  to a correct resolution, so it asserts something false rather than merely omitting it. Correcting
  the resolution itself is deferred; this release states the behaviour truthfully.
  `reference/permission-preflight.md` carries the residual cases rather than leaving them implied,
  scoped to both the pre-dispatch and named-worker modes. A pre-v2.1.211 harness, where a worktree
  session loads its own local file rather than the main checkout's, **masks** a gap the worker really
  hits, and this report cannot self-detect it since it never probes the running Claude Code version —
  a documentation-completeness matter rather than a live defect on any v2.1.211-or-later install.

## [0.31.2]

### Fixed

- **`triage` excludes lane infrastructure from raw intake, so the telemetry surface a lane reads to
  operate can no longer be triaged as backlog (#1739).** Lane-infrastructure exclusion was
  implemented in the two lane skills that select work — the worker loop's drain snapshot and the
  attended queue's merged view — but not in `triage` itself, which defines the intake population
  both of them compose. A bare `/work-items:triage` therefore listed an open `Lane telemetry:
  <lane>` issue as untriaged intake whenever that issue carried the raw marker, and the skill's
  closing invariant ("no outcome leaves a re-selectable raw item") pushes toward acting on what it
  lists — relabelling or closing a surface the lane reads to operate. `triage` now carries the
  exclusion as a third rule bounding what enters the flow, applied to the listing **before**
  bucketing so the raw marker cannot bucket an excluded item. The exclusion is deliberately
  label-blind: the marker arrives as a creation-time filing default and a lane can re-add it, so a
  label-keyed rule would keep re-acquiring the defect. An explicitly named telemetry issue now
  stops the same way a named already-triaged item stops, instead of walking the state machine
  toward a close.
- **That exclusion identifies a telemetry issue the way the lane does, never by title alone
  (#1739).** `Lane telemetry: <lane>` is only the DEFAULT home. A lane's launch config may pin
  `lanes[].telemetry.issue` to an existing issue with an operator-chosen title (the `claude-ops`
  lane config), and `work-loop` resolves its telemetry home from that config before falling back to
  the title. A title-only test therefore admitted the one issue whose loss costs the most — a real,
  configured telemetry home — to raw intake, where relabelling or closing it destroys durable lane
  state. Identity is now the pinned config issue where the config is visible, else the default
  title, and — independent of both — any issue carrying the convention's sentinel status comment
  (`<!-- claude-ops:lane-telemetry marker=… -->`). The two signals cover each other's gap: a pin
  defeats the title test, and an issue pinned but not yet written to carries no sentinel yet.
  `work-loop`'s drain-snapshot exclusion, which stated the title contract itself, now points at
  this definition instead of restating a narrower one.
- **`attend-queue` stops re-deriving that exclusion (#1739).** Its `[intake]` rows already compose
  `triage`'s attention view and are documented as not re-deriving its buckets; the lane-infrastructure
  paragraph restated the title contract anyway. It now points at the composed view, leaving one
  statement of the contract on the intake path instead of two.

## [0.31.1]

### Fixed

- **`work-loop` and `attend-queue`'s inlined telemetry upserts now gate their body and verify what
  landed (#943).** Both lanes inline the same `gh api` upsert the babysit lane does — an installed
  plugin cannot invoke `claude-ops`'s `telemetry-upsert.sh` — and so inherited none of that wrapper's
  body checks. The defect that surfaced on the babysit lane is a property of the shared upsert shape,
  not of one lane: an `@path` passed as a body VALUE is transmitted as literal text (`gh` expands a
  leading `@` only for `--body-file` / `-F field=@file`). Both blocks now carry three checks. A
  **pre-write gate** rejects a `$BODY_FILE` that is empty, opens with a literal `@`, is not
  sentinel-prefixed, or holds under 16 bytes of payload — no POST, no PATCH. The **write's own exit
  status** is then checked, because a failed PATCH leaves the previous cycle's body in place and a
  read-back running regardless would accept it. A **post-write read-back** re-reads what the write
  stored and reports the cycle UNREPORTED unless that body still opens with the sentinel and clears
  the same floor; this is the check that would have caught the actual #943 shape, where the composed
  file is fine and the defect is the invocation (`-f body=@FILE` instead of `-F body=@FILE`) — a
  file-only check cannot see it. Every branch that ends without a verified body — including a
  degraded create, which leaves no sentinel-prefixed comment to re-read — reports UNREPORTED and
  skips the duplicate-supersede pass, so a cycle whose own write is unproven never tombstones a
  racing session's comment. The 16-byte floor is measured on everything below the sentinel LINE, so
  it matches the wrapper's `MIN_BODY_BYTES` byte-for-byte on LF and CRLF alike; prefix comparison is
  byte-wise, so a CRLF body is not false-rejected. `work-loop` additionally records a refusal or
  failed verification in durable loop state; `attend-queue` has none, so it carries the same fact in
  the cycle's own summary — either way stderr does not survive the session and a cycle that did not
  report must stay visible to the next one. The `$BODY_FILE` sentinel-first-line contract is now
  stated in prose. Two wrapper limits are inherited rather than fixed: a PATCH that succeeds while
  storing the previous body still verifies, and the read-back proves *some* well-formed telemetry is
  present, not *this* cycle's. Not replicated at all: the 64 KiB cap, the containment checks,
  retries, and the wrapper's distinct non-zero exits — every inline branch exits 0.
- **`work-loop`'s telemetry upsert moves to `reference/telemetry-upsert.md`.** SKILL.md sat at 499 of
  its 500-line hard cap, so the checks above did not fit. The upsert — lane-instance resolution and
  validation, the singleton lookup, the body gate, the write-status check and read-back, the
  POST/PATCH, and the creation-race reconcile — moves verbatim into a spoke, the same shape the
  sibling `source-control:babysit-loop` lane already uses for the identical block. SKILL.md keeps the
  telemetry home and the durable-state contract and points at the spoke for the mechanism; the
  rationale for inlining rather than calling `claude-ops`'s wrapper is now stated once instead of
  twice.

## [0.31.0]

### Fixed

- **Two lanes on one repository no longer clobber each other's durable state, including
  `first_drain_complete` (#1295).** `work-loop` and `attend-queue` each built their telemetry
  sentinel from a fixed marker naming the lane *type*, so every concurrent instance of a lane
  resolved the same comment on the same telemetry issue and overwrote it last-writer-wins. The
  reconcile already in the upsert did not help: it converges duplicate *comments* from a creation
  race, not conflicting *state* written by two live lanes. `item_cap`, `clean_streak`, and
  `rate_limit_latch` silently stopped reflecting either lane's experience, and
  `first_drain_complete` — the flag that ends the first-drain C3 ratification gate — was set for
  every machine by whichever one finished a drain first, widening autonomy with no human
  ratification. The marker now carries the convention's lane-instance suffix
  (`work-items:work-loop@<instance>`, `work-items:attend-queue@<instance>`), so each instance
  creates, reads, and edits exactly one comment no sibling can match, and every counter in the
  block is per-instance. Earn-trust is re-earned per instance; item-level ratifications still
  travel with the item, so only the blanket period-end flag resets.

### Added

- **`lane_instance` config key, and an instance-collision check in `work-loop`'s durable state.**
  The id defaults to the sanitized lowercased hostname and is validated `^[a-z0-9][a-z0-9-]{0,31}$`
  inside the lane's own executable block — it is operator-supplied text interpolated into a shell
  string and a `jq` program, so it is rejected rather than sanitized-and-continued. Partitioning is
  only correct while ids are distinct, so the state block (now `work-items/loop-state@2`) carries
  `lane_instance`, a per-session `writer_nonce`, a per-cycle `heartbeat_at`, and `paused_until`: a
  differing nonce over a stale block is the ordinary restart adoption, and a differing nonce over a
  *fresh* block means another live lane holds this id — the lane writes nothing, escalates, and
  stops. The check runs before any write, so a duplicate id degrades to a stopped lane rather than
  a clobbered `first_drain_complete`. Two shapes the freshness test alone misreads are carved out:
  a fresh block carrying a non-null `restart_request` is a stopped predecessor's clean handoff
  (recording the ask is its last write), so the replacement adopts immediately — clearing the
  request — instead of waiting out the staleness window; and an unclaimed marker is claimed with a
  cycle-0 block plus a re-read through the creation-race reconcile *before any work*, so two
  same-id sessions starting together stop before either overwrites the other's first durable
  state.

### Changed

- **The `Lane telemetry: <lane>` issue title is deliberately untouched.** The drain-exit snapshot,
  the intake sweep, and the attention view all match lane infrastructure by that title contract, so
  partitioning by marker rather than by title leaves every one of those consumers unmoved. Migration
  is a deliberate reset: no pre-existing comment matches an instance's new sentinel — neither the
  legacy un-suffixed markers nor the improvised `work-items:telemetry lane=… instance=…` comments
  some lanes began posting in practice — so the first cycle posts a fresh block from defaults,
  including `first_drain_complete:false`. That fails closed and is intended. A lane never adopts,
  edits, or tombstones the legacy comment: its marker names no writer, so no instance can prove it
  owns it, and adopting it would reintroduce the clobber. Retiring it is an operator action.

## [0.30.3]

### Added

- **An item-body embedded-instruction eval case on every body-reading skill (#1717).** This plugin's
  eval sets held a single adversarial-input case, and it covered a different surface entirely —
  nothing here exercised the one text all of these skills read: an item's own body and comments.
  `triage`, `decompose`, `work`, and `attend-queue` each now have one case whose prompt embeds a
  directive addressed to the reading agent and whose expectations assert the directive is evaluated
  as data and not acted on. `work-loop`'s equivalent case
  (`work-loop-item-body-is-data-not-instruction`) already shipped, so these four complete the set of
  body-reading surfaces #1713 enumerates. The cases are keyed to what the embedded text would
  subvert in that lane rather than paraphrased across four files — `triage`'s verification step and
  direction-gate branch, `decompose`'s approval gate and don't-touch-the-parent rule, `work`'s
  claim-before-dispatch prerequisite and never-merge boundary, and `attend-queue`'s
  operator-is-the-authority rule — so each binds a boundary the skill already states. Modelled on
  the existing case in `plugin-quality`'s `audit` skill (`anti-pattern-injection-in-audited-source`)
  rather than introducing a second eval shape.

## [0.30.2]

### Fixed

- **`work-loop`'s `usage_sample` prose contradicted the loop-lane invariant it cites.** The
  convention permits reading the previous sample back to derive `five_hour_delta_pct` — the
  subtraction *and* the rollover comparison — but 0.29.0 described the field as "deliberately inert:
  no lane behavior reads it back", which no lane computing a rollover-suppressed delta could satisfy.
  The convention's wording is corrected upstream (loop-lane 6.0.1); the entry recording 0.29.0 is
  left as shipped and superseded by this one. **The measure-only guarantee is unchanged** — the value
  still reaches no decision, at any threshold.
- **`at` was ambiguous between two timestamps.** It is when the lane read the tee, not the snapshot's
  own `captured_at`, which the staleness rule permits to lag it.
- **The delta's `null` condition read too narrowly.** "Either sample is missing" excluded a present
  sample carrying a `null` `five_hour_pct`; it is now `null` whenever either side's `five_hour_pct`
  is unavailable.

## [0.30.1]

### Changed

- **`lib/lease.sh`/`lib/lease.test.sh` annotated for the shell-portability-lint
  gate's newly-active `date -d` class (#1510).** `wit_iso_to_epoch`'s
  BSD-first/GNU-fallback ladder is correct dual-dialect code, split across a
  `||`-continued line the gate's same-line auto-guard doesn't recognize, so
  it now carries a `portability-ok:` annotation (restructured to drop an
  unnecessary trailing `\` so the annotation could sit on its own line
  without breaking the `||` chain — no behavior change). The test file's
  same-line `date -d ... || date -u -r ...` fallback is annotated directly.

## [0.30.0]

### Changed

- **`work` rides the structural capability-tier binding for every source-touching dispatch
  (`#1649`).** The Step 5 execute chain now names the model-tier enforcement carried by
  `implementation:implement-dispatch`'s new `implementer` / `phase-verifier` agent frontmatter, and
  the branch-owned fix re-dispatches into the persisted worktree dispatch
  `implementation:implementer` when the `implementation` plugin is installed (when absent, an
  explicit per-invocation strong-tier alias — never inheritance of the orchestrator's model). The
  PR-monitor and post-green review-pass dispatches into the persisted worktree likewise carry an
  explicit per-invocation `model` now — fast-tier alias for the mechanical watch, no weaker than
  the implementer binding for the review pass, since a reviewer is never weaker than the
  implementer it checks. A fast-tier lane root no longer silently determines implementer strength,
  which is what let a `sonnet` root run every implementer as `sonnet` despite the loop-lane tier
  vocabulary.

## [0.29.0]

### Added

- **`work-loop` samples per-cycle usage into its durable state block (#1651).** A lane's spend was a
  blind spot: the cycle budget counts cycles, the rate-limit guard's pause is a ceiling, and nothing
  recorded how much of the shared subscription windows a cycle actually consumed. The durable-state
  block now carries a `usage_sample` — the two window percentages the guard step **already reads**
  every cycle, plus the rise since the previous sample — so measuring adds a write, not an
  observation. The field is deliberately inert: no lane behavior reads it back, and no pacing,
  adaptive cap, or pause derives from it. Its caveats are recorded beside it because they bound what
  the data can support — the reading is a snapshot no fresher than the guard's staleness rule allows,
  from a machine-local, last-writer-wins tee that refreshes only while an interactive session renders
  a status line (so an unattended background lane samples null every cycle, and an empty sample means
  unobserved, not zero); the figures are account-scope (concurrent lanes move the same windows, so a
  rise is this lane's own consumption only when it is the sole active session) and a percentage of a
  subscription window rather than a token count. No token count is claimed because none is readable
  at a cycle boundary: the status-line context-window token counts are current-context occupancy
  rather than session totals as of Claude Code v2.1.132. A machine-readable cumulative cost field
  (`cost.total_cost_usd`) does exist and is session-scoped, so it is the deferred candidate for
  per-lane attribution — but the guard's tee does not forward it, and widening the tee is a
  rate-limit-guard change this entry deliberately does not make
  (<https://code.claude.com/docs/en/statusline>, re-verified 2026-07-28 — `used_percentage` 0–100,
  `resets_at` epoch seconds, `rate_limits` subscriber-only and each window independently absent; no
  drift).

## [0.28.0]

### Added

- **`work-loop` detects consecutive no-progress cycles and escalates instead of cycling invisibly
  (#1648).** Every stall mechanism was per-PR or per-item, so a lane cycling repeatedly while
  accomplishing nothing in aggregate was invisible to itself. The lane now persists a
  `no_progress_streak` counter beside `clean_streak` in its `#502` durable state block: a cycle
  with actionable work in the cycle-start snapshot (frontier candidates or untriaged intake) that
  ends with no qualifying progress — an item advanced or a PR opened — increments it, an idle
  cycle — or one held under the rate-limit guard's pause, where the lane declines work by design —
  leaves it unchanged, and any qualifying progress resets it. At the threshold (new
  `work_loop_no_progress_threshold` userConfig key, default 3) the lane raises a stall escalation
  through the existing escalation contract — a `Lane stall: work-loop` tracker item with the
  human-gated role label and the machine-marked escalation comment, at most one open at a time
  (author-matched) — and **keeps looping**: a stalled lane is a signal about the queue, not a
  reason to terminate. Shared counter semantics are owned by the loop-lane convention (§4,
  "No-progress detector", convention 5.0.0); the lane body holds them by citation and defines only
  the worker-lane progress events.

## [0.27.0]

### Added

- **`work-loop` escalation record write — deterministic surface for out-of-band notification
  (#1650).** Escalating — step 5, step 2's routed-advisory routing, and the admission gate's
  first-drain `kind=ratify-c3` queueing — now also creates
  `.claude/lane-escalations/<UTC-stamp>-<item>-work-loop.json` with the Write tool in the same
  step that files the tracker escalation, immediately before posting the marker comment — one new
  file per NEWLY filed escalation (suppressed by the marker read the step already performs),
  `loop-lane/escalation-record@1`
  shape, summary restating only the already-public marker-comment text. The Write tool call (never
  a shell redirect, whose `Bash` event the seam's `Write` matcher never sees) is what a consuming
  repo's `PostToolUse`
  `type:"http"` hook keys on to reach an off-machine human deterministically; the documented seam
  and settings shape are owned by the loop-lane convention (§2, v4.0.0). Record-before-marker is
  load-bearing: a stop between the two non-atomic writes then costs one duplicate notification the
  next cycle re-files, where the reverse order strands a standing marker that suppresses the record
  on every later cycle and loses the notification permanently. Without a configured hook the file
  is inert exhaust; the tracker item stays the escalation of record.

### Changed

- **`work-loop` gains a lane-start preflight that ignores the escalation record directory itself
  (#1650).** The record write is unconditional, so an unignored `.claude/lane-escalations/` would
  strand an untracked file per escalation in the tree this lane runs its gates against — and
  nothing delivers a tracked ignore rule into a consuming repo, so an existing consumer that
  upgrades would hit exactly that. New cycle-shape step 0 runs once per lane: if
  `git check-ignore -q` reports the path unignored, append it to the clone's untracked
  `$(git rev-parse --git-common-dir)/info/exclude`. No consumer change, no tracked file touched,
  and a no-op wherever the repo's own `.gitignore` already carries the rule.

## [0.26.1]

### Fixed

- **`setup check`'s role-label probe no longer FAILs on the zero-row schedule a skeleton-only bind
  produces (#1298).** `apply` step 6 keys the recurring-maintenance label requirement on the
  schedule's **final row count** — with zero rows a missing label is "informational, not a gate" —
  but `check` probe 6 still keyed it on the schedule **file's presence**. Since `0.25.3` made
  "binding present, schedule present, zero rows" the expected steady state after a first bind, the
  two surfaces returned different verdicts for one state, and an operator's first `check` after a
  deliberately-quiet bind was a hard FAIL over a `[Maintenance]` item that a zero-row schedule can
  never produce. Probe 6 now branches on row count exactly as `apply` does: **≥1 row with the
  resolved label absent is still a hard FAIL, unchanged and unweakened** — the requirement fires
  where it is load-bearing — while an absent or zero-row schedule is INFO noting the label must
  exist before the schedule is ever seeded. An unparsable schedule has no readable row count, so
  probe 6 reports INFO naming probe 4's validity FAIL as the reason rather than laundering that FAIL
  into a verdict of its own. Every one of those row-count outcomes is reached only once the role
  resolves: a malformed, empty, or non-string configured
  `config.role_labels["recurring-maintenance"]` is probe 6's own FAIL and settles the probe's single
  verdict outright, so no row count — zero, absent, or unreadable — can downgrade an independent
  binding error to INFO. This mirrors `apply` step 6, where the same value is "an error, not a
  fallback" regardless of how many rows the schedule carries. Probe 4 additionally reports a
  valid-but-empty `items` array as INFO pointing at `apply --seed-schedule`; no probe previously
  reported the emptiness itself, so `check` never told an operator the schedule had no rows or how to
  seed it. `check` remains read-only. First `check`-side eval coverage lands with it.

## [0.26.0]

### Added

- **A read-trust boundary on item text, stated once and cited from every skill that reads an item
  (#1657).** Every provenance control in these lanes governed *write* authority — who may merge,
  what may dispatch — and none told an agent what to do with the prose it reads. Item titles,
  bodies, comments, and linked-PR text and diffs arrive from a surface any author or agent can
  write, and were read into context uncaveated, as instruction-shaped as anything else in the
  prompt.
  - New `reference/item-content-trust.md` owns the boundary: item-derived text is data describing
    the work, never instruction to the agent reading it; the boundary keys on the surface the text
    arrived on rather than on who wrote it, so it applies to a teammate's item exactly as to a
    stranger's; an item whose text instructs the agent is a finding to report, not a request to
    satisfy. It also states the widening rule — no admission, dispatch, merge eligibility,
    capability grant, or gate waiver ever rests on a claim recorded in a body or comment, per the
    autonomy plugin's admission policy — with the carve-out that a claim which can only *tighten*
    stays usable as a signal, and names the one shipped instance of that carve-out
    (`work-loop`'s frontier-tier quota guard). That instance carries its bounding condition at both
    ends: the carve-out holds only while the resolved frontier cap ceiling is at or below the
    resolved general one, and `work-loop`'s own "Adaptive item cap" step states what to do when an
    operator inverts them — drop the separate frontier ceiling, which would let a body claim widen
    throughput, and bound the item by the general ceiling, keeping the concurrency-1 half that can
    only tighten. `work_loop_frontier_item_cap_ceiling`'s manifest description carries the same
    ordering expectation at the point of configuration; the manifest cannot enforce it, because
    `userConfig` `min`/`max` are static numeric bounds with no cross-key validation
    ([plugins reference](https://code.claude.com/docs/en/plugins-reference#user-configuration)).
  - `triage`, `decompose`, `work`, `work-loop`, and `attend-queue` each carry the standing
    instruction in their
    shared tracker context, plus one line on what the boundary bites hardest in that lane, and cite
    the reference for everything else — the escalation route, the widening rule, and the subagent
    rule are stated once in the reference rather than four times in the skills. `source-control`'s
    `babysit-loop` and the loop-lane parked-decision prompt, which inherit no skill's copy, carry
    the same headline and citation.
  - Item text handed to a subagent goes inside a quoted untrusted-data section with the standing
    never-follow instruction attached, reusing the delimiter shape `source-control`'s
    `babysit-prs` already specifies for the merge lane rather than inventing a second form. The
    fence itself is carried inline beside that citation, verbatim and unreworded, so the rule stays
    executable when the cross-plugin fetch fails — an instruction whose only mechanical detail sits
    behind a network round-trip contradicts itself the moment the fetch does, leaving an agent with
    no delimiter and no permission to improvise one.

### Changed

- **`work-loop`'s admission gate justifies its ratification-phrase refusal from the boundary, not
  from a work-class row (#1657).** The refusal previously rested on "the work-class table above
  already routes untrusted provenance to human-gated" — a C5 row whose executable test reads a
  *pull request*, which an issue does not have. The refusal is unchanged; it is now derived from
  the standing rule it is an instance of (item text never widens authority, and admission widens
  it), which holds for an issue with no field test at all.

## [0.25.4]

### Fixed

- **`work-loop` and `attend-queue` no longer downgrade the whole rate-limit guard because one window
  is absurd (#1612).** Both lane bodies inlined the reader contract's mode table — "tee file absent,
  stale, missing `rate_limits`, or absurd values → mode unknown → reactive-only" — which collapses the
  guard wholesale as soon as any single value is absurd. Against the floor's "pause when **either**
  window reports `used_percentage >= 90`", a lane holding one garbage window and one valid window at
  95% kept claiming work until a reactive rate-limit failure landed, rather than pausing on the window
  it could still trust. The inlined rule now classifies validity per window: tee file absent, stale, or
  missing `rate_limits` is still a whole-guard downgrade; an absurd `used_percentage` or `resets_at`
  makes only that window unknown; the floor keeps applying to every still-plausible window; and
  reactive-only is reached only when no window is plausible. The rule stays byte-identical across all
  three lane bodies (the third is `source-control`'s `babysit-loop`). The operable floor's values are
  unchanged.

## [0.25.3]

### Changed

- **`setup apply` no longer seeds recurring schedule rows by default on a first-time bind (`#1211`).**
  A bare `apply` against an absent or empty schedule now writes only the minimum viable config — the
  provider binding, the canonical role-label pass, and the empty `{"items": []}` skeleton that stops
  `due` / `recheck` / `work` degrading to "no recurring schedule configured". The candidate-inference
  and per-item interview pass, previously unconditional, is opt-in: the new `apply --seed-schedule`
  argument, an explicit in-invocation request to seed, or a single yes/no offer whose RECOMMENDED
  default is skip. With no interactive user (a loop lane or other unattended context) the skip default
  applies silently; `--seed-schedule` carries the opt-in decision without the offer prompt, but the
  pass it selects is still the per-item interview, so seeding stays an attended operation. A
  first-time bind is usually a detour from another verb reporting "no binding", so the operator who
  came to do something else is no longer walked through an interview per candidate item to get there. The gate keys on the
  schedule carrying **no items**, not on the file being absent, so a skipped bind's `{"items": []}` is
  still reachable by re-running `apply` — a schedule that already carries ≥1 item is summarized and
  offered updates exactly as before, unchanged. The role-label pass is re-anchored to the bind rather
  than to the interview so it still runs on the skipped path; with zero schedule rows a missing
  `recurring-maintenance` label is reported as informational rather than gating, since no
  `[Maintenance]` item can be created from an empty schedule.
- **`setup apply` now defines its unattended behavior for every pass, not only the seeding offer.**
  The seeding offer is the last question in `apply`'s flow; the provider/config interview and the
  role-label remap offer ahead of it had no unattended resolution, so an unattended first-time bind
  blocked before it could reach the skip default. The rule is now stated once for the whole flow: a
  decision whose RECOMMENDED answer is safe resolves to it silently (and the summary names which
  defaults were taken), while a decision with no safe default is never guessed — `apply` stops and
  reports it as a named blocker. Provider binding is where the second branch applies, and only when
  the repo has **no** binding yet: `github` is RECOMMENDED but needs `gh`, and `local-markdown` /
  `jira` need `storage_dir` / `config.jira` values that have no defaults and cannot be inferred, so
  with `gh` absent `apply` writes no binding rather than making every seam verb resolve a provider
  the repo never chose. An unattended re-run against a repo that is **already** bound keeps its
  existing provider and config — re-binding is a switch-providers decision, so a working `gh` never
  moves a `local-markdown`, `jira`, or consumer-local repo onto `github` behind the operator's back.

## [0.25.2]

### Fixed

- **`track start` suggests a branch based on the remote's OWN default branch.** Both branch-switch
  suggestions emitted `git checkout -b <type>/<N>-<slug> origin/main`, hardcoding a default-branch
  name into a forge-agnostic skill: on a repo whose default branch is `master`, `trunk`, or
  `develop`, the user was handed a command that either fails or silently bases the work on the wrong
  ref. The existing-branch check now resolves `BASE_REF` by asking the REMOTE first
  (`git ls-remote --symref origin HEAD`), falling back to `refs/remotes/origin/HEAD` only when the
  remote is unreachable: that local symbolic ref is a cache no clone refreshes on its own, so a repo
  that renamed its default branch keeps answering with the old name, and a `git remote add` +
  `git fetch` clone never has it at all. The resolved name is remote-controlled input on its way
  into a command the user pastes, and Git accepts branch names carrying shell metacharacters
  (`main;id`), so it is accepted only against a conservative branch-name charset and refused —
  never escaped — otherwise. `ls-remote` can also name a branch this clone has never fetched, whose
  `origin/<name>` would not resolve; that is fetched once and dropped if it still misses. Neither
  rung guesses a literal: whenever the resolution ends empty the suggestion is emitted with no
  start-point and the unresolved default branch is stated, rather than reintroducing the assumption
  under a different name. `templates/checklist.md`, which
  `/work-items:work` copies verbatim for every run, said "from origin/main" and would have
  contradicted this in the agent's own working ledger; it now names the resolved base.
  Both suggestions emit `<base-ref>` — a placeholder the agent substitutes with the resolved value,
  like `<type>` / `<N>` / `<slug>` beside it. Emitting the shell variable itself would have shipped
  a broken command: the suggestion is pasted into the USER's terminal, which never saw the agent's
  assignment, so `"$BASE_REF"` would expand to an empty pathspec. Surfaced by `portability-lint`,
  which reads the whole file once the file is touched.

## [0.25.1]

### Documented

- **`reclaim` classifier denial is now a documented, non-blocking condition (`#1381`).** A
  work-loop self-observation found the seam `reclaim` verb refused by the Claude Code auto-mode
  classifier while the sibling `claim` verb on the same script was not, with neither verb carrying
  an explicit `permissions.allow`/`deny` rule — a harness-level tool-call denial that produces no
  script exit code, distinct from the existing exit-`6` capability-unsupported case.
  All three `reclaim` callers — `skills/work/SKILL.md` "Step 0", `skills/track/actions/start.md`,
  and `skills/track/actions/audit.md` — now instruct treating it the same as exit `6` (report once,
  skip, proceed; never retry, never self-widen permissions). `start` still catches a live foreign
  lease through `claim`'s exit-`7` back-off; `audit` reports the stale-claim pass as **skipped**
  rather than as zero stale claims, since a denied call checked nothing.
  `tools/work-item-tracker/CONTRACT.md` "Exit codes" now notes this out-of-band failure mode
  explicitly. `reference/permission-preflight.md` records the finding and flags whether an explicit
  allow rule would bypass the classifier for this command shape as an open, unverified question
  (official docs describe allow rules bypassing the classifier by default, but also describe an
  unspecified "arbitrary-code-execution patterns" carve-out that still routes through it) — any
  operator-side permission-floor fix needs that confirmed first.

## [0.25.0]

### Added

- **Brief-before-ask requirement in the interactive gates (`#1202`).** `triage`'s interactive
  direction gate (both the initial recommendation and each step-4 interview question) and
  `attend-queue`'s row-working loop (`[intake]`, `[escalated]`, `[ratify]` rows) now require
  restating, before any operator-facing decision question, (1) which item, (2) the decision being
  asked, and (3) the consequence of each option **presented** — an open-ended question, which has no
  option set to enumerate, states what the answer will determine instead of being narrowed into a
  closed list to satisfy the restatement. Previously an operator could be asked to decide with only
  option labels and no restated item context, forcing them to halt the pass and ask "what issue are
  you looking at."

## [0.24.7]

### Fixed

- **`work-loop`'s first-drain C3 ratification gate no longer posts a duplicate `kind=ratify-c3`
  queue comment on every cycle (`#1348`).** An item whose ratification was recorded directly in
  the issue body (an `attended triage <date>, operator-ratified` line) — even one already
  corrected once by a same-day comment restoring it to the frontier — collected a fresh queue
  comment each pass, reproducing the noise the correction had already cleaned up (observed on
  `#815`, `#816`, `#965`). The gate now separates the two queue actions: the `kind=ratify-c3`
  comment is posted **at most once ever** (keyed on a marker comment authored by the tracker
  seam's configured write identity — a marker pasted by any other commenter is untrusted
  provenance and never suppresses the queue event), while the role labels converge idempotently on
  the item's correct state rather than being counted as a repeated event: human-gated applied and
  autonomous-eligible cleared in the same edit, mirroring `attend-queue`'s
  never-flip-without-clearing rule. The comment is written before the labels are touched, and a
  failed comment write leaves the labels alone — an item parked human-gated with no marker sits
  outside both `list-frontier --autonomous` and `attend-queue`'s `[ratify]` view, which nothing
  could repair.

  Body prose is context for the operator, never dispatch authority. Free-form issue bodies are
  editable by any author or agent and the work-class table already routes untrusted provenance to
  human-gated, so a body marker is now surfaced in the queue comment — letting the operator
  confirm and record it machine-marked in one step — instead of admitting the item. Dispatch
  still requires the `/work-items:attend-queue` ratification reply or `first_drain_complete`. The
  human-gated label is deliberately kept while machine ratification is absent: `attend-queue`
  lists a `[ratify]` row only for an item carrying that label plus the marker, so stripping it
  would make the item invisible to the operator and unratifiable. The autonomous-eligible role
  label is likewise **not** ratification evidence — unattended `/work-items:triage` applies it to
  every briefed delegable item.

## [0.24.6]

### Documentation

- **`wayfind: *` is now documented as a read-only, skill-private routing axis (`#1255`).** Neither
  the label taxonomy reference nor the shared tracker-seam gotchas said anything about the
  `wayfind: *` labels a triage lane can encounter — a silence a lane meeting them had no basis to
  read as "hands off." `reference/label-taxonomy.md` gains a "Skill-private routing markers"
  section and `reference/tracker-seam.md`'s Gotchas gain a matching entry: both point at
  `/planning:wayfind` (sole writer, on its own map sub-issues) and the resolving decision
  (`melodic-software/github-iac#179`) rather than restating the member list. No work-items skill
  applies, strips, or requires a `wayfind:` value on the items it manages — behavior is unchanged,
  this closes a documentation gap.

## [0.24.5]

### Fixed

- **`triage` no longer routes to `priority: pN-*` labels that exist in no governed repository
  (`#1253`).** The live governed priority axis across the fleet is `priority: critical` / `high` /
  `medium` / `low` / `needs-triage` — the `p0-critical`…`p3-low` scheme `triage`'s priority-label
  step, `track add`'s filing default, and `dogfood-filing.md` named inline appeared in zero
  repositories, so an autonomous triage pass that followed the skill literally failed applying a
  nonexistent label. `triage`, `track add`, and `dogfood-filing.md` now resolve the live `priority:`
  label set from the bound adapter at action entry (consistent with every other "members from the
  live set" axis in `label-taxonomy.md`) instead of naming members inline; where prose still shows a
  concrete value it is marked as an illustrative example, not a routing instruction. The
  triage-assessed default (mid-urgency tier) vs. `track add` filing default (lowest-urgency tier, an
  untriaged-signal floor) distinction is preserved.

## [0.24.4]

### Documentation

- **GitHub adapter: force UTF-8 wherever a body edit leaves the UTF-8-safe pipeline (`#1037`).**
  A new cross-cutting gotcha in `tools/work-item-tracker/adapters/github/README.md` records that the
  `gh` transports do not transcode, and requires an explicit UTF-8 encoding on both sides of any
  ad-hoc read or write of a fetched body. No behavior change.

## [0.24.3]

### Fixed

- **Two `discipline`-rename token-sweep misses corrected: `reference/pipeline-shape.md` and
  `skills/work-loop/SKILL.md` (`#1328`).** The `re-anchor` -> `discipline` plugin rename (`#1276`)
  rewrote the tokens on these lines but left stale `re-anchor` prose beside them — "re-anchor slot"
  / "re-anchor set" in `pipeline-shape.md:52`, "presence-gated re-anchor sweep" in
  `work-loop/SKILL.md:176`. Both now read `discipline`, matching the sibling sites the same rename
  commit already updated (`docs/conventions/loop-lane/README.md`,
  `plugins/source-control/skills/babysit-loop/SKILL.md`).

## [0.24.2]

### Fixed

- **`e2e-probe.sh` now creates and filters the declared `wayfind: research` / `wayfind: task`
  labels (colon-space), not the colon-no-space `wayfind:research` / `wayfind:task` the probe
  previously used (`#1256`).** The colon-no-space form is a string that production never emits —
  it never exercised a label value containing a space, the exact case that makes these labels
  non-trivial (an unquoted `label:wayfind: research` search qualifier returns zero results
  silently rather than erroring). A static regression test now guards both the correct literal and
  the forbidden one directly against the probe's source.

## [0.24.1]

### Documentation

- `tools/work-item-tracker/tests/lib.sh` now points at
  `docs/conventions/shell-test-helpers/README.md`, the repo's owner doc recording that per-plugin
  shell assert-helper duplication and per-script exit-code taxonomies are deliberate, not drift. No
  behavior change.

## [0.24.0]

### Changed

- **`work`'s autonomous concurrency cap is now wired to real enforcement (`#573`).** When
  `${user_config.work_dispatch_concurrency_cap}` resolves to a value, the orchestrator threads it into
  the delegated `/implementation:implement-dispatch` dispatch as that skill's new `--wave-cap <N>`
  ceiling; a surviving placeholder (unset) passes no `--wave-cap`, so implement-dispatch applies its
  own internal 3–5 wave default. The cap previously changed nothing.

### Removed

- **`work_cycle_batch_cap` is removed from `userConfig` (`#573`).** `work` selects and executes exactly
  one item per invocation, so it has no cycle to bound — the scalar had no honest in-skill enforcement
  point and bound nothing. The autonomous per-cycle item budget already lives, and is enforced, in the
  driving loop as the `work-loop` lane's adaptive item cap (`work_loop_item_cap_*`); a future,
  demonstrated need for a distinct loop-side batch budget would reopen as a `/loop`-side concern rather
  than an inert knob.

## [0.23.0]

### Changed

- **`work`'s autonomous execute step now specifies the full orchestrator-dispatch lifecycle (`#572`),**
  resolving the previously-deferred seam across branch/worktree provisioning, PR-creation ownership,
  and fix re-dispatch:
  - **Provisioning is worker-side.** The dispatched worker materializes its own out-of-tree worktree
    as its first step and works it via `git -C` without entering it — the orchestrator never invokes
    `/source-control:worktree create`, whose `EnterWorktree` terminal would transition the
    orchestrator's session. The worker commits, pushes, and brings the branch current with the default
    branch before returning the worktree path + branch name; a worker that cannot provision parks and
    escalates.
  - **PR creation is orchestrator-owned.** After the worker returns and the pre-PR diff gate passes,
    the orchestrator (never the worker) opens the PR via the new `/source-control:pull-request create
    --pushed` PR-only entry; the worker scope-fence forbids PR creation. Detection of a consuming
    project's own PR stage lives in the orchestrator (invoke-vs-defer).
  - **Branch-owned fixes (failing CI, review findings) re-dispatch a fresh scope-fenced subagent into
    the same persisted worktree** — the worktree is the state carrier across dispatches and persists
    through the PR lifecycle, cleaned up only by whoever merges, never by this lane.
  - `work-loop`'s former interim `#572` workaround is reframed as this now-canonical behavior it
    inherits from `work`.

## [0.22.1]

### Fixed

- **Permission preflight no longer reports a false `additionalDirectories` gap for a tilde-form
  grant.** `normalize_path` folded backslashes and Windows drive letters but never expanded a
  leading `~`, so a `permissions.additionalDirectories` entry written in `~/…` form never matched
  the absolute worktree root the harness derives from that same home — the preflight wrongly emitted
  its `(c)` gap even though the grant was live. `normalize_path` now expands a leading `~` (`~` alone,
  or `~/…` / `~\…` — both separators, since a Windows entry may use a backslash) to the user home
  (`HOME`, then `USERPROFILE`) before folding, so tilde-form entries compare equal to the absolute
  probed root. A trailing separator on the home (including `HOME=/`) is stripped before the join so
  it cannot produce a non-collapsing `//`. Regression cases cover the forward- and backslash-separator
  matches, the trailing-separator home, the outside-home non-match, and unchanged non-tilde behavior.

## [0.22.0]

### Added

- **Two loop-lane skills: `work-loop` and `attend-queue`.** The work-items adopters of the
  loop-lane convention (`docs/conventions/loop-lane/` in the marketplace repository). `work-loop`
  is the worker lane — a self-paced drain loop that sweeps raw intake through `triage`'s
  autonomous lane each cycle, admits items through a fail-closed work-class gate (C2 autonomous;
  C3 bug-fix-shaped autonomous behind a first-drain ratification queue; C3 feature-shaped, C4, C5,
  and unclassified human-gated; plus a path/topic hard gate over SHA pins, checksum recomputation,
  and consumer CLAUDE.md ground-rule surfaces, and a bot-authored-advisory default to human-gated),
  executes admitted items via `work` under an adaptive item cap (start 2, +1 after 3 clean,
  ceiling 3, -1 on dirty, floor 1; frontier-tier items at concurrency 1 with ceiling 2; no ramp
  while a rate-limit warning is latched), provisions worktrees explicitly before dispatch as the
  `#572` workaround, and exits on the seam-frontier-empty plus GraphQL close-linkage condition or
  the convention's drain-terminal state. `attend-queue` is the attended lane — one merged
  attention view of worker-escalated items (human-gated role + machine-marked escalation comment),
  first-drain C3 ratifications, and untriaged intake (composing `triage`'s attention view),
  driving decisions via `/planning:interview` (presence-gated), writing answers back as issue
  comments, and flipping unblocked items to the autonomous-eligible role in a single edit. Both
  lanes hold shared loop-layer concerns by citation to the loop-lane convention, inline the
  rate-limit guard's operable floor byte-identically per its inline-floor rule, and inline the
  `claude-ops`-compatible sentinel telemetry upsert (an installed plugin cannot invoke a sibling
  plugin's scripts).
- **`work` gains an autonomous invocation path.** When invoked by a loop lane or another
  unattended context, the Step 3 confirmation prompt is not presented: the invoker names the
  already-admitted item id and states its admission gate passed, the auto-confirmation is recorded
  in the item's claim comment, and every later step — including the seam claim as the atomic
  acquisition point — is unchanged. Attended invocations keep the interactive prompt.
- **GitHub adapter "Open linked PRs" operation is draft-aware.** The GraphQL selection now
  requests `isDraft` and the operation documents two reductions: the default (drafts count — a
  draft closing PR is still in-flight work for `work`'s frontier exclusion) and a non-draft
  reduction for `work-loop`'s drain-exit evaluation, which must not treat a draft as satisfying
  the exit (review-caught).
- **Four `userConfig` keys for the work-loop adaptive cap bounds:** `work_loop_item_cap_start`
  (default 2), `work_loop_item_cap_ceiling` (default 3), `work_loop_item_cap_floor` (default 1),
  and `work_loop_frontier_item_cap_ceiling` (default 2). Enforcement is the loop body's own
  arithmetic; the composed budget with `/implementation:implement-dispatch`'s per-item wave cap
  remains interim pending `#573`.

## [0.21.4]

### Changed

- **Raw-intake marker canonicalized as dual-axis across `triage` docs and evals (`#818`).** The live
  raw marker is applied on whichever axis a consuming repo files it under — `priority:needs-triage`
  or `status:needs-triage` — but `SKILL.md`'s Triage-states table and Attention-view buckets,
  `reference/dogfood-filing.md`'s filing step, `reference/label-taxonomy.md` and
  `reference/tracker-seam.md`'s axis-grammar tables, and two triage evals described or asserted it
  as status-axis-only. All now match the dual-axis wording the "Scope: raw intake only" section
  already carries (`#802`): a consuming repo may file the raw marker under either axis, and both are
  canonical. On the Priority axis the marker is passed as the `track add` `--priority` value (a
  single-label group), replacing the `priority:p3-low` filing default rather than adding a second
  `priority:` label.

## [0.21.3]

### Fixed

- **`work`'s dispatch brief no longer lists `## Related` as a standing PR obligation (#975).**
  `/source-control:pull-request`'s PR-body scaffold is now configurable via
  `pr_body_required_sections` and no longer includes `## Related` by default — the prior wording
  enumerated it alongside `Closes #N` as if every PR carried it. The dispatch brief and the
  post-green deferred-finding step (`skills/work/SKILL.md`) now: point at pull-request's
  configurable scaffold instead of restating it, drop `## Related` from the standing-obligations
  list, and have the deferred-finding step ensure the section exists before citing a follow-up issue
  in it, rather than assuming pull-request already created one. That step is documented as a
  **read-modify-write** (`gh pr view --json body` then `gh pr edit --body-file -`), matching the
  GitHub adapter's own PR-body-edit identity note — `gh pr edit --body`/`--body-file` REPLACES the
  whole body, so a bare append-flavored write would silently drop `Closes #N` and the rest of the
  scaffold (review-caught). Eval 3 updated to match.

## [0.21.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.21.1]

### Fixed

- **Triage SKILL state machine + attention view reconciled with live labels (`#817`).** The
  attention view's bucket list named only `status:needs-triage`, leaving a repo that files raw
  intake on the priority axis (`priority:needs-triage`, per `#802`'s dual-axis Scope wording)
  invisible to the no-arg attention view; the bucket now names both axes. Separately,
  `status:needs-decision` was already referenced by the closing invariant as a routing outcome
  that clears the raw marker, but was never introduced as a side exit in the state machine itself
  (unlike `needs-info`, human-gated, and close) — it is now documented alongside them in the
  side-exits sentence and the state diagram. Doc-only; no routing logic changed.

## [0.21.0]

### Added

- **Issue-conventions reference — `reference/issue-conventions.md` (`#552` member 6).** The title
  convention (~98% of live org issues conform) and the filing body shape were load-bearing and
  written down nowhere. The new doc is the single source of truth for the TITLE convention
  (`<prefix>: <lowercase summary>`, area/path and conventional-commit prefix dialects, `Epic:` for
  umbrellas, sub-issue edges over title suffixes) and points — never copies — at the existing owners
  for body (`track add` "Build body", `agent-brief.md`), type/labels (`track add` type resolution,
  `label-taxonomy.md`), and close reason (`track done`). Cited from `track add`, `decompose`,
  `triage`, and `dogfood-filing.md`.

### Changed

- **Triage priority default is `p2-medium`; `p1-high` is reserved (`#552` member 4).** 77% of open
  issues carried `priority: high`, destroying it as a staffing signal. Triage now defaults to
  `priority:p2-medium` when no directive, category rule, or severity signal sets one, and reserves
  `priority:p1-high` for items that block other work or carry an imminent external deadline. The
  `track add` filing default (`p3-low`) is deliberately distinct — an untriaged-signal floor, not a
  priority assessment — and is now documented as such.
- **Duplicate / supersede close discipline (`#552` member 5).** Sampled closures were 100%
  `COMPLETED` — duplicates and superseded items were closing under the wrong reason. Duplicates now close via the
  provider's native duplicate mechanic where one exists (GitHub: `gh issue close --duplicate-of`,
  which sets close reason `duplicate` and a structured, API-queryable `duplicateOf` relationship),
  with the portable fallback — append a queryable `## Duplicate of #N` body section and close
  `not planned` — for cross-repo targets and providers without a native duplicate reason. Superseded
  and duplicate items never close as `completed` (triage outcome table, `track done`, GitHub adapter
  README mechanic).

## [0.20.0]

### Added

- **Mini-SDLC pipeline-shape SSOT — `reference/pipeline-shape.md` (`#613`, stage 1 of `#513`).** The
  work lane had no durable definition of the *shape* of the pipeline it runs per item — the lane
  catalog, the implementer ≠ reviewer ≠ verifier invariant, and the depth tiers lived only as evolving
  prose and per-issue plans, so the shape drifted and could not be scaled or reviewed in one place. A
  new reference doc owns that stable policy: the fixed lane set (explore → research → plan →
  devil's-advocate → implement → test → review → verify, with the re-anchor slot reserved), the
  "variation in depth, never in shape" principle, the role-separation invariant, and placeholder depth
  tiers carried as a plan field. It is a reversible reference-doc STOPGAP (form/location/name left to
  the operator per `#513`) and points at the return-payload contract (`#496`) and convention-gap
  protocol (`#554`) rather than restating them. **Scope note:** this stage lands the shape and the
  wire-in only — the depth-scaling dispatcher and the separated-reviewer/verifier runtime are later
  `#513` stages, so the doc defines the target shape and makes no claim that the runtime already
  depth-scales or fully separates roles today.

### Changed

- **`work` Step 5 dispatches against the pipeline-shape SSOT (`#613`).** The execute sub-step now
  points the dispatched chain at `reference/pipeline-shape.md` for the lane shape, additively — the
  existing instruction to follow the consuming project's own development workflow and domain rules is
  retained; the chain runs the shape *within* the consumer's workflow and rules, never in place of
  them.

## [0.19.0]

### Added

- **Jira Cloud adapter for the work-item-tracker seam (`#379`).** A new bundled `jira` adapter
  (`tools/work-item-tracker/adapters/jira/`) binds a Jira Cloud project set behind the seam,
  alongside the shipped `github` and `local-markdown` adapters; GitHub stays the default. The
  adapter is **read/resolve-only by default** (issue #379 hard constraint): `get-item`,
  `list-items`, and `capabilities` are supported; every coordination write verb
  (`create-item`/`claim`/`renew-lease`/`reclaim`/`link-blocks`/`add-sub-item`) and
  `list-sub-items` are declared `false` in the manifest and exit `6` at the core gate — no code
  path creates, claims, or mutates a Jira ticket. Reads use Jira Cloud REST v3
  (`GET /rest/api/3/issue/{key}`, `POST /rest/api/3/search/jql` with `nextPageToken` pagination)
  over `curl`; Basic auth email + API token, the token referenced by env-var name only (never
  stored in the tracked binding, never placed in argv). Normalization maps `statusCategory` →
  open/closed, single assignee → `accountId`, labels verbatim, issue type, open-only
  `blocked_by_count` under the configured link type, `fields.parent` → `parent_id`, and the
  browse URL. The blocker link type and the exact "done" `statusCategory` key are configurable
  override seams (`config.jira.blocked_by_link_type`, `config.jira.done_category_keys`),
  defaulting to the documented standards so the adapter is independent of the two live-instance
  facts deferred to the work-laptop pass. `/work-items:setup` gains `jira` as a selectable
  provider. Contract: `tools/work-item-tracker/CONTRACT.md` "jira adapter"; operations reference:
  `tools/work-item-tracker/adapters/jira/README.md`. Branch/PR `SW2-*` linkage and opt-in writes
  are sequenced follow-ups.

## [0.18.2]

### Fixed

- **GitHub adapter resolves a consumer-local `gh-bot.sh` wrapper independent of adapter location
  (`#365`).** `common.sh` resolved the bot wrapper relative to the adapter's own directory
  (`${CLAUDE_PLUGIN_ROOT}/tools/github-auth/gh-bot.sh` in the normal bundled path), so a consuming
  repo's wrapper at `${CLAUDE_PROJECT_DIR}/tools/github-auth/gh-bot.sh` — the path CONTRACT.md's
  "Identity routing" section already documented as the override — was never found, and tracker writes
  silently fell back to the ambient `gh` (session-user) identity. `wit_gh_resolve_bot_wrapper` now
  checks the consumer-local path first, falling back to the plugin-bundled path, mirroring the
  adapter's own consumer-local-first/plugin-bundled-fallback resolution (CONTRACT.md "Adapter
  resolution"). CONTRACT.md's "Identity routing" section is updated to match.

## [0.18.1]

### Changed

- **`triage` scope now keys on triage state, not authorship (`#486`).** The "Scope: raw intake
  only" section, the Purpose, and the frontmatter `description` defined raw intake as "items the
  team did not author," which contradicted the plugin's own self-observation filing contract: dogfood
  issues the team files carry only the raw marker, surface in the same attention view, and genuinely
  need triage. Raw intake is now defined as *any untriaged item carrying the raw marker, whoever
  authored it*; the "did not author" phrasing is demoted to an illustrative list of common sources.
  The paired exclusion is re-keyed too — "never re-triage already-triaged output" now turns on
  absence of the raw marker (decompose output, or a `track add` that leaves no raw marker) rather than
  `track add` authorship. The raw marker wins over coexisting default labels, so a team-authored dogfood
  issue filed with a default `priority:` label *and* the raw marker is correctly in scope while
  born-triaged items stay out. No routing-logic change.

## [0.18.0]

Extract the cross-lane self-observation filing rule ("file what you will not fix: dedupe → categorize
→ fixed shape → `needs-triage`") into one shared reference surface so the lanes reference it instead
of each absorbing a private, drift-prone copy (`#540`).

### Added

- **Shared self-observation filing contract — `reference/dogfood-filing.md`.** The rule that an
  autonomous lane files a problem it will not fix in-cycle is cross-lane-identical, so the absorption
  umbrellas (`#477`/`#478`/`#479`) must not each absorb a private copy. The new reference is the single
  in-repo source of truth: it composes the existing mechanics by pointer — the *Search items* dedupe
  read and body template `track add` owns, the `create-item` seam write, and the `needs-triage` status
  label — and adds only the self-observation policy (when to file vs the `tracker-seam.md` "Default =
  fix, not file" posture, the mechanical-vs-model split, autonomous authorization, and the AI
  disclaimer). No new script: the mechanical core is already the seam + adapter + `track add`
  machinery, so the doc references it rather than forking the template and search mechanics.

### Changed

- **`work`, `triage`, and `scan-todos` now reference the shared filing contract at their filing
  sites** — the `work` post-green deferred-finding follow-up, the `triage` follow-up-work creation,
  and the `scan-todos` "file a work item" branch each point at `reference/dogfood-filing.md` for the
  dedupe → categorize → fixed shape → `needs-triage` sequence instead of leaving it implicit.

## [0.17.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.17.1]

Paginate the github adapter's *open linked PRs* signal so the `/work-items:work` frontier filter
cannot miss an `OPEN` closing PR that sorts past the first page of linked closing PRs (`#677`).

### Fixed

- **Open-linked-PR filter now walks every page (`#677`).** The github adapter's *Open linked PRs*
  query read only `closedByPullRequestsReferences(first:100)` — a single page. Because
  `includeClosedPrs:false` still retains `MERGED` nodes, an issue with a long merge/reopen history
  (more than 100 linked closing PRs) could push its single `OPEN` closing PR onto a later page; the
  filter then saw an all-`MERGED` page, reported `false` = pickable, and the in-flight item could be
  re-picked from the frontier → double-dispatch (a duplicate PR). The documented snippet now uses
  `gh api graphql --paginate` with an `$endCursor` variable and `pageInfo { hasNextPage endCursor }`,
  walking the connection to exhaustion; `gh` applies `--jq` per page and `grep -qx true` collapses the
  per-page booleans to a single result — `true` as soon as any page carries an `OPEN` node. The
  connection exposes no server-side OPEN-state filter and no OPEN-first `orderBy`, so pagination is
  the only correct route; a `first:100` bump only moves the boundary. Refs `#668`, `#654`.
- **Open-linked-PR check now fails closed on query error.** The paginated snippet captures the
  `gh api graphql` result and checks its exit status before reducing, propagating a non-zero exit
  (and emitting no boolean) when the query fails — an expired token, rate limit, or a network error
  on a later cursor page. Previously the `… | grep -qx true && echo true || echo false` tail masked
  `gh`'s exit code and converted any failure to `false` = pickable, re-introducing the exact
  double-dispatch this fix targets precisely when the in-flight state could not be confirmed. The
  `/work-items:work` consumer now excludes the candidate this cycle on such a failure rather than
  treating an unconfirmed check as "no open PR".

## [0.17.0]

Add a loop-start permission preflight so the unattended `work` (and, by shared contract,
`source-control:babysit-prs`) lanes report a missing grant or untrusted worktree root **once, up
front**, instead of stopping for a per-operation prompt mid-cycle (`#495`). Report-only by design:
the assistant cannot self-apply the fix — the auto-mode classifier blocks an agent broadening its
own `permissions.allow`, and a plugin `settings.json` grant is inert — so the check detects and
points at the operator-side remediation, never edits settings, and never retries a denial into
broader grants.

### Added

- **Loop-start permission preflight (`#495`).** New `skills/work/scripts/preflight.sh` (with
  `preflight.test.sh`) reads the effective `permissions.allow` / `permissions.additionalDirectories`
  from user-global and project settings and reports three conditions: (a) cwd is not a git repo (a
  note — a worktree-operating lane still proceeds); (b) a probed core working verb
  (`git add`, `git commit`, `git push`, `gh pr create`, `gh issue comment`) is denied by a matching
  deny rule or is not covered by any `Bash()`/`PowerShell()` allow rule; (c) the configured
  out-of-tree worktree root is not covered by `additionalDirectories`. A verb counts as covered only
  by an **open-glob** grant (`git commit *` / `git commit:*`); a flag-scoped rule
  (`git commit --amend`, a force-with-lease-only push) is a gap, and a **bare-exact** rule
  (`git commit`) is a gap reported with a distinct message — it covers an argumentless caller (the
  babysit fix cycle's plain `git push`) but not the work lane's argument-carrying call, so the remedy
  is the open glob. Deny wins over allow: a deny rule of the verb keeps it a gap (reported distinctly
  as denied) even when allowed — matched exact-shape only (never glob simulation) so the flag-scoped
  standard deny floor is never false-flagged, but erring **wider** than coverage by also counting the
  bare spelling (a false *denied* is safe). The worktree-root check is root-agnostic (coverage of the
  passed root, never a hardcoded path), and Windows and git-bash path spellings are folded to one
  comparable form. Per-checkout `settings.local.json` handling: under `--worktree-root` with no
  distinct `--project-root` (pre-dispatch) the coverage reads exclude this checkout's gitignored
  local file, which a fresh worktree would not carry, so a local-only grant cannot mask a worker-side
  gap; a distinct `--project-root` (a named worker checkout) instead reads that worktree's OWN
  `settings.local.json`; the interactive path keeps local; deny always reads it. Always exits `0`;
  `--count` reports the GAP total for a scripted gate. No live permission probe.
- **Preflight reference (`#495`).** New `reference/permission-preflight.md` is the source of truth
  for the preconditions: it points at the `melodic-software/standards` `claude-permissions`
  component (`components/claude-permissions/`, composed operator-side via the dotfiles chezmoi seam)
  as the canonical allow/deny floor rather than restating a list, documents the trusted
  sibling-worktree-root `additionalDirectories` guidance, and records the detect-and-report /
  never-self-apply contract. The `work` skill wires the check as the first loop-start action, ahead
  of the binding preflight.

## [0.16.1]

### Fixed

- **Triage side-exit routing now clears the raw-intake marker on every outcome (`#562`).** The
  closing invariant in the triage skill only named `status:ready` and the two role labels as
  contradictory with the raw marker, and pinned the marker to a single hardcoded label string. A
  status side-exit — `status:needs-decision`, `status:needs-info`, human-gated (`needs-human`), or
  the terminal `status:ready` — could leave `needs-triage` attached, so an already-decided item
  (e.g. `#505`, routed to `status:needs-decision`) resurfaced in the next cycle's needs-triage queue
  as if it were unrouted intake, wasting a read-and-confirm pass every cycle. The invariant is now
  exhaustive across the routing space — **every** open-keeping outcome removes the raw marker in the
  same edit — and framed around the abstract raw-intake marker resolved from the live label set
  rather than a hardcoded prefix, so it holds regardless of which axis a repo files `needs-triage`
  under. Doc-only; absorbed into the triage `SKILL.md` alongside the `#478` routing rules.

## [0.16.0]

Close the work-item-tracker seam's container read-verb gap (`#498`): the seam reserves `work-map`
containers as a first-class use case but had no way to operate one within scope. The frontier was
repo-global only, its rows dropped parent linkage, an unassigned/unblocked container surfaced as its
own frontier item, and no verb enumerated a container's children — collectively blocking a clean
container-based consumer (surfaced by the `#416` wayfind-routing planning pass). Related but distinct:
`#416` (the wayfind consumer) and `#379` (the Jira adapter, a different backend).

### Added

- **`list-sub-items <parent-id> [--state open|closed|all]` (new seam + adapter verb).** Enumerates a
  container's DIRECT children as full normalized item objects (same `{items:[…]}` envelope as
  `list-items`), each re-parented to the container. Raw enumeration — closed and nested-container
  children are kept, so the "decisions-so-far" closed-children invariant check and sub-map traversal
  both have a seam path. `--state` defaults to `all`. Both adapters implement it: the GitHub adapter
  resolves children through the native `subIssues` link and intersects with `list-items` (its list
  surface omits parent linkage), so its truncation bound is `list-items`' own (`list_items_max`);
  the offline `local-markdown` adapter matches on the stored `parent` frontmatter.
- **`list-frontier --parent <container-id>` (container-scoped frontier).** Scopes the frontier to one
  container's children — core reads `list-sub-items` for that container instead of the repo-global
  `list-items`, then applies the identical filter. Gates on the adapter's `list-sub-items` capability.

### Fixed

- **A container is never its own frontier item (`#498` obs #3).** `list-frontier` now excludes any item
  carrying the container label (`work-map`) unconditionally — global and `--parent`-scoped alike, and
  under `--autonomous` — fixing the correctness wart where an unassigned, unblocked container passed the
  frontier filter and surfaced itself. The container label is a named constant (`WIT_CONTAINER_LABEL`)
  matching the CONTRACT term; per-repo remapping is deferred to the `config.role_labels` convention.
- **`list-frontier --parent` rejects `--repo` instead of silently dropping it (`#498`).** A container is
  addressed by its qualified id, which already carries the repo, so `--repo` cannot re-target a
  container-scoped frontier. The scoped path never threaded `list_args`, so a caller passing both flags
  had `--repo` silently ignored. Passing both is now a usage error (exit `2`) with a clear message,
  matching the seam's fail-loud convention for invalid arg combinations.

## [0.15.0]

Close the work-items entry-invariant gap where a missing provider binding (`.work-item-tracker.json`)
degraded silently — role labels fell to defaults with no signal, and seam coordination verbs surfaced
a raw mid-flow `exit 3` instead of an actionable message (`#449`). The full remote / no-checkout mode
(shallow-clone or `gh api`-backed codebase reads) stays deferred with a recorded trigger.

### Added

- **Binding presence is a third loud entry invariant (`#449`).** "Shared tracker context" now checks
  the provider binding alongside `jq` and the seam script, but discharges it distinctly: the first two
  have no recovery path and stop; a missing binding is loud and routable, never a silent default and
  never a raw `exit 3`. Seam **coordination** verbs (`create-item`, `get-item`, `claim`, `renew-lease`,
  `reclaim`, `link-blocks`, `add-sub-item`, `list-frontier`, `capabilities`) cannot run unbound, so
  before the first one the skill surfaces a message distinguishing **setup was never run** (→
  `/work-items:setup`) from a **deliberate gh-native
  operating mode** (proceed for provider-mechanic operations only, accepting no race-safe claim/lease).
  Provider-mechanic operations (list/search/close, label/comment edits) run as raw `gh`, never read
  the binding, and proceed unbound. Caveat recorded: the gh-native path presumes a `gh`-backed
  provider — a `local-markdown` target with no binding cannot proceed and stays a hard stop.
  `/work-items:work` gains an explicit binding preflight **before Step 0** — its `reclaim` is the
  lane's first coordination verb, so the check is discharged before it runs rather than surfacing as a
  raw mid-reclaim `exit 3`.

### Changed

- **Silent role-label default becomes a loud warning (`#449`).** When a canonical role resolves to its
  documented default because `.work-item-tracker.json` or its `config.role_labels` entry is absent, the
  skills now warn loudly instead of substituting silently — a repo that remapped `config.role_labels`
  was previously queried under the wrong strings with no signal. Applied at every action-entry
  resolution site that inlines it (`work`, `triage`, `track` — `SKILL.md` summary plus
  `due`/`recheck`/`audit` — and `decompose`) and in the shared invariants (`reference/tracker-seam.md`,
  `reference/label-taxonomy.md`). A present-but-malformed, empty, or non-string configured value
  remains a hard stop, unchanged.

### Deferred

- **A first-class gh-native no-lease claim path for coordination-*dependent* lanes (`/work-items:work`)
  is parked, not built (`#449`).** Making those lanes runnable unbound (assignee-only claim, no lease,
  races are the operator's problem) is claim-safety contract surface — deferred with the same trigger
  as the full remote-repo mode: someone needs unattended coordination-dependent work at scale.

## [0.14.4]

### Fixed

- **`/work-items:work` Step 5 guards against loop-prompts that restate dispatch without the claim (`#581`).**
  Step 5's sequence already put the seam `claim` (assignee + lease) first, but a hand-authored loop-prompt
  standing-rule that restates "dispatch every picked issue to a subagent in its own out-of-tree worktree"
  reads as a complete execution contract on its own and never mentions claiming — so an orchestrator
  following that loop-prompt literally did the worktree isolation and skipped the seam's race-safe claim
  entirely (observed twice on live loop-lane sessions, leaving actively-worked issues unassigned with no
  lease). A prominent guard note at the head of Step 5 now states the claim-before-dispatch invariant the
  skill enforces regardless of loop-prompt wording: worktree isolation is not the collision signal between
  concurrent lanes, the seam claim is, and dispatching a subagent before the claim is held is a defect even
  when the loop-prompt never named the claim step. Documentation/guidance only — no skill-code or seam
  behavior change; eval 1 gains a matching expectation.

## [0.14.3]

### Fixed

- **GitHub adapter `renew-lease` no longer revives an expired lease (`#370`).** `renew-lease` confirmed
  the handle still matched the active (newest non-superseded) lease but never checked liveness, so a
  crashed or delayed holder retaining its handle past `renewed_at + ttl_hours` — with no newer lease
  comment — could PATCH a fresh `renewed_at` and reclaim an item another worker had reasonably treated
  as expired, defeating TTL-based handoff. It now checks `wit_lease_is_live` immediately before
  patching and returns a conflict (exit `7`) for an expired lease instead of reviving it.
- **GitHub adapter `reclaim` unassigns only the expired lease's holder (`#370`).** On the expired-lease,
  no-activity path `reclaim` read all assignees and removed every one, silently unassigning a user
  added manually after the old lease or a concurrent claimer added before the snapshot — in the
  concurrent case leaving that claimer's live lease in place while the frontier treated the item as
  unassigned (two workers on one item). Removal is now scoped to the lease's `holder`, and ownership is
  revalidated immediately before mutating (the lease must still be the active, expired lease) so a
  concurrent claim during the activity-check window aborts the reclaim as a no-op rather than stripping
  the new owner. The shared active-lease selection is extracted to `wit_select_active_lease`
  (`lib/lease.sh`), reused by both verbs.

## [0.14.2]

### Fixed

- **Local-markdown expired lease returns the item to the frontier (`#367`).** For the `local-markdown`
  binding an expired lease still left `assignees` populated, and since `reclaim` is unsupported for
  this offline adapter (no coordination surface to run an activity check over) and `list-frontier`
  always excludes assigned items, any abandoned local claim was permanently absent from selection after
  its TTL expired. `list-items` now projects the effective assignee of an expired-lease item as empty,
  so the core frontier derivation returns it to the frontier — without inventing a new adapter
  capability. The projection is scoped to list/frontier derivation; `get-item` still reports the stored
  assignee verbatim (parity with the GitHub adapter, whose assignee persists until reclaim).
- **Local-markdown claim no longer reports success on a failed assignee write (`#367`).** `claim`
  appended the inline lease marker and then set `assignees` with no return-code check, so a failed
  assignee write (store full or unwritable) was silently ignored and a successful claim JSON was still
  emitted — leaving a live lease marker with an empty `assignees`, which `list-frontier` presents as
  available while later claims conflict on the live lease until it expires. The two writes are now a
  single consistent operation: a failed assignee write rolls the just-appended marker back and fails
  the claim (exit `1`), emitting no success record for a half-applied write.

## [0.14.1]

### Fixed

- **Open-linked-PR filter no longer wrongly drops issues from fenced examples (`#654`).** The GitHub
  adapter's "Open linked PRs" mechanic (`#463`) matched a closing-keyword `jq` regex over the raw
  PR body, so a PR body carrying a fenced `Closes #<N>` example spuriously reported issue `#<N>` as
  having an open closing PR and dropped the still-pickable issue from the `/work-items:work`
  frontier. The mechanic now reads GitHub's own computed close-linkage via the GraphQL
  `Issue.closedByPullRequestsReferences` connection (open-state nodes only), which excludes fenced
  code blocks and HTML comments, needs no word/number-boundary guards, and honors the default-branch
  requirement — retiring the raw-body regex and its partial `gsub` fence-stripper (which recognized
  only exactly-three backtick/tilde fences). Behavior change: an issue whose only `Closes #<N>` is on
  a non-default-base PR now stays pickable, matching GitHub's real auto-close semantics.

## [0.14.0]

Absorb bullets 1–4 of the v4 loop-prompt routing rules into `/work-items:triage` so the skill owns
them instead of a session prompt (`#478`). Bullet 5 stays deferred to `#459` (pointer only); bullet 6
(`wayfind:*` label semantics) is cross-repo label policy noted on `github-iac#176` and untouched here.

### Added

- **Decision-defaulted ready route (`#478`).** "Triage states" now documents three briefed exits —
  delegable, decision-defaulted, human-gated. A single-fork item whose brief carries a well-grounded
  RECOMMENDED answer with only a maintainer-vetoable (reversible) alternative routes to the
  autonomous-eligible role with `status:ready` plus a `Decision defaulted: X — veto before merge`
  comment, instead of falling to human-gated. "Recommend category + state" carries the routing test
  (reversible/maintainer-vetoable → defaulted; genuinely open → human-gated) and "Apply outcome" adds
  the matching row.
- **Cluster-aware routing (`#478`).** "Gather context" adds a cluster-detection cross-reference: when
  several open items share one underlying decision, one representative becomes the decision carrier
  (human-gated, member numbers in its body) and each member links to it via the native `blocked-by`
  edge with a `blocked by #<carrier> decision` comment — no per-member human-gated label. One human
  touch per decision. No new labels.
- **Multi-surface T1 stub (`#478`).** "Apply outcome" adds a lightweight briefing variant: a trivial
  (T1) fix spanning 3+ surfaces gets a one-line `sites + fix pattern` comment in place of a full brief
  and still takes the autonomous-eligible role. The brief durability rule holds — name sites by
  interface / symbol / domain concept, not file paths or line numbers (recommended default:
  symbol-level naming).
- **Severity sub-sort (`#478`).** The priority-label step now records the finding's self-labeled
  severity in the triage comment (`priority set to pX by <rule>; reporter severity: <sev>`) when a
  directive or category rule sets the `priority:` label above it, so implementers can sub-sort within
  a priority band. No new labels.

### Changed

- **Human-gated narrowed (`#478`).** The human-gated briefed exit is reserved for a genuinely open
  decision (open design space, product intent, cross-repo policy) or a capability blocker (external
  access, manual QA), distinguishing it from the new decision-defaulted route.

## [0.13.1]

### Fixed

- **`status: ready` issues with an open linked PR are no longer pickable (`#463`).** `/work-items:work`
  selection now excludes a frontier candidate (tiers 2–3) that already has an open PR targeting it for
  closure, closing the re-pick risk where an issue kept `status: ready` for its entire open-PR window and
  a picker had to hand-cross-check `gh pr list` to avoid starting a duplicate branch. The check routes
  through a new GitHub adapter *Open linked PRs* mechanic (closing-keyword linkage — the same `Closes #N`
  signal `pr-issue-linkage` enforces — is authoritative; an intentional `Refs #N` opt-out does not
  exclude), and fails open when the bound provider exposes no PR host (offline `local-markdown`). This
  retires the interim in-flight heuristic that lived in the execute-step staleness pre-check. The durable
  seam-level in-review state is deferred to the tracker-seam layer (`#416`/`#498`), not built here.

## [0.13.0]

Absorb the v4 loop-prompt execution rules into `/work-items:work` so the execute step owns them
instead of a session prompt, delegating anything a sibling skill already owns rather than restating it.

### Added

- **Orchestrator-dispatch is the documented default for autonomous execution (`#451`).** The execute
  step's generic "follow the project's development workflow" deference now states the default posture:
  pick and claim, then dispatch a scope-fenced implementation subagent that edits source in its own
  out-of-tree worktree — the orchestrator never edits source. Dispatch *mechanics* are chained to
  `/implementation:implement-dispatch` (not re-described); worktree lifecycle stays with
  `/source-control:worktree`; the interactive all-inline path remains `/implementation:implement`.
  The autonomous dispatch handoff (branch/worktree provisioning before the dispatch preflight and
  orchestrator-owned PR creation) is not yet guaranteed end-to-end — deferred to `#572`.
- **The dispatch brief carries the PR contract forward (`#462`).** The brief relays what
  `/source-control:pull-request` will require at PR time — that skill still owns the PR body shape,
  `Closes #N` injection, and merge style — enumerating the version-bump, CHANGELOG, attribution-trailer
  plus session link, and `## Related` obligations so a worker knows them up front, not via red CI.
- **Post-green review pass with work-item linkage.** After CI green, one review pass fixes branch-owned
  findings via the owning subagent; the fetch → validate → classify → reply → resolve loop stays owned
  by `/source-control:pull-request`. A VALID-but-deferred finding now requires a follow-up issue filed
  via `/work-items:track add`, cited in the reply and in `## Related`, before it can be resolved. The PR
  then hands off to `/source-control:babysit-prs`.
- **High-blast-radius pre-PR diff gate.** The orchestrator does a full-diff read before opening a PR
  when the diff touches skill frontmatter descriptions or trigger keywords, cross-plugin contracts, or
  hooks — complementing the worker scope-fence with an orchestrator read of what actually changed.
- **Concurrency and batch caps as `userConfig`.** New `work_dispatch_concurrency_cap` (default mirrors
  `/implementation:implement-dispatch`'s 3–5 wave cap) and `work_cycle_batch_cap` scalars; the execute
  step resolves them from config with no hardcoded literal. Enforcement is not yet wired — these are the
  *intended* values (implement-dispatch still applies its own internal cap and no consumer reads the batch
  cap), with threading into the delegated dispatch and driving loop tracked in `#573`. A batch cap bounds
  one CYCLE, never the loop
  — cap-reached or frontier-drained ends the cycle only, not autonomous operation (loop wakeup and delay
  stay owned by `/loop`). Same-plugin serialization carries an interim awareness note pending `#464`.
- **Explicit never-merge boundary.** The skill states that `work`'s lane ends at PR creation and
  handoff; merging is the babysit lane or a human, never `work`.

### Changed

- **Selection skips a frontier item that already has an open PR (interim, retire on `#463`).** The
  staleness pre-check advances past an in-flight item rather than starting a duplicate branch, until the
  durable in-progress marker lands and the frontier excludes in-flight items itself.

## [0.12.3]

### Fixed

- **Triage's step-2 wait-gate no longer contradicts its own autonomous mode.** The "Recommend
  category + state" step ended with a flat "Wait for the user's direction before mutating anything,"
  while the AI disclaimer section presupposed the opposite — autonomous/agent sessions that mutate
  without a human turn. No branch selected between them, so an operator following step 2 could not triage
  autonomously and an autonomous lane necessarily violated step 2. The gate is now an explicit
  two-branch direction gate: interactive sessions (a human present, no standing lane rules) keep the
  wait-gate; autonomous `/loop` / `/schedule` AFK lanes treat their standing rules as the direction
  the gate requires and proceed without a human turn (the mode the AI disclaimer already anticipates),
  so the gate is satisfied by the lane's mandate rather than silently ignored.

## [0.12.2]

### Fixed

- **Triage outcomes now clear the raw-intake marker.** The `triage` skill's "Apply outcome" step
  listed the labels each outcome adds but never said to remove `status:needs-triage`, so applying an
  outcome stacked `status:ready` and the role label on top of the raw marker. The attention view
  re-selects any open item still carrying the marker, so triaged items re-triaged every cycle
  (silent-loop-kill class). Step 5 now states that every outcome is a transition off raw that
  replaces the marker rather than adding to it, and a closing invariant forbids a raw marker
  alongside a briefed/ready or role label on an open item.

## [0.12.1]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/prototype:pressure-test`); behavior unchanged.

## [0.12.0]

Bundle the work-item-tracker seam into the plugin so installing it delivers the engine and the
shipped adapters — no per-repo vendoring. Executes shape A of the tracker-seam distribution decision.

### Added

- **The seam ships with the plugin.** The dispatcher, `lib/`, `CONTRACT.md`, the `github` and
  `local-markdown` adapters, and the conformance suite now live under
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/`. A consuming repo gets the seam by installing the
  plugin; it no longer has to vendor `tools/work-item-tracker/` itself.
- **Two-rule resolution.** Seam code resolves **plugin-dir canonical, project-root fallback**;
  adapters resolve **consumer-local-first, plugin-bundled fallback** (first match wins). A repo can
  add a provider the plugin does not ship, or shadow a bundled adapter with a local copy it owns, at
  `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/` — without forking the plugin
  (CONTRACT.md "Adapter resolution").
- **Provider binding in setup.** `/work-items:setup apply` now seeds `.work-item-tracker.json`
  (provider + non-secret config) as the once-per-repo binding step, run first — ahead of the
  recurring-schedule and role-label passes; `/work-items:setup check` verifies the binding's presence
  and validity read-only. The binding step extends the uniform check/apply contract [0.11.0]
  established rather than adding a second setup surface. The seam still hard-errors (exit 3) at call
  time when no binding is present.

### Changed

- **Skill seam invocations resolve the bundled dispatcher first.** Each executable snippet resolves
  `"$TRACKER"` plugin-dir-canonical with a project-root fallback, then invokes it; doc citations point
  at `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/...`.
- **Adapter operations reference and CONTRACT are provider-neutral.** The GitHub adapter reference and
  the contract no longer cite a specific consuming repo's convention docs or bot-auth wrapper; writes
  optionally route through a bot wrapper when the consuming repo provides one, otherwise bare `gh`.
- **Adapters hard-fail on a missing shared seam lib.** `github` and `local-markdown` `common.sh`
  verify each required `lib/` helper exists before sourcing and exit 3 with a diagnostic if absent, so
  a consumer-local adapter shadow that cannot resolve the bundled `lib/` fails loudly instead of
  silently emitting a malformed (empty-id) record.

## [0.11.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects read-only the tracked
  `.github/recurring-schedule.json` (presence — absent is INFO, since `due` / `recheck` / `work` degrade
  gracefully — JSON validity, and the unique `id`/`title` reconciliation keys), the `jq` and
  tracker-seam entry gates (probed via `reference/tracker-seam.md`, not restated), and the
  recurring-maintenance role label, reporting a PASS/FAIL/INFO table; `apply` runs the
  interview-seed-reconcile flow and the optional role→label remap, then re-runs `check` to verify. The
  schedule shape, reconciliation logic, and role-label invariants are unchanged; the read-only
  inspection path and the `check | apply` argument-hint are new.

## [0.10.0]

### Changed

- **Runtime prerequisites declared and classified** (prerequisite-visibility
  wave). README Requirements now name Bash + `jq` (Git Bash on native
  Windows, where `jq` is a separate install) and classify `jq` as required
  for correctness — stop with the install remediation, never improvise a
  parse. The tracker-seam reference gains an explicit entry-point presence
  check for the seam script with a remediation pointer
  (`tools/work-item-tracker/CONTRACT.md`, `/work-items:setup`) instead of
  failing on the first verb.

## [0.9.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` names the
  tracker as the contract's cross-lane index — tickets point, never store primary artifacts;
  `/work-items:decompose` ticket provenance now cites the PR carrying the source plan instead of
  the contract-slice path, which is pruned before merge and would dangle. Pre-PR publishes record
  slug + phase (a label, not a path) and backfill the PR reference as a comment once it opens.

## [0.8.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.8.0]

### Changed (breaking)

- **Skill renamed: `scan` → `scan-todos`.** `/work-items:scan` no longer exists; invoke
  `/work-items:scan-todos`. Under the `work-items` namespace the bare verb read as scanning
  tracker items; the skill sweeps the codebase's source comments for TODO/FIXME/HACK/XXX
  markers, so the name now states its object. No behavior change; no alias or renames-map
  entry — clean break per the marketplace's settling-phase rename policy.

## [0.7.0]

Split the single `work-items` action-router skill into five focused skills. The capability set is
unchanged — the same taxonomy, seam, canonical-role remap, and recurring-schedule behavior — only
decomposed so each surface is invoked directly. The separate `setup` skill is unchanged.

### Changed (breaking)

- **One skill → five skills.** The `work-items` skill (an action router over 13 actions) is
  replaced by five skills. The nine backlog-CRUD verbs stay behind a sub-action router in `track`;
  the four multi-step surfaces each become a standalone skill. Invocation mapping:

  | Old | New |
  |-----|-----|
  | `/work-items:work-items` (bare — stats dashboard) | `/work-items:track` (default = stats dashboard) |
  | `/work-items:work-items {stats\|list\|add\|start\|done\|due\|recheck\|search\|audit}` | `/work-items:track <action>` |
  | `/work-items:work-items triage` | `/work-items:triage` |
  | `/work-items:work-items work` | `/work-items:work` |
  | `/work-items:work-items decompose` | `/work-items:decompose` |
  | `/work-items:work-items scan` | `/work-items:scan` |

- **Shared context lifted to the plugin level.** The tracker seam, operation routing, label
  taxonomy, canonical-role resolution, recurring-schedule note, integration points, and gotchas —
  previously repeated in the router body — now live once in `reference/tracker-seam.md`, and each
  skill references it via `${CLAUDE_PLUGIN_ROOT}`. The `label-taxonomy.md` and `agent-brief.md`
  references and the `checklist.md` template moved from the skill directory to the plugin root
  (`${CLAUDE_PLUGIN_ROOT}/reference/…`, `${CLAUDE_PLUGIN_ROOT}/templates/…`) so all five skills
  share one copy; `topic-docs.md` was already there.

### Added

- **Per-skill eval coverage.** Each new skill ships its own `evals/evals.json`: `track` (empty-args
  stats default + the remapped-role due/recheck/audit cases), `work` (auto-select-and-claim + the
  remapped-role frontier case), `triage` (PR-as-item, verify-before-interview, never-re-triage
  decompose output), `decompose` (vertical-slice HITL/AFK dependency ordering), and `scan`
  (single-pass sweep + marker classification). The `work` case's workflow-chain example was updated
  to the current cross-plugin skill names.

## [0.6.0]

Raw-intake triage, canonical role labels, and the rejected-concept ledger check.

### Added

- **Canonical-role → label mapping.** The skills now speak three canonical roles —
  `autonomous-eligible`, `human-gated`, `recurring-maintenance` — and resolve each repo-actual
  label string from the tracker binding (`.work-item-tracker.json`, `config.role_labels`).
  Defaults are the previous literals (`agent-ready` / `needs-human` / `recurring`), so existing
  consumers need zero migration. The role table and binding shape live in
  `reference/label-taxonomy.md` "Canonical roles"; `/work-items:setup` offers the remap interview
  (with an existence check on the target label and a warning that `human-gated` is shared with the
  seam's `list-frontier --autonomous` exclusion).
- **Rejected-concept ledger check at intake.** When the consuming repo keeps a ledger
  (`docs/out-of-scope/`, one file per concept), `add` and `triage` match incoming requests against
  it by concept similarity and answer from the ledger — appending the request to the concept
  file's "Prior requests" log — instead of re-litigating a prior rejection. `triage` records a
  newly rejected enhancement there and links it from the closing comment; already-implemented
  closes are never ledgered. Degrades gracefully: no `docs/out-of-scope/`, no check.
- **Triage eval coverage** — PR-as-item routing, verify-before-interview ordering, and the
  never-re-triage-decompose-output exclusion.

### Changed

- **`triage` reworked as the raw-intake state machine.** Triage now covers items the team did not
  author — bug reports, incoming feature requests, and unsolicited PRs — through
  raw → verified → briefed → autonomous-eligible, with side exits to needs-info, human-gated, and
  close. An unsolicited PR enters the same intake as an issue: its diff is an attachment to
  evaluate, never an obligation to merge. Verification (reproduce the bug / confirm the diff does
  what it claims) precedes any interview, and a briefed outcome follows the agent-brief
  durability-over-precision rule (behavioral contracts, no file paths or line numbers). Items
  published by `decompose` are born triaged and never re-enter the flow.
- **Re-read-before-write + append-only discipline** on multi-turn shared artifacts (the recurring
  schedule, the checklist ledger, out-of-scope concept files, the tracker binding): re-read from
  disk immediately before writing and append/merge rather than rewriting from a stale in-context
  copy.

## [0.5.0]

Adopt the marketplace topic-docs convention (`docs/conventions/topic-docs/`, contract v1.0.0).

### Added

- **`reference/topic-docs.md`** — the plugin's binding to the contract: which paths the skill reads
  and writes per tier (the `work-items-checklist.md` ledger and ad-hoc notes are memory-tier under
  `.work/<slug>/`; tracker projections go through the seam, never files), the slug spec and
  self-ignore guard, and the two-location plan/PRD lookup.

### Changed

- **`decompose` default source moved to the contract tier.** The topic's `PLAN.md` / `PRD.md` now
  resolve via a two-location lookup: `docs/topics/<slug>/` (contract slice on the task branch,
  default) → `.work/<slug>/` (`contract_tier: local`). Previously the default was `.work/<slug>/`,
  which the convention classifies as memory tier — plans are contract documents. The prior
  `.claude/notes/<slug>/` location is retired outright — no compatibility layer; move residual
  content manually.
- The checklist emit path (`.work/<slug>/work-items-checklist.md`) is now governed by the binding:
  `<slug>` derives per the shared slug spec and the session's first memory-tier write verifies the
  resolved memory root's self-ignore guard (a `.gitignore` containing `*`, created and announced
  when absent).

## [0.3.0]

### Added

- **Re-runnable `setup` skill for the recurring-schedule seam.** `/work-items:setup` interviews the
  consumer, infers candidate recurring items from the repo layout (dependency manifests, lint config,
  CI workflows, security surfaces), and writes the tracked `.github/recurring-schedule.json` — the
  bulk / initial-config path complementing the per-item `add --recurring`. Idempotent: re-run to
  reconfigure. Seeds new rows with today-based dates but never advances an existing row's cadence
  clock (that stays `recheck`'s job), ensures the load-bearing `recurring` label exists, guards `id`
  and `title` uniqueness (both reconciliation keys), and reconciles a renamed row's still-open
  `[Maintenance]` item.

### Fixed

- `due` and `work` now match a due recurring item's tracker item by the **full** `[Maintenance]
  {title}`, exact — never a bare prefix or substring — so a shorter title cannot spuriously match a
  longer item's record.

## [0.2.0]

Re-plumbed onto the provider-neutral work-item-tracker seam. The skill is now backend-agnostic; GitHub
is the bound adapter today rather than a hardcoded dependency.

### Changed (breaking)

- **Provider-neutral over the tracker seam.** Every tracker operation routes through the
  work-item-tracker seam — the skill calls `tools/work-item-tracker/work-item-tracker.sh <verb>` and the
  bound provider adapter executes it (contract: `tools/work-item-tracker/CONTRACT.md`). The skill core
  inlines **no** provider commands: coordination (create, claim, renew/reclaim lease, dependency links,
  sub-items, frontier selection, single-item fetch) uses seam verbs, and provider mechanics (filtered
  listing, search, aggregation, close, label/comment edits) reference the bound adapter's operations
  doc. Previously the skill called `gh` directly throughout.
- **Claim protocol is now assignee + lease, race-safe at the seam.** The label-based
  hold&nbsp;→&nbsp;verify&nbsp;→&nbsp;claim dance (`status:considering` / `status:claimed`) is retired.
  Claiming assigns the item and writes a lease comment; races are resolved by lease-comment identity,
  and a session-start `reclaim` runs idempotently to recover crashed sessions' stale leases. The claim
  identity is always the authenticated session user, never a shared bot.
- **New consumer requirement.** The consuming repo provides the seam at `tools/work-item-tracker/` and
  binds its active provider in `.work-item-tracker.json`. The skill no longer shells out to `gh` on its
  own; the GitHub adapter behind the seam does.

### Changed

- Backend-neutral vocabulary throughout — "work item" rather than "GitHub issue"; the description and
  action docs read against any bound provider.
- Removed the skill's `gh`-scoped `allowed-tools` and the inline `gh`-based pre-computed dashboard
  block; the dashboard now derives through the seam and adapter.
- The agent-brief template ships at `reference/agent-brief.md`.

## [0.1.0]

- Initial release: a GitHub-Issues work-item tracker skill — `stats`, `list`, `add`, `work`, `start`,
  `done`, `due`, `recheck`, `search`, `scan`, `audit`, `decompose`, `triage` — with a `gh`-backed
  hold&nbsp;→&nbsp;verify&nbsp;→&nbsp;claim multi-agent claim protocol.
