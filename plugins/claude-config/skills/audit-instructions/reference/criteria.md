# Instruction-Audit Criteria

Version: 1.1.0
Last updated: 2026-07-25

The checks the `audit-instructions` skill runs, seeded from current official prompting doctrine.
Each check carries an evidence tier, an authority tag, a default severity, its surface
applicability, and one decisive source line (point-don't-copy — the full doctrine lives at the
cited URL, not restated here).

**Recheck triggers** — treat these as staleness signals and re-verify the catalog against live
docs when any fires: a new frontier model release; **a change to any page listed under Sources
below**. Every check cites one of those pages, so the trigger set is the source set — naming a
subset would leave the harness-behavior rows depending on pages nothing watches. Model-specific
pages (the Fable 5 guide) are superseded on each model generation.

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier** — `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified by the delete-and-watch
  loop, never confident removals).
- **Authority** — `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice). A closed three-value set. All fifteen checks are currently
  `ANTHROPIC-DOCS`.
- **Severity** — `error` / `warning` / `info`.

**Surface partition.** Checks I1–I5 are the instruction-memory hygiene layer: they apply on
non-memory surfaces (skill bodies, agent definitions, prompt-type hooks, output styles); on
memory-layer surfaces (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`) their
findings route to the `claude-memory` plugin's `audit` skill when it is installed, and fall back
to the official include/exclude guidance (I1–I5 source below) when it is not. Checks I6–I12 and I15 apply
to all surfaces; I13 and I14 name narrower surface sets in their own rows.

## Sources

- Claude Code best practices — <https://code.claude.com/docs/en/best-practices>
- Prompting best practices —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Prompting Claude Fable 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- Memory (CLAUDE.md, rules, auto memory) — <https://code.claude.com/docs/en/memory>
- The `.claude` directory — <https://code.claude.com/docs/en/claude-directory>
- Refusals and fallback (`reasoning_extraction`) —
  <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
- CLI reference (`claude doctor` and the other terminal forms) —
  <https://code.claude.com/docs/en/cli-reference>
- Subagents (what loads into a subagent at startup) — <https://code.claude.com/docs/en/sub-agents>
- Skills (how a skill's supporting files are referenced and loaded) —
  <https://code.claude.com/docs/en/skills>

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
  quirks) living in an always-loaded surface.
- **Remediate:** move it to a skill or a path-scoped rule that loads on demand.
- **Source:** best-practices — "only include things that apply broadly. For domain knowledge or
  workflows that are only relevant sometimes, use skills instead."

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
- **Source:** prompting best-practices — "Tell Claude what to do instead of what not to do."

### I7: Reason with the request

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an instruction that states a request with no intent or motivation attached.
- **Remediate:** add the why — the model connects the task to relevant context instead of inferring
  intent on its own.
- **Source:** Fable 5 guide, "Give the reason, not only the request" — "Claude Fable 5 tends to
  perform better when it understands the intent behind a request."

### I8: Model-era re-audit

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** prior-model workarounds and over-prescriptive step lists — instructions enumerating
  behaviors a current model handles from a brief instruction, or scaffolding that pins an approach.
- **Remediate:** propose removal or a briefer instruction; verify via the delete-and-watch loop
  that default performance holds or improves.
- **Source:** Fable 5 guide — "Skills developed for prior models are often too prescriptive for
  Claude Fable 5 and can degrade output quality."

### I9: Example hygiene

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an example block that pins the model's *approach* to a task (behavioral scaffolding).
  Do not flag examples that steer output format, tone, or structure — those remain recommended.
- **Remediate:** keep 3–5 diverse format/tone/structure examples; propose trimming or reframing
  only approach-pinning ones, A/B'd against the no-example default.
- **Source:** prompting best-practices, "Use examples effectively" — examples are "one of the most
  reliable ways to steer Claude's output format, tone, and structure"; keep them diverse enough
  "that Claude doesn't pick up unintended patterns."

### I10: Reasoning-echo directives

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all.

- **Detect:** instructions telling the model to show, echo, transcribe, or explain its internal
  reasoning as response text. The deterministic pre-scan marks show-your-thinking phrasing.
- **Remediate:** remove them; read structured `thinking` blocks or use a send-to-user tool if
  reasoning visibility is needed.
- **Source:** Fable 5 guide — such instructions "can trigger the `reasoning_extraction` refusal
  category on Claude Fable 5, causing elevated fallbacks."

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
(skill bodies and their reference files, agent definitions, prompt-type hooks, output styles).

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

---

## Output format

Findings are presented using the Phase D report table defined in the skill body
([SKILL.md](../SKILL.md)), one proposed diff per finding — the column set lives there and is not
restated here.

A clean audit ("No instructions flagged.") is a valid outcome. Behavioral-tier proposals are
always presented as proposals paired with the delete-and-watch follow-through, never as confident
removals.
