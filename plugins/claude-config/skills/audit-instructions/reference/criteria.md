---
version: 1.2.0
last-updated: 2026-07-25
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
fires the whole catalog, not the check that noticed it. Model-specific pages (the Fable 5 guide) are
superseded on each model generation.

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier** — `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified by the delete-and-watch
  loop, never confident removals).
- **Authority** — `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice). A closed three-value set.
- **Severity** — `error` / `warning` / `info`.

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
non-memory surfaces (skill bodies, agent definitions, prompt-type hooks, output styles); on
memory-layer surfaces (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`) their
findings route to the `claude-memory` plugin's `audit` skill when it is installed, and fall back
to the official include/exclude guidance (I1–I5 source below) when it is not. Checks I6–I12 and
I15–I16 apply to all surfaces; I13 and I14 name narrower surface sets in their own rows. I15 routes
on the same convention for the narrower case its own entry states.

## Sources

- Claude Code best practices — <https://code.claude.com/docs/en/best-practices>
- Prompting best practices —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Prompting Claude Fable 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- Memory (CLAUDE.md, rules, auto memory) — <https://code.claude.com/docs/en/memory>
- The `.claude` directory — <https://code.claude.com/docs/en/claude-directory>
- Skills (what loads when, how supporting files are referenced, the listing budget,
  invocation-control fields) — <https://code.claude.com/docs/en/skills>
- How features layer (per-surface precedence, routing between surfaces) —
  <https://code.claude.com/docs/en/features-overview>
- Context window (what survives compaction) — <https://code.claude.com/docs/en/context-window>
- Refusals and fallback (`reasoning_extraction`) —
  <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
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
- **Adjacent axis:** this check is load *timing*. Definition-site *locality* — an instruction sitting
  away from the thing it governs — is I13, and an instruction can be correctly deferred here and
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
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Fable 5 guide — "Skills developed for prior models are often too prescriptive for
  Claude Fable 5 and can degrade output quality."

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

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** two live instructions that cannot both be satisfied, where no official layering rule
  already determines which one wins. A finding is a relation between two instructions, never a
  property of one line: it names both participating locations.
- **Comparison set** — every surface that can hold instruction text:
  - `CLAUDE.md` at every scope — managed policy, user, project root, nested, `CLAUDE.local.md`
  - `.claude/rules/`, both unscoped and `paths:`-scoped
  - skill bodies
  - agent definitions
  - prompt-type hooks, including hook text configured in `.claude/settings.local.json`
  - output styles

  The comparison set is not narrowed by a scope argument. A conflict is a relation between two
  surfaces, so a run scoped to one surface still needs the others inventoried to find the
  counterpart; the scope filter governs which side may *produce* a finding, never which surfaces are
  read. Phase A's inventory contract states this obligation.
- **Compare only definitions that can be live together.** Two surfaces that can never be active in
  the same context are alternatives, not an unsatisfiable pair: only the selected output style
  applies to a session, and two agent definitions execute in separate subagent contexts. Filter the
  comparison set by co-activation before comparing, and compare an agent or output-style definition
  against the surfaces that *do* load alongside it rather than against its own siblings.
- **Resolve before comparing — imports only where the surface implements them.** `@path` expansion is
  a memory-surface behavior: `CLAUDE.md` at every scope, `CLAUDE.local.md`, and `.claude/rules/` files
  import additional files, and those files are "expanded and loaded into context at launch"
  (<https://code.claude.com/docs/en/memory>). Expand imports on those surfaces, and resolve symlinks
  everywhere, before comparing. An imported file's content is live instruction text, so a detector
  that reads only the importing file compares a different surface than the model sees, and every
  `@docs/foo.md` import is invisible to it.
- **An `@path`-shaped reference in a skill body or agent definition is not an import.** No official
  page extends import expansion beyond the memory surfaces, and a skill's supporting files are read on
  demand when the skill needs them rather than loaded at launch
  (<https://code.claude.com/docs/en/skills>). Expanding one anyway would let I15 report conflicts
  against instructions that were never in context. Treat it as an ordinary pointer: the pointing line
  is comparable, the pointed-at file is not — it enters the comparison set only on its own merits, as
  a skill body or agent definition the inventory already collected.
- **`AGENTS.md` is deliberately not in the comparison set.** The memory doc's own `AGENTS.md`
  section states it outright — "Claude Code reads `CLAUDE.md`, not `AGENTS.md`" — and prescribes an
  `@AGENTS.md` import or a symlink as the way to make one load
  (<https://code.claude.com/docs/en/memory>). A stock install never loads it, so flagging it would
  false-positive on every repo that keeps one for other tools. Its content enters the comparison set
  exactly when a loaded surface imports or symlinks it — through the resolution step above, not as a
  surface of its own.
- **Routing — `claude-memory:audit` C6 is the incumbent inside the memory layer**, on the same
  convention I1–I5 already run:
  - A contradiction **wholly inside the memory surfaces C6 actually inventories** — the project-root
    `CLAUDE.md` / `CLAUDE.local.md` and the project `.claude/rules/` tree — is C6's. I15 does not
    report it, so one finding is emitted rather than two from two plugins with no reconciliation rule
    between them.
  - **Cede only what the incumbent can see.** C6's discovery is bounded to those project-root and
    project-rules files, so a memory-layer contradiction that reaches a surface outside them — a
    user-scope `CLAUDE.md` or `~/.claude/rules/` file, or a nested `CLAUDE.md` below the project root
    — stays I15's. Ceding it would leave it unchecked by both plugins. Confirm the incumbent's
    discovery scope before ceding, and cede a pair only when *both* sides fall inside it.
  - A contradiction with **at least one side outside** the memory layer — a skill body, an agent
    definition, a prompt-type hook, an output style — is I15's, and nothing else covers it.
  - Anything involving the **managed-policy tier** is I15's, read-only.
  - When `claude-memory` is **not installed**, report that memory-layer contradictions go unchecked
    and name `claude-memory:audit` as the skill that performs them. This check still does not
    perform them.
- **Must not flag:**
  - a more-specific instruction narrowing a broader one — for `CLAUDE.md` conflicts the docs state
    that Claude reconciles by judgment with more specific instructions typically taking precedence,
    so a nested file tightening a root rule is the mechanism working
  - format-steering against behavior-steering — they govern different things, the same distinction
    I9 draws when it refuses to flag format-steering examples
  - two **conditional** instructions whose conditions are disjoint, so neither can fire on the same
    file — two `paths:`-scoped rules over `src/**` and `docs/**`, say. An unconditional instruction
    always applies, so it can never be the disjoint side of this pair: an unconditional rule that
    contradicts a path-scoped one *is* a conflict on the paths the scoped rule covers.
  - two instructions that agree in substance and differ only in wording — redundancy is I1's concern
  - a shadowed same-named skill or subagent: exactly one is live, so this is a resolved override, not
    a conflict (see the adjacent report below)
- **Adjacent report, not a conflict finding:** where a skill or subagent is shadowed by a same-named
  definition at a higher-precedence scope, report it in its own `info` section naming the live
  definition and the inert one. It is worth telling an operator about — an inert definition that
  looks live is its own trap — but it is name comparison across a known precedence order and belongs
  in the mechanical tier, not in this check's judged findings. Skills and subagents are the whole
  contract: they are the shadowable definitions Phase A already inventories. Same-named MCP servers
  across scopes are deliberately **not** covered — this skill inventories no MCP configuration and
  routes `.mcp.json` mechanics to `claude-config:audit`, so promising an MCP shadow report here
  would promise a finding with no data behind it.
- **Remediate, by scope, and never a default deletion:**
  - **Both sides operator-owned:** reconcile, and say which one to change. A conflict is evidence
    that two intentions exist, and which is correct is not derivable from the text — so do not
    propose deleting either side by default.
  - **One side managed policy:** report as "conflicts with org policy at `<path>`", and propose no
    edit — neither to the policy side, nor to the lower side justified by the conflict alone.
    `claudeMdExcludes` cannot reach the managed tier, so seeking an exception may be the correct
    resolution, and that is an organizational decision rather than a linting one. Such a finding
    carries the report's **no-change representation** in place of a diff — Phase D exempts it from
    the per-finding fenced-diff contract rather than forcing an edit this rule forbids.
  - **One side a user-scope file under a dotfile manager:** route as a recommendation through that
    repository, never an in-place edit.
- **Source:** memory, "Consistency" — "if two rules contradict each other, Claude may pick one
  arbitrarily. Review your CLAUDE.md files, nested CLAUDE.md files in subdirectories, and
  `.claude/rules/` periodically to remove outdated or conflicting instructions."; features-overview,
  "Understand how features layer", for the per-surface precedence rules that decide when a difference
  is already resolved.

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
