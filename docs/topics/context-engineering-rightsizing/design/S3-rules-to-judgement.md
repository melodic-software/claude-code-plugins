# S3 — "Then: Give Claude rules / Now: Let Claude use judgement"

Scope: from the `**Then: Give Claude rules / Now: Let Claude use judgement**` heading through
`*Write code that reads like the surrounding code: match its comment density, naming, and idiom.*`

## Claims

| # | Claim | Source verbatim |
|---|---|---|
| C1 | The era-level thesis: rule-giving is superseded by judgement-granting. | "**Then: Give Claude rules / Now: Let Claude use judgement**" |
| C2 | Absolute rules originated as worst-case avoidance, with file deletion the named exemplar. | "When we first rolled out Claude Code, we needed to be sure that Claude avoided worst case scenarios, such as deleting files." |
| C3 | Worst-case avoidance was purchased by asserting things that are not universally true. | "This meant we would give particularly strong guidance that might not always be true," |
| C4 | A specific verbatim rule was retired from the Claude Code system prompt. | "*In code: default to writing no comments. Never write multi-paragraph docstrings or multi-line comment blocks — one short line max. Don't create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files.*" |
| C5 | The retired rule was wrong for a subset — not all — of prompts. | "But for a certain subset of prompts, this guidance would be wrong." |
| C6 | Two named failure modes: user preference, and genuinely complex code. | "In the case of documentation, the user may have their own preferences, or specific parts of very complex code might need multi-line comment blocks." |
| C7 | The tradeoff was known and deliberately accepted for older models. | "Still, without these guardrails for older models, the comments Claude wrote would be incorrect in many cases and we had to accept this tradeoff." |
| C8 | Capability claim: newer models handle these decisions without explicit rules. | "But newer models have better judgement and can handle these decisions well without explicit rules." |
| C9 | The replacement is a context-sensitive instruction, not an absence of instruction. | "In the new system prompt we say: *Write code that reads like the surrounding code: match its comment density, naming, and idiom.*" |

## Evidence status

Fetched this session: `code.claude.com/docs/en/memory`, `code.claude.com/docs/en/best-practices`,
`code.claude.com/docs/en/skills`,
`platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices`,
`platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5`.

| # | Status | Basis |
|---|---|---|
| C1 | **PARTIAL** | No official page states a general "rules → judgement" doctrine. Two narrower official statements point the same direction. Opus 5 page, *Task scope and over-verification*: "If your prompt contains explicit verification instructions … **remove them**". Prompting best practices, extended-thinking section: "**Prefer general instructions over prescriptive steps.** A prompt like 'think thoroughly' often produces better reasoning than a hand-written step-by-step plan." Both are class-scoped (verification instructions; reasoning scaffolding), not the general claim. |
| C2 | **UNBACKED** | A historical assertion about Anthropic's internal system-prompt development. No official page documents Claude Code system-prompt history or the rationale for past guardrails. Looked in the memory, best-practices, and skills pages, and in the prompting-best-practices migration section. Legitimately unverifiable from outside. |
| C3 | **UNBACKED** | Same. The *mechanism* it describes is corroborated indirectly: memory page, "if two rules contradict each other, Claude may pick one arbitrarily." That confirms the cost of conflicting instructions, not this historical account of why they were introduced. |
| C4 | **UNBACKED** | Anthropic does not publish Claude Code system-prompt history. The quoted text cannot be verified as ever having been in the system prompt, nor as having been removed. Treat as author testimony. |
| C5 | **UNBACKED** | No official source; internally coherent. |
| C6 | **UNBACKED** as a claim about the retired rule | Adjacent official text *contradicts* the direction: the prompting best-practices anti-overengineering prompt still ships "Only add comments where the logic isn't self-evident" as recommended current guidance. |
| C7 | **UNBACKED** | Historical testimony. |
| C8 | **PARTIAL** | Officially confirmed for *named classes*, not generally. Opus 5 page: "Claude Opus 5 verifies its own work without being told to"; "Claude Opus 5 catches and fixes its own mistakes well without prompting." Same claim-shape (capability now covers what a rule used to force), officially stated, for verification and self-correction — never for comment density. |
| C9 | **CONFIRMED — primary source, not a doc page** | The sentence is present verbatim in the Claude Code system prompt of this very session: "Write code that reads like the surrounding code: match its comment density, naming, and idiom." Direct observation of the running harness. Note the evidence class: this confirms the line is deployed, not that the article's account of what it replaced is accurate. |

Net: 1 confirmed (by live observation), 2 partial, 6 unbacked. That tally is expected and not a defect —
S3 is largely a first-person account of an unpublished internal artifact. Its *criteria* value therefore
rests on C1/C8/C9, the three claims with external support, not on the historical narrative.

## The discriminator (the stopping rule)

This is the calibration knob the brief asks for. The article's own worked example settles it, and the
answer is sharper than "delete absolutes."

**S3's transform is not deletion. It is re-pointing.** The replacement (C9) is still an instruction,
still imperative, still unconditional, still in the system prompt. What changed is the *referent*: from
a fixed value ("no comments", "one short line max") to a pointer at something observable in the working
context ("the surrounding code"). "Match its comment density" is every bit as absolute as "write no
comments" — it just resolves at runtime instead of at authoring time.

That yields a mechanical test.

> **The substitution test.** Can the rule be rewritten as *"match / follow / defer to `<observable in
> the agent's working context>`"* without losing what the author meant?
>
> - **Yes → over-constraint.** The rule was a hard-coded guess at something the context already
>   answers. Re-point it. This is the S3 target.
> - **No → genuine operator opinion. Keep it absolute.** The rule fails substitution for exactly one
>   of four reasons, and each is a reason the article elsewhere endorses keeping.

A rule fails the substitution test — and therefore stays — when any of these holds:

1. **The context does not contain the answer.** The fact is invisible from the working tree: a tool's
   actual behavior, a platform quirk, an ordering constraint. Officially backed as keep-worthy —
   best-practices include-list: "Common gotchas or non-obvious behaviors"; memory page on `/doctor`'s
   trim: it "keeps pitfalls, rationale, and conventions that differ from tool defaults."
2. **The context contains the answer and the operator overrides it anyway.** The team decided
   something the surrounding code contradicts, or the surrounding code is what they are trying to
   change. Best-practices include-list: "Code style rules that differ from defaults." The article
   endorses this directly: "It's best when skills encode particular opinions, knowledge, or best
   practices that are particular to you, your team, or product."
3. **The worst case is irreversible or outward-facing.** Deletion, force-push, publishing, spending,
   secret exposure, merging. C2 is precisely the class the article says the guardrails were *for*, and
   S3 never claims that class is obsolete — it claims "many" constraints can go, not the worst-case
   ones. The article's own Skills guidance keeps the carve-out explicit: "Avoid making them
   overconstrained, **except in highly important areas**."
4. **The rule is what the artifact is.** For a skill whose product *is* a discipline (verify this,
   don't assume, don't copy), the absolutes are the deliverable. Deleting them does not rightsize the
   skill; it empties it.

**Corollary — the pointer must have a referent.** "Match the surrounding code" is safe in a first-party
system prompt because Claude Code always has surrounding code. It is *not* automatically safe in a
redistributable plugin, which executes in a consumer repo its author has never seen. Before re-pointing
any rule in `plugins/**`, confirm the referent is guaranteed present at the consumer; where it is not,
the rule needs a stated fallback, not a bare pointer. This repo's `CLAUDE.md:39-43` already encodes the
underlying constraint ("Repo-agnostic", "Read the consumer's context via `${CLAUDE_PROJECT_DIR}` and the
consumer's own `CLAUDE.md` / `.claude/rules`"), which is the correct shape: point at the consumer's
declared context, degrade explicitly when absent.

## Criteria

### S3-1 — Re-point substitutable absolutes (the section's primary rule)

- **Surface:** SKILL.md body, agent definition, repo `CLAUDE.md`, hook prompt text.
- **Observable:** an imperative absolute (`never`/`always`/`must`/`do not`/`don't`) whose object is a
  **style, format, density, or verbosity choice** that varies legitimately across consumer repos, AND
  that passes the substitution test, AND whose referent is guaranteed present in the consumer context.
- **Pass/fail:** fail if all three hold and the rule still states a fixed value. Remediation is
  rewrite-to-pointer, not deletion.
- **Must NOT flag:** `plugins/source-control/skills/commit/SKILL.md:94` — "Never write the message to
  `.git/<TEMP>.txt`. If a real file is unavoidable, use `mktemp`." Fails substitution by reason 1: no
  observable in any consumer repo tells the agent this. It is a mechanism gotcha.
- **Must NOT flag:** `plugins/code-tidying/skills/tidy/SKILL.md:130` — "**Never push red.**" Fails by
  reason 3.

### S3-2 — Absolute-word audit must separate directives from descriptions

- **Surface:** any grep-driven remediation pass over this repo.
- **Observable:** whether the absolute word occupies an imperative slot, or a descriptive/definitional
  one ("never published", "the never-merge boundary", "is never flagged", "Always-loaded instruction
  files").
- **Pass/fail:** a finding that counts a descriptive use as an over-constraint is a false positive.
- **Why this is a criterion and not a footnote:** measured below at **10 of 39** sampled hits — 26% of
  the raw token count is not a directive at all. Any S3 pass driven by a bare `rg never` count is
  overstated by roughly a third before it starts.

### S3-3 — Absolutes governing an irreversible act are out of scope for this section

- **Surface:** all.
- **Observable:** the prohibited action is destructive, outward-facing, or spends money/trust —
  delete, force-push, merge, publish, install, elevate, write a secret.
- **Pass/fail:** flagging one is a criteria violation, per C2 and the article's "except in highly
  important areas."
- **Must NOT flag:** `plugins/disk-hygiene/skills/clean/SKILL.md:43`, `:212`, `:221`.

### S3-4 — Conflicting instruction pairs are a finding even when each rule is individually sound

- **Surface:** the composed context — harness system prompt + user `CLAUDE.md` + repo `CLAUDE.md` +
  loaded skill bodies, evaluated together.
- **Observable:** two loaded instructions that resolve differently for the same decision.
- **Pass/fail:** fail on the pair, not on either member. Officially grounded — memory page: "if two
  rules contradict each other, Claude may pick one arbitrarily."
- **Must NOT flag:** a general rule with a documented narrower exception (e.g.
  `plugins/implementation/skills/implement-dispatch/SKILL.md:35`, which states its exception explicitly).
- This is the criterion that catches the live collision documented under Conflicts.

## Targets in this repo

All figures below are from commands run this session against
`<repo-root>`. Skill bodies were measured **with YAML
frontmatter stripped**, so `description` text is excluded.

**Population.**

| Measure | Value | How |
|---|---|---|
| `plugins/*/skills/**/SKILL.md` | 187 | `find plugins -name SKILL.md \| wc -l` |
| Body lines (frontmatter stripped) | 26,466 | `awk` frontmatter strip → `cat \| wc -l` |
| Absolute-directive tokens in bodies | **2,251** | `rg -o -P "(?i)\b(never\|always\|must not\|must\|do not\|don't\|non-negotiable\|mandatory\|forbidden\|under no circumstances\|at all times)\b"` |
| Bodies containing ≥1 | **186 / 187** | same regex, `rg -l` |
| Bodies containing zero | 1 — `plugins/testing/skills/plan/SKILL.md` | set difference |
| Repo `CLAUDE.md` | 63 lines, **5** tokens | same regex |
| User-global `~/.claude/CLAUDE.md` | 69 lines, **30** tokens (26 × `never`) | same regex |

Token frequency across bodies: `never` 1,233 (170 files) · `do not` 361 · `must` 230 · `don't` 189 ·
`always` 149 · `required` 102 · `mandatory` 63 · `must not` 35 · `forbidden` 13 · `non-negotiable` 11 ·
`at all times` 2 · `under no circumstances` 0.

**Density leaders** (absolutes per 100 body lines, files ≥40 lines):
`plugins/implementation/skills/implement-dispatch/SKILL.md` 41.4 (36/87) ·
`plugins/planning/skills/questionnaire/SKILL.md` 32.5 · `plugins/miro/skills/setup/SKILL.md` 28.6 ·
`plugins/playbooks/skills/fable-5/SKILL.md` 26.6 · `plugins/discovery/skills/explore-deep/SKILL.md` 24.0 ·
`plugins/work-items/skills/work/SKILL.md` 21.5 · `plugins/planning/skills/interview/SKILL.md` 18.4.

**Absolute leaders** (raw count): `source-control/babysit-prs` 75 · `source-control/babysit-loop` 51 ·
`planning/plan` 49 · `source-control/pull-request` 48 · `planning/interview` 47 ·
`playbooks/boris/vendor` 46 · `work-items/work` 44 · `autonomy/setup` 42.

**Sample classification.** Unbiased systematic sample — every 23rd match of the regex across all
`plugins/**/SKILL.md`, n=40, of which 1 landed in frontmatter → **39 usable**. Classified against the
discriminator above:

| Class | n | Share | Examples |
|---|---|---|---|
| **Not a directive** (descriptive/definitional) | 10 | 26% | `work-items/work-loop:166` "the never-merge boundary" · `visualization/visualize:90` "(never published)" · `docs-hygiene/compress:19` "Always-loaded instruction files" · `code-tidying/audit-comment-residue:27` "is never flagged" |
| **Directive, survives — reason 1 (gotcha)** | 11 | 28% | `context7/lookup/vendor/cli:70` "Always run `ctx7 library` first — `ctx7 docs react \"hooks\"` will fail without a valid ID" · `source-control/commit:94` · `docs-hygiene/rename-references:150` |
| **Directive, survives — reason 2 (operator opinion)** | 6 | 15% | `domain-driven-design/curate-language:39` "Never manufacture consensus." · `source-control/pull-request:270` · `work-items/work:202` |
| **Directive, survives — reason 3 (irreversible)** | 6 | 15% | `context7/setup:109` (secret write) · `ai-briefing/generate:32` (ToS) · `source-control/pull-request:139` (would clobber WIP) · `session-flow/running-retro:122` "never auto-apply" |
| **Directive, survives — reason 4 (the rule is the product)** | 2 | 5% | `adhd/clarify:124` · `desktop-notification/setup:79` |
| **Meta — already encodes a discriminator** | 1 | 3% | `claude-config/audit-instructions:150` |
| **Re-point candidate (S3-1 hit)** | **1** | **3%** | `plugins/debugging/skills/debug/SKILL.md:41` — "**Simplest explanation first** — do not reach for an exotic cause while a mundane one is untested" |
| Truncated / undetermined | 2 | 5% | — |

**What that projects to.** ~26% of the 2,251 tokens are non-directives → ≈1,670 genuine directives
repo-wide. At the sampled re-point rate (1 of 39), that is **order-of-magnitude ~40–60 repo-wide
candidates**. State the uncertainty honestly: with n=39 and one hit, the 95% confidence interval on the
rate runs roughly 0.1%–13%, so the true count could plausibly be anywhere from a handful to ~200. The
sample is adequate to establish the *shape* of the finding (small minority) and inadequate to size it
precisely. **A full classification pass would need to be run, not extrapolated.**

**The finding that matters more than the count.** The absolutes in this repo are overwhelmingly
*mechanism-anchored* — they name a specific tool, flag, path, or failure mode. Two targeted searches
for the class S3 actually retired came back near-empty:

- Comment/docstring policy directives in skill bodies: **zero** instances of the retired shape. Every
  hit was either a CI-hygiene mechanism (`implement-dispatch:90`, issue-number back-references trip the
  `comment-hygiene` check) or an unrelated use of the word "comment" (PR comments).
- Generic quality exhortations — the "self-evident practices like 'write clean code'" class the
  best-practices exclude-list names: **4 hits, all false positives** on inspection.

So the naive S3 reading — "this repo is full of absolute rules, delete them" — is **not supported by the
measurement**. The volume problem in these skill bodies is verbosity, not absoluteness
(`implement-dispatch:41` is a single ~450-word bullet; `playbooks/boris/vendor` is 1,684 lines), and
verbosity is `docs-hygiene:compress`'s and `skill-quality:check`'s territory, not S3's.

**The capability already exists.** `plugins/claude-config/skills/audit-instructions/SKILL.md` is a
report-only auditor for exactly this concern, with an eleven-check catalog at
`plugins/claude-config/skills/audit-instructions/reference/criteria.md` (172 lines), a deterministic
pre-scan at `scripts/instruction-scan.sh`, evidence tiers, and per-check official sources. Its `I6`
(criteria.md:97) is "Bare prohibition to positive reframing" and `I8` (criteria.md:117) is "Model-era
re-audit". **S3's contribution is not a new skill — it is a missing twelfth check**, because neither
existing remediation is S3's transform:

- `I6` remediates to *"state what to do instead"* → "never write comments" becomes "write comments
  sparingly". Still a fixed value.
- `I8` remediates to *removal or a briefer instruction* → deletion.
- **S3 remediates to a runtime-resolved pointer** → "match the surrounding code's comment density".

Recommended routing: add `I12 — Absolute value to context pointer` to
`reference/criteria.md`, authority `ANTHROPIC-DOCS`, tier `behavioral`, sourced to the deployed system
prompt line (C9) and to the Opus 5 page. Also worth correcting while there: `I6` cites "Tell Claude what
to do instead of what not to do" as authority for an all-surface check, but that guidance sits under
**"Control the format of responses"** on the prompting best-practices page — it is output-formatting
steerability, not general instruction authoring. `I6`'s stated scope currently overreaches its own cited
source.

**User-global scope (read-only — routed recommendation, never edited by this pass).**
`~/.claude/CLAUDE.md` is 69 lines carrying 30 absolute-directive tokens, 26 of them `never` — a density
of ~43 per 100 lines, **higher than every skill body in this repo**, and it loads in full into every
session on the machine. If S3 has one highest-leverage target on this machine, it is this file rather
than `plugins/**`. Two observations, both for the operator to decide:

- Line 33 is the closest thing on the machine to the rule S3 retired: "Prefer self-documenting code —
  naming and structure before comments … Delete comments that restate the code … Applies to every
  deliverable; apply the Boy Scout Rule to such comments encountered while working, unprompted."
- It is already *better-formed* than the retired rule — it states a test and a rationale rather than a
  bare threshold, which is what `I6`/`I7` ask for. Under the discriminator it **survives by reason 2**
  (deliberate override of what surrounding code would say). It is not a deletion candidate. It is,
  however, half of the live conflict documented next.

## Conflicts and ambiguity

**1. The sharpest conflict: the comment rule now collides with the deployed system prompt.** This
session's system prompt contains, verbatim, "Write code that reads like the surrounding code: match its
comment density, naming, and idiom." The user's global `CLAUDE.md:33` mandates deleting comments that
restate the code, "Applies to every deliverable", "unprompted". In a consumer repo whose surrounding
code is comment-dense and restates itself, these resolve to opposite actions on the same edit. Neither
is wrong in isolation; the *pair* is the defect, and the memory page names the consequence exactly:
"if two rules contradict each other, Claude may pick one arbitrarily." This is the article's own opening
pathology — "'leave documentation as appropriate,' or 'DO NOT add comments' as our system prompt,
skills, and user requests clash" — reproduced live on this machine. Resolution is a one-line edit to the
user file (scope the rule to *new and modified* code, or state which wins), not a deletion. Routed, not
applied: the file is chezmoi-managed and out of this pass's editable set.

**2. Official doctrine currently contradicts a strong reading of C1 — twice, in its own examples.** The
prompting best-practices anti-overengineering prompt, presented as *current* recommended guidance, is a
stack of bare absolute prohibitions: "Don't add features, refactor code, or make 'improvements' beyond
what was asked", "Don't add docstrings, comments, or type annotations to code you didn't change",
"Don't create helpers, utilities, or abstractions for one-time operations." And best-practices tells
CLAUDE.md authors the opposite of "soften": "You can tune instructions by adding emphasis (e.g.,
'IMPORTANT' or 'YOU MUST') to improve adherence." A reader who takes S3 as "absolutes are legacy" is
contradicted by the pages S3's own repo-side implementation cites as authority. S3 is a claim about
*which* absolutes, never *whether*.

**3. S3 collides with an officially-endorsed pattern this repo has built at scale — and the operator
must break the tie.** The Opus 5 page: "If your prompt contains explicit verification instructions
('include a final verification step for any non-trivial task,' '**use a subagent to verify**'), remove
them … The same applies to legacy harness scaffolding that adds separate verification steps," and "**do
not use subagents to verify or double-check your own work**." Against that:

- **23 of 187** skill bodies mandate a fresh-context/independent verifier or reviewer subagent
  (`rg -l` count, listed below); 134 of 187 mention verify/verification at all (544 occurrences).
  `plugins/implementation/skills/implement-dispatch/SKILL.md:55` makes it `MUST` for autonomous runs.
- The user's global `CLAUDE.md` makes it a standing rule: "Never let the context that produced work be
  its own final critic: producer ≠ critic ≠ tester."
- And `code.claude.com/docs/en/best-practices` **endorses it**, in a section titled "Add an adversarial
  review step": "a reviewer running in a fresh subagent context sees only the diff and the criteria you
  give it, not the reasoning that produced the change."

The two official pages are not obviously reconcilable as written. The defensible reading is that the
Opus 5 page targets *self*-verification (the model re-checking its own answer, which it now does
unprompted) while the best-practices page targets *bias* (a fresh context is epistemically different,
not merely a repetition) — but the Opus 5 page's literal words name the subagent case. This is a real,
consequential, unresolved tension, and it is the single decision most likely to change what this pass
does. **Do not let a remediation pass resolve it silently in either direction.** Affected files:
`playbooks/fable-5`, `verification/confirm`, `re-anchor/{sweep-all-disciplines,setup,scrutinize-dont-coast,do-your-research,do-your-research-deep,recheck-against-upstream-deep}`,
`session-flow/orchestrate`, `claude-config/audit-instructions`, `debugging/debug`,
`review/quality-gate`, `planning/{audit-answers,plan}`, `implementation/{implement,implement-dispatch}`,
`codebase-health/audit`, `code-tidying/{tidy,batch-simplify}`, `claude-ops/changelog`,
`naming/name-it-better`, `docs-hygiene/{audit-derivability,compress}`.

**4. C9 does not generalize from a first-party system prompt to a redistributable plugin.** "Match the
surrounding code" is a safe pointer for Claude Code because the referent always exists. A skill in
`plugins/**` runs in a consumer repo the author has never seen, where the referent may be absent
(greenfield), inconsistent (monorepo of mixed vintages), or the very thing the user is trying to fix
(legacy cleanup). The article never addresses this because it is writing about a first-party product.
Any S3 remediation here must carry the fallback clause; see the corollary in the discriminator.

**5. The `re-anchor` plugin is the stress case, and the discriminator holds.** Sixteen skills whose
entire function is re-imposing absolute discipline ("never assume", "point don't copy", "reason don't
recite"). A naive S3 pass would gut them as the densest concentration of absolutes in the repo. Under
reason 4 they are the clearest keeps in the tree — deleting the absolutes does not rightsize these
skills, it deletes their content. The article agrees on its own terms: "It's best when skills encode
particular opinions, knowledge, or best practices that are particular to you, your team, or product."
Worth noting the irony for the operator: this plugin exists to counteract model default behavior, which
is precisely the "context does not supply the answer / operator overrides the default" territory the
discriminator protects.

**6. C5/C6 undercut the section's own framing.** The article concedes the retired rule was right for
most prompts and wrong for "a certain subset" — then retires it entirely. That is a defensible product
call at Anthropic's eval scale (they measured: "no measurable loss on our coding evaluations"). It is
**not** a defensible inference pattern for an operator with no evals. This repo ships no eval harness
for instruction changes; `audit-instructions` says so explicitly ("that loop is prose guidance — this
skill ships no eval tooling") and correspondingly ships every behavioral finding as a human-gated
proposal. Any S3-driven change here inherits that constraint: it is a proposal to be watched, not a
verified improvement.

**7. Scope caveats on my two supporting citations.** "Prefer general instructions over prescriptive
steps" sits in the **extended-thinking** section of the prompting page (about reasoning scaffolding),
and "Tell Claude what to do instead of what not to do" sits under **"Control the format of responses"**
(about output formatting). Neither is general instruction-authoring doctrine. I am citing them as
directional support for C1 and labelling both PARTIAL rather than promoting either to confirmation.

## Open questions for the operator

1. **Does the verifier-subagent pattern stay?** Official Opus 5 guidance says remove it; official Claude
   Code best practices endorses it; your global `CLAUDE.md` mandates it; 23 skills implement it.
   *RECOMMENDED: keep it, and narrow the wording.* The independence argument (fresh context, rationale
   withheld) is a different mechanism from the self-verification the Opus 5 page targets, and
   best-practices endorses it explicitly for that reason. Concretely: drop blanket verifier dispatch on
   *mechanical, behavior-preserving* work (`implement-dispatch:55` already carves this out for
   interactive runs — extend the carve-out to autonomous), keep it where the verdict is subjective or
   the blast radius is wide. This is the one decision that should be made before any file is touched.
2. **Fix the comment-rule collision in `~/.claude/CLAUDE.md:33`?** *RECOMMENDED: yes — scope it to new
   and modified code, so it stops contradicting the deployed system-prompt line on untouched
   surroundings.* One-line change; routed to the dotfiles repo, not edited here.
3. **Add `I12` to `audit-instructions/reference/criteria.md`, or write a separate S3 skill?**
   *RECOMMENDED: add `I12` to the existing catalog.* The auditor already has the surfaces, tiers,
   pre-scan, routing, and human gate; a second skill would duplicate all of it and drift.
4. **Fix `I6`'s over-scoped citation while in that file?** *RECOMMENDED: yes* — its source is
   output-formatting guidance, cited as authority for an all-surface prohibition check.
5. **Run a full classification pass, or accept the sample?** *RECOMMENDED: run it, scripted, before any
   deletion.* n=39 sized the shape (small minority) but not the count; the CI spans 40–200+. The
   deterministic pre-scan already exists — this is a script run, not a judgement call.
6. **Should the S3 pass touch `plugins/**` at all this cycle?** *RECOMMENDED: no, apart from `I12` and
   the tie-break in Q1.* The measurement does not find the over-constraint S3 describes here; it finds
   verbosity, which routes to `docs-hygiene:compress` / `skill-quality:check`. The real S3 target on
   this machine is the 69-line, 30-absolute user-global `CLAUDE.md`, which is read-only to this pass.
7. **Does `plugins/debugging/skills/debug/SKILL.md:41` get re-pointed?** *RECOMMENDED: leave it.* It is
   the sample's only S3-1 hit, but it is a diagnostic heuristic with a stated rationale, and the cost of
   being wrong (an agent chasing an exotic cause) exceeds the ~15 tokens saved.

## Fence events

None. I did not read, list, grep, or reference `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, any other worktree under
`<worktrees-root>/`, or any other agent's file under `sections/`. All repository reads were confined
to `<repo-root>`. `~/.claude/CLAUDE.md` was read (permitted and
in scope as a routed-recommendation surface) and not modified. I created only
`sections/S3-rules-to-judgement.md` plus scratch files outside the repo.

One note for the record: `plugins/claude-config/skills/audit-instructions/` and its
`reference/criteria.md` are a prior *implementation* of this article's general theme, but they are
first-party repository content, not the fenced prior analysis of this article, and reading them was
necessary to answer whether S3 produces new work. Flagging it so the operator can judge the boundary.
