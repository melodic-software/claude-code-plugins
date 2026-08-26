# Changelog — discovery plugin

## [0.16.10]

### Changed

- **The `intent-tracer` no-split record now names the pin that actually goes red.** 0.16.9 recorded
  `agents/intent-tracer.md`'s Tool honesty section as deliberately not split, and cited
  `agents/tool-honesty.test.sh`. That suite argues drift risk rather than breakage: it reads each
  agent body for that agent's own tool claims, so lifting the prose into a spoke takes the claims
  out of its window and the suite goes quiet instead of red. The harder pin went unnamed.
  `scripts/contract.test.sh` asserts that `agents/intent-tracer.md` itself contains the string
  `single write boundary`, which sits at line 125, inside the range the audit proposed moving, so
  the split fails the assertion `agents/intent-tracer.md defers to the single write boundary`.
  Measured by applying the split to a throwaway copy of the plugin and running both suites.
  Recorded because the sweep's standing hazard is that a pin under `scripts/` is the one a split
  lane misses, and a record naming only the quiet suite invites the re-proposal it exists to
  prevent. No file in the shipped surface changed. Docs-hygiene sweep, L2-progressive-disclosure.

### Fixed

- **Three unresolvable citations in `reference/topic-docs.md`.** The by-value recovery-ladder rungs
  were written as `skills/explore/reference/dispatch.md`, `skills/research/context/dispatch.md` and
  `skills/trace-intent/context/dispatch.md`, whose implied base is the plugin root while the real
  base is `reference/`, so none of the three resolved. All three now use the anchored
  `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/<path>` form that `reference/parent-contract.md` already
  uses correctly for the same targets. Docs-hygiene sweep, L4-encapsulation.

## [0.16.9]

### Changed

- **All three of this plugin's progressive-disclosure splits audited and deliberately not applied.**
  The audit proposed lifting the routing section out of `research` and `explore` and the Tool
  honesty section out of `agents/intent-tracer.md`. Both routing sections carry lines
  `scripts/contract.test.sh` pins by path in `skills/<skill>/SKILL.md`: the token-is-file-identity
  demotion and the structured `preload:` field (#2895), the inline-is-not-an-escape-hatch rule, and
  the fail-closed coverage rule on the inline path. Each pin exists because the same statement once
  drifted across three files, and a pin cannot follow a pointer. The splits were applied, the suite
  went red on five assertions, and they were reverted rather than the pins relaxed. Docs-hygiene
  sweep, L2-progressive-disclosure.
- **`agents/intent-tracer.md` audited and deliberately not split.** The audit proposed lifting its
  Tool honesty section into a plugin-scope spoke shared with `researcher` and `explorer`. The
  section is per-agent by construction: it states that this definition declares no `tools:`
  allowlist, enumerates what that inherits, and ends by telling the reader that none of the three
  agents describes the others. `agents/tool-honesty.test.sh` also reads each agent body for exactly
  those claims and checks them against that agent's own frontmatter, and it cannot follow a
  pointer. Recorded here so the next sweep does not re-propose it.

## [0.16.8]

### Changed

- **The Phase 3 fallback pointer front-loads its subject (`research`).** It was the file's one
  deviation from its own dominant pointer shape. Docs-hygiene sweep, L7-write-for-agents.

## [0.16.7]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** In
  `scripts/check-coverage-complete.py`, the USAGE literal's first 17 lines (a byte-for-byte
  copy of the module docstring) now derive from `__doc__`; `--help` output is byte-identical.
  One accepted theoretical divergence, verified unreachable: under `python -OO` or
  `PYTHONOPTIMIZE=2` (which strip docstrings and which nothing in this repo or its CI
  invokes) the script now fails at import on every invocation instead of running; the
  failure direction is safe for the gate (exit 1, never a false "complete"). Also removed a
  dead `-v OFS=' '` from `check-coverage-complete.sh`'s awk (no multi-arg print or `$0`
  rebuild reads OFS) and an inert shellcheck directive from its test. Suites green apart
  from one pre-existing root-container failure (chmod 000 does not block root) confirmed
  identical at HEAD.

## [0.16.6]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** A negative parallelism in an old
  changelog entry restated positively, and "in order to dodge the gate" in
  `explore/SKILL.md` tightened to "to dodge the gate".

## [0.16.5]

### Fixed

- **De-slop review repairs.** Restored sentence structure where em-dash removal
  left a lowercase continuation, a mid-parenthetical period, and comma-stacked
  appositives.

### Changed

- **Instruction-surface de-slop (#2891, shard 7).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. Fenced report and protocol templates keep their original
  punctuation.

## [0.16.4]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.16.3]

### Fixed

- **A matching `preload_token` is no longer treated as proof that `skills:` preload
  fired (#2895).** The #2374 fallback Reads the same `SKILL.md` that preload would
  have injected, so a recovered agent echoes the same token a preloaded run would —
  and the agent body also embedded the token, so it could be echoed without seeing
  the skill at all. The same pattern sat on `discovery:intent-tracer`. The token is
  now file-identity evidence only and lives only in the skill file, on both
  families. Provenance is a structured `preload: fired | fallback` field the parent
  grades; `fallback` is the accepted recovery, not a discard. A missing or
  unrecognized `preload:` field is an out-of-date agent definition. `explorer` has
  no disk-fallback path and is unchanged.

## [0.16.2]

### Fixed

- **Two routes back to the code-shape exclusion `trace-intent` is built around, both closed.** The
  source-control evidence row listed "test names" among what that category holds — but a test name
  is a symbol in the implementation, not someone writing down a reason, so admitting it readmitted
  code shape through the category table while the outcome gate still demanded that no claim rest on
  the code's shape. Dropped; a code *comment stating a reason* stays admissible, because that is
  someone writing down why. And `context/gotchas.md` called a named constant plus a nearby
  convention "a hypothesis at best", which collides with `Speculative`'s own output section
  (*Competing hypotheses*) and so read as licensing the very rung the scale forbids for code shape;
  it now says plainly that this is code shape, leaves the scale, and is recorded as a gap.
- **A grading criterion that was not derivable from the skill as written.** The ceiling on
  *version-control behaviour* — change coupling, churn, hotspots — said "reaches `Inferred` and
  never `Direct`" while the eval graded "never `Direct` or `Supported`". The body now names both
  rungs. This is not a third code-shape route: the same section says plainly that behavioural signal
  is **not** code shape and is admissible. It is the neighbouring rule, and the gap was between the
  body and its own eval rather than in the exclusion.
- **An eval that could not distinguish the behavior it targets from correct behavior.** The
  anticipatory-skip case told the model not to bother checking the tracker but never stipulated
  that a tracker existed — and the tracker category is presence-gated, so in a bare checkout the
  correct output is a tracker-unavailable gap line, which the eval's first expectation graded as a
  failure. The prompt now states that the tracker is configured and reachable, isolating
  anticipatory skipping from presence-gating, which the unavailable-category eval already covers
  separately.
- **`trace-intent` was the one skill in this plugin linking `reference/parent-contract.md` by a
  relative path.** Its Scope-section link rendered the `${CLAUDE_PLUGIN_ROOT}` token as the link
  *text* while the href underneath was `../../reference/parent-contract.md`. `explore`,
  `research` and `research-deep` all cite that same file with the token on both sides, and so does
  the rest of the fleet by a wide margin. Two spellings of one reference across sibling skills is
  the divergence `discipline:reuse-or-replace` exists to catch, and the relative form is the one
  that breaks first — it resolves from the file's own location rather than from the installed
  plugin root. Brought into line with its siblings.

## [0.16.1]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `blindspot`'s `EXPLORE.md` hand-off and its
  deeper-research route; `research`'s route to the multi-topic sibling; `research-deep`'s tier-3
  inline row and its inline-tier section; `trace-intent`'s delegation of repo-local git
  archaeology to `/discovery:explore git` and its follow-up routing through `/work-items:track`.
  `blindspot`'s step-4 escalation is deliberately left as prose — it produces a *recommendation*
  to the user, not an invocation. Wording only; tier semantics and dispatch behavior unchanged.

## [0.16.0]

### Added

- **`/discovery:trace-intent` — reconstruct why a thing was built the way it was.**
  The plugin's third evidence-substrate axis: `explore` answers what IS, `research`
  answers what SHOULD BE, and this answers what WAS and why, from records outside
  the code — review discussion, tickets, long-form documents. Every claim carries an
  **intent-evidence tier** (Direct / Supported / Inferred / Speculative / Unknown)
  measuring inferential distance from an explicit statement of intent, which is a
  different axis from the research skill's source-authority tiers and is deliberately
  not that vocabulary. A per-citation source-reliability note rides alongside without
  routing, because evidence directness and source reliability are separate questions —
  a review comment by the change's author and a four-year-old wiki page are both
  `Direct` and are not equally trustworthy. `Unknown` is a first-class tier: an
  investigated question that came back empty is a finding about how the decision was
  made. Reauthored from the `why` skill in `cursor/plugins` (MIT); provenance and the
  one deliberate departure are recorded in `docs/upstream/cursor-pstack.md`.
- Three evidence categories ship — source control, long-form documents, issue tracker —
  each presence-gated, none assumed. Four further categories that carry real intent
  evidence are deliberately **not** shipped, because no seam in this marketplace reaches
  them and four permanently-empty investigators would report the same gap forever; the
  adapter seam for adding one is documented instead.
- **`discovery:intent-tracer`** — the purpose-built subagent `/discovery:trace-intent`
  dispatches by default, so review threads, ticket histories and design documents stay
  out of the orchestrator's context window. It follows the `discovery:researcher`
  pattern — a `disallowedTools:` denylist and no `tools:` allowlist — because an
  allowlist strips every MCP tool, and two of this skill's three evidence categories
  live behind MCP forge and tracker surfaces; an allowlisted agent would report both as
  unavailable forever and be unable to tell that gap apart from a real one. It is
  read-only on every evidence surface it touches: it never comments on a pull request,
  transitions a ticket, or edits a page.
- `skills/trace-intent/context/dispatch.md` — the intent family's parent-side dispatch
  contract: the three inline escape hatches, the post-dispatch acceptance gate, the
  reason-per-skip check that stands in for a coverage ledger (this family's corpus is
  whatever the environment exposes, so an enumerate-then-mark ledger would count against
  a denominator nobody can fix in advance), why a tier census sitting entirely in
  `Speculative` / `Unknown` is a **pass**, and the by-value rung.
- `skills/trace-intent/context/artifact-shape.md` — the third sidecar header schema, and
  deliberately neither sibling's. The research header's `confidence` / source `tier` /
  publishing `pool` describe external evidence and would let "someone hinted at this in a
  merge thread" occupy the field a fetched primary source does; the exploration header's
  `verified: read | grep | inferred` describes whether a repository file was opened, which
  is the one axis this skill refuses to grade intent on. `tier` is readable off the header
  so a verifier who never saw the run can grade tier assignment mechanically, and
  `reliability` is a sibling of `ref` rather than of `tier` — only `tier` routes a claim to
  an output section. **Sources consulted** lives in the index rather than a sidecar,
  because a sidecar is opt-in reading and a reader who takes the answer and stops must
  still meet the shape of the record behind it.

### Changed

- `/discovery:explore`'s description gains an explicit boundary against
  `/discovery:trace-intent`. Its `'how does this work'` trigger is why-shaped, so
  without the reverse boundary auto-discovery could route intent questions into the
  wrong sibling — the same defect the research / research-deep boundary already fixes.
- `reference/parent-contract.md` now covers three dispatched families rather than two:
  the pointer table gains the intent row, the pre-dispatch baseline command names
  `.trace-intent-dispatch` in both its POSIX and PowerShell forms, and the gate's
  pre-flight probe list distinguishes the routes that owe a coverage checker from the
  one that does not. `/discovery:trace-intent` keeps the shared `Topic:` envelope label
  rather than adding a `Target:` one, so the label a dispatched agent parses and the
  `topic_as_received` field that verifies it stay the same name.
- `reference/topic-docs.md` records `INTENT.md` in the plugin's writes table and widens the
  single write-boundary statement from two dispatched agents to three. The artifact stays
  **private** — it is deliberately absent from `reference/artifact-protocol.md`, which is one
  of five byte-identical copies across five plugins, so promoting a kind into it costs an
  identical edit to all five plus a protocol version bump. That price is worth paying for an
  artifact several plugins consume and not for one this skill writes and its own reader reads.
- `scripts/contract.test.sh` extends its write-boundary loop to the third agent, and
  `scripts/check-dispatch-artifact.test.sh` runs its full shape suite a third time for
  `INTENT.md` — an `EXPLORE.md`-only run would let an `INTENT.md` regression through on
  the strength of an explore-shaped pass.

## [0.15.6]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.15.5]

### Changed

- **Explore composes the toolchain ecosystem seam instead of a silent second
  signal table (#2726).** `skills/explore/reference/ecosystem-discovery.md` now
  presence-gates `/toolchain:check`'s covered-ecosystem set and
  `project-discovery` / `anchor` for shared detection and root adjacency, keeps
  explore-only keys (`dependency-grep`, `test-globs`, `test-content-grep`,
  `build-configs`, `runtime-version-cmd`) even when that seam is present —
  including fallback ecosystems the seam does not cover (`rust`, `java`) and the
  exhaustive configuration / runtime-probe inventories seam `globs` /
  `install-hint` do not replace — and retains the prior YAML table as the
  documented fallback when `toolchain` is absent. `explore` Dimensions 3–6, the
  `explorer` agent, and the plugin README cite the same gate+fallback shape.

## [0.15.4]

### Fixed

- **Acceptance gates fail closed when they cannot run (#2616).** A denied or
  uninvocable research gate is a FAIL — not a reason to take the inline escape
  hatch to dodge a post-dispatch check, and not a licence to mark criterion 11
  PASS by reading the coverage ledger. `reference/parent-contract.md` requires a
  `--help` pre-flight for scripts the **chosen** route owes: the dispatch artifact
  checker before dispatching (explore or research), and the coverage checker for
  research on both the dispatch and inline paths. A legitimate inline
  `/discovery:explore` does not owe a script verdict and is not halted by an
  unavailable artifact checker. Prefers shebang path invocation over
  `bash <script>`, and documents the coverage checker's Python twin
  (`scripts/check-coverage-complete.py`) for sessions where the Bash tool is
  blocked but `python3` is reachable; that twin maps UTF-8 / I/O read failures to
  exit 2 (ungradeable), matching the shell gate. The stale claim that
  `${CLAUDE_PLUGIN_ROOT}` never substitutes in `allowed-tools` is corrected
  against the skills page (fetched 2026-08-14); turn-scoped grants still cannot
  cover the post-dispatch gate, so the plugin still ships none.

## [0.15.3]

### Fixed

- **Fork availability wording in setup check.** Reconcile setup skill prose with discipline
  `sweep-all` preflight: report `CLAUDE_CODE_FORK_SUBAGENT` as a control and defer availability to a
  live inheritance probe instead of claiming forks are unconditionally on.

## [0.15.2]

### Fixed

- **`researcher` no longer assumes `skills:` preload succeeded.** The agent
  body now requires confirming the preload-liveness sentinel or Reading the
  skill before research, and mandates echoing `preload_token` — matching the
  parent contract that treats a missing token as a failed dispatch. (#2338)

## [0.15.1]

### Fixed

- **Erratum for the 0.14.1 CHANGELOG entry (#2339).** That entry stated the routing gap backwards —
  it described deep work landing in the lighter skill, while #2271 (`D-F9`) filed the opposite
  (small lookups routed into `research-deep`). The clause 0.14.1 shipped was a positive pointer toward
  the heavier sibling, not a negative boundary claiming small work for `research`; 0.15.0 replaced it
  with the correct direction. The 0.14.1 text stands as written; this records the correction. The
  contract test now keys on that direction, not merely on naming `research-deep`.

## [0.15.0]

### Fixed

- **A harness behavior this plugin had never sourced was stated as settled fact in eight places.**
  Through 0.14.0 the plugin asserted a specific empty-string rendering of `$ARGUMENTS` on the
  subagent preload path — at `agents/explorer.md`, `agents/researcher.md`, both `SKILL.md` bodies and
  `skills/research/context/dispatch.md`, in a weaker sixth form at `skills/explore/SKILL.md`, and
  inside both `evals.json` files where it had become a **grading criterion**. Re-checked against raw
  markdown on 2026-08-11: the skills page scopes the placeholder to "All arguments passed **when
  invoking** the skill" and says preload "work[s] differently: the full skill content is injected at
  startup"; the sub-agents page says only "The full content of each listed skill is injected into the
  subagent's context at startup". **Neither page covers argument substitution on that path in either
  direction**, and the nearest documented analogue — the `context: fork` walkthrough, where the
  subagent "receives the skill content as its prompt" with the placeholder shown escaped — points the
  other way.

  This is recorded as **unsupported, not false**: nothing establishes that the retired sentence was
  wrong. What was wrong was asserting an uncovered mechanism as the stated reason. Every copy now
  states the rule that holds whichever way the harness renders the placeholder — *the scope or topic
  does not reach a preloaded body by argument substitution, so do not rely on seeing an unfilled
  slot; a topic that did not arrive in the dispatch prompt is a parent-envelope failure the agent
  reports rather than repairs* — which is strictly stronger than what it replaced, because it no
  longer depends on a rendering nobody has verified. The doc status is written down once, in the new
  `reference/parent-contract.md`.

  **Erratum against 0.14.0.** That entry's closing line, "That older claim is untouched here and is
  tracked separately," described the claim as merely deferred. It is the claim retired here; the
  0.14.0 text stands as written and this is its correction.

- **The truncation rule and both recovery ladders prescribed opposite outcomes for one event.** Three
  sites (`agents/explorer.md`, `agents/researcher.md`, `skills/research/context/dispatch.md`) said
  the parent "discards the partial slice **rather than** resuming it" on a no-payload or `truncated`
  return, while both ladders said resume first — and `skills/explore/reference/dispatch.md`
  back-referenced the discard rule as the justification for its own. Five sites, two rules, one
  event. The observed incident refutes discard-first: a resume recovered the complete artifact set
  from retained context, so following the rule as written would have thrown away a finished run and
  re-dispatched at full cost.

  **Resume first; decide about the slice from what the resume returns.** Sourced against the
  sub-agents page (raw markdown, 2026-08-11): "Resumed subagents retain their full conversation
  history … The subagent picks up exactly where it stopped rather than starting fresh," and "A
  completed subagent that receives a `SendMessage` auto-resumes in the background without a new
  `Agent` invocation." The discard is not removed — it is **sequenced**, and stays mandatory once the
  resume is refused, unavailable, or comes back without a usable payload, because that is precisely
  the state the coverage script cannot grade. `truncated` still means the turn-budget stop and its
  rung is unchanged, so #2203's `persistence:` axis is not reopened.

- **The pre-dispatch envelope specified six fields and the primary dispatchers delivered a
  parenthetical.** `skills/research/context/dispatch.md`'s parent-obligation table had five rows and
  no **Memory root**, while `agents/researcher.md` requires it "as its own field, not left to be
  derived" and `skills/research-deep/SKILL.md` already ships it as a literal prompt line. The
  envelope is now one labelled template — reproduced from `research-deep`'s existing block so the two
  cannot drift — and the table carries the missing row. Memory root is recorded as the one
  **degradable** field: the agent derives, flags in `open_questions`, and continues, which is the
  behavior actually observed and is proportionate to a recoverable, visible wrong guess.

  **Capability flags stay one flag, deliberately.** All five statements of the field named nesting
  and nothing else, and the capability that actually failed in the field was the child's ability to
  write. The fix is **not** to assert a write flag: there is no pre-dispatch probe for it that does
  not either lie or corrupt the gate's freshness baseline, and the parent's own `mkdir`/`touch`
  proves only that the *parent* can write there. All three sites now say so and route the question to
  `persistence: written | by-value`, which is the mechanism that already answers it after the fact.

- **The pre-dispatch baseline was POSIX-only at three sites, and two pointers were monorepo paths.**
  `touch` is not a command in PowerShell and the directory flag is a parameter error there, and
  `shell: bash` does not cover this — its documented scope is inline injection blocks, not prose the
  parent executes later through its own tool. The command now has exactly one home carrying **both**
  shell forms, and the three skills point at it. `skills/explore/reference/dispatch.md` and
  `skills/research/context/dispatch.md` cited `plugins/discovery/agents/<name>.md`, which resolves to
  nothing from an installed plugin root; both now use the `${CLAUDE_PLUGIN_ROOT}` form every other
  cross-reference in the plugin already used.

- **Three files stated three different write boundaries, and scratch had no owner.**
  `reference/artifact-protocol.md` sanctions scratch inside the memory slice, `agents/explorer.md`
  put it out of bounds ("exactly two permitted destinations"), and `agents/researcher.md` admitted it
  only incidentally. `reference/topic-docs.md` now carries the single statement — three destinations,
  a `scratch-` naming prefix so a consumer can tell a working file from a deliverable, and a cleanup
  owner (the run that created it, falling to the ladder's existing clear-the-slice rung when the run
  dies). Both agents point at it instead of restating it. The researcher's **session** scratch dir is
  named as a separate, harness-owned place outside that boundary rather than merged into it — the two
  were never the same location, and collapsing them would have shipped a new false claim.
  `reference/artifact-protocol.md` is byte-identical across four plugins and is not edited here.

- **`skills/research/SKILL.md` was the hub and was larger than the spoke it delegates to** — a file
  preloaded in full into every dispatched `maxTurns: 40` run. Measured at `9b34a82a`: **6,629 words
  against `context/discipline.md`'s 5,087**, a gap that #2222 had widened by 851 words. The two
  densest lines (3,105 and 2,108 characters) are where the mechanism depends on exact reading, so
  neither was compressed in place. **Three distinct operations, stated as three:** the fetch-log
  specification **moved** to `context/artifact-shape.md` beside the sidecar-header schema it belongs
  with (+644 words there); the Tier-3 scoped exception **moved** to `context/discipline.md`'s "Source
  tiers" (+149 words there, the only content this release adds to that file); and outcome-gate
  criterion 9's cell was **compressed to a pointer, because `discipline.md` already carried the
  elaboration** — "A probe locates a rung; it does not grade one", the exhaustive-surface rule, and
  the `unresolved` default have been in its "Primary-source-first protocol" all along, so the hub was
  restating a spoke rather than owning anything. The remaining reduction is ordinary compression of
  rationale the two dispatch spokes already carry. **The hub is now 5,026 words / 232 lines**, below
  the 5,236-word spoke, and a contract test pins the direction so the next edit cannot silently
  re-invert it.

  Its `description` also gained the boundary clause it lacked: `research-deep` already routed back to
  `research` and nothing routed the other way, so auto-discovery could send a small lookup into the
  heavier sibling and never the reverse.

- **`explorer`'s turn budget was smaller than `researcher`'s with no stated reason** — 30 against 40
  on the read-heavier workload. Raised to 40 **on parity grounds only.** It is explicitly *not*
  offered as the cause of any past bare-prose return: the packet's own `evidence-2.md` supersedes
  that reading and the discriminator is unrecoverable.

  Separately, both agents' "budget a turn for the payload" instruction asked them to schedule against
  a limit they cannot observe. They now **emit the payload block early and keep it current**, so a
  stop at any later point leaves the parent a well-formed payload rather than silence.

### Added

- `plugins/discovery/reference/parent-contract.md` — the parent's **cross-family** contract. The
  plugin had two family-specific parent-side spokes and no home for what is identical across both,
  which is why five statements existed in two to six copies each and every one had drifted. It owns
  the envelope template, the baseline in both shell forms, the doc status of the preload path, the
  caller-supplied-`${CLAUDE_…}` caveat (previously triplicated verbatim across three `SKILL.md`
  files), the gate's un-run case, and the resume-before-discard ordering. The two existing spokes
  keep their family-specific halves and point here; the file states that split in its own header so a
  future edit knows where a new statement belongs.

- `plugins/discovery/scripts/contract.test.sh` — a grep-level contract test over the plugin's shipped
  documents, alongside the two script suites. It pins every defect above: no file asserts the
  unsupported preload mechanism (10 hits before, over 7 files), no monorepo agent pointer (2 before), the baseline
  command has exactly one home and that home states a PowerShell form, no file prescribes
  discard-instead-of-resume (4 before), the envelope table carries its Memory root row,
  `explorer maxTurns >= researcher maxTurns`, and `research/SKILL.md` stays smaller than
  `context/discipline.md`. **24 assertions; 22 fail at the merge-base and all 24 pass at the tip.**
  The two that hold on both sides are the deliberate no-grant guards, and they are labelled as such
  — an earlier revision of this file asserted that each agent "points at" the write boundary, which
  passed *before* the change too because both agents already linked that file for an unrelated
  reason. That assertion now keys on the restatements being gone, because a check that cannot fail is
  the script-layer form of the self-graded gate these skills refuse everywhere else — the exact
  pattern `B-F8` records across three previous releases. `CHANGELOG.md` is excluded from the content
  sweeps by design: it quotes the wording it retires, and editing a shipped entry to satisfy a
  tripwire is the failure this file exists to make expensive.

### Security

- **No permission grant is added, and that is the finding.** The gate invocations run through Bash
  and neither `SKILL.md` declares `allowed-tools`; the un-run case was unstated, so a gate that could
  not run read as a gate that passed. A grant cannot be made to work here, on three sourced legs
  (skills page, raw markdown, 2026-08-11): Claude Code substitutes only `${CLAUDE_SKILL_DIR}` and
  `${CLAUDE_PROJECT_DIR}` in `allowed-tools` Bash rules — `${CLAUDE_PLUGIN_ROOT}` is not on that list
  and a rule written with it is inert — while `${CLAUDE_SKILL_DIR}` is "the skill's subdirectory
  within the plugin, **not the plugin root**", and these scripts live at the plugin root precisely
  because one gate serves both families; `bash` is not one of the wrappers stripped before matching,
  so a covering rule would be interpreter-led (this repo's `permission-rule-hygiene` anti-pattern 1);
  and the grant "clears when you send your next message", while the parent runs this gate on a later
  turn. So both skills now state the honest rule — **a gate that could not run is a FAIL, never a
  skip** — and the parent contract records the operator-setup path the docs actually prescribe
  ("add allow rules to those permission settings instead"), which a plugin cannot ship for them.
  This narrows behavior; it widens no trust surface.

## [0.14.1]

### Fixed

- **`research` description now routes away from `research-deep`.** Auto-discovery reads the
  description, not the body; `research-deep` already pointed small lookups at `research`, but the
  reverse boundary was missing and could route deep work into the lighter skill incorrectly. (#2271)

## [0.14.0]

### Fixed

- **The plugin's own by-value fallback was unreachable from the only failure that needs it.**
  `reference/topic-docs.md` has said since the 2.0.0 contract that "a worker dispatched into its
  **own** checkout (worktree or background session) returns findings by value instead, and the
  parent writes the memory slice." No agent definition referenced that rule as a persistence mode
  and neither recovery ladder carried a rung for it: `skills/explore/reference/dispatch.md` and
  `skills/research/context/dispatch.md` had rungs for a bad envelope, a live agent to resume, and a
  refused resume, and none for *the worker could not write*. Following the rule anyway guaranteed a
  halt — an empty slice holding only the parent's pre-dispatch baseline is exactly what
  `check-dispatch-artifact.sh` exits 1 on, and both `SKILL.md` files declared any non-zero exit to
  halt the workflow. Two documents in one plugin prescribed opposite outcomes for the same run, and
  the correct one was the unreachable one.

  Compounding it, no payload value could say what had happened. `status` was `complete | truncated`
  and `truncated` is the turn-budget stop whose ladder consequence is *discard the partial slice*;
  `complete` requires an `artifact:` pointer the run had no file to name. Both available values
  misdescribed a run that finished its work and could not save it, and the only honest one routed
  the parent to throw the work away. Observed consequence: a parent reinvented the by-value rule ad
  hoc in a resume message, because the rule the plugin already owned could not be reached from the
  failure it was written for.

  **`persistence: written | by-value` is now its own payload axis** on both agents, deliberately
  separate from `status` and from `coverage` — `truncated` keeps meaning the budget stop, so the
  discard rung stays correct, and `coverage` stays a statement about exploration and the corpus
  ledger rather than about the disk. On the by-value path the agent returns its index, sidecars and
  ledger as verbatim bodies after the YAML block, `artifact:` names the path the parent must write
  to (a destination, not a claim that a file exists), and both ladders gained the matching rung
  ahead of the resume rung: **the parent writes the slice from the payload, then re-runs the same
  gate.**

  **The exception is to the halt, not to the gate**, and both `SKILL.md` files now say so in those
  terms. The workflow proceeds only on a subsequent exit 0 — for research, from both the artifact
  gate and the coverage-ledger gate. `persistence: by-value` routes the parent and grades nothing;
  a by-value payload that returns *findings* instead of artifact bodies is a failed dispatch, not a
  fallback, because a claim the gate is invited to accept on the agent's word is the same laundering
  the source-tier discipline refuses everywhere else. A by-value slice earns its exit 0 from the
  identical command, freshness check included: the parent writes after its own pre-dispatch `touch`.

  This also closes the seam where exit 1 read identically for "never ran" and "ran well, could not
  persist". The script is right to grade disk state and nothing else; the branch belongs one level
  up, in the ladder, where gate step 1 has already put the payload in the parent's hands.

  **Three conditions bind the parent's write, because the recovery path must not become a hole in
  the rules it recovers into.** The by-value rung is the only place in this contract where a
  filename the *worker* produced becomes a write the *parent* performs, and the parent holds wider
  write permission than the sandboxed worker — a researcher in particular spends its whole run
  ingesting untrusted third-party pages. So: filenames are checked **before** anything reaches disk
  and only the contract's own names are accepted (`EXPLORE.md` / `EXPLORE-<section>.md`,
  `RESEARCH.md` / `RESEARCH-<section>.md` / `research-checklist.md`), as bare filenames; a directory
  separator, a `..` segment or a leading `/` makes the payload a failed dispatch rather than a name
  to sanitize. The explorer's **collision rule still applies** — a slice root already holding an
  unrelated `EXPLORE.md` gets a parent-assigned sub-slice here too, because overwriting the index
  that rule protects would be a silent, unrecoverable loss arriving through the recovery path. And
  the research side's **unbounded-corpus rule is unchanged** — a run that recorded the corpus as
  unbounded wrote no ledger and owes none here, so the coverage gate is re-run only when a ledger
  was owed; running it against a file nobody was supposed to write exits 2, a FAIL, and would halt a
  complete run on a check that never applied to it.

- **`agents/researcher.md` described a tool grant it never made.** The file declared no `tools:` key
  and no `disallowedTools:` key, so it inherited every tool available to a subagent — while its own
  "Tool honesty" section asserted "`Edit` is absent from your tool list" and "`Agent` is listed."
  Both sentences are false there. The paragraph is a verbatim copy from `agents/explorer.md`, where
  the `tools:` allowlist at line 4 makes both of them true; it was carried into a file whose
  frontmatter inverts them. Inheritance was derivable from the missing keys and observed directly: the agent's own
  transcript shows it calling `ToolSearch` and `WebFetch`, neither of which appears in the
  explorer's allowlist.

  The harm is not tidiness. This is an unattended `maxTurns: 40` worker whose entire write boundary
  is instruction-held, and the false inventory — understating the pool by roughly a dozen tools
  including a second shell and the whole session MCP set — is the calibration input for that
  boundary. Least-privilege understatement is the dangerous polarity.

  The section now states what is true: no allowlist is declared, the pool is inherited, `Edit` and
  `PowerShell` are held, `Agent` is inherited and conditionally filtered at the depth limit, the MCP
  pool is held, and the memory-tier boundary holds by instruction and by nothing else. **No `tools:`
  allowlist was added** — an allowlist removes every MCP tool, and the skill's third mandatory
  discipline requires doc-MCP servers in the tool spread, so the allowlist would break the discipline
  it was meant to protect. A narrow `disallowedTools:` denylist is the instrument instead.

  Three decisions are now written down rather than left accidental. **`NotebookEdit` is denied** —
  nothing in the contract writes notebooks. **`Edit` is kept, deliberately**: `research-checklist.md`
  rows go `[ ]` → `[x]` as phases proceed, and denying `Edit` would force a full-file rewrite of the
  coverage ledger at every phase boundary. **`EnterWorktree`/`ExitWorktree` are denied and
  `isolation: worktree` is not set on either agent**, because these artifacts are graded off disk by
  the parent, in the parent's checkout, against a slice path the parent resolved before dispatch —
  work written into an isolated copy of the repository lands where that gate never looks, and the run
  would read as having produced nothing. Isolation and a disk-graded handoff are incompatible by
  construction; this plugin chose the handoff. The explorer/researcher asymmetry is now stated in
  both files as the deliberate thing it is.

  One thing the fix does **not** claim: it does not make the write boundary enforceable. You cannot
  deny "Bash writing a file" without denying `Bash`, which the research discipline needs. Both agents
  instead gain an explicit instruction that a refused `Write` is an answer rather than an obstacle —
  do not route the same write through `Bash` to get around it. That is grounded in the transcript
  asymmetry it was observed as (three `Write` calls refused while a Bash-mediated write succeeded to
  the same directory tree), not in any documented rule about which guard covers which tool.

- **Nothing restated the input, so a corrupted scope or topic passed every gate.** Every refusal
  mechanism in the plugin was a presence test — preload token present or `MISSING`, envelope field
  present or absent, index on disk or not, ledger rows marked or not, `artifact:` pointer present or
  not — so none of them could fire on an input that arrived present and wrong. Observed 2026-08-10:
  an argument naming *another* plugin's `${CLAUDE_PLUGIN_DATA}` directory reached a dispatched agent
  rewritten to this plugin's own path. The agent was asked a factually wrong question and answered
  it correctly, which is the most expensive shape of wrong available.

  Both agents now echo the envelope back — `scope_as_received:` / `topic_as_received:`, quoted
  verbatim, explicitly not paraphrased or normalized — and both acceptance gates compare it against
  the envelope the parent wrote. A mismatch is a failed dispatch even when the artifact is complete
  and every mechanical check exits 0. A payload lacking the field is an out-of-date agent definition,
  not a pass.

  The accompanying caveat in `skills/explore`, `skills/research` and `skills/research-deep` is
  written as an observation rather than a mechanism, on purpose. What is documented (both pages
  fetched 2026-08-11) is that skill and agent content is a substitution site for the three
  `${CLAUDE_*}` path placeholders "anywhere the placeholder appears", and that no escape exists for
  them — "A backslash before any other `$` is left unchanged" covers `$ARGUMENTS` and declared
  argument names, not these. What is documented nowhere is whether argument-supplied text is itself
  scanned for those placeholders. The caveat therefore states the observation, the two documented
  facts, and the gap, and **carries an unconditional 2027-02-11 expiry** so the claim cannot go stale
  invisibly. The echo-back is the part that works under either reading.

  The caveat also states its own boundary, because two nearby claims read as if they were about one
  thing. This is about placeholder-shaped text a **caller** supplies on the inline path or in a
  dispatch prompt. It is a different question from what the adjacent paragraph says about a
  `$ARGUMENTS` placeholder the plugin's **own body** carries on the preload path, and it is evidence
  for neither side of it. That older claim is untouched here and is tracked separately.

### Added

- `plugins/discovery/agents/tool-honesty.test.sh` — a contract test over this plugin's own agent
  definitions, locking the class of drift the second entry describes rather than the one instance of
  it: prose claiming a tool is absent from (or present in) a tool list must be backed by a `tools:`
  key that actually omits (or lists) it, every agent must declare its posture in frontmatter rather
  than leaving the prose as the only inventory, neither agent may set `isolation:`, and both payload
  contracts must carry the `persistence:` and echo-back fields. Scoped to this plugin's agents on
  purpose — a repo-wide sweep would fail this plugin's test on another plugin's drift.

- `scripts/check-dispatch-artifact.test.sh` gains the by-value pair: a slice holding only the
  pre-dispatch baseline exits 1, and the same slice exits 0 once the parent writes it from the
  payload, with freshness and pointer checks both passing. The pair is the point — the first half
  proves the exception answers a failure the gate really produces, the second proves the recovery
  routes *through* the gate rather than around it.

- Eval cases on both skills covering the outcomes the new axis has to keep apart: a by-value
  recovery that must be written and re-graded rather than discarded, a by-value payload carrying
  findings instead of artifact bodies (a failed dispatch, not a fallback), an echo-back mismatch
  that fails a dispatch whose artifact is otherwise perfect, a by-value payload naming a file
  outside the contract (rejected before anything is written), an explore-side recovery into a slice
  root already holding an unrelated index, and a research-side recovery of an unbounded corpus,
  which owes no ledger and must not be graded against one.

## [0.13.1]

### Fixed

- **One clean `sitemap.xml` no longer earns `probed-and-not-existing` for an artifact the sitemap
  never indexed.** 0.12.0's absence rule read "earned only against a surface that enumerates the
  publisher's own artifacts completely: a `sitemap.xml` (or its index), the in-repo docs tree, a
  releases or asset listing" — a disjunction of three surfaces, and criterion 9 restated it as
  "such as a sitemap or the in-repo docs tree", explicitly single-surface. "Completely" was the
  intended guard and was never made operative, so a publisher that omits PDFs from its sitemap,
  parks model cards on an asset host, or keeps them off the docs tree let a run record rung 1 as
  absent, descend to the announcement, and pass criterion 9 with the system card unread.

  **The contradiction was internal and needed no external evidence.** The ladder's own preamble
  scopes the two surfaces apart — "(The doc-index probe below enumerates *pages*; this ranks
  *artifact classes*.)" — and the doc-index table stamped `sitemap.xml` "**Exhaustive** — every URL
  … enumerate ALL pages". Pages. Rung 1 for a model/benchmark claim is "the **system or model
  card**, often a PDF". Two paragraphs apart, the file licensed an absence claim about PDFs from a
  surface it itself scoped to pages.

  `probed-and-not-existing` is now earned exactly two ways: the surfaces checked TOGETHER cover
  every first-party surface an artifact of *that claim class* plausibly lives on (docs sitemap or
  its index, in-repo docs tree, releases or asset listing, download/asset host, a sibling
  first-party domain the publisher links to), or the publisher itself declares its chosen inventory
  complete for the class. *Plausibly, for that class* is a stated bound, not decoration — the
  surfaces the class actually uses, never every surface imaginable, so a claim class a publisher
  only ships in-repo is still settled by the tree alone and the outcome stays reachable. Short of
  either, the rung is unresolved: a Gap naming surfaces checked and unchecked. The doc-index table's
  `sitemap.xml` row is rescoped to "exhaustive for that host's listed pages … NOT an artifact
  inventory", and `context/gotchas.md` gains the failure mode, which its curated-vs-exhaustive
  bullet had been hiding — a curated index is not the only non-proof of absence.

- **`unresolved` is now a value the fetch log can actually hold.** Found by an adversarial verifier
  run against the fix above, and a real hit: the Output Format section's ladder vocabulary was
  four-valued — carries-the-claim, does-not-exist, fetched-and-lacking, unreachable-after-escalation
  — with no slot for `unresolved`, while describing does-not-exist as "the bypass outcome a probe
  alone can establish" and asserting "nonexistence is what a probe settles". Both phrases
  contradicted the tightened criterion 9 fourteen lines above them, and the reviewer's exact path
  completed straight through the gap: sweep one surface, land on `unresolved` per criterion 9, find
  no legal slot for it in the log, write the nearest legal value — does-not-exist — and pass.

  The vocabulary is five-valued now, `unresolved` among them and marked as the DEFAULT whenever the
  sweep was not completed, explicitly not a licence to source from a rung below. The probe-settles-
  nonexistence phrasing is struck. Criterion 9's own "exactly one of three outcomes" is corrected to
  four for the same reason. This wording predates the fix, but the fix is what made it operative:
  before, `unresolved` was a corner case, and after, it is the common outcome.

- **The criterion-9 eval oracle can now fire.** The same verifier pass caught that the grading
  clause added above was attached to case 8, a RabbitMQ/Kafka/NATS comparison — library-behavior
  claims, whose rung 1 is "the source itself", so the off-sitemap-PDF scenario it grades cannot
  arise from that fixture and the clause passed vacuously. That clause is generalized to any claim
  class, and case 12 `absence-of-a-rung-needs-more-than-one-clean-surface` puts a real model-card
  fixture in front of the run: a vendor's launch-post benchmark number, conditions asked for, rung 1
  a card the docs sitemap does not list.

  **Proven by A/B control on the two texts, not by grep.** Fresh-context agents given only the
  pre-fix criterion 9 + absence rule and asked the isolated question — clean docs sitemap, no PDF
  in it, nothing else checked, may rung 1 be recorded absent? — answered
  `probed-and-not-existing` in 2 of 3 samples. Given only the post-fix text and the identical
  question, 3 of 3 answered `unresolved`. Prose, so a model-judgment control rather than a
  deterministic one.

## [0.13.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.12.2]

### Fixed

- **The coverage-ledger case no longer advertises coverage it does not have — the same defect 0.12.1
  was written to remove.** Both 0.12.1's entry above and the block comment at
  `scripts/check-dispatch-artifact.test.sh` claimed the case fails against a harvest that "globs the
  directory instead of reading the index". It does not. Found by an independent verification pass
  that ran exactly that mutation: a directory-glob harvest emits `sidecars=1 missing=0`, exit 0 —
  byte-identical to the correct gate, so the assertion cannot tell them apart.

  **The stated mechanism was wrong in principle, not merely here.** The comment reasoned that a glob
  "picks it up on any case-insensitive filesystem — which is what this repo is developed on". Bash
  matches a glob against the DIRENT STRING, so how the filesystem compares names for *lookup* never
  enters. Probed on this platform: `shopt -s nullglob; echo RESEARCH-*.md` yields only
  `RESEARCH-tiers.md`, while `test -f RESEARCH-checklist.md` succeeds.

  Both claims are struck. The two legs that ARE real — a dropped `RESEARCH-` anchor and a
  case-insensitive `grep -oiE` harvest — were verified by mutation and are unchanged. A glob rewrite
  is still caught, by the named-but-missing sidecar cases it cannot satisfy; that is now stated where
  the wrong claim used to be. No behavior changes: the gate, the fixture, and all 103 cases are
  untouched.

## [0.12.1]

### Fixed

- **The dispatch gate's stdout assertions no longer discard the exit status.** `stdout_raw` and
  `stdout_has` in `scripts/check-dispatch-artifact.test.sh` ran the gate, compared the verdict line,
  and never looked at `$?`. Most cases happened to have an exit-code twin over the same fixture; at
  least one — the coverage-ledger case — did not, so a gate emitting the documented line under the
  wrong status passed it. Both helpers now take the expected exit as their first argument, matching
  the `run` / `run_raw` convention already in the file. Proven by mutation: with the gate's success
  path changed to `exit 3`, the ledger case reports `ok` under the previous helpers and `FAIL` under
  these.
- **The coverage-ledger test case now discriminates.** Its fixture wrote `research-checklist.md` into
  the slice but never named it in the index, and the gate harvests sidecar names from the index
  **text** — so no implementation of the current design could have counted it, and the case asserted
  something its label implied but did not test. The index now mentions the ledger the way a real run's
  restatement or handoff does, with the file still on disk beside it, so the case fails against a
  harvest that drops the `RESEARCH-` anchor or matches case-insensitively. Verified by mutation:
  under a `grep -oiE` harvest the case fails, where the previous fixture passed.

### Changed

- **`skills/research/SKILL.md` and `skills/research-deep/SKILL.md` state that one slice-root freshness
  baseline covers an N-topic fan-out.** The pre-dispatch step reads singular while a fan-out parent
  assigns N sub-slices; both readings were already correct, because the gate compares each sub-slice
  index's mtime against the file it is handed and a baseline touched now is newer than anything an
  earlier run left under the slice. One clause now says so in both files — identical from the em-dash
  onward, with only the lead-in differing, because each file's surrounding sentence already frames the
  fan-out differently. `research-deep` is where a reader actually performing the fan-out is standing,
  and its existing rule there covers per-sub-slice *grading* but said nothing about the baseline. No
  procedure changed, and no parity gap opens on the explore side, which has no fan-out.
- **The `[0.12.0]` entry below is internally consistent about the pre-dispatch command.** It described
  the baseline as a bare `touch`, then its own `### Fixed` section introduced the `mkdir -p` as
  load-bearing. The description now carries both halves. No other history was touched.

### Deliberately not done

- **No deprecation shim for `scripts/check-explore-artifact.sh`.** The `0.12.0` rename is a clean
  break and stays one. `docs/PLUGIN-PHILOSOPHY.md` rules out "silent backward-compatibility shims and
  dual-read windows" on the clean-break path, and the fleet's three prior renames — `claude-memory`
  `0.2.0`, `code-tidying` `0.6.0`, `claude-config` — each shipped as a BREAKING changelog line saying
  the old invocation stops resolving, with no shim. Those were user-facing skill invocations; this is
  a script inside the installed plugin cache, reachable only by a `${CLAUDE_PLUGIN_ROOT}`-relative
  path from this plugin's own skills, so it was never a supported external contract to begin with.
  The changelog entry is the contract.

## [0.12.0]

### Added

- **The dispatch acceptance gate now covers `/discovery:research`, not just `/discovery:explore`.**
  `0.11.x` hardened the explore dispatch with an on-disk artifact check, a freshness baseline, a
  pointer cross-check, and a recovery ladder, and left the research side with none of them — so a
  `researcher` that returned a mid-stream narration line as its whole payload was still accepted on
  the strength of `status: complete`, exactly as the explore-side failure that produced the gate.
  - `skills/research/SKILL.md` — new parent-side acceptance gate in the routing section: a
    pre-dispatch `mkdir -p <slice> && touch <slice>/.research-dispatch` baseline (the `mkdir -p` is
    load-bearing — see **Fixed** below), a payload well-formedness step, the
    off-disk artifact check cited by **exit status**, and a ledger step. A non-zero exit halts the
    workflow rather than annotating it.
  - `skills/research/context/dispatch.md` — the rationale spoke: why the gate grades the parent's own
    slice path rather than the payload's `artifact:`, why one gate serves both skills, why the ledger
    is a separate script rather than a flag, the two freshness limits that follow from that, and a
    research-specific recovery ladder.
  - `skills/research/evals/evals.json` — a gate eval (`empty-payload-halts-the-dispatch`), the
    counterpart of the explore suite's.
  - `skills/research-deep/SKILL.md` — the **other** parent of `discovery:researcher`, and the one
    that actually performs the N-topic fan-out. Its post-dispatch boundary now names the gate as the
    step that comes before the four obligations, and carries the fan-out rule the gate implies:
    grade each topic against the sub-slice it was assigned, before synthesizing the slice-root
    index, because the gate reads a synthesized root alongside its sub-slices as ambiguous.

### Changed

- **`scripts/check-explore-artifact.sh` → `scripts/check-dispatch-artifact.sh`, parameterized by
  `--index-name`.** One gate now serves both skills, because they share one on-disk shape:
  `artifact-shape.md` states that the index shape, the section-keyed sidecar filenames, the sub-slice
  rule, and both placement rules are identical for exploration, and that what differs is the sidecar
  YAML **header** — which this gate never opens. Every check in it operates on the identical surface,
  so a second copy would have duplicated ~300 lines of reasoned logic in a repository that ships a
  cross-plugin source-drift checker to police exactly that.
  - **`--index-name` is required, never defaulted.** A silent `EXPLORE.md` default would grade a
    research slice against the wrong family — reporting a successful run as unusable, or, in a slice
    that also holds an exploration, reporting a research dispatch that wrote nothing as usable. Its
    stem is also interpolated into the sidecar-matching ERE, so the flag rejects anything outside
    `[A-Za-z0-9_-]` rather than silently widening what counts as a sidecar.
  - **Fixed on the way past:** the "index names no sidecar" branch printed a short verdict line
    missing the documented `freshness=` and `pointer=` fields, so a parent grepping the verdict line
    for them found nothing on exactly one of the failure paths. It now reports through the same
    `verdict` helper as every other outcome.
  - `scripts/check-dispatch-artifact.test.sh` — the shape suite now runs **twice**, once per artifact
    family, plus new cases for `--index-name` itself: missing, value-less, non-`.md`, regex-unsafe
    stems, both directions of cross-family isolation, and `research-checklist.md` not being counted
    as a sidecar.
  - `skills/explore/SKILL.md` and `skills/explore/evals/evals.json` — the invocation and the eval
    rubric follow the rename and pass `--index-name EXPLORE.md`, and the "only the slice path is
    required" sentence is corrected to name `--index-name` alongside it.

### Fixed

- **The freshness baseline could not be taken on a first-time topic.** Both skills told the parent to
  `touch <slice>/.<skill>-dispatch` before dispatching, and on a scope or topic whose slice does not
  exist yet that `touch` fails — so the dispatch either stopped before it started or reached the gate
  with no baseline to grade against, which is exit 2. Now `mkdir -p <slice> && touch …` on both sides,
  including `skills/explore/reference/dispatch.md`. Found by review on this PR; the defect predates it
  on the explore side, and fixing only the research side would have opened a fresh parity gap.

### Deliberately not ported

- **A `verification: pending` payload check.** The researcher's contract already makes that field
  non-negotiable, but adding a parent-side check for it on this side alone would open a fresh parity
  gap in the other direction. It belongs to a change that does both skills at once.
- **A ledger freshness check.** `--newer-than` binds the index, not `research-checklist.md`, and the
  ledger gate reads marks rather than provenance. The gap is real but narrow — it needs a re-dispatch
  into a dirty slice whose replacement run found the corpus unbounded — and it is closed by the
  ladder's "clear the slice before re-dispatching" rung rather than by a one-caller flag on the
  shape-agnostic half of the pair.

## [0.11.3]

### Changed

- **`research-deep` now dispatches `discovery:researcher` at both of its worker-spawning call
  sites.** Tier 2 spawned a bare `general-purpose` agent with a long inline prompt that hand-carried
  the research discipline, and the N-topic fan-out spawned N more the same way — while the plugin
  already ships the purpose-built worker that `/discovery:research` routes to. Two ways of running
  one discipline, and the second was the weaker one: a hand-written prompt is a copy of a contract
  that lives in `skills/research/`, so it is only ever as disciplined as that copy is faithful, and
  a spawn with no calibration runs at whatever effort and turn budget it inherits rather than the
  ones tuned for this work.
  - **Both call sites move together.** Migrating one would have left the other as a silent second
    way of doing the same thing, which is the shape this change exists to remove.
  - **One shared envelope section** now serves both paths — the six fields the agent refuses to
    guess (topic, the reason it is being researched, memory-slice path, memory root as its own
    field, budget, capability flags), with the field-by-field rationale pointed at
    `skills/research/context/dispatch.md` rather than restated. The N-topic path keeps its
    parent-assigned sub-slices and passes the memory root separately, which is exactly the nested
    case the agent names: a worker handed a sub-slice path cannot tell from it which ancestor is the
    configured root.
  - **The researcher's `tools` allowlist is gone, so session MCP tools reach the worker again.**
    The migration's review surfaced that the allowlist silently dropped every MCP tool the former
    `general-purpose` spawn inherited — the sub-agents reference is explicit that a `tools`
    allowlist excludes MCP tools while an unrestricted definition keeps them. The agent now
    inherits its pool (background tool filtering still applies), restoring source-specific
    documentation and synthesis MCP tools to both this skill's dispatches and `/discovery:research`'s.
  - **`Budget` is documented as narrowing-only** — the researcher's fixed `maxTurns: 40` is a
    ceiling the envelope cannot raise; work needing more depth belongs to Tier 1's engine. The
    envelope-rationale pointer is scoped honestly: `dispatch.md` carries five of the six fields,
    and `Memory root`'s rationale lives in the researcher's own contract.
  - **The dispatch prompt is envelope fields only.** The disciplines, the citation rule, the outcome
    gate, and the return-payload shape are the agent's own standing contract; the old prompt's
    carry-verbatim reminders are the copy that drifts the moment the parent skill changes.
  - Everything the old prompt enforced that is genuinely parent-side is unchanged: per-topic
    sub-slice assignment, the N ≥ 2 decomposition rule, and the post-dispatch boundary this session
    closes for every dispatched run before surfacing anything. The Tier 2 rationale sentence now
    reads on discipline-at-turn-zero and calibration; the tool-access half — Phase 3 needs
    direct-fetch and MCP tools, and the artifact must be written, which a read-only Explore agent
    cannot do — survives as the secondary reason it always was.
  - `agents/researcher.md` and the README agent table named `/discovery:research` as the sole
    dispatcher; both now name `/discovery:research-deep` too, and evals 1 and 3 grade the agent type
    and the envelope rather than a `general-purpose` spawn.

## [0.11.2]

### Changed

- **`research-deep`: the multi-topic fan-out now has a ceiling.** N came straight from the user's own
  topic count with a stated floor (N ≥ 2 dispatches parallel agents) and nothing above it, so a
  twenty-topic ask dispatched twenty agents. N is now capped at roughly a dozen, past which the ask
  gets narrowed with the user before dispatching — the same wave cap the `discipline` plugin already
  uses, rather than a new threshold invented here.

## [0.11.1]

### Fixed

- **The plan-mode filter claim bundled two tools under one unconditional rule, and only one of them
  is unconditional.** `skills/explore/SKILL.md` and `agents/explorer.md` both stated that
  "`EnterPlanMode` and `ExitPlanMode` are filtered out of every non-fork subagent". Verified
  2026-08-08 against the official subagent docs, which list the first filter's removals as
  "`EnterPlanMode`" with no qualifier and "`ExitPlanMode`, unless the subagent's `permissionMode` is
  `plan`". `ExitPlanMode` carries a carve-out; `EnterPlanMode` does not.
  - The correction is not an appended qualifier. Attaching the carve-out to the joined sentence
    would have spread it to `EnterPlanMode`, replacing a claim that is too strong with one that is
    too weak — and too weak in the direction that matters, since it would imply a dispatched run
    could enter plan mode. The two tools are now stated separately.
  - **The surrounding conclusion survives, and now rests on the `tools` allowlist rather than on
    the filter alone.** Both sites conclude that a dispatched run's read-only boundary is the
    agent's own instruction, not harness enforcement. Deriving that from `permissionMode` would
    not hold: the same page states subagents "inherit the permission context from the main
    conversation", naming only `bypassPermissions`, `acceptEdits`, and `auto` in its precedence
    rules, so a definition's silence on `permissionMode` does not by itself settle which mode the
    subagent runs in. `agents/explorer.md` instead declares `tools: "Read, Grep, Glob, Bash,
    Write, Skill, Agent"` — an allowlist naming neither plan-mode tool — so it holds neither
    however the filters and inheritance resolve. That is a property of the definition in the
    repository, checkable without reasoning about permission-mode precedence at all.

## [0.11.0]

### Changed

- **Both dispatch envelopes now carry the reason the work is being done**, not only what to do. A
  section-by-section audit against Anthropic's Fable 5 prompting guide found that every
  dispatch-brief contract in this marketplace specified outcome, output shape, sources, and
  boundaries — and none carried intent. That guide singles out long-running agents drawing on
  multiple workstreams as where the omission costs most, and a dispatched worker is that case at its
  sharpest: it has no conversation to infer intent from.
  - Both halves of each contract move together, which is the part that makes it bind. The parent
    side states the field in the envelope (`skills/explore/SKILL.md`, `skills/research/SKILL.md`,
    and the envelope table in `skills/research/context/dispatch.md`), and the worker side adds it to
    the list it refuses to guess (`agents/explorer.md`, `agents/researcher.md`). Adding it to the
    parent alone would leave a worker that accepts a reason-less prompt without noticing, which is
    the silent failure the field exists to stop.
  - The justification travels with the field in every one of those places: a missing topic or scope
    is silence the agent can report, while a missing reason is invisible — the agent works the topic
    as written, returns something well-formed, and neither side learns it answered the wrong
    question. Intent is what decides which of several defensible readings is the one wanted.
  - **The enforcement sentence names the reason too.** Listing a field under "refuse to guess" and
    then omitting it from the `status: truncated` rule directly below leaves the field advisory: the
    agent reads the obligation and nothing makes a missing reason stop the run. Both agents now halt
    on an absent or ambiguous reason exactly as they do for an absent scope, topic, or slice path.

## [0.10.1]

### Added

- **`explore`: sidecar bodies get a length calibration.** Every surrounding surface was already
  calibrated (one-line index abstracts, one-line YAML findings, a sentence-capped agent return),
  but the sidecar bodies — where the bulk of the disk-written artifact lands — carried no length
  guidance, and the outcome gate is a floor (no placeholders), not a ceiling. SKILL.md now
  carries the calibration: match body length to what the section needs; cover the substance
  without filler sections, redundant summaries, or boilerplate.

## [0.10.0]

### Added

- **A deterministic acceptance gate for a dispatched `/discovery:explore` run.** A consuming project
  reported an `explorer` dispatch that returned `status: completed` carrying a mid-stream narration
  line as its entire payload — no `preload_token`, no summary, no artifact path — and the parent
  proceeded as though exploration had finished. The contract that was supposed to stop that was
  already present as prose, and had been since `78e89e12`, four days before the run that failed;
  another paragraph would have been the same category of thing. So the check is now runnable and
  fails closed.
  - `scripts/check-explore-artifact.sh` — new. Takes the memory-slice path the **parent** resolved
    before dispatching, and grades the run off disk: exactly one `EXPLORE.md` (slice root or one
    level below, the sanctioned sub-slice depth), non-empty, naming at least one
    `EXPLORE-<section>.md` sidecar, with every named sidecar present beside it and non-empty. Exit 0
    usable, 1 no usable artifact set, 2 ungradeable. Three opt-in checks extend it — `--newer-than`
    (the index is newer than a baseline the parent touched pre-dispatch), `--expect-index` (the
    payload's pointer resolves to the file that was graded), and `--expect-sidecars` (the payload's
    count matches what the index names). Each reports `unchecked` in the verdict line when it is not
    run, so a skipped check never reads as a passed one.
  - `scripts/check-explore-artifact.test.sh` — new. 46 black-box cases, weighted toward the readings
    that would be invisible if wrong: an empty slice, a stub index, an index naming files nobody
    wrote, a stale artifact from an earlier run, a payload pointing somewhere else, and two candidate
    indexes must never report `usable`.
  - `skills/explore/SKILL.md` — new parent-side acceptance gate in the routing section, citing the
    script's **exit status** rather than a reading of the directory, and stating the halt explicitly:
    a non-zero exit stops the workflow rather than annotating it.

  **The path deliberately comes from the parent's envelope, never from `artifact:`.** The payload is
  the broken party in the reported failure, so a check that reads its own input from the payload
  cannot see that failure at all.

  **Two ways an on-disk check can still pass a failed run, both now closed.** Existence is not
  freshness: a slice already holding an earlier run's complete artifact set satisfies every check
  even when this dispatch wrote nothing, and the sidecar count agrees because both runs write the
  same sections — hence the pre-dispatch `.explore-dispatch` baseline and `--newer-than`. And because
  the gate selects the index from the parent's slice path rather than from the payload, the two are
  free to disagree: a payload naming another file is not corroborating what was graded, and its
  `verification_request.target` would aim the sibling verifier at a file the gate never looked at —
  hence `--expect-index`, with the gate's own `index=` authoritative for the verifier and the
  handoff.

- **The missing half of validate-on-receipt.** The parent's rule covered a missing or mismatched
  `preload_token` and nothing else. A payload carrying **no artifact pointer** is now stated to be a
  failed dispatch regardless of the `status` field it reports.

- **`skills/explore/reference/dispatch.md`** — new spoke carrying the parent's obligations, why
  `test -s` alone was not enough, and the recovery ladder the reporting session had to find by trial
  at a cost of roughly eight minutes. Resume the agent by **agent ID** with `SendMessage` when it is
  still live; fix the envelope yourself on an exit 2; discard and re-dispatch on a refused resume.
  Verified 2026-08-08 against the official subagents page
  (<https://code.claude.com/docs/en/sub-agents>): "When a subagent completes, Claude receives its
  agent ID", "Claude uses the `SendMessage` tool with the agent's ID or name as the `to` field to
  resume it", "A completed subagent that receives a `SendMessage` auto-resumes in the background
  without a new `Agent` invocation", and — the reason the ladder says ID rather than name — "As of
  v2.1.199, `SendMessage` checks that a name still refers to the same agent it reached earlier in
  the conversation". The same page bounds the claim: a subagent the **user** stopped "doesn't
  auto-resume", and the built-in Explore agent this skill names as its one alternative is one-shot
  and "can't be resumed", so the ladder is scoped to the custom `discovery:explorer`.

## [0.9.3]

### Fixed

- **The `Workflow`-tool availability claim omitted the fork exception.** Three places stated flatly
  that a subagent cannot reach `Workflow`, contradicting `skills/research-deep/SKILL.md`'s own
  gotcha, which already scoped the filter to *non-fork* subagents. Verified 2026-08-05 against the
  official subagent docs: "Subagents inherit the built-in tools and MCP tools available in the main
  conversation, narrowed by two filters ... Forks skip both filters and receive the main
  conversation's exact tool pool" — and `Workflow` is one of the tools that first filter removes.
  A fork therefore *does* hold `Workflow`; the unqualified wording told it Tier 1 was categorically
  out of reach and silently degraded it to Tier 2.
  - `README.md` — the `/discovery:research-deep` row.
  - `skills/research-deep/SKILL.md` — the frontmatter `description` and the Purpose paragraph.

- **Tier 2 was labelled a fork, which it is not.** `/research-deep`'s fallback tier spawns an
  ordinary isolated `general-purpose` subagent; nothing about it forks the conversation. Calling it
  "forked" collided with the genuine fork distinction the fix above turns on — that a *fork* holds
  `Workflow` and a non-fork subagent does not — so the same word carried two meanings, one of them
  wrong. Tier 2 is no longer called a fork anywhere; its explicit label is now "isolated subagent".
  The true-fork references (the `Workflow` filter and the `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`
  nesting allowance) are unchanged.
  - `skills/research-deep/SKILL.md` — the frontmatter `description`, the tier table, the Tier 2
    heading, and the post-dispatch boundary paragraph.
  - `skills/research-deep/evals/evals.json` — eval 3's name and first expectation, and eval 5's
    expected output. Eval 3's expectation previously accepted "forked/isolated" and now requires
    "isolated", tightening it in the direction of the corrected label.
  - `reference/topic-docs.md` — the visibility section called the `-deep` executions "forks" and
    named `EXPLORE.md` as one of their artifacts. `-deep` resolves solely to `research-deep`, whose
    isolated subagent writes `RESEARCH.md`; `explore-deep`, whose frontmatter did declare
    `context: fork`, was retired in 0.9.0. The checkout-locality claim the sentence exists to make
    is unchanged. This document is loaded at runtime by the skills, so the stale label reached them.
  - `README.md` — the graceful-degrade roster advertised "forked subagents" as an adjacent
    capability; no skill in the plugin declares `context: fork`, so the roster now names subagents
    plainly.

- **The main-context rationale carried only half its reason.** All three statements of why
  `/research-deep` must run inline cited the `Workflow` tool alone — which, once that claim is
  correctly scoped to non-fork subagents, licenses a fork to dispatch the skill. The rationale now
  also carries the `Agent`-spawn leg that `skills/research-deep/SKILL.md`'s *Dispatching this skill
  itself* gotcha already stated, and which holds for forks too: at the configurable depth limit a
  fork keeps `Agent` listed but the spawn errors, so no dispatched context guarantees it.
  - `README.md` — the `/discovery:research-deep` row.
  - `skills/research-deep/SKILL.md` — the frontmatter `description` and the Purpose paragraph.

## [0.9.2]

### Fixed

- **`/research-deep`'s single-topic tiers returned an artifact nobody had graded.** The
  post-dispatch verification boundary — dispatch the sibling verifier, apply project fit, write both
  back into the index — was stated only inside the `N >= 2` multi-topic branch. Tier 2 returned the
  worker's summary and artifact path directly and Tier 1 said to surface the engine's return, yet no
  producing context can complete the `/research` outcome gate's verifier-owned rows (independent
  corroboration, HIGH confidence) or its parent-owned row (project fit): the first two belong to a
  fresh context by design, the third needs the consuming project's conventions, and nested `Agent`
  availability is not something a producer can be relied on to have. The main session could
  therefore present claims as gate-passed that were never graded.

  The boundary is now **one section that every dispatching tier cites** rather than prose inside the
  multi-topic branch, so Tier 1, Tier 2, and each topic worker are covered by construction and the
  multi-topic paragraph points at it instead of restating it. Tier 2's dispatch envelope asks the
  worker to leave those rows `pending`.

- **The evals encoded the retired artifact layout and rewarded the defect above.** `evals/evals.json`
  required each topic worker to write a sibling `research-<topic>.md` at the slice root — the
  collision-prone contract replaced by per-topic sub-slices (`<memory_dir>/<slug>/<topic-slug>/`)
  each holding a normal `RESEARCH.md` — so running it penalized the compliant layout and could not
  protect the fix from regression. Eval 1 now requires per-topic sub-slices, session-assigned paths,
  and the per-topic verification boundary. Evals 2 and 3 gain that boundary for Tier 1 and Tier 2;
  eval 2 previously expected the engine's summary and artifact path to be surfaced directly, which
  is exactly the behavior the fix removes.

## [0.9.1]

### Fixed

- **Nested-spawn availability claims described a state that lasted two releases.** Four places
  asserted that the harness "filters `Agent` out of every non-fork subagent unless
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is set" — true only for Claude Code 2.1.217–2.1.218.
  Verified 2026-07-26 against the byte-exact release changelog: nesting shipped at a fixed five
  layers (v2.1.172 — "Sub-agents can now spawn their own sub-agents (up to 5 levels deep)"), went off
  by default (v2.1.217), and returned at v2.1.219 — "Subagents can now spawn nested subagents up to
  depth 3 by default (was 1); set `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` to disable nesting."
  Confirmed behaviorally on 2.1.220: a non-fork `general-purpose` subagent held a fully-schema'd
  `Agent` tool with the variable unset. Note the polarity flip the stale wording hides — the variable
  now *lowers* the ceiling as readily as it raises one, so "absent" no longer implies "off."
  - `agents/explorer.md`, `agents/researcher.md` — the necessary-not-sufficient framing and the
    check-the-tool-is-actually-there instruction were already right and are kept; only the reason
    changes, plus a new caution that a denied spawn is a permission verdict rather than a depth one
    (spawns are classifier-evaluated before launch).
  - `skills/setup/SKILL.md` — the dispatch-capability row no longer recommends setting the variable
    on the assumption that absent means off. It now reports the value against the version and names
    which window each reading belongs to.
  - `skills/research-deep/SKILL.md` — two spots restated as availability that must be observed
    rather than derived. The claim that `Agent` "errors even inside a fork" is replaced by the
    invariant that actually holds: a fork cannot spawn a further fork.
- Load-bearing behavioral claims here are now version-pinned, so the next default move is visible as
  drift instead of reading as settled fact.

## [0.9.0]

### Removed

- **BREAKING: `/discovery:explore-deep` is retired.** Callers use `/discovery:explore`, which now
  dispatches `discovery:explorer` by default and provides the same isolation — project memory
  loaded, artifact persisted by the worker, only a bounded summary returning. The retirement was
  gated on the agent reproducing what the skill carried beyond `/explore`, and it does, including
  the two conditions that were load-bearing: path-scoped project rules Read explicitly (a subagent
  does not auto-load them, and convention-blind findings are how a downstream edit lands against the
  project's declared direction), and sidecar-on-collision with the chosen filename surfaced in the
  return (a prior exploration lost to a filename collision is silent and unrecoverable). Two
  behaviors were deliberately NOT carried over: the empty-scope repository-orientation pass, because
  a dispatched agent with no scope is a parent-envelope failure rather than a mode, and the `!`
  precompute, which fires at every spawn before the agent knows it needs the data and multiplies
  under fan-out.

### Added

- **`discovery:explorer` and `discovery:researcher` — the plugin's first agents.** Each preloads its
  skill through `skills:`, so the discipline arrives as content at turn zero rather than as a
  recollection the agent may or may not reach for. Neither declares `memory`, and that omission is
  load-bearing: declaring it auto-enables `Edit` regardless of the `tools` list, which would falsify
  each agent's own tool-honesty note. That note states only what the tool set actually buys — no
  single-call in-place mutation of an existing repo file — and explicitly not read-only status,
  because `Bash` and `Write` both write.
- **Dispatch by default for `/discovery:explore` and `/discovery:research`.** From the main
  conversation each dispatches its agent; the conversation gains a file pointer and a summary rather
  than the transcript. Three documented conditions send a run inline instead — tight turn-by-turn
  iteration, cost on a lookup too small to justify an envelope, and an invoking context that is
  itself a subagent (hoisting: the outer dispatch already supplied the fresh context, so an inner
  hop only spends the inner window). Running inline relaxes no discipline.
- **A preload-liveness sentinel on both skills.** A `skills:` entry that fails to resolve is skipped
  **silently** — logged to the debug log and nowhere else — producing an undisciplined run that
  still writes an artifact and still reports complete coverage, indistinguishable from success at
  every other seam. Each skill now carries a token the dispatched agent echoes verbatim into its
  return payload, and the parent discards any run whose token is missing or mismatched rather than
  downgrading or accepting it.
- **Phase 0 corpus enumeration and a scripted coverage gate.** When a topic has a finite, knowable
  set to cover, `/discovery:research` writes `research-checklist.md` before the first query, one row
  per corpus item with a depth criterion fixed at enumeration time — a criterion written afterwards
  drifts down to whatever the run managed. The enumeration surface must be exhaustive by
  construction (a sitemap, an in-repo tree, a release list); a ledger built from search results
  certifies the blind spot it exists to close. New outcome-gate criterion 11 cites the exit status of
  `scripts/check-coverage-complete.sh` rather than a reading of the table, because the context most
  motivated to call a checklist finished is the one reading it. The script fails closed: a ledger it
  cannot parse exits 2, and 2 is a FAIL.
- **`discovery:setup check` reports dispatch capability** — harness version against the 2.1.219
  floor, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, and fork availability — as PASS/INFO rows only.
  Absence degrades rather than blocks: nesting buys throughput, not coverage, because the one control
  needing a context that has not seen the work is the outcome-gate verifier, which the parent
  dispatches as a sibling.

### Changed

- **`EXPLORE.md` and `RESEARCH.md` are always an index**, at every size rather than past an overflow
  threshold, with content in sibling sidecars carrying a machine-readable YAML header. A size
  threshold makes the artifact's shape depend on how much a run happened to write, and it arrives
  exactly when the artifact is already too big to skim. Sidecar headers carry per-claim `sources[]`
  with `url`, `tier`, and `pool` — that is what makes the independent-corroboration criterion
  gradeable by a verifier that never saw the run, since independence is a property of publishing
  pools and a bare tier list encodes neither.
- **The outcome gate grows an Owner column.** Criteria asking the run to judge the quality of its own
  choices — independent corroboration, and HIGH confidence per accepted claim — move to a sibling
  verifier the parent dispatches; project fit stays with the parent, which alone holds the consuming
  project's conventions. A dispatched run returns `verification: pending` and renders no verdict on
  those rows.
- **The Tier-3 rule for subagent returns gains a scoped exception.** It targets an ad-hoc subagent
  handing back synthesis with no captured primaries, and stays in force for that. It does not reach a
  `discovery:researcher` run that executed the discipline and wrote every primary URL into the
  artifact: the tier attaches to the artifact and its captured sources, never to the transport.
  Without this, dispatch-by-default would demote every run to the tier the gate's first criterion
  refuses.
- **Three statements preferring inline execution are overturned**, not softened — dispatch-by-default
  contradicts them outright. Two were making a real point badly and are restated in terms that hold
  in either posture: the run that judges a claim should be the run that read the source, and
  summarization loss is bounded by what the artifact persists.
- **Open questions hand back instead of being surfaced directly.** `AskUserQuestion` is unavailable
  in every non-fork subagent, so a dispatched run returns them in its payload and the parent surfaces
  them. The anti-pattern being guarded — silent downstream resolution — is unchanged; only the
  hand-off moves. Same for the ask-before-git-archaeology rule on deleted files, which a dispatched
  run records as an open question rather than proceeding past.

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
  probed-and-not-existing, fetched-and-lacking-the-claim, or unreachable-and-enumerated as a Gap. An
  unprobed "nothing deeper
  exists" would let the shallow run this criterion targets nominate its own landing page as the top,
  while the not-existing outcome keeps the common legitimate case — most claim classes ship no rung-1
  artifact — representable without fabricating a fetch. That outcome carries its own evidence bar so
  it cannot become the escape hatch the criterion exists to close: it is earned against an exhaustive
  first-party surface (a sitemap, the in-repo docs tree, a releases listing), never against a search
  miss or a curated `llms.txt`, which the doc-index table itself calls deliberately partial. A rung
  those fail to surface is unresolved — a Gap naming the discovery surfaces checked and unchecked. A probe locates a rung; it does not grade
  one, so it can establish a rung's absence but never that a rung which exists lacks the claim: a
  title, index entry, or search snippet is exactly what omits the section being chased, and a
  probe-only lacks-the-claim outcome is how a system card gets walked past with the gate still
  passing. A bare fetch record, equally, would
  let a run log the deeper artifact it found and source from a
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
  the fetch. `curl -g` covers the same ground on curl's side: `{}` and `[]` are legal URL characters
  that curl reads as sequence syntax no matter how the shell quoted them, expanding one URL into
  several requests over a single output path. The artifact downloads extensionless with `-D` capturing the headers from the same
  transfer — naming the file by type up front is circular, since the path must exist before the
  response that reveals the type, and re-fetching to learn it costs a second full transfer of a
  large or single-use signed download. The recorded `Content-Type` is corroborating evidence in both
  directions and decisive in neither: a challenge page and the real spec are both `text/html`, and a
  valid PDF served as `application/octet-stream` is confirmed by its signature rather than rejected
  for its type — otherwise a complete local download gets reported as unreachable. The same
  asymmetry applies to the challenge-shape rejections: a consent surface disqualifies the download
  when it stands in place of the artifact, not when a cookie banner merely sits alongside a document
  whose title, headings, and body are all present. Extraction is checked for usable text
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
