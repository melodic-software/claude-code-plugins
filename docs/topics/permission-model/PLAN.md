# permission-model

## Brief

### TLDR

Add **two** new skills to the `claude-config` plugin. `audit-permission-state` computes the
**effective merged Claude Code permission state** across all five settings scopes with per-rule
provenance, plus a decidability-bounded set of lints over that state and over the `autoMode` block;
`draft-auto-mode-rules` is the authoring lane, drafting an `autoMode` block to stdout for a human to
paste. Both audit or generate and print; neither enforces and neither writes configuration. Existing
`claude-config` permission checks get in-place scope widening at the same time — **both are now named:
`audit-permission-grants` check P1 gains user-global scope, and `claude-config:audit`'s settings scan
gains the start-directory `settings.local.json` copy.** No new plugin.

*Amended 2026-08-09: one skill → two, on the operator's admission of the authoring lane. `MIGRATION-PLAYBOOK.md`
§Naming binds a skill name to its kind, so an `audit-*` skill cannot host a `draft` action.*

### Goal

Close the legibility gap in Claude Code's permission plane for downstream consumers of this
marketplace.

Research established the gap is total: there is no `claude permissions` CLI subcommand (established
by controlled live probe on 2.1.225 — the same probe form returns real usage for seven other hidden
commands and falls back to top-level usage for `permissions`), no documented machine-readable export
of resolved permission state, and across roughly thirty third-party tools nobody audits an `autoMode`
block, resolves cross-scope precedence, or validates a managed policy against the scopes beneath it.
The highest-adoption linter in the space carries one permission rule out of 447 and zero
managed-settings coverage. The official plugin marketplace ships 284 plugins and none of them manage
permission configuration.

Demand is documented rather than assumed: measured dead allow rules written by the harness's own
"Always allow" path (77 of 154 rules in one Windows project; 6 of 9 on macOS), a session carrying 900+
allow rules still prompting 700+ times in two days, and two production fleet incidents caused by the
managed-tier no-merge rule.

Auto mode becomes the default permission mode for new sessions on Pro, Max, and Team plans on
2026-08-14. That does not create the gap, but it widens it: broad allow rules and every `Agent` allow
rule are silently dropped on entering auto mode, and consumers have no way to see that happen.

### Constraints

**Product shape**

- Audit and legibility first. Auto-mode authoring is a second lane, not v1's core.
- **Report-only.** No enforcement in v1 and no writes to consumer configuration. An enforcing hook, if
  ever built, is an explicitly separate opt-in component. Research confirms enforcement is genuinely
  available to a plugin — hook `deny` and exit-2 both hold, measured — so this is a deliberate posture
  choice, not a capability limit.
- The managed/enterprise tier is in scope, **read-only**. A plugin can never author managed policy:
  those are admin-write OS paths or a claude.ai Owner role.

**Packaging**

- A new sibling skill under `claude-config`, plus in-place scope widening of two existing checks.
  **Not** a new plugin. `marketplace.json`'s `renames` map is a flat plugin→plugin map and cannot
  express a partial extraction, so extracting would silently strip `audit-permission-grants` from
  every consumer on update. Extraction would also turn `audit-pass/SKILL.md`'s route-out section into an unguarded
  cross-plugin reference, which `PLUGIN-PHILOSOPHY.md` §Organization names a defect.

**Reading state**

- **Compute** the merge, bounded by a per-item decidability criterion with a **stated basis**. In
  scope: anything following from documented mechanics over readable inputs, each claim citing the
  mechanic it follows from. Out of scope: classifier judgment, runtime demotion state, and anything
  resting only on an open upstream discrepancy — each becomes a **named caveat** on the affected
  finding, never a silent drop and never an assertion.
- **Shell out only for `autoMode` built-in defaults.** The changelog does not track the content of the
  shipped rule lists (zero matches across all 359 releases), so version-gating them from release notes
  is impossible — probe and diff, never infer from a version number.
- **Defensive contract for every CLI read, each item measured on 2.1.225, not assumed:** never a
  strict JSON parser (`claude auto-mode config` emits raw control characters inside string values;
  `jq` and Python's default `json.loads` both reject, exit code still 0); tolerate a **missing** key,
  not merely an empty array (`defaults --label` omits `environment` entirely); split a rule label at
  the first `[`, not the first `:` (`soft_deny` labels carry a bracketed annotation before the colon);
  **never trust exit status** (`critique` returned 0 on all three runs including the one producing no
  output at all).

**Upstream posture**

- **Fetch at read time.** Bake no upstream catalogs — not the default rule lists, the block/allow
  catalogs, the protected-path enumeration, the version-gate table, or the footgun list.
- Every durable claim derived from upstream carries a recheck trigger naming an **observable event**,
  per `docs/conventions/upstream-drift/README.md`. A bare date does not qualify in this repository.
- A record carries claim **and** basis **and** trigger. A trigger without its basis is untestable: the
  invalid-JSON defect is machine-conditional (attributed to user-supplied entries spliced without
  re-escaping), so "`config` parses under a strict parser" would pass on a clean machine and clear a
  defect that was never present. The basis must state the probe.

**Leverage built-ins, never re-implement their judgment**

- `claude auto-mode critique` is surfaced and wrapped, never replaced. It owns the semantic judgment
  (clarity, completeness, conflicts, actionability). We own only the mechanical layer it does not do.
  Its unreliability is wrapped, not hidden: truncation and empty-output detection, with a plain
  "critique returned nothing; run it yourself" surface.

**Surface and output**

- A skill driving deterministic scripts. No CI-gate entry point.
- Findings use the `review` plugin's `severity.md` vocabulary — the marketplace's neutral baseline.

### Acceptance criteria

1. Given a repository and a user home with settings at two or more scopes, the skill reports the
   effective merged `permissions.allow` / `.ask` / `.deny` set with the source scope named per rule,
   and each precedence claim cites the documented mechanic it follows from.
2. The skill detects **both** dead-config traps at their **two distinct gates** — `autoMode.*` ignored
   in project and local settings (local also read before v2.1.207), and `defaultMode: "auto"` ignored
   in project and local settings (project could set it before v2.1.142) — and reports each separately.
   `useAutoModeDuringPlan`, which is not read from shared project settings, is covered as a third.
3. The skill classifies every allow rule that auto mode drops on entry: blanket `Bash(*)` /
   `PowerShell(*)`, wildcarded interpreters, package-manager run commands, and **all `Agent` allow
   rules**.
4. The skill detects a `$defaults` omission per `autoMode` section and states which built-in rule list
   that omission discards.
5. The skill detects `disableAutoMode` typed as a boolean rather than the string `"disable"`, in any
   scope (it is not managed-only).
6. The skill detects allow rules that cannot match — doubled-backslash Windows paths, unanchored allow
   globs, `Write(path)`-shaped rules that are accepted but never consulted, and `:*` used anywhere but
   at pattern end.
7. The skill reads a pre-v2.1.211 `settings.local.json` copy left in the start directory as well as
   the repository-root copy, because permission rules from both stay in effect.
8. Every CLI read survives the measured defect set: invalid JSON, a missing key, a bracket-prefixed
   label, and exit 0 on empty output. A run that produced no usable output reports that fact and never
   claims success.
9. The skill performs no writes to any consumer settings file, in any scope, under any flag present in
   v1.
10. Every finding whose basis is an open upstream discrepancy carries that discrepancy as a named
    caveat.
11. `claude-config:audit-permission-grants` check P1 sees user-global rules. Today
    `reference/criteria.md`'s settings-scan section scans project and local settings only, so a user-global
    interpreter-wildcard rule is invisible to it.
12. `skill-quality:check listing-budget` is run against the resulting shape; the new skill's listing
    cost is stated rather than assumed.

### Captured assumptions

- Every CLI behavior recorded here comes from a single capture on **Claude Code 2.1.225, Windows 11**,
  2026-08-09. The measured defects are shell-dependent (Git Bash truncated vs PowerShell empty), so
  per-platform behavior is assumed similar and **not verified**. Re-probe before acting.
- The five research slices carry no `preload_token` — the `/discovery:research` preload failed
  silently across the whole fan-out. Only `permissions-core` received full independent adversarial
  verification (7/7 priority claims survived, 15/15 drift hashes reproduced, 3 defects found and
  corrected). The other four are cross-checked against each other but not separately verified.
- Roughly fifteen GitHub issues in the ecosystem sweep were title-verified only, bodies not read.
- Reddit was unreachable during the sweep; no absence claim is possible from that venue.
- #83766 and #42797 report `permissions.ask` patterns auto-approved under `defaultMode: auto`, which
  contradicts current documented behavior. Treated as **open discrepancies, not settled facts**.

### Out-of-scope

- Enforcement of any kind in v1, including the PreToolUse `"ask"` lever that is documented to bind the
  classifier in auto mode.
- Writing or generating consumer configuration, including a `--fix` mode.
- Authoring managed policy. Auditing it is in scope; authoring it is structurally impossible for a
  plugin.
- Re-implementing the semantic judgment `claude auto-mode critique` performs.
- A new plugin, and the extraction of `audit-permission-grants` out of `claude-config`. Re-opens only
  on the trigger recorded under Q5 below.
- Skill naming, which still needs deriving against `MIGRATION-PLAYBOOK.md` §Naming. One live
  constraint: `PLUGIN-PHILOSOPHY.md` §Naming requires the namespace noun to be true of every skill under
  it, and the locked authoring lane is a mutating verb — `claude-config` survives that test, a
  narrower noun would not.

### Deferred questions

- **Q11 — RESOLVED 2026-08-09, no longer deferred.** A marketplace-installed plugin's skill
  `allowed-tools` grant is **NOT** gated by workspace trust: it takes effect at user scope in a
  never-trusted workspace, under `-p` where no trust dialog can appear. Measured on 2.1.225 — the
  covered command ran, the uncovered one blocked with `This command requires approval`, and a
  no-grant baseline proves that shape blocks. Method, the two stated bounds (local-directory
  marketplace, user scope only), and four invalid prior attempts are recorded in
  `.work/permission-model/EXPERIMENT-marketplace-allowed-tools-trust.md`.

  **Consequence for this repository, carried into the plugin-acceptance security review:** a skill
  this marketplace ships can grant itself a prompt-free tool invocation in a consumer's untrusted
  workspace, and the install-time plugin trust prompt is the only gate in front of that — there is no
  second, per-workspace one. This does not change v1's scope, which ships no self-grant.

- **Q12 — CLOSED 2026-08-09, shipped.** PR #2089 merged at `2026-08-09T17:31:08Z`;
  `docs/OFFICIAL-DOCS.md:100` now carries
  `| Configure auto mode (autoMode, claude auto-mode) | https://code.claude.com/docs/en/auto-mode-config | 2026-08-09 |`.
  The USER-RESERVED gate is discharged — nothing here waits on it.

- **Unprobed CLI surfaces — RESOLVED 2026-08-09 by `/planning:plan`'s own probe**
  (`.work/permission-model/EXPERIMENT-debug-channel-merge-narration.md`). The debug channel narrates
  the merge per destination with full rule text **and** narrates every auto-mode-dropped allow rule
  individually with its absolute source path and reason. `claude config` does **not** exist as a
  subcommand (controlled probe: `claude config --help` falls back to top-level usage; control
  `claude plugin --help` returns real usage), so there was nothing to enumerate. `claude --safe-mode`
  as a differential control was not needed — the drop narration is explicit rather than differential.
  Consequence: the computed merge stays as the read path; the channel becomes an optional oracle whose
  disagreement with the prediction is itself a finding. Bounds are in the experiment file — scopes
  absent from the capture were not disproved, obtaining the narration costs a session spawn, and the
  `[DEBUG]` strings carry no stability contract.

- **Runtime prerequisite and its degradation path.** A non-strict JSON parser implies Python or Node —
  a new undeclared runtime prerequisite, which `PLUGIN-PHILOSOPHY.md` §Prerequisites and failure behavior and §Cross-platform contract govern
  ("never assume Bash, `jq` … is present"; never execute an undeclared tool as an incidental
  fallback). The measured defects are shell-dependent, so the declaration and the degradation path are
  per-platform. **Arbiter: `/planning:plan`.**

- **Fresh-context delegation directive.** `PLUGIN-PHILOSOPHY.md` §Fresh-eyes checkpoints requires any
  skill step that judges output the same context produced to state a fresh-context delegation or a
  greppable exemption; `skill-quality:check` enforces it. Not yet stated for this skill. **Arbiter:
  `/planning:plan`.**

- **Two-lane security-floor posture.** `audit/reference/required-permissions.md` is a shipped lane-1
  default security floor. Bringing an enterprise audience into scope raises the odds a consuming org
  holds its own floor, pushing it toward lane 2 (discover-and-externalize) per
  `PLUGIN-PHILOSOPHY.md` §Two-lane convention posture. That re-derivation is owed regardless of this work. **Arbiter:
  `/planning:plan`.**

### Recheck triggers

- **Plugin extraction re-opens when** the auto-mode authoring lane acquires its first persistent-state
  or settings-writing component.
- **The local merge retires when** `claude permissions --help` returns real usage instead of falling
  back to the top-level `Usage:` line — the same controlled probe that established its absence.
  This trigger is **necessary but not sufficient on its own**: a second, narrower route already
  exists. `claude --debug-file <path> -p <prompt>` narrates the merge per destination with full rule
  text, and narrates every auto-mode-dropped allow rule individually with its source file path and
  the reason `(bypasses classifier)` — measured on 2.1.225, 216 drop lines in one session
  (`.work/permission-model/EXPERIMENT-debug-channel-merge-narration.md`). It does not retire the
  computed merge, because it costs a session spawn and parses undocumented `[DEBUG]` strings with no
  stability contract. It is an oracle, not a read path.
- **The debug-channel oracle degrades when** a `--debug-file` capture on a machine with known
  auto-mode-dropped rules stops emitting `Ignoring dangerous permission <rule> from <path> (bypasses
  classifier)`. Basis: the strings are undocumented internal output, so only a capture proves them.

## Plan

**Skill name: `claude-config:audit-permission-state`.** Derived against `MIGRATION-PLAYBOOK.md`
§Naming: an action / user-invoked skill takes an action verb, and a sibling family orders
base-concept-first — the plugin's existing family is already `audit`, `audit-automation-gaps`,
`audit-instructions`, `audit-pass`, `audit-permission-grants`, `audit-prompting-postures`. `state`
is the discriminator against the `grants` sibling: grants are what you wrote, state is what is
actually in effect. `claude-config` survives the namespace-noun test that a narrower noun would fail.

**Standards grounding — cited by SECTION NAME, never by line number.** `PLUGIN-PHILOSOPHY.md`
§Cross-platform contract and §Prerequisites and failure behavior govern Phases 1 and 5;
§Two-lane convention posture governs the Phase 6 boundary; §Fresh-eyes checkpoints governs the
Phase 8 declaration; §Naming governs both skill names. `AGENTS.md` governs staging (explicit paths,
never `git add -A`). An earlier draft of this plan cited line ranges and **every one of them was
wrong within a day** — the file moved under them. Line-number citations into living files are
forbidden in this plan; grep the section heading instead.

### Phase 0: Discharge the fresh-docs mandate [DONE]

**Completed 2026-08-10 — output: [`phase0-fresh-docs.md`](phase0-fresh-docs.md).** Eleven facts
confirmed against pages fetched this session, five corrections to this plan, two open upstream
discrepancies, and three claims moved to *not stated* that must not ship as fact. The corrections
change downstream phases; the material ones are folded into the phase bodies below:

- **Phase 1** — managed policy is a plist domain, a Windows **registry hive**, a JSON file, **and** a
  `managed-settings.d/` drop-in directory, per OS. Not a jq-over-two-paths read. And
  `.claude/settings.local.json` resolves **through worktrees to the main checkout**, with three stated
  exceptions.
- **Phase 4** — `autoMode.classifyAllShell` (v2.1.193+) suspends **every** Bash/PowerShell allow rule
  when true, which inverts criterion 3's answer. No criterion covers it.
- **Criterion 2** — the `v2.1.142` gate is **not stated** on any governing page, and neither is the
  claim that `useAutoModeDuringPlan` is unread from shared project settings.
- **Criterion 6** — the `Write(path)` item needs re-deriving; the page describes a different mechanic
  (parameter-form rules on a tool's primary content field are ignored **and emit a startup warning**).
- **Phase 6** — the no-`allowManagedAutoModeRulesOnly` claim is now confirmed by the governing page and
  is no longer resting on an unverified research slice.

### Phase 0 (original brief, retained for the record)

`CLAUDE.md` names this non-negotiable and this work is squarely inside its scope: the plan edits a
plugin manifest and the skills' whole contract surface is documented harness behavior. Every upstream
fact currently in the Brief rests on one machine's 2026-08-09 capture, which the mandate does not
accept as a substitute. The Brief's "fetch at read time" constraint governs the **shipped skill's
runtime**; it does not discharge the **implementer's** obligation.

- Open `docs/OFFICIAL-DOCS.md`, WebFetch every page it indexes for permissions, permission modes,
  settings, server-managed settings, sandboxing, hooks, and auto-mode configuration, and cite each URL.
- Re-confirm from those fetched pages, not from recall or from this file: the version gates
  `v2.1.142` / `v2.1.207` / `v2.1.211`; the `autoMode` key set; the precedence order Phase 2 encodes;
  the `disableAutoMode` string-vs-boolean shape; and the claim that no `allowManagedAutoModeRulesOnly`
  exists.
- Any fact not confirmed from a page fetched during this phase is marked unverified in the phase that
  consumes it and carries a caveat per criterion 10.

**Sanity Check:** the phase's output file names one fetched URL per fact above; assert every version
gate constant appearing anywhere in the two new skills also appears in that file
(`comm -23` of the two sorted constant lists is empty).

### Phase 1: Walking skeleton — scope discovery across all five scopes [TODO]

The integration slice. Everything downstream reads what this produces.

- Create the skill directory following the sibling's exact topology:
  `plugins/claude-config/skills/audit-permission-state/{SKILL.md,reference/criteria.md,scripts/,evals/evals.json}`.
- `scripts/permission-state.sh` discovers and reads every settings scope: managed policy (read-only,
  per-platform paths), user (`~/.claude/settings.json`), project (`.claude/settings.json`), local
  (`.claude/settings.local.json`), and the **pre-v2.1.211 start-directory copy** as a distinct fifth
  member — acceptance criterion 7 requires it read alongside the repo-root copy because rules from
  both stay in effect.
- Emit one scope record per file: scope, absolute path, present/parsed, and the three rule arrays.
- Declare `jq` as **required for correctness** with a hard stop at the entry point, matching
  `permission-rule-check.sh:63-64` (`ERROR: jq required`, exit 2). Declare it in the plugin README.

- **Fixture seam is Phase 1 work, not an afterthought.** The sibling exposes only
  `PERMISSION_HYGIENE_FIXTURE_DIR`, which sets `ROOT` and therefore reaches project and local scopes
  only. This script needs **separate** overrides for the user-home, managed-policy, and
  start-directory roots, so every scope is testable without ever reading or writing the operator's
  real `~/.claude/`. No test may touch the real user home.
- **Managed-policy reader scope — DECIDED 2026-08-10: portable core plus declared optional platform
  legs.** Phase 0 correction 1 splits the managed scope into four sub-surfaces with different costs,
  so the reader is split the same way rather than being all-or-nothing:
  - **Portable core, always read, on every OS:** the per-OS `managed-settings.json` and its sibling
    `managed-settings.d/` drop-in directory.
  - **Declared optional platform integrations:** the Windows registry keys
    `HKLM\SOFTWARE\Policies\ClaudeCode` and `HKCU\SOFTWARE\Policies\ClaudeCode`, and the macOS
    `com.anthropic.claudecode` managed-preferences domain. Each is read where it is native and
    readable; where its tool is missing or the read fails it **warns visibly and skips that leg
    only**, preserving the portable core result. That is §Prerequisites' *required for an optional
    feature* class and §Cross-platform contract's *optional platform integrations must degrade
    visibly* clause — a declared classification, not an unexplained gap.
  - **Basis for splitting here rather than dropping the registry:** Phase 6's headline output is which
    managed intents are enforced versus loosenable. A Windows reader that checks only
    `%PROGRAMFILES%\ClaudeCode\managed-settings.json` does not under-report a registry-deployed
    policy — it reports *no managed policy deployed* while one is in force. That is a wrong finding on
    the plugin's primary platform, not a blind spot.
  - **Elevation is not required.** Measured 2026-08-10 on Windows 11, unelevated:
    `reg query "HKLM\SOFTWARE\Policies"` returns subkeys and exits 0. Recheck trigger: an unelevated
    `reg query` of that path starts returning `ERROR: Access is denied` — basis, only a live probe
    proves the ACL, and the plugin never elevates.
  - **Verification honesty, per §Cross-platform contract.** The Windows registry leg is verified
    empirically against a synthetic `HKCU` fixture key (no real policy is deployed on the development
    machine, so a synthetic key is the only available positive case). The macOS plist domain and the
    Linux paths **cannot** be verified from the development machine and ship with an honest
    manual-verification gap recorded in the skill. This applies to the fully-built option too — no
    option available here ships every leg verified.
  - **`managed-settings.d/` merge semantics are a decidability caveat, not an assertion.** The reader
    inventories and reads each drop-in file; any claim about how the drop-ins merge with each other or
    with the base file carries a named caveat unless a fetched page states the ordering.
  - Legacy `C:\ProgramData\ClaudeCode\managed-settings.json` is **never probed** — unsupported since
    v2.1.75, and reading it would report policy not in force (Phase 0 correction 2).

**Sanity Check:**

- Point the fixture seams at a tree carrying **all five** scopes, then assert each named scope appears
  exactly once: `grep -c '^user'` = 1, `^project` = 1, `^local` = 1, and `^startdir-local` = 1. A `≥2`
  count is not acceptable — it passes on project+local alone and leaves criterion 7's dedicated scope
  member entirely unverified.
- The managed scope is four sub-surfaces, so it gets a **per-surface** assertion instead of one row.
  Every leg emits a row on every OS — a non-native or unreadable leg emits an explicit
  `not-applicable` / `skipped` row rather than nothing, so the row count is deterministic per OS and a
  silently-missing leg is detectable: `grep -c '^managed file'` = 1, `^managed dropin` = 1,
  `^managed registry` = 1, `^managed plist` = 1. Asserting only an aggregate `^managed` row would pass
  with three of the four legs never attempted.
- Optional-leg degradation, per §Prerequisites: run on Windows with a stub `PATH` directory carrying
  every needed tool **except** `reg`; assert exit 0, a visible warning naming the registry leg, a
  `^managed registry ... skipped` row, and that the `^managed file` and `^managed dropin` rows are
  still emitted — the portable core survives the optional leg's absence.
- jq-absent behavior: create a stub directory containing every needed tool **except** `jq`, run with
  `PATH=<stub>`, assert exit 2 and `ERROR: jq required`. Do **not** use bare `PATH=` — measured, it
  yields `bash: command not found` and exit 127, because the interpreter itself becomes unresolvable,
  so the check would fail for a reason unrelated to jq.

### Phase 2: Merge and per-rule provenance [TODO]

Acceptance criterion 1.

- Compute the effective merged `allow` / `ask` / `deny` set from the Phase 1 scope records.
- Every merged rule carries `origin` (the winning scope) and `precedence_basis` — the documented
  mechanic the placement follows from. Basis is a per-rule field, not prose, because criterion 1
  requires each precedence claim to cite its mechanic.
- Per the Brief's decidability bound: anything resting on classifier judgment, runtime demotion state,
  or an open upstream discrepancy becomes a named caveat on the affected finding, never a silent drop.

**Sanity Check:** run against a fixture with a rule defined at two scopes; assert the output names
exactly one winner and that `grep -c 'precedence_basis'` equals the merged-rule count (no rule
without a basis).

### Phase 3: Auto-mode drop classification and entry diff [TODO]

Acceptance criterion 3, plus brainstorm candidate 4.

- Classify every allow rule auto mode drops on entry: blanket `Bash(*)` / `PowerShell(*)`, wildcarded
  interpreters, package-manager run commands, and **all `Agent` allow rules**.
- **Sharing the sibling's pattern vocabulary requires real refactoring — plan for it.**
  `permission-rule-check.sh` is self-executing (it scans and `exit 0`s at load), so it cannot be
  sourced, and the repo's no-duplication rule forecloses copying the `_interp` block. Extract the
  pattern definitions into a shared, side-effect-free file both detectors source. That extraction
  edits a **Phase 9-owned** file, so it is sequenced with Phase 9 and destroys the claim that the two
  are independent — see the execution shape.
- **Criterion 8 binds this CLI read too.** The oracle's `claude --debug-file … -p …` invocation gets
  the same defensive contract as the `autoMode` lane: never trust exit status, tolerate a missing or
  empty capture, and never infer an empty drop set from a capture that produced no drop lines.
- Render the entry diff: effective state before and after the drop, per rule, with the drop reason.

- **Debug-channel oracle — opt-in, explicitly priced.** Behind a flag that states the cost *before*
  spawning anything, run `claude --debug-file <scratch-path> -p "<minimal prompt>"` and parse the
  harness's own drop narration — `Ignoring dangerous permission <rule> from <absolute path> (bypasses
  classifier)`, closed by a `Removing N allow rule(s) from source '<destination>'` summary. Cross-check
  it against this phase's prediction; **report disagreement in either direction as a finding.** The
  prediction stays the default read path — the oracle costs a session spawn in the consumer's
  environment and parses undocumented `[DEBUG]` strings with no stability contract. Never spawn
  without the flag; never spawn silently. Write the capture to a scratch path, never to
  `~/.claude/debug/`. Evidence and bounds:
  `.work/permission-model/EXPERIMENT-debug-channel-merge-narration.md`.

**Sanity Check:**

- Feed a fixture containing one rule of each of the four classes; assert all four appear in the
  dropped set and that a narrow exact rule (`Bash(git status)`) does not.
- Oracle off by default: run the phase with no flag and assert zero `claude` child processes and no
  file created under the scratch path.
- Oracle on: assert the run prints the cost notice before the spawn, and that the count of
  `AGREES`/`DIVERGES` lines **equals the compared-rule count exactly** — not `≥ 1`, which passes on a
  single line while the per-rule guarantee is unmet.
- Oracle on with the drop strings absent (simulate with a fixture capture): the run reports the oracle
  as unavailable and falls back to the prediction rather than reporting an empty drop set.

### Phase 4: Permission-plane lints [TODO]

Acceptance criteria 2, 5, 6.

- **Criterion 2 — both dead-config traps at their two distinct gates, reported separately:**
  `autoMode.*` ignored in project and local settings (local also read before v2.1.207), and
  `defaultMode: "auto"` ignored in project and local settings (project could set it before v2.1.142).
  `useAutoModeDuringPlan` is covered as a third, because it is not read from shared project settings.
- **Criterion 5** — `disableAutoMode` typed as a boolean rather than the string `"disable"`, in any
  scope; it is not managed-only.
- **Criterion 6** — allow rules that cannot match: doubled-backslash Windows paths, unanchored allow
  globs, `Write(path)`-shaped rules that are accepted but never consulted, and `:*` used anywhere but
  at pattern end.

**Sanity Check:** a fixture per check; assert each fires exactly once and that criterion 2's two gates
emit two separately-labeled findings rather than one merged finding
(`grep -c '\[C2-autoMode\]'` = 1 and `grep -c '\[C2-defaultMode\]'` = 1).

### Phase 5: `autoMode`-block lane [TODO]

Acceptance criteria 4 and 8, plus brainstorm candidates 1, 2, 3.

- **Criterion 4** — `$defaults` omission per `autoMode` section, stating which built-in rule list the
  omission discards. Probe and diff via `claude auto-mode defaults`; never infer from a version number
  (the changelog does not track the content of the shipped lists — zero matches across all 359
  releases).
- **Criterion 8 — the measured defensive contract, every item, each already reconfirmed on 2.1.225:**
  never a strict JSON parser; tolerate a **missing** key rather than an empty array (`defaults --label`
  omits a non-matching key entirely); split a rule label at the first `[`, not the first `:`; never
  trust exit status. A run producing no usable output reports that fact and never claims success.
- **Candidate 2** — intra-`autoMode` contradiction lint: allow vs `soft_deny`, `hard_deny` vs allow.
- **Candidate 3** — dead / unactionable rule lint: rules shadowed by an earlier `hard_deny`, and prose
  entries with no observable predicate. **Not a duplicate of criterion 6** — criterion 6 is syntactic
  non-matching on the `permissions.allow` plane; this is semantic shadowing inside the `autoMode`
  block. Different surface, different inputs. The prose half either states a mechanical basis or
  routes to `critique`, which owns that judgment.
- **Candidate 1** — surface `claude auto-mode critique` as its own action, wrapped in truncation and
  empty-output detection with a plain "critique returned nothing; run it yourself" surface. Wrapped,
  never replaced: it owns the semantic judgment.
- **Runtime, decided and measured** (`.work/permission-model/EXPERIMENT-nonstrict-json-runtime.md`):
  Python 3 is **required for an optional feature** — this lane only. Absent → warn visibly, skip this
  lane, continue with the documented reduced result. Pure POSIX was tested and cannot substitute: the
  offending byte is a raw line feed inside a string value, which no line-oriented filter can
  distinguish from the pretty-printer's structural newlines. Node is an equally valid host and is
  deliberately not adopted — a second optional runtime doubles the declaration surface for one feature.

**Sanity Check:**

- Parse a **checked-in fixture** carrying a raw line feed inside a string value: the shipped reader
  returns the four `autoMode` sections while `jq -e .` on the same fixture exits non-zero. Do **not**
  run this against `claude auto-mode config` on the developer's machine — the Brief records the defect
  as machine-conditional, so on a clean config `jq` exits 0 and the check fails while the skill is
  behaving correctly. The check must exercise shipped code against a fixture, not the operator's
  environment.
- The other three measured defects each get their own fixture assertion, because criterion 8 names
  four and only one was covered: a **missing** key (not an empty array) is tolerated; a label carrying
  a bracketed annotation splits at the first `[`, not the first `:`; and a run that exits 0 with empty
  output is reported as "produced no usable output" rather than as success.
- With Python unreachable, the skill exits 0, prints a visible skip notice naming the lane, and still
  emits Phase 2 merge output — assert both the notice string and the merge rows in one run.

### Phase 6: Managed-policy conformance report [TODO]

Brainstorm candidate 6 — the highest-value residue of the ecosystem sweep.

- Read the deployed managed policy (read-only always; a plugin can never author managed policy —
  admin-write OS paths or a claude.ai Owner role) and diff it against every scope beneath it.
- Report which managed intents are genuinely enforced versus silently loosenable. The load-bearing
  claim: **there is no `allowManagedAutoModeRulesOnly`** — permissions, hooks, MCP,
  sandbox-filesystem, and sandbox-network each got an exclusivity lock and auto mode did not, so
  managed `autoMode` rules *can* be loosened by a developer and only `permissions.deny` in managed
  settings is unoverridable.
- **That claim is NOT independently verified and must not ship as "measured".** It originates in the
  `managed-policy` research slice, and the Brief's own `### Captured assumptions` records that only
  `permissions-core` received independent adversarial verification — the other four are cross-checked
  against each other only. Phase 0 re-confirms it from a fetched page. Until it does, the phase's
  headline finding carries an explicit caveat naming its provenance. A whole phase resting on an
  unverified slice with no caveat is exactly the failure criterion 10 exists to prevent.
- **Two-lane posture (`PLUGIN-PHILOSOPHY.md` §Two-lane convention posture), decided:** this phase ships **no security floor
  of its own**. It reports what the consumer's own policy does and does not achieve — it never
  prescribes which rules a policy should contain. That keeps it lane-neutral by construction and out
  of the lane-1/lane-2 question entirely. The owed re-derivation of
  `audit/reference/required-permissions.md` toward lane 2 is a real debt but belongs to the `audit`
  skill that ships it, not to this plan.

**Sanity Check:** against a fixture managed policy containing one `permissions.deny` rule and one
`autoMode` rule, assert the report marks the deny rule enforced and the `autoMode` rule loosenable.
For lane-neutrality, assert the **positive** property: every rule string appearing in the report also
appears in the fixture policy or in a scope file beneath it (set difference is empty). Do not assert
`grep -c 'RECOMMEND ADD' = 0` — nothing emits that string, so it passes unconditionally and proves
nothing about the guarantee it claims to protect.

### Phase 7: Authoring lane — `claude-config:draft-auto-mode-rules` [TODO]

Brainstorm candidate 7. Drafts an `autoMode` block from an interview plus the Phase 2 merge, prints it
to stdout, human pastes. **No write, no persistent state**, so it does not trip the Brief's
plugin-extraction recheck trigger.

This is a **second sibling skill**, not an action on `audit-permission-state`: §Naming binds a skill
name to its KIND, and an `audit-*` skill hosting a `draft` action would make its own name untrue.
**Admitted 2026-08-09**, which amends the Brief's TLDR from one new skill to two and adds a second
listing-budget entry that Phase 8 must state rather than assume.

- **History source — DECIDED 2026-08-10: dropped.** "The repo's observed prompt and denial history"
  was not a location, and an unnamed read surface in a skill shipped to consumers is unreviewable. The
  draft is driven by the interview plus the Phase 2 merge alone. This removes a read surface and a
  second dependency on the priced oracle; binding it to the Phase 3 debug capture was the alternative
  and was not taken. The skill must not acquire a history input without re-opening this decision.

**Sanity Check:** a skill is a markdown surface, not a process, so nothing is piped from it. Assert
instead against the deterministic script the skill drives: run it on a fixture and pipe **its** stdout
through a strict parser (`jq -e .`), asserting exit 0 — strict is correct here because we author this
output, and the non-strict allowance exists only for the CLI's malformed emission. This keeps Phase 7
free of the Python dependency that Phase 5 scopes to one optional lane. Zero-writes is covered by
Phase 8's sweep, which must include this skill.

### Phase 8: Cross-cutting close [TODO]

- **Criterion 9 — no writes, any scope, any flag.** Assert mechanically, not by inspection.
- **Criterion 10** — every finding whose basis is an open upstream discrepancy carries that
  discrepancy as a named caveat. The two live ones are #83766 and #42797 (`permissions.ask` patterns
  auto-approved under `defaultMode: auto`, contradicting current documented behavior).
- **Fresh-context delegation directive, decided — in the enforced machine-readable form.**
  `PLUGIN-PHILOSOPHY.md` §Fresh-eyes checkpoints requires a skill step whose output judges work the
  same context produced to delegate to a fresh-context subagent or carry a greppable exemption. These
  skills read consumer configuration and run deterministic scripts over it; no step judges output they
  authored. Ship the exemption in the form `skill-quality` Check 21 actually enforces —
  `<!-- fresh-eyes-exempt: <class> -- <reason> -->` with class from
  `deterministic-gate|external-input|deferred` — and **class `external-input`**, since the judged
  material is the consumer's configuration, not our own output. **Both** skills carry one; a prose
  paragraph containing the words does not satisfy the checker and would error.
- **Criterion 12** — run `skill-quality:check listing-budget`; state the resulting cost rather than
  assuming it. With Phase 7 gated in, state the two-entry cost.
- Register as an `audit-pass` lane per that skill's documented lane rule; add `evals/evals.json`;
  update `plugins/claude-config/.claude-plugin/plugin.json` (`version`, `description`).
- **Frontmatter `name:` — verify at implementation time, do not assume.** At `main`
  (`30be2a0b`) all 191 skills still carry `name:`. A branch dropping it repo-wide
  (`refactor/drop-redundant-skill-name-frontmatter`) exists but is **not merged**. Match whatever
  `main` holds when the branch is cut; re-check rather than copying this sentence's answer.

**Sanity Check:**

- Write-assertion, **oracle explicitly ON for this run**: checksum the whole fixture tree **and a
  fixture `HOME`** before and after running every action of **both** skills, and assert zero changes
  in either. Running only the default configuration proves nothing about criterion 9, because the
  default disables the one code path that spawns a process capable of writing outside the tree.
- `skill-quality:check` returns PASS for **both** `audit-permission-state` and
  `draft-auto-mode-rules`, and its Check 21 passes on each — that is the real verification of the
  fresh-eyes declaration; a `grep` for the words matches ordinary prose and certifies nothing.
- Version bump: assert `plugins/claude-config/.claude-plugin/plugin.json` `version` differs from its
  value at the branch point, and that its `description` names both new skills.

### Phase 9: existing-check scope widening and the shared extractions [TODO]

Acceptance criterion 11, the Brief's **second** widening, and the two extractions later phases consume.
**Not independent** — see the execution shape; it shares `plugin.json` with Phase 8 and owns the file
Phase 3's pattern extraction touches.

- The criteria file and the detector scan project and local settings only, so a user-global
  interpreter-wildcard rule is invisible to check P1. Add the user-global scope.
- **Build the fixture-home seam first — it does not exist.** The detector's only override is
  `PERMISSION_HYGIENE_FIXTURE_DIR`, which sets `ROOT`, and the scans read `$ROOT/.claude/settings.json`
  and `$ROOT/.claude/settings.local.json` only; the test harness passes exactly that one variable.
  There is no way to point it at a fake user home, so user-global cannot be tested at all until a
  second override exists. Adding it **is** the phase's first work item; without it the only way to
  exercise the new scope is to read the operator's real `~/.claude/settings.json`, which no test may do.
- **Extract the shared pattern vocabulary here**, side-effect-free, so Phase 3 can source it. The
  current file self-executes and `exit 0`s at load, so it cannot be sourced as it stands.

- **The Brief's second widening — DECIDED 2026-08-10: `claude-config:audit`'s settings scan gains the
  start-directory `settings.local.json` copy.** `check-structure.sh` reads the repository-root copy
  only. The settings page states the harness still reads a `.claude/settings.local.json` an earlier
  version left in the starting directory, and that permission rules from **both** files stay in
  effect — so a rule set nobody audits is live. This is the same criterion-7 surface
  `audit-permission-state` covers, applied in place to the existing check. It rides Phase 8's single
  `plugin.json` bump like the P1 widening does.

- **Shared managed-scope enumeration — DECIDED 2026-08-10: extract, do not write a third copy.**
  Approving Phase 1's managed reader makes this the **third** in-repo component enumerating managed
  paths, after `claude-config:audit/scripts/check-structure.sh` (per-OS JSON file + `managed-settings.d/`,
  test seam `SETTINGS_AUDIT_MANAGED_PATH`) and `claude-memory:stateless/scripts/scope-report.sh`
  (file only; registry flagged, deliberately not read). §Convention registry binds a cross-plugin
  convention to an owner doc **before** a second adopter, and we are already past two.
  - Plugin-form isolation forbids a runtime reach-out across plugin roots, so the repo's established
    mechanism is a byte-identical copy at the same path-within-plugin, plus a dedicated sync/drift
    check, registered in `scripts/cross-plugin-source-registry.txt`. Follow that mechanism rather than
    inventing a second one — an unregistered identical cluster is exactly what
    `check-cross-plugin-source-drift.sh` exists to flag.
  - Scope the shared source to **path enumeration and OS detection only**. Presentation, redaction
    posture, and each caller's existing output stay with the caller: `check-structure.sh` deliberately
    reports managed policy as counts rather than values, and `scope-report.sh` deliberately reports
    presence only. Migrating either one's *output* is not in this plan.
  - **Blast radius to state, not discover later:** this edits a second plugin (`claude-memory`), which
    owes its own version bump and CHANGELOG entry independent of `claude-config`'s.

**Sanity Check:**

- With the new fixture-home seam pointed at a fake home containing one interpreter-wildcard rule,
  assert exactly one P1 finding naming that file; assert the finding does **not** appear when the seam
  is unset (proving the fixture, not the real home, produced it); assert
  `scripts/permission-rule-check.test.sh` still passes.
- Second widening: with a fixture tree carrying a start-directory `.claude/settings.local.json` that
  the repository root does not carry, assert `check-structure.sh` emits a row naming that file, and
  that its existing tests still pass. Assert the row is **absent** on a fixture with no start-directory
  copy, so the check cannot pass by always emitting it.
- Extractions: `bash -n` plus a source-and-return test proves the extracted files are side-effect-free
  (sourcing them runs nothing and exits nothing); `scripts/check-cross-plugin-source-drift.sh --check`
  exits 0 with the new cluster registered; and deliberately perturbing one copy makes it exit non-zero,
  proving the drift check actually covers the new cluster rather than silently ignoring it.

### The Brief's second scope-widening — RESOLVED 2026-08-10

The Brief commits twice to widening **two** existing checks (`### Constraints` → Packaging: "plus
in-place scope widening of two existing checks"; and the TLDR), and only P1 was ever named. The
operator resolved it rather than the plan guessing it: the second is **`claude-config:audit`'s
settings-file scan**, widened to the pre-v2.1.211 start-directory `settings.local.json` copy. It is a
Phase 9 work item with its own sanity check. The alternative — striking "two" from the Brief and
shipping one widening — was offered and not taken.

## Blast radius

**MEDIUM-HIGH.** A new component shipped from a marketplace consumed downstream, plus in-place
behavior changes to **two** existing checks (Phase 9) that widen what they flag — consumers will see
new findings on unchanged repos. Phase 9's shared managed-scope extraction also edits a **second
plugin** (`claude-memory`), which owes its own version bump and CHANGELOG entry. Mitigated by:
report-only throughout (criterion 9), no consumer writes under any flag, the managed tier read-only by
construction, and the extraction scoped to path enumeration so no caller's existing output changes.
The genuinely irreversible surface is the published skill name, which is why naming was derived
against §Naming rather than chosen.

## Stress-test summary

Fresh-context reviewer dispatched 2026-08-09 with the rationale withheld. **19 findings, 2 CRITICAL.
Every finding was independently re-verified against the repository before any edit; all 19 held.**
No finding was rejected.

The two CRITICALs were factual, not stylistic, and both invalidated premises this plan was resting on:

1. **Three load-bearing premises were stale.** PR #2089 is **merged**; the `auto-mode-config` row is
   already in `docs/OFFICIAL-DOCS.md`; `main` is `a013d204`, not `30be2a0b`; and the frontmatter
   `name:` refactor **has merged**, so copying the sibling's frontmatter would re-introduce a field
   `main` deliberately removed. The Brief's Q12 gate was being held open on shipped work.
2. **The whole topic slice is untracked on a spent branch** and absent from `main`. Following the
   handoff's own instruction — cut a branch from `main` — would produce a worktree with no plan in it.

The remaining seventeen clustered into four honest weaknesses, all now corrected in place:

- **Sanity checks that could not fail or could not run.** `grep -c 'RECOMMEND ADD' = 0` asserted a
  string nothing emits; `PATH= bash` yields exit 127 (`bash: command not found`), never the exit 2 it
  claimed to test; Phase 5's headline check ran against the operator's live config, which the Brief
  itself calls machine-conditional, so it would fail on a clean machine while the code was correct;
  Phase 7 piped a markdown skill into a JSON parser; a `≥2` scope count passed without ever asserting
  the two novel scopes; a `grep` for "fresh-eyes" matched prose while the real checker enforces a
  strict directive form.
- **A parallel wave built on false file-disjointness.** Phases 4, 5 and 6 all write the same
  `criteria.md` and `SKILL.md`; Phases 8 and 9 collide on `plugin.json`. The plan is now sequential,
  and Phase 9 moved early because it owns seams the earlier phases need.
- **Governance skipped or mis-cited.** The `CLAUDE.md` fresh-docs mandate had no step at all — now
  Phase 0. Every `PLUGIN-PHILOSOPHY.md` line-range citation pointed at the wrong section within a day;
  citations are now by section name, and line numbers are forbidden in this plan.
- **Coverage gaps.** Criterion 8 binds *every* CLI read but the oracle's new CLI read had no
  defensive contract and 3 of its 4 measured defects had no check; criterion 9's write assertion ran
  only with the risky path disabled; the Brief's commitment to widen **two** existing checks has only
  one assigned, now flagged OPEN rather than guessed.

One item the reviewer explicitly declined to assert: whether a `-p` oracle session writes transcript
files outside the scratch path. It is unverified, not a finding — carried into Open questions.

## Execution shape

Ten phases, 0 through 9.

**Corrected after review: there is no parallel-safe set. This plan is sequential.**

The earlier draft claimed Phases 4, 5 and 6 were file-disjoint "own criteria rows, own scripts". They
are not: criteria rows are not separate files — the sibling and this plan both put every check in one
`reference/criteria.md` — and Phase 5's `critique` action and Phase 6's report are both new actions in
the single `SKILL.md`. All three write the same two files. Phase 9 was likewise called "zero file
overlap", but Phase 8 bumps `plugins/claude-config/.claude-plugin/plugin.json` and Phase 9 is a
behavior change in the same plugin that must ride the same bump — and Phase 9 now also owns the
pattern extraction Phase 3 consumes.

| Order | Phase | Gated by |
|---|---|---|
| 1 | 0 | — (fresh-docs mandate; everything downstream cites it) |
| 2 | 9 | 0. Moved early: it owns the fixture-home seam, the extracted pattern vocabulary, and the shared managed-scope enumeration that Phases 1 and 3 consume. |
| 3 | 1 | 9 (fixture seams) |
| 4 | 2 | 1 |
| 5 | 3 | 2, 9 (pattern vocabulary) |
| 6 | 4 | 3 (shares the drop vocabulary) |
| 7 | 5 | 2 |
| 8 | 6 | 2 |
| 9 | 7 | 2 |
| 10 | 8 | all — it measures the finished surface and owns the single version bump |

| Phase | Surface | Basis |
|---|---|---|
| 0 | Main session | Fetch-and-cite judgment; its output is the citation base for everything after. |
| 9, 1, 2, 3 | Main session | Seams, merge, and precedence basis are the contract. |
| 4, 5, 6 | Main session, sequential | They share `criteria.md` and `SKILL.md`; a worker fan-out would collide. |
| 7 | Main session | New public surface; naming and scope judgment. |
| 8 | Main session | Measures and closes. |

| Phase | Surface | Basis |
|---|---|---|
| 1, 2, 3 | Main session | Judgment-heavy; the merge and precedence basis are the contract. |
| 4, 5, 6 | Sub-agent worker (if used) | File-disjoint, criteria-row shaped, mechanical once the merge exists. |
| 7 | Main session | New public surface; naming and scope judgment. |
| 8 | Main session | Measures and closes; must see everything. |
| 9 | Sub-agent worker or main | Fully independent, small, well-fenced. |

**Cost note:** no parallel wave survives the file-overlap check, so there is no agent-count tradeoff to
offer. Sequential is the shape, not a fallback from one.

**Sub-topic promotion watch:** Phases 5 and 6 each carry ≥5 distinct work items and could earn their
own topic slice. Promote if either exceeds ~300 LOC delta or grows sub-phases.

## Open questions

All three approval-round questions are resolved (2026-08-09):

1. **Debug-channel oracle — SHIP IT, opt-in and explicitly priced.** Folded into Phase 3 with its own
   four sanity checks. The prediction remains the default read path.
2. **Phase 7 — IN.** Ships as the second sibling skill `claude-config:draft-auto-mode-rules`.
3. **Fresh-context plan reviewer — dispatched** at the user's explicit request.

Remaining genuinely open, carried into implementation:

- **Scopes absent from the oracle capture were not disproved.** No `projectSettings` line appeared
  because this repository's `.claude/settings.json` carries no `permissions` key; no `policySettings`
  line appeared because no managed policy is deployed on the probe machine. Re-probe on a
  managed-policy machine before claiming Phase 6 coverage from the oracle.
- **What governs whether a `-p` probe session is in auto mode** was not isolated, and it determines
  whether the oracle emits drop lines at all. Phase 3's fallback sanity check covers the failure, but
  the mechanic is unknown.
- **The `[DEBUG]` string format** carries no stability contract; the recheck trigger is recorded under
  `### Recheck triggers`.
- **What a `-p` oracle session writes outside the scratch path is unverified.** It plausibly writes a
  transcript, project state, or telemetry under the user's config directory. Criterion 9 forbids
  writes to consumer *settings*, and a transcript is not a settings file, but the boundary was never
  measured. Measure it in Phase 3 before the oracle ships, and state the result in the flag's cost
  notice — a feature that spawns a session must be honest about everything it leaves behind.
- **Whether `managed-settings.d/` drop-ins have a stated merge order.** Phase 0's fetched pages
  enumerate the directory but no ordering was recorded. Until a page states it, the reader inventories
  the drop-ins and any merged-result claim carries a decidability caveat.

## Handoff to implementation

### User-approval gates

- Any proposal to add a `--fix` mode, or any consumer write in any scope, stops and asks — the Brief
  puts both out of scope and criterion 9 asserts against them.
- Any change that would make the debug-channel oracle spawn by default, rather than behind its
  explicit priced flag, stops and asks. The opt-in *is* the approved shape.
- Promoting Phase 5 or Phase 6 to its own topic slice (the sub-topic watch below) stops and asks.

### Execution shape (`[EXEC-SHAPE]` tagged)

The wave table, the routing table, and the sequential fallback above.

### Mechanical work

- **This slice is not durable yet — fix before anything else.** `docs/topics/permission-model/` is
  **untracked** in a worktree sitting on `docs/index-auto-mode-config`, whose PR **#2089 merged**
  (`2026-08-09T17:31:08Z`) carrying only the `OFFICIAL-DOCS.md` row. The branch is spent and nothing
  in this slice is on `main` (`git ls-tree -r --name-only main | grep topics/permission-model` →
  no matches). Cut `feat/audit-permission-state` from current `origin/main` — untracked files carry
  across the switch — and commit the slice before any implementation work begins.
- **Branch:** `feat/audit-permission-state`, from current `origin/main`. The existing worktree is 21
  commits behind. Do **not** reuse `docs/index-auto-mode-config`; it is merged.
- **Frontmatter `name:` is GONE on `main` — do not copy the sibling's.** `main` is at `a013d204`;
  `git grep -l '^name:' main -- '*/SKILL.md'` returns only `vendor/` files, so
  `refactor/drop-redundant-skill-name-frontmatter` **has merged**. Both new skills ship without a
  frontmatter `name`. Re-verify at branch-cut time rather than trusting this sentence.
- Commit at phase boundaries; stage explicit paths only, never `git add -A` (`AGENTS.md`).
- PR body must satisfy `.github/workflows/pr-issue-linkage.yml`: a closing keyword or the literal
  `No linked issue`, plus a non-empty `## Related` section.
