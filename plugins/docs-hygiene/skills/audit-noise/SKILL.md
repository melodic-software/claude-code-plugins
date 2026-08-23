---
description: "Classify tracked markdown for nine noise shapes — historical citations, ghost refs to ephemeral paths, \"Why this file exists\" preambles, hard-coupled consumer lists, scope/loading meta-commentary, plan/changeset references, conversational antecedents (\"as you asked\"), tracker/PR back-references, and prohibitions with no positive alternative — emitting Tier 1 (remove/relocate), Tier 2 (review needed), and Tier 3 (likely legitimate) findings with per-shape treatment guidance; read-only on audited files. Use when: 'audit markdown noise', 'declutter', 'check for stale citations', 'find ghost refs', 'classify preamble', 'strip conversational residue from a doc', 'find negations without a positive', 'sweep a rule/skill/convention doc for noise', or before editing any tracked .md — not for prose flavor/compression (use /compress), structural markdown lint (your repo's markdown linter), or the same residue shapes inside code comments (use /code-tidying:audit-comment-residue, which owns non-markdown files)."
argument-hint: "[audit] [target] [--persist-findings]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh:*)", "Bash(git branch --show-current:*)", "Bash(git rev-parse --show-toplevel:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Classify markdown for citations, ghost refs, meta-commentary, plan/conversational/tracker residue
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files: !`git status --porcelain 2>/dev/null | grep -E '\.md"?$' | head -10 || echo "none"`
Noise findings (sample): !`${CLAUDE_SKILL_DIR}/scripts/detect.sh 2>/dev/null | grep -E '^(Summary total:|Finding shape:)' | head -20 || echo "none"`

## Purpose

Tracked markdown — rules, skill bodies, instruction files (`CLAUDE.md`, `AGENTS.md`), `docs/`, READMEs — accumulates nine NOISE shapes distinct from FLAVOR (owned by the sibling `/docs-hygiene:compress`). Each shape carries a maintenance tax plus a reader-facing tax that compounds across the corpus. This skill is a read-only classifier: it surfaces candidates with treatment guidance; the author hand-applies every edit.

Three of the nine — `plan-reference`, `conversational-antecedent`, `ticket-pr-residue` — carry the same names the code-side sibling `/code-tidying:audit-comment-residue` uses, because they are the same authoring failure landing in a different file type. Ownership splits by file type, not by shape: markdown is this skill's, everything else is the sibling's, and neither scans the other's files. The patterns are **not** shared code. The sibling classifies only the extracted comment portion of a line; this skill classifies whole prose, where the same words are load-bearing far more often, so its patterns are tightened accordingly and several of the sibling's cues are deliberately not carried over.

## Existence pre-check (before in-page noise)

Before classifying in-page noise, ask the whole-page admission question first:
**could a reader with repository search derive this page's content from the
code itself?** A page failing admission is a deletion candidate — its finding
recommends relocate-then-delete (salvage anything admissible first), never a
line-level noise treatment, and never auto-delete (this skill stays
read-only).

Four categories always pass admission regardless of derivability: decisions,
domain language, thin navigation, and policy/wiring. For the four-factor
scoring behind a contested call, reuse `/docs-hygiene:audit-derivability`'s
rubric by reference — namespaced skill invocation, optional: invoke it via the
Skill tool when available; otherwise apply the admission question above
standalone.

**Org override.** This pre-check is a portable-baseline default. When the
consuming repository declares its own documentation-existence convention,
resolve and defer to it via `/discipline:follow-our-standards`'s resolution
ladder (repo-declared source → repo's own conventions → this portable
baseline) instead of the default above.

Only a page that passes admission proceeds to the nine in-page NOISE shapes below.

## Noise shapes and treatments

| Shape | What it looks like | Default tier | Treatment |
|---|---|---|---|
| `citation` — historical citations | Dated incident citations, inline provenance attribution, migration/rename narration ("Empirically observed 2026-…", "was renamed to", "we pivoted from") when the current form suffices | 1 | Relocate to a per-file `## Sources` / `## History` footer; strip when non-load-bearing (version control preserves history). Keep inline only when the date is load-bearing (methodology or freshness stamp) |
| `ghost-ref` — refs into slice-scoped working paths | Concrete paths into a topic-docs work slice — memory slices (`.work/<slug>/`), branch-pruned contract slices (`docs/topics/<slug>/`), and concrete children of the concern-scoped roots — cited from durable surfaces, plus any citation of the retired `.claude/notes/` location. The citing document outlives the slice, so slice retirement breaks the reference; this holds whether or not the consumer's memory tier is gitignored | 2 | 3-way classify: promote the content to a durable home, replace with a durable pointer (a commit-SHA permalink or the carrying/pruning PR number), or strip. Exemptions apply per matched path, never per line: slot-variable forms (`<slug>` as a schema placeholder, not a literal name) and the bare concern-scoped roots (`.work/handoffs/`, `.work/reviews/`, `.work/running-retros/`, `.work/overengineering/` — reserved first-level names under the memory root per the topic-docs convention — with nothing concrete after) are NOT ghost refs — a concrete child under a concern root flags |
| `preamble` — "Why this file exists" openers | Opening section explaining motivation/history/rationale | 2 | Diataxis classify: KEEP on Explanation-quadrant files (rule bodies, ADRs, convention rationale); STRIP on Reference-quadrant files (data tables, registries, cheat-sheets), replacing with a 1-sentence orientation |
| `enum-list` — hard-coupled consumer lists | Tables/lists hardcoding N specific consumers that drift on every add/remove ("the following five skills…", bulleted `/skill — role` rosters) | 1 | Replace with a runtime derivation (a grep/list command cited inline) or a category citation; hardcode only when both fail |
| `scope-meta` — scope/loading meta-commentary | Body prose restating loading mechanics that config/frontmatter already owns ("Path-scoped to X", "Loads on Read of Y", "Auto-loads when…") | 1 | Strip the clause — the frontmatter/config is the single source of truth; keep a genuine cross-ref riding the same sentence. Files with no scoping frontmatter MAY state scope in one sentence |
| `plan-reference` — plan/changeset narration | Prose pointing at the work that produced the page instead of the page's subject: `replaces the old …`, `in this PR we …`, `Task 2 of the plan` | 1 | Delete the plan/changeset frame and keep whatever the sentence asserts about the present subject, rewritten without it. A doc citing a plan artifact that still exists is a live cross-reference, not this shape — matching requires a first-person actor behind `in this PR`, so `the files changed in this PR` is not flagged |
| `conversational-antecedent` — asides to the requester | Prose addressed to the person who asked for the page or to the conversation that produced it: `As you asked, …`, `As requested, …`, `Per our discussion, …`, `per your request`, `like you said` | 1 | Delete the address — the conversation is invisible to every future reader, and the assertion behind it survives verbatim once the clause is cut. Two followers stand the shape down, because both name something a future reader can still open: an anaphoric adverb (`as we discussed above`), and `in` ahead of a **document locator** — a `§` or `#anchor`, a section/chapter/step/table, a link or path, or a named durable document (`as we decided in §3`, `in the ADR`). `in` ahead of anything else is matched, so `as we discussed in yesterday's meeting` and `as we decided in favor of X` are residue; tracker nouns are deliberately not locators, since `decided in issue 88` is provenance that `ticket-pr-residue` owns. The actor-less `as requested` matches only as a clause-final adverbial, so the attribution `as requested by the client` is not matched |
| `ticket-pr-residue` — tracker/PR back-references | Bare provenance offered as the reason the prose says what it says: `See PR #45 for the rationale`, `Tracked in JIRA-123`, `decided in issue 88`, `from the feature branch` | 2 | Review — delete a bare provenance reference, or relocate it to the `## Sources` / `## History` footer (already an exempt section, so a relocated reference stops flagging). **Carve-out:** a markdown task-list item (`- [ ] … #123`, `- [x] … #123`) and a `TODO(#123)`-family marker are never flagged — both denote OUTSTANDING tracked work, where the reference is the actionable part of the line, which is the markdown restatement of the sibling's sanctioned-`TODO` exception. Nothing else is carved out: an inline parenthetical (`… (tracked in #482)`) stays Tier 2 so a reviewer rules on it rather than the scanner |
| `negation` — prohibition with no positive alternative | A prohibition (`never`, `do not`, `don't`, `avoid`, `must not`, `should not`) with no positive alternative stated in the same sentence ("Do not use markdown.") | 2 | Rewrite to the positive target the prohibition implies (*"Do not use markdown"* → *"Compose your response as smoothly flowing prose paragraphs"*). Keep a negation only where the positive form genuinely loses the constraint, and then pair it with the positive in the same sentence. **Never a deletion** — the constraint survives; only its framing changes. The write-side rule this completes is [`/docs-hygiene:write-for-agents`](../write-for-agents/SKILL.md) "Prompt the positive". **A hard guardrail that cannot be phrased positively is not a finding** and is never flagged (carve-outs in Hard rules) |

Consumers with their own ephemeral-path or noise conventions can refine these defaults in their repo's `CLAUDE.md` / rules; the classifier's shapes and tiers above are the skill's built-in baseline.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` files from git; file path → single-file; dir path → batch | run `${CLAUDE_SKILL_DIR}/scripts/detect.sh` on targets; map the emitted facts to the per-file tier table using the treatments above |
| `audit [target]` | same target rules | explicit form of the default; same behavior |

Single action v1; `relocate` and `generalize` actions are deferred until real demand surfaces — author hand-edits driven by audit output cover the sweep workflow.

**`--persist-findings`** (off by default) additionally writes the run's `negation` findings as a
`type: review-findings` file for `review:fanout`'s `fix` relay, per
[context/persist-findings.md](context/persist-findings.md) — it owns every mechanic (destination
resolution, the fetch-and-refuse gate, the self-ignore guard, which findings enter the file, and
what each cell says). A bare invocation reports and stops. `negation` is the only shape with a
severity-crosswalk row; the other five stay in the human report and are counted as declined.

## Auto-detect default

Shared clean-tree / no-scope shape: [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md).

1. Empty arg AND clean tree → OFFER the repo-wide audit instead of silently no-opping; run only on
   the user's confirmation. The offer carries prescribed defaults (overridable): corpus = all
   tracked `.md` minus `**/evals/fixtures/**` and `CHANGELOG.md`; slice-scoped files (contract and
   memory tiers) sectioned separately in the report; scan via a chunked `detect.sh` pass
   (`detect.sh --paths-file <list> --offset N --limit M` — one process per chunk, no
   per-file shell loop); on a
   large corpus, judge only scanner-flagged files, fanning out a small number of concurrent
   subagents with one fresh-context verification pass over the merged verdicts; report first —
   this skill stays read-only either way, and the author applies any treatment edits only after
   reviewing the report (report-vs-fix-as-you-go is the author's call; report-first is the
   accuracy-preferred default because repeating shapes get one corpus-wide treatment decision).
   Unattended (no human to confirm), surface the offer as
   blocked and stop — never launch the repo-wide run on silence.
2. Empty arg AND uncommitted `.md` files → batch audit over those files
3. Single file path → single-file audit
4. Directory path → batch audit (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit on rest (explicit form)

## Hard rules

- **Read-only on every audited target.** No `Edit`, no `Write`, no mutating `Bash` op against any
  file this skill audits. The author owns every treatment edit. **Emitting the findings artifact is
  the one write this skill performs, and it is not an exception to that rule** — the distinction is
  **target mutation vs artifact emission**, and only the first is what "read-only" forbids. The
  artifact is a NEW file in the gitignored memory tier, never an audited target; it is written only
  under `--persist-findings`, and it is a proposal for a human-gated relay rather than an applied
  edit. Describing it to an operator as a change that has been made is wrong. The rule widens
  exactly this far and no further: no audited file becomes writable, and a bare invocation still
  writes nothing at all.
- **Tier semantics.** Tier 1 = definite noise; Tier 2 = review needed; Tier 3 = likely legitimate (surfaced for awareness). Tier 3 carries NO treatment — a finding whose ruling includes an edit ("strip", "relocate", "replace") is Tier 2 or 1 by definition.
- **Section EXEMPTIONS never flagged:** `## Recheck triggers`, `## Cross-references`, `## Sources` / `## History` / `## External authority` footers (any ATX heading level — `### Sources` counts; a later non-exempt heading of any level ends the exemption), ADR amendment blocks, `CHANGELOG.md` entries and release notes (detect.sh skips `CHANGELOG.md` by basename), YAML frontmatter (`---` … `---`), and fenced code blocks. Inline `` `code` `` spans are stripped before every shape match EXCEPT ghost-ref, which still sees unwrapped path text — so a shape-definition or worked example written in backticks does not self-match, and an example written in plain quotes does.
- **Dismissal grounds the judgment pass may use** (recurring, sanctioned; the scanner cannot see them): a fictional slug instantiated by a worked example (nothing can dangle), a vendored-verbatim upstream baseline that is never hand-edited by policy, a delete/prune instruction whose target is the path being removed (a record, not a followable reference), and a shape-definition or output-schema example matching its own pattern.
- **Negation carve-outs are evidence-gated, so an unresolved candidate is EMITTED.** Three
  conditions suppress a `negation` candidate, and each requires its evidence present on the
  sentence: a **paired positive** (`instead`, `rather than`, `prefer`, `in place of`, `in favour
  of`), a **hard guardrail** whose constraint a positive form cannot carry (`secret`, `credential`,
  `token`, `password`, `api key`, `force-push`, `--force`, `rm -rf`, `destructive`, `irreversible`,
  `data loss`, `production`, `security`, `vulnerab`, `rewrite history`), or a **worked example**
  (a `->` / `→` demonstration). Absence of that evidence selects the finding — a judgment call can
  make a run noisier but can never silently withhold one. The carve-out lives in the shared scanner,
  so the human report and any persisted findings file give one candidate one disposition. Every
  marker matches as a **whole word**: a bare substring would let a longer word (`secretary` for
  `secret`, `preferentially` for `prefer`) satisfy a *withholding* boundary and lose a real finding
  silently.
- **`negation` is scoped to one physical line (known limitation).** `detect.sh` classifies line by
  line, so a sentence markdown soft-wraps is judged in pieces: `Do not use markdown;` on one line
  with `compose prose instead.` on the next is reported even though the positive is paired in the
  same sentence. The error direction is a false positive, never a silent withhold, so it costs
  reviewer attention rather than coverage. Accumulating sentence state across soft line breaks is
  deferred, not assumed away.
- **Opt-out markers respected.** A well-formed HTML comment line `<!-- markdown-discipline-ignore -->` (covers the next paragraph, through the next blank line or heading) and `<!-- markdown-discipline-ignore-line -->` (exactly the next physical line — a blank line consumes it, so place the marker directly above the content line) skip the wrapped content. A prose mention of the marker name is not a live marker.
- **Convention-path exemptions apply per matched path, never per line.** An angle-bracket slot variable (`.work/<slug>/…`, `docs/topics/<slug>/…`) is a schema placeholder, not a literal path; the reserved concern-scoped roots (`.work/handoffs/`, `.work/reviews/`, `.work/running-retros/`, `.work/overengineering/` — roster SSOT: topic-docs Memory, concern-scoped tier) are citable only bare or with a placeholder child — a concrete child under them flags. A convention token on a line never exempts a concrete ghost ref sharing that line; the tracked concern file (`.claude/topic-docs.yaml`) matches no ghost-ref pattern and needs no exemption. Exception: the retired `.claude/notes/` location flags even in placeholder form.
- **Output deterministic.** Filenames sort lexically; per-file tier rows sort by line number; no timestamps in output.
- **Default action is the audit action** — `/docs-hygiene:audit-noise <file>` is identical to `/docs-hygiene:audit-noise audit <file>`.

## Output schema

Per target file, the existence pre-check verdict precedes the in-page findings:

```text
<file>: admission PASS
<file>: admission FAIL — deletion candidate (relocate-then-delete recommended)
```

A FAIL skips the in-page tier table below; a PASS proceeds to it:

```text
<file>: N finding(s) — T1=<n>, T2=<n>, T3=<n>

| Tier | Shape | Line | Excerpt | Treatment |
|------|-------|------|---------|-----------|
| 1    | citation | 42 | "Empirically observed 2026-..." | Relocate to a ## Sources / ## History footer |
| 2    | ghost-ref | 87 | ".work/foo-slice/PLAN.md cites..." | 3-way classify (promote / SHA-permalink / strip) |
| 2    | preamble | 7  | "## Why this file exists" | Diataxis classify (KEEP if Explanation; STRIP if Reference) |
| 3    | preamble | 1  | (top-of-file orientation paragraph) | Likely legitimate; surfaced for awareness |
| 1    | conversational-antecedent | 9 | "As you asked, this section..." | Delete the address to the requester |
| 2    | ticket-pr-residue | 55 | "See PR #45 for the rationale" | Review (delete bare provenance / relocate to ## Sources) |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited, <T1> Tier 1, <T2> Tier 2, <T3> Tier 3 findings.
```

`shape` values: `citation`, `ghost-ref`, `preamble`, `enum-list`, `scope-meta`, `plan-reference`, `conversational-antecedent`, `ticket-pr-residue`, `negation`.

## What this skill is NOT

- **Not `/docs-hygiene:compress`.** The sibling `/docs-hygiene:compress` owns FLAVOR (filler, hedging, articles, redundant restatement); `/docs-hygiene:audit-noise` owns NOISE (the nine shapes above). Different concerns; both may apply to the same target iteratively.
- **Not `/code-tidying:audit-comment-residue`.** The boundary is the FILE TYPE, not the shape vocabulary: three shape names (`plan-reference`, `conversational-antecedent`, `ticket-pr-residue`) are deliberately shared, so the same authoring failure gets the same name whichever file it lands in, and each file type keeps exactly one owner — markdown here, everything else there, no dedup or precedence rule needed. That split is also why the code skill is not simply widened to `.md`: on markdown its `history-narration` would fire on the same lines as this skill's `citation` with the opposite treatment (delete vs. relocate to a `## Sources` footer), and a conflict between two treatments is resolved by ownership, not by scope. The two detectors do not share pattern code, and this skill's are tighter — see Purpose.
- **Not a markdown linter.** Structural GFM conventions belong to the repo's markdown linter (e.g. markdownlint-cli2); `/docs-hygiene:audit-noise` is semantic noise classification.
- **Not an Edit operation.** Read-only: it surfaces findings; the author applies treatments.
- **Not a content deduplicator.** When the noise is the same concept repeated across files, that is the sibling `/docs-hygiene:extract-ssot`'s territory at any multiplicity — sub-three repetition lands in its non-abstracting buckets, and only minting a new SSOT artifact waits for 3+.

## Sources

- [Diataxis Explanation](https://diataxis.fr/explanation/) — the Diataxis classifier behind the preamble treatment
- [markdownlint configuration](https://github.com/DavidAnson/markdownlint?tab=readme-ov-file#configuration) — opt-out marker HTML-comment form precedent
- [topic-docs convention](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md) — Memory, concern-scoped tier roster (bare-root ghost-ref exemption)
