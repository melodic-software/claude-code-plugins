# S4 — Then: Give Claude examples / Now: Design interfaces

## Claims

1. **Examples were the top-ranked rule for tool usage.**
   > "The number one rule for tool usage was to give Claude examples on how to use them."

2. **Examples now constrain the model's exploration space.**
   > "With our newest models, we've found that giving examples actually constrains them to a certain
   > exploration space."

3. **The replacement is interface design — more expressive parameters.**
   > "Instead of using examples, think more about the design of your tools, scripts and files- what
   > parameters does Claude have and how can they be more expressive?"

4. **A closed enumeration teaches usage by its shape.**
   > "For example, in the Todo tool example, just listing status as an enumeration between pending,
   > in_progress, and completed, hints to Claude about how to use it."

5. **A cross-item invariant is still stated as prose instruction.**
   > "The instruction on keeping one item in_progress helps define our requested behavior."

Note the scope carried by the source text itself: claim 1 says **"for tool usage"**, and claim 3
enumerates **"tools, scripts and files"**. The section never says "delete examples from prose
guidance." Claims 4 and 5 together are the article's own boundary marker — see Criteria C1.

## Evidence status

| # | Status | Basis |
|---|---|---|
| 1 | **UNBACKED** | A historical statement about Anthropic's prior internal practice. No current official page ranks example-giving as a tool-usage rule. Not refutable from docs either. Searched: <https://code.claude.com/docs/en/agent-sdk/custom-tools.md>, <https://code.claude.com/docs/en/skills.md>. |
| 2 | **UNBACKED, with live counter-signal** | No official page states that examples constrain newer models. Current docs actively endorse examples in three places: `when_to_use` is documented as "Additional context for when Claude should invoke the skill, such as trigger phrases or **example requests**"; the skill-directory layout documents `examples/sample.md  # Example output showing expected format` and `examples.md (usage examples - loaded when needed)`; and the custom-tools page's own recommended parameter description is `"Unit to convert from, e.g. kilometers, fahrenheit, pounds"` — an inline example inside a tool schema. Sources: <https://code.claude.com/docs/en/skills.md>, <https://code.claude.com/docs/en/agent-sdk/custom-tools.md>. |
| 3 | **PARTIAL** | The *mechanisms* are documented — enum constraints (`z.enum()` in TypeScript; a full JSON Schema dict in Python "when you need enums, ranges, optional fields, or nested objects"), per-field descriptions via `.describe()`, required/optional, and behavioural annotations (`readOnlyHint` etc.). What is **not** documented is the article's framing that these *substitute for* examples. Source: <https://code.claude.com/docs/en/agent-sdk/custom-tools.md>. |
| 4 | **PARTIAL** | The enum-schema pattern is documented as first-class and is the page's headline "Example: unit converter" pattern ("**Enum schemas:** `unit_type` is constrained to a fixed set of values"). The behavioural claim — that the enum *hints how to use the tool* — is the article's inference, not a documented statement. Source: <https://code.claude.com/docs/en/agent-sdk/custom-tools.md>. |
| 5 | **UNBACKED** | No official page discusses cross-item invariants in tool contracts. The claim is self-evidencing within the article and is structurally consistent with what schemas can and cannot express: a per-field enum cannot encode "at most one item may hold this value." |

Nothing in this section is CONFIRMED by official documentation. That is the honest result: S4 is an
internal-practice report, and the current docs run mildly *against* its blanket phrasing while
supporting the interface mechanisms it recommends.

## Criteria

Claim → criterion: claim 1 is historical and yields none. Claim 2 yields **C1** and **C2**. Claim 3
yields **C3**. Claims 4 and 5 jointly set the boundary and yield **C4**.

### The boundary (governs every criterion below)

The claim generalizes to **execution exemplars** and stops at **routing exemplars**.

- **Routing surface** — `description`, `when_to_use`, agent-definition `description`. These exist to
  answer *should I load this at all*. Examples here are officially sanctioned ("trigger phrases or
  example requests") and are what the model matches against. Out of scope for claim 2. Never flag.
- **Execution surface** — SKILL.md body, agent-definition body, tool/parameter descriptions,
  hook contracts. These answer *how do I do the thing*. This is where claim 2 applies.

Within the execution surface, claims 4 and 5 draw the second line: an **interface can absorb
per-field legal values** (the enum); it **cannot absorb cross-field or cross-item invariants** (one
item `in_progress`). The latter stay prose — stated declaratively once, not demonstrated.

### C1 — Worked-procedure exemplars in an execution surface

- **Surface:** SKILL.md body, **progressive-disclosure spoke files** (`context/`, `reference/`,
  `templates/`, `lanes/`), agent-definition body. Spokes are execution surface: they load into
  context when the skill runs, so moving an exemplar out of SKILL.md does not exempt it.
- **Flag when:** a fenced block or passage walks one complete instance of the skill's own procedure
  (a sample transcript, a canned filled-in report, a worked run) *and* the skill already declares
  that output's shape structurally elsewhere (a table, a schema file, a template file).
- **Pass/fail observable:** the exemplar's information content is a strict subset of the declared
  structure. If deleting the exemplar loses no field, no legal value, and no invariant, it fails.
- **Must NOT flag (three carve-outs):**
  1. A format exemplar for a field whose format *is* the contract — e.g.
     `created: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>` at
     `plugins/planning/skills/prd/SKILL.md:150`. There the example is the schema.
  2. **Rubric / boundary-calibration examples** — worked applications of a judgment gate that show
     where a threshold sits, including the failing case. `plugins/docs-hygiene/skills/extract-ssot/context/decision-framework.md:81-155`
     is five such (four PASSES, one FAILS, ✅/❌ per test). No enum expresses a threshold, and the
     article's own S8 endorses rubrics as references (`source-article.md:90`).
  3. **Anything under a `vendor/` path.** These are upstream-owned materializations; `check-skill.sh`
     check 8 requires `vendor/` byte-identical vs HEAD unless paired with an upstream-version bump
     (`plugins/skill-quality/scripts/check-skill.sh:38-39`). Editing one to satisfy C1 breaks the
     gate. Route upstream or leave alone.

### C2 — Redundant inline illustration (the mechanically checkable one)

- **Surface:** SKILL.md body, spoke files, agent-definition body — **excluding `vendor/`** for the
  reason given in C1 carve-out 3. The two most example-dense files in the repo are vendor
  (`plugins/playwright/skills/playwright/vendor/SKILL.md`, 24 hits;
  `plugins/playbooks/skills/boris/vendor/SKILL.md`, 11), so an uncarved C2 targets exactly the
  content that must not be hand-edited.
- **Flag when:** an inline `e.g.` / `for example` illustrates a value of a parameter whose legal
  values the *same file* already declares as a closed set (an action-router table, a `[a|b|c]`
  argument form, an explicit enum list), and every illustrated value appears verbatim in that set.
- **Pass/fail observable:** set-membership. Fully scriptable.
- **Must NOT flag:** an `e.g.` naming an instance of an **open** class, where no closed set exists or
  could exist. This is the dominant form in this repo — see Targets. Canonical non-flag:
  `plugins/claude-config/skills/audit-automation-gaps/SKILL.md:65` —
  `` `<root-build-config>` — e.g. `Directory.Build.props` for .NET, `pyproject.toml` for Python ``.
  The class of build-config filenames is open across ecosystems; the example is the only way to
  convey it and is not replaceable by an interface.

### C3 — Action-space declaration (the highest-leverage criterion)

This is claim 3 applied to the repo's real interface: a router skill's model-visible action space.

- **Surface:** skill frontmatter `description`, cross-checked against the body's action-router table.
- **Flag when:** a skill with `disable-model-invocation` not `true` carries an action-router table of
  ≥2 backticked actions, and a *user-requestable entry-point* action from that table is named
  nowhere in the `description`.
- **Pass/fail observable:** scripted set-difference between the router table's first-column tokens
  and the description text. The Targets section below was produced by `s4router.py`, written this
  session into the session scratchpad, which does not persist.
- **Must NOT flag:** (a) `disable-model-invocation: true` skills, whose description never enters the
  model's listing at all — verified: `plugins/education/skills/teach/SKILL.md:6` sets it, so its 8
  undeclared actions cost nothing model-side; (b) diagnostic/terminal sub-actions reachable only
  *after* the skill is already chosen (`help`, `status`), which no routing decision depends on.

### C4 — Invariant stated, not demonstrated

- **Surface:** SKILL.md body, tool/parameter description, hook contract.
- **Flag when:** a cross-field or cross-item invariant is conveyed *only* by a worked example, with
  no declarative statement of the rule.
- **Pass/fail observable:** semi-checkable. Presence of a declarative sentence stating the invariant
  is detectable; whether the invariant is fully captured is not. Treat as a review prompt, not a gate.
- **Must NOT flag:** an invariant stated declaratively *and* accompanied by one illustration of a
  violation — that illustration carries the negative case, which a positive statement does not.

### What is not checkable — stated plainly

The positive half of claim 3 — **"expressive enough that prose examples become unnecessary"** — has
no direct observable, and I could not construct one. Expressiveness is a property of the *fit*
between a name/enum and the concept it denotes; nothing mechanical distinguishes `in_progress` from
`state_2`. Two things are salvageable, and only these:

1. **Its failure symptom is measurable.** C2 detects the symptom (prose re-explaining what the
   interface already declares). Absence of the symptom is *not* evidence of expressiveness.
2. **A reviewer-facing residual test.** For each prose example in an execution surface, name the
   parameter, enum value, router row, or filename that would carry the same information. If one can
   be named, the example is redundant and the interface should carry it. If none can be named, the
   example is carrying either an open-class instance (keep) or an invariant (restate per C4). This
   is a question a human or a review agent answers; it is not a gate.

Any criterion phrased as "the interface must be expressive enough that examples are unnecessary"
should be rejected as unfalsifiable.

## Targets in this repo

All counts from commands run in `<repo-root>`.

**Population.**

- `find plugins -name SKILL.md | wc -l` → **187** skills.
- `find plugins -path "*/agents/*.md" | wc -l` → **7** agent definitions.
- `find plugins -name hooks.json | wc -l` → **15** hook manifests.
- `grep -rh "^argument-hint:" plugins --include=SKILL.md | wc -l` → **158** carry `argument-hint`.
- `find plugins -name "*.md" ! -name SKILL.md ! -path "*/agents/*" | wc -l` → **681** spoke files.
- `find plugins -path "*/vendor/*" -name "*.md" | wc -l` → **19** vendor files (frozen surface).

**C1 — the target set is real, and it lives in the spokes, not in SKILL.md.**

*In SKILL.md:* `grep -rniE "(example|sample) (output|response|report|session|transcript|invocation)" plugins --include=SKILL.md`
→ **1 hit**, and it is not an exemplar (`plugins/songwriting/skills/practice/SKILL.md:38`, a
pre-flight instruction). `grep -rlE "^#{2,4} Examples?" plugins --include=SKILL.md` → **1 file**.
`grep -rl "<example" plugins --include="*.md"` → **0** across every plugin markdown file. Skill
bodies carry essentially no worked execution exemplars.

*In spokes:* the same patterns over `plugins --include="*.md"` minus `SKILL.md` → **8 files** with an
`## Example` heading. Classified:

- **Rubric — do not flag (C1 carve-out 2):**
  `plugins/docs-hygiene/skills/extract-ssot/context/decision-framework.md:81,96,111,126,143` — five
  worked applications of a 6-test gate, four PASSES and one FAILS.
  `plugins/songwriting/context/pat-pattison/research/mosaic-rhyme.md:237` is craft calibration in the
  same shape.
- **Genuine C1 candidates:**
  `plugins/machine-health/skills/audit/references/shared/output-schema.md:41` — a filled-in JSON
  instance placed immediately after the JSON schema it instantiates (the cleanest hit in the repo);
  `plugins/planning/skills/prd/context/templates.md:50,149,239` — three filled-in template instances
  where the template and its frontmatter schema are declared directly above. Both carry *some*
  residue the schema does not express (severity semantics; how much detail a one-pager holds), so
  neither is a mechanical delete — they are review items.
- **Vendor — excluded:** `plugins/playwright/skills/playwright/vendor/references/element-attributes.md:5`.
- **Command-usage lists, not procedure walks:** `plugins/playwright/skills/playwright/reference/commands.md:131`,
  `plugins/repo-hygiene/skills/clean/context/clean-batch.md:126`,
  `plugins/repo-hygiene/skills/clean/context/git-tree-reset-batch.md:107`.

So the earlier SKILL.md-only reading understated C1: the population is one level down, it is **small
(4 candidate sites across 2 files)**, and the largest cluster in the spokes is a rubric the article
itself endorses.

*In agent bodies:* the three exemplar patterns over `plugins/*/agents/*.md` → **0 hits**; **2** `e.g.`
occurrences across all 7 files. **No C1 or C2 target in agent definitions.**

**C2 — classified, not assumed.**
`e.g.` occurrences split by surface: **51** on `argument-hint` lines, **192** in SKILL.md body prose
(243 total in SKILL.md), plus **351** in spokes. Of the 192 body occurrences, **9 are vendor** and
**183 editable**; total vendor `e.g.` across all 19 vendor files is **14**. I hand-classified a
systematic 21-line sample of the 192:

- **~1** redundant with a closed set the same file declares (category (a), the article's target) —
  `plugins/songwriting/skills/suno/SKILL.md:192`, and even that is borderline because the adjacent
  match rule is open-ended.
- **~15** name an instance of an **open** class — `plugins/claude-config/skills/audit-automation-gaps/SKILL.md:65`,
  `plugins/code-tidying/skills/batch-simplify/SKILL.md:86`,
  `plugins/docs-hygiene/skills/audit-noise/SKILL.md:116`,
  `plugins/verification/skills/confirm/SKILL.md:123`,
  `plugins/planning/skills/prd/SKILL.md:87`, `plugins/session-flow/skills/reanchor/SKILL.md:37`,
  and similar. **Not replaceable by an interface.**
- **~5** unclassifiable from the line alone (parenthetical asides, truncated context).

Two of the 21 sampled lines were vendor (`plugins/playbooks/skills/boris/vendor/SKILL.md:1585`,
`plugins/playwright/skills/playwright/vendor/SKILL.md:53`) and are excluded by C2's carve-out.

Extrapolated, the repo's `e.g.` population is dominated by open-class instance naming, which claim 3
does not reach. **C2's real yield here is small.** A full classification of all 183 editable body
occurrences (and the 351 spoke occurrences) would be needed before any sweep; do not sweep on the
sample.

**C3 — the real target set.**
Router-shaped skills with a ≥2-row backticked action table: **29**. Of those:

- **2** name *none* of their body actions in the description:
  - `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:3` — body declares
    `identify | verify | plan | execute | batch | unwind`; description names none.
  - `plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md:3` — body declares `fix`,
    `file-issues`; description names neither.
- **16** name some but not all. Largest gaps: `plugins/planning/skills/design/SKILL.md:3` (7 of 10
  undeclared), `plugins/songwriting/skills/suno/SKILL.md:3` (4 of 14),
  `plugins/education/skills/teach/SKILL.md:3` (8 of 11 — **excluded by C3**, it sets
  `disable-model-invocation: true`).
- **17 of the 18** gapped skills are model-invocable (`disable-model-invocation: false`), so the
  omission genuinely costs model-side routing.

**Cross-surface divergence (verified, single instance).**
`plugins/firecrawl/skills/firecrawl/SKILL.md` — `argument-hint:4` declares 10 commands; the
model-visible `description:3` declares 8. The two missing commands are real router rows
(`SKILL.md:100` `search-feedback <id>`, `SKILL.md:101` `credit-usage`). The script comparing
descriptions to argument-hints found 3 candidates; **2 were regex false positives** (`search <feature>`,
`sync (default, mutating)`), leaving this one. Confirmed independently against the body table, so the
finding does not depend on argument-hint semantics.

**Positive exemplar — hook contracts already satisfy S4.**
The hook JSON contract is the article's thesis executed: `permissionDecision` is
`allow|deny|ask|defer`, `decision.behavior` is `allow|deny`, and every decision field is paired with
an explicit `…Reason` field. No prose example is needed to know the legal moves. Source:
<https://code.claude.com/docs/en/hooks.md>. The repo's 15 `hooks.json` manifests
(e.g. `plugins/guardrails/hooks/hooks.json:5-12`) are declarative matcher/command/timeout records
with no exemplars. **No remediation; cite as the reference shape for C3.**

**Agent definitions — routing surface, out of scope.**
All 7 carry quoted trigger phrases in `description` (e.g.
`plugins/review/agents/ci-log-auditor.md:3` — `"Use for 'audit run X', 'thorough CI review', …"`).
Official docs define this field as "When Claude should delegate to this subagent"
(<https://code.claude.com/docs/en/sub-agents.md>). Per the boundary, these are routing examples.
**Do not flag.**

## Conflicts and ambiguity

**1. The repo's own gate treats deleting an example as a build failure.** `check-skill.sh` check 3 is
"Trigger-keyword preservation vs the base ref" — a rewrite that drops a single-quoted trigger phrase
from `description` FAILs the gate (`plugins/skill-quality/scripts/check-skill.sh:30-33`), and check
12 WARNs when a description lacks quoted `Use when` phrasing. **170 of 188** `description:` lines
carry quoted phrases (188 lines across 187 skills — `plugins/playbooks/skills/boris/vendor/SKILL.md`
carries a second `description:` line in its body). Read naively, S4 says delete these; the gate says
a build breaks if you do. The conflict dissolves on the routing/execution split — and the operator
should know the guardrail already exists: a careless application of S4 to descriptions will be
caught, not silently shipped.

The repo already practises the boundary this section draws, one level up: check 14 WARNs when an
action-router skill ships no `evals/evals.json` (`plugins/skill-quality/scripts/check-skill.sh:45`),
and an eval case carries `prompt` + `expected_output` — worked examples deliberately held **outside**
the model's context, exercised against the skill rather than loaded into it. That is the
routing/execution split expressed as infrastructure, and it is the right destination for any exemplar
C1 removes.

**2. Current official docs contradict the blanket phrasing.** `when_to_use` is documented as the
place for "trigger phrases or **example requests**"; the skill layout documents an `examples/`
directory and `examples.md`; and the custom-tools page's *own* recommended parameter description
embeds `e.g. kilometers, fahrenheit, pounds`. Anthropic's tool-authoring reference does the thing the
article says to stop doing. Only the narrow reading (execution exemplars, not routing or open-class
illustration) reconciles them.

**3. Sharpest internal conflict — S4 vs S8.** S4: stop giving examples. S8 ("Rich references"):
> "A spec may also be a detailed test suite, or a function in a different codebase that Claude might
> port."

A detailed test suite **is** an example set — the densest one available, one worked input/output pair
per case. S4 says examples constrain the exploration space; S8 says supply a test suite as the spec.
The reconciliation available in the text is that S8's examples are *specifications of the required
result* (there is no exploration space — the assertions are the contract) while S4's are
*demonstrations of one path to a result* (where many paths were valid). That distinction is the load-
bearing one and **the article never states it**. Anyone applying S4 without it will strip test-suite
references under S8's own banner. This is the single sharpest thing in my section.

**4. C3 fights the listing budget, measured.** Making descriptions declare full action spaces costs
listing characters. Measured: all skill descriptions in this repo total **109,059 characters**
(`grep -rh "^description:" plugins --include=SKILL.md | wc -c`), mean 579, max 1,182. Official docs:
`description` + `when_to_use` truncates at **1,536 characters** per skill, the listing budget "scales
at 1% of the model's context window," and on overflow "Claude Code drops descriptions starting with
the skills you invoke least" (<https://code.claude.com/docs/en/skills.md>). So C3's added action
tokens compete directly against the trigger phrases check 3 protects, inside a fixed budget that this
marketplace is plausibly already overflowing. **"More expressive" is not free**, and the article does
not acknowledge a cost. This also puts S4 in tension with S5 (progressive disclosure), which exists
to move content *out* of always-loaded surfaces.

**5. `argument-hint` is very likely not a model surface.** Docs define it as a "Hint shown during
autocomplete to indicate expected arguments" (<https://code.claude.com/docs/en/skills.md>) — a human
affordance. Empirically, the skill listing in my own context for `firecrawl` reproduces its
`description` verbatim *and omits* `search-feedback, credit-usage`, which appear only in its
`argument-hint`. If that holds, the repo's **51** example-bearing `argument-hint` values cost the
model nothing and S4's claim does not reach them at all. **Unverified residual:** whether
`argument-hint` is injected at *invocation* time (as opposed to in the listing) is not documented and
I did not test it. No criterion above depends on this.

**6. Deliberate repo practice that C3 would flag.** The nine `songwriting/*` skills end their
`argument-hint` with "— full actions in body," an explicit decision to defer the action space to the
body rather than spend listing budget. C3 flags eight of them. That is a legitimate progressive-
disclosure choice under S5, not obviously a defect. C3 should be scoped to *entry-point* actions a
user would name in a cold request, and the operator should decide the line.

**7. Claim 2 is unmeasured in both directions.** The article reports it as an internal finding with
no eval cited, and I found no public evidence. Every criterion above is therefore justified by
*second-order* reasoning (redundancy, budget cost, routing reachability) rather than by the
exploration-space mechanism. If the mechanism is wrong, C1/C2 lose their rationale; C3 survives
because its justification is routing reachability, not exploration space.

## Open questions for the operator

- **Does C3 gate on all router actions or only entry-point actions?**
  *Recommendation: entry-point only* — actions a cold user request could name. Diagnostics (`help`,
  `status`) and post-selection sub-actions stay out, which spares the listing budget and the
  songwriting cluster.
- **Should C3 become check 21 in `check-skill.sh`, or a review-agent prompt?**
  *Recommendation: `check-skill.sh` as a WARN, not a FAIL* — the set-difference is deterministic, but
  the entry-point judgment is not, and a FAIL would force budget spend the operator has not approved.
- **Do we classify all 183 editable body `e.g.` occurrences (plus 351 in spokes) before acting on C2?**
  *Recommendation: yes, and expect a small yield.* The 21-line sample puts redundant-with-a-closed-set
  at roughly 1 in 20. Sweeping on the sample would strip open-class illustrations that carry real
  information.
- **Are the 4 genuine C1 candidates removed, or relocated into `evals/`?**
  *Recommendation: relocate, do not delete.* `machine-health/.../output-schema.md:41` and
  `planning/prd/context/templates.md:50,149,239` each carry residue the schema does not express;
  moving them into eval fixtures keeps the calibration and takes it out of the model's context, which
  is what claim 2 actually asks for.
- **Is the S4/S8 reconciliation (specification-of-result vs demonstration-of-path) adopted as this
  effort's stated reading?** *Recommendation: yes, and record it explicitly*, because without it the
  two sections issue opposite instructions about test suites and reference code.
- **Do we spend a session verifying whether `argument-hint` reaches the model at invocation time?**
  *Recommendation: no.* No criterion depends on it; record it as an unverified note.

## Fence events

None. One near-miss to disclose: I ran `mkdir -p sections && ls sections` to create my output
directory, and the listing showed two sibling filenames (`S8-rich-references.md`,
`S13-try-simplifying.md`). I opened neither and read no content from them. My S8 references above are
to the **source article's** S8 text, quoted from `source-article.md:88`, not to any sibling output.
No fenced path under `docs/topics/`, `.work/fable-field-guide-audit/`, or any other worktree was
read, listed, or grepped.
