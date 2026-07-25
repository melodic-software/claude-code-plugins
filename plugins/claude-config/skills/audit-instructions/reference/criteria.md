---
version: 1.1.0
last-updated: 2026-07-24
---

# Instruction-Audit Criteria

The checks the `audit-instructions` skill runs, seeded from current official prompting doctrine.
Each check carries an evidence tier, an authority tag, a default severity, its surface
applicability, and one decisive source line (point-don't-copy — the full doctrine lives at the
cited URL, not restated here).

**Recheck triggers** — treat these as staleness signals and re-verify the catalog against live
docs when any fires: a new frontier model release; any change to the two prompting-best-practices
pages; a change to the Claude Code best-practices page; a change to the memory, feature-layering,
or context-window pages, which carry the consistency, precedence, and compaction statements I3,
I12, and I13 rest on. One staleness event fires the whole catalog, not the check that noticed it.
Model-specific pages (the Fable 5 guide) are superseded on each model generation.

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier** — `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified by the delete-and-watch
  loop, never confident removals).
- **Authority** — `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice).
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
to the official include/exclude guidance (I1–I5 source below) when it is not. Checks I6–I13 apply
to all surfaces; I12 routes on the same convention for the narrower case its own entry states.

## Sources

- Claude Code best practices — <https://code.claude.com/docs/en/best-practices>
- Prompting best practices —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Prompting Claude Fable 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- Memory (CLAUDE.md, rules, auto memory) — <https://code.claude.com/docs/en/memory>
- The `.claude` directory — <https://code.claude.com/docs/en/claude-directory>
- How features layer (per-surface precedence, routing between surfaces) —
  <https://code.claude.com/docs/en/features-overview>
- Context window (what survives compaction) — <https://code.claude.com/docs/en/context-window>
- Refusals and fallback (`reasoning_extraction`) —
  <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>

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
- **Remediate:** move it to a skill or a path-scoped rule that loads on demand. **A destination
  qualifies only if it defers loading** — `@path` imports do not, so a split into imports is an
  organizational change and not a context saving, and proposing one satisfies this check's letter
  while changing the load profile not at all. **State the move cost with the recommendation:** a
  `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file is
  read again, so content that must survive compaction stays unscoped or in the project-root
  `CLAUDE.md`.
- **Adjacent axis:** this check is load *timing*. Definition-site *locality* — an instruction sitting
  away from the thing it governs — is I13, and an instruction can be correctly deferred here and
  still misplaced there.
- **Source:** best-practices — "only include things that apply broadly. For domain knowledge or
  workflows that are only relevant sometimes, use skills instead."; memory — "splitting into `@path`
  imports helps organization but doesn't reduce context, since imported files load at launch";
  context-window, "What survives compaction", for the per-destination cost.

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

### I12: Cross-surface instruction conflict

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** two live instructions that cannot both be satisfied, where no official layering rule
  already determines which one wins. A finding is a relation between two instructions, never a
  property of one line: it names both participating locations.
- **Comparison set** — every surface that can hold instruction text:
  - `CLAUDE.md` at every scope — managed policy, user, project root, nested, `CLAUDE.local.md`
  - `.claude/rules/`, both unscoped and `paths:`-scoped
  - skill bodies
  - agent definitions
  - prompt-type hooks
  - output styles
- **Resolve before comparing.** Expand `@path` imports and resolve symlinks first. An imported file's
  content is live instruction text — imported files load at launch — so a detector that reads only
  the importing file compares a different surface than the model sees, and every `@docs/foo.md`
  import is invisible to it.
- **`AGENTS.md` is deliberately not in the comparison set.** Claude Code reads `CLAUDE.md`, not
  `AGENTS.md`, so a stock install never loads it and flagging it would false-positive on every repo
  that keeps one for other tools. Its content enters the comparison set only when a loaded surface
  imports it — through the import expansion above, not as a surface of its own.
- **Routing — `claude-memory:audit` C6 is the incumbent inside the memory layer**, on the same
  convention I1–I5 already run:
  - A contradiction **wholly inside** the memory layer (CLAUDE.md, CLAUDE.local.md, rules files) is
    C6's. I12 does not report it, so one finding is emitted rather than two from two plugins with no
    reconciliation rule between them.
  - A contradiction with **at least one side outside** the memory layer — a skill body, an agent
    definition, a prompt-type hook, an output style — is I12's, and nothing else covers it.
  - Anything involving the **managed-policy tier** is I12's, read-only.
  - When `claude-memory` is **not installed**, report that memory-layer contradictions go unchecked
    and name `claude-memory:audit` as the skill that performs them. This check still does not
    perform them.
- **Must not flag:**
  - a more-specific instruction narrowing a broader one — for `CLAUDE.md` conflicts the docs state
    that Claude reconciles by judgment with more specific instructions typically taking precedence,
    so a nested file tightening a root rule is the mechanism working
  - format-steering against behavior-steering — they govern different things, the same distinction
    I9 draws when it refuses to flag format-steering examples
  - a conditional and an unconditional instruction whose conditions are disjoint, so neither can fire
    on the same file
  - two instructions that agree in substance and differ only in wording — redundancy is I1's concern
  - a shadowed same-named skill, subagent, or MCP server: exactly one is live, so this is a resolved
    override, not a conflict (see the adjacent report below)
- **Adjacent report, not a conflict finding:** where a skill, subagent, or MCP server is shadowed by
  a same-named definition at a higher-precedence scope, report it in its own `info` section naming
  the live definition and the inert one. It is worth telling an operator about — an inert definition
  that looks live is its own trap — but it is name comparison across a known precedence order and
  belongs in the mechanical tier, not in this check's judged findings.
- **Remediate, by scope, and never a default deletion:**
  - **Both sides operator-owned:** reconcile, and say which one to change. A conflict is evidence
    that two intentions exist, and which is correct is not derivable from the text — so do not
    propose deleting either side by default.
  - **One side managed policy:** report as "conflicts with org policy at `<path>`", and propose no
    edit — neither to the policy side, nor to the lower side justified by the conflict alone.
    `claudeMdExcludes` cannot reach the managed tier, so seeking an exception may be the correct
    resolution, and that is an organizational decision rather than a linting one.
  - **One side a user-scope file under a dotfile manager:** route as a recommendation through that
    repository, never an in-place edit.
- **Source:** memory, "Consistency" — "if two rules contradict each other, Claude may pick one
  arbitrarily. Review your CLAUDE.md files, nested CLAUDE.md files in subdirectories, and
  `.claude/rules/` periodically to remove outdated or conflicting instructions."; features-overview,
  "Understand how features layer", for the per-surface precedence rules that decide when a difference
  is already resolved.

### I13: Definition-site locality

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
  documentation. Reported only, never fix-applied, per the `OPINION` policy above.
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
