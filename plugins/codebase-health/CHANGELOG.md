# Changelog

All notable changes to the `codebase-health` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.8.1]

### Changed

- **`audit`: the config-lane route names the Skill tool (#3002).** The Claude Code config
  route-out (`/claude-config:audit`, `/claude-config:audit-automation-gaps`) says so inline.
  Wording only; presence gates and fallbacks unchanged.

  The remediation preamble is deliberately **not** rewritten: the `--fix` paragraph below it
  requires "an explicit user-directed suggestion" and states "Do NOT auto-invoke either skill —
  the user drives both", so phrasing that route as a Skill-tool invocation would contradict the
  gate four lines down and could launch the source-editing lane from a read-only audit. It stays
  a recommendation to the user — a mention under the rubric's own carve-out, not an operative
  chain.

## [0.8.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.7.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.7.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.7.0]

### Changed

- **BREAKING: `audit` stops at the Phase 3 report and delegates remediation.** The
  inline fix/verify/self-review/retrospect phases (formerly Phases 4–7) are removed —
  they duplicated lanes owned end-to-end by other plugins. Fixing now routes to
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
  (presence — absent is INFO, since the audit re-infers targets each run — dimension source-list
  validity, tracked-not-ignored, and overlay divergence) and reports a PASS/FAIL/INFO table; `apply`
  runs the interview-infer-write flow, then re-runs `check` to verify the written file. The inference,
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
  out-of-scope when that plugin is not installed) — behavior already documented in SKILL.md,
  now regression-tested.

## [0.2.0]

### Added

- Optional background/unattended execution variant for the Phase 1 per-file fan-out: the same
  discovery can run as a saved workflow (background execution, same-session resume, rerunnable
  script) when the environment provides such a surface; the in-session fan-out remains the default.
