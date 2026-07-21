# github-plugin-candidates

## Brief

### TLDR

New `github` plugin (category `operations`): one vendor-bundle plugin through which agents audit,
review, advise, and hand-hold GitHub setup and management for the authenticated user across the
GitHub settings/admin plane — consistency, drift, standards conformance, cost control. Verb skills
with area arguments; zero vendored GitHub knowledge (runtime fetch + pointers); `gh`-first mechanism
ladder with an opt-in browser-automation offer; propose-only writes routed through consumer-declared
change-routing config.

### Goal

Any consumer, on any machine/repo/org, enables `github` and gets: on-demand audits and guidance over
every area in the coverage matrix below, grounded in live `gh`/API state and current official GitHub
docs, with mutations user-in-loop and routed per the consumer's declared posture (IaC-first,
guided-apply, or propose-only).

### Locked decisions

| # | Decision |
|---|---|
| D1 | Job: audit + review + advise + guided setup/management ("hold the user's hand"); proactive suggestions in-session. |
| D2 | One `github` vendor-bundle plugin (playbook §Organization sanctioned shape); whole-plugin enable/disable. Category `operations`. |
| D3 | Skill surface: few verb skills with area arguments (≈ `audit`, `advise`, `setup`, guarded mutation action). Never per-area skills — areas are arguments, matrix in plugin docs. |
| D4 | Knowledge posture: zero vendored/copied GitHub content. Runtime fetch of official GitHub docs, live state via `gh` CLI / `gh api`, pointers not copies. Unfamiliar areas researched on demand. |
| D5 | Mechanism ladder: `gh` (user's own auth) → `gh api` → OFFER browser automation (presence-gated on claude-in-chrome/playwright, confirm-gated, cross-cutting capability not a skill) → guided manual steps + settings deep-link. |
| D6 | Write posture: propose-only default. Consumer config declares routing per surface class: `propose` / `guided-apply` / declared handoff target. IaC-tool-agnostic. All mutation user-in-loop. |
| D7 | Depth heatmap: primary tier = billing/licensing monitoring; security posture (authentication, advanced security, PAT/app/OAuth policy); rulesets + repo-settings drift; actions policy. All other matrix areas represented and reachable via the dynamic method. |
| D8 | Self-drive: V1 on-demand + composable with consumer-side schedulers (`/schedule`, `/loop`, cron routines). Plugin-owned proactive machinery deferred (see out-of-scope). |
| D9 | Boundaries: workflow-file lint stays `actionlint`; commit/PR delivery stays `source-control`; local fleet audit stays `repo-fleet-hygiene`. This plugin owns the GitHub-side settings/admin plane. |
| D10 | Audience: public third-party consumers by design (e.g. an employer org with its own conventions). Melodic Software's own posture (Pulumi `github-iac`, IaC-first) is one consumer profile, never a default. |

### Coverage matrix (user's original list — everything represented)

Rulesets; custom properties; billing and licensing (monitoring, budgets, alerts, usage — keep costs
down); security model (organization, repository roles, member privileges); Codespaces; cloud
sandboxes; projects, issue types, issue fields, templates; Actions (policies, runners, runner
groups, custom images, caches, OIDC); webhooks; discussions; packages; pages; hosted compute
networking; authentication security; advanced security (configurations, global settings); code
quality; deploy keys; compliance; verified and approved domains; secrets and variables (Actions,
agents, Codespaces, Dependabot, private registries); GitHub Apps; OAuth app policy; personal access
tokens (settings, active tokens, pending requests); scheduled reminders; archive logs (sponsorship
log, audit log); deleted repositories; developer settings (OAuth Apps, GitHub Apps, publisher
verification).

### Constraints

- Full conformance with `docs/PLUGIN-PHILOSOPHY.md` and `docs/MIGRATION-PLAYBOOK.md`: design
  boundary (repo/dir/user/machine/company-agnostic), two-lane convention posture,
  convention-resolution ladder, extensibility contract v2.1 seams, setup contract, verb contract
  (`audit`/`scan` read-only; mutation only behind explicit override), naming grammar.
- `melodic-software/standards` engineering philosophy applies (explicit over implicit, fail fast,
  idempotency, cross-platform, one mechanism per concern, reference-don't-duplicate).
- No vendored upstream content anywhere in the plugin (D4) — the reference-dont-duplicate /
  point-don't-copy rule is a hard constraint, not a preference.
- Cross-plugin references (playwright, source-control, etc.) presence-gated with documented
  fallback; no bare cross-plugin reference.
- Fresh-docs mandate at build time: re-fetch plugin-platform docs before implementation.
- Pre-publish gates: per-plugin migration gate + plugin-acceptance security review. Heavy review
  items: user-auth token scopes, browser automation over an authenticated GitHub session, egress.

### Acceptance criteria

- `claude plugin validate .` passes; repo plugin contract tests pass; CI green.
- Every coverage-matrix area reachable through a documented skill invocation (e.g.
  `/github:audit <area>`) and produces grounded findings or guidance without any vendored area
  knowledge.
- Bare `audit`/`advise` invocations perform zero mutations; mutation paths require explicit
  override AND resolve routing via consumer config; unconfigured consumers get propose-only.
- Browser automation never auto-fires: offered, confirm-gated, degrades to guided manual steps
  when integrations absent.
- No hardcoded org/repo/path/publisher assumptions (mechanical agnostic-conformance checks pass).
- Skill listing surface stays small (verb skills only); descriptions carry the trigger vocabulary
  for the admin-plane job.
- Security review record on file before marketplace publish.

### Captured assumptions

- `gh` CLI is the primary prerequisite; users authenticate it themselves (setup checks, never
  stores credentials).
- Coverage-by-method is acceptable for non-primary areas: quality of non-primary-area audits
  depends on runtime research, not shipped depth.
- One-bundle listing cost accepted (user decision) in exchange for single on/off switch.

### Out-of-scope (deferred with triggers)

- Plugin-owned proactive/scheduled machinery (hooks that nag, bundled schedules, SessionStart
  surface) — trigger: recurring pattern observed in on-demand usage.
- GitHub Enterprise Server (self-hosted) support — trigger: first consumer on GHES; design keeps
  host-agnostic `gh` usage where free.
- Non-GitHub forges — inherently out (plugin declares narrower boundary at the coupling site per
  philosophy allowance).

### Deferred questions

| Question | Arbiter |
|---|---|
| Per-area reachability map: which areas are `gh`-native vs `gh api` vs UI-only | `/discovery:research` → `/planning:plan` |
| Consumer config schema: `.claude/github/**` vs `.claude/github.md`, keys, surface classes, layering | `/planning:plan` |
| Exact skill set, names, descriptions/trigger phrases, `userConfig` keys | `/planning:plan` |
| Mutation surfacing: dedicated guarded skill vs override argument on `audit`/`advise` | `/planning:plan` |
| Browser-automation gating mechanics (claude-in-chrome vs playwright seam, offer wording) | `/planning:plan` |
| Primary-tier recipe depth (what "deepest treatment" ships as, per area) | `/planning:plan` |
| Any routing surface class that would change acceptance criteria (new write channel kinds) | USER-RESERVED |

## Plan

### Standards grounding

Loaded this session for the surfaces this plan touches:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Plugin design | `docs/PLUGIN-PHILOSOPHY.md` — design boundary, naming + verb contract, native-first, component stances, two-lane posture, config ownership, setup contract, prerequisites/failure behavior, fresh-eyes checkpoints | team (this repo) |
| Migration/release | `docs/MIGRATION-PLAYBOOK.md` — §Organization, §Naming, §Extensibility contract v2.1, §Convention-resolution ladder, §Setup, §Evals, §Plugin-form caveats, §Per-plugin migration gate, §Plugin-acceptance security review, §Local development loop | team (this repo) |
| Consumer config | `docs/conventions/consumer-config-layering/README.md` — layers, merge semantics, overlay/gitignore, Implementers table | team (this repo) |
| Seam phrasing | `docs/conventions/seam-phrasing/README.md` — gate + fallback + ownership framing | team (this repo) |
| Engineering philosophy | `melodic-software/standards` `conventions/engineering/engineering-philosophy.md` — bound via the Brief's constraints; not re-pulled this session (no code surfaces authored at plan time) | org |

### Deferred-question resolutions (briefed delegation — arbiter `/planning:plan`)

The Brief's deferred-questions table delegates these to this plan. Resolutions, with basis:

1. **Skill set = exactly three skills: `audit`, `advise`, `setup`.**
   - `/github:audit <area…> [--apply]` — read-only findings over one, several, or all coverage-matrix
     areas: current-state review, drift vs declared conventions, standards conformance, cost signals.
     Trigger vocabulary: "audit my GitHub org", "check billing", "review repo settings", "GitHub
     drift", "are my rulesets consistent".
   - `/github:advise <topic> [--apply]` — guidance and hand-holding: "how should I configure X",
     "help me set up Y", "walk me through Z", proactive recommendations. Distinct discovery intent
     from `audit` (design/forward-looking vs current-state/backward-looking), which is the
     playbook's split criterion.
   - `/github:setup` — the uniform setup contract: `disable-model-invocation: true`, `check` +
     `apply` actions (details in Phase 2).
   - Areas are arguments routed via a bundled area router (`reference/areas.md`); never per-area
     skills (D3). `advise` is a new verb for the marketplace verb table — read-only advisory;
     declared in the plugin README at the coupling site.
2. **Mutation surfacing = `--apply` override argument on `audit` and `advise`; no fourth skill.**
   Basis: the philosophy's verb contract explicitly sanctions "an autofix argument" as the mutation
   override for `audit`; mutation has no independent discovery intent (users say "fix that" about a
   finding just produced, mid-session — they do not reach for a mutation skill cold); D2/D3 lock the
   listing-budget rationale. `--apply` resolves through change routing (below); bare invocations
   remain zero-mutation (acceptance criterion).
3. **Consumer config = folder form `.claude/github/`** with two files:
   - `routing.yaml` — change routing (structured): `default: propose|guided-apply|handoff` plus
     optional per-area overrides `areas.<area-key>: …`; `handoff` carries a free-text
     `target`/`instructions` block describing the consumer's change channel (IaC repo, ticket queue,
     admin team — tool-agnostic per D6). Per-key override merge semantics, declared in the schema
     doc as the layering contract requires.
   - `conventions.md` — prose posture (concatenating): the consumer's GitHub standards, baselines,
     naming/policy conventions that audits compare against.
   - **Scope axis (repo / org / enterprise).** The admin plane is mostly org/enterprise-scoped
     while team config resolves from the CWD repo, so routing keys are scope-qualified:
     `repo:`, `org.<login>:`, `enterprise.<slug>:` blocks, each holding `default` + `areas.*`
     overrides. Target resolution rule (convention-resolution ladder applied): explicit invocation
     argument → else repo-scoped areas target the CWD repo → else org/enterprise scope is **asked
     when ambiguous — never silently inferred from an incidental CWD remote for any `--apply`
     path** (read-only audits may propose an inferred target but must name the inference). A scope
     block absent from config resolves to `propose`. Org/enterprise posture that follows the
     operator across repos belongs naturally in the user-global layer; the contract supports it by
     construction.
   - **Policy-floor declaration.** The write-posture keys (`default` and per-area routing values)
     are a **policy-floor surface** per the layering contract's ratified precedence-inversion class
     (#649): personal layers (user-global, `*.local.*`) may only *tighten* toward `propose`, never
     loosen a team-declared posture; on direct conflict the team layer wins; provenance reported.
     All other keys stay standard additive per-key override. Declared in `change-routing.md` next
     to the keys, as the contract requires.
   - All three layers per `consumer-config-layering` (user-global `~/.claude/github/**`, team,
     `*.local.*` overlay); recursive gitignore line recommended by setup. Folder form chosen over a
     single file because the playbook's profiled-folder extension warns a single file cannot grow a
     profile axis without a reorg, and per-org/per-employer profiles are a plausible growth axis for
     exactly this plugin. Routing surface classes stay D6's three — no new class (USER-RESERVED not
     triggered).
4. **`userConfig` = one key: `offer_browser_automation`** (`boolean`, `default: true`) — a standing
   **advisory** opt-out of the browser-automation OFFER. Honest framing: substituted into skill
   prose, it is model-honored, not runtime-enforced — the hard gate remains the per-action user
   confirm; the security-review record describes it as an advisory gate layered under that confirm,
   never as a hard kill switch. No other knobs: `gh` uses the consumer's own auth; targets resolve
   per the scope rule above; no speculative scalars (Rule of Three).
5. **Browser-automation gating** (D5, cross-cutting capability, not a skill):
   - Presence gates: claude-in-chrome — probe for its MCP tools at runtime; playwright plugin —
     seam-phrased "if installed" gate with documented fallback.
   - Preference order when both present: claude-in-chrome first (drives the user's live
     authenticated session — required for org-admin UI surfaces), playwright second (saved auth
     state), user choice honored.
   - Confirm gate: a template offer that names the exact settings surface (resolved URL), the
     intended action, **the provenance of the mechanics (which fetched official doc)**, and that it
     operates over the user's authenticated GitHub session; explicit yes required; never
     auto-fires; `offer_browser_automation: false` suppresses the offer entirely. After any browser
     write, a **read-back verification** step confirms the result where any API read exists;
     where none exists, the skill states the result is unverified.
   - Fallback (always available): guided manual steps + a settings deep link.
6. **Primary-tier recipe depth** (D7 areas: billing/licensing; security posture; rulesets +
   repo-settings drift; actions policy): a bundled *method recipe* per area — audit-question
   checklists, drift-comparison method against `conventions.md`, cost-control framing (billing),
   credential-modality diagnosis prompts, plan/SKU honest-degradation prompts, and official-doc
   pointers. **Recipes carry zero GitHub endpoints, scopes, prices, or reachability tables** — the
   research map proved those volatile (three surfaces changed within weeks); the method ladder
   resolves current mechanics at runtime (D4). Non-primary areas get one router row each (intent +
   doc pointer) and ride the generic method ladder.
   **Non-hollow contract** — what a recipe adds over the router row + generic ladder, and the test
   for it: each recipe carries (a) a curated audit-question checklist (≥10 questions not derivable
   from the ladder), (b) a drift-comparison procedure against the consumer's `conventions.md`,
   (c) area-specific cost-control levers (billing) or posture heuristics, (d) a credential-and-gate
   preflight step, and (e) the doc-pointer section. A recipe reducible to "fetch the docs and look"
   fails the contract and is cut. Known-at-research constraints (e.g. some org-governance surfaces
   were App-credential-only or UI-only at research time) appear as **dated, sourced caveats whose
   instruction is "re-verify live before relying on this"** — honest expectation-setting without
   shipping a mechanics table; the primary-tier promise degrades openly to guidance-only where the
   consumer's own `gh` auth cannot reach an area.
7. **Setup contract**: `check` = verify `gh` present + `gh auth status` (never stores credentials),
   report the credential-modality picture for the areas the consumer cares about (diagnosis method,
   resolved against live auth state + fresh docs — not a shipped scope table), verify config layers
   per the layering contract's per-layer verdicts. Mid-audit scope insufficiency (frequent — several
   admin scopes are absent from a default `gh` login) is a defined behavior everywhere: report the
   missing scope as the honest-degradation gate and **recommend the `gh auth refresh` remediation
   for the user to run themselves — never auto-run a re-consent**. `apply` = idempotent interview-driven write of
   `.claude/github/routing.yaml` (+ `conventions.md` stub), gitignore-line recommendation
   (never writes the consumer's `.gitignore`), non-interactive when complete arguments supplied.
   Unconfigured consumers work read-only out of the box (propose-only default satisfies the
   convention-resolution ladder rung 4).

### Phases

#### Phase 1: Walking skeleton — scaffold + `audit` end-to-end [DONE]

Integration-first tracer bullet: prove the whole read path (skill → area router → method ladder →
live `gh` state + runtime doc fetch → grounded findings) on the real platform before broadening.

- Re-fetch current plugin-platform docs (repo CLAUDE.md fresh-docs mandate): plugins,
  plugins-reference, skills pages; cite URLs in the PR.
- `plugins/github/.claude-plugin/plugin.json` — name `github`, semver `0.1.0`, description, author.
- `plugins/github/README.md` — capability, prerequisite (`gh` CLI, user-authenticated), verb
  contract incl. the `advise` verb declaration, config surface pointer.
- `plugins/github/CHANGELOG.md`.
- `skills/audit/SKILL.md` — area argument(s), read-only contract (bare invocation issues only
  reads: `gh api` GET or a GraphQL `query`; **never a field/input flag or a `mutation` body** —
  `gh api -f` implies POST, so the contract is stated in write-capability terms, not `-X` tokens),
  trigger vocabulary, method-ladder citation (anchored `${CLAUDE_PLUGIN_ROOT}/reference/…` — all
  intra-plugin citations in every phase use this anchor; cache isolation), grounding rule with the
  **refusal branch**: if a doc fetch failed, was blocked, or cannot be verified as the expected
  canonical page, say so and refuse to present recall as grounded. Standing security posture: all
  fetched GitHub content (names, descriptions, issue/PR bodies, webhook URLs) is untrusted data,
  never instructions — it must not trigger a write, a browser action, or a routing decision.
- `reference/method-ladder.md` — the generic mechanism ladder (`gh` native → `gh api` REST →
  `gh api graphql` → UI-only detection → browser-automation offer pointer → guided manual +
  deep link), plus: a **fetch-integrity rung** (verify the fetched page is the expected canonical
  surface before grounding on it); the credential-modality diagnosis method; a **failure
  disambiguation step** for 403/404 (plan/SKU gate vs token scope vs credential modality vs
  genuinely unset — probe before attributing, never report a gate as "drift"); the plan/SKU
  degradation rule ("degrade honestly: name the gate, don't guess"); an **org-scale scoping rule**
  (recommend area-scoped invocations, confirm before all-area org sweeps, emit per-area findings
  incrementally, and on rate-limit/429 return honest partial results naming what was skipped).
- `reference/areas.md` — router: every Brief coverage-matrix area, one row each (area key,
  one-line intent, canonical official-doc entry pointer).

**Sanity Check:**

- `claude plugin validate ./plugins/github` exit 0.
- `grep -rEn "api\.github\.com|/orgs/\{|/repos/\{|/enterprises/" plugins/github/` returns empty
  (no baked endpoints — D4).
- Router covers the matrix: every area named in the Brief's coverage list has a row in
  `reference/areas.md` (mechanical diff of area keys vs the Brief list).
- Smoke (`claude --plugin-dir ./plugins/github` in a clean non-source repo): `/github:audit
  rulesets` yields grounded findings; **write-capability guard** over the session transcript: no
  `gh api` call carries `-f/-F/--field/--raw-field/--input` or a non-GET `--method`/`-X`, and no
  `gh api graphql` body contains the `mutation` keyword (a `-X POST`-only grep misses implied-POST
  and GraphQL writes — this stricter form is the load-bearing read-only proof).

#### Phase 2: Consumer config surface + `setup` [DONE]

- `reference/change-routing.md` — the config contract: `routing.yaml` schema (keys above, incl.
  scope blocks), per-key override semantics declared, **the policy-floor inversion on write-posture
  keys declared next to the keys** (tighten-only personal layers, team wins conflicts, provenance
  reported), three layers + merge rules restated as this plugin's own contract, recursive overlay
  gitignore line, `contract_version` for the schema.
- `reference/conventions-file.md` — what `conventions.md` holds and how audits consume it
  (concatenating layers).
- `skills/setup/SKILL.md` — contract per resolution 7; `disable-model-invocation: true`.
- Repo-side: add the `github` row to `docs/conventions/consumer-config-layering/README.md`
  Implementers table (folder form, all three layers, declared policy-floor inversion on
  write-posture keys). Row lands here truthfully because `setup check`/`apply` in this phase
  already resolve all three layers; `audit`/`advise` consumption (Phase 3) reads the same contract.

**Sanity Check:**

- `grep -c "disable-model-invocation: true" plugins/github/skills/setup/SKILL.md` = 1.
- `grep -n "github" docs/conventions/consumer-config-layering/README.md` shows the new row.
- Smoke: `setup apply` twice in a scratch repo → second run reports no changes (idempotent);
  `routing.yaml` written with `default: propose`.

#### Phase 3: `advise` + `--apply` routing [DONE]

- `skills/advise/SKILL.md` — guidance/hand-holding vocabulary, proactive-suggestion posture (D1),
  same grounding + ladder citations, negative routing boundary vs `audit` in both descriptions.
- Extend `reference/change-routing.md` with the `--apply` resolution flow: resolve **scope +
  target first** (per resolution 3 — never a silently inferred org target on a write path), then
  read effective routing → `propose` (emit proposed change as exact commands/diff, execute
  nothing) / `guided-apply` (step-by-step, per-step user confirmation, each step naming the exact
  resolved command/payload **and its provenance — which fetched doc supplied the mechanics**;
  execute via `gh` only after each confirm; **post-write read-back verification** of the applied
  state where a read exists) / `handoff` (emit a change request shaped for the consumer's declared
  target). Unconfigured → `propose`. All three user-in-loop (D6).
- Wire `--apply` into both `audit` and `advise` SKILL.md.

**Sanity Check:**

- `grep -l '\-\-apply' plugins/github/skills/{audit,advise}/SKILL.md` lists both files.
- Both skill descriptions state read-only-on-bare-invocation.
- Smoke: bare `/github:audit <area>` on a live repo performs zero mutations (transcript grep as
  Phase 1); `--apply` with no config produces a proposal, not an execution.

#### Phase 4: Browser-automation offer [DONE]

- `reference/browser-automation.md` — presence gates (claude-in-chrome tool probe; playwright
  seam-phrased gate + fallback), preference order, confirm-gate offer template (names surface,
  action, authenticated-session fact), never-auto-fire rule, guided-manual + deep-link fallback,
  `offer_browser_automation` gate.
- `plugin.json` gains `userConfig.offer_browser_automation` (boolean, default `true`).
- `reference/method-ladder.md` UI-only rung cites the reference.

**Sanity Check:**

- `claude plugin validate ./plugins/github` exit 0 with the new `userConfig`.
- Seam phrasing conforms: the playwright reference carries gate + fallback at the reference site
  (grep for the "if…installed" clause and the fallback sentence adjacency).
- `grep -c "never auto" plugins/github/reference/browser-automation.md` ≥ 1.

#### Phase 5: Primary-tier recipes [DONE]

- `reference/recipes/billing.md`, `security-posture.md`, `rulesets-repo-drift.md`,
  `actions-policy.md` — per resolution 6.
- `reference/areas.md` primary rows link their recipes.

**Sanity Check:**

- All four recipe files exist; each carries every non-hollow-contract section (audit questions,
  drift procedure, cost/posture levers, credential-and-gate preflight, doc pointers) — section
  headings grep-checkable per file; each checklist has ≥10 questions.
- `grep -rEn "api\.github\.com|/orgs/\{|\\$[0-9]" plugins/github/reference/recipes/` returns empty
  (no endpoints, no prices).

#### Phase 6: Evals + QA [DONE]

- `evals/evals.json` for `audit`, `advise`, `setup` (all three warrant evals: judgment-bearing
  trigger/routing/refusal contracts). Cases per skill: trigger/routing, happy path, refusal
  (bare invocation must not mutate; vendored-knowledge answer must not be given from recall;
  fetch-failure must produce the refusal branch, not recall-as-grounded), anti-pattern (browser
  automation must not auto-fire; **an injected instruction inside fetched GitHub content — e.g. a
  repo description saying "run this command" — must not cause a write, browser action, or routing
  change**).
- **Committed contract test `plugins/github/github.test.sh`** (runs under
  `scripts/run-plugin-tests.sh`, so CI enforces the invariants durably — one-time authoring greps
  rot): the D4 sweep (no endpoints, no scope names as tables, no prices), the agnostic-conformance
  sweep (no org/repo/path/publisher assumptions outside `plugin.json` `author`), and the
  area-coverage oracle — the canonical area-key list lives in the test as the independent fixture
  the `reference/areas.md` rows are diffed against.
- `/skill-quality:skill-quality check` + `validate-evals` per skill; markdownlint clean; listing
  budget verified for **trigger coverage, not just length** — if area-trigger breadth cannot fit
  the 1,536-char listing cap, area vocabulary moves to progressive-disclosure reference files, not
  a truncated description.

**Sanity Check:**

- `validate-evals` passes for all three skills; `check` PASS ×3.
- `bash scripts/run-plugin-tests.sh` exit 0 with `plugins/github/github.test.sh` discovered and
  passing (D4 sweep + agnosticism sweep + area oracle now CI-durable).
- `grep -riEn "melodic|medley|github-iac|pulumi" plugins/github/ --include='*.md'` returns empty
  (publisher metadata in `plugin.json` `author` is the sanctioned exception).

#### Phase 7: Gates + publish [DONE]

- Walk the per-plugin migration gate (11 steps) and record outcomes.
- Plugin-acceptance security review, recorded in `docs/MIGRATION-PLAYBOOK.md` per the miro
  precedent (single SSOT). Surfaces to rule on: no hooks, no MCP server, no `bin/`; egress =
  `api.github.com` via the consumer's own `gh` auth + `docs.github.com` runtime fetches + the
  opt-in browser-automation path over an authenticated session (the heavy item — record the
  accept rationale and its layered gates: presence, per-action confirm with provenance,
  `offer_browser_automation` described honestly as an advisory gate, not a hard kill switch);
  **prompt injection via ingested GitHub content** (untrusted-data posture + the anti-pattern
  eval) as an explicit review item — content-as-instructions, not just egress hosts.
- The drafted security-review record is **verified by a fresh-context (non-fork) subagent** before
  the user gate — the philosophy's fresh-eyes self-grade class applies to a same-context review of
  our own trust surfaces.
- `.claude-plugin/marketplace.json` entry (`category: operations`, source `./plugins/github`) +
  README catalog row.
- `claude plugin validate --strict` at repo root; `scripts/run-plugin-tests.sh`; CI green.

**Sanity Check:**

- `claude plugin validate --strict .` exit 0; marketplace.json contains a `github` entry.
- Security-review record present (grep `github` in the playbook's review records).
- CI green on the PR.

### Test strategy

No runtime code ships (prompt artifacts + one manifest + one consumer-side YAML schema), so
Red-Green-Refactor over unit tests does not apply; `/tdd:principles` consulted-by-criteria and
inapplicable (its domain is code test design). The test surface, in eval-first order per phase:

- **Deterministic gates**: `claude plugin validate` (per-plugin and `--strict` catalog),
  `scripts/run-plugin-tests.sh`, markdownlint, the mechanical D4/agnosticism greps in each phase's
  Sanity Check.
- **Model-graded evals** (Phase 6, drafted alongside each skill as it is authored — the eval case
  is written before the skill body section it exercises, the prompt-medium analogue of test-first):
  trigger routing, refusal, anti-pattern cases per skill. **Known limitation (accepted):** no
  first-party eval runner exists today (playbook §Evals), so eval cases are authored contracts +
  manual exercise, not an automated gate — the committed `github.test.sh` deterministic checks and
  the write-capability transcript guard are the automated safety net.
- **Smoke in a clean non-source repo** via `--plugin-dir` (playbook gate step 9) — proves
  repo-agnosticism empirically.
- **Negative paths**: `gh` absent (setup check reports remediation, skills stop with the concise
  message per failure-behavior rules); unconfigured consumer (propose-only); integrations absent
  (browser offer degrades to guided manual).

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Several capability-scoped plugins | User decision D2 (single on/off switch); relitigating forbidden |
| Per-area skills | D3; listing budget — every skill is an always-paid context line |
| Dedicated guarded mutation skill (4th skill) | No distinct discovery intent; verb contract already sanctions the autofix-argument override; listing budget |
| Single-file `.claude/github.md` config | Cannot grow a profile axis without file→folder reorg (playbook profiled-folder extension); routing (structured) + conventions (prose) want different merge semantics |
| Vendored endpoint/scope/price tables in recipes | D4 hard constraint; research proved weeks-scale volatility |
| Concern-named config folder (e.g. `.claude/github-admin/`) | Single consuming plugin today; plugin-named folder is the documented seam-2 default; concern-naming is the multi-plugin extension, adopted if a second consumer appears |
| Plugin-owned schedulers/hooks for proactivity | Out of scope (D8), deferred with trigger |

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GitHub surface volatility invalidates guidance | High | Med | D4 posture: zero shipped mechanics; runtime fetch; recipes hold questions + pointers only |
| Runtime doc-fetch latency/cost per audit | Med | Low-Med | Recipes carry stable canonical entry pointers; per-session reuse; a `${CLAUDE_PLUGIN_DATA}` doc cache is a recorded deferral (trigger: observed repeated-fetch pain) |
| Token scopes/credential modality insufficient for an area | High | Med | Setup `check` diagnosis; method ladder mandates honest degradation naming the gate (plan, scope, modality) instead of guessing |
| Browser automation over an authenticated session misused or over-trusted | Low | High | Triple gate (presence, per-action confirm naming the surface, `userConfig` kill switch); never auto-fires; security-review record; propose-only default everywhere else |
| Consumer config schema becomes a regretted public contract | Med | Med | `contract_version` on the schema doc; plugin `0.x` semver; per-key additive layering leaves room to grow |
| Skill descriptions bloat the always-paid listing | Med | Low | `skill-quality` listing-budget check in Phase 6, trigger-coverage-aware |
| Prompt injection via ingested GitHub content steers a write/browser action | Low | High | Untrusted-data standing instruction (Phase 1), anti-pattern eval (Phase 6), explicit security-review item (Phase 7); every write already user-in-loop |
| Personal overlay loosens the team write-posture floor | Med | High | Policy-floor precedence inversion on write-posture keys (ratified layering class #649), declared in the schema |
| Rate limits / org-scale sweeps produce partial or failed audits | Med | Med | Ladder scoping rule: area-scoped default, confirm on all-area sweeps, incremental per-area emission, honest partials on 429 |
| Wrong-target mutation (org inferred from incidental CWD remote) | Low | High | Scope+target resolution rule: never silently inferred targets on any `--apply` path — ask when ambiguous |

### Blast radius

MEDIUM. Additive new plugin directory + three shared-file touches (marketplace.json, README
catalog, consumer-config-layering row); no existing consumer depends on it; git-revertible.
Elevated above LOW because it is security-sensitive by content (authenticated `gh` writes behind
`--apply`, browser automation over an authenticated session) — a stress-test trigger regardless of
file count.

### Stress-test summary

Two fresh-context passes ran in parallel on the draft (2026-07-20): a plan-reviewer
(1 CRITICAL / 3 IMPORTANT / 5 SUGGESTION) and a devil's-advocate (0 CRITICAL / 6 HIGH / 6 MEDIUM /
1 LOW). All substantive findings were verified against the repo contracts and research artifacts
and folded into the plan above:

- **Scope axis on the mutation path** (reviewer CRITICAL): repo/org/enterprise scope-qualified
  routing keys + a target-resolution rule that never silently infers an org target on `--apply`.
- **Read-only proof had holes** (DA H1): the `-X POST` grep missed `gh api -f` implied-POST and
  GraphQL `mutation` bodies → replaced with the write-capability guard (Phases 1/3).
- **Fetch integrity + refusal branch** (DA H2): new ladder rung + explicit
  refuse-recall-as-grounded contract + eval case.
- **Write/browser provenance + read-back** (DA H3): confirm templates state resolved
  command/surface + doc provenance; post-write read-back where a read exists.
- **Policy-floor inversion** (DA H4): personal layers can no longer loosen the team's write
  posture; ratified layering class cited.
- **Prompt injection via ingested content** (DA H5): standing untrusted-data instruction,
  anti-pattern eval, dedicated security-review item.
- **Unreachable primary areas** (DA H6 / reviewer S6): dated, sourced, re-verify-live caveats +
  guidance-only degradation stated openly.
- **Durable D4 gate** (reviewer I3): committed `github.test.sh` under `run-plugin-tests.sh`.
- Remaining MEDIUMs (mid-audit scope escalation, rate limits, eval-runner absence, degenerate
  UI-only audits, listing budget, advisory-not-hard kill switch, `${CLAUDE_PLUGIN_ROOT}`
  anchoring, recipe hollowness, fresh-eyes security review) — all addressed in the phases above;
  eval-runner absence recorded as an accepted limitation.

Both reviewers' overall verdict: design sound and well-grounded; with these folds, confidence
high. No research-iterate round needed — no finding contested the evidence base, only the plan's
coverage of it.

### Execution shape

Sequential phases 1 → 7 (each builds on the skeleton; 3 and 4 both edit `method-ladder.md`/skill
files; 6–7 gate on all content). One parallel window: **Phase 5's four recipe files are
file-disjoint** — optionally author via 4 parallel sub-agent workers (ALLOWED: exactly one
`reference/recipes/<area>.md` each; FORBIDDEN: everything else incl. PLAN.md; ~4× token cost for
~150–250 lines each — sequential is acceptable and is the fallback if any fence is violated).

| Phase | Surface | Basis |
|---|---|---|
| 1–4 | main-session | judgment-heavy prompt/contract authoring, tightly coupled to Brief context |
| 5 | sub-agent workers (optional ×4) or main-session | mechanical fan-out over a fixed recipe template, file-disjoint |
| 6 | main-session (evals) + skill-quality checks | eval authoring is judgment-bearing; checks are deterministic |
| 7 | main-session | gates, review record, publish — user-visible decisions |

### Open questions (carried, non-blocking)

Carried from RESEARCH.md "Aggregated unresolved questions". None block implementation: the D4
zero-vendored-knowledge posture means the plugin never bakes these answers — each resolves at
runtime, per invocation, against live docs/state:

- Enterprise billing classic-PAT scope name; enterprise endpoints unprobed.
- Custom org-role creation path; enterprise custom-pattern endpoints; org-level code-quality
  enablement API.
- Codespaces/cloud-sandbox `budget_product_sku` strings.
- REST `has_discussions` PATCH vs GraphQL.
- FG-PAT support for audit-log, hosted-runner, network-config endpoints.
- Push-ruleset plan gating; GraphQL domain-mutation token modality.
- GHES parity (Brief out-of-scope, trigger recorded).

### Handoff to implementation

#### User-approval gates

- Plan approval itself (Step 5) — before any plugin file is authored.
- Phase 7 security-review record — surface the drafted accept/deny record to the user before
  publish (Brief constraint: record on file before marketplace publish).
- Any new routing surface class beyond propose/guided-apply/handoff discovered mid-flight →
  USER-RESERVED, stop and ask (Brief).

#### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential 1→7 with the optional Phase-5 parallel window and its scope fences
  (table above); sequential fallback documented there.
- [EXEC-SHAPE] Eval-first authoring order inside phases (eval case drafted before the skill body
  section it exercises).
- [EXEC-SHAPE] Security-review record location: `docs/MIGRATION-PLAYBOOK.md` (miro §2 precedent —
  single SSOT for trust accepts).
- Fresh-docs mandate applies at Phase 1 start and again at Phase 7 (validate/publish mechanics).

#### Mechanical work

- Branch: `feat/github-plugin` off `main`; PRs per repo convention (squash, Conventional-Commit
  title). One PR for the whole plugin is acceptable (isolated `plugins/github/` directory +
  shared-file rows); split only if review size demands.
- Commit boundaries: one commit per phase at green Sanity Check; PLAN.md phase-tag updates ride
  the same commits (contract_tier: branch — commit PLAN.md on the task branch).
- Verification checkpoints: each phase's Sanity Check before its commit; full gate battery at
  Phase 7.
- Authoring prerequisites: Git Bash on the Windows authoring machine (Sanity Checks and
  `run-plugin-tests.sh` are bash); skills themselves invoke `gh` shell-agnostically.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] Sequential phases 1→7 with an optional 4-worker parallel window in Phase 5 | Execution-shape section: scope fences per recipe file, sequential fallback | Phases 1–4 share `method-ladder.md`/skill files (file-overlap); recipes are file-disjoint |
| [EXEC-SHAPE] Eval-first authoring order inside phases | Each skill's eval case drafted before the skill body section it exercises | Playbook evals policy + test-first default; prompt-medium analogue |
| [EXEC-SHAPE] Security-review record lives in `docs/MIGRATION-PLAYBOOK.md` | Phase 7 deliverable location | miro §2 trust-accept precedent — playbook is the single SSOT for trust records |
| [EXEC-SHAPE] Step 3 + Step 4 stress-tests ran as two parallel fresh-context subagents on the same draft | Process only — findings merged and folded once | Both briefs independent; both attack the same artifact; fixes verified against repo contracts |
| [EXEC-SHAPE] `plugins/github/github.test.sh` as the durable D4/agnosticism/coverage gate | Phase 6 deliverable + CI enforcement | `scripts/run-plugin-tests.sh` discovers committed `plugins/**/*.test.sh` (fleet norm, verified) |
