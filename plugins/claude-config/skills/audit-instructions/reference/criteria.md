---
version: 1.6.0
last-updated: 2026-08-02
---

# Instruction-Audit Criteria

The checks the `audit-instructions` skill runs, seeded from current official prompting doctrine.
Each check carries an evidence tier, an authority tag, a default severity, its surface
applicability, and one decisive source line (point-don't-copy — the full doctrine lives at the
cited URL, not restated here).

**Recheck triggers** — treat these as staleness signals and re-verify the catalog against live
docs when any fires: a new frontier model release; **a change to any page listed under Sources
below**. Every check cites one of those pages, so the trigger set is the source set — naming a
subset would leave the harness-behavior rows depending on pages nothing watches. One staleness event
fires the whole catalog, not the check that noticed it. Model-specific pages (the Fable 5 and
Opus 5 guides) are superseded on each model generation.

**Per-row verification stamps.** A row that restates a volatile upstream *literal* — a level name, a
model range, a type predicate — additionally carries the four-part record that claim needs: the
claim, its basis, an as-of date, and a recheck trigger naming an observable event (the shape is
`docs/conventions/upstream-drift/README.md` in this monorepo; in a standalone install the four
parts, not the path, are the requirement). A row that restates nothing and only points at its page
carries no stamp, because a pointer cannot go stale.

A per-row stamp **supplements** the catalog-wide trigger above; it never replaces or narrows it.
The catalog trigger still fires every row on any Sources change — that is why a row's own trigger
names only the events the Sources set would *miss*, such as a value set changing while its page
keeps the same URL. **Where the two disagree, the catalog trigger wins**, because it is the wider
one and a staleness signal is not something to resolve by picking the narrower authority.

The requirement **binds on touch**, per the convention above: rows predating this rule keep their
citations as they are and adopt the four parts the next time they change. A missing stamp on an
older row is therefore not itself a defect in this catalog.

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier** — `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified by the delete-and-watch
  loop, never confident removals).
- **Authority** — `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice). A closed three-value set.
- **Severity** — `error` / `warning` / `info`.

**Model scoping.** A check or row sourced from a SINGLE model's guide is annotated
`Model scope: <version>` and FIRES only when the run's resolved target model (the skill body owns
`--target-model` resolution) matches that scope; otherwise it is inert and the report lists it as
`skipped-for-target`. **The match is exact string equality of the normalized version token**
(e.g. `opus-5`): a point release or a dated full model ID does NOT auto-match a base-version scope
— model guides are calibrated per version, and successive guides have reversed each other, so a
near-miss target skips the row (reported `skipped-for-target`, naming the near-miss) rather than
inheriting a sibling version's doctrine. The scope value is data — no check body branches on a
model name in prose. Promotion to fleet-wide (unscoped) happens only through the gate: an
authoritative model-agnostic upstream doc states the claim, OR multiple model guides converge on
it. Unannotated checks are model-agnostic and always fire.

**`OPINION` enablement.** Enablement attaches to *detection*, never to advice, and splits on what a
rule does:

- An `OPINION` check that **emits** findings is **off** on bare invocation, enabled only by the
  explicit `--opinion` argument, capped at `info`, and never fix-applied. An unconfirmed
  practitioner preference does not get to mutate a consumer's instruction corpus under the same
  banner as documented doctrine.
- An `OPINION` rule that **withholds** findings is **on** by default, disabled only by an explicit
  opt-out. Defaulting a suppressor off would not make the audit more conservative — it would delete
  the only bound on the checks it moderates.
- `OPINION`-derived *advice* inside a backed check's Remediate line follows that check's enablement
  and severity, because the detection is the host's and is backed. It is labelled inline as
  `OPINION`-derived and is never fix-applied.

Every run reports one line naming how many `OPINION`-tier checks were available, how many did not
run, and the argument that enables them — an off-by-default tier nobody can find is shipped in name
only.

**Surface partition.** Checks I1–I5 are the instruction-memory hygiene layer: they apply on
non-memory surfaces (skill bodies, agent definitions, hook instruction text, output styles); on
memory-layer surfaces (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`) their
findings route to the `claude-memory` plugin's `audit` skill when it is installed, and fall back
to the official include/exclude guidance (I1–I5 source below) when it is not. Checks I6–I12 and
I15–I20 apply to all surfaces; I13 and I14 name narrower surface sets in their own rows.

## Sources

- Claude Code best practices — <https://code.claude.com/docs/en/best-practices>
- Prompting best practices —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Prompting Claude Fable 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- Prompting Claude Opus 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5>
- Memory (CLAUDE.md, rules, auto memory) — <https://code.claude.com/docs/en/memory>
- The `.claude` directory — <https://code.claude.com/docs/en/claude-directory>
- Skills (what loads when, how supporting files are referenced, the listing budget,
  invocation-control fields) — <https://code.claude.com/docs/en/skills>
- How features layer (per-surface precedence, routing between surfaces) —
  <https://code.claude.com/docs/en/features-overview>
- Context window (what survives compaction) — <https://code.claude.com/docs/en/context-window>
- Hooks (handler types, and which events inject handler output into context) —
  <https://code.claude.com/docs/en/hooks>
- Refusals and fallback (`reasoning_extraction`) —
  <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
- Thinking (the sanctioned reasoning-visibility path, the `display` field, and the thinking-block
  round-trip protocol) — <https://platform.claude.com/docs/en/build-with-claude/thinking>
- Troubleshooting thinking (the per-request 400s, and the models the effort restriction covers) —
  <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
- Effort (the levels, and where thinking may not be disabled) —
  <https://platform.claude.com/docs/en/build-with-claude/effort>
- Model configuration (the harness-side thinking-display and thinking-disable surfaces, and which
  effort levels each surface accepts) — <https://code.claude.com/docs/en/model-config>
- Settings (the `effortLevel` value set) — <https://code.claude.com/docs/en/settings>
- Environment variables (`CLAUDE_CODE_EFFORT_LEVEL`, `MAX_THINKING_TOKENS`) —
  <https://code.claude.com/docs/en/env-vars>
- Prompt caching (what belongs to the cache key) — <https://code.claude.com/docs/en/prompt-caching>
- CLI reference (`claude doctor` and the other terminal forms) —
  <https://code.claude.com/docs/en/cli-reference>
- Subagents (what loads into a subagent at startup) — <https://code.claude.com/docs/en/sub-agents>

---

### I1: Line-necessity bar

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** a line whose removal would not change behavior — restates a default, a truism, or
  something the model already does correctly.
- **Remediate:** cut it, or (if it enforces something) convert per I5.
- **Source:** best-practices — "For each line, ask: *Would removing this cause Claude to make
  mistakes?* If not, cut it."

### I2: Length and skimmability

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** a surface long or dense enough that its own rules start getting ignored; the tell is
  the model breaking a rule the file contains.
- **Remediate:** prune, split into path-scoped rules or skills, tighten structure.
- **Source:** best-practices — "Bloated CLAUDE.md files cause Claude to ignore your actual
  instructions."

### I3: Broad-applicability placement

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** only-sometimes-relevant content (a workflow, domain knowledge, one subsystem's
  quirks) living in a surface that loads **more broadly than the content is relevant**. Two cases,
  because the surfaces this check runs on are not all always-loaded:
  - an always-loaded surface — the selected output style, an unscoped rule, root `CLAUDE.md` where
    the partition allows it;
  - a surface loaded in full on every use of a component whose own scope is broader than the
    content's — a skill body or an agent definition covering several concerns, where the content
    matters to one of them and is in context for all of the others. Establish that breadth before
    flagging: a skill or agent that exists *only* for the content's concern loads it exactly when it
    is relevant, and is not a finding.
- **Remediate:** move it to a skill or a path-scoped rule that loads on demand. **A destination
  qualifies only if it defers loading** — `@path` imports do not, so a split into imports is an
  organizational change and not a context saving, and proposing one satisfies this check's letter
  while changing the load profile not at all. **State the move cost with the recommendation:** a
  `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file is
  read again, so content that must survive compaction stays unscoped or in the project-root
  `CLAUDE.md`. **A *new* skill is not a free destination:** its body defers, but the listing entry it
  adds — `name` plus the combined `description` and `when_to_use`, truncated at 1,536 characters — is
  always in context, so the saving is the body minus that entry rather than the whole body. Moving
  content into a skill that **already exists** adds no listing entry and does not carry this cost.
  The only field that keeps a description out of context is `disable-model-invocation: true`, which
  also makes the skill user-invocable only; `user-invocable: false` does not, and `skillOverrides`
  does not reach plugin skills at all. State the entry as a cost, not a threshold — whether a corpus
  is over its listing budget is a different question and not this check's.
  **Content taken out of an agent definition needs an agent-reachable destination.** A subagent runs
  in its own context, and path-scoped rules are invisible there
  (<https://code.claude.com/docs/en/sub-agents>), so proposing one for instructions the agent needs
  removes them from every dispatch rather than deferring them. Name a destination the agent itself
  reaches — a skill the agent's definition invokes or preloads, or text kept in the definition — and
  never a `paths:`-scoped rule.
- **Adjacent axis:** this check is load *timing*. Definition-site *locality* — an instruction sitting
  away from the thing it governs — is I16, and an instruction can be correctly deferred here and
  still misplaced there.
- **Source:** best-practices — "only include things that apply broadly. For domain knowledge or
  workflows that are only relevant sometimes, use skills instead."; memory — "splitting into `@path`
  imports helps organization but doesn't reduce context, since imported files load at launch";
  context-window, "What survives compaction", for the per-destination cost; skills — "skill
  descriptions are loaded into context so Claude knows what's available, but full skill content only
  loads when invoked", the combined `description` and `when_to_use` text "is truncated at 1,536
  characters in the skill listing to reduce context usage", and "Plugin skills are not affected by
  `skillOverrides`."

### I4: Inferable or redundant content

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** content the model can derive from the code, standard language conventions it already
  knows, inlined API docs that should be a link, or self-evident practices.
- **Remediate:** delete; link to the source of truth instead of inlining it.
- **Source:** best-practices include/exclude table — exclude "Anything Claude can figure out by
  reading code" and "Standard language conventions Claude already knows."

### I5: Rule-to-hook or delete

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: I1–I5 partition.

- **Detect:** a rule the model already follows without it, or one that must fire every time with
  zero exceptions.
- **Remediate:** delete the already-followed rule; convert the must-always rule to a hook, which is
  deterministic where an instruction is only advisory.
- **Source:** best-practices — "If Claude already does something correctly without the instruction,
  delete it or convert it to a hook."

### I6: Bare prohibition to positive reframing

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** a bare "never / do not / don't" instruction. The deterministic pre-scan marks
  candidate lines; a line already carrying a rationale marker is a weaker candidate.
- **Remediate:** reframe positively — state what to do instead — as the primary fix. Where a
  genuine hard "never" survives, keep it but add its rationale (see I7) as the fallback.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** prompting best-practices — "Tell Claude what to do instead of what not to do."

### I7: Reason with the request

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all. Unscoped —
promotion gate MET: the model-agnostic best-practices page states the same claim (see Source),
so this fires for every target model.

- **Detect:** an instruction that states a request with no intent or motivation attached.
- **Remediate:** add the why — the model connects the task to relevant context instead of inferring
  intent on its own.
- **Source:** Fable 5 guide, "Give the reason, not only the request" — "Claude Fable 5 tends to
  perform better when it understands the intent behind a request." Convergent model-agnostic
  source (the gate-meeting one): Prompting best practices, "Add context to improve performance" —
  "Providing context or motivation behind your instructions, such as explaining to Claude why
  such behavior is important, can help Claude better understand your goals and deliver more
  targeted responses."

### I8: Model-era re-audit

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

The base row and each model row carry their own `Model scope` (single-model guide sources;
promotion gate unmet for all of them).

**Base row** · Model scope: `fable-5`.

- **Detect:** prior-model workarounds and over-prescriptive step lists — instructions enumerating
  behaviors a current model handles from a brief instruction, or scaffolding that pins an approach.
- **Remediate:** propose removal or a briefer instruction; verify via the delete-and-watch loop
  that default performance holds or improves.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Fable 5 guide — "Skills developed for prior models are often too prescriptive for
  Claude Fable 5 and can degrade output quality."

**Row I8-a: instructed self-check removal** · Tier `behavioral` · Model scope: `opus-5`.

- **Detect:** instructions telling the model to re-check work it already checks — "double-check
  your answer," "re-verify before responding," "include a final verification step," "use a
  subagent to verify" — including legacy harness scaffolding that adds separate verification
  steps.
- **Classify by reviewer INDEPENDENCE, not invocation source:** architected independent review — a
  fresh-context reviewer blind to the producing rationale, or a different-vendor verifier — is NOT
  a finding; the anti-pattern is the instructed self-check. **Carve-out lanes (never flagged):**
  security review, destructive operations, managed-upstream-file changes, PR merge gates.
- **Remediate:** propose removal; verify via the delete-and-watch loop.
- **Bounded by:** the **Stopping condition** below.
- **Source:** Opus 5 guide, "Task scope and over-verification" — remove explicit verification
  instructions: they "cause over-verification on Claude Opus 5, and removing them reduces wasted
  tokens with no loss in quality"; "Self-correction" — avoid instructing re-checks it already
  performs.

**Row I8-b: conservative-reporting detection** · Tier `behavioral` · Model scope: `opus-5`.

- **Detect:** review/report instructions that gate severity at the FINDING stage — "be
  conservative," "only report high-severity issues," "don't nitpick" — which this model follows
  literally, withholding real findings. The gate is about WITHHOLDING findings from the audit or
  report output: severity-based routing where everything is still reported somewhere ("only page
  on-call for high-severity; log the rest") and non-reporting uses of "conservative"
  ("conservative time estimates") are not findings.
- **Two fences, OWNED HERE (the scanner over-produces by contract; the model lane adjudicates):**
  1. **Restraint-clause shape** — a clause bounding when a TRANSFORMATION or action applies
     ("When NOT to apply…", "skip the change when…") is not a reporting gate; the canonical
     non-finding shape is a tidying catalog's restraint text (in this monorepo:
     `plugins/code-tidying/skills/tidy/reference/tidyings.md`; in a standalone install the shape,
     not the path, is the fence).
  2. **Quoted/meta surfaces** — a document that DISCUSSES the conservative-reporting pattern
     (this criteria file, a model-adaptation delta chapter, verification records quoting it) is
     not a finding. Judge at the level of the instruction's audience: quoted text embedded inside
     an operative directive ("follow the maxim: 'only report high-severity issues'") is still
     operative and IS a finding; the exemption is for documents about the pattern, never for
     quotation as packaging.
- **Remediate:** rephrase to report-everything + a separate filter/rank pass.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Opus 5 guide, "Code review and bug-finding" — the model "may follow that
  instruction literally and report less; ask it to report everything and filter in a separate
  pass instead."

**Row I8-c: don't-think / don't-reason directive** · Tier `behavioral` · Model scope: `opus-5`.

- **Detect:** instructions telling the model not to think or not to reason — with thinking
  disabled these increase internal-tag leakage. Also flag tag-hygiene rules that name thinking
  tags specifically (less effective than the general form).
- **Remediate:** remove the directive; where output-tag hygiene is genuinely needed, use the
  general "internal or system XML tags" phrasing.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Opus 5 guide, "Running with thinking disabled" — "If your system prompt contains a
  rule instructing the model not to think or not to reason, remove it; that kind of instruction
  increases tag leakage"; naming thinking tags is "less effective than the general form."

### I9: Example hygiene

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an example block that pins the model's *approach* to a task (behavioral scaffolding).
  Do not flag examples that steer output format, tone, or structure — those remain recommended.
- **Remediate:** keep 3–5 diverse format/tone/structure examples; propose trimming or reframing
  only approach-pinning ones, A/B'd against the no-example default. Where the example block exists
  to enumerate what a caller may pass — modes, options, permitted values — name the interface
  destination that carries it instead: an argument enumeration, a frontmatter field, a typed
  `argument-hint`. That destination clause is **`OPINION`-derived** — no official page states it —
  so it rides this check's enablement and severity per the `OPINION` policy above, is labelled as
  `OPINION` in the finding, and is never fix-applied.
- **Source:** prompting best-practices, "Use examples effectively" — examples are "one of the most
  reliable ways to steer Claude's output format, tone, and structure"; keep them diverse enough
  "that Claude doesn't pick up unintended patterns."

### I10: Reasoning-echo directives

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all · Model scope:
`fable-5` (the cited refusal category is documented for that model only; promotion gate unmet).

- **Detect:** instructions telling the model to show, echo, transcribe, or explain its internal
  reasoning as response text. The deterministic pre-scan marks show-your-thinking phrasing.
- **Remediate:** remove them; where reasoning visibility is genuinely needed, read structured
  `thinking` blocks through the surface that already exposes them — in Claude Code, `Ctrl+O` verbose
  mode and the `showThinkingSummaries: true` setting (model configuration); on the API,
  `display: "summarized"` (Thinking). A send-to-user tool remains the path when the reasoning has to
  reach the user as ordinary response text.
- **Source:** Fable 5 guide — such instructions "can trigger the `reasoning_extraction` refusal
  category on Claude Fable 5, causing elevated fallbacks." Corroborated by the Thinking page, which
  states the same refusal for the same model: "On Claude Fable 5, a request that attempts to elicit
  the model's internal reasoning as part of the response text can be refused with
  `stop_details.category: "reasoning_extraction"`." That second citation does **not** move the
  promotion gate: its own section names both Claude Fable 5 and Claude Mythos 5 for the adjacent
  raw-chain-of-thought property, then names Fable 5 alone for the refusal — a sentence-adjacent
  chance to widen, declined, so the narrower scope is deliberate.

### I11: CLI over MCP where equivalent

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an instruction steering the model to an MCP tool where an equivalent CLI exists, when
  the surface's concern is context cost rather than a capability the MCP server uniquely provides.
- **Remediate:** prefer the CLI for the equivalent operation; keep the MCP path where it adds
  capability.
- **Source:** best-practices — "CLI tools are the most context-efficient way to interact with
  external services."

### I12: Stale or misattributed harness-capability claim

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** an instruction that asserts a Claude Code *harness* behavior — what a command does,
  what a keystroke saves, what loads into which context window, what a mode persists — where
  **either** the official documentation **for the version the claim is about** states something
  incompatible with it, **or** a reproduction matching **every** stated precondition fails. The
  subject is the product, not the model, which is what separates this from I8.
- **Remediate:** correct the claim against the cited page, or cut it and point at the page instead
  of restating it. Where the behavior is version-gated, carry the minimum version with the claim.
- **Must NOT flag: silence.** A page that no longer mentions a behavior is not evidence the behavior
  changed — product documentation is routinely rewritten, condensed, or reorganized, and this
  repository deliberately keeps empirical smoke tests for behaviors the official pages never
  specified at all. Absence of documentation raises the claim for reproduction; it does not
  establish drift, and it never on its own justifies a removal.
- **Must NOT flag: a gated claim that still reproduces under its own conditions.** Match the
  conditions before matching the text. Version is the common one — a claim scoped to a pinned or
  supported older release is measured against that release, not against the latest page — but it is
  not the only one: **OS, a setting, an account tier, a feature flag, and launch mode are equally
  preconditions**, and a replay under different conditions proves nothing about the instruction.
  **A successful matched reproduction settles it**; a failed one settles it only when every stated
  precondition was met, and is otherwise **inconclusive rather than a finding**. A claim carrying no
  conditions is about current default behavior and is measured against the current page. This is the
  mirror of the remediation above: a catalog that asks authors to carry a claim's conditions must not
  then flag the claims that do.
- **Must NOT flag:** prose that names two adjacent forms and distinguishes them correctly — the
  terminal `claude doctor` being read-only while the in-session `/doctor` applies fixes is the
  canonical pair, and a file that states both is right, not drifting. A bare routing pointer that
  tells the reader to run a command without claiming what it does. Text that quotes a retired
  affordance explicitly as retired.
- **Source:** CLI reference — "Print read-only installation and settings diagnostics from the
  terminal without starting a session … For the in-session setup checkup that can also apply
  fixes, run `/doctor`."

### I13: Citation form that does not load

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: non-memory only
(skill bodies and their reference files, agent definitions, hook instruction text, output styles).

- **Detect:** an `@path` written outside backticks and outside a fenced block on a surface where `@`
  carries no import meaning, **in prose that asserts the file has already arrived** — "as specified
  in @reference/rules.md above", "the criteria in @reference/criteria.md are loaded", a claim that
  the content is present rather than an instruction to go get it. Import syntax is a property of the
  CLAUDE.md family; on a skill or agent surface the `@` is inert, so an instruction written on the
  assumption that it imported is describing a load that did not happen.
- **Remediate:** rewrite the assertion into an explicit read, and cite the file the way that surface
  actually resolves — a backticked path or a markdown link. **Changing the citation syntax alone is
  not the fix**: neither form imports anything either, so a diff that swaps `@reference/rules.md` for
  a backticked path while leaving "as specified above" in place keeps the false claim and still lets
  the agent proceed without the content. The false premise is the defect; the syntax is where it
  shows.
- **Must NOT flag: an `@path` the surrounding prose treats as a file to read.** The path is still
  legible in the loaded prompt, so "follow `@reference/rules.md`" works — the reader opens it, the
  inert prefix costs one character. **The finding is the false assumption of automatic loading, not
  the citation form**, and a warning on every inert `@` would flag working instructions. When the
  prose does not say the content already arrived, leave it.
- **Must NOT flag:** anything on a memory-layer surface, where `@path` genuinely imports. A
  package scope (`@anthropic-ai/…`), a decorator, an email address, or a `@username` handle. A
  backticked `` `@path` ``, which the import parser skips by design and which is the documented
  way to mention a path without importing it. A path cited without an `@` at all.
- **Source:** memory — "CLAUDE.md files can import additional files using `@path/to/import`
  syntax", against skills, where supporting files are instead referenced "so Claude knows what
  each file contains and when to load it" and no import syntax is defined.

### I14: Retrieval of an already-loaded surface

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: agent definitions and
skill bodies.

- **Detect:** an instruction directing the agent to go read a surface the main conversation loads at
  startup and therefore already carries — the **root** `CLAUDE.md`, the user `CLAUDE.md` at the
  **resolved** `${CLAUDE_CONFIG_DIR:-~/.claude}`, the **root** `CLAUDE.local.md`, unconditional
  project rules (no `paths` frontmatter), and managed policy files. Two qualifiers are load-bearing.
  Root-level: the startup guarantee is scoped to the hierarchy discovered from the launch directory,
  not to every file of that name in the tree. Resolved: `CLAUDE_CONFIG_DIR` moves the whole config
  tree, so a hardcoded `~/.claude/CLAUDE.md` both flags a read that is now necessary and misses the
  redundant read of the configured path. Phase A resolves this variable already (`SKILL.md:76-78`);
  match it. The read spends a turn to retrieve text that is already present.
- **Remediate:** cut the retrieval step and state the requirement the read was meant to satisfy.
- **Must NOT flag: anything that loads on demand rather than at startup.** The guarantee this check
  rests on covers the hierarchy *the main conversation loads*, which is not the whole memory family.
  **Nested `CLAUDE.md` and nested `CLAUDE.local.md` files in subdirectories, and path-scoped rules
  (`paths` frontmatter), load lazily when work reaches their scope** — both filename forms, since
  the lazy-loading behavior is a property of the location rather than of the name. An instruction to
  read either one before operating in that package can be doing real work. Flag only when the
  specific file named is one of the startup-loaded set above; when a surface's residency is not
  established, leave it.
- **Must NOT flag:** an instruction to read a surface that is *not* auto-loaded — `AGENTS.md`,
  contributing guides, ADRs, CI workflow files, per-ecosystem convention docs. Those are ordinary
  progressive disclosure. **Any read where the file is the operation's subject rather than its
  instructions** — auditing it, editing it, patching it, reporting on it, or anything else needing
  current disk contents. The startup copy is a snapshot taken at launch; another process can have
  changed the file since, and a pre-edit read cut on the grounds that "it is already in context"
  produces a patch against stale text. A rule restated in a
  delegation prompt for the built-in Explore and Plan agents, which are documented as the only
  subagents that skip `CLAUDE.md` and have no per-agent setting to change that.
- **Source:** subagents, "What loads at startup" — a non-fork subagent's initial context contains
  "every level of the CLAUDE.md hierarchy the main conversation loads, including
  `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, and managed policy files." The qualifier
  *the main conversation loads* is what bounds this check: memory documents lazy loading for
  "path-specific rules or lazy-loaded files in subdirectories", so those are outside the guarantee.

### I15: Cross-surface instruction conflict

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all — but the unit is
a **pair**, so this row is answered by Phase B2 rather than by a per-surface lane.

- **Detect:** two instruction surfaces that both constrain the same decidable act and prescribe
  incompatible actions for at least one input firing both, with no resident text arbitrating between
  them. The unit of judgment is the pair, never one document read alone — which is why the
  per-surface lanes are structurally blind to it. The five gates that make this checkable, the
  residency table gate 1 resolves against, and the precedence table separating what the docs settle
  from what they leave unresolved all live in
  [conflict-criteria.md](conflict-criteria.md); that file is this row's adjudication procedure.
- **Comparison set:** every pair drawn from the surfaces Phase A inventoried, including the ones it
  recorded as *skipped* — plugin-cache content, managed materializations, org policy — since a
  contradiction is real whether or not this repository may edit either side. Resolve `@path` imports
  and symlinks to their targets before pairing, so an imported file is compared as part of the
  surface importing it rather than as a separate one.
- **Excluded from the comparison set:** `AGENTS.md` and other files that are not Claude Code
  instruction surfaces. They shape no behavior here, so a divergence between one and a `CLAUDE.md`
  is not a conflict this check reports.
- **Remediate by scope**, never by picking a winner the docs do not name. Where the precedence table
  cites a documented order, name the winner and its source. Where it does not, report the pair as
  `unresolved` with both anchors quoted and let the operator choose. Where the same conflict keeps
  recurring, offer the mechanism route — a `PreToolUse` hook, a `permissions.deny` rule, or a skill's
  own `disallowed-tools` — since a mechanism outranks instruction text.
- **Must NOT flag:** two surfaces that can never be resident together (that is orphaned instruction
  drift, reported separately). Different observables sharing a keyword. The same verb over different
  objects. An absolute carrying its own exception beside a directive presupposing that exception. A
  pair one of whose sides already states which wins. The full set with worked instances is in
  [conflict-criteria.md](conflict-criteria.md).
- **Source:** memory — "If two rules contradict each other, Claude may pick one arbitrarily", which
  is why an unarbitrated pair is a finding rather than a stylistic note.

### I16: Definition-site locality

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** an instruction that governs one named thing — a tool, a script, a subsystem, a skill —
  living somewhere other than that thing's own definition: a rule about tool X in a global
  always-loaded file rather than beside X.
- **Different axis from I3, and both can fire on one instruction.** I3 is load *timing*; this is
  definition-site *locality*. An instruction can be correctly deferred — already in a skill or a
  path-scoped rule — and still sit away from the thing it governs.
- **Must not flag:** an instruction that genuinely applies across the whole target, which is I3's
  broad-applicability case and not a locality defect; or one whose subject has no definition site to
  sit beside.
- **Remediate:** move it beside its subject — the skill body, the agent definition, the tool's own
  documentation. **The destination must be a surface Claude loads.** This check diagnoses locality,
  not load timing, so a move that lands an always-loaded instruction in an ordinary README or
  reference file silently drops the behavior it enforced unless Claude independently reads that file.
  Where the subject's definition site is not itself loaded, propose the colocated text *plus* a
  retained one-line pointer on a loaded surface that triggers reading it — never a bare move.
  Reported only, never fix-applied, per the `OPINION` policy above.
- **Source:** none. No official page states definition-site locality, which is why this check is
  `OPINION`-tier. The *routing* half — which surface a class of content belongs in — is documented
  at features-overview, "Compare similar features", and is I3's concern, not this check's.

### I17: Thinking disabled at an effort level that forbids it

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. Unscoped —
promotion gate MET: the claim is stated on a model-agnostic feature page, not in a model guide.
**The model range is a Detect condition, not a `Model scope` annotation.** The source says the
restriction "applies to Claude Opus 5 and later models", and the annotation's exact-string matching
has no range form — annotating `opus-5` would make the row inert on the next generation while the
restriction still holds. I20 handles a model range the same way.

Each row below carries its own decisive source; they share a subject, not a citation.

**Base row: the rejected pairing.**

- **Detect:** a surface that recommends, documents, or sets a **thinking-disable surface** —
  `MAX_THINKING_TOKENS=0`, `alwaysThinkingEnabled: false`, the `/config` global toggle, the
  `Alt+T` / `Option+T` session toggle, or API `thinking: {"type": "disabled"}` — together with
  `xhigh` or `max` effort, on Claude Opus 5 or a later model. Both operands are configuration
  literals, so a surface prescribing both publishes a per-request 400 that nothing recovers.
- **Effort literals do not all reach every surface, and the literal set is not the whole set.**
  `max` reaches a session through `CLAUDE_CODE_EFFORT_LEVEL`, `--effort`, `/effort`, or skill and
  subagent `effort` frontmatter — the frontmatter case being a surface this skill already
  inventories. **`ultracode` also trips this** without matching either literal: it is a Claude Code
  setting rather than an effort level and "sends `xhigh` to the model", so a surface pairing it with
  a thinking-disable surface produces the identical rejection. Match on the effort that reaches the
  request, not on the spelling.
- **Remediate:** lower the effort to `high` or below, or leave thinking on — and state which, since
  the pairing has no third resolution.
- **Scope, and where the config check lives:** this row audits **instruction text**. The same
  pairing expressed as *settings keys* is a config-mechanics finding and belongs to
  `claude-config:audit`, per this skill's own routing — an instruction-content catalog that also
  scanned settings files would claim authority a sibling already holds. Instruction text that
  happens to *live* in a settings file, such as a prompt-type hook's injected text, stays here: the
  discriminator is whether the content instructs, not which file holds it.
- **Must NOT flag:** `effortLevel: max` as a literal to hunt — the settings schema accepts `"low"`,
  `"medium"`, `"high"`, `"xhigh"` only, so that string is unreachable there and an auditor sent
  after it finds nothing and learns nothing. **A document that states the pairing in order to
  describe or forbid it** — this row, a model-adaptation delta chapter, a verification record
  quoting it — on the same audience test I8-b applies: the pairing prescribed inside an operative
  directive is a finding; a document *about* the pairing is not. A thinking-disable surface named
  with no effort level in reach of it.
- **Source:** effort — "On Claude Opus 5, thinking cannot be disabled at `xhigh` or `max` effort:
  requests that set `thinking: {"type": "disabled"}` at those levels return a 400 error."
  Corroborated at thinking-troubleshooting, which supplies the model range and adds that the
  restriction "is enforced on each request". The per-surface value sets are read from the surfaces'
  own pages: settings for `effortLevel`, environment variables for `CLAUDE_CODE_EFFORT_LEVEL`,
  skills and subagents for `effort` frontmatter, and model configuration for `/effort`, the session
  and global thinking toggles, and ultracode.
- **Verified 2026-08-02** against those pages, fetched as raw markdown. **Recheck trigger:** the
  effort level set gaining or losing a name, or the restriction's model range moving.

**Row I17-a: `MAX_THINKING_TOKENS=0` presented as a universal off switch** · Tier `mechanical` ·
Severity `warning`.

- **Detect:** text stating or implying that `MAX_THINKING_TOKENS=0` turns thinking off generally.
  It does not. On Fable 5 it has no effect at all — nor do the session toggle or
  `alwaysThinkingEnabled` — and on third-party providers it omits the `thinking` parameter instead,
  so an adaptive-reasoning model may still think. Also flag text treating
  `CLAUDE_CODE_DISABLE_THINKING` as equivalent: that variable omits the parameter on every
  provider, which on a model that thinks by default leaves it still thinking.
- **Remediate:** carry the exceptions with the claim, or point at the page instead of restating it.
- **Adjacent axis:** this is also a harness-capability claim, so **I12 can fire on the same line**.
  I12 asks whether the claim matches its page; this row asks whether a reader following it gets the
  behavior they were promised. Report both when both hold.
- **Must NOT flag:** a mention that already carries the Fable 5 or third-party exception. A bare
  reference to the variable making no claim about its reach.
- **Source:** environment variables — `MAX_THINKING_TOKENS` "Set to `0` to disable thinking on the
  Anthropic API, except on Fable 5, which cannot have thinking turned off; on third-party providers,
  `0` omits the `thinking` parameter instead". Model configuration heads the same control "Disable
  regardless of effort", so a surface repeating that heading unqualified inherits a claim the
  variable's own page contradicts.
- **Verified 2026-08-02** against those two pages, fetched as raw markdown. **Recheck trigger:** the
  set of models that cannot disable thinking changing.

**Row I17-b: mid-session effort change prescribed without its cost** · Tier `mechanical` ·
Severity `info`.

- **Detect:** an instruction directing a reader to change effort part-way through a session without
  naming what it costs. Effort is part of the cache key, so the next request re-reads the whole
  conversation uncached.
- **Must NOT flag: a Claude Code surface**, where the harness already surfaces the cost — it "asks
  you to confirm before applying the change", and a change resolving to the level already in effect
  skips the dialog and keeps the cache. This row is for surfaces instructing an API or Agent SDK
  caller, where no dialog exists. Nor flag a change prescribed *with* its cost stated, which is the
  remediation.
- **Remediate:** name the re-read cost, and prefer choosing effort at session start.
- **Source:** prompt caching — "**Effort level**: each effort level has its own cache for the same
  model. Changing it mid-session recomputes the entire request, and Claude Code asks you to confirm
  before applying the change."
- **Verified 2026-08-02** against that page, fetched as raw markdown. **Recheck trigger:** effort
  leaving the cache key, or the confirmation behavior changing.

### I18: Thinking blocks altered on the way back to the model

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. Unscoped —
promotion gate MET: the round-trip protocol is stated on a model-agnostic feature page, not in a
model guide.

- **Detect:** instruction text directing an agent, a script, or a reader to handle assistant content
  blocks in a way that breaks the round-trip protocol. Three shapes:
  1. **Dropping the `signature`.** An instruction to reconstruct, summarize, re-serialize, or
     hand-assemble an assistant turn before sending it back, where the reconstruction does not
     carry each `thinking` block's `signature` through unchanged. The server decrypts that field to
     rebuild the reasoning; a block without it is not the block the model produced.
  2. **The type-filter smell.** An instruction to select content blocks by testing
     `block.type == "thinking"` when round-tripping tool-use responses. The predicate silently
     omits `redacted_thinking` blocks, which the protocol requires back unchanged.
  3. **Within-turn echo integrity.** An instruction to reorder, edit, truncate, or partially drop
     the consecutive `thinking` blocks of the latest assistant message — including "keep only the
     last one" and "strip thinking before resending" advice. Modified blocks are rejected with a
     400.
- **Reach — this is wider than Messages API client code.** Any instruction whose output eventually
  becomes a request body is in scope: Agent SDK callers, harness integrations, and **tooling that
  parses, excerpts or rewrites a stored transcript that will later be replayed or resumed**. What
  puts a surface in scope is a path back to the model, not the file format it reads.
- **Remediate:** echo the assistant `content` array back unchanged rather than rebuilding it; where
  blocks must be selected, select by what is being *excluded* rather than by an equality test on one
  type name; where a transcript is being read for analysis only, say so, since a read that never
  re-sends is outside the protocol entirely.
- **Must NOT flag:** an instruction to read or analyze a transcript with no path back to the model —
  metrics extraction, retrospectives, search. **A `redacted_thinking` clause premised on those blocks
  being present in local transcripts**, which is a separate and unevidenced claim; this row's
  concern is only that a type filter would drop them if the API returned them. Pruning of *prior*
  turns' thinking, which the API does for you and which the page explicitly allows outside tool use.
  **A document that names the type-filter predicate in order to describe the smell** — this row,
  a model-adaptation delta chapter, a verification record quoting it — on the same audience test
  I8-b applies: the predicate quoted inside an operative directive is still operative and is a
  finding; a document *about* the pattern is not.
- **Source:** Thinking, "Preserving thinking blocks" — "Pass every `thinking` block back to the API
  complete and unmodified, alongside the `tool_use` block it accompanied", and "Within the latest
  assistant message, the sequence of consecutive `thinking` blocks must match what the model
  generated in the original request: you can't rearrange, edit, or partially drop them." Same page,
  "Thinking encryption" — "Full thinking content is encrypted and returned in the `signature` field
  on each thinking block" — and "Redacted thinking blocks" — "Filtering on
  `block.type == "thinking"` alone silently drops `redacted_thinking` blocks and breaks the
  multi-turn protocol".
- **Local coverage, measured 2026-08-02: zero instances of all three shapes in the repository that
  authored this row**, which ships it consumer-facing and unexercised by its own corpus. Stated so
  the absence reads as an as-of measurement rather than as a passed check. **Re-measure when** a
  round-trip or transcript-replay path lands here.
- **Verified 2026-08-02** against the Thinking page, fetched as raw markdown. **Recheck trigger:** a
  content-block type joining or leaving the set the protocol requires echoed back.

### I19: Restated external benchmark figure with no recheck trigger

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** a surface restating a named benchmark's score, ranking, or suite version — a model
  comparison table, a launch-figure list, a "state of the art on X" claim — carrying no recheck
  trigger. Benchmark figures are attested by an announcement at a moment: suites revise, vendors
  report against a different harness, and a later release reorders the table, so a figure with no
  stated re-derivation event silently becomes a claim about the past told in the present tense.
- **Remediate:** either point at the vendor's announcement and restate nothing, or keep the figure
  and attach the four-part record — the claim, the announcement it came from, the as-of date, and a
  trigger naming an observable event (a new frontier-model release, a suite version bump, a decision
  that would turn on the figure). Label the figures as launch-day snapshots where that is what they
  are; leaving them as history is a valid outcome and usually the right one.
- **Must NOT flag: a verbatim upstream baseline held for drift detection.** A vendored copy exists
  to be compared byte-for-byte against its source, so stamping it would corrupt the comparison it
  exists to serve — this is a genuine suppression, not a routing case, which is what distinguishes
  it from plugin-cache content and managed materializations: those are still flagged, and the
  finding becomes a routing recommendation to the owning repository. Flag the locally-owned surface
  that *restates* the figure, never the baseline it was restated from.
- **Must NOT flag:** a benchmark named as a pointer with no figure attached. A figure already
  carrying a trigger, whatever heading that trigger sits under.
- **Source:** none. No official page states that a restated benchmark figure needs a re-derivation
  event, which is why this check is `OPINION`-tier and off by default. The four-part shape it asks
  for is this monorepo's `docs/conventions/upstream-drift/README.md`; in a standalone install the
  four parts, not the path, are the requirement.

### I20: Prefilled assistant response

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all — `error` because
following the instruction produces a rejected request, the same consequence class as I17 and I18,
not because instances are expected to be common.

- **Detect:** instruction text that tells a caller to prefill Claude's response — to supply a
  partial assistant message on the last turn so the model continues from it. The classic uses are
  the tells: forcing a JSON or YAML shape, opening with `Here is the requested summary:` to skip
  preamble, steering around a refusal, resuming an interrupted generation, and re-injecting context
  as a pseudo-assistant reminder.
- **Remediate:** the technique is not deprecated advice but a rejected request — on current models a
  prefilled last assistant turn returns a 400. Replace it per use: state the output contract in the
  `user` turn or a structured-output facility for format control, ask directly for no preamble,
  prompt clearly rather than prefill past a refusal, and move context reinjection into the user turn
  or a tool.
- **Must NOT flag:** an assistant message anywhere other than the last turn, which is unaffected.
  **A document that names the technique or its tells in order to describe it as retired** — this
  row, a migration guide, a model-delta chapter — on the same audience test I8-b applies: a prefill
  prescribed inside an operative directive is a finding; a document *about* prefill is not.
  Instructions targeting an explicitly pinned earlier model, which still supports it.
- **Source:** prompting best practices, "Migrating away from prefilled responses" — "Starting with
  Claude 4.6 models and Claude Mythos Preview, prefilled responses (providing a partial assistant
  message for Claude to continue from) on the last assistant turn are no longer supported. Requests
  with prefilled assistant messages to these models return a 400 error… Earlier models continue to
  support prefills, and adding assistant messages elsewhere in the conversation is not affected."
- **Verified 2026-08-02** against that page, fetched as raw markdown; the standalone prefill
  technique page now redirects to the prompt-engineering overview. **Recheck trigger:** any change to
  that page, or the unsupported-model range moving.

---

## Stopping condition

Authority `OPINION` · applies to I6 and I8 · **enabled by default**, opt out with
`--no-stopping-condition`.

Neither I6 nor I8 carries an a-priori bound: I6's only escape is a rewrite concession and I8's
remediation is unconditional, so both trim without a floor. This rule **withholds** findings rather
than emitting them, which is why it inverts the `OPINION` default above — disabling it does not make
the audit more conservative, it removes the only bound on two trimming checks and makes both strictly
more aggressive.

- **Withhold** an I6 or I8 proposal where the instruction guards a high-consequence area: a safety
  gate, an irreversible or destructive action, a security or permission boundary, an external
  contract, or genuine ordering another step depends on. De-prescription is the default posture; it
  is not the posture in the places where being wrong is expensive.
- **Report every withholding** in the run's own section, naming the check it moderated and the
  ground. A silently suppressed finding reads as coverage.
- **Source:** none — the "except in highly important areas" carve-out appears on no official page,
  and it is the calibration knob the de-prescription guidance (I8's Fable 5 source) leaves unset.

---

## Output format

Findings are presented using the Phase D report table defined in the skill body
([SKILL.md](../SKILL.md)), one proposed diff per finding — the column set lives there and is not
restated here.

A clean audit ("No instructions flagged.") is a valid outcome. Behavioral-tier proposals are
always presented as proposals paired with the delete-and-watch follow-through, never as confident
removals.
