# Changelog

All notable changes to the `codebase-health` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.14.0] - 2026-11-13

### Changed

- **Breaking:** the `verification` level now defaults to `light` when the default branch sets no `verification` key or cannot be read: verifier dispatches are skipped and the skip line is written. An invalid value or a team file that does not parse still resolves `standard`, naming the error. Set `verification: standard` (or `strict`), or `verification_skills.<skill>`, in the team file on the default branch to raise it.

## [0.13.9] - 2026-11-13

### Changed

- The vendored prerequisites checker's usage and schema errors give `EXAMPLE_ENABLED` as the sample option name, one that names no plugin.

## [0.13.8] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.13.7] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [0.13.6] - 2026-11-11

### Changed

- The README options reference lists its upstream documentation as pointers only, with no as-of date or recheck trigger.

## [0.13.5] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [0.13.4] - 2026-11-11

### Changed

- The `audit` skill now cites the gather-block convention record, "The pre-compute block runs as one shell
  invocation", instead of restating how the harness runs the pre-compute block. No behavior
  change.

## [0.13.3] - 2026-11-09

### Changed

- Internal simplification of the shared view helpers this plugin carries, no behavior change.

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

## [0.13.2] - 2026-11-09

### Changed

- Simplified the shared resolve-convention-home.sh, resolve-convention-pattern.sh and rewrite-guard.sh copies; behavior is unchanged.

- Simplified the shared setup-apply.mjs, spawn_noise.py and state-key.sh library copies; behavior is unchanged.

## [0.13.1] - 2026-11-06

### Fixed

- `/codebase-health:audit` looks up the user-global `~/.claude/codebase-health.md` with one Read of that literal path, never a Glob, a spelled-out home directory or a search of the home tree; the rendered-view resolver command takes `--option "<option>"` instead of the `${user_config.medium}` token; and the rendered-views files are never read or audited in any phase (#7296).

## [0.13.0] - 2026-11-06

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/codebase-health.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/codebase-health.schema.json`. `/codebase-health:audit` Phase 2 follows it: `strict` dispatches the separate false-positive validator even after an inline Phase 1, and `light` and `off` dispatch none, record `verification: skipped (<level>)` and report the findings `unverified`.

## [0.12.6] - 2026-11-06

### Fixed

- `/codebase-health:setup apply` no longer writes, edits or rewrites `.claude/codebase-health.md` before you confirm the proposed changes. It drafts the config, shows it and asks, and writes only after your reply, whatever tool it would use ([#13734](https://github.com/melodic-software/claude-code-plugins/issues/13734)). The two setup eval cases held out of #8635's conversion, `setup-apply-interviews-first` and `setup-apply-keeps-existing`, are restored.

## [0.12.5] - 2026-11-06

### Changed

- The audit and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Seven new cases: `audit-unscoped-cost-gate` (a bare whole-repo request asks for a scope, names the per-file fan-out cost, and dispatches nothing), `audit-review-only-stops` (`--review-only` reports, hands off to no remediation skill, writes no file and stays on the named file), `audit-infers-and-offers-setup` (with no config the audit looks for one before discovery, says it is absent, audits what the repo holds and offers `/codebase-health:setup` without writing a config), `audit-settings-schema-routes-out` (settings and `.mcp.json` schema drift is reported out of scope and routed to `/harness-config:audit`, never claimed available or fanned out), `audit-view-team-terminal` and `audit-view-retired-terminal` (a terminal medium from the team file or the retired `~/.claude/rendered-views.md` prints the resolver's line and notice with no view offer) and `audit-view-publishing-ignored` (publishing values in the team file and the retired file are only noticed, never followed). `audit-planted-drift` gains the table header, severity, confidence, enforcement, config-gap, resolver-line, view-unavailable and no-HTML-write graders, and `audit-fix-delegates` gains the not-installed manual handoff and report-before-handoff graders. The shared fixture gains `drift-docs-tree`, `harness`, three `view-*` and two `setup-*` modes; the `view-*` and `setup-*` modes make the workspace its own repository, and a file under `$HOME` is written only when it is not the real home. The legacy view-offer lines need the visualization plugin loaded and the offer-taken lines (no `artifact` passed) a second user turn, so neither is measured; with the plugin absent the cases grade the one-line unavailable note instead. The two setup cases (apply explores and asks before writing; apply keeps an existing config) are held out: setup apply writes the config before the user confirms, which the eval run denies, so they cannot read VALID until that is fixed ([#13734](https://github.com/melodic-software/claude-code-plugins/issues/13734)); the fixture keeps their `setup-*` modes for the restore. setup's confirmed write and `.local` override offer need a second user turn. Both `evals.json` files are deleted.

## [0.12.4] - 2026-11-04

### Changed

- The plugin now calls the config cascade's personal layer the personal override (the overlay name is retired) (#13191).

## [0.12.3] - 2026-11-04

### Changed

- Shared config-cascade library synced: the personal layer is now called the personal override in comments and in view-settings' warnings, and `overlayApplies` is `personalOverrideApplies` (#13187). Behavior is unchanged.

## [0.12.2] - 2026-11-04

### Fixed

- Shared `view-registry.mjs` synced where this plugin carries it: the architecture lane now declares that its plugin ships a `medium` option, which #13027 added; no other change to this plugin.

## [0.12.1] - 2026-11-04

### Changed

- **The shared view registry records whether each lane's plugin ships a `medium` option.** `lib/view-registry.mjs` gains `hasMediumOption` on every lane registration, and the retired `~/.claude/rendered-views.md` notice names the plugin's `medium` option only for a lane where it is set; this plugin's notices are unchanged.

## [0.12.0] - 2026-11-04

### Added

- **`medium` option.** A per-user default for the audit's rendered-view offer (default `auto`), passed to the shared medium resolver; the retired `~/.claude/rendered-views.md` notice points at it. Its fixed list of values needs Claude Code v2.1.271 or later.

### Changed

- **`/codebase-health:audit` resolves its view medium through the shared resolver.** The rendered-view offer now runs `lib/view-settings.mjs resolve --lane codebase-health:audit` and prints the resolver's report line and notices. The skill no longer reads `~/.claude/rendered-views.md`, `.claude/rendered-views.md` or `.claude/rendered-views.local.md` itself: the resolver gives a notice for each one naming its new home, a `terminal` or `file` value there still keeps the view local when no other setting decides, and a publishing value there is ignored. The `rendered-views` settings under `docs/conventions/` and the new `medium` plugin option decide ([#12677](https://github.com/melodic-software/claude-code-plugins/issues/12677)).

## [0.11.3] - 2026-11-04

### Changed

- Shared `view-settings.mjs` and `view-registry.mjs` synced where this plugin carries them: the planning lane's design kind and shipped `artifact` default, and the resolver output's `page` and `publishes` fields (#12650); no other change to this plugin.

## [0.11.2] - 2026-11-04

### Fixed

- Shared `view-settings.mjs` synced where this plugin carries it ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)): a `terminal` or `file` value in a retired `rendered-views.md` file keeps the view local when no scope sets one, instead of falling to a publishing default; no other change to this plugin.

## [0.11.1] - 2026-11-03

### Changed

- Shared medium resolver modules (`view-settings.mjs` and the modules it loads) synced into `lib/` ([#12667](https://github.com/melodic-software/claude-code-plugins/issues/12667)); no other change to this plugin.

## [0.11.0] - 2026-11-02

### Added

- **`/codebase-health:audit` offers a rendered view of its report.** In an interactive session with the visualization plugin installed, it offers to render the findings through `/visualization:visualize` after the report, and never builds a page itself. A new `--medium <value>` argument, or the `medium` key of the `rendered-views` layers, controls the offer: `terminal` drops it, and `file` keeps the view local.

## [0.10.10] - 2026-11-01

### Changed

- `audit` drops citation text that changed no behavior: a sentence about how it cites the worktree skill's record, a second link to the discovery method in Phase 1, and a pointer to a marketplace-internal doc that consumer repos do not have. Measured with no loss on Opus 5.5 and Sonnet 5.5.

## [0.10.9] - 2026-10-25

### Changed

- The audit's routing row for page derivability no longer cites a file inside the review plugin's skill folder; it names `/review:fanout run-everything` by invocation only.

## [0.10.8] - 2026-10-20

### Changed

- `audit` gains a `## Next` section routing findings to `/implementation:implement` and applied fixes to `/verification:confirm` ([#7972](https://github.com/melodic-software/claude-code-plugins/issues/7972)).

## [0.10.7] - 2026-10-13

### Changed

- The pre-compute, effort-token and saved-workflow notes point at the exact upstream sections, each with an as-of date and recheck trigger.

### Fixed

- The audit no longer states that a command's whole output always returns inline, that rule files load only when a covered file is read, or that every dispatched agent carries CLAUDE.md; it points at the live doc sections instead and keeps its decisions (bound in the pipe, read every rule file in Phase 0).

## [0.10.6] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.10.5] - 2026-10-02

### Fixed

- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.

## [0.10.4] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.10.3] - 2026-09-30

### Fixed

- **`audit`'s `discovery-method.md` links the audit checklist by its relative path.** The link text named the file through the literal plugin-root token, which the Read tool does not expand. The link target was already relative. No behavior change.

## [0.10.2] - 2026-09-27

### Changed

- `audit`'s discovery method reads "Verify all claims, not just some" instead of "Critical: verify ALL claims". Each claim on a line is still verified independently (#4120).

## [0.10.1] - 2026-09-27

### Changed

- The audit's routing table points prose restated from an external source at
  `/attribution:audit`, the renamed `/provenance:audit`.

## [0.10.0] - 2026-09-23

### Changed

- `audit`'s report opens with a **Needs you** line for findings that turn on a user decision and
  config-gap observations to persist.
- Each discovery subagent's brief states when it is done and when it returns early.

## [0.9.5]

### Changed

- **The Phase 1 scope gate states its requirement instead of shouting it.** "Scope first (MANDATORY. Cost gate)" is now "Scope first (cost gate)"; the sentences after it already stated the filter requirement, the roughly-20-file confirmation threshold, and the token-cost reason, all unchanged.
- **Phase 0 no longer instructs a re-read of always-loaded instructions.** The root `CLAUDE.md` / `AGENTS.md` reach this skill, and each dispatched agent, at startup. The step now reads the `.claude/rules/` files, which do not: those reach a context only when a file they cover is read, and Phase 0 needs the whole convention set as its lens before any file is opened. The lens the phase establishes is the same.

## [0.9.4]

### Changed

- Cite the marketplace `docs/` doctrine files by their lower-kebab names (`docs/plugin-philosophy.md`, `docs/migration-playbook.md`, and siblings); the files were renamed and the old uppercase paths no longer resolve.

## [0.9.3]

### Changed

- **The plugin's prose drops its em dashes.** Six surfaces were rewritten: this changelog, two `skills/audit/reference/` documents, `skills/audit/context/discovery-method.md`, and the two templates under `skills/audit/templates/` and `skills/setup/templates/`. Wording only, with no change to any check, severity, source glob, or phase. Both templates were cleared for rewrite rather than marked: the plugin ships no scripts at all, and each em-dash-bearing template line appears nowhere else in the repository, so nothing parsed the separator. In `config-template.md` the dashes sat in the preamble's definition list, never in the `**primary-sources:**` field markers the config actually uses, which are byte-unchanged. Three headings changed anchor; nothing linked to them. The released sections corrected in place are 0.8.2, 0.8.1, 0.8.0, 0.7.2, 0.7.1, 0.7.0, 0.5.0, and 0.3.0: their wording changed, their facts did not.
- **The 0.8.1 entry quotes `skills/audit/SKILL.md` as it now reads.** That body was rewritten in the same campaign, so the quotation was updated to match it rather than preserve superseded wording.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, the `skills/audit/` reference, context, and template trees, and the setup template, alongside the SKILL bodies it already covered.

## [0.9.2]

### Changed

- **audit:** the inert `shell: bash` frontmatter key is dropped, since no injection remains in the file (prompt-audit follow-up F12).
- Point the audit gather block at the dated composition record (prompt-audit follow-up F6)

## [0.9.1]

### Added

- **`audit`:** an Effort subsection that reads the caller's effort level through the
  `${CLAUDE_EFFORT}` substitution and uses it to select a prefix of the resolved dimension list.
  `low` audits the first dimension only and skips Phase 2 external research, `medium` audits the
  first two and researches Phase 2's listed claim types among those two, and `high` and above audit
  every resolved dimension, so behavior at the default level is unchanged. Effort never adds a dimension the config
  removed and never reorders the list. A narrowed run must name the skipped dimensions in the report,
  and skipping external research reuses the existing graceful-degrade path, confidence-tagging the
  externally-unverifiable part `needs-review` rather than dropping the claim.

## [0.9.0]

### Added

- **`audit`:** a `Boundary, the adjacent drift lanes` section routes the seven sibling drift lanes,
  one table row each: the `review` plugin's `doc-drift-detector` agent, `/session-flow:reanchor`,
  `/discipline:recheck-against-upstream`, `/provenance:audit`, `/claude-config:audit`,
  `/instruction-placement:delta`, and `/overengineering:delta`. The table is a **router for the
  operator, not a dispatch list for the skill**: a request owned by another lane is reported as
  uncovered and that lane is named as the next thing to run, never invoked from inside a bare
  read-only `audit`. That keeps the verb contract intact, since several of these lanes mutate,
  `/discipline:recheck-against-upstream` most directly ("Correct each forward now"), and `--fix`
  authorizes remediation of this skill's own findings only. Lanes are named whether or not their
  plugin is installed, and an absent one is never asserted as available. Each row states its own
  invocation form, because one route is an agent (Agent tool) and the rest are skills. The two rows
  that overlap this skill say where the line falls: the `doc-drift-detector` route is scoped to
  whether a page deserves to exist, its derivability admission gate, while whether a page's claims
  are true stays here repo-wide, so `--docs-only` runs this skill's exhaustive claim pass and never
  routes out; that row also names `/review:fanout run-everything` explicitly, since fanout's default
  lifecycle-tiered mode never dispatches the agent. The `claude-config` row adds
  `/claude-config:audit-instructions` for the instruction surfaces Phase 0 reads only as the
  convention lens. The prior claude-config-only scope notes in the skill body and the README are
  folded into the table rather than stated three times, and the README points at the section instead
  of repeating it. Frontmatter description unchanged (#3810).

  The read-only routing contract, and the observation that automatic dispatch was scope the
  implementation added rather than anything #3810 asked for, come from the parallel independent work
  on this issue in #3829 (closed as a duplicate), ported here with attribution.

## [0.8.9]

### Changed

- audit: the verified-non-issues section asks for evidence per row instead of a count at least equal to the findings; the fan-out rationale and the scope gate drop the unsourced coverage multipliers and the two disagreeing token-cost figures (in SKILL.md and `context/discovery-method.md`); the read-only default and the delegation rule are stated at the argument contract, the fix gate, and the Remediation section only, with the two extra copies removed; the research-tooling rule reads the same in both places (having a tool is optional, using one when present is not); the throttle note drops the pinned concurrency figure and the model-tier prescription; the dimension-order note and the `--review-only` alias are stated without "moot" and "legacy"; "Thoroughness beats speed" is dropped.
- setup: `apply` step 1 starts from the effective config `check` reports instead of repeating the layer walk.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.8.8]

### Fixed

- **`audit`:** the git pre-compute lines moved out of `## Pre-computed context` into a "Repository
  context. Gather first" body section of individual Bash calls, one command per call, each `head`
  bound kept inside its command and a failure read as an unknown value. The harness composes a
  skill's whole pre-compute block into one shell invocation, and a worktree-isolated session refuses
  a git-bearing compound command, which blocked these skills from loading inside a worktree. Same
  shape as the worktree skill's fix in #1619. Non-git pre-compute lines stay where they were.

## [0.8.7]

### Changed

- **setup:** after a team-layer write, re-run the tracked-file pair
  (`git check-ignore -v` no match AND `git ls-files --error-unmatch` exit 0).
  Non-zero `ls-files` means written but untracked: commit it to share with
  the team, never success.

## [0.8.6]

### Changed

- `setup` (and the README/reference docs) now recommend config-cascade's mandated recursive `.claude/**/*.local.*` gitignore line for personal overlays instead of a narrow or bespoke spelling (#3582, customization-consistency Phase 1a).

## [0.8.5]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

## [0.8.4]

### Changed

- **Grammar repaired where the em-dash purge left a sentence broken.** `skills/audit/SKILL.md`. The #2891 substitution replaced a dash without restructuring the sentence, leaving a verbless fragment or a comma splice. Wording only; no rule changed.
- **Authoring-doctrine pass over `README.md`.** Fixed sentences that parsed two ways. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.8.3]

### Changed

- **Instruction-surface de-slop (#2891, codebase-health cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.8.2]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose, as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.8.1]

### Changed

- **`audit`: the config-lane route names the Skill tool (#3002).** The Claude Code config
  route-out (`/claude-config:audit`, `/claude-config:audit-automation-gaps`) says so inline.
  Wording only; presence gates and fallbacks unchanged.

  The remediation preamble is deliberately **not** rewritten: the `--fix` paragraph below it
  requires "an explicit user-directed suggestion" and states "Do NOT auto-invoke either skill,
  the user drives both", so phrasing that route as a Skill-tool invocation would contradict the
  gate four lines down and could launch the source-editing lane from a read-only audit. It stays
  a recommendation to the user, a mention under the rubric's own carve-out, not an operative
  chain.

## [0.8.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.7.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback, presence-gated per the seam-phrasing convention.

## [0.7.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention. Bash-only pipelines must not fall through to a
  PowerShell host.

## [0.7.0]

### Changed

- **BREAKING: `audit` stops at the Phase 3 report and delegates remediation.** The
  inline fix/verify/self-review/retrospect phases (formerly Phases 4–7) are removed.
  They duplicated lanes owned end-to-end by other plugins. Fixing now routes to
  `/implementation:implement` and verification to `/verification:confirm`, referenced as
  soft dependencies (used when installed). `--fix` no longer fixes inline; it hands the
  Phase 3 findings off to those lanes, and when they are absent the findings table is the
  manual handoff (never re-inlined). The audit's codebase-health-specific outputs are
  preserved: the Config Drift → Missing Enforcement → Code Quality → Doc Drift fix order
  travels with the Phase 3 "Fix priority" section, and post-audit config-gap observations
  worth persisting via `/codebase-health:setup` fold into Phase 3's required sections.

## [0.6.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.6.1]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/claude-config:audit-automation-gaps`); behavior unchanged.

## [0.6.0]

### Changed

- **BREAKING: `audit` is read-only on bare invocation** (fleet conformance
  wave: the naming doctrine's `audit` verb contract). It reports and stops;
  auto-fix phases now require the explicit `--fix` flag. `--review-only` is
  accepted as a legacy alias for the new default and no longer needs to be
  passed.

## [0.5.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects the effective merged
  `.claude/codebase-health.md` config read-only across its user-global → team → local overlay layers
  (presence, dimension source-list validity, tracked-not-ignored, and overlay divergence) and reports
  a PASS/FAIL/INFO table. An absent config is INFO, since the audit re-infers targets each run.
  `apply` runs the interview-infer-write flow, then re-runs `check` to verify the written file. The inference,
  example-claims, and layer-merge logic are unchanged; the read-only inspection path and the
  `check | apply` argument-hint are new.

## [0.4.0]

### Changed

- Renamed the plugin `codebase-audit` → `codebase-health` and its audit skill `codebase-audit` → `audit`.
  The audit invocation is now `/codebase-health:audit` (setup is `/codebase-health:setup`). Existing
  installs migrate automatically through the marketplace renames map.
- Renamed the consumer config-file convention `.claude/codebase-audit.md` → `.claude/codebase-health.md`
  (setup writes it, audit reads it). Re-run `/codebase-health:setup` to scaffold the new file; migrate
  any existing config manually.

## [0.3.0]

### Added

- Eval covering the scope-boundary decline: declining claim-extraction fan-out over
  `settings.json` / `.mcp.json` / hooks / permissions and routing to the adjacent
  `claude-config-audit` plugin's `/claude-config-audit:settings-audit` skill (or stating
  out-of-scope when that plugin is not installed), behavior already documented in SKILL.md,
  now regression-tested.

## [0.2.0]

### Added

- Optional background/unattended execution variant for the Phase 1 per-file fan-out: the same
  discovery can run as a saved workflow (background execution, same-session resume, rerunnable
  script) when the environment provides such a surface; the in-session fan-out remains the default.
