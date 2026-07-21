# Instruction-Audit Criteria

Version: 1.0.0
Last updated: 2026-07-21

The checks the `audit-instructions` skill runs, seeded from current official prompting doctrine.
Each check carries an evidence tier, an authority tag, a default severity, its surface
applicability, and one decisive source line (point-don't-copy — the full doctrine lives at the
cited URL, not restated here).

**Recheck triggers** — treat these as staleness signals and re-verify the catalog against live
docs when any fires: a new frontier model release; any change to the two prompting-best-practices
pages; a change to the Claude Code best-practices page. Model-specific pages (the Fable 5 guide)
are superseded on each model generation.

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier** — `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified by the delete-and-watch
  loop, never confident removals).
- **Authority** — `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice). All eleven seeds are `ANTHROPIC-DOCS`.
- **Severity** — `error` / `warning` / `info`.

**Surface partition.** Checks I1–I5 are the instruction-memory hygiene layer: they apply on
non-memory surfaces (skill bodies, agent definitions, prompt-type hooks, output styles); on
memory-layer surfaces (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`) their
findings route to the `claude-memory` plugin's `audit` skill when it is installed, and fall back
to the official include/exclude guidance (I1–I5 source below) when it is not. Checks I6–I11 apply
to all surfaces.

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

---

## Output format

Findings are presented using the Phase D report table defined in the skill body
([SKILL.md](../SKILL.md)), one proposed diff per finding — the column set lives there and is not
restated here.

A clean audit ("No instructions flagged.") is a valid outcome. Behavioral-tier proposals are
always presented as proposals paired with the delete-and-watch follow-through, never as confident
removals.
