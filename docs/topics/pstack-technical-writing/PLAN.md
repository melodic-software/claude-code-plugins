# pstack-technical-writing — `/docs-hygiene:write-for-humans`

Lane 4 of the cursor/plugins pstack port. Upstream: `pstack/skills/technical-writing/SKILL.md`
(MIT), clone pinned at `60c641e4`, 131 lines, no supporting files.

## Brief

### TLDR

Ship the write-side doctrine for **human-facing** prose as the declared sibling of
`write-for-agents`. Ship it **lane-2 shaped**: the layers resolve from the consuming project's own
declared style guide first, and the four bundled standards are a named, replaceable default set —
never this marketplace's house rules imposed on a consumer.

### Goal

Close a hole the incumbent declares twice about itself. `docs-hygiene:write-for-agents` is the
fleet's only write-time prose doctrine, and both its description (`SKILL.md:2`) and its
"What this skill does NOT do" (`:112`) exclude human-facing docs: "end-user READMEs, changelogs, and
marketing prose have a different reader and different rules." Nothing else claims that surface —
verified across `wizard`, `plugin-quality`, `knowledge`, `education`, `playbooks`, `bug-report`,
`planning`, `github`, `adhd`, `naming`, `domain-driven-design`, and a sweep of every `description:`
line in the marketplace, which returns only `ai-slop:audit` (audit-side), `docs-hygiene:compress`
(flavor-trim), `discipline:tighten-your-output` (terseness), and `bug-report:write` (one fixed
artifact).

Two of upstream's four layers have **zero** presence in this marketplace: `grep -rln` for
"google developer style" / "developers.google.com/style" and for "global english" both return
nothing. Diátaxis appears three times and is never applied — twice as classification context
(`audit-derivability`, `audit-noise`) and once as a research-source pointer
(`code-tidying/skills/tidy/lanes/docs-prose.md:68`). Nothing picks a document's mode.

### The lane-2 constraint, and why it reshaped this lane

An adversarial fresh-context audit challenged 6 of 10 round-1 answers and reclassified 1 to the
maintainer. Its central finding is the one that reshaped the design:

`PLUGIN-PHILOSOPHY.md:198-202` admits a shipped default "only when it is a good-practice value that
cannot conflict in *any* repo the plugin drops into", and names Conventional Commits as the
archetype of what fails that test. Google developer style, ASD-STE100, and Global English are that
class — repos pick Microsoft's guide, Chicago, or an in-house one instead. **The proof was inside
the round-1 answer set:** an answer existed solely to delete two Global English rules because they
already conflicted with the authoring repo's own em-dash ruling. A standard that must be pre-edited
to stop fighting its home repo cannot be a value that "cannot conflict in any repo".

So the standards ship as **resolvable defaults**, the same idiom `naming:name-it-better` uses
("scores against the resolved source of truth; missing criteria route upstream") and
`code-tidying:tidy` uses for its per-consumer lanes. The em-dash and semicolon rules stay in the
default set, where a consumer's own config or style guide disables them — rather than being deleted
for every consumer because one repo disagreed.

## Constraints

1. **Lane 2, not lane 1.** The skill resolves the consuming project's declared style guide before
   applying anything bundled. The four standards are named as the fallback default set.
2. **No repo-specific paths, symbols, or conventions in the skill body.** `PLUGIN-PHILOSOPHY.md:192`
   and `scripts/check-skill-portability.sh`. This kills the worked example as upstream wrote it —
   upstream's example is about its own `budget.mjs`, and a substitute path from *this* repo is the
   same defect with a different string.
3. **Write-time only.** Mirrors `write-for-agents/SKILL.md:110-111`. Audits route out.
4. **One spoke, not three.** The three sentence-level layers are consumed simultaneously — every
   sentence passes all three — so splitting them forces three opens per sentence, against
   `write-for-agents/SKILL.md:32` and `:63`.
5. **No edit to `discipline:wait-what`.** A `reference/` spoke is a private surface under
   `audit-encapsulation`'s public-surface contract, and `wait-what/SKILL.md:26-27` states it
   "deliberately stays this small: a skill that fights unclear output fails by growing."
6. **No claim on commit messages or PR bodies.** `ai-slop/skills/audit/SKILL.md:110` already
   excludes them from the markdown-prose regime; shape is owned by `source-control:commit`'s
   subject-convention ladder and `docs/conventions/pr-body-convention/`.
7. **Both descriptions route.** `write-for-agents` gains a route here, and this skill routes back.
8. **Every external standard carries a four-part upstream-drift stamp** — claim, basis, as-of date,
   and an observable recheck trigger. `docs/conventions/upstream-drift/README.md:88-92` bars a bare
   date, which is all upstream's stamps carry.
9. **No frontmatter `name`.** `PLUGIN-PHILOSOPHY.md:79-86`.
10. **`disable-model-invocation: false`, stated explicitly**, so check 24 can gate it.

## Acceptance criteria

- [x] AC1 — `plugins/docs-hygiene/skills/write-for-humans/SKILL.md` exists; `skill-quality:check`
      returns PASS with 0 errors.
- [x] AC2 — The body resolves a consuming project's declared style guide BEFORE applying any
      bundled layer, and names the bundled set as the replaceable default.
- [x] AC3 — The Diátaxis mode picker ships with all four modes and the don't-mix rule.
- [x] AC4 — One spoke, `reference/sentence-rules.md`, carries all three sentence-level layers.
- [x] AC5 — The em-dash and semicolon rules are PRESENT in the default set, with the consumer-config
      escape stated, not deleted.
- [x] AC6 — The worked example contains no path, symbol, or filename from any real repository.
- [x] AC7 — Upstream review-checklist items 1 and 8 are absent (cross-document audit and
      count-verification are not write-time self-checks).
- [x] AC8 — Four upstream-drift stamps, each with an observable recheck trigger.
- [x] AC9 — No commit-message or PR-body claim anywhere in the skill.
- [x] AC10 — `write-for-agents`' description routes here, and this skill's routes back; the
      trigger-continuity gate passes on `write-for-agents`.
- [x] AC11 — `evals/evals.json` ships and passes `check-evals-quality.sh`.
- [x] AC12 — `plugin.json` skill list, plugin README table, `docs/CATALOG.md`, and
      `SKILL-CHEAT-SHEET.md` all include the new skill.
- [x] AC13 — `docs-hygiene` version bumped with a CHANGELOG entry.
- [x] AC14 — `docs/upstream/cursor-pstack.md` carries the `technical-writing` attribution row with
      taken / rejected / renamed and the port's recheck trigger.
- [x] AC15 — `code-tidying`'s docs-prose lane is left unchanged, and the reason is recorded.
- [x] AC16 — No frontmatter `name`; `disable-model-invocation: false` stated explicitly.

## Phases

- [x] **Phase 1** — SKILL.md + the sentence-rules spoke. AC1-AC9, AC16.
- [x] **Phase 2** — Route both descriptions; evals. AC10, AC11.
- [x] **Phase 3** — Packaging: plugin.json, README, CATALOG, cheat sheet, version, CHANGELOG.
      AC12, AC13.
- [x] **Phase 4** — Provenance row and the decided-drops record. AC14, AC15.
- [x] **Phase 5** — Gates, commit, push.

## Decided drops, recorded so a later reader sees they were considered

The audit surfaced twelve upstream items the round-1 set never decided on. Each is resolved here:

1. **"The codebase is the word list"** — KEPT, generalized: write the real symbol, file, flag, or
   command name of the *thing being documented*.
2. **"Add new offenders to unslop's abstract-metaphor rule"** — DROPPED. `ai-slop`'s
   `reference/catalog.md` is a private surface and a CC BY-SA 4.0 derived corpus; telling a consumer
   to edit another plugin's internals is an encapsulation violation twice over.
3. **"Use the compass on one sentence; gut feel is often wrong here"** — KEPT.
4. **"Don't mix modes; split and link instead"** — KEPT.
5. **"Apply unslop to every doc this skill touches"** — KEPT as a presence-gated invoke of
   `/ai-slop:audit`, phrased per `docs/conventions/seam-phrasing/`.
6. **"Product UI strings are not documentation"** — KEPT as a scope exclusion.
7. **"Indent code snippets with tabs"** — DROPPED. A hard formatting convention that collides with
   a consuming repo's own linter config; lane-1 material by the same test that reshaped this lane.
8. **"Make every count or tree claim true at the commit that lands it"** — KEPT in the body as a
   writing rule, but NOT as a checklist item (that is the verification action cut per AC7).
9. **"Skip idioms, colloquialisms, Latin abbreviations, metaphors"** — KEPT; it is a Global English
   rule about translation and non-native readers, which is a different axis from `ai-slop`'s
   AI-authorship tells, so this is not a duplicate rubric.
10. **The four source stamps** — KEPT and upgraded to four-part drift stamps (AC8).
11. **The STE fidelity caveat** ("the numbered rules and dictionary live in the spec PDF; the
    principles above are the transferable core") — KEPT, and load-bearing: it is why this ships a
    paraphrase of a standard rather than claiming to be the standard.
12. **Frontmatter `name: technical-writing`** — DROPPED per AC16.
