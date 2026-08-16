# Changelog

All notable changes to the `plugin-quality` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.4]

### Changed

- **The `auditor` grounds harness claims on the raw-markdown `curl` route, not `WebFetch`
  (issue 2854).** Step 3 of `agents/auditor.md` prescribed `WebFetch` as the default for every
  load-bearing harness-behavior claim. That is rung 2 of the ladder in
  `docs/conventions/upstream-drift/README.md`, which the convention labels *degraded* and which
  truncates long pages silently — and "not in the response" is indistinguishable from "not on the
  page". The step now names the convention's rung-1 route (`curl` the `.md` channel to a file,
  search the file locally) as the default, points at the convention for the ladder and the identity
  and absence checks rather than restating them, and keeps `WebFetch` only for pages with no
  raw-markdown channel. The tool-honesty note was amended in step: the step-3 `curl` joins Bash's
  enumerated uses, and the network clause now permits it alongside `WebFetch` instead of capping
  network reach at `WebFetch`.
- **A quotation must survive a literal substring search of the fetched bytes.** The same step states
  the concrete check — `grep -c -F` a distinctive fragment against the saved file, non-zero or it is
  not a quote — and that a failed fetch, an unresolvable `.md` channel, or a fragment that does not
  match is recorded as **unverified**, never reconstructed from recall. Realized cost that motivated
  this: two fabricated load-bearing doc quotes reached filed-ready drafts in one audit chain, both
  attributed verbatim to the hooks reference, neither present in it.
- **The step stands alone from a plugin cache.** The auditor runs from an installed plugin cache,
  where this repo's convention file is not on disk — so a step that only pointed at it would have
  been unexecutable. The rules the step needs are stated inline (the rung-1 route, the canonical-slug
  and first-heading identity checks that make an absence assertable, the substring check), with the
  convention named as the owning record for the full text rather than as a required dereference. The
  agent's closing contract and its network clause were widened to match: both previously forbade the
  fetch and the scratch file the new step requires.
- **Doc citations now carry their retrieval channel.** The agent's output contract requires each
  harness-behavior citation to state the channel it came over and a byte count or line number
  alongside the URL and fetch date, and `skills/audit/SKILL.md` step 3 records a finding whose
  citation omits the channel as unverified — so the requirement binds where the output is consumed,
  not only where it is produced.

## [0.6.3]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.6.2]

### Changed

- **Adopt upstream-drift stamp on hook audit exit-code semantics (#2297 carrier 1).** The
  component-type checklist now carries basis, as-of date, and a recheck trigger for the
  PreToolUse/PostToolUse exit-code contract instead of an unstamped harness assertion.

## [0.6.1]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `scripts/packet-seal.sh`, `agents/auditor.md`, `skills/audit/SKILL.md` — `PostToolUse`
    firing after a tool call succeeds, and a matcher keying on the tool name, both still stated in
    the hooks reference. The tamper-evidence rationale is unchanged.
  - `skills/audit/references/component-types/config.md` — the monitor `when` trigger, its
    `"always"` default, and `"on-skill-invoke:<skill-name>"` (plugins reference, monitors).

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.1] - 2026-08-08

### Changed

- **`audit`'s description drops its shouted trigger qualifier.** "Use WHENEVER you are vetting,
  reviewing, stress-testing, or hardening a plugin component" now reads "Use when vetting, …"; the
  concrete trigger phrases listed immediately after are what actually route the skill, so the
  emphasis added nothing.

## [0.5.0] - 2026-08-04

### Added

- **Config lens covers plugin-shipped harness config files.** The plugins guide
  (<https://code.claude.com/docs/en/plugins>, fetched 2026-08-04) specifies three plugin-root
  config surfaces the lens predated, each with a silent failure mode worth auditing:
  `settings.json` (only `agent` and `subagentStatusLine` supported; unknown keys silently ignored;
  wins over `settings` in `plugin.json`), `.lsp.json` (an invalid entry is skipped — only
  `claude --debug` says why; a failed start surfaces in the `/plugin` Errors tab), and
  `monitors/monitors.json` (start governed by the `when` trigger — `"always"` default vs
  `"on-skill-invoke:<skill-name>"`; every stdout line reaches Claude as a notification).
  `config.md` now names the surfaces and their checks, and the hub's index row routes them there.

## [0.4.0] - 2026-07-31

### Added

- **`scripts/packet-prune.sh` — retention as a mechanism instead of prose (#1808).** The rule was
  a sentence telling the model to "delete packet directories older than 30 days": an unbounded
  recursive delete, over the one tree that also holds the only durable copy of an unattended run's
  emitted work item, left entirely to model obedience. The two safety properties now live in the
  script and hold whether or not the paragraph is read — it is **dry-run by default**, and it
  **never deletes a packet containing `item.md`** at any age, because step 6's unattended clause
  sends every unattended run to rung 4 and makes that file the sole copy of the audit's entire
  output. Age is graded from the nonce directory NAME, not mtime, so retention does not depend on
  the same in-place mutation the packet exists to resist; an ungradable name is reported and kept.
  "Ungradable" is decided by round-tripping the calendar value through `date`, not by the name's
  character shape: `00000000T000000Z` matches the nonce pattern exactly, names no instant that
  exists, and sorts below every cutoff, so a shape-only test classified it `DELETE` and `--apply`
  destroyed it — the precise fail-closed violation the rule exists to prevent. A value the
  implementation rejects (GNU) or silently normalizes to another day (BSD turns Feb 31 into Mar 3)
  cannot round-trip identically, and any uncertainty routes to `UNPARSABLE`, never to `DELETE`.
  Because failing closed silently would be its own defect — a `date` that exists but cannot
  round-trip would grade every packet ungradable, stopping retention forever while still reporting
  success — the already-validated cutoff is run through the same path at startup, and a userland
  that cannot reproduce a known-good nonce is refused with exit 2 like a missing `date`. That
  self-check is also the only thing that can catch a broken BSD branch, which no GNU-only CI reaches.
  The root must be named `evidence`, so a mistyped path is refused before anything is walked, and
  containment is re-established **per candidate** by canonicalizing it — checking only the root let
  a symlinked session directory yield a path whose real location is outside the tree, which an
  independent review reproduced as an `rm -rf` outside the evidence root. Such candidates report
  `ESCAPED` and are skipped; deletion targets the canonical path. The `item.md` search is recursive
  and case-insensitive, because a deliverable one directory down is exactly as unrecoverable. A
  delete that fails is its own `FAILED` verdict and exits 1, so an incomplete retention pass is not
  indistinguishable from a clean one; a dry run reports `would-delete=` rather than `deleted=`.
- **`scripts/packet-seal.sh` — tamper-evidence for packet files (#1808).** `record` writes a
  `packet.sha256` manifest; `verify` reports `MATCH`/`CHANGED`/`MISSING`/`UNSEALED` per file and
  fails closed on a packet it cannot grade. The resume rule and the `auditor` both verify before
  trusting packet content. Altered and merely-unsealed are **separate exit codes** (1 vs 3): a
  packet legitimately gains files after its last seal — `contract.md` at step 4, `item.md` at step
  6, both of which now re-seal — so collapsing them would have made the ordinary interrupted-run
  packet, the exact case resume exists for, report as tampered. `record` refuses to reseal over an
  already-divergent file rather than laundering the rewrite into a fresh digest, enumeration covers
  everything that is not a directory (a `-type f` walk could not see symlinks, so an all-symlink
  packet sealed zero files and then verified "intact"), and a symlink packet entry is refused
  outright rather than digested — the whole class, not just escaping links, because resolving a
  target portably would need GNU-only `readlink -f` and a packet never legitimately holds a link.
  Exit 0 states its own limit: nothing changed *since the seal*, which is not a claim the content
  is pristine.

### Fixed

- **The resume rule no longer breaks on a multi-target audit (#1808).** It re-derived the packet
  path by re-sanitizing the raw argument into a single expected slug, while the packet model, slug
  rule, and `argument-hint` were all singular. A request like "audit the plugins we used" resolves
  to several components, the run reasonably allocates one conforming packet per component, and the
  re-derived slug then matches **no directory at all** — so a post-compaction resume concludes the
  findings are missing from a run that produced six packets. Fan-out is now documented behaviour
  rather than an undocumented improvisation: the argument resolves to a LIST of targets, each gets
  its own packet under a slug derived from the **resolved component identity** (capped at 64
  characters, which also retires the Windows 260-character path hazard), and resume
  **enumerates** the session directory instead of deriving one slug. Enumeration reads no pointer,
  so unlike a name taken from packet content it cannot be *steered* by audited content — but it is
  not unconditionally trustworthy: the `auditor` holds Write, so an auditor subverted by an
  injection could plant a sibling slug that enumeration would pick up. Resume therefore reports the
  enumerated slug set rather than silently consuming it. Enumeration is also **grouped by run**: a
  session directory accumulates every audit that session ran, so taking every slug and
  independently picking each one's latest nonce mixed runs — audit A, later audit only B, and
  resuming B also loaded A's packet and carried its stale findings into the union contract and the
  emit. The run nonce is the discriminator, now pinned as one value computed once at run start and
  reused for every target packet, and advanced when the name is already taken so two runs in the
  same second cannot share one (re-deriving it per target would straddle a second boundary and
  split one run into several; sharing it would merge two). Resume groups the enumerated pairs by
  nonce — one nonce, one run — and never unions across groups. Selection is deliberately *not* a
  bare greatest-nonce rule: a later run that died in step 1 leaves a findings-less packet whose
  nonce outsorts everything, and picking on that alone would report an earlier run's complete
  sealed packets as missing. Every group is reported with its slug set and whether it holds
  grounded findings, the selected group is named along with the reason, and an unselected group is
  set aside visibly rather than reduced to a count — which is also what keeps a planted slug under
  an attacker-chosen high nonce from silently becoming the whole selection.
- **Packet files are declared write-once, and their mutation by sibling hooks is now detectable
  (#1808).** The guardrail section anticipated a write being *rejected*; the likelier event is the
  write succeeding and the content being rewritten underneath it. `PostToolUse` runs after a tool
  call succeeds, may rewrite content, and matches on **tool name**
  (<https://code.claude.com/docs/en/hooks>, fetched 2026-07-31) — so every sibling plugin
  registering `Write|Edit` post-processes every packet write, and two such formatters ship in this
  fleet. Observed damage hit verbatim quotations and code-span identifiers, the two content
  classes a packet exists to preserve, and it is silent with respect to the artifact: the notice
  goes to the *session*, the very context the packet outlives. Three rules now apply — write once
  (a correction is a new file, since the autocorrect has no memory and reverts hand-repairs),
  read back immediately after each write, and seal. The scope is stated honestly: the digest
  cannot detect the FIRST in-place rewrite (any later tool call necessarily hashes the
  already-rewritten bytes) — the read-back is that detector — but it turns every divergence after
  the seal from silent into reported. Three tempting escapes are recorded as disproved rather than
  left to be re-proposed: a non-`.md` extension, a `typos`/`markdownlint` opt-out, and a shell
  redirect that dodges the matcher (a hook bypass the fleet's own guardrails block by design).
- **The `${CLAUDE_PLUGIN_DATA}` harness claim was false (#1808).** The packet section asserted the
  token "does NOT substitute in skill markdown"; the plugins reference puts skill and agent content
  in the "anywhere the placeholder appears" row alongside hook and monitor commands
  (<https://code.claude.com/docs/en/plugins-reference>, fetched 2026-07-31). Corrected in place —
  the prescribed manual derivation was itself doc-correct and is kept as the fallback. Fixed here
  rather than deferred because this release's script invocations use `${CLAUDE_PLUGIN_ROOT}` in the
  same files, which the false claim would have told a reader could not work.
- **The backstop persist seals last, after the provenance write (#1808).** Step 3's
  both-writes-refused path sealed immediately after writing the recovered findings and only then
  created `evidence-<n>.md`, so following it literally left the provenance file written past the
  last seal — and the resume rule's mandatory verify then reported `UNSEALED` (exit 3) on *every*
  backstop-recovered packet. The packet class whose provenance most needs to be trustworthy was the
  one class that always arrived partly unsealed. The step now writes the findings, reads them back,
  records the provenance, and seals **once, after every write the step makes**, matching write-once
  rule 3's "when a step's packet writes are complete".
- **The `auditor` enumerates `evidence*.md` instead of assuming `evidence.md` (#1808).** Real
  packets carry supplementary `evidence-<n>.md` files — and the write-once rule above makes more of
  them — so a read of one assumed name that fails is not evidence the packet is empty.

## [0.3.1] - 2026-07-30

### Fixed

- **The dispatching session now verifies the packet's grounded findings landed, and persists them
  when the `auditor` could not (#1674).** 0.2.0 moved the packet filename out of the report-name
  class and 0.2.1 taught the resume rule the fallback name, but neither closed the case where
  *every* packet write is refused inside the subagent. The `auditor` was told to return its
  findings as text; nothing told the main session to catch them, so the compaction-surviving
  guarantee held only when the operator happened to re-persist the returned text by hand — an
  undocumented step. Step 3 now opens with a persist-check: probe the Resume rule's closed set of
  grounded-findings basenames, and on the `auditor`'s documented both-names-refused return, write
  the returned findings verbatim into the packet (`audit-notes.md`, falling back to
  `audit-data.md`) before presenting or advancing. This is a backstop, not a relocation — the
  dispatching session is itself a subagent under a loop lane, so the filename rule remains the
  primary defense.
- **A refused main-thread write is now a named blocker, not a shrug.** When the dispatching
  session's own writes are refused too, step 3 reproduces the findings inline and stops before the
  contract lock, rather than locking a contract over findings that exist nowhere durable — the
  same ungrounded contract the resume rule already refuses to carry.
- **The both-names-refused return got a machine-visible marker.** `agents/auditor.md` now requires
  that return to open with the literal ASCII line `PACKET WRITE REFUSED: full findings inline` and to
  carry the COMPLETE findings in place of the summary form, since a refusal mentioned in passing
  reads as a successful run with a caveat and a one-line-per-finding summary is not a ledger the
  main session can persist on the agent's behalf. Step 3 correspondingly refuses to write a
  summary into the packet under a closed-set name: presence of one of those names is precisely
  what tells a resumed session the grounded findings exist, so doing so would forge the ledger
  instead of recovering it.
- **Backstop-persisted findings carry their provenance.** The backstop write keys on a
  marker-string match with no independent confirmation a write was attempted and refused, so step
  3 records the backstop path in `evidence.md`, and step 4's unattended contract lock marks each
  such finding `backstop-persisted: unverified` rather than extending the severities-stand-as-is
  rule to the least-verified route into the packet.

## [0.3.0] - 2026-07-26

### Changed

- **Context-gate migrated to the context-guard reader contract's v2 band shape (#1475).** The
  gate now understands the token shape: `zones.json` validity is evaluated per shape (percentage
  keys as before; optional `token_bands` with per-window-class rows — absent is valid
  zero-config), the inlined fallback floor carries both the percentage bands (50/75) and the
  window-class token bands (200k class 100000/160000, 1M class 200000/400000, over occupancy =
  `total_input_tokens + total_output_tokens`), and the reader contract's combination rule is
  inlined verbatim: when both shapes are computable, the worse zone wins (conservative-min); when
  only one is computable, it stands alone; when neither is, the zone is unknown. This removes the
  documented split-brain hazard where a token-shape `zones.json` would have been rejected
  wholesale in favor of the stale inlined 50/75 table. The compaction override now also
  recognizes context-guard's new evidence-degraded marker
  (`~/.claude/context-guard/context/<session_id>.compacted`). The inlined token shape also carries
  the contract's version floor: it is computable only when the snapshot's `cli_version` is present,
  purely numeric dotted, and >= 2.1.132, because before that release the token fields were
  cumulative session totals and a cumulative value below the window size is indistinguishable from
  a real occupancy.

### Added

- **`scripts/zones-inline-drift.test.sh`** — the consumer-lane drift check the reader contract's
  "Inline-floor ownership" rule has always named but nothing implemented: asserts every
  load-bearing inlined floor phrase (staleness window, snapshot/zones/marker paths, both band
  shapes, the token-shape version floor, the combination-rule sentence) appears in BOTH this skill
  and the context-guard reader contract after normalization. Runs in the repo's plugin-gate CI job via the shared
  `*.test.sh` discovery; SKIPs cleanly in an installed plugin cache where the sibling contract
  file is unreachable.

## [0.2.2] - 2026-07-29

### Changed

- **`auditor` agent pins `effort: high`.** The auditor is a consequential-verdict lane; the pin
  keeps its audits from silently degrading when the dispatching session runs at a lowered effort
  level, per the marketplace effort-tier rules (PLUGIN-PHILOSOPHY.md, "Effort tiers").

## [0.2.1] - 2026-07-26

### Fixed

- **The compaction resume rule could not find the packet's findings file after the rename fallback
  fired (#1592).** 0.2.0 documented a fallback that writes the grounded findings to `audit-data.md`
  when the subagent report-file guardrail also rejects `audit-notes.md`, but the resume rule
  accepted only `audit-notes.md` or a legacy `findings.md`. A compaction after that fallback
  therefore dropped the findings file from the deterministic recovery path — the exact loss the
  packet exists to prevent — even though the substitution had been recorded in `evidence.md`.

  The rule now probes a **closed set** of basenames — `audit-notes.md`, `audit-data.md`, legacy
  `findings.md` — and the rename fallback may only choose from that set, so resume never needs a
  pointer telling it what to open. Raised in review on #1569; the fix missed that PR's merge.

  Two further review findings on the fix itself shaped the final design:

  - **The findings pointer must not come from `evidence.md` (P1, prompt injection).** An earlier
    revision had resume read the filename recorded there. `evidence.md` records what the audited
    component printed, which is DATA under audit per the skill's own standing untrusted-content
    posture — a forged substitution record could have redirected a post-compaction resume onto an
    attacker-chosen file and suppressed or replaced the real findings. Closing the name set removes
    the pointer, and with it the injection surface; the `evidence.md` note is now explicitly a
    courtesy for human readers, not an input.
  - **A missing findings file must be surfaced, not shrugged off (P2).** An earlier revision told a
    resumed session to treat every non-empty packet file as in-scope rather than concluding the
    findings were gone — which would let an interrupted auditor (dispatch died before persisting, or
    every write refused) flow into contract lock and emit with no grounded findings at all. Every
    initialized packet already holds a non-empty `evidence.md`, so "some file exists" was never
    evidence that findings do. Resume now stops and re-runs step 2 when none of the closed set is
    present.

## [0.2.0] - 2026-07-26

### Changed

- **The evidence packet's grounded-findings file is renamed `findings.md` → `audit-notes.md`
  (#1565).** Some subagent contexts run a Write-tool guardrail that rejects report-shaped
  *filenames* — "Subagents should return findings as text, not write report files" — and the
  packet write is refused for what the file is called, not what it contains or where it goes. Both
  writers in this workflow can sit inside such a context: the `auditor` of step 2 is a subagent by
  construction, and the dispatching session is one whenever the skill is invoked from a loop lane
  or another agent, so "let the main thread write it" is not a fallback that reliably exists. The
  rename was verified empirically this session: `findings.md` and `analysis.md` were both rejected
  from a subagent, while byte-identical content written as `audit-notes.md`, `audit-packet-data.md`
  and `packet-findings.json` all succeeded — the guardrail keys on the filename alone. The
  compaction resume rule now reads `audit-notes.md` **or** a legacy `findings.md`, so packets
  already on disk stay recoverable. The guardrail is documented in the skill as **observed
  harness behavior, not documented behavior**: it appears on no official page (sub-agents
  reference checked 2026-07-26, <https://code.claude.com/docs/en/sub-agents>, which documents
  write restriction only at tool-access granularity via `disallowedTools`), so a filename outside
  the report/summary/findings/analysis class is the primary defense and a second rename is the
  documented backstop.

### Added

- **Step 4 (contract lock) gains an autonomous-invocation clause (#1566).** The step was
  written as unconditionally interactive with no branch for an unattended dispatch, so every
  loop-lane invocation re-improvised its own fallback. It now performs the step from derived
  answers rather than skipping it, using the same two rules `/work-items:setup` applies on its
  unattended path — a decision whose recommended answer is safe resolves to it silently and is
  recorded as auto-resolved; a decision with no safe default is reported as a named blocker rather
  than guessed — with a per-decision table for scope, severity calibration, named assumptions, and
  emit target. `contract.md` records `autonomous: true` so a later reader can tell which answers
  came from a human.

  The emit-target row does **not** block when the ladder's rungs 1–2 both miss. An earlier revision
  of this entry called an unresolved target a blocker, which contradicted step 6 — that step sends
  every unattended run to rung 4 regardless of whether 1–2 resolved, and `reference/config.md`
  names "no repo" as one of rung 4's own entry conditions. Blocking would have stranded exactly the
  targetless runs rung 4 exists for: a plugin loaded with `--plugin-dir` has no marketplace
  registration to infer from and no tracked config, and is the case most likely to be audited
  unattended. The row now records which rung would have been taken, or that none resolved, and the
  emit lands on rung 4 either way.
- **Step 6 (egress gate) gains an autonomous-invocation clause that does NOT relax the gate
  (#1566).** The originating report proposed treating step 6 as having "the identical issue" as
  step 4; that half is **refuted**. Step 4 has no external side effect, so deriving its answers is
  safe; step 6's draft+confirm surface is the recorded override that lets a read-only `audit` verb
  mutate at all, and an absent confirmer is not an implicit confirmation. An unattended run
  therefore falls to sink-ladder rung 4 unconditionally — the complete item is written locally as
  `item.md` and the run reports the rung and identity it would have used, then stops. No auto-file
  mode is introduced: rung 4 was already the one path the gate does not cover, because it produces
  no external effect.
- Two evals covering both clauses, including an anti-pattern eval asserting that an unattended
  invocation must not emit externally.

## [0.1.2] - 2026-07-25

### Changed

- `skills/audit` step 2 no longer justifies its dispatch by what a fork inherits. Three successive
  rationales for rejecting `context: fork` were each defeated in review, so the requirement is now
  stated as an invariant the step must satisfy: a context that carries the evidence packet but
  **not** this session's conversation history or prior reasoning, plus a named dispatch target that
  makes the dispatch site auditable. The `auditor` agent supplies both — and the packet crossing the
  boundary is deliberate, since the agent reads it as ground truth. The framing holds either way on
  #1258, which reports the Agent tool's `fork` subagent type not inheriting the conversation in
  practice, against its documentation.

## [0.1.1] - 2026-07-24

### Fixed

- `skills/audit` step 2 no longer claims a fork "would inherit this session's degraded history".
  That is false for a skill's `context: fork` frontmatter, which starts the subagent with no
  conversation history; conversation inheritance belongs to the Agent tool's separate `fork`
  subagent type. The step now names that type explicitly and also forbids running inline.
- `skills/audit/references/component-types/skill.md` composition lens no longer asserts that a
  forked sub-skill "loses history" as a defect; it asks whether the inline-vs-`context: fork`
  choice matches what the step needs, and names the mechanism.
- `agents/auditor.md` says why it has no conversation history — it is a named subagent rather than
  a conversation fork — instead of leaving "by design" for the reader to interpret.

## [0.1.0] - 2026-07-24

### Added

- `skills/audit` — six-step post-use component audit (`/plugin-quality:audit
  <plugin>[:<component>]`): evidence capture into a compaction-proof packet, map+ground in the
  fresh `auditor` subagent with per-topic fresh-docs verification, blindspot + candidates,
  interactive contract lock, presence-gated review seams, sink emit behind the draft+confirm
  egress gate (acting `gh` account surfaced). Context-gate over context-guard snapshots with a
  per-zone decision table; conservative on unknown. Evals incl. conservative-dispatch and
  prompt-injection anti-pattern cases.
- `agents/auditor.md` — fresh-context audit specialist (steps 2–3) with an honest Bash grant and
  the standing untrusted-content instruction.
- `skills/audit/references/` — recurring-concerns checklist + five component-type lenses, ported
  from the retiring machine-local skill and generalized.
- `reference/config.md` — `.claude/plugin-quality.md` cascade surface (per-key override), sink
  resolution ladder, markdown item schema (byte-compatible with the cross-terminal handoff inbox
  contract), work-items seam boundary.
- `skills/setup` — `check` (gh + acting account, context-guard seam → dispatch mode, config
  provenance) / `apply` (tracked config only), with evals.
