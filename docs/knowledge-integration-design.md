# knowledge — apply/integrate skill (design record)

Spec for the `knowledge` plugin's first-class value step: a session opens against the consolidated
`knowledge-artifacts` corpus and fits relevant findings into **any** target repo. Capability and shape
(a skill, not a manual workflow) are already locked — see `MIGRATION-PLAYBOOK.md`
"Knowledge-artifacts consuming repo + integration flow — decision record (2026-07-13)". This record
specs the skill; it does not re-open the mechanism. **No build here** — the implement follow-up is
emitted below.

## The problem

Ingest skills (`book-distill`, `youtube`, `course-digest`) produce durable, concept-organized artifacts
that each carry repo-applicability recommendations. Today those recommendations are read by a human and
applied by memory — nothing codifies the analyze-here → fit-into-a-target step, and the corpus is
decoupled from any one product repo (it lives in `melodic-software/knowledge-artifacts`). The apply
skill closes that gap as a repeatable, invocable capability that works against **any** target, not just
the repo that happens to be open.

Scope boundary: the corpus holds ingest-pipeline material and its synthesized outputs — source media,
transcripts, frame extractions, distilled reference files. It is not a general documentation home;
repo-owned docs stay in their repos, and durable per-topic knowledge flows through the knowledge-vault
seam, not this corpus.

## Load-bearing decision — the session's home is the corpus

A session runs **in the corpus checkout** (`knowledge-artifacts` is `${CLAUDE_PROJECT_DIR}`); the
**target repo is an explicit per-invocation argument**. This falls directly out of the record's framing
("a session opens against the corpus, then fits findings into any target repo") and resolves the
two-pointer tension cleanly:

- The corpus is read from the session's own tree — no pointer knob for it.
- `library_dir` is **not** overloaded as the corpus pointer. `library_dir` is the *landing* directory
  for ingest output in a consuming repo; in a target-repo session it resolves to *that target's* landing
  dir, which is the wrong thing to read a corpus from. Keeping the corpus as CWD sidesteps the collision.
- No new `userConfig` knob is added (contract Rule of Three — no speculative knobs): the corpus is the
  CWD, the target is an argument.

Rejected alternative — *session home is the target, corpus reached via a new `corpus_dir` knob*: adds a
speculative knob, and couples every target-repo session to corpus config it otherwise never needs.

## Invocation surface

- Invoked from a checkout of `knowledge-artifacts`: `/knowledge:apply --target <path-or-repo>`.
- `--target` accepts a local path (a sibling checkout) or an `owner/repo` slug the skill clones into a
  scratch working tree (cross-repo mechanics below).
- Optional `--topic <term>` narrows the corpus to one concept area; absent, the whole corpus is ranked.
- Default is **read-only** (produce a report). Writing is a separate, gated step (proposal/apply below);
  no flag silently mutates the target.
- `argument-hint` advertises the target argument; the skill refuses with a clear message when run outside
  a corpus checkout (no corpus to analyze) rather than guessing a corpus location.

## Target-repo scan

The skill discovers what in the target is improvable against the corpus, read-only:

- **Stack fingerprint** — languages, frameworks, build/test tooling, and ecosystem markers, so corpus
  findings can be matched to what the target actually uses.
- **Existing-practice surfaces** — the target's own `CLAUDE.md` / `AGENTS.md` / `.claude/rules` / `docs`
  and any `.claude/skills`, to learn both its declared conventions (contract seam 3 — the target's own
  steering governs how a proposal is framed) and which corpus practices it already adopts.
- **Gap signal** — where a corpus recommendation is relevant to the stack but absent from the target.

Scan is bounded and cached to `${CLAUDE_PLUGIN_DATA}` (machine state, survives updates) so a re-run
against the same target does not re-walk the tree.

## Relevance ranking

Corpus artifacts (reference files, YouTube applicability menus, course digests) are matched and ranked to
the target's surfaces by three factors, highest-weighted first:

1. **Stack fit** — the artifact's topic maps to a framework/language/tooling the target uses.
2. **Gap** — the target does not already apply the practice (a fit-but-present item ranks below a
   fit-but-absent one).
3. **Recommendation strength** — the artifact's own stated applicability priority.

Output is a ranked candidate menu (backend-neutral **work-item** vocabulary), each item citing its corpus
source artifact and the target surface it would touch — enough for the operator to decide without
re-reading the corpus.

## Proposal / apply mechanism — read-only-first, human-gated

A strict **report → diff → PR** ladder, never a silent write:

1. **Report (default)** — the ranked menu above. No target mutation.
2. **Diff** — for operator-selected items, generate concrete edits as a reviewable diff against a target
   working tree. Still no push.
3. **PR** — on explicit approval, open a pull request against the target's remote (the review gate is the
   PR itself; integrations land through review, never a direct commit to the default branch).

The human review gate sits between every stage. The skill frames edits in the target's *own* conventions
(from the scan) rather than imposing corpus-repo style.

## Contract v2.1 fit

- **Seam 1 (`userConfig`)** — no new knob. Corpus = CWD; target = per-invocation argument. `library_dir`
  is left as the ingest landing seam it already is.
- **Seam 3 (consumer steering)** — the skill reads the *target's* `CLAUDE.md` / `.claude/rules` so
  proposals match the target's declared conventions with no plugin-side wiring.
- **Convention-resolution ladder** — config present → use it; absent → infer from the target tree and
  record the inference; cannot infer → ask. No baked target-repo layout.
- **`${CLAUDE_PLUGIN_DATA}`** — scan results and ranking cache only (machine state), never configuration.
- **External systems** — the PR step uses `gh` directly with backend-neutral work-item vocabulary; no
  pluggable-tracker abstraction, no shipped MCP server (CLI covers the need — MCP discriminator rule 1).
- **Cross-skill references** — degrade gracefully: hand off to a present skill via its slash invocation,
  fall back to prose when absent.
- **Setup** — unchanged; the apply skill introduces no new persisted config, so `/knowledge:setup` needs
  no new interview branch.
- **Evals** — warranted: the skill is judgment-bearing (trigger, routing on `--topic`, the write-gate
  refusal, the shape of the ranked menu). Author `evals/evals.json` against fixtures in the implement
  issue; fixtures do not need the live corpus repo.

## Cross-repo mechanics

Two repos, one session, no MCP:

- **Corpus** — the session CWD (`knowledge-artifacts`), read directly.
- **Target** — a local sibling checkout given by `--target <path>`, or an `owner/repo` slug the skill
  clones into a scratch working tree under `${CLAUDE_PLUGIN_DATA}`. Edits land in that working tree.
- **PR** — opened with `gh pr create -R <target-remote>` from the target working tree, so the corpus repo
  is never a commit target. A `owner/repo` target with no local checkout is cloned read-then-branch; a
  path target is operated on in place (or in a worktree) at the operator's choice.

## Emitted issue

- **`implement(knowledge-integration)`** — build the `/knowledge:apply` skill to this spec: `SKILL.md`
  (invocation, scan, ranking, report→diff→PR gate), `evals/evals.json` against fixtures, and a README
  row. **agent-ready** — authoring is grounded in this spec plus contract v2.1 and needs no live corpus
  repo; end-to-end exercise against the real `knowledge-artifacts` corpus is validated once #1393 lands
  (non-blocking for authoring). Sub-issue of wave-2 map #1369.
