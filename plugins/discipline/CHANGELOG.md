# Changelog

All notable changes to the `discipline` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

Entries below `0.9.0` were released under the plugin's former name, `re-anchor`.

## [0.12.18]

### Changed

- **`setup` step 6 fork-mode framing matches current docs.** Fork subagents are on by default in interactive sessions on Claude Code >= v2.1.232 (off by default in non-interactive `-p` and Agent SDK sessions; `CLAUDE_CODE_FORK_SUBAGENT` overrides either way, re-checked 2026-08-26) — the step no longer frames fork-spawning as needing explicit enabling. From the repo-wide derivability/point-dont-copy audit (PR #3387).

## [0.12.17]

### Changed

- **`sweep-all`'s preflight and batched pass move to spokes.** The two sections were 300 of the
  body's 469 lines and neither executes in session-start digest mode, which is the default and the
  cheap one. They are now `skills/sweep-all/reference/inheritance-preflight.md` and
  `reference/batched-pass.md`, each cited with the condition that sends a reader there. The
  member-human-gates carve-out stays in the body, where a batched run cannot miss it. Docs-hygiene
  sweep, L2-progressive-disclosure.

## [0.12.16]

### Changed

- **Six README parentheticals repaired.** Each ended a sentence inside itself, leaving a fragment on
  one side of the period: the simpler-code convention gloss, both divergence classes in
  `recheck-against-upstream`, the `reason-dont-recite` cross-reference, the
  `research_deep_verification` option row, and the `setup check` read-only note. Docs-hygiene sweep,
  L8-write-for-humans.
- **The lead paragraph drops its own scope-decision provenance.** How this plugin's scope came to be
  widened is a changelog fact and is already recorded as one here. The widened scope itself stays.
  Docs-hygiene sweep, L8-write-for-humans.

## [0.12.15]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.12.14]

### Changed

- **Instruction-surface de-slop (#2891, shard 5).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.12.13]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.12.12]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). This skill is
  check-only — it has no `apply` action — so `check` gained a closing step telling the reader to
  rerun it and report the observed value, rather than asserting an unobserved change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.12.11]

### Changed

- **Corrector-to-corrector routes name the Skill tool (#3002).** `do-your-research-deep` and
  `recheck-against-upstream-deep`'s "use the lighter sibling" bullets, plus the exact reciprocal
  that was missed the first time — `do-your-research`'s "Escalating to a verification fan-out"
  route up to `/discipline:do-your-research-deep`; `pick-for-the-problem`'s current-research
  route to `/discovery:research`; `mind-your-maxims`'
  Delegations section (one preamble line covering both axes); `reuse-or-replace`'s two
  evidence/rationale routes; `scrutinize-dont-coast`'s `/review:quality-gate` route;
  `use-your-skills`' `/skill-quality:check` and `/claude-config:audit` routes. Wording only —
  the axis boundaries, presence gates, and prose-degradation fallbacks are unchanged.

## [0.12.10]

### Changed

- **`reason-dont-recite` disambiguates its shared trigger phrase.** It carries the
  literal trigger `'why is it this way'`, which the new `/discovery:trace-intent`
  serves from the opposite direction: this skill challenges whether a convention
  should STILL hold and re-derives it from first principles, while that one recovers
  the original reasoning from the historical record. The two are inverse postures on
  the same words — one treats absent rationale as a finding, the other goes and looks
  for it — so the description now names the boundary and routes across it.

  The clause is presence-gated with a documented fallback (read the record directly)
  rather than an unguarded cross-plugin reference, and it is strictly **additive**:
  every pre-existing single-quoted trigger is preserved byte-identically, because the
  trigger-preservation check treats a cross-plugin move as a dropped trigger and an
  auto-invocation regression.

## [0.12.9]

### Changed

- **`sweep-all` membership / `batch_promote` contract (#2738).** Membership stays
  glob + colocated tier metadata — the runbook no longer names never-tier members
  inline as if they were the member set. `batch_promote` is situational-only: a
  never-tier, core, or unknown promote entry draws a visible warning and is not
  promoted (`setup check` matches). Overlay net-effect reporting must surface
  those warnings.

### Added

- **`wait-what` eval suite (#2738).** Five cases covering missing-context restore,
  ASD-STE100 register, project ubiquitous language, re-ground-not-compress, and
  no-glossary silent no-op — closing the gap where the other sixteen skills shipped
  evals and this one did not.

## [0.12.8]

### Changed

- **Plugin-quality audit fixes.** (1) The manifest description's closed "two further species"
  enumeration had already drifted (it omitted `setup`); it is now open phrasing with marked
  examples — the exact pin `point-dont-copy` itself prescribes. (2) `scrutinize-dont-coast`
  declared two deltas to the shared loop while making three; the fresh-context relocation of the
  loop's step 2 is now enumerated as the third. It also gains a parenthetical distinguishing the
  Agent-tool fork (inherits conversation) from a skill's `context: fork` (isolated) — the docs
  overload the word. (3) Sibling boundaries were declared one-way; `reason-dont-recite` now names
  the reciprocal carve-outs (recheck-against-upstream, reuse-or-replace, pick-for-the-problem) and
  `pick-for-the-problem` names `reuse-or-replace`'s consistency axis, so a scope edit on either
  side has the other in view. (4) Method-doc step citations now carry the step's name alongside its
  number ("step 2, self-audit") across the correctors, so a future loop renumbering cannot
  silently invalidate them.

## [0.12.7]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.12.6]

### Fixed

- **`sweep-all`: binding degrade path for fork-unavailable environments (#1681).**
  When conversation-inheriting forks cannot run, the skill now fails closed and
  loud: the report's first line is the exact token `SWEEP-ALL: DEGRADED
  (fork-unavailable)`, followed by an explicit statement that no audits ran and
  no corrections were applied, then the session-start posture digest only. Next
  actions name direct per-corrector invocation and re-run after fork mode is
  available. `CLAUDE_CODE_FORK_SUBAGENT=0` short-circuits before the canary;
  unset/`1` still dispatch the inheritance-proof canary. No sequential inline
  audit+correct fallback — the batch does not substitute a main-thread pass.

## [0.12.5]

### Fixed

- Surface fork dependency in sweep-all listing description.

## [0.12.4]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `skills/use-your-skills/SKILL.md` — the skill listing carrying every skill name always and
    shortening descriptions to fit its budget, with the body loading only on invocation
    (skills reference); and, from the sub-agents reference, that without the `skills` field a
    subagent "can still discover and invoke project, user, and plugin skills through the Skill
    tool during execution" — the premise behind naming skills in a delegation prompt.

## [0.12.3]

### Changed

- **`skills/sweep-all`: the mirror basis is retired for a primary one — the trigger 0.12.2 wrote
  fired, and this honors it.** 0.12.2 could not read `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` from
  `env-vars` (three fetches truncated before the `CLAUDE_CODE_MAX_*` range), so it sourced the row
  from a same-day verbatim mirror, labelled it one rung below a primary read, and stated its own
  retirement condition: "any env-vars fetch that reaches the `CLAUDE_CODE_MAX_*` range, which
  retires the mirror basis for a primary one". A verbatim end-to-end read of the page on 2026-08-10
  through the new [`.md` fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route)
  reached it. The row is **unchanged** — "Maximum number of read-only tools and subagents that can
  execute in parallel (default: 10)" — so no cited value moves; what changes is the standing of the
  citation, from mirror-corroborated to primary, which is the whole point of writing a retirement
  condition down instead of leaving the rung permanent.
- **`skills/sweep-all`: four more env-vars rows this skill leans on are now quoted from the same
  read.** `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (removed in v2.1.224, previously default 200),
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20), `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` (the
  `run_in_background` parameter on Bash and subagent tools), and `CLAUDE_CODE_FORK_SUBAGENT`
  ("overriding any server-side rollout") each match the way the preflight cites it. They were being
  carried on reads the truncation problem had made unrepeatable; now one fetch covers all five and
  the note says which. The recheck trigger widens to match the widened basis, and the currency claim
  is capped at the fetch date because upstream publishes no per-page content date.

## [0.12.2]

### Fixed

- **`skills/sweep-all`: the open `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` currency question is closed
  (#2176).** 0.12.1 landed the v2.1.224 cap removal with an honest in-place marker saying the
  concurrency variable beside it was carried forward from a 2026-07-29 read, not re-verified, and
  "tracked as its own item". That item is now closed, so the marker pointed at nothing. The row reads
  exactly as cited — "Maximum number of read-only tools and subagents that can execute in parallel
  (default: 10)" — so the claim is current, not drifted. The marker is replaced rather than deleted,
  because the route matters: `env-vars` truncated before the `MAX` range for a **third** time, so this
  was read from a same-day verbatim mirror of the docs
  ([`ericbuess/claude-code-docs` `docs/env-vars.md`](https://github.com/ericbuess/claude-code-docs/blob/main/docs/env-vars.md),
  synced 2026-08-10), whose freshness is corroborated by its carrying the same v2.1.224 cap removal.
  That is strong evidence one rung below a primary read, and the citation now says so instead of
  either overclaiming a primary fetch or leaving a closed question looking open. The replacement
  carries the [upstream-drift convention](../../docs/conventions/upstream-drift/README.md)'s fourth
  part, which the marker it replaces did not need and the bare stamp would have dropped: a recheck
  trigger — a release note naming tool-use concurrency, parallel tool execution, or the variable, or
  any `env-vars` fetch that reaches the `CLAUDE_CODE_MAX_*` range, which retires the mirror basis for
  a primary one.

## [0.12.1]

### Fixed

- **`sweep-all` no longer counts dispatches against a per-session cap that was removed.** Its
  budget reasoning had every Agent-tool subagent counting against both
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20, still current) and
  `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (documented default 200). The second was removed in
  v2.1.220–v2.1.224 ([2026-w32](https://code.claude.com/docs/en/whats-new/2026-w32), verified
  2026-08-10) and is gone from the sub-agents page along with its variable. The concurrency limit —
  the one the paragraph calls "the hard one" — is unchanged, so the dispatch conclusion stands; only
  the second constraint has since been removed. It was accurate when written (documented default
  200, v2.1.212+) and went stale under the platform, which is the failure mode a dated verification
  stamp exists to make findable.
- **The `env-vars` citation is restored, and one variable is now marked as unverified.** Re-sourcing
  the cap removal had swapped that link out, which left the paragraph's *first* claim —
  `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`, documented default 10 — with no source at all. The link is
  back alongside the new one. That variable itself could **not** be re-verified: two `env-vars`
  fetches truncated before its alphabetical range, and the sub-agents page names only the concurrency
  and depth limits. That is not evidence of removal — the same truncated fetch returned ABSENT for
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, which is quoted verbatim elsewhere — so the claim is marked
  in place as carried forward from the 2026-07-29 read and not re-verified, with its currency tracked
  as an open item rather than left looking fresh.

## [0.12.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.11.0]

### Added

- **`wait-what` — a one-shot, user-invoked-only communication repair** (a declared
  further species beside `sweep-all`, not a corrector). Type `/discipline:wait-what`
  when the model's last message did not land: it re-pitches — backs up as far as
  needed, adds the context the reader was missing, talks in ASD-STE100 Simplified
  Technical English (short sentences, one meaning per word, technical terms exact),
  and uses the project's ubiquitous language, read from the nearest domain glossary
  or context map per the consuming project's own convention (degrading silently when
  none exists). `disable-model-invocation: true` is load-bearing — only the human
  can detect that a message did not land — and the skill carries no
  `discipline-batch` tier, so a sweep never fires it. The body is deliberately
  small: a skill that fights unclear output fails by growing. Ported from
  mattpocock/skills v1.2 `wait-what` (see `docs/upstream/mattpocock-skills.md` for
  provenance, the naming-exception record, and the on-demand-beats-passive evidence
  behind the shape).

## [0.10.2]

### Changed

- **`script-the-deterministic-work` and `reuse-or-replace`: listing descriptions tightened
  (1,054 → 872 and 1,022 → 836 chars)** — trimmed the explanatory prose from each frontmatter
  `description` toward the shared skill-listing budget (claude-code-plugins#2022, option 2).
  Every single-quoted trigger phrase is preserved verbatim (skill-quality check 3); both
  correctors' disciplines and not-for boundaries are unchanged in the bodies.

## [0.10.1]

### Fixed

- **`do-your-research` claimed triggers its body did not support (`#1269`).** The
  description routes "fact-check that" and "make sure that's right" to this tier,
  but the discipline asked only that a claim be checked "against an authoritative
  source" — no notion of source tier, independent corroboration, or recency
  appeared anywhere in the file. The bar someone reaches for most often was the
  one stated most weakly, while the real contract sat in the heavy tiers. The
  discipline now states that bar as three named dimensions — tier, independent
  corroboration, recency — and resolves what clears each one down the same
  ladder the method doc already uses: the consuming project's declared policy
  first, then the contract `/discovery:research` states where the `discovery`
  plugin is installed, then a floor this skill owns. The floor is the plugin's
  own baseline calibrated for the inline tier rather than a copy of a heavier
  tier's numbers, so a `discipline`-only install still knows what clears the
  bar instead of resolving it from a plugin that may not be present. Two
  matching audit triggers were added: a claim resting
  on one source or on corroborators sharing an upstream pool, and a
  version/default/flag/API claim checked against a source predating the current
  release. The clean-audit eval fixture, written against the weaker bar,
  now establishes corroboration and recency so conforming to the new contract
  and returning "nothing to correct" stay the same answer.
- **The skills split on depth but never named direction.** `do-your-research` and
  `do-your-research-deep` are an inline-versus-fan-out pair, which left the
  preventive/detective axis — grounding a claim before it is asserted, versus
  checking claims already asserted — unnamed even though the two have different
  trigger moments and different costs when skipped. Both directions are now
  stated in `do-your-research`, with depth reaffirmed as the skill boundary.
  Deliberately not a split: neither tier owns one direction.
  `do-your-research-deep` is unchanged and inherits this by its existing
  "no separate copy of the discipline here" pointer.

## [0.10.0]

### Fixed

- **`sweep-all`: the fork stop-rule was inert — nothing defined how to evaluate its guard
  (`#1621`).** The runbook said "if forks are unavailable, report that the inheriting audit
  fan-out cannot run and stop," but no part of the plugin defined how to determine that.
  A rule whose guard cannot be evaluated is inert, not merely under-specified: the path that
  actually ran was the blind one — non-inheriting subagents fabricating ledgers from their
  system prompt, merged at step 3 and **written to the working tree** at step 4. Observed, not
  hypothetical: a real full-batch run dispatched eight forks, all eight came back with no
  inherited conversation, and only two subagents' refusal to invent a ledger stopped eight
  fabrications from being merged.

  A **preflight** now runs before the fan-out, in two stages. Stage 1 is a zero-dispatch paired
  tool-schema read, and it deliberately **never gates**: fork mode "removes the
  `run_in_background` parameter from the `Agent` tool"
  (<https://code.claude.com/docs/en/sub-agents>) while `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`
  removes it from "Bash and subagent tools" (<https://code.claude.com/docs/en/env-vars>), so
  the pair discriminates those two causes — but the docs tie removal to the env-var path only
  and say nothing about the server-side rollout, so no branch is conclusive and shipping it as
  a gate would silently downgrade a working sweep. Stage 2 is the decider: ONE proof-only canary
  fork, dispatched alone ahead of the first wave, carrying no corrector and returning no ledger.
  Folding the canary into a member's real audit would look free and is not — a fork inherits
  everything the session holds when it spawns, so a member ledger returned before wave 1 would
  sit in every later fork's context and anchor its audit, breaking the independence the dedup
  step relies on. The guard costs one extra fork, and the skill says so.
  The runbook specifies the proof question's four *properties* — the answer exists only in
  conversation history, the prompt neither contains nor paraphrases it, it keys on ordinary
  inherited material, and it cannot be guessed — rather than a fixed question, and the main
  thread **fails closed**: absent, ambiguous, or unverifiable proof counts as not inherited. A
  conversation too thin to supply such a detail does not lose its audit — the main thread mints
  a high-entropy value into the transcript before the canary spawns and asks for it back.

- **`sweep-all`: the degraded mode existed only in `setup`, a file a sweep never loads
  (`#1621`).** `setup` declared "where it is off, only the session-start posture digest runs"
  while `sweep-all` declared "report and stop" — two contracts for one condition, and the
  better one where the sweep could not read it, so the operator got nothing at all. The
  degraded pass now lives in `sweep-all` (posture digest, the reason and the signal that
  established it, and the direct-invocation path), and `setup` points at it instead of
  restating it. This **refutes** the framing the audit was commissioned with: the brief asserted
  no degraded mode existed and proposed a three-rung fallback ladder — a degraded mode was
  already the plugin's declared position, and the ladder (audits weaker than the ones the skill
  halts to avoid) is deliberately **not** built.

- **`sweep-all`: "make NO writes" was presented as though the harness enforced it (`#1622`).**
  It cannot. A named subagent's tools can be narrowed with `tools` / `disallowedTools`; forks
  "skip both filters and receive the main conversation's exact tool pool"
  (<https://code.claude.com/docs/en/sub-agents>), so every audit fork holds Write, Edit, and
  Bash and is only *asked* not to use them — and the declared delta's safety argument rested on
  that property. The skill now says so plainly, and treats a fork that wrote as untrusted output
  to stop on rather than correct on top of. Detecting that a fork wrote is advisory here and
  tracked as its own work in `#1631`: a prose-specified before/after digest protocol drew a
  correct review finding in three consecutive rounds, which is the signal that deterministic
  sub-work belongs in a script the skill calls — this plugin's own
  `script-the-deterministic-work` position — reusing the repository's existing state-digest
  contract rather than standing up a second parallel way of digesting a working tree.

  `isolation: "worktree"` was considered as containment and **rejected**, with the reasoning
  recorded in the skill so it is not re-proposed: a git worktree is created from a commit, so
  isolated forks would not see the uncommitted work in flight — usually the very thing under
  audit — and isolation would not bound a write addressed by an absolute path, of which
  inherited history is full. It trades real audit fidelity for partial containment.

- **`sweep-all`: the wave cap imported a number calibrated for a different kind of subagent, and
  the shared budget was unmodeled (`#1623`).** "Like the `-deep` siblings" resolved to "roughly
  a dozen", which is sized for cheap fresh-context subagents and exceeds
  `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` (documented default 10); it also silently dropped those
  siblings' mid-run checkpointing.

  The replacement is not a smaller cap but a different default: **prefer ONE wave.** Splitting is
  what breaks the ledger independence step 3's dedup assumes — a fork inherits everything the
  session holds at spawn, so wave 2 reads wave 1's findings — and the `-deep` siblings carry no
  such invariant, which is why their number never belonged here. The two documented limits are
  also distinguished, which the old text conflated: `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`
  (default 10) caps how many run at once, not how many you dispatch, while
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20) is the hard spawn failure — so even a
  fully-admitted set dispatches in one wave in a quiet session. Membership resolution decides
  scope and concurrency decides only timing: a relevant corrector is never dropped to fit a
  budget; the pass waits for capacity. `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (default 200) is
  modeled too, and per-wave checkpointing is restored for the split fallback that needs it.

- **`sweep-all`: the retry rule never defined failure (`#1621`).** "Retry only a failed subset,
  once" did not cover the actual exposure — a fabricated ledger is not an errored dispatch.
  Failure now explicitly includes a ledger returned without verified inheritance proof.

### Changed

- **`sweep-all`: the undocumented fork-off fallback is now labelled as an observation.** The
  runbook asserted that requesting the `fork` type with fork mode off "falls back to a fresh
  general-purpose subagent" as though it were documented harness behavior. It appears on no
  current official page. It is now flagged observed-not-documented, and the preflight no longer
  depends on it — it proves inheritance positively instead of predicting the shape of its
  absence. (Asserting undocumented behavior as fact is precisely what this plugin's flagship
  corrector exists to catch.)

### Added

- **`sweep-all` evals: two entries for paths every existing eval assumed away** — the
  failed-canary degrade, and the fork tool pool being verified rather than enforced.

## [0.9.0]

### Changed

- **Renamed the plugin `re-anchor` -> `discipline`; every skill moves from
  `/re-anchor:*` to `/discipline:*`.** Three defects in the old name, each verified rather
  than asserted. (1) It was a bare verb — the sole outlier among 60 sibling plugins, all of
  which are nouns or noun-phrases. (2) The `re-` prefix presumes a prior anchoring, but the
  shared method's documented conversation-start case is a *first* posture-set with nothing
  yet to re-anchor. (3) "Anchoring" is the cognitive-bias term of art — the plugin was named
  after a bias `reason-dont-recite` exists to fight.

  `discipline` is the word the plugin already used for itself 189 times ("a drift corrector
  for research discipline"), so the name is the authors' own revealed vocabulary rather than
  a coinage. Container/member word overlap (`/discipline:sweep-all`) is routine in this
  marketplace — `/planning:plan`, `/debugging:debug`, `/visualization:visualize`,
  `/work-items:work` all ship that shape.

  Candidates rejected on evidence: `steering` (fails the conversation-start case; collides
  with Codex "mid-turn steering" and ML "activation steering"), `calibration` (implies
  adjustment against a measurable reference with quantified error — this work is
  judgment-based, the same objection that rules out `invariants`), `salience` (accurate but
  not a word a reader reaches for first), `grounding` (slug already taken).

  **Migration, and its one manual step.** On Claude Code >= 2.1.193 the marketplace
  `renames` map is followed at session start: an enabled `re-anchor@<marketplace>`
  loads as `discipline` instead of failing `plugin-not-found`, and the old key is
  rewritten to the new one in the user, project, and local settings scopes for BOTH
  `enabledPlugins` and `pluginConfigs` — so configured `batch_exclude` / `batch_promote` /
  `batch_demote` / `research_deep_verification` values move across with no action. Two
  edges: managed and policy scopes are read-only to Claude Code and are not rewritten, and
  if `discipline@<marketplace>` already carries its own `pluginConfigs` entry the new
  id's values win and the old ones are dropped rather than merged. Below 2.1.193 nothing
  is lost — the rename simply does not migrate, and the old name reports
  `plugin-not-found`.

  What the map does NOT rewrite is any invocation stored outside settings. In a consuming
  repository's instruction files, an agent prompt, a saved workflow, or automation,
  `/re-anchor:<skill>` must become `/discipline:<skill>` and `/plugin configure re-anchor`
  must become `/plugin configure discipline` by hand.

- **Renamed `sweep-all-disciplines` -> `sweep-all`.** Removes the one genuinely awkward
  pairing the plugin rename introduced (`/discipline:sweep-all-disciplines`). This leaf
  rename has NO compatibility entry — the `renames` map keys plugins, not skills — so
  `/re-anchor:sweep-all-disciplines` becomes `/discipline:sweep-all` and any stored
  reference to the old skill name must be updated by hand.

## [0.8.0]

### Added

- **`sweep-all-disciplines`: an explicit dedup-by-root-cause step between collect and correct
  (`#1154`).** Distinct correctors routinely surface one underlying finding as separate ledger
  entries (observed in a real full-batch run: one recall-based claim flagged independently by
  `do-your-research`, `recheck-against-upstream`, and `mind-your-maxims`), and the main thread had
  to dedup by hand. The batched pass now names step 3 — group entries that share a root cause,
  carry the union of their evidence and, keyed by reporting corrector, the remedy that corrector
  asks for (a reporter→remedy mapping, so each remedy keeps its rank). Dedup collapses the
  re-analysis and re-reporting of one root cause,
  NOT the corrective work: a shared root cause can demand non-interchangeable remedies (retracting
  an unsupported claim satisfies the research reporters, but `mind-your-maxims` may still require a
  reader-facing uncertainty disclosure), so every reporter's remedy is still applied, each at its
  own rank. The merged finding is reported once with full attribution. Fork independence is
  unchanged and explicitly reaffirmed: the forks never share a ledger (that independence keeps each
  audit un-anchored), and the grouping is the single point where ledgers combine. The pass steps
  renumber 1–5 (fan out → collect → dedup → correct → report).

### Changed

- **Cost gotcha carries a real datapoint.** The "forks run at the parent model's cost" gotcha now
  records order-of-magnitude from a full-batch run — ~170K tokens per fork (inherited transcript),
  ~1.4M for an 8-in-scope pass in two waves of four — so the sweep is budgeted as a deliberate
  spend rather than a reflex.

## [0.7.0]

### Added

- **`fact-check` trigger routing** on both research correctors. `do-your-research`
  and `do-your-research-deep` now list `'fact-check'` / `'fact check this'` (and
  adjacent phrasing) in their descriptions, so the reflex phrase routes to the
  research discipline. Every prior trigger phrase is preserved.
- **`do-your-research-deep` step 1 is now a TYPED FULL INVENTORY.** It enumerates
  every claim the session rests on as a typed checklist — assumptions, asserted
  facts, concrete specifics, and load-bearing premises — not just the obviously
  load-bearing ones, so coverage is provable. The ledger reports one row per
  inventory item (no silent drops), each carrying verdict, source, **source tier**,
  **consensus count** (independent authoritative sources), and **recency** where the
  fact can go stale. Source tier and consensus resolve against the consuming
  project's own research discipline via the shared method's source-of-truth ladder;
  an internal assumption with no external referent is covered by an honest
  re-derived / needs-confirm verdict rather than a fabricated citation.
- **Configurable verification depth** for `do-your-research-deep` — the expensive
  tier by design. New `research_deep_verification` `userConfig` scalar (the plugin's
  fourth option): `tiered` (default — resolve trivial and non-load-bearing items
  inline, fan subagents out only over load-bearing ones) or `full` (subagent-verify
  every item). An invocation argument (`argument-hint: [tiered|full]`) overrides the
  configured default; an empty value, an unexpanded token, or an unrecognized string
  all fall back to `tiered` without erroring. Existing wave-throttle, failed-subset
  retry, and blind-subagent mechanics are unchanged.

### Changed

- **`setup` broadened from the posture-batch overlay to the whole re-anchor
  configuration surface.** It now also reports and validates
  `research_deep_verification` alongside the three `batch_*` overlay options,
  treating an unrecognized depth as a WARN that still resolves to `tiered`.

## [0.6.0]

### Added

- **`sweep-all-disciplines`** — a posture-batch runbook, the plugin's first
  **declared second species**: not a corrector (it re-anchors no discipline of
  its own) but a router that composes the correctors. It fans out a
  conversation-inheriting fork subagent per in-scope corrector for an
  audit-only pass (shared-loop steps 1–2, no writes), then applies the
  corrections once on the main thread in a fixed rank order (`use-your-skills`
  first, `tighten-your-output` last). At conversation start it instead reports
  a cheap posture digest from the listing and tier metadata, loading no
  corrector bodies. Recorded in the skill as a **declared delta** from the
  shared loop's per-corrector "correct forward now" step; member human-gates
  and the outward-artifact carve-out survive batching.
- **Colocated batch-tier metadata on every corrector.** Each corrector
  self-classifies in its own frontmatter `metadata:` block — `re-anchor-batch`
  (`core` / `situational` / `never`) plus `re-anchor-batch-rank` — so the
  runbook resolves membership and order by globbing and reading, never from a
  hand-maintained list; changing a shipped tier is a PR to that corrector.
  `core` runs every session, `situational` is relevance-gated, and `never`
  covers the `-deep` fan-out tiers plus `scrutinize-dont-coast` (its non-fork
  fresh-context pass and stop-to-remediate gate are incompatible with the
  autonomous fork fan-out).
- **`userConfig` overlay** (`batch_exclude` / `batch_promote` /
  `batch_demote`) — the plugin's first `userConfig` surface — adjusts batch
  membership without a PR.
- **`setup` skill** — a check-only `/re-anchor:setup` conforming to the setup
  contract's userConfig-only carve-out: it reports the effective batch overlay
  (treating an unexpanded `${user_config.…}` token as unset) and routes
  reconfiguration to the native `/plugin configure re-anchor` flow; it writes
  no config.

### Fixed

- README corrector table and per-skill detail now list `scrutinize-dont-coast`
  (added in 0.5.0), closing a 13-listed-versus-14-shipped drift.

## [0.5.1]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is
  installed (e.g. the OpenAI Codex plugin, invoked per its own docs), with the
  fresh-context same-vendor subagent as the stated fallback — presence-gated
  per the seam-phrasing convention.

## [0.5.0]

### Changed

- Shared method doc (`context/re-anchor-audit-correct.md`) now sanctions
  **declared step deltas**: a corrector may modify a loop step when its
  discipline demands it, provided the delta and its reason are stated in that
  skill's `SKILL.md`. Undeclared divergence remains a violation; the
  Non-negotiables are never overridable.

### Added

- **`scrutinize-dont-coast`** — a corrector for adversarial self-scrutiny. It re-anchors a
  *meta* discipline rather than a single content axis: don't coast on your own
  recent output — confidence that work is sound is not evidence that it is. The
  load-bearing adversarial re-examination is delegated to a fresh-context
  (non-fork) subagent blind to the reasoning that produced the output, satisfying
  the fresh-eyes rule that a same-context self-check cannot. It makes two
  deliberate deltas to the shared re-anchor loop, both documented in the skill:
  it **stops the trajectory first** (the failure mode is over-confident forward
  momentum) and **remediates *with* the user** instead of autonomously (the
  remedy for runaway momentum can't be more unilateral momentum). An optional
  focus scopes the pass without suppressing a serious out-of-focus flaw. Negative
  routing is explicit: pre-implementation plan stress-tests go to
  `/planning:devils-advocate`, review checkpoints to `/review:quality-gate`, and
  single-axis flaws to the sibling that owns them.

## [0.4.0]

### Added

- **`use-your-skills`** — a corrector for skill-use discipline. The skill
  listing (every skill's name and description) is in context so the fitting
  skill gets invoked instead of reinvented; this re-anchors the habit of
  scanning it, maps the conversation and task to the skills that fit, and
  invokes them. Because a fresh non-fork subagent does not inherit the parent's
  listing (it discovers skills on disk via the Skill tool), the skill's
  subagent guidance is to name the relevant skills in a delegation prompt and,
  for a discipline a custom subagent should always carry, recommend its
  `skills:` frontmatter preload. Session-behavior only: description quality
  routes to `/skill-quality:check` and machine-level listing-budget overflow to
  `/claude-config:audit`. A deterministic per-prompt `UserPromptSubmit` routing
  hook is deliberately deferred (trigger: audits repeatedly show a skill
  existed but its description never surfaced it, or skills repeatedly fail to
  fire).
- **`reuse-or-replace`** — a corrector for anti-fragmentation discipline.
  When an established way of doing something already exists, new work reuses it
  or openly replaces it (migrate the uses, record the decision) — it never
  silently stands up a second parallel way. The mandatory misconstrual
  guard states this is NOT straight conformity: replacing the established way
  is first-class when evidence backs an improvement or its rationale is missing,
  incumbency-only, or stale; the sin is the silent second way, not divergence.
  Divergence owes a recorded rationale proportional to blast radius (ADR/docs
  for durable, PR/commit for small); no recorded reason is the finding. Scope is
  the unlintable approach level (idioms, structure, naming shapes, error
  handling, doc formats, process); mechanical style stays with linters.
  Cross-references `reason-dont-recite` (evaluation-side) and carves itself out
  of `pick-for-the-problem` (tool/dependency selection).

### Changed

- **`script-the-deterministic-work`** — its audit now runs in both directions.
  Alongside hand-work that should have been scripted, it hunts an **existing**
  script or tool that over-reaches into judgement (a detect-then-judge flag
  consumed as the verdict, or reasoning-only work handed to a script), and
  corrects by **de-scripting** — demoting the flag back to a candidate and
  returning reasoning-only work to reasoning.
- **`do-your-research`** — description adds the `'evidence, not vibes'` trigger
  phrase; no behavior change.

## [0.3.3]

### Fixed

- `follow-our-standards` now states that its upstream shared-policy route
  **names and drafts** the standards change and routes it to the human,
  OFFERING to open the standards PR — it does not open that PR (or any
  outward artifact) without the user's explicit opt-in, mirroring the OFFER
  gate the sibling `recheck-against-upstream-deep` applies to its work-items
  routing. Closes the ambiguity in "named and routed" that, combined with
  the correct-forward mandate, an aggressive reading could take as licence
  to file a standards PR unprompted.
- The shared method's `correct forward now` step gains an outward-artifact
  carve-out, and a new Non-negotiable states the plugin-wide invariant that
  no corrector files an outward artifact (PR, issue, published review
  comment) without explicit opt-in — a documented guarantee for consume-only
  consumers. In-tree correction stays ungated.
- `reason-dont-recite` notes that the standards-disagreement route it hands
  to `follow-our-standards` drafts and proposes rather than files, for
  consistency with the gate above.

## [0.3.2]

### Fixed

- `tighten-your-output` now presence-gates its `compress` and `simplify`
  routes with a documented prose/in-thread fallback, per the seam-phrasing
  convention — closing the lone unguarded cross-plugin reference that the
  sibling correctors already guard.

## [0.3.1]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/claude-config:audit-automation-gaps`); behavior unchanged.

## [0.3.0]

### Added

- `/re-anchor:script-the-deterministic-work` — offload-the-deterministic
  discipline: purely deterministic sub-work (counting, diffing, sorting,
  transforming, matching, sweeping, arithmetic) gets a script that runs and
  returns real output, and the model reasons only afterward over that output.
  The tier boundary — deterministic (script it), detect-then-judge (script
  the detect half; the verdict stays judgement), reasoning-only (never
  script) — re-anchors the consuming org's enforceability-tiers convention;
  the in-task "script it now" application has no standards doc yet, so the
  skill flags that gap rather than inventing a rubric. Runs in both
  directions: analysis reasons over a script's output; generation emits a
  deterministic scaffold (PR body, issue, report, config boilerplate) from a
  script or native template so model output is reserved for the judgment
  slots. Distinct from a standing-automation capability: recurring checks
  route to a hook, this corrector owns the one-off, session-time script.

## [0.2.0]

### Added

- **Four state-and-selection correctors.** The plugin's scope widens from the
  work in flight to also cover the pre-existing state and choices a session
  trusts — existing state is not evidence of its own correctness. New skills,
  all sharing the plugin-scope re-anchor / audit / correct-forward method:
  - `/re-anchor:recheck-against-upstream` — existing state (config, code,
    docs, infra) is not proof it still matches upstream. Fetches the current
    official upstream docs for the surface in play and classifies each
    divergence: gap (no recorded rationale — deprecation and version drift
    called out here), deliberate divergence (rationale recorded — re-checked
    only for whether it still holds), or undocumented divergence (needs the
    human's call, routed to the repo's ADR/docs convention). Reports what was
    compared versus skipped; unverified conformance is not "clean".
  - `/re-anchor:recheck-against-upstream-deep` — the fan-out tier: fresh-context
    subagents compare a whole subsystem/framework/repo against upstream
    doc-by-doc, throttled in bounded waves, reporting an inline divergence
    ledger. Offers work-items routing for gap/undocumented findings when a
    work-item capability is installed (degrades to a prose offer); deliberate
    still-valid divergences stay report-only; checkpoints the partial ledger
    to a durable topic-memory slice mid-run when one exists. A sibling rather
    than a `deep` argument because the fan-out is a heavier execution tier
    (mirrors `/discovery:research-deep`).
  - `/re-anchor:pick-for-the-problem` — tool/library/framework/approach
    selection fitted to the problem, not reached for out of habit,
    availability, incumbency, or preconception. Define the problem first,
    survey the field, walk the native > authoritative > vetted-third-party
    ladder, and price every dependency's coupling (abandonment, pricing,
    license, security, exit cost) at adoption time; building what already
    exists is a finding. Routes a load-bearing evaluation to a research
    capability rather than a verdict from memory. A deep dependency-inventory
    variant is deliberately deferred.
  - `/re-anchor:mind-your-maxims` — cooperative-communication discipline per
    Grice plus the AI-augmented transparency maxim (arXiv:2403.15115), pointed
    at rather than restated. Audits responses and agent-authored artifacts on
    Quantity (both directions), Relation, Manner, and Transparency. Truthfulness
    delegates to `do-your-research`, pure verbosity to `tighten-your-output`;
    Benevolence is a deliberate out-of-scope exclusion.

### Changed

- **Plugin scope widened** from "the work in flight" to "the work in flight
  and the pre-existing state and choices it trusts", in `plugin.json` and the
  README, with the rationale recorded as a `/re-anchor:reason-dont-recite`
  finding on that boundary. Keywords extended (`upstream`, `conformance`,
  `selection`, `dependencies`, `communication`).

## [0.1.0]

### Added

- **Initial release.** Discipline correctors sharing one re-anchor / audit /
  correct-forward method at plugin scope
  (`context/re-anchor-audit-correct.md`):
  - `/re-anchor:do-your-research` — research and no-assumptions discipline: assert
    nothing without a source, verify every concrete specific, frame the problem before
    the solution, and treat training-data recall as unverified.
  - `/re-anchor:do-your-research-deep` — the verification-fan-out tier of
    `do-your-research`: enumerates every load-bearing claim and dispatches fresh-context
    subagents to verify each against a primary source, throttled in bounded waves, then
    reports a per-claim ledger. A sibling skill rather than a `deep` argument because the
    subagent fan-out is a heavier execution tier (mirrors `/discovery:research-deep`).
  - `/re-anchor:follow-our-standards` — alignment to the consuming organization's
    engineering conventions, with relevance-routed progressive loading and respect
    for a declared managed / locally-owned seam.
  - `/re-anchor:point-dont-copy` — pointer-over-copy discipline: no copied content,
    internal-name coupling, or closed capability lists; duplication threshold of two.
    Re-anchors through the consuming org's reference-don't-duplicate and
    documentation-and-citations conventions (in-repo and external facts), degrading
    to a portable baseline.
  - `/re-anchor:reason-dont-recite` — incumbency discipline: inherited content is
    evidence of what is, never self-justifying authority; a choice supported only by
    precedent earns first-principles re-derivation. A standards disagreement it
    surfaces routes upstream via `/re-anchor:follow-our-standards`.
  - `/re-anchor:tighten-your-output` — terseness discipline: fewer words or lines
    with no loss of meaning or correctness. Code re-anchors the consuming org's
    simpler-code convention; prose terseness has no standards doc yet, so the skill
    flags that gap and routes batch work to compress (prose) and simplify (code).
- Repo-agnostic and machine-agnostic: each corrector re-anchors the discipline the
  consuming project declares in its own instruction layer, and degrades to a portable
  baseline when none is declared.
