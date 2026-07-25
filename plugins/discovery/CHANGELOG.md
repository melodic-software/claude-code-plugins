# Changelog — discovery plugin

## [0.8.5]

### Added

- **`/discovery:research` — artifact ladder for the primary-source-first protocol.** A SEARCH order
  over the artifact CLASSES the same claim is published at (deepest technical artifact — for a model
  or benchmark claim the system/model card — → platform reference → product docs → changelog →
  announcement → third-party), complementing the doc-index probe that enumerates pages. It does not
  reorder authority: the tier table still ranks that, and the recency gate's changelog cross-check
  stays unconditional. Stopping at an announcement page — the shallowest rung that still carries the
  claim — and reporting a figure as unsourced is the failure this closes. Gate criterion 9 checks it.
- **Outcome-gate criteria 9 and 10** — 9: for every ACCEPTED claim taken from a publisher's own
  artifacts (vendor, OSS maintainer, or standards body — matching the ladder's own reach), the fetch
  log must account for every rung above the one the claim came from, each recorded as
  probed-and-lacking-the-claim or as unreachable-and-enumerated as a Gap. An unprobed "nothing deeper
  exists" would let the shallow run this criterion targets nominate its own landing page as the top,
  and a bare probe record would let a run log the deeper artifact it found and source from a
  shallower rung anyway; the unreachable route keeps the graceful-degradation contract intact. 10:
  every reported absence must name both the checked
  and the unchecked set. The broad-topic eval gains concrete thresholds and a does-NOT-meet clause so
  criterion 10 is exercised against a real negative rather than passing vacuously, and its
  outcome-gate expectation is updated to match.

- **The fetch log is now a written output-contract section**, not a term the gate referred to without
  anything producing it. Criteria 6 and 9 are graded against it, so it exists as
  `Claim | URL or command | artifact-ladder rung | tool used | outcome` with, per accepted claim, an
  entry for the rung the claim came from and one per rung above it — plus, for a claim whose subject
  ships releases, its latest-release/changelog entry, because criterion 6's cross-check does not
  depend on which rung supplied the claim, and a claim sourced above the changelog rung would
  otherwise leave the recency gate graded from recollection. That entry's outcome is composite,
  because one changelog fetch can serve the ladder walk and the cross-check at once: the ladder value
  where the walk reaches that rung, plus the confirmed-latest version and date and a verdict of
  `current`, `invalidated`, or `unresolved`. Criterion 9 reads the first half and criterion 6 the
  second, so neither stands in for the other; recording the rung as fetched without its verdict was
  the same recollection hole one level down — criterion 6 is graded off this log, so a run could file
  the required row and still derive the currency judgement from memory. Entries are keyed by claim
  because
  criterion 9 is evaluated per claim and one artifact routinely carries claim A while lacking claim B. Without it criterion 9 could only be
  answered from recollection — which the gate's own preamble says does not bite — and a fresh session
  could not audit the ladder evidence at all.

### Changed

- **A fetch size failure now routes into the existing escalate-on-block ladder** rather than reading
  as a dead end: a content-length rejection or a silent truncation is a fetcher limit, not a source
  limit. Recipe — download out of context, confirm the file is the artifact and not a 200
  login/consent/bot-challenge page, extract with whatever extractor the machine has, grep. Each
  download lands under a claim-and-URL-derived filename inside its own `mktemp -d` directory —
  parallel workers sharing a fixed `doc.pdf` could overwrite one another mid-validation and cite the
  wrong document, a claim slug alone collides as soon as one claim is chased across two URLs, and
  even the full stem collides when two parallel queries chase the same claim to the same URL. The
  uniqueness rides the directory rather than the filename because BSD `mktemp` replaces only trailing
  `X`s, so a `…-XXXXXX.<ext>` template fails outright on macOS. The discovered URL is bound as
  single-quoted data rather than interpolated into the `curl` line: `$()` and backticks are legal in
  a URL path and expand inside double quotes, so a hostile link would otherwise run as code before
  the fetch. The artifact downloads extensionless with `-D` capturing the headers from the same
  transfer — naming the file by type up front is circular, since the path must exist before the
  response that reveals the type, and re-fetching to learn it costs a second full transfer of a
  large or single-use signed download. The recorded `Content-Type` is corroborating evidence in both
  directions and decisive in neither: a challenge page and the real spec are both `text/html`, and a
  valid PDF served as `application/octet-stream` is confirmed by its signature rather than rejected
  for its type — otherwise a complete local download gets reported as unreachable. Extraction is checked for usable text
  before it counts as a search: an extractor exits 0 on a scanned or image-only PDF and returns
  nothing, so empty or garbled output routes to another extractor, OCR, then escalation rather than
  becoming a false "not found" about a source nobody read. An
  unconfirmed download routes back through the full escalate-on-block order and does not count as the
  recipe having run, so it can never manufacture a premature "unreachable". "Unreachable" is reserved
  for exhaustion, of which there are two kinds: extraction that failed after escalation also failed,
  and acquisition that failed through every rung — a source answering the direct fetch and every
  fallback with a login, challenge, or block never yields an artifact to confirm, and the recorded
  full walk is what earns the status. Neither covers the opposite mistake: an artifact that WAS
  confirmed, extracted, and searched is a REACHED source that belongs in the checked set even when
  the claim is not in it.
- **Absence claims ship their enumeration.** A negative finding states the sources actually checked
  AND the sources left unchecked, never a bare "unsourced" / "not found" — an absence claim is only
  as strong as the set it was checked against. Stated at the `Gaps` output contract, gated by
  criterion 10.

## [0.8.4]

### Changed

- **Setup no longer hardcodes a publisher and repository name in the schema reference.** The skill
  pointed at a `raw.githubusercontent.com/<publisher>/<repo>` URL for `topic-docs.schema.json`,
  binding a runtime-consulted reference to one forge account inside a plugin that is otherwise
  publisher-agnostic — a fork, a mirror, or a rename leaves the skill citing someone else's schema.
  It now names the schema by the convention's own filename and defers to
  `reference/topic-docs.md`, this plugin's binding, which already carries the single pointer to the
  published convention. One coupling site per plugin instead of two, and the one that remains is the
  file whose job is to cite upstream.
- **The setup skill now says why its body matches `verification`'s byte-for-byte.** Most of it does,
  and nothing on the page said whether that was a shared source to extract or a coincidence to
  leave alone — so the next reader either re-litigates it or "deduplicates" two skills that are
  supposed to be free to diverge. They are: both restate rules the topic-docs contract and the
  marketplace setup contract already own, which is what a `SKILL.md` must do since it cannot defer
  at runtime to a document the consuming repo lacks. `planning` renders the same rules in its own
  prose and already disagrees with both on two of them. A maintainer note at the block points at
  the contract's new "Implementers restate the rules" section, which carries the reasoning and the
  trigger that would reopen extraction.

## [0.8.3] — 2026-07-24

### Fixed

- `explore-deep` and `explore` no longer condition forked execution on
  `CLAUDE_CODE_FORK_SUBAGENT=1`. That variable gates the Agent tool's `fork`
  subagent type, not skill-level `context: fork`, which the skills reference
  documents with no environment gate. Setting it also runs the opposite
  direction from what the docs claimed — it forces every subagent to the
  background and nullifies the `background` frontmatter field.
- `explore-deep` no longer claims it inherits the parent's full toolset. On
  Claude Code ≥2.1.218 a backgrounded fork runs with the narrower
  background-subagent tool set; the skill now points at the sub-agents reference
  for that list rather than enumerating it, names `background: false` as the
  escape hatch, and states the pre-2.1.218 behavior the old claim was correct
  for.

### Removed

- `explore-deep` eval case `fallback-when-fork-unavailable`. The skill declares
  `context: fork` in its own frontmatter, so the body executes inside the fork
  and cannot detect fork-unavailability — the branch it asserted cannot fire.

## [0.8.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.1] — 2026-07-20

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.8.0] — 2026-07-20

### Added

- **`/discovery:blindspot` — blindspot mode extracted from `/discovery:explore` into its own skill.**
  Surfacing the USER's unknown-unknowns before they work in unfamiliar territory (a codebase area or a
  domain vocabulary) is a distinct responsibility with a distinct output contract — blindspot cards and
  one improved prompt, no `EXPLORE.md`, and the explore outcome gate skipped — that had been grafted onto
  explore. It now lives in `skills/blindspot/` with its own frontmatter, workflow, and evals.

### Changed

- **`/discovery:explore` is trimmed back to its core responsibility** — codebase investigation, the
  `EXPLORE.md` handoff artifact, and the outcome gate. The blindspot mode/table row, its two artifact-skip
  clauses in the outcome gate and final step, and the blindspot domain-lane research carve-out are removed;
  a one-line pointer to the sibling `/discovery:blindspot` skill replaces the extracted section. Cross-plugin
  references (`plugins/discovery/README.md`, `plugins/planning/skills/interview/SKILL.md`) now point at the
  new skill.

## [0.7.3] — 2026-07-19

### Fixed

- **`/discovery:explore` and `/discovery:explore-deep` keep the absolute project root out of the
  persisted `EXPLORE.md`.** The pre-computed `Project root:` value (a live `git rev-parse
  --show-toplevel`) is now marked session-orientation only, and the explore outcome gate adds a
  binary criterion requiring machine-agnostic artifact paths — relative to the repo root, or to the
  current working directory when no repo root exists. The live root stays available for resolving
  files while working; it is never echoed into the handoff, so `EXPLORE.md` stays machine-agnostic.

## [0.7.2] — 2026-07-19

### Changed

- **`/discovery:setup` no longer cites the marketplace-repo ADR by bare path.** Both
  `vault_backend: gitbook` deferral notes in `skills/setup/SKILL.md` inlined the rationale
  directly — git remains the storage layer because GitBook offers no concurrency-safe, lossless
  write path — replacing the dead `docs/adr/…` reference that resolves to nothing in the
  cache-isolated installed plugin. Behavior is unchanged; gitbook stays deferred and non-writable.

## [0.7.0] — 2026-07-18

### Changed

- **`/discovery:setup` adopts the uniform `check` / `apply` contract.** The single
  interview-style flow is split into a read-only `check` (default) that reports the
  effective topic-docs concern, the inferred convention, and the committed-tier ignore
  guard as PASS/FAIL/INFO, and an `apply` that persists `.claude/topic-docs.yaml`.
  `apply` gains a non-interactive path: complete `<key>=<value>` arguments
  (`memory_dir=`, `contract_dir=`, `contract_tier=`, `vault_backend=`) skip the
  interview, so headless and CI use are possible. The ignore guard, the gitbook-deferred
  handling, and the never-edit-root-`.gitignore` rule are unchanged.

## [0.6.0] — 2026-07-17

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states that
  `EXPLORE.md` / `RESEARCH.md` are checkout-local and are the cross-checkout-useful kind the
  contract's `.worktreeinclude` template carries into new worktrees. The by-value boundary is the
  checkout, not the process: the `-deep` forks run in the parent's checkout and write the
  artifacts there directly; only workers dispatched into their own checkout return findings by
  value for the parent to write.

## [0.5.1] — 2026-07-15

### Fixed

- **`/discovery:setup` reports `vault_backend: gitbook` as deferred and non-writable.** Offering or
  preserving the key now cites the ADR (`docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`)
  and states that durable writes still target `docs`; the skill never configures or tests a GitBook
  API, MCP, or Git Sync writer.

## [0.5.0] — 2026-07-15

### Added

- Research floor-scaling and broad-topic-minimums evals in `skills/research/evals/evals.json`:
  `floor-scaling-single-product` pins that Phase 2 query count tracks the Phase 1 written gap
  count rather than stopping at the 3-query floor (SKILL.md's "floor is a starting point, not a
  target"); `broad-topic-triple-tool-comparison` pins that a 3-tool comparison topic fires the
  doubled phase/query/source minimums (SKILL.md item 8, discipline.md's "Broad-topic
  auto-detect").

## [0.4.0] — 2026-07-14

Adopt the marketplace topic-docs convention, contract v1.0.0
(<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>):

- `EXPLORE.md` / `RESEARCH.md` are memory-tier artifacts written to
  `<memory_dir>/<slug>/` (default `.work/<slug>/`), never committed. The
  session's first memory-tier write verifies the **resolved memory
  root** contains a self-ignoring `.gitignore` (`*`), creating it
  (announced) when absent. No skill edits the consumer's root
  `.gitignore`.
- New `reference/topic-docs.md` — the plugin's **deltas-only** binding
  to the contract: its artifact/tier table. The contract owns the
  resolution order, slug spec, runtime guards, no-project-root
  fallback, and the non-interactive/forked mode the `-deep` variants
  run under; every skill resolves destinations by citing the binding,
  not by restating the rules.
- Slug derivation and sidecar filenames follow the contract's spec;
  skill-specific sidecars are `EXPLORE-<scope>.md` /
  `RESEARCH-<topic>.md`.
- `/discovery:setup` now interviews for and persists the tracked
  concern file `.claude/topic-docs.yaml` (previously the `notes_dir`
  pluginConfig), offering and preserving every schema key —
  `contract_dir`, `memory_dir`, `contract_tier`, `vault_backend` — and
  citing the schema by its raw URL. Order is guard-then-persist: the
  `git check-ignore -v` conflict check on the configured contract root
  runs BEFORE the concern file is written — and only when the chosen
  tier is `branch` (local mode has no committed tier to guard).
- Removed: the `notes_dir` userConfig option and the `.claude/notes/`
  layout. Prior locations are retired outright — no compatibility
  layer, no dual-read window, no migration tooling; move residual
  content manually.
