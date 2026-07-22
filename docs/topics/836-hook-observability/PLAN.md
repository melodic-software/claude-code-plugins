# Plan: #836 — hook-observability fleet convention + fleet adoption

## Brief

Issue melodic-software/claude-code-plugins#836 (epic #830, sub-item 6 of
`docs/topics/lint-static-analysis-gaps/PLAN.md`, lines 37-41):

> Hook-observability fleet convention — every fleet hook emits `statusMessage` (during run),
> `systemMessage` (failure/notable action), and the hook-telemetry OTel envelope. Grounded in
> current official hooks docs at authoring time (no native user-visible hook UI exists as of
> 2026-07-21; OTel events + author-emitted messages are the sanctioned surfaces). Optional
> sub-item: upstream feature request for a native verbose-hooks UI toggle.

Acceptance criteria (PLAN.md lines 64-65): *"Hook-observability convention documented as an owner
doc (convention registry row) and adopted by every fleet hook; conformance audited."*

## Brief-said-X / docs-say-Y / so-we-did-Z (mandatory correction)

The brief says every hook "**emits** `statusMessage`". Fresh fetch of
<https://code.claude.com/docs/en/hooks> (2026-07-22) shows `statusMessage` is a **static field on
the hooks.json handler object** — sibling of `type`/`command`/`timeout`/`if`/`once` — not a
runtime JSON-output field a hook script emits on stdout. It is "a custom spinner message displayed
while the hook runs," declared once at config time. **So we corrected the mechanism**: fleet
adoption of `statusMessage` is a `hooks.json` config edit, not a shell-script change. This does not
change the acceptance criterion's intent (a live status label during hook execution) — only the
implementation surface.

## Research findings (fresh, cited)

Source: <https://code.claude.com/docs/en/hooks>, fetched 2026-07-22.

1. **`statusMessage`** — handler-object config field (`hooks.json`), optional, no default. Spinner
   label shown while the hook process runs.
2. **`systemMessage`** — JSON output field (exit 0), "warning message shown to the user," 10,000
   char cap, immediate effect. The composing helpers (`hook::emit_channels` /
   `hook::emit_skip_notice`, `lib/hook-utils.sh:58,74`) exist fleet-wide and are already callable
   by every hook — **adoption at every missing-prerequisite skip site is not yet complete**; see
   "systemMessage — 11 genuine gaps" below for the sites still on stderr-only or
   `additionalContext`-only.
3. **Exit-code display semantics** (load-bearing for scoping "notable action" below):
   - Exit 0: stdout parsed as JSON if present; **stderr is ignored** — never shown to user or
     agent on exit 0.
   - Exit 2: stderr fed to Claude as an error / shown to user depending on event; for
     `PreToolUse` this **blocks the tool call** — the block itself is the user-visible surface
     (via Claude Code's own permission-denial UI), independent of any `systemMessage`.
4. **OTel correlation** — hook input JSON carries `prompt_id` (v2.1.196+), which matches the
   `prompt.id` attribute on real OpenTelemetry events, enabling external correlation.
   **Not adopted in this lane** — see "Deferred: prompt_id correlation" below.
5. **Why the envelope is local-file, not real OTel export** — Claude Code strips all `OTEL_*`
   exporter environment variables from every hook subprocess it spawns (documented at
   `/docs/en/monitoring-usage#administrator-configuration`). A hook process cannot emit real OTel
   telemetry even if it wanted to; `hook::emit_telemetry`'s file-sink envelope is the only
   surface available to a hook. This convention doc states that rationale explicitly so it reads
   as a grounded design choice, not an oversight.

## Deferred: prompt_id correlation

Adding `prompt_id` to the telemetry envelope (`hook::emit_telemetry`'s `data` object, or a new
schema field) is a genuine improvement — it would let external tooling correlate a hook's local
telemetry with the same turn's real OTel events. It requires either a new parameter on
`hook::emit_telemetry` (`lib/hook-utils.sh`, the synced SSOT) or updating every producer's
`data_json` construction (25 call sites) to extract and pass it. Bundling it into #836 would:

- Be a **`hook-telemetry` schema change** (bump `schema_version` 1.0 → 1.1), not a
  `hook-observability` concern — different owner doc, different issue.
- Force either an inconsistent partial rollout (some producers populate `prompt_id`, others
  don't — indistinguishable from "genuinely absent, pre-first-input" per the docs) or a 25-file
  sweep unrelated to this issue's three-surface scope.

**Filed separately, not fixed here.** `prompt_id`-correlation stays out of #836; tracked as a
follow-up against the `hook-telemetry` convention (issue to be filed at PR-A time, referenced in
the new doc's "Deferred" section).

## Two-PR structure (precedent-matched)

Per `docs/PLUGIN-PHILOSOPHY.md:272-274`: *"A new cross-plugin convention lands in an owner doc
before a second plugin adopts it."* Confirmed via git history: `hook-precision`
(`d0805dc8fc`, PR #761) landed as a **doc-only** commit (README + one registry row), with fleet
adoption explicitly deferred to follow-up work ("member fixes ride their own issues"). Matching
that precedent:

- **PR A — convention doc.** `docs/conventions/hook-observability/README.md` (new, owner doc) +
  one row in `docs/PLUGIN-PHILOSOPHY.md`'s Convention registry table (~line 286). Small, fast,
  unblocks PR B. Body: "Part of #836" (not "Closes" — the issue's acceptance criteria require
  adoption too).
- **PR B — fleet adoption.** Branches off main **after PR A merges**, so hooks.json/scripts can
  cite the merged doc. Closes #836.

## PR A scope (this session, first)

- `docs/conventions/hook-observability/README.md` — owner doc. Contents:
  - Three surfaces: `statusMessage` (config, spinner), `systemMessage` (user-visible, exit-0 JSON,
    scoped to "silently-skipped feature due to missing runtime prerequisite" per the existing
    doctrine at `lib/hook-utils.sh:26-30`), OTel-style telemetry envelope (`hook::emit_telemetry`).
  - Explicit scoping rule for `systemMessage`: **required** for missing-prerequisite skip paths;
    **not required** for exit-2 blocking paths (already user-visible via Claude Code's own
    permission-denial UI — an additional systemMessage would be redundant) or for legitimate
    agent-only advisory findings (those stay on `additionalContext` by design).
  - `statusMessage` wording convention: present-tense gerund phrase, tool-specific, e.g.
    "Formatting Go imports...", "Checking for secrets...", "Recording tool-failure telemetry...".
  - The OTEL_*-stripping citation (why local envelope, not real export) and the deferred
    `prompt_id` correlation note with a link to the follow-up issue.
  - Conformance-audit pointer: what a future audit checks per hook (statusMessage present on every
    command-hook handler; systemMessage present on every missing-prerequisite skip path; telemetry
    call present in every producer).
- `docs/PLUGIN-PHILOSOPHY.md` — one new row: `| Hook observability | docs/conventions/hook-observability/ |`.
- File the `prompt_id`-correlation follow-up issue; link it from the doc's Deferred section.
- Optional brief sub-item (upstream feature request for a native verbose-hooks UI) — file as a
  separate low-priority issue/note, not implemented here (external, no repo action).

Blast radius: **two files** (one new, one one-line edit). No plugin touched. No version bump. No
CHANGELOG entry (docs/ is not a plugin). Sanity check: `markdownlint` on the new README; verify
relative links resolve; verify the registry table row matches the existing row format exactly.

## PR B scope (second lane, after PR A merges)

**Zero `lib/hook-utils.sh` (SSOT) edits** — verified: every fix uses an *existing* helper
(`hook::emit_skip_notice`, `hook::emit_telemetry`). This collapses the collision risk explore-836
flagged against open PR #903 (also touches `lib/hook-utils.sh`) to zero for this lane — nothing to
sequence against. (Registry-row rebase risk against PR #925's `PLUGIN-PHILOSOPHY.md` edit is PR A's
concern, not PR B's, and is a one-line context conflict at worst — same class as prior lanes'
benign version-bump collisions.)

### statusMessage — mechanical, all 27 wired producer hooks, 12 plugins

Add a `statusMessage` field to every `command`-type handler object in each plugin's `hooks.json`.
One line per handler, present-tense gerund wording. Plugins touched (hooks/ present):
actionlint, bash-format, biome-format, claude-ops, desktop-notification, eol-normalizer, go-format,
guardrails, markdown-format, powershell-format, ruff-format, typos-format. Each gets a patch-level
`plugin.json` version bump + CHANGELOG entry (changelog-parity-gate).

### systemMessage — 11 genuine gaps (per audit-836's per-hook classification)

All 9 use the existing jq-free `hook::emit_skip_notice`/`hook::emit_channels` helpers — convert
the current `echo "..." >&2; exit 0` (invisible on exit 0 per the docs — a real doctrine
violation, not cosmetic) to `hook::emit_skip_notice <EVENT> "<message>"`:

- `plugins/guardrails/hooks/block-dangerous-git.sh:47-50`
- `plugins/guardrails/hooks/block-hook-bypass.sh:45-48`
- `plugins/guardrails/hooks/block-no-verify.sh:45-48`
- `plugins/guardrails/hooks/block-noncanonical-commit.sh:72-75`
- `plugins/guardrails/hooks/cli-flag-verify.sh:38-41` (jq-missing) **and** `:78` (bundled-verifier
  missing — currently fully silent, not even stderr; add a skip notice there too)
- `plugins/guardrails/hooks/flag-commit-pr-skill-bypass.sh:56-59`
- `plugins/guardrails/hooks/hardcoded-path-check.sh:40-43`
- `plugins/guardrails/hooks/secret-pattern-detection.sh:33-36`
- `plugins/guardrails/hooks/workflow-resilience-check.sh:24-27` (secondary gap, bundled with its
  telemetry fix below)

Convert agent-only skip branches to dual-channel (`hook::emit_additional_context` →
`hook::emit_channels`/`hook::emit_skip_notice`):

- `plugins/claude-ops/hooks/skill-usage-audit.sh:42-43,58-59`
- `plugins/claude-ops/hooks/skill-usage-expansion-audit.sh:53-54,71-72`

**No change** to the 6 pure-telemetry claude-ops emitters (api-error, config-change,
instructions-loaded, permission-denied, pre-compact, tool-failure audits) — their prereq-skip
paths degrade telemetry only, already covered by `hook::emit_telemetry`'s documented fail-open
contract; no user-facing feature is silently lost. **No change** to guardrails' exit-2 block paths
— already user-visible via Claude Code's blocking UI (doc states this rationale explicitly).

### Telemetry — scope clarified, 1 genuine gap

Codex correctly flagged that "every exit path emits telemetry" (the doc's original Conformance
wording) does not hold literally: every existing telemetry-emitting guardrails hook has several
`exit 0` short-circuits BEFORE its `emit_tel` helper is even defined — missing `jq`, wrong tool
type, empty content, path outside the project, an excluded-path-pattern match. Verified this
pattern empirically across all 8 existing telemetry-emitting guardrails hooks (`block-dangerous-
git`, `block-hook-bypass`, `block-noncanonical-commit`, `cli-flag-verify`,
`flag-commit-pr-skill-bypass`, `hardcoded-path-check`, `secret-pattern-detection`, plus the
claude-ops audit hooks) — in every one, the pre-`emit_tel` exits are pure inapplicability
short-circuits (this tool/file/state doesn't apply to this hook at all), and every *meaningful*
outcome (a check ran and produced a result: ok / blocked / skipped-for-cause) does call
`emit_tel`. **The real, corrected rule: telemetry is required for every meaningful outcome, not
for pure inapplicability short-circuits that carry no diagnostic information** — both the owner
doc's Conformance section and this plan are corrected to say this precisely, rather than the
looser "every exit path."

Under that corrected rule, the genuine gap is unchanged in substance but now precisely scoped:

- `plugins/guardrails/hooks/workflow-resilience-check.sh` — has **zero** telemetry calls anywhere,
  including on its meaningful outcome paths (fan-out detected, throttle applied, advisory issued)
  — unlike every sibling guardrails hook, which correctly telemeters those. Add a
  `hook::emit_telemetry` call at each meaningful exit (status `ok`/`skipped` per outcome),
  matching every other guardrails hook's shape. Its pure-inapplicability exits (missing `jq`,
  no fan-out script) correctly need no telemetry, matching the sibling pattern.

### Housekeeping bundled into PR B

- Reconcile `docs/conventions/hook-telemetry/README.md`'s stale Implementers table (omits
  actionlint, biome-format, eol-normalizer, powershell-format, several guardrails hooks,
  skill-usage-expansion-audit) — natural byproduct of touching every producer's telemetry status;
  needed for #836's own "conformance audited" criterion to be true on merge.

### Test plan (PR B)

- `claude plugin validate --strict` per touched plugin (statusMessage acceptance already smoke-
  tested against go-format this session — passes).
- Each converted guardrails/claude-ops hook: existing `*.test.sh` (if present) extended with a
  jq-missing-path case asserting `systemMessage` is now non-empty (previously asserted only
  stderr / additionalContext, per the doctrine violation being fixed). Where no test file exists
  yet for a guardrails hook, add the minimal FAKEBIN-pattern case for the changed branch only —
  not a full test-suite retrofit (out of scope).
- `scripts/validate-plugin-contracts.mjs` full run.
- Local CI-equivalent gate sweep: hygiene, changelog-parity-gate, hook-utils-sync (expect **no
  diff** — confirms the zero-SSOT-edit claim empirically), silent-skip-gate, skill-quality-gate.

## Stress-test targets (mandatory fresh-context pass before PR B implementation)

- Is the A/B/C/D classification correct for all 17 audited hooks — spot-check 3-4 against the
  actual current source, not just the audit's citations.
- Does `hook::emit_skip_notice`'s dual-channel emission interact safely with each hook's *existing*
  exit-0 JSON output (e.g. `cli-flag-verify.sh`'s advisory `additionalContext` at `:390` and
  `workflow-resilience-check.sh`'s existing `emit_additional_context` at `:52`) — must compose into
  ONE JSON document (`hook::emit_channels`'s documented contract), not two competing `printf`s.
  This is the single highest-risk correctness question for PR B.
- Confirm no hook currently relies on the jq-missing branch being *silent* for a reason not yet
  surfaced (e.g., a downstream test asserting empty stdout on that path).

## Stress-test corrections (fresh-context pass, folded in)

Full stress-test confirmed the plan's core (config-only `statusMessage`, doc-first two-PR
structure, jq-missing/advisory mutual exclusion, zero-SSOT-edit claim, all cited line numbers).
Two real corrections, both folded into PR B scope below:

- **C1 — use `hook::require_jq`, not raw `hook::emit_skip_notice`, for jq-missing branches.**
  The fleet's canonical jq-gate pattern is `hook::require_jq <event> <plugin> "$INPUT"`
  (`lib/hook-utils.sh:132`) — it wraps `emit_skip_notice` in `hook::notice_once` so the notice
  fires once per session, not on every invocation. Raw `emit_skip_notice` has no such gate; on a
  broad matcher (block-dangerous-git's `Bash` matcher, cli-flag-verify's `Write|Edit`) it would
  spam a systemMessage on every tool call — the exact hazard `lib/hook-utils.sh:88-89` documents.
  **All 9 jq-missing conversions use `hook::require_jq <event> "guardrails" "$INPUT"`** (shared
  per-plugin notice key — one jq-missing notice per session across all 8 guardrails hooks is
  sufficient; no need to differentiate by individual guard). The one non-jq gap
  (`cli-flag-verify.sh:78`, bundled-verifier-missing) manually pairs
  `hook::notice_once "guardrails-cli-flag-verifier" "$INPUT"` with `hook::emit_skip_notice`,
  since `require_jq` doesn't fit a non-jq prerequisite.
- **C2 — the existing `silent-skip-gate` (`scripts/check-silent-skips.sh`) does not enforce this
  convention and must be tightened as part of PR B.** Its `is_visible()` currently treats a bare
  `>&2` write as a sanctioned visibility signal — which is exactly the pattern all 9 fixed sites
  used, and per the fresh docs finding above (exit 0 discards stderr entirely — never shown to
  user or agent), a bare stderr write on an exit-0 skip path is **not actually visible**. The
  gate has a false negative for the precise violation class #836 exists to fix; leaning on it as
  PR B validation (as an earlier draft of this plan did) would be circular. **Fix: remove
  `l ~ />&2/` from `is_visible()`** (every site this gate inspects is, by construction, an exit-0
  skip path — a bare stderr write is never visible there per the docs, so the sanctioned-call
  list should require `hook::emit_skip_notice`/`hook::emit_system_message`/`hook::notice_once`/
  `hook::require_jq`, or an explicit `# silent-skip-ok:` annotation). Update the script's header
  comment (drop "or a stderr write" from the sanctioned list, cite the docs finding) and flip the
  `check-silent-skips.test.sh` fixture at "block skip with a stderr notice passes" (currently
  asserts bare stderr passes — must assert it now FAILS). **Verified safe to tighten**: grepped
  every `plugins/*/hooks/*.sh` for a bare `>&2` write within 3 lines of an `exit 0` not already
  wrapped in a `hook::` call — the only 9 hits are exactly the 9 sites this PR already converts
  (`block-dangerous-git.sh:48`, `block-hook-bypass.sh:46`, `block-no-verify.sh:46`,
  `block-noncanonical-commit.sh:73`, `cli-flag-verify.sh:39`, `flag-commit-pr-skill-bypass.sh:57`,
  `hardcoded-path-check.sh:41`, `secret-pattern-detection.sh:34`,
  `workflow-resilience-check.sh:25`) — no other fleet hook regresses.
- **O1 (accepted, scoped in) — workflow-resilience-check.sh's telemetry gap is real plumbing, not
  a one-liner.** The hook has no `start=${EPOCHREALTIME}` stamp, no `data_json` builder, and 4
  distinct exit paths (no-script, no-fanout, has-throttle, advisory). PR B adds a start stamp
  near the top (after `hook::check_enabled`) and an `emit_telemetry` call at each exit path with a
  status reflecting that path's outcome (`ok` for has-throttle/advisory, `skipped` for
  no-script/no-fanout), matching the shape every other guardrails hook already uses.

## Open decisions / not yet locked

- Exact `statusMessage` wording per hook — draft during PR B implementation, not pre-decided here
  (27 short strings, low-risk, easy to review together).
- Whether the upstream native-verbose-hooks-UI feature request (brief's optional sub-item) gets
  filed as a GitHub issue against `anthropics/claude-code` or just noted — default: file a brief,
  low-priority issue there if repo conventions allow external filing; otherwise note as declined
  with rationale (no repo mechanism for it). Decide at PR A close-out.
