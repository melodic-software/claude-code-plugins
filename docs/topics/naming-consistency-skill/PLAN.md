# naming-consistency-skill

## Brief

> Scope-change note, 2026-09-12: PR #4097 landed as `d5a8a04b` and the branch `claude/naming-consistency-skill` now exists off `main`, so this Brief and plan live in the contract slice `docs/topics/naming-consistency-skill/PLAN.md`; ADR references are `0034` (main claimed `0033` first); the emitted path-scoped rule file is opt-in (`--rule`) because this repository itself deferred its rule file under the unhobble baseline; the reproduction pin is `7eb1f628`.
>
> Contract tier note, 2026-09-11: this Brief sat in the memory slice (`contract_tier: local`)
> because the branch that will carry the skill is itself an open maintainer question (Q14); it moves
> to `docs/topics/naming-consistency-skill/PLAN.md` on that branch once the branch exists. Interview
> ran unattended under the maintainer's standing posture (accept decisions resolved by fresh-context
> agents when backed by consensus research); ten questions resolved that way, and the five that were the
> maintainer's were answered on 2026-09-12 (see Deferred questions).

### TLDR

- Add to `docs-hygiene` a reusable pair that generalizes PR #4097: a read-only `audit-file-names`
  that inventories a doc tree's file names against a casing rule with an exemption set, computes the
  reference blast radius, classifies every reference by a parameterized tier boundary, refuses
  case-only collisions, and writes a rename plan as a findings artifact; and a `realign-file-names`
  that consumes that artifact behind one acceptance per file rename, performs `git mv`, applies the
  scripted reference maps by tier, regenerates declared generated files, and delegates the straggler
  sweep per pair to `rename-references audit orphans`.
- Repo-specific values (casing regex, scope roots, exemptions, tier path sets, hard exclusions,
  generated files with their regenerators) live in a tracked `.claude/docs-hygiene.json` read with
  jq, written and validated by a thin `docs-hygiene:setup`; bundled defaults equal this repository's.
- Gate emission produces a portable checker on the check-script contract, its co-located test, and a
  path-scoped rule file (template: `scripts/check-docs-naming.sh`); CI wiring, registry rows, and the
  ADR stay the consumer's, the ADR offered through `/architecture:record-decision`.
- Versioned-unit bumping and redirect-map emission are out of v1 unless the maintainer opts in
  (Q7, Q13); the skill ships in its own draft PR on a branch the maintainer names (Q14).

### Goal

A maintainer of any repository with a documentation tree can bring its file names to one stated
casing rule, with every reference repointed and the historical record respected, in one audited,
per-rename-gated pass, and leave behind a gate that keeps the tree consistent, without repeating the
hand-built scripts PR #4097 needed.

### Constraints

- The pair honours the plugin philosophy's verb table as written: the audit is read-only on bare
  invocation and writes its findings artifact to the memory tier; the realign consumes that artifact,
  never re-inventories the tree, never re-derives a casing verdict or a tier, blocks a finding whose
  file moved since the audit (the fix is a re-audit), and mutates only behind explicit per-item
  acceptance, never a blanket approval.
- The acceptance unit is one file rename with its mechanical reference edits (13 acceptances for the
  rename PR's case, never one per reference). A reference edit that needs judgment (an ambiguous bare
  token, a tier-boundary call) is resolved in the audit or escalated singly; rename-references'
  bucket-level auto-apply is acceptable only inside one accepted rename.
- Case-only collisions among tracked paths (pre-commit `check-case-conflict` algorithm: fold new and
  existing paths plus parent directories, intersect) are a hard refusal in both skills; `git mv old
  new` performs a case-only rename in one step and `core.ignoreCase` is never changed.
- Files the concern file lists as generated are never sed-edited; the realign runs their declared
  regenerator after apply and fails if the regenerator is absent.
- Tier semantics are a parameter: current surfaces change in every form; historical-record tiers
  change in links and backtick paths only; a released-changelog tier is untouched by default; the
  per-tier form table is printed before any apply.
- Leaf names are qualified (`audit-file-names`, `realign-file-names`, or `tidy-file-names` under the
  one-skill option) and change no leaf-name registry entry; `disable-model-invocation: false` on the
  audit and realign, `true` on `setup` (exception class ii); every new skill carries `evals/evals.json`,
  a `## Next` section, and, if it declares `allowed-tools`, the pairing test.
- Descriptions stay under 1,024 codepoints (description plus `when_to_use` under 1,536), and
  `check-listing-budget.sh plugins/docs-hygiene/skills` (7545/8000 today) is brought back under the
  estimate by trimming existing docs-hygiene descriptions in the same PR; the cap baseline only
  shrinks.
- The concern file `.claude/docs-hygiene.json` gains a row in the config-cascade Implementers table
  in the same PR; the shape borrows ls-lint's scope map plus ignore list plus escape-hatch regex.
- House style: no em dashes in any new file; skill bodies state the current rule, never the incident;
  scripts, not heredocs, carry the sed maps (this repository's guardrail hooks block heredoc and
  inline-interpreter file writes); `rename-references` gains a `## Next` pointer to the new audit,
  which bumps docs-hygiene (minor).
- Every new script is on the check-script contract, registered in `check-script-contract.test.sh`
  when it lives under `scripts/`, black-box tested through `fixture-tree.sh` with git isolation, and
  clean under shellcheck, shfmt, and check-shell-portability.
- Draft PR first; Conventional Commits title; PR body with the four sections and the closing line.

### Acceptance criteria

- On a fixture tree with three uppercase files and thirty references across current, ADR, and
  changelog tiers, `audit-file-names` writes a findings artifact with one finding per rename, each
  carrying the old and new path, the tier of every reference site with its line range, and the
  collision verdict; the tree is byte-identical before and after (`git status --porcelain` empty).
- `audit-file-names` on a fixture where `docs/Foo.md` and `docs/foo.md` would both exist after the
  plan exits non-zero naming the collision, and writes no plan.
- `realign-file-names` on that artifact performs exactly the accepted renames via `git mv`, edits
  every current-tier reference form, edits only links and backtick paths in historical tiers, leaves
  the changelog tier untouched, runs the declared regenerator, and leaves an unaccepted rename and
  all its references untouched.
- `realign-file-names` refuses a finding whose file moved since the audit and names the re-audit as
  the fix; it never edits a file the concern file lists as generated.
- IF the maintainer answers "approve everything" to a realign gate, THEN the realign refuses and
  re-presents the current item alone.
- The emitted checker passes `check-script-contract.test.sh`'s three dimensions on a fixture (clean
  exit 0 with a stdout statement, seeded violation exit 1 with the finding on stderr only, missing git
  exit 2), and its emitted test proves the uppercase, underscore, empty-dot-segment, and case-collision
  failures.
- `docs-hygiene:setup` writes `.claude/docs-hygiene.json` with this repository's defaults, `setup
  check` exits 0 on it and non-zero on a malformed file, and the audit resolves the same values from
  it that PR #4097 used by hand (regex, exemptions, three tiers, the landscape.json regenerator).
- `scripts/check-changed-skills.sh origin/main` exits 0 on every new SKILL.md;
  `check-listing-budget.sh plugins/docs-hygiene/skills` reports under the estimate; changelog parity,
  the em-dash gate, and `scripts/affected-tests.sh --run` exit 0.
- Run against this repository at the pre-rename tip of `main`, `7eb1f628` (revised 2026-09-12 from `c61ed529`, which the #4097 squash left unreachable), the pair reproduces the rename
  PR's outcome: the same 13 renames, no residual old basename or bare stem outside the historical
  tiers, and the same generated-file regeneration, with 13 acceptances.

### Captured assumptions

- Unwanted-behaviour and state-driven coverage went unexamined: the interview ran unattended, so the
  coverage prompt was skipped; the negative criteria above (collision refusal, moved-file refusal,
  blanket-approval refusal, generated-file refusal) come from the validators, not from the maintainer.
- The pair is the working shape (Q2 blocked, default the pair); every constraint above that names the
  pair has a one-skill reading (`tidy-file-names` with a `--plan` preview) that the plan carries as
  its alternative until the maintainer answers.
- The bundled defaults are this repository's current values as of PR #4097; another consumer edits
  the concern file rather than the skill.
- The existing `docs-hygiene:rename-references` stays as it is apart from the `## Next` pointer; its
  48-case evals surface is not migrated.
- No `.claude/topic-docs.yaml` exists, so the topic-docs defaults apply; the Brief's contract tier is
  local only until Q14 resolves.

### Out-of-scope

- Versioned-unit bumping inside the skill (Q7, unless the maintainer opts in).
- Redirect-map emission for site generators (Q13, unless the maintainer opts in).
- Source-code trees as a first-class target (Q15; v1 is doc trees).
- In-file formatting consistency (headings, frontmatter shape), the follow-up the maintainer deferred
  in the rename interview.
- Renumbering duplicate ADRs, this repository's CI wiring for consumers, and any change to
  `rename-references` beyond its `## Next` section.

### Deferred questions

- None. The five maintainer questions were answered on 2026-09-12 ("approved", each default
  taken): Q2 the audit/realign pair; Q7 no bump stage in v1 (documented as a manual step); Q13 no
  redirect-map stage in v1 (concern-file key reserved, map shape recorded in the reference file);
  Q14 a new draft-PR branch `claude/naming-consistency-skill` off `main` after #4097 merges, where
  this Brief moves to `docs/topics/naming-consistency-skill/PLAN.md`; Q15 doc trees only, host
  `docs-hygiene`.

## Plan

> Revision 2, 2026-09-12: the fresh-context plan review (2 CRITICAL, 12 IMPORTANT, 9 SUGGESTION,
> every finding verified against the cited files) reshaped this plan: per-finding drift guards
> replace the whole-file blob hash; gate emission moves off `setup` onto its own
> `disable-model-invocation: true` skill; every script takes `--root`; the artifact merges by old
> path across re-audits; `generated` is team-layer only; suite fixtures live under
> `scripts/fixtures/`; the ADR is `0034`. Revision 3 folded the devil's-advocate run (1 CRITICAL,
> 5 HIGH, 7 MEDIUM, 6 LOW): the reproduction pin moves to main's pre-rename tip, write-back
> preserves the inode, bare stems are anchored and reviewed rather than blindly edited, finding ids
> derive from the old path, the budget is a Phase 1 table, and the resolver strips CRLF.

### Goal

**What**: add to `docs-hygiene` a `setup` skill with a tracked concern file, a read-only
`audit-file-names` that writes a consent-gated rename plan, a `realign-file-names` that executes
accepted renames one at a time with tiered reference repointing, and a manual-timing
`generate-file-name-gate` that writes a portable checker and test (and, on request, a rule file)
into a consumer, all bundled with tests, evals, and the plugin's bump.
**Why**: PR #4097 did the five jobs (inventory, tiered sweep, `git mv`, generated-record
regeneration, gate) with hand-built scratch scripts that live nowhere; ADR 0034 records that the
sweep "is not reusable as written". The pair makes the next tree, in this repository or any other,
a per-rename-gated run instead of a rebuild.

### Standards grounding

No standards index exists (`.claude/standards.yaml` and `docs/standards/` absent; rung 6, nothing
persisted). The plan is grounded in the repository's own convention surfaces read this session:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/plugin-philosophy.md` | Naming (verb table: `audit` read-only, `realign` consumes sibling findings behind per-item gates); "Setup is explicit and repeatable" (setup owns only the plugin's configuration surface, `apply` scoped to that artifact); Cross-platform contract (record a manual-verification gap for OS-sensitive behavior); Fresh-eyes checkpoints | team |
| `scripts/skill-leaf-name-registry.txt`, `scripts/check-skill-leaf-names.sh` | qualified leaves collide with nothing; `setup *` is open-set; bare `generate` is registered to `ai-briefing,wizard`, so the emitter takes a qualified leaf | team |
| `plugins/skill-quality/scripts/check-skill.sh` | checks 1, 2, 2b, 4/10, 5, 7, 14, 22, 24, 25, 27; trigger-phrase drop check; invoked as `CHECK_SKILL_SKILLS_ROOT=<plugin>/skills check-skill.sh [--require-evals] <leaf>` | team |
| `plugins/skill-quality/scripts/check-listing-budget.sh` | shared budget 8000, docs-hygiene at 7545 over 9 skills; `disable-model-invocation: true` skipped | team |
| `scripts/skill-description-cap-baseline.txt` | three docs-hygiene skills over 1,024; the file only shrinks | team |
| `docs/conventions/invocation-mode/README.md` | `false` on audit and realign; `true` on setup (class ii) and on the emitter (class i, a side-effect workflow with human timing) | team |
| `docs/conventions/config-cascade/README.md` | Implementers row shape; three layers, per-key override; policy-floor class for a key a personal layer must not weaken; resolution anchors at `${CLAUDE_PROJECT_DIR}` | team |
| `docs/conventions/topic-docs/README.md` (Implementers table, docs-hygiene row), `plugins/review/reference/topic-docs.md` | five-rung resolution; memory-tier artifacts; non-interactive collapse; self-ignore guard | team |
| `docs/conventions/detector-findings/README.md`, `plugins/instruction-placement/context/findings-artifact.md` | a consent-gated artifact is never `type: review-findings`; status arcs; `branch:` proves ownership; per-finding drift, merge by stable id, declines never resurrected | team |
| `README.md` "The check-script contract" | exit 0/1/2, findings stderr, statement stdout; `scripts/check-*.sh` registry (plugin scripts are outside it) | team |
| `scripts/check-changelog-parity.sh` header, `plugins/docs-hygiene/CHANGELOG.md` | a new skill is a minor bump; `## [x.y.z]` entry above main's | team |
| `scripts/check-purged-em-dashes.sh`, `scripts/em-dash-purged-paths.txt` | docs-hygiene patterns cover `*.md`, `context/*.md`, `skills/*/{SKILL,actions,context,reference,evals/fixtures}`; new plugin-level `reference/` and `templates/` need patterns | team |
| `scripts/check-orphaned-fixtures.sh` | every file under `**/evals/fixtures/` must be named by a grader or a test; `scripts/fixtures/` is out of scope | team |
| `scripts/check-shell-portability.sh`, `scripts/check-fixture-git-isolation.sh`, `scripts/check-silent-skips.sh`, `.shellcheckrc` | portable shell, git-isolated fixtures, no skip lines, `add-default-case` | team |
| `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` | a grant pairs only with an unquoted, wrapper-free `${CLAUDE_SKILL_DIR}/scripts/...` invocation in the body | team |
| `docs/adr/0034-name-docs-files-lower-kebab-case-with-conventional-exceptions.md` | the rule, exemptions, tier boundary, hard cutover, case-collision refusal, the deferred rule file | team |

### Approach

Sequential, integration-first inside each layer: the concern file and its reader come first
because every script resolves values through them; the audit's artifact shape is fixed before the
realign that consumes it; the emitter reuses the audit's resolved values; publication and the
reproduction run close. Scripts carry every deterministic stage (inventory, collision fold, form
ladder, tier match, map generation, apply); the model owns tier judgments the config leaves open,
the per-item gate, and the summaries. Every script accepts `--root <dir>` (default: the git
toplevel of the current directory) and runs git as `git -C "$root"`, so a worktree or a fixture
is addressed explicitly and `${CLAUDE_PROJECT_DIR}` never redirects a run to the wrong tree; a
detached checkout slugs as `detached-<short-sha>`. Every path list in the concern file (`roots`,
`exempt_paths`, `sweep_exclude`, tier `paths`) is matched by git's own `:(glob)` pathspec so one
matcher decides what `**` means. Every existence or collision test goes through the index
(`git ls-files --error-unmatch`, the fold-and-intersect), never `-e`/`-f`, because a
case-insensitive filesystem answers those for the wrong spelling.

**Build technique**: kept tracer-bullet slice. Phase 3's sanity check is the end-to-end fixture run
(audit writes the plan, realign applies one accepted rename, then a second) before Phases 4 and 5
widen it.

### Phase 1: Concern file, resolver, and the setup skill [TODO]

Review: code-design

The single consumer surface every later script reads.

| File | Action | Rationale |
|---|---|---|
| [ ] Pre-flight (first work item) | KEEP | Identify consumers: `git grep -n 'docs-hygiene.json\|docs-hygiene/reference'` must return nothing (no parser of these paths exists); record the exact command that reproduces the committed `docs/architecture/landscape.json` (`plugins/architecture/skills/map-landscape/SKILL.md` documents `landscape-record.sh`; if no single command reproduces the committed record byte-for-byte apart from `generated_on`/`last_touched`, the default `generated` entry names the command and states which fields churn) |
| [ ] `plugins/docs-hygiene/scripts/lib/resolve-config.sh` | CREATE | Sourced library: merge user-global `~/.claude/docs-hygiene.json`, team `.claude/docs-hygiene.json`, overlay `.claude/docs-hygiene.local.json` per top-level key of `file_names` with jq, every read piped through `tr -d '\r'` (native Windows jq emits CRLF); `tiers`, `generated`, `sweep_exclude`, and `exempt_*` are **policy-floor keys**: the team layer wins a direct conflict, a personal layer may only add roots or exemptions, and `generated` is team-layer only (a command the realign executes); the resolved output names the supplying layer beside every value; `"schema": 1` is required and an unknown schema exits 2; bundled defaults from `skills/setup/templates/docs-hygiene.json` when every layer is absent; prints the resolved document and the layer per key; takes `--root` |
| [ ] `plugins/docs-hygiene/scripts/lib/resolve-config.test.sh` | CREATE | Self-contained (no repo test lib; inline `unset GIT_DIR GIT_WORK_TREE GIT_CONFIG`, mktemp fixtures, fake HOME): absent layers resolve to defaults; team overrides per key; overlay wins per key except the policy-floor keys; `generated` from an overlay or user-global layer is reported inert; malformed JSON exits 2 with the file named; a CRLF-terminated document through a stub `jq` resolves clean values; missing `schema` exits 2 |
| [ ] `plugins/docs-hygiene/skills/setup/templates/docs-hygiene.json` | CREATE | Bundled defaults equal to this repository's values (the design sketch's document, with the released tier `**/CHANGELOG.md` per the interview) |
| [ ] `plugins/docs-hygiene/reference/config.md` | CREATE | Every key, default, provenance, layer rules, the policy-floor keys, `schema`; the `_comment` allowance; `redirect_map` reserved; `sweep_exclude_sites` (`<file>:<literal>` pairs a sweep never edits, the reproducible form of a hand decision); a regenerator is expected to be idempotent on an unchanged tree and may stamp dates (named per entry under `churn`); the manual bump step (Q7) named as a consumer procedure |
| [ ] Listing-budget table (Phase 1 deliverable, recorded in this plan's evidence notes) | KEEP | Per-skill target lengths for the eleven listed docs-hygiene descriptions summing to at most 7,900 codepoints: the two new listed descriptions written first at 600 to 700 each, trims spread across the nine siblings (the four over or near the cap first), every single-quoted trigger phrase preserved verbatim |
| [ ] `plugins/docs-hygiene/skills/setup/scripts/setup-check.sh` | CREATE | PASS/FAIL/INFO table: jq present; each layer absent or parses; required keys and types; `regex` compiles under `grep -E`; every `generated[].regenerate` non-empty and its first word resolves (`command -v` or an existing path under the root); tier names unique; `regex` free of `'` (it is inlined into an emitted script); team file tracked and not ignored; overlay ignored (WARN with the recommended line); a personal layer that declares a policy-floor key is reported as overridden. Exit 0/1/2; `--root` |
| [ ] `plugins/docs-hygiene/skills/setup/scripts/setup-apply.sh` | CREATE | `--defaults` writes the bundled document to the team path when absent; `key=value` merges per key with jq; prints `already configured` on no change; never edits `.gitignore`; never writes outside `.claude/docs-hygiene.json` |
| [ ] `plugins/docs-hygiene/skills/setup/scripts/setup-check.test.sh`, `setup-apply.test.sh` | CREATE | Self-contained; the design's malformed cases exit 1 (check), an unresolvable regenerator exits 1, idempotent re-run (apply) |
| [ ] `plugins/docs-hygiene/skills/setup/SKILL.md` | CREATE | Uniform setup contract (template `plugins/code-metrics/skills/setup/SKILL.md`, but script paths unquoted and wrapper-free so the pairing test passes): `check` (default) / `apply [--defaults | key=value ...]`; `disable-model-invocation: true`, `user-invocable: true`; `allowed-tools` paired to the two scripts; `## Next` names `/docs-hygiene:audit-file-names`; `## Gotchas` |
| [ ] `plugins/docs-hygiene/skills/setup/evals/evals.json` | CREATE | Three cases: check on a clean fixture, check on a malformed file, apply defaults then check |
| [ ] `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` | MODIFY | Add `setup` to `SKILLS` |
| [ ] `scripts/em-dash-purged-paths.txt` | MODIFY | Add `plugins/docs-hygiene/reference/*.md` and `plugins/docs-hygiene/skills/*/templates/*` |
| [ ] `.claude/docs-hygiene.json` | CREATE | This repository's own team layer, written by `setup apply --defaults` and committed |
| [ ] `docs/conventions/config-cascade/README.md` | MODIFY | One Implementers row: `docs-hygiene`, `.claude/docs-hygiene.json`, all three layers, conforms (per-key override on `file_names.*`; `generated` in the policy-floor class, team-tracked only, because the realign executes it) |
| [ ] `plugins/docs-hygiene/README.md` | MODIFY | Requirements: jq already listed; add the configuration surface paragraph and the `setup` row (final table lands in Phase 5) |

**Sanity Check:**

- [ ] `bash plugins/docs-hygiene/scripts/lib/resolve-config.test.sh && bash plugins/docs-hygiene/skills/setup/scripts/setup-check.test.sh && bash plugins/docs-hygiene/skills/setup/scripts/setup-apply.test.sh` exit 0
- [ ] `bash plugins/docs-hygiene/skills/setup/scripts/setup-check.sh` exits 0 on this repository and prints one `PASS` row per key group; on a fixture whose `regex` is `[` it exits 1 naming the key; on a fixture whose regenerator's first word resolves to nothing it exits 1
- [ ] The recorded regenerator command, run from the repository root, leaves `git diff --stat docs/architecture/landscape.json` empty or changing only the fields the `generated` entry names
- [ ] `jq -e '.file_names.rule == "lower-kebab" and (.file_names.tiers | length) == 3' .claude/docs-hygiene.json` exits 0
- [ ] `CHECK_SKILL_SKILLS_ROOT=plugins/docs-hygiene/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals setup` reports 0 FAIL; `bash plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` exits 0
- [ ] `shellcheck` and `shfmt -d` over every new `.sh` exit 0; `scripts/check-shell-portability.sh --paths plugins/docs-hygiene` exits 0
- [ ] `grep -c '`docs-hygiene`.*docs-hygiene.json' docs/conventions/config-cascade/README.md` is 1; `grep -c 'docs-hygiene/reference' scripts/em-dash-purged-paths.txt` is 1
- [ ] `grep -nE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)' <every new .sh under plugins/docs-hygiene>` prints nothing (Bash 3.2 denylist; the portability gate does not cover these)
- [ ] The budget table exists in this plan's evidence notes and its targets sum to at most 7,900

### Phase 2: `audit-file-names` (read-only) [TODO]

Review: code-design

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/docs-hygiene/skills/audit-file-names/scripts/inventory.sh` | CREATE | `--config <json> [--root <dir>]`: `git -C "$root" ls-files -z` under each root; apply `exempt_*`; check the basename against `regex`; propose the `lower-kebab` transform; fold every tracked path (plus parent directories) with `tr` and intersect proposed against existing (pre-commit `check-case-conflict` algorithm); emit `OFFENDER`, `COLLISION`, `EXEMPT` TSV rows; exit 0 (2 on usage, missing git, or an unknown `rule`) |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/scripts/sweep.sh` | CREATE | `--config <json> --pairs <tsv> [--root <dir>]`: for each old basename, `git grep -n -F` over tracked files minus `sweep_exclude`; form ladder `raw-url`, `github-url`, `md-link`, `backtick-path`, `table-or-key`, `bare-stem` (anchored as `(^|[^A-Za-z0-9_/.-])STEM([^A-Za-z0-9_.-]|$)` so `CATALOG` never matches inside `CATALOG-TAXONOMY`, maps ordered longest old name first); a `bare-stem` site whose stem is one dictionary-shaped word (no hyphen, no digit) takes `action: review` and is escalated singly by the audit, never edited blind; `sweep_exclude_sites` pairs take `action: skip`; tier = the declared tier whose matching glob has the most path segments, `current` when none matches, ties by declared order; `action` from the tier's `forms`; `generated` paths marked `regenerate`; substring hazards handled by anchoring (`CATALOG.md` never matches `CATALOG-TAXONOMY.md`) |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/scripts/emit-findings.sh` | CREATE | Composes the artifact from the two TSVs; one record per offender with a stable id `FN-<8 hex of sha1(old path)>`, presented in site-count order; each site row carries its excerpt so realign can re-verify the line; **merge semantics**: when the out file exists and its `branch:` matches, records are matched by id (the old path), `declined`/`applied`/`applying`/`blocked` statuses survive, vanished offenders are dropped, and a `roots:` mismatch refuses unless `--replace`; exit 1 and no write when any `COLLISION` row exists (the collision named on stderr); exit 3 on empty input |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/scripts/*.test.sh` | CREATE | One suite per script, self-contained, mktemp git fixtures copied from `scripts/fixtures/`; cases: uppercase, underscore, exempt names, topics slice, code extensions, dotted stem, collision, each form of the ladder, each tier's action, generated marking, the `CATALOG` versus `CATALOG-TAXONOMY` substring hazard, an `UNSAFE CATALOG SOURCE` prose line as `review`, a `sweep_exclude_sites` pair as `skip`, two mutually referencing offenders, a worktree root passed through `--root`, a detached checkout slug, merge on re-run preserving a `declined` record, roots mismatch |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/scripts/fixtures/tree/` | CREATE | A tree with three uppercase files that cite each other and thirty references across current, historical, and released tiers plus one generated JSON and a stub regenerator script (out of the orphaned-fixture gate's scope; every suite names it) |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/evals/evals.json` | CREATE | Cases (narration where paths are fictional): plan written with one finding per rename and the tree byte-identical; collision refusal; empty-offender report; a `declined` record surviving a re-audit |
| [ ] `plugins/docs-hygiene/context/file-name-findings.md` | CREATE | The artifact shape (design sketch minus `Old blob`; `head:` is recorded for the evidence trail, never checked), stable ids, status arcs including `applying`, who writes what, merge-by-old-path, decline durability (a decline is checkout-local unless the operator accepts the offered `exempt_paths` entry in the team concern file, offered never taken); `type: docs-hygiene-file-name-findings`, never `review-findings` |
| [ ] `plugins/docs-hygiene/reference/topic-docs.md` | CREATE | Binding: `<memory_dir>/docs-hygiene/<branch-slug>/file-names.md`, five-rung resolution, self-ignore guard, non-interactive collapse |
| [ ] `docs/conventions/topic-docs/README.md` | MODIFY | Rewrite the `docs-hygiene` Implementers row: writes `file-names.md` (memory tier, concern-scoped), delta doc `plugins/docs-hygiene/reference/topic-docs.md` |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/context/tiers.md` | CREATE | Per-tier form table printed before any apply; specificity rule; the three default tiers and why released entries are untouched by default |
| [ ] `plugins/docs-hygiene/skills/audit-file-names/SKILL.md` | CREATE | Gather block; `[audit] [root ...]`; run the three scripts; resolve the home through the binding; write or merge the artifact; summarize; refuse on collision; `disable-model-invocation: false`; `allowed-tools` paired (unquoted invocations); `## Next`: `/docs-hygiene:realign-file-names`; `## Gotchas` |
| [ ] `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` | MODIFY | Add `audit-file-names` to `SKILLS` |

**Sanity Check:**

- [ ] The three suites exit 0; `bash .../inventory.sh --config <fixture-config> --root <fixture>` prints exactly 3 `OFFENDER` rows and 0 `COLLISION` rows; on the collision fixture prints 1 `COLLISION` row
- [ ] `emit-findings.sh` on the fixture writes a file whose frontmatter has `type: docs-hygiene-file-name-findings` and `findings: 3`, and `git -C <fixture> status --porcelain` is empty afterwards; a second run after marking FN-002 `declined` keeps that status
- [ ] `emit-findings.sh` on the collision TSV exits 1, names the twin on stderr, and `test ! -e <out>` holds
- [ ] `CHECK_SKILL_SKILLS_ROOT=plugins/docs-hygiene/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals audit-file-names` reports 0 FAIL; `bash plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` and `scripts/check-orphaned-fixtures.sh --check` exit 0
- [ ] `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/docs-hygiene/skills` prints `within budget` (the new description counts from this phase on)
- [ ] `grep -c 'file-names.md' docs/conventions/topic-docs/README.md` is at least 1

### Phase 3: `realign-file-names` (per-item gated executor) [TODO]

Review: code-design

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/docs-hygiene/skills/realign-file-names/scripts/apply-rename.sh` | CREATE | `--config <json> --artifact <path> --id FN-NNN [--root <dir>] [--dry-run]`: per-finding drift guard: the old path must still be in the index at the root (`git ls-files --error-unmatch`, never `-e`) and each site's cited line must still carry the old token (a site that no longer matches is reported and skipped, never edited blind; a substitution that would hit zero times is a reported skip, never a silent no-op; an old path that is gone exits 1 `blocked: re-audit`, unless the new path is present with `Status: applying`, which resumes); refuse `Status` other than `pending`/`accepted`/`applying`; regenerator resolvability is checked before anything moves; write `Status: applying` first; `git -C "$root" mv old new` (one step, case-only included; `core.ignoreCase` never touched); build the basename map and, for `all` tiers, the stem map; apply per site, only the forms the tier allows, editing through a temp file written back with `cat "$tmp" > "$target"` so the inode, mode bits, and symlink target survive (never `sed -i`, never `mv` over the target, never a `generated` path); run each touched `generated[].regenerate` from the team layer, fail if its first word does not resolve; write `applied` (or `blocked`) into the record and **remap sibling records**: site rows that named the renamed file now name the new path; `--dry-run` prints the per-tier form table and the planned edits |
| [ ] `plugins/docs-hygiene/skills/realign-file-names/scripts/apply-rename.test.sh` | CREATE | Self-contained, fixtures from the audit skill's `scripts/fixtures/`; cases: accepted rename applied with every current form edited; an executable fixture script keeps its mode bits after its reference is edited; historical file receives link and backtick edits only; released file untouched; unaccepted sibling untouched; two mutually referencing offenders applied in sequence (the second still applies after the first edited its file); missing old path refused; a drifted site skipped and reported; generated path never edited and the stub regenerator ran (marker written); unresolvable regenerator fails before `git mv`; an interrupted apply (`applying` with the file already moved) resumes to `applied`; idempotent second run is a no-op; `--root` against a second worktree |
| [ ] `plugins/docs-hygiene/skills/realign-file-names/context/apply-recipe.md` | CREATE | The presentation before each acceptance (old, new, site counts per tier, generated files, collision verdict), the exact script call, the verification after, the offered-never-taken `exempt_paths` entry on decline |
| [ ] `plugins/docs-hygiene/skills/realign-file-names/SKILL.md` | CREATE | Argument `[FN-xxxxxxxx ...]`: each explicit id is one acceptance (ranges, globs, `all`, `everything`, or a blanket yes are refused out loud and the current item re-presented; branch match check (no head match: consumers commit between renames); the orphan sweep runs for every `applying` or `applied` pair, not only after a clean apply; per-item script call; the straggler sweep per pair through the Skill tool: `/docs-hygiene:rename-references audit orphans <old> to <new>`; never commits; "What this skill does NOT do" names the manual bump step for versioned units; `## Next`: the consumer's verification workflow and `/docs-hygiene:rename-references`; `## Gotchas` |
| [ ] `plugins/docs-hygiene/skills/realign-file-names/evals/evals.json` | CREATE | Cases: one accepted id applied and the sibling untouched; blanket approval refused; missing old path blocked with the re-audit named |
| [ ] `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` | MODIFY | Add `realign-file-names` |

**Sanity Check:**

- [ ] `bash .../apply-rename.test.sh` exits 0; `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/docs-hygiene/skills` prints `within budget`
- [ ] End-to-end on the Phase 2 fixture: audit writes the plan; `apply-rename.sh --id FN-001` then `git -C <fixture> diff --name-status HEAD` shows exactly one `R` line for FN-001 plus modified files that are all listed under FN-001's sites; `git -C <fixture> grep -c <old-basename>` in the released-tier file is unchanged; the historical file's narrative line still carries the old bare stem; FN-002's old path still exists; then `apply-rename.sh --id FN-002` exits 0 and its sites inside FN-001's renamed file are edited at the new path
- [ ] `apply-rename.sh --id FN-003` after `git -C <fixture> mv <old> <elsewhere>` exits 1 with `re-audit` on stderr and no other file changes
- [ ] `CHECK_SKILL_SKILLS_ROOT=plugins/docs-hygiene/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals realign-file-names` reports 0 FAIL

### Phase 4: `generate-file-name-gate` (manual-timing emitter) [TODO]

Review: code-design

Emission writes consumer-owned files under the consumer's `scripts/`, which is outside what the
setup contract lets `setup apply` touch, so it is its own skill: qualified leaf (bare `generate`
is registered to other owners), `disable-model-invocation: true` (a side-effect workflow whose
timing is the operator's; also outside the listing budget), `user-invocable: true`.

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/templates/check-file-names.sh.tmpl` | CREATE | `scripts/check-docs-naming.sh` generalized: roots, regex, exemptions inlined at emission (`@@ROOTS@@`, `@@REGEX@@`, ...), the case-collision pass, the check-script contract (findings stderr, statement stdout, 0/1/2), no plugin dependency at run time |
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/templates/check-file-names.test.sh.tmpl` | CREATE | Self-contained suite proving uppercase, underscore, empty-dot-segment, and case-collision failures plus the exemptions |
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/templates/file-names-rule.md.tmpl` | CREATE | Path-scoped rule with `paths:` from roots, the rule and exemptions, the gate named; emitted only with `--rule` |
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/scripts/emit-gate.sh` | CREATE | `--config <json> [--root <dir>] [--out-dir scripts] [--rule] [--force]`: renders the templates through awk `-v` assignment (never a sed replacement, so `&`, `\`, and `|` in a consumer regex cannot break the emitted script); refuses to overwrite an existing target without `--force`; with `--rule`, writes `.claude/rules/file-names.md` and, when the consumer's `AGENTS.md` or `CLAUDE.md` carries a `BEGIN GENERATED: instruction-placement rules index` block, prints that the index must be re-rendered (mention-only pointer to `/instruction-placement:check`); prints the wiring it does not do (CI step, registry row, ADR through `/architecture:record-decision`) |
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/scripts/emit-gate.test.sh` | CREATE | Names every template basename (affected-tests mapping); emitted checker: clean fixture exit 0 with the statement on stdout only; seeded violation exit 1 with the finding on stderr only; `git` hidden from PATH exit 2; emitted test suite exits 0 against the emitted checker; `--rule` on a fixture carrying an index block prints the re-render notice; overwrite refused without `--force` |
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/SKILL.md` | CREATE | `[--out-dir <dir>] [--rule] [--force]`; states the unhobble-style caveat (a rule file is a pointer surface the consumer may deliberately not carry); `## Next`: `/architecture:record-decision`; `## Gotchas` |
| [ ] `plugins/docs-hygiene/skills/generate-file-name-gate/evals/evals.json` | CREATE | Cases: emit into a fixture and run the emitted checker; refuse overwrite; `--rule` notice |
| [ ] `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh` | MODIFY | Add `generate-file-name-gate` |

**Sanity Check:**

- [ ] `bash plugins/docs-hygiene/skills/generate-file-name-gate/scripts/emit-gate.test.sh` exits 0 and its output contains `emitted checker passes the three contract dimensions`
- [ ] In a fixture, after `emit-gate.sh --root <fixture> --out-dir scripts`, `bash scripts/check-file-names.sh --check` exits 0, and after `touch docs/NEW-FILE.md && git add -A` it exits 1 naming `docs/NEW-FILE.md` on stderr with empty stdout
- [ ] `shellcheck` over the emitted checker and test (rendered into the fixture) exits 0
- [ ] `CHECK_SKILL_SKILLS_ROOT=plugins/docs-hygiene/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals generate-file-name-gate` reports 0 FAIL; `scripts/check-skill-leaf-names.sh --check` exits 0

### Phase 5: Integration, budget, reproduction, publication [TODO]

Review: code-design

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/docs-hygiene/skills/rename-references/SKILL.md` | MODIFY | Add `## Next` before `## Gotchas`: `tree-wide casing cleanup: /docs-hygiene:audit-file-names`; description clause "for a whole tree against a casing rule use audit-file-names" |
| [ ] `plugins/docs-hygiene/skills/{compress,write-for-humans,audit-progressive-disclosure,audit-noise}/SKILL.md` | MODIFY | Trim description prose only; every single-quoted trigger phrase preserved verbatim (check-skill's trigger-phrase drop check); target under 1,024 codepoints each |
| [ ] `scripts/skill-description-cap-baseline.txt` | MODIFY | Remove the three docs-hygiene rows once under the cap (the file only shrinks) |
| [ ] `plugins/docs-hygiene/README.md` | MODIFY | Skill table rows for `setup`, `audit-file-names`, `realign-file-names`, `generate-file-name-gate`; the configuration surface section; the manual bump step for versioned units |
| [ ] `plugins/docs-hygiene/.claude-plugin/plugin.json` | MODIFY | `description` names the four skills; version to the next minor above main (`0.22.0` if main is still `0.21.x`) |
| [ ] `plugins/docs-hygiene/CHANGELOG.md` | MODIFY | `## [0.22.0]` with `### Added` (four skills, the concern file, the binding, the artifact contract) and `### Changed` (rename-references `## Next` and description clause; four descriptions trimmed) |
| [ ] `docs/catalog.md`, `docs/skill-cheat-sheet.md` | MODIFY | Regenerated through `node scripts/generate-catalog.mjs` and `node scripts/generate-cheatsheet.mjs` |
| [ ] `.github/workflows/ci.yml` | MODIFY | One `test-windows` step running `plugins/docs-hygiene/skills/realign-file-names/scripts/apply-rename.test.sh` (opt-in by name, like the existing fixed suites), so NTFS exercises the case-only `git mv` path; no `id:` (not a hygiene step) |
| [ ] `docs/topics/naming-consistency-skill/PLAN.md` | CREATE then DELETE | The Brief and this plan on the branch (contract tier); pruned in the final commit; pasted into the PR body with the pre-prune SHA |

**Reproduction run** (the Brief's last acceptance criterion): the pre-rename tip on `main` is
`7eb1f628` (`d5a8a04b^`, the parent of the #4097 squash; `c61ed529` is unreachable from `main`
after the squash), so `git worktree add <tmp> 7eb1f628` and `git -C <tmp> ls-tree --name-only
HEAD docs/ | grep -c '[A-Z]'` prints 13 before anything runs;
copy `.claude/docs-hygiene.json` into it; run `inventory.sh`, `sweep.sh`, `emit-findings.sh` with
`--root <tmp>`; assert 13 `FN-` records; run `apply-rename.sh --root <tmp>` for each of the 13 ids;
assert the residual greps from ADR 0034 hold outside the historical and released tiers, the 13 `R`
lines of `git diff --name-status -M HEAD -- docs/` match PR #4097's rename set, `git diff
--summary | grep 'mode change'` is empty, `landscape.json` was regenerated (the `edges` array
equal to the PR's; date-stamped fields are the declared churn), and
every file in `git diff --name-only` is either one of the 13, a file PR #4097's sweep commit
edited, or a generated file. The set comparison is handed to a fresh-context verifier (the
authoring context does not grade its own reproduction); differences are recorded in the plan's
evidence notes, and a difference in the edited-file set routes to `/planning:plan review` before
the PR leaves draft.

**Manual-verification gap (cross-platform contract):** a case-only `git mv` on a case-insensitive
filesystem cannot be observed on this Linux runner; the `test-windows` CI lane runs the suites, and
that lane's result on the emitted and bundled suites is the recorded verification for Windows. macOS
is unverified and recorded as such in the plugin README.

**Sanity Check:**

- [ ] `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/docs-hygiene/skills` prints `within budget`
- [ ] `scripts/check-changed-skills.sh origin/main` exits 0 (nine changed skills: four new, `rename-references`, four trims; 0 failed) and its output carries no trigger-phrase WARN line (check 3 is advisory, so the WARN lines are read, not trusted to fail); `scripts/check-skill-leaf-names.sh --check` exits 0; `actionlint .github/workflows/ci.yml` and `scripts/check-lane-coverage.sh --check` exit 0
- [ ] `scripts/check-changelog-parity.sh --check-bump origin/main && scripts/check-changelog-parity.sh --check && scripts/check-changelog-parity.sh --check-order` exit 0
- [ ] `node scripts/generate-catalog.mjs --check && node scripts/generate-cheatsheet.mjs --check` exit 0
- [ ] `scripts/check-purged-em-dashes.sh && scripts/check-fixture-git-isolation.sh --check && scripts/check-silent-skips.sh && scripts/check-shell-portability.sh --paths plugins/docs-hygiene && scripts/check-orphaned-fixtures.sh --check` exit 0
- [ ] `scripts/affected-tests.sh --run` exits 0 with every changed file mapped (the claude-ops process-budget cases are the known environmental exception on this runner)
- [ ] `markdownlint-cli2` over every changed markdown file reports 0 issues; `typos` and `editorconfig-checker` over the changed files exit 0
- [ ] The reproduction run's assertions above hold and the fresh-context set comparison returned no unexplained difference; the evidence note is in this file
- [ ] `scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0 on the final head; the PR body carries the four sections, the `No related issue` line, the plan in a `<details>` block, and the pre-prune SHA

### Files affected (whole plan)

Roughly 48 files: 36 created under `plugins/docs-hygiene/` (four skills with scripts, tests,
context, evals, fixtures, templates; the plugin-level resolver, reference, and context files), one
new tracked concern file, and twelve modified (four sibling descriptions, README, manifest,
changelog, the pairing test, the cap baseline, the em-dash path list, the config-cascade and
topic-docs rows, `ci.yml`, the two generated docs).

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| One `tidy-file-names` skill with a `--plan` preview | Q2 answered: the pair, which matches the two existing `realign` precedents and keeps the per-item gate structurally separate from the inventory | The maintainer asks for a single entry point |
| Wrap ls-lint or remark-lint for the inventory | Research LT9: no tool covers inventory plus rename plus tiered repoint; the repo builds 80-plus bash `check-*.sh` siblings; a Node or Go binary adds a dependency for a 60-line walk | The repository adopts ls-lint for another reason |
| Drive every repoint through `rename-references apply` | Interactive Edit-tool application, one pair per run; 13 pairs across three tiers is a scripted job (EXPLORE patterns, Q4); it stays the straggler sweep per pair | rename-references gains a batch map mode |
| YAML concern file through `parse-concern-value.sh` | That parser reads scalars only; the surface carries lists and maps; the fleet's list-shaped precedents are JSON with jq (Q5) | The shared parser grows list support |
| Python scripts for the sweep | The ruff pin rule and the Windows lane; every docs-hygiene sibling script is bash; Bash 3.2 compatibility is already the house rule | A stage needs a real parser (a markdown AST) |
| Gate emission as `setup apply gate` | The setup contract scopes `apply` to the plugin's own configuration artifact; consumer `scripts/` are not that artifact (plan review finding 5) | The setup contract widens |
| Gate emission as a realign stage | `realign` executes findings and never authors (Q8) | The verb table gains an `emit` verb |
| Whole-file blob hash as the drift guard | Renamed docs cite each other, so the first apply changes every sibling's blob and blocks the rest (plan review finding 1) | Findings stop sharing files |
| Ship the bump stage now | Q7 answered: out of v1; this repository's parity gate catches a missed bump | The maintainer opts in |

### Test strategy

Test-first per script (Red, then the minimal script, then the exemption and edge cases), each
suite self-contained like `audit-noise/scripts/detect.test.sh` because plugin scripts ship to
consumers without the repository's test lib; the Brief's "black-box tested through
`fixture-tree.sh` with git isolation" is read as git-isolated mktemp fixtures with the same
isolation the builder provides (inline `unset GIT_DIR GIT_WORK_TREE GIT_CONFIG`, a full test
identity), and its "on the check-script contract" as the 0/1/2 exit and stderr/stdout split for
gate-shaped scripts, with detectors exiting 0 on findings as every docs-hygiene detector does; `emit-findings.sh`'s
exit 3 on empty input is a documented deviation in its header (precedent: `affected-tests.sh`). Test
boundaries the tests drive:

- `inventory.sh`, `sweep.sh`, `emit-findings.sh`, `apply-rename.sh`, `setup-check.sh`,
  `setup-apply.sh`, `emit-gate.sh`, `resolve-config.sh` CLIs (newly introduced; black-box through
  mktemp git fixtures, every one with `--root`)
- The emitted checker and its emitted test (newly introduced; rendered into a fixture and run
  there, including the three check-script contract dimensions)
- Every new `SKILL.md` through `check-skill.sh --require-evals` and `check-changed-skills.sh`
  (existing gate); every `evals.json` through the evals-quality lint (existing gate)
- `allowed-tools` grants through the plugin's pairing test (existing)
- The whole pipeline through the reproduction run at `7eb1f628` (this repository's own history as
  the fixture; a manual verification graded by a fresh-context verifier and recorded in the plan,
  not a committed suite)

Edge cases named in the suites: dotted stems (`v1.2.schema.json`), empty dot segments, the
`CATALOG` versus `CATALOG-TAXONOMY` substring hazard, a bare stem followed by `.md` (handled by the
basename map, never double-edited), a learner-workspace `GLOSSARY.md` under `sweep_exclude`, a
generated path in the site list, two offenders that cite each other, a drifted site line, a second
worktree as `--root`, an artifact whose `branch:` differs from the checkout, a re-audit over a
`declined` record, a CRLF-emitting stub `jq`, an executable file whose reference is edited, an
interrupted apply resumed.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Listing budget cannot be met by prose trims alone | Med | Med | The emitter is `disable-model-invocation: true` (not counted); trim four descriptions under 1,024 first (frees about 1,300); keep the two new listed descriptions under 800; `when_to_use` unused; last resort is a shorter audit description, never `true` on realign (Q11) |
| A trimmed description drops a quoted trigger phrase | Med | High (auto-invocation regression, gate FAIL) | Trim prose only; run `check-changed-skills.sh origin/main` after each trim |
| `sed -i` and `grep -P` portability | Med | Med | Edits through a temp file and `mv`; `grep -E` only; `check-shell-portability.sh --paths` in Phase 1's sanity check onward |
| jq absent on a consumer | Low | Med | Already a docs-hygiene requirement; `setup check` reports it first |
| A personal layer swaps the regenerator the realign executes | Low | High | `generated` is team-layer only (policy-floor); an overlay declaring it is reported inert |
| The reproduction run diverges from PR #4097's edit set | Med | Med | Differences are evidence, not failures: hand-decided exclusions live in the concern file; a fresh-context verifier grades the set; a set difference routes to `/planning:plan review` |
| The fixture tree is large and brittle | Med | Low | One committed fixture under `scripts/fixtures/` reused by the suites through copy into mktemp; assertions on counts and named paths, never on whole-file diffs |
| `check-skill` line caps (200 soft, 500 hard) on four new bodies | Med | Low | Hub-and-spoke: recipes and tables in `context/` |
| The evals-quality lint rejects thin cases | Low | Low | Rich form with `name` plus `expectations`; `narration: true` where a case names fictional paths |
| main bumps docs-hygiene while the branch is open | High | Low | Resolve to main's version plus the minor at sync, entry above main's |
| Case-only rename behavior unobservable on this runner | High | Low | Recorded manual-verification gap; the new `test-windows` step runs `apply-rename.test.sh` on NTFS; macOS stays recorded as unverified |
| The emitted checker drifts from `scripts/check-docs-naming.sh` | Med | Low | Follow-up work item (filed at PR time): a drift test that renders the template with this repository's config and diffs it below the header |
| `audit-noise` classifies the new memory-tier artifact path as a ghost ref | Low | Low | Follow-up work item: a `docs-hygiene/` entry in the topic-docs concern-scoped root roster |

### Execution shape

Fully sequential: 1 gates 2 (every script reads the resolver), 2 gates 3 (the artifact shape), 3
gates 4 only through the shared pairing test and the resolved values, 5 needs everything. No two
phases are file-disjoint enough for a material parallel saving: Phases 2, 3, and 4 share the
plugin-level pairing test and the artifact contract document.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | schema and resolver decisions shape every later script |
| 2 | main-session | the form ladder and tier match need judgment against the PR's hand-decided cases |
| 3 | main-session | mutation logic and the gate contract; tightly coupled to Phase 2's artifact |
| 4 | main-session (sub-agent worker acceptable for the template rendering) | mechanical generalization of an existing script; a worker brief could carry it, cost not worth the hop |
| 5 | main-session, plus one fresh-context verifier for the reproduction set comparison | budget trims need trigger-phrase judgment; the reproduction verdict is not self-graded |

Sequential fallback: not applicable (no parallel wave recommended).

### Open questions

- None at approval time. The five maintainer questions are answered (Brief, Deferred questions).

### Handoff to implementation

#### User-approval gates

- The plan approval itself: pre-authorized by the maintainer's 2026-09-12 instruction ("approved";
  implement, PR, merge), recorded here; the maintainer can still revise before the PR leaves draft.
- `[FALLBACK, confirm or override]` Phase 5: if the reproduction run's edited-file set differs from
  PR #4097's sweep set after concern-file exclusions are applied, implementation stops and routes
  to `/planning:plan review` instead of widening the config to force a match.
- `[FALLBACK, confirm or override]` Phase 5: if the listing budget still exceeds 8000 after the four
  trims and lean new descriptions, implementation shortens the audit description further and
  reports the residual, never flips an invocation mode.

#### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential, all main-session (table above), one fresh-context verifier in Phase 5.
- [EXEC-SHAPE] Gate emission is its own `generate-file-name-gate` skill with
  `disable-model-invocation: true`, never a setup action, a realign stage, or an audit write: the
  setup contract scopes `apply` to the plugin's own configuration artifact, and the emitter's
  timing is the operator's.
- [EXEC-SHAPE] Explicit finding ids on the realign command line are the per-item acceptances
  (precedent: instruction-placement realign's `[finding-id ...]`); a bare run walks pending
  findings one at a time; `all` is refused. This is what makes the unattended reproduction run
  possible with 13 acceptances.
- [EXEC-SHAPE] The artifact home is `<memory_dir>/docs-hygiene/<branch-slug>/file-names.md`
  through a new `plugins/docs-hygiene/reference/topic-docs.md` binding (precedent:
  instruction-placement's plugin-named memory root); re-audits merge by old path.
- [EXEC-SHAPE] JSON concern file keyed under `file_names` so later docs-hygiene surfaces share the
  file; v1 bundles the `lower-kebab` transform only and accepts any `regex` for the check;
  `generated` is the one policy-floor key.
- [EXEC-SHAPE] Every script takes `--root`; edits go through a temp file written back with
  `cat` (inode and mode preserved); sed maps are generated by the script into mktemp, never
  written by the model through a heredoc; path lists match through git `:(glob)` pathspecs.
- [EXEC-SHAPE] Finding ids derive from the old path (`FN-<8 hex>`), so an id names the same rename
  across re-audits; word-shaped bare stems are `review`, never edited blind.
- [EXEC-SHAPE] The reproduction pin is `7eb1f628` (main's pre-rename tip), scoped to `docs/`.
- [EXEC-SHAPE] Commit boundaries follow Tidy First per phase: (1) config and setup, (2) audit,
  (3) realign, (4) emitter, (5) integration and trims, then the prune commit.
- [EXEC-SHAPE] The branch is `claude/naming-consistency-skill` off `main` after #4097 merges; the
  Brief and this plan move to `docs/topics/naming-consistency-skill/PLAN.md` there.

#### Mechanical work

- Each phase's Sanity Check block is the verification checkpoint; a red check stops the phase.
- Phase-boundary handoff notes through `/session-flow:handoff file phase-N`.
- Validation on the merged tree before the PR flips to ready: `scripts/affected-tests.sh --run`.

## Blast radius

MEDIUM by reach (one plugin, about 45 files, a new tracked concern file, two convention-doc rows),
LOW by reversibility (every change is a `git revert` away; no published API changes; the emitted
gate is only rendered into fixtures in this repository), and every consumer that could break is
under an existing CI gate (check-changed-skills, listing budget, changelog parity, pairing test,
em-dash, portability, orphaned fixtures). Triggers matched: "new skill creation that composes
other skills and has side effects" (realign mutates a tree and chains rename-references), so the
formal stress-test runs.

## Stress-test summary

**Fresh-context plan reviewer (Step 3):** 2 CRITICAL, 12 IMPORTANT, 9 SUGGESTION, all 23 verified
against the cited files and folded in above. The two CRITICAL: the whole-file blob-hash drift guard
would block every rename after the first because the renamed docs cite each other (replaced by an
old-path-exists plus per-site line re-verification guard, with sibling site remapping after each
apply, and a mutually-citing fixture case); the bundled regenerator command named a flag the
script does not have (Phase 1 now pre-flights the exact command and `setup check` resolves the
command's first word). The IMPORTANT set moved gate emission off `setup` (setup contract), added
`--root` everywhere (worktree reproduction; config-cascade anchors at `CLAUDE_PROJECT_DIR`),
dropped the head match, defined merge-by-old-path and a decline surface, made `generated`
team-layer only, added `setup` to the pairing test with unquoted invocations, fixed the
`check-skill.sh` invocation form, added the topic-docs Implementers row, the em-dash path
patterns, and the orphaned-fixture gate, and corrected the ADR number to 0034.

**Devil's-advocate (Step 4, deep, fresh context):** 1 CRITICAL, 5 HIGH, 7 MEDIUM, 6 LOW, all
evidence-cited and verified. CRITICAL (the same blob-guard flaw, with `MIGRATION-PLAYBOOK.md` citing
`PLUGIN-PHILOSOPHY.md` six times at the pre-rename tip as the concrete case): replaced as above, plus
`Status: applying` with resume semantics and zero-hit substitutions reported rather than silent.
HIGH: `c61ed529` is unreachable from `main` after the squash (pin moved to `7eb1f628`, scoped to
`docs/`, with a mode-change assertion); temp-file plus `mv` strips executable bits from eleven
scripts the sweep edits (write-back through `cat`, an executable fixture case); `\b` anchoring
corrupts `CATALOG-TAXONOMY` and would rewrite the prose line `UNSAFE CATALOG SOURCE` that PR #4097
left alone (anchored stem pattern, longest-first maps, `review` for word-shaped stems,
`sweep_exclude_sites`); the regenerator flag did not exist (Phase 1 pre-flight, resolvability
check, declared churn); the budget arithmetic did not close (a Phase 1 target table summing to
7,900, new descriptions at 600 to 700, the budget check in every phase from 2 on). MEDIUM: stable
ids and merge semantics, CRLF from native Windows jq (`tr -d '\r'` plus a stub test),
index-based existence checks and a `test-windows` step, policy-floor on `tiers`, `generated`,
`sweep_exclude`, `exempt_*` with layer provenance printed, the HEAD match dropped, ADR 0034. LOW:
em-dash and affected-tests coverage, the advisory trigger check read explicitly, a Bash 3.2 denylist
in the sanity blocks, cwd-based root and the detached slug, awk-rendered templates with `'` rejected
in `regex`, bookkeeping counts. Two follow-ups deferred to work items: the template drift test and
the topic-docs roster entry. No research-iterate loop was needed: every finding was settled by
repository evidence rather than a contested external claim; the one external point (git's
case-only `mv` on case-insensitive filesystems) rests on ADR 0034's source-code reading and is
covered by the new Windows step.
