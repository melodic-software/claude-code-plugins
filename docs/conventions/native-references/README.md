# Native references: presence-gated phrasing for Claude Code's own surfaces

Owner doc for **how a component in this marketplace refers to a native Claude Code surface**,
whether a built-in CLI command, a bundled skill, a plugin-backed built-in, or a session-provided
skill, when that surface materially overlaps what the component does. One shape: a read-time
presence gate that routes, never an assertion that the native thing is there.

The problem this closes is specific. A marketplace skill and a native surface can do overlapping
work, and the model picks between them from descriptions alone. Silence produces duplication; a
static claim ("Claude Code ships `/doctor`, so use that") produces a false statement in every
session where the surface is gated off. Both failures are avoided by the same sentence shape.

## Boundary

This doc owns the phrasing of references **to native surfaces**. It does not own:

- **Cross-plugin references.** [`seam-phrasing`](../seam-phrasing/README.md) owns the
  gate + fallback + ownership-framing shape for optional references to *another plugin's* skill.
  Its three elements are the template this doc specializes; a native surface is not a plugin, which
  is why the specialization needs its own owner rather than a clause in that doc.
- **Whether a reference should exist at all.** That is a verdict, and verdicts live in the
  committed overlap store rendered into [`docs/NATIVE-SURFACES.md`](../../NATIVE-SURFACES.md).
  This doc governs the words once a verdict says a reference is warranted.
- **The stamp discipline on any upstream fact a reference restates.**
  [`upstream-drift`](../upstream-drift/README.md) owns the four-part record (claim, basis, as-of
  date, recheck trigger) and the observability bar its triggers must clear.
- **Instruction economy.** [`PLUGIN-PHILOSOPHY`](../../PLUGIN-PHILOSOPHY.md) owns the rule that
  every always-loaded description is a per-session tax. This doc keeps the phrase to one clause
  because of that rule; it does not restate it.

## Why a gate, and never an assertion

Native availability varies along at least four independent axes, so any static availability
sentence is wrong somewhere by construction:

| Axis | Mechanism |
|---|---|
| Settings / environment | `disableBundledSkills` and `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` remove bundled skills and workflows; `skillOverrides` maps a name to `on` / `name-only` / `user-invocable-only` / `off`; `DISABLE_DOCTOR_COMMAND` hides `/doctor` specifically |
| Plan | Some surfaces require a paid or specific plan tier |
| Platform / provider | Some surfaces are absent on some OSes, and several are unavailable on non-first-party model providers |
| Host surface | CLI, web/cloud, VS Code, and mobile expose different rosters; terminal-interface commands do not exist in a web session, and a cloud session carries session-provided skills a local CLI does not |

Claim, basis, and trigger for that table, per [`upstream-drift`](../upstream-drift/README.md):
the four axes are documented on `https://code.claude.com/docs/en/settings-reference.md`
(`disableBundledSkills`, `skillOverrides`), `https://code.claude.com/docs/en/env-vars.md`,
`https://code.claude.com/docs/en/commands.md` ("Not every command appears for every user.
Availability depends on your platform, plan, and environment."), and
`https://code.claude.com/docs/en/cloud-environments.md`; verified 2026-08-23; **recheck trigger**:
a Claude Code release note or docs change adds, removes, or renames a gating axis, or a
`skillOverrides` state leaves the four-value set.

The consequence is the rule: **a component never states that a native surface is present, absent,
enabled, or unavailable.** It states what to do *if the surface resolves in the session*, and the
model reads its own listing to decide.

## The description phrase

The routing-effective surface is the frontmatter `description`, because descriptions load into
model context by default while bodies load only on invocation. One clause, front-loaded, matching
this grammar:

```text
When the <class> <name> <surface-noun> resolves in your session, prefer it for <native's job>;
this skill for <ours>.
```

Four required parts:

1. **The gate**: `resolves in your session` (or `resolves in this session`). This is the
   canonical, greppable token. It is a read-time condition on the model's own listing, not a claim
   about the machine. `if installed`, `always available`, `Claude Code ships`, and `is built in`
   are all wrong here: the first is the cross-plugin gate, the rest are assertions.
2. **The provenance class**: `bundled`, `built-in`, `plugin-backed built-in`, or
   `session-provided`, named in the sentence. The classes behave differently (different disable
   switches, different rosters per host), and a reader who cannot tell which one they are looking
   at cannot check the gate.
3. **The routing split**: what the native surface is preferred *for*, and what this component is
   preferred *for*. A gate with no split tells the model a thing exists without telling it when to
   pick which, which is the duplication the reference exists to stop.
4. **Self-containment**: the phrase carries its own meaning with no external lookup.

Worked example, in the shipped shape:

```text
When the bundled doctor skill resolves in your session, prefer it for the quick native
health-and-fix pass; this skill for the deep read-only install-tree inventory.
```

**Absent is not a fallback state.** Unlike a cross-plugin seam, there is nothing to degrade to: the
component's own job is the fallback, and the split sentence already says what that job is. Do not
write "otherwise this skill", which is noise the shared budget pays for.

### Budget caveat

Descriptions are subject to two limits, and a baked phrase is the best available routing surface,
not a guaranteed one:

- the combined `description` + `when_to_use` text is truncated at **1,536 characters** in the
  listing by default (`skillListingMaxDescChars`); and
- the listing as a whole is capped at a **share of the context window**
  (`skillListingBudgetFraction`, default 1%). On overflow the listing keeps every skill *name* and
  drops whole descriptions, starting with the least-invoked skills.

Basis: `https://code.claude.com/docs/en/skills.md` (Frontmatter reference; Troubleshooting →
"Skill descriptions are cut short") and `https://code.claude.com/docs/en/settings-reference.md`;
verified 2026-08-23. **Recheck trigger**: a release or docs change moves the 1,536 default, the
1% default, or the drop-order rule.

Two obligations follow. Keep the phrase to one clause, since it spends shared budget every session
for every consumer. And where a fleet's listing plausibly overflows, the overlap store records a
per-row *phrase may be budget-dropped* caveat, so nobody later reads a baked phrase as a guarantee
that the model saw it.

### Open consideration: the bundled keep-set

A single-source, unconfirmed read of a shipped build suggests bundled entries may be exempt from
budget dropping, which would make native/marketplace routing asymmetric under pressure. It is
recorded here as an open consideration and **nothing in this convention builds on it**: no phrase,
no verdict, and no registry row may cite it until a live probe confirms it. **Recheck trigger**:
a live in-session probe confirms or refutes the exemption, or upstream documents the drop order at
the source level.

## The Boundary section

The Boundary section is the surface a verdict lands on. **A store row whose verdict is not `defer`
and whose observation is extraction-evidence lands together with its `## Boundary` section in the
component's body, in the same change.** A verdict that lives only in the store changes nothing the
model reads: the registry is a maintainer surface and shipped plugins never carry it, so until the
body says how the two surfaces relate, the overlap the row records is still silent at runtime.
The section costs nothing the description phrase costs. Bodies load only on invocation, so a
Boundary section spends no shared listing budget and changes no routing; the gate the phrase
earns (below) has no reason to hold the section back.

The section carries the conclusion: the surfaces by provenance class, the routing split, and the
mutation gate. The four-part records behind it (the basis each upstream specific rests on, its
as-of date, its recheck trigger, the extraction or docs evidence) live in a **reference file inside
the same skill**, linked from the section with a same-plugin relative path, so the body stays short
and the detail stays reachable. Modeled on the `review` plugin's organic pattern (`/review:quality-gate`
and `/review:fanout` each carry one):

```markdown
## Boundary, the bundled `<name>` skill

<One sentence naming the surfaces and why they are conflated.>

- **`<name>` (<provenance class>)**: what it does, what it mutates, how it is invoked.
- **`<name>` (<provenance class>)**: same.

**Routing:** <when to prefer each>.

**Mutation gate:** <which invocations mutate, and the explicit opt-in they require>.
```

Six properties the section keeps:

1. **Every overlapped surface named in the section, as a code span.** `## Boundary` on its own is
   a heading any prose satisfies, and several components carry one for a surface this convention
   has no verdict on. The heading naming the surface is the preferred shape and is what the
   template above shows; a generic `## Boundary` heading is still accepted when the section text
   names the surface, which is how one section covers a component that overlaps several. Either
   way the name is a code span, so a surface whose name is also an ordinary English word (`run`,
   `design`) is never satisfied by a sentence that happens to use the word.
2. **Surfaces named by provenance class**, exactly as in the description phrase.
3. **A mutation gate per surface that mutates.** Naming an overlap without naming what it writes
   invites an unrequested mutation.
4. **One owning description, pointers elsewhere.** Where two components in the *same plugin* both
   overlap the surface, one carries the description and the other points at it with a same-plugin
   relative link and adds only what is specific to itself. Cross-plugin pointers are forbidden.
5. **Presence-gated language throughout**: the body inherits the description's gate; it never
   promotes a surface to available because the body is longer.
6. **Upstream specifics carry their basis and date**, per
   [`upstream-drift`](../upstream-drift/README.md).

## Self-containment: shipped plugins never cite the registry

The overlap store and [`docs/NATIVE-SURFACES.md`](../../NATIVE-SURFACES.md) live in this
repository. A plugin installed from the marketplace does **not** have them: a citation would be a
broken reference at install time, and the reader would be routed to a file that does not exist.

So: baked text repeats what it needs and cites nothing outside its own plugin. The registry is a
maintainer surface: it records the verdict, the evidence, and the trigger that would change them;
the component carries the conclusion. The parity check enforces the forward direction
mechanically: every baked line traces back to a store row, and a claimed Boundary section must name
that row's surface rather than merely carry the heading. In the other direction the two baked
surfaces differ. A row without its Boundary section is a defect the self-check fails on, because
the section costs nothing and can always land in the change that adds the row; a row without a
description phrase is legal pending state, because the phrase is the budget-priced,
routing-affecting half and earns its separate gate.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| A baked native reference traces to a store row | **Deterministic**: built, as the overlap self-check's store↔baked-line parity pass |
| Every non-`defer` extraction-evidence row has its Boundary section (`baked.boundary_section` true, and a `## Boundary` section in the component naming that row's surface as a code span) | **Deterministic**: built, in the same self-check, as a blocking problem (exit 1). The tier carries no advisory grade: advisory belongs to detect-then-judge, where a tool narrows a set a human then rules on, and nothing here needs a ruling. A consumer gate passes a degraded run because degraded reports what this repository cannot fix by editing its own files; a missing section is fixable in the change that adds the row |
| Every store row carries a recheck trigger and a class-tagged observation record | **Deterministic**: built, in the same self-check |
| The phrase uses the presence gate rather than an availability assertion | **Detect-then-judge**: the `resolves in your session` token is greppable, but deciding whether a *different* sentence asserts availability is a judgment about meaning. Candidate check named, not built: flag a component description naming a bundled or built-in surface with no gate token. Build trigger: a second assertion-shaped native reference reaches `main` after this doc |
| The routing split is the right one | **Reasoning-only**: it is the verdict, and verdicts are human-gated by design |

## Adopters

| Surface | What it carries |
|---|---|
| `/claude-ops:audit-install-state` | Description phrase + `## Boundary` section for the bundled `doctor` skill (verdict `complementary`) |
| `/review:quality-gate`, `/review:fanout` | The organic Boundary pattern this doc generalizes; adopts the phrasing rules on next touch |

| `/claude-config:audit-instructions` | `## Boundary` section for the bundled `claude-api` skill's `prompt-audit` subcommand (verdict `complementary`, composite posture), four-part detail in the skill's own reference file; no description phrase |
| `/evals:methodology` | `## Boundary` section for the bundled `claude-api` skill's `hillclimb` and `build-eval` subcommands (verdict `complementary`); detail in the skill's eval-design reference |
| `/playbooks:fable-5` | `## Boundary` section for the bundled `claude-api` skill as the live-facts and cost-audit surface its chapters defer to (verdict `complementary`); detail in the pack's prompt-caching reference chapter |
| `/review:code-review`, `/review:security-review` | `## Boundary` sections for the bundled `code-review` skill and the native `security-review` command (verdict `complementary`, CI lane versus session pass); four-part detail in each skill's `reference/` file; no description phrase |
| `/code-tidying:tidy`, `/code-tidying:batch-simplify` | `## Boundary` sections for the bundled `simplify` skill (verdict `complementary`, diff-anchored versus lane- and sweep-anchored); detail in each skill's reference or context file; no description phrase |
| `/testing:run-e2e` | `## Boundary` section for the bundled `run` skill (verdict `complementary`, a look versus evidenced verification); detail in the skill's context file; no description phrase |
| `/claude-ops:audit-performance`, `/claude-ops:audit-skill-visibility` | `## Boundary` sections for the bundled `doctor` skill (and `/skill-doctor` for the second), verdict `complementary`; the second also carries the description phrase; detail in each skill's `reference/` file |
| `/visualization:visualize`, `/prototype:explore-directions` | `## Boundary` sections for the bundled `design` skill (verdict `complementary`, user-run canvas versus throwaway page or mockup); detail in the catalog spoke and the skill's `reference/` file; no description phrase |

Applying **description phrases** fleet-wide is a reserved, separately gated sweep: one plugin per
unit, each running apply, verify, PR, close, never a single fleet-wide edit, because each phrase
and spends shared budget. **Boundary sections** are not routing-affecting and spend no budget, so
Boundary-only baking may land across several plugins in one change; the unit rule does not apply
to it.

## Versioning

Changing a required part of the description phrase, the canonical gate token, or an enforceability
verdict is a major change to this contract; additive guidance is minor; clarification is a patch.
Version history lives in [`CHANGELOG.md`](CHANGELOG.md), which landed with the first recorded
change; the doc's README-only original state reads as 1.0.

## External authority

- `https://code.claude.com/docs/en/skills.md`: description loading, the per-entry cap, and the
  listing budget's drop behavior.
- `https://code.claude.com/docs/en/settings-reference.md`,
  `https://code.claude.com/docs/en/env-vars.md`: `disableBundledSkills`, `skillOverrides`,
  `skillListingMaxDescChars`, `skillListingBudgetFraction`, and the env twins.
- `https://code.claude.com/docs/en/commands.md`,
  `https://code.claude.com/docs/en/cloud-environments.md`: plan/platform gating and per-host
  roster differences.

Upstream publishes no convention for deferring to its own surfaces (absence checked 2026-08-23
against the pages listed above and `https://code.claude.com/docs/llms.txt`), which is why this
repository owns one.
