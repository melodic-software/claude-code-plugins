---
description: "Read-only audit of tracked markdown for nine noise shapes, like historical citations, ghost refs, why-this-file-exists preambles, tracker back-references, and conversational residue, tiered by treatment. Use when: 'audit markdown noise', 'declutter', 'check for stale citations', 'find ghost refs', 'classify preamble', 'strip conversational residue from a doc', 'find negations without a positive', 'sweep a rule/skill/convention doc for noise'. Code comments: /code-tidying:audit-comment-residue."
argument-hint: "[audit] [target] [--persist-findings]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh:*)", "Bash(git branch --show-current:*)", "Bash(git rev-parse --show-toplevel:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Classify markdown for citations, ghost refs, meta-commentary, plan/conversational/tracker residue
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Uncommitted .md files (empty = none matched or the probe returned nothing), `git status --porcelain | grep -E '\.md"?$' | head -10`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 10 entries")
bounds nothing: the Bash tool returns the complete output into context before anything can be decided.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls, not pre-compute lines: the harness runs a skill's whole pre-compute block
as one shell invocation, and a worktree-isolated session refuses a compound command that contains
git. The dated record for that composition claim is the
[gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation),
"The pre-compute block runs as one shell invocation".

## Pre-computed context

Noise findings (sample): !`${CLAUDE_SKILL_DIR}/scripts/detect.sh 2>/dev/null | grep -E '^(status:|Summary total:|Finding shape:)' | head -20 || echo "none"`

## Purpose

Tracked markdown (rules, skill bodies, `CLAUDE.md`, `AGENTS.md`, `docs/`, READMEs) accumulates nine NOISE shapes, distinct from FLAVOR, which the sibling `/docs-hygiene:compress` owns. Every reader pays to read past noise in every file that carries it. This skill is a read-only classifier: it surfaces candidates with treatment guidance; the author hand-applies every edit.

Three shapes, `plan-reference`, `conversational-antecedent`, and `ticket-pr-residue`, share names with the code-side sibling `/code-tidying:audit-comment-residue` because they are the same authoring failure in a different file type. Ownership splits by file type, not shape: markdown is this skill's, everything else is the sibling's, and neither scans the other's files. The patterns are **not** shared code: the sibling classifies only a line's extracted comment portion, while this skill classifies whole prose, where the same words carry meaning far more often, so its patterns are tighter and several of the sibling's cues are deliberately not carried over.

## Existence pre-check (before in-page noise)

Before classifying in-page noise, ask the whole-page admission question:
**could a reader with repository search derive this page's content from the
code itself?** A failing page is a deletion candidate. Its finding recommends
relocate-then-delete (salvage anything admissible first), never a line-level
noise treatment, and never auto-delete (this skill stays read-only).

Four categories always pass admission regardless of derivability: decisions,
domain language, thin navigation, and policy/wiring. For the four-factor
scoring behind a contested call, reuse `/docs-hygiene:audit-derivability`'s
rubric by reference: invoke it via the Skill tool when available; otherwise
apply the admission question standalone.

**Org override.** This pre-check is a portable-baseline default. When the
consuming repository declares its own documentation-existence convention,
defer to it, resolved via `/discipline:follow-our-standards`'s resolution
ladder (repo-declared source → repo's own conventions → this portable
baseline).

Only a page that passes admission proceeds to the nine in-page NOISE shapes below.

## Noise shapes and treatments

| Shape | What it looks like | Default tier | Treatment |
|---|---|---|---|
| `citation`, historical citations | Dated incident citations, inline **origin notes** ("ported from X", "Merged 2026-07-24 from Y"), migration/rename narration ("Empirically observed 2026-…", "was renamed to", "we pivoted from") when the current form suffices | 1 | Relocate to a per-file `## Sources` / `## History` footer; strip when non-load-bearing (version control preserves history). Keep inline only when the date is load-bearing (methodology or freshness stamp). Origin cues are clause-anchored on both sides plus a list-bullet anchor, require column 0 (the code-side sibling allows leading whitespace), and stand down on a line carrying a link (inline or reference-style) or a bare URL, because a pointer is what `/attribution:audit` asks an author to write. The stand-down covers only a pointer, not the other two sanctioned forms: an attribution naming a work rather than a location ("Copied from Kent Beck, *Tidy First?*, chapter 3") is matched, as is a clause-leading descriptive use ("Copied from the source buffer, the bytes are then hashed"). Both land on relocate, not delete, and `## Sources` is an exempt section, so relocating either is terminal |
| `ghost-ref`, refs into slice-scoped working paths | Concrete paths into a memory work slice (`.work/<slug>/`) and concrete children of the concern-scoped roots, cited from durable surfaces, plus any citation of the retired `.claude/notes/` location. The citing document outlives the slice, so slice retirement breaks the reference, whether or not the consumer's memory tier is gitignored | 2 | 3-way classify: promote the content to a durable home, replace with a durable pointer (a commit-SHA permalink or the carrying PR number), or strip. Exemptions apply per matched path, never per line: slot-variable forms (`<slug>` as a schema placeholder, not a literal name) and the bare concern-scoped roots (`.work/handoffs/`, `.work/reviews/`, `.work/running-retros/`, `.work/overengineering/`, `.work/enforceability/`, `.work/exports/`, `.work/lanes/`, reserved first-level names under the memory root, with nothing concrete after) are NOT ghost refs. A concrete child under a concern root flags |
| `preamble`, "Why this file exists" openers | Opening section explaining motivation/history/rationale | 2 | Diataxis classify: KEEP on Explanation-quadrant files (rule bodies, ADRs, convention rationale); STRIP on Reference-quadrant files (data tables, registries, cheat-sheets), replacing with a 1-sentence orientation |
| `enum-list`, hard-coupled consumer lists | Tables/lists hardcoding N specific consumers that drift on every add/remove ("the following five skills…", bulleted `/skill — role` rosters) | 1 | Replace with a runtime derivation (a grep/list command cited inline) or a category citation; hardcode only when both fail |
| `scope-meta`, scope/loading meta-commentary | Body prose restating loading mechanics that config/frontmatter already owns ("Path-scoped to X", "Loads on Read of Y", "Auto-loads when…") | 1 | Strip the clause; the frontmatter/config is the single source of truth. Keep a genuine cross-ref riding the same sentence. Files with no scoping frontmatter MAY state scope in one sentence |
| `plan-reference`, plan/changeset narration | Prose pointing at the work that produced the page instead of its subject: `replaces the old …`, `in this PR we …`, `Task 2 of the plan` | 1 | Delete the plan/changeset frame and keep what the sentence asserts about the present subject, rewritten without it. A doc citing a plan artifact that still exists is a live cross-reference, not this shape. Matching requires a first-person actor behind `in this PR`, so `the files changed in this PR` is not flagged |
| `conversational-antecedent`, asides to the requester | Prose addressed to the person who asked for the page or to the conversation that produced it: `As you asked, …`, `As requested, …`, `Per our discussion, …`, `per your request`, `like you said` | 1 | Delete the address. The conversation is invisible to every future reader, and the assertion survives verbatim once the clause is cut. Two follower classes stand the shape down, because both name something a future reader can still open: an anaphoric adverb (`as we discussed above`), and `in` / `under` / `at` / `on` ahead of a **document locator**, meaning a `§` or `#anchor`, a section/chapter/step/table, a link or path, or a named durable document (`as we decided in §3`, `in the ADR`, `on the ADR's recommendation`). Those prepositions ahead of anything else are matched, so `as we discussed in yesterday's meeting`, `as we decided in favor of X`, `as we agreed on Tuesday`, and `as we decided at the standup` are residue. Tracker nouns are deliberately not locators: `decided in issue 88` is a back-reference that `ticket-pr-residue` owns. The actor-less `as requested` matches only as a clause-final adverbial, so the attribution `as requested by the client` is not matched |
| `ticket-pr-residue`, tracker/PR back-references | A bare back-reference offered as the reason the prose says what it says: `See PR #45 for the rationale`, `Tracked in JIRA-123`, `decided in issue 88`, `from the feature branch` | 2 | Review: delete a bare back-reference, or relocate it to the `## Sources` / `## History` footer (an exempt section, so a relocated reference stops flagging). **Carve-out:** a markdown task-list item (`- [ ] … #123`, `- [x] … #123`) and a `TODO(#123)`-family marker are never flagged: both denote OUTSTANDING tracked work, where the reference is the actionable part of the line (the markdown form of the sibling's sanctioned-`TODO` exception). Nothing else is carved out: an inline parenthetical (`… (tracked in #482)`) stays Tier 2 so a reviewer rules on it, not the scanner. **Routed, not flagged:** in a `SKILL.md` this shape is `/skill-quality:check`'s, and in an `agents/*.md` it is `/harness-config:audit-instructions`'s |
| `negation`, imperative prohibition with no positive alternative | An **imperative** prohibition (`never`, `do not`, `don't`, `avoid`, `must not`, `should not`) opening the sentence, with no positive alternative stated in that sentence ("Do not use markdown."). Soft-wrapped sentences are accumulated across paragraph lines before classification. Descriptive prose ("Older versions do not support this flag"), a mid-sentence cue (already-paired "Prefer X; never Y"), and a table row are out of scope | 2 | Rewrite to the positive target the prohibition implies (*"Do not use markdown"* → *"Compose your response as smoothly flowing prose paragraphs"*). Keep a negation only where the positive form genuinely loses the constraint, and then pair it with the positive in the same sentence. **Never a deletion**: the constraint survives; only its framing changes. This completes the write-side rule [`/docs-hygiene:write-for-agents`](../write-for-agents/SKILL.md) "Prompt the positive". **A hard guardrail that cannot be phrased positively is not a finding** and is never flagged (carve-outs in Hard rules) |

Consumers with their own ephemeral-path or noise conventions can refine these defaults in their repo's `CLAUDE.md` / rules; the shapes and tiers above are the built-in baseline.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` files from git; file path → single-file; dir path → batch | run `${CLAUDE_SKILL_DIR}/scripts/detect.sh` on targets; map the emitted facts to the per-file tier table using the treatments above |
| `audit [target]` | same target rules | explicit form of the default; same behavior |

One action; the author's hand-edits from audit output cover the sweep workflow.

**`--persist-findings`** (off by default) additionally writes the run's `negation` findings as a
`type: review-findings` file for `review:fanout`'s `fix` relay, per
[context/persist-findings.md](context/persist-findings.md), which owns every mechanic (destination
resolution, the fetch-and-refuse gate, the self-ignore guard, which findings enter the file, and
what each cell says). A bare invocation reports and stops. `negation` is the only shape with a
severity-crosswalk row; every other shape `audit_noise_detect_shapes_into` in
[`scripts/lib/noise-shapes.sh`](scripts/lib/noise-shapes.sh) appends stays in the human report and
is counted as declined.

## Auto-detect default

Shared clean-tree / no-scope shape: [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md).
The rules below are what this skill runs; open the shared file only when editing them, for the
sibling divergences it owns.

1. Empty arg AND clean tree → OFFER the repo-wide audit instead of silently no-opping; run only on
   the user's confirmation. The offer carries prescribed defaults (overridable): corpus = all
   tracked `.md` minus `**/evals/fixtures/**` and `CHANGELOG.md`; slice-scoped files (contract and
   memory tiers) sectioned separately in the report; scan via a chunked `detect.sh` pass
   (`detect.sh --paths-file <list> --offset N --limit M`, one process per chunk, no
   per-file shell loop); judge every scanner-flagged file AND a bounded sample of
   scanner-negative files (enough that a fresh full-corpus judgment pass cannot find
   real drift this report called clean). Never report a fully-clean result from
   scanner-flagged files alone: the scanner is a structural matcher, not a complete
   reading of the shape table, and judgment is required for the paraphrases it misses.
   Size the judgment pass to the corpus. When every file fits one inline reading (tens of files,
   not the hundreds that make a fan-out pay), read every file in the main session and skip both
   the fan-out and the verification pass: a full reading already covers the scanner-negative
   sample, and subagent verdicts would need re-reading anyway. Above that, fan out a small number
   of concurrent subagents with one fresh-context verification pass over the merged verdicts.
   Report first. The skill stays read-only either way, and the author applies treatment edits only
   after reviewing the report (report-vs-fix-as-you-go is the author's call; report-first is the
   accuracy-preferred default because repeating shapes get one corpus-wide treatment decision).
   Unattended (no human to confirm), surface the offer as blocked and stop. Never launch the
   repo-wide run on silence.
2. Empty arg AND uncommitted `.md` files → batch audit over those files
3. Single file path → single-file audit
4. Directory path → batch audit (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit on rest (explicit form)

## Hard rules

- **Read-only on every audited target.** No `Edit`, no `Write`, no mutating `Bash` op against any
  file this skill audits; the author owns every treatment edit. **Emitting the findings artifact is
  the one write this skill performs, and it is not an exception**: "read-only" forbids **target
  mutation**, not **artifact emission**. The artifact is a NEW file in the gitignored memory tier,
  never an audited target, written only under `--persist-findings`, and a proposal for a
  human-gated relay, not an applied edit. Describing it to an operator as a change that has been
  made is wrong. No audited file becomes writable, and a bare invocation still writes nothing.
- **Tier semantics.** Tier 1 = definite noise; Tier 2 = review needed; Tier 3 = likely legitimate (surfaced for awareness). Tier 3 carries NO treatment. A finding whose ruling includes an edit ("strip", "relocate", "replace") is Tier 2 or 1 by definition.
- **Section EXEMPTIONS never flagged:** `## Recheck triggers`, `## Cross-references`, `## Sources` / `## History` / `## External authority` footers (any ATX heading level, so `### Sources` counts; a later non-exempt heading of any level ends the exemption), ADR amendment blocks, `CHANGELOG.md` entries and release notes (detect.sh skips `CHANGELOG.md` by basename), YAML frontmatter (`---` … `---`), and fenced code blocks. Inline `` `code` `` spans are stripped before every shape match EXCEPT ghost-ref, which still sees unwrapped path text. A shape-definition or worked example written in backticks does not self-match; one written in plain quotes does.
- **Dismissal grounds the judgment pass may use** (recurring, sanctioned; the scanner cannot see them): a fictional slug instantiated by a worked example (nothing can dangle), a vendored-verbatim upstream baseline that is never hand-edited by policy, a delete/prune instruction whose target is the path being removed (a record, not a followable reference), and a shape-definition or output-schema example matching its own pattern.
- **Negation carve-outs are evidence-gated, so an unresolved candidate is EMITTED.** Three
  conditions suppress a `negation` candidate, each only with its evidence present on the
  sentence: a **paired positive** (`instead`, `rather than`, `prefer`, `in place of`, `in favor
  of`, or a bare imperative after a separator such as an em dash, semicolon, or colon, looking through a
  leading adverb such as `just` / `simply`), a **hard guardrail** whose constraint a positive form cannot carry (`secret`, `credential`,
  `token`, `password`, `api key`, `force-push`, `--force`, `rm -rf`, `destructive`, `irreversible`,
  `data loss`, `production`, `security`, `vulnerab`, `rewrite history`), or a **worked example**
  (a `->` / `→` demonstration). Absent evidence selects the finding: a judgment call can make a
  run noisier but never silently withhold one. The carve-out lives in the shared scanner, so the
  human report and any persisted findings file give one candidate one disposition. Every marker
  matches as a **whole word**: a bare substring would let a longer word (`secretary` for
  `secret`, `preferentially` for `prefer`) satisfy a *withholding* boundary and lose a real
  finding silently.
- **`negation` selects only an IMPERATIVE, and classifies the accumulated sentence.** Two scope
  gates; without them the shape fires on most descriptive prose in an instruction corpus and buries
  every real finding. (1) The cue must open the **sentence**, after list, blockquote,
  task-list-checkbox and emphasis markers. "Prompt the positive" is a rule about *instructions*,
  so descriptive prose is out of scope, and a mid-sentence cue is already the paired form
  ("Prefer X; never Y"). The stated cost: a subject-led instruction ("The agent must not emit a
  bare summary") is not selected. (2) Soft-wrapped sentences are accumulated across paragraph
  lines before the classifier runs, so a wrapped prohibition is judged as one sentence. A finding
  is attributed to the sentence's first physical line, where the cue opens, so the fix action
  lands on the instruction's start, not its continuation. The other eight shapes stay
  line-scoped. A table row still does not select: a row begins with `|`.
- **Opt-out markers respected.** A well-formed HTML comment line `<!-- markdown-discipline-ignore -->` covers the next paragraph, through the next blank line or heading. `<!-- markdown-discipline-ignore-line -->` covers exactly the next physical line; a blank line consumes it, so place it directly above the content line. Both skip the wrapped content. A prose mention of the marker name is not a live marker.
- **Convention-path exemptions apply per matched path, never per line.** An angle-bracket slot variable (`.work/<slug>/…`) is a schema placeholder, not a literal path; the reserved concern-scoped roots in the `ghost-ref` row are citable only bare or with a placeholder child, and a concrete child under them flags. A convention token on a line never exempts a concrete ghost ref sharing that line. Exception: the retired `.claude/notes/` location flags even in placeholder form.
- **Output deterministic.** Filenames sort lexically; per-file tier rows sort by line number; no timestamps in output.
- **Default action is the audit action**. `/docs-hygiene:audit-noise <file>` is identical to `/docs-hygiene:audit-noise audit <file>`.

## Output schema

Two writers, one report. `detect.sh` emits `File:` / `Finding *:` / `Summary *:`
lines only. It does **not** emit admission verdicts, and does **not** emit
Tier 3 for any of the nine named shapes (each has a fixed default tier in
`audit_noise_shape_tier`); a scanner `T3=` count is reserved for an
unrecognized shape name, which should not occur. Admission and any Tier 3
"likely legitimate" row are **judgment-pass** rulings the operator writes after
reading the scanner facts. Do not treat scanner stdout as if it contained
`admission PASS` / `admission FAIL`.

A run that scanned nothing is distinct on stdout from one that scanned files
and found nothing: `detect.sh` prints `status: no-targets` in the first case
(even when stderr is discarded, as the pre-computed context above does). A
clean audit prints `Summary total: files=<N>` with `N>0` and zero findings.

Per target file, the judgment-pass existence pre-check precedes the in-page findings:

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
| 2    | ticket-pr-residue | 55 | "See PR #45 for the rationale" | Review (delete a bare back-reference / relocate to ## Sources) |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited, <T1> Tier 1, <T2> Tier 2, <T3> Tier 3 findings.
```

`shape` values: `citation`, `ghost-ref`, `preamble`, `enum-list`, `scope-meta`, `plan-reference`, `conversational-antecedent`, `ticket-pr-residue`, `negation`.

## What this skill is NOT

- **Not `/docs-hygiene:compress`.** The sibling `/docs-hygiene:compress` owns FLAVOR (filler, hedging, redundant restatement, and articles when `compress_articles` is `cut`); `/docs-hygiene:audit-noise` owns NOISE (the nine shapes above). Both may apply to the same target iteratively.
- **Not `/code-tidying:audit-comment-residue`.** The boundary is the FILE TYPE, not the shape vocabulary (see Purpose): each file type keeps exactly one owner, so no dedup or precedence rule is needed. The code skill is not simply widened to `.md` because on markdown its `history-narration` and `origin-note` would fire on the same lines as this skill's `citation` with the opposite treatment (delete vs. relocate to a `## Sources` footer), and a conflict between two treatments is resolved by ownership, not by scope.
- **Not a markdown linter.** Structural GFM conventions belong to the repo's markdown linter (e.g. markdownlint-cli2); `/docs-hygiene:audit-noise` is semantic noise classification.
- **Not an Edit operation.** Read-only: it surfaces findings; the author applies treatments.
- **Not a content deduplicator.** The same concept repeated across files is the sibling `/docs-hygiene:extract-ssot`'s territory at any multiplicity. Sub-three repetition lands in its non-abstracting buckets, and only minting a new SSOT artifact waits for 3+.

## Next

- Findings are persisted with `--persist-findings`: `/review:fanout fix`.
- A page failed the existence pre-check and needs the four-factor ruling:
  `/docs-hygiene:audit-derivability`.
- What is left is flavor rather than noise: `/docs-hygiene:compress`.

## Sources

- [Diataxis Explanation](https://diataxis.fr/explanation/), the Diataxis classifier behind the preamble treatment
- [Claude 4 best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-4-best-practices), source of the negation rule's worked example ("Do not use markdown" rewritten to the positive form), read 2026-08-31; recheck when that page drops or rewords the example
- [markdownlint configuration](https://github.com/DavidAnson/markdownlint?tab=readme-ov-file#configuration), opt-out marker HTML-comment form precedent
