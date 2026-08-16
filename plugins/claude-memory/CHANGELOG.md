# Changelog

All notable changes to the `claude-memory` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.1]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.9.0]

### Added

- **`lib/state-key.sh`** — the per-project state key for anything written under
  `${CLAUDE_PLUGIN_DATA}`. Prints `<repo-identity>/<worktree-discriminator>`, the scheme
  `claude-config:audit-pass` defines and `audit-prompting-postures` already uses, adopted here rather
  than reinvented. Byte-identical to the `claude-config` copy and registered in
  `scripts/cross-plugin-source-registry.txt`, so the two cannot drift apart silently. A remote URL
  becomes directory components in the resulting path, so an identity outside the accepted segment
  shape — a relative remote like `../central.git`, an absolute local path, a Windows path — is hashed
  rather than embedded; the suite asserts no `..` and no backslash survives into a key.

### Changed

- **`audit` no longer serves one project's findings as another's.** It wrote its report to a fixed
  `${CLAUDE_PLUGIN_DATA}/audit/last-audit.md` — machine-global, since that directory is keyed to the
  plugin identifier and nothing else — and then **read it back**: `report` mode served whatever the
  file held and `fix` mode acted on it. On a machine with two repositories, `report` in project B
  could present project A's findings as project B's, and `fix` could propose edits derived from
  another repository's memory layer. A wrong answer served, not merely a lost artifact — which is why
  an append-only history would not have closed it. All four sites now resolve one path,
  `audit/<state-key>/last-audit.md`: the write in `context/audit.md`, its restatement in
  `reference/criteria.md`, and the two reads in `SKILL.md` and `context/fix.md`. The path is derived
  once in `SKILL.md` and referred to by the spokes rather than restated, and the key comes from
  running the resolver, never from testing whether a placeholder is set.
- **A report that cannot be attributed to a project is no longer served or migrated.** The pre-rename
  `health/` layout and any unkeyed `audit/last-audit.md` carry no project segment, so nothing records
  which repository produced them, and adopting one into a project's key would invent that attribution.
  The previous behavior moved `health/` to `audit/` and read it. Both read paths now decline, name the
  leftover file's path as something the operator may delete, and offer a fresh audit. **This is a
  behavior change on upgrade**: an operator holding a report under the old layout is told to re-run
  rather than shown the old one.
- **`fix` mode states why an unattributable report is unusable input** rather than treating a missing
  report as the only failure case — it proposes edits to real instruction files, so acting on another
  repository's findings is the expensive error.
- **Two evals pin the property**, which had no coverage at all: two repositories neither share nor
  overwrite one report, and a legacy unkeyed report is neither served nor adopted. The
  `report-without-prior-audit` case now asserts the per-project derived path rather than "the most
  recent saved audit".

## [0.8.1]

### Changed

- **`scope-report.sh` now reports every managed-policy surface, not one JSON file.** Its
  hand-kept per-OS location list had fallen behind the settings doc: it never named the
  `managed-settings.d/` drop-in directory, and it folded the Windows registry policy keys into a
  parenthetical inside the file path. The locations now come from `lib/managed-scope.sh`, a
  shared library that `claude-config` carries a byte-identical copy of, so a location change
  lands once instead of per plugin. The report gains a `managed.d` row and one `not read` row per
  non-file surface (the `HKLM`/`HKCU` policy keys on Windows, the managed-preferences domain on
  macOS) — a presence report must not let an absent JSON file read as "no managed policy
  deployed". The Windows base path also now resolves through `%PROGRAMFILES%` rather than assuming
  the default location.

## [0.8.0]

The audit now covers two surfaces it never could before, which is why this is a minor.

### Fixed

- **`audit`: the user-global instruction surfaces were audited by nothing at all.** Step 1 discovery was
  two bare `find` commands rooted at the current directory — `find . -maxdepth 1 -name "CLAUDE.md"` and
  `find .claude/rules -name "*.md"` — so it could only ever see project scope. Meanwhile
  `claude-config`'s `audit-instructions` partitions memory-layer hygiene to this skill and names
  **`~/.claude/rules/`** explicitly in the handoff (`audit-instructions/reference/criteria.md:96`). One
  skill delegated a user-global surface by name; the receiving skill's discovery could not reach it. So
  `~/.claude/CLAUDE.md`, which loads in *every* session in *every* project, was checked by neither — and
  under-coverage reads as a clean report.

  Discovery now resolves `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` for both `CLAUDE.md` and `rules/*.md`,
  reusing the same config-root resolution the memory-dir resolver already carries rather than
  re-deriving it.

  *(Recorded because the originating report argued this from a different line —
  `reference/criteria.md:224`, the C9 carve-out for personal files. Read in context that line **excludes**
  personal files from C9 as "not repo-scoped", which cuts against the argument rather than for it. The
  seam above is the load-bearing mechanism, and it needs no interpretation.)*

### Added

- **`scripts/discover-instruction-surfaces.sh` + tests.** Discovery is a script now because the fix has
  a second half that inline `find` cannot carry: **every file is tagged with the scope it loads from.**
  Widening discovery without that would have traded under-coverage for a false positive — C9 is
  project-scoped and its own criteria row says to skip personal files, so an unscoped widening would fire
  C9 on `~/.claude/CLAUDE.md` and FAIL it for not stating a repo's build and test commands. Step 2 now
  routes on the emitted scope, and the R-checks apply at both scopes — an always-loaded user rule costs
  context in every session of every project, so they apply to it at least as strongly as to a project
  rule. 44 checks in the sibling `*.test.sh` style, including the Git Bash case where the config root is
  a Windows path with a drive letter.
- **A third scope value, `both`, for the two dotfiles layouts where one physical file is reachable by
  each layer.** A naive widening emits such a file twice under two path spellings: a duplicate finding,
  and a cross-scope comparison of a file against itself. Paths are now canonicalized and compared, and
  where they coincide the file is emitted once as `both`, which satisfies either `--scope` filter
  because the file really is reachable by each layer.

  **Each layout collides exactly one surface, which is why the two comparisons are computed
  independently rather than from one flag.** A repo rooted at `~` — the target shape the sibling
  `audit-pass` fix calls ordinary — makes `.claude/rules` and `~/.claude/rules` the same **directory**,
  while its two `CLAUDE.md` files stay distinct. A repo rooted at `~/.claude` itself makes the depth-1
  `CLAUDE.md` and `~/.claude/CLAUDE.md` the same **file**, while its rules dirs stay distinct — project
  rules there resolve to `~/.claude/.claude/rules`, not `~/.claude/rules`. Cases pin the asymmetry in
  both directions.
- **Path-scoped rules are not assumed loaded.** A user rule carrying `paths:` frontmatter is absent until
  a matching file is read, so a repo-relative currency or redundancy finding against one is valid only
  where its `paths:` can match in *this* project. Step 2 and the Step 3 comparison both say to establish
  co-residency first rather than treating every discovered user rule as live here.
- **R1 says which `CLAUDE.md` it compares against.** "Does this rule duplicate content already in
  CLAUDE.md?" was unambiguous while only one could ever be in scope; with two it was not. R1 now pairs
  within a scope — a user rule against the user `CLAUDE.md`, a project rule against the project one —
  because R1 is a redundancy the owner of that layer fixes by deleting one of the two, and only a
  same-scope pair is theirs to fix. Cross-scope overlap is real and belongs to the Step 3 pass, which
  reports it against the pair and names each side's scope; routing it through R1 as well would report
  one overlap twice and address it to the wrong person. A `both`-scoped rule is the one case with no
  same-scope partner — it arises only in the `~`-rooted layout, where the two `CLAUDE.md` files stay
  distinct — so it compares against each `CLAUDE.md` in scope, attributing every finding to the scope of
  the one it overlapped.
- **Step 3 gains a cross-scope consistency pass.** Both layers load together, so a user instruction that
  contradicts a project one is a live conflict rather than a layering choice, and one the project already
  states is redundant context on every run. The report names which scope each side came from, because the
  resolution differs — only one of the two is yours to edit on behalf of the repo.

## [0.7.1]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `skills/stateless/reference/official-guidance.md` — all seven block quotes from the settings
    and `.claude` directory references (settings precedence ladder and its managed-tier override
    bullet, the `env` description, `cleanupPeriodDays`, the not-automatically-cleaned table
    heading, the `sessions/` sweep exclusion, the `claude project purge` deletion list, its
    `shell-snapshots/`/`backups/` carve-out, and its confirmation prompt) matched the live pages
    word for word. The file's own negative — that no settings-precedence exception bullet names
    `autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, or auto memory — was re-checked
    against the complete bullet list and still holds, as does its note that the `v2.1.124+` floor
    for `claude project purge` has no current upstream source. Every dated citation in the file
    moved: the seven block quotes, the settings negative, the `env`-block quote (whose stamp wraps
    across two lines), and the `cli-reference` observation that `claude project purge` now carries
    no version requirement at all.
  - `skills/audit/reference/official-guidance.md` — the memory reference re-verification date.

## [0.7.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.6.0]

### Fixed

- **A single heavy pseudo-frontmatter line silently blanked the `audit` skill's M1 index-size byte
  count** (claude-memory 0.5.9 → 0.6.0, criteria 1.5.2 → 1.5.3). `memory-dir-stats.sh` bounded its
  frontmatter block by grammar and by line count but never by weight, and markdown prose opening
  `Note:` or `Important:` is a well-formed `key:` mapping entry. A `MEMORY.md` opening with a `---`
  thematic break, carrying one long paragraph, and reaching any later `---` had that paragraph
  stripped however much it weighed: a 26,020-byte index reported 5 loaded bytes. M1 is a
  `[FAIL]`-severity size gate and a low count always passes it, so the shape disarmed the gate's
  25KB limb outright — the same disarming the line cap already prevented on the 200-line limb. The
  block is now bounded a third way, by `fmbytecap` bytes of held content, and that index reports
  its full 26,020 bytes.

  The cap is 1KB. It is calibrated against what real frontmatter weighs, not against the 25KB
  limit: Claude Code stamps only a `modified` scalar, and even a hand-written block of twenty
  entries runs to a few hundred bytes, so 1KB clears every real shape by a wide margin and a block
  under it still strips whole. Like the two bounds it joins, it leaves a residue — a misparsed
  block still strips up to the cap before the bound ends it — and 1KB of 25KB is the smaller share
  of M1's two limits, against the line cap's 20 of 200. Both directions stay the ones M1's
  readings already guess toward: an over-count can only make the gate fire early, while the
  under-count it replaces stopped it firing at all. criteria.md M1 reading 1 records the bound.

## [0.5.9]

### Fixed

- **Attributed blockquotes in `stateless`'s `reference/official-guidance.md` carried text the
  cited pages do not say** (claude-memory 0.5.8 → 0.5.9). The settings-page precedence quote
  substituted a bare `(…)` for item 1's parenthetical, so an ellipsis inside quote marks stood
  where real page words belong; it now reads `(server-managed, MDM/OS-level policies, or managed
  settings)`, with the attribution note recording that the three links are flattened to their
  labels and that each item's nested detail bullets are omitted. Two harder defects surfaced in
  the same pass. The `"Cannot be overridden by any other level, including command line
  arguments"` quote truncated mid-sentence, dropping `, apart from the exceptions in the bullets
  below` and inverting a qualified claim into an absolute one; the full sentence is restored, and
  new prose carries the conclusion the skill needs as a verified negative — item 1's exception
  bullets name auto memory nowhere — instead of an enumeration this file would have to keep in
  sync. Review narrowed that conclusion to settings scopes only: `CLAUDE_CODE_DISABLE_AUTO_MEMORY`
  as an OS environment variable sits outside settings precedence and still overrides the effective
  value even against a managed `autoMemoryEnabled`, as the file's env-var precedence section
  already states. The `claude project purge` quote asserted `"The command requires Claude Code
  v2.1.124 or later"`, a sentence claude-directory no longer carries and cli-reference never did;
  it is out of the quote, and the retained `v2.1.124+` floor the plugin states elsewhere is
  labelled a claim with no current upstream source rather than left looking doc-backed. Review
  extended that reconciliation within the reference file itself: its second, unlabelled `v2.1.124+`
  mention now defers to the labelled statement instead of restating the floor as doc-backed fact,
  and the cli-reference negative carries its own citation — the page is in the file's Sources list
  and documents `claude project purge` with no version requirement (verified 2026-08-08).

  The `env` and `cleanupPeriodDays` quotes were re-checked character-for-character against the
  live page and are verbatim as they stand, so their wording is untouched. What changed around
  `cleanupPeriodDays` is the reading: its `"session files and other application data"` sat under
  prose stating `sessions/` is not age-swept, close enough to read as contradicting it. New prose
  resolves the phrase against the table it links to — transcripts, `shell-snapshots/`, `debug/`,
  `tasks/`, `file-history/` — and states that `sessions/` is not a row in it, which is what the
  quote two paragraphs down already said. Every settings and claude-directory verification stamp
  in the file moves to 2026-08-08, the date each quote was re-checked.

## [0.5.8]

### Fixed

- **The `audit` workflow told the model to be mechanical on every check, contradicting the skill's
  own determinism contract.** "Be mechanical, not interpretive" sat unscoped at the end of the
  generic per-check loop, but only C1/M1/M2/RD1 are the deterministic spine; C2-C9, R1-R4, and
  M3-M4 are a judgment tier that requires reading and interpreting content by design. The
  instruction is now scoped to the spine, and the judgment tier is told to apply its fixed criteria
  consistently rather than to skip the judgment.

### Changed

- **`stateless`' disable workflow says why the scope gate exists** — applying the wrong scope
  silently changes memory behavior for the wrong audience (machine-wide vs. this repo) — instead of
  stating the stop as a bare prohibition.

## [0.5.7]

### Fixed

- **A pseudo-frontmatter block of markdown headings silently blanked the `audit` skill's M1
  index-size count** (claude-memory 0.5.6 → 0.5.7, criteria 1.5.1 → 1.5.2). `memory-dir-stats.sh`
  admitted `#` lines to its frontmatter grammar, so a `MEMORY.md` opening with a `---` thematic
  break, carrying up to twenty heading lines, and reaching any later `---` had the whole span
  stripped as frontmatter: a five-line index reported one loaded line. M1 is a `[FAIL]`-severity
  size gate that a low count always passes, so the shape disarmed the gate outright. A `#` line is
  a comment to YAML but a heading to markdown, and headings are loaded content, so the grammar now
  accepts only blank lines and `key:` mapping entries and that shape counts every line.

  The cost is that a real YAML comment inside frontmatter ends the block, and ending it strips
  nothing at all — the opening `---`, every entry held so far, and the rest of the block through
  its close all count. That is an over-count, the direction M1's readings already guess toward,
  and it takes a hand-edited index to reach, since Claude Code only stamps a `modified` scalar
  into frontmatter a file already has. Comments join an existing class rather than opening a new
  one: frontmatter this grammar cannot parse already ended the block before this change, and a
  block sequence under `tags:` still does. criteria.md M1 reading 1 records both halves.

## [0.5.6]

### Changed

- **`stateless`'s purge scope boundary now points at the official full wipe** (claude-memory
  0.5.5 → 0.5.6). Wherever the skill states that purge is auto-memory-only — the SKILL.md scope
  statement and table, `context/purge.md`'s pre-gate presentation and follow-through, and
  `reference/official-guidance.md`'s out-of-scope section — it now names `claude project purge`
  (Claude Code v2.1.124+). The command's scope — what it deletes, what it leaves alone, and that
  it confirms first — is quoted verbatim in `reference/official-guidance.md` and nowhere else, so
  the skill holds one copy of an upstream list instead of one per call site; every other mention
  points there, and code.claude.com/docs/en/claude-directory stays the source for the deletion
  plan and flags.
  Also retires the reference file's now-false "there is no built-in purge command" claim.

### Fixed

- **The `stateless` scope table answered for four entities with one verdict, and was wrong for
  two of them.** A single `Transcripts / history / sessions / snapshots` row claimed
  `cleanupPeriodDays` auto-cleans all four. Per code.claude.com/docs/en/claude-directory
  (verified 2026-08-04) it auto-cleans transcripts and shell snapshots, but not the other two:
  `history.jsonl` sits among the paths "not covered by automatic cleanup" that "persist
  indefinitely", and `sessions/` "isn't part of the age-based sweep", being cleared when each
  session exits. The row also gave one location for all four and said nothing about
  `claude project purge`, whose scope cuts across it and lands differently on each of the four
  (quoted in `reference/official-guidance.md`). Now four rows,
  each carrying its own path, sweep behavior, and purge behavior, so every verdict is true of
  every subject in its row. The same correction applies to `reference/official-guidance.md`'s
  out-of-scope section, which stated the sweep for all four as one fact. Also retires two
  counted re-fetch pointers ("the two source pages", "both pages") that the file family had
  grown past — they now point at the source list rather than counting it.

- **Three `stateless` reference quotes attributed to the settings doc were paraphrase, not
  quotation.** `reference/official-guidance.md` presents block quotes as verbatim, but its
  settings-precedence list, `env` description, and `cleanupPeriodDays` description used wording
  absent from code.claude.com/docs/en/settings — the precedence list invented every item label
  ("Local" for "Local project settings", "Project" for "Shared project settings") and the
  bracketing "(highest priority)" / "lowest priority", the `env` description was a rewrite, and
  the `cleanupPeriodDays` one stitched invented wording around real fragments with ellipses. The
  substance was right in all three cases; only the fidelity was wrong, which is
  the defect that matters in a file whose contract is verbatim quotation. All three now carry the
  page's own words, verified 2026-08-05, with the precedence list quoted as the structured list it
  is and its omissions marked. Managed settings' "cannot be overridden" property, previously
  stitched into the precedence quote, is now quoted from the nested bullet that states it.

- **The instruction-layer row claimed a user scope `CLAUDE.local.md` does not have.** One
  `CLAUDE.md / CLAUDE.local.md / .claude/rules/` row gave the location as `repo + user`, true
  of `CLAUDE.md` (`~/.claude/CLAUDE.md`) and of `.claude/rules/` (`~/.claude/rules/`, which
  code.claude.com/docs/en/memory calls "Personal rules ... apply to every project on your
  machine") but not of `CLAUDE.local.md`, which that page scopes to "Just you (current
  project)" with no user-scope equivalent. Split so the location is true of its own subject.

## [0.5.5]

### Fixed

- **Re-align auto-memory and CLAUDE.md reference facts with the live memory doc**
  (claude-memory 0.5.4 → 0.5.5; criteria 1.5.0 → 1.5.1), verified against
  code.claude.com/docs/en/memory on 2026-08-04. Two drifted facts in
  `audit`'s `reference/official-guidance.md` corrected: `@import` recursion depth is 4 hops, not 5;
  and `autoMemoryDirectory` is read from any settings scope (user, project, local, policy,
  `--settings`) with project/local values gated behind the workspace trust dialog — the prior claim
  that project settings are not accepted no longer matches the docs. M1's measurement now mirrors
  the documented limit check: YAML frontmatter and block-level HTML comments are stripped before
  the MEMORY.md index loads, so they don't count toward the 200-line/25KB limits (backing quote
  added to `official-guidance.md`). The deterministic spine follows the same rule:
  `memory-dir-stats.sh --memory-lines` now measures post-strip content instead of raw `wc -l`, a
  new `--memory-bytes` mode covers the 25KB limb, and the SKILL.md pre-computed context reports
  both figures so M1 never disagrees with its own injected stats. Also: the `audit` SKILL.md scope
  table states the 25KB limb of the MEMORY.md load limit alongside the 200-line one, and a quote
  attribution names the page's current "Set up a project CLAUDE.md" section (formerly
  "Project memory"). The strip counts an unterminated block as content rather than swallowing the
  rest of the file: a leading thematic break or frontmatter clipped mid-file previously reported
  zero, and since M1 is a `[FAIL]`-severity size gate that zero always passes, the gate could not
  fire. A fenced block inside a comment no longer toggles fence state, and text sharing a line with
  a comment's open or close is counted as the loaded content it is. `criteria.md` M1 now records
  the four readings the strip applies and marks them as this plugin's reading, not doc-derived —
  the memory doc states the fenced-code carve-out for CLAUDE.md only and is silent on it for
  MEMORY.md.

## [0.5.4]

### Changed

- **`audit`'s C2 deletion test now runs per line, as the official docs state it** (claude-memory
  0.5.3 → 0.5.4; criteria 1.4.0 → 1.5.0). The check evaluated whole H1/H2 sections — "Would Claude
  make mistakes without this section?" — but the source it quotes tests each line: "For each line,
  ask: 'Would removing this cause Claude to make mistakes?' If not, cut it." A section-level pass
  let keep-worthy lines shield surplus neighbors in the same section. Sections remain as the
  report's grouping unit only: findings are per line, and a section whose every line flags
  collapses into one section-level finding. `context/fix.md`'s C2 fix pattern follows.

### Added

- **`audit`'s C1 carries the official symptom-first diagnostic for over-long files.** C1's
  rationale already stated the causal claim (long files reduce adherence); it now also codifies the
  reverse tell as detect guidance — "If Claude keeps doing something you don't want despite having
  a rule against it, the file is probably too long and the rule is getting lost" — so an audit
  prompted by a rule being ignored cites the tell and reports the length finding even below the
  WARN threshold. The sourced quote lands in `reference/official-guidance.md` per the determinism
  contract.

## [0.5.3]

### Added

- **`audit` gains C9, a check that a project CLAUDE.md states the repo's exact build and test
  commands** (claude-memory 0.5.2 → 0.5.3; criteria 1.3.0 → 1.4.0). It is the only CLAUDE.md check
  that looks for *missing* content — C4 asks whether an instruction that exists is concrete enough
  to verify, C5 whether it should have been cut, and neither asks whether the commands are there at
  all. Official memory guidance lists build and test commands first among what project memory is
  for, and `/init` populates them by analyzing the codebase, so without the statement they are
  inferred every session rather than read. Two severities, following C6 and C7's pattern of heading
  a check at its higher branch: FAIL for a stated command the repo's own manifest does not have,
  which is C7's wrong-reference class and worse than an absent one (Claude runs it and the check
  fails for the wrong reason); WARN for a command that is absent or given only as prose naming the
  tool ("we use pytest" is not a command). Never flags a repo that genuinely has no build or test
  step. Scoped to project CLAUDE.md — skipped for CLAUDE.local.md and personal files, which are not
  repo-scoped.

  **A step 0 keeps the check honest against its own source.** The memory page states both halves of
  a tension: project memory is for "build and test commands", while the same page's
  CLAUDE.md-vs-auto-memory table puts "Build commands" in the *auto memory* column. So the check
  asks first whether the commands are stated on any loaded surface — nested CLAUDE.md, path-scoped
  rule, or auto memory — and treats a yes as a C3 placement question rather than a C9 finding. The
  requirement is that the commands be reachable, not that they sit in one file. Without this, C9
  would flag a repo for following the other half of the page it cites.

  Boundary with C7 stated explicitly so a run does not double-report: C7 owns file paths, version
  pins, and counts; C9 owns whether the command itself runs. Backed by a new "Build and test
  commands" section in `reference/official-guidance.md` carrying the sourced quotes the skill's own
  determinism contract requires, and by a new eval covering the wrong-command FAIL, the step-0
  carve-out, and the no-double-report rule.
  The applicability ranges in `SKILL.md` and `context/audit.md` move to C9 accordingly.

## [0.5.2]

### Fixed

- **The `audit` skill no longer fails to load when invoked from a worktree-isolated agent.** Two
  `## Pre-computed context` lines resolved the memory dir inline — `d=$(… resolve-memory-dir.sh);
  ls "$d"/*.md …` — and the harness composes that block into one shell invocation whose
  worktree-isolation guard refuses any `$` expansion, so the whole skill was refused rather than
  merely reporting `0`. Both lines now call a bundled `memory-dir-stats.sh` (`--md-count` /
  `--memory-lines`) through the harness-substituted `${CLAUDE_PLUGIN_ROOT}`, leaving the pre-compute
  command free of every expansion the guard rejects; the script still resolves the memory dir via
  the single-source-of-truth `resolve-memory-dir.sh`, reports `0` on every failure path the old
  fallback covered, and now also survives BSD `wc` padding. Refs #1687.

## [0.5.1]

### Fixed

- **The shared concern-value parser no longer reads a declared key as absent over YAML key spacing.**
  `parse-concern-value.sh` anchored on the exact regex `^<key>:`, so `memory_dir : .work` (YAML
  permits whitespace before the `:`) and a root block mapping written at a uniform indent both
  resolved to the caller's fallback — substituting a value the repo never chose for one it did.
  Both shapes now resolve, matched at the document's own base indentation so a same-named key
  nested under another mapping never answers for the root one — including when the root key is
  present but deliberately empty. Synced from `lib/parse-concern-value.sh`; version bumped so installed
  copies receive it.

## [0.5.0]

### Fixed

- **The C3 placement eval no longer rewards moving an unspecified remainder.** Its prompt left the
  other half of the 300-line `CLAUDE.md` unstated, so removing the running log alone already brought
  the file under the line budget — and if that remainder were always-on project conventions, C3 says
  they belong in `CLAUDE.md`. The expectation nevertheless demanded a skill or path-scoped rule for
  it, rewarding a move that can make required instructions unavailable after compaction. The prompt
  now says what the remainder is (a Terraform walkthrough relevant only under `infra/`), and the
  expectation requires the destination to be justified by relevance rather than by the budget.
- **`reference/official-guidance.md` no longer claims Claude Code loads `AGENTS.md`.** The
  "Compaction by steering method" table carried a `CLAUDE.md / AGENTS.md` row, but the memory doc's
  own `AGENTS.md` section states "Claude Code reads `CLAUDE.md`, not `AGENTS.md`" and prescribes an
  `@AGENTS.md` import or a symlink as the way to make one load
  (<https://code.claude.com/docs/en/memory>). The row is now `CLAUDE.md` alone, with its nested-file
  on-demand reload spelled out, and a following note records how an `AGENTS.md` actually reaches
  context. Left as written, the snapshot contradicted the sibling `claude-config` catalog, which
  excludes `AGENTS.md` from its comparison set on the doc's authority.

### Changed

- **`audit` check C3 (Content Placement): three gaps closed in one revision.** The routing table
  answers one question, so these land as one edit rather than three checks that would emit three
  findings on one misplaced section. (1) **Auto memory becomes a destination** — the plugin audits it
  as a first-class entity in M1–M4 but never routed content to it, so the destination set predated
  auto memory; the row states that Claude writes it and that asking Claude to remember something
  lands there rather than in CLAUDE.md — gated on the destination's effective enabled state, because a
  disabled auto memory neither loads nor accepts writes, so an ungated recommendation to move
  accumulated learnings out of CLAUDE.md would delete them from every future session rather than
  relocate them. The gate reuses the resolver the sibling `stateless` skill already owns instead of
  reading one scope: `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is authoritative wherever set (`1` off, `0` on
  even against `autoMemoryEnabled: false`), and settings precedence decides `autoMemoryEnabled` only
  when the variable is unset.
  (2) **`@path` imports are named as a non-destination** —
  imported files load at launch, so a split into imports reorganizes and saves nothing, and the same
  holds for an import inside a path-scoped rule, where the rule's own body defers and the imported
  file does not — carried as an explicitly provenance-marked empirical extension (first-party repro
  on Claude Code 2.1.219) so the `update` action cannot overwrite it with doc-sourced text.
  `reference/official-guidance.md` already recorded the launch-load behavior and no check cited it. (3) **Every move recommendation now prices the destination** against the "Compaction by
  steering method" table that same reference file ships and no check cited — path-scoped rules and
  nested CLAUDE.md return only when a matching file is read again, so a rule that must persist across
  compaction stays unscoped or in root CLAUDE.md. Pricing extends past compaction to the skill
  destination the routing table already recommended: a **new** skill defers its body but adds a
  listing entry — `name` plus the combined `description` and `when_to_use`, truncated at 1,536
  characters — that is always in context, so part of the cost moves into the always-loaded tier
  instead of out of it. A move into a skill that already exists adds no entry and is not charged.
  `disable-model-invocation: true` is the only field that keeps a description out of context, and it
  makes the skill user-invocable only; `skillOverrides` does not reach plugin skills. Catalog
  version 1.3.0.

## [0.4.1]

### Fixed

- **`audit` reference: the path-scoping status claim was false.** `reference/official-guidance.md`
  asserted (dated 2026-04-01) that `.claude/rules/` files "load unconditionally at session start
  regardless of `paths:` frontmatter", citing four open issues. A first-party repro on Claude Code
  2.1.219 disproved it: a rule scoped `paths: ["**/*.tsx"]` was absent at session start, present
  after reading a matching `.tsx` file, and absent again after reading a non-matching one — deferral
  works in both directions. The cited evidence failed independently too: two of the four issues are
  closed NOT_PLANNED and never supported the claim (#38487 asks that Write/Edit *also* trigger
  injection, which presupposes deferral works; #32906 is a docs issue about subagents), and the two
  still open assert opposite failure modes. The passage now states path scoping as verified working
  on 2.1.219 as of 2026-07-24, with no version floor claimed since no changelog entry or maintainer
  comment pins when it changed, and keeps the caveats that do survive: an `@import` inside a
  path-scoped rule still inlines at session start and defeats the rule; path-scoped content is
  invisible to subagents, teammates, and skill-forked contexts (#32906, closed NOT_PLANNED —
  accepted behavior); a new-file Write does not trigger the rule; and before v2.1.211 on-demand
  rules loaded even when `project` was excluded from `--setting-sources`.

## [0.4.0]

### Added

- **`stateless`: machine-wide mode (`status all` / `purge all`).** The skill's name and
  description invite "am I stateless everywhere on this machine?", but every action was
  single-project — a machine-wide audit had to hand-roll a loop over
  `~/.claude/projects/*/memory/`. New `scripts/enumerate-all-projects.sh` lists every
  per-project store under `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/` with MEMORY.md line
  counts and topic-file counts (enumeration-only, never exits non-zero on absence, reusable
  by the sibling `audit` skill; ships with its own test script). `status all` appends the
  machine-wide table to the posture report, with explicit caveats that per-repo settings
  overrides and relocated `autoMemoryDirectory` stores are not visible from enumeration
  alone. `purge all` runs the same manifest → gate → optional-backup → delete flow with
  every per-project store as the candidate set, one combined manifest, and ONE combined
  confirmation gate stating the machine-wide total and every directory with per-dir counts;
  the backup offer covers the whole manifest with per-dir sibling snapshots. (#981)

## [0.3.5]

### Changed

- **`stateless` disable: dotfile-manager backfill detection beyond chezmoi.** Step 3 claimed
  to be repo-agnostic but only checked chezmoi, with a hand-wave to "check any other dotfile
  manager". It now carries concrete detectors for chezmoi (managed-output check — the previous
  bare `&&` chain reported TRACKED whenever the binary existed), yadm
  (`ls-files --error-unmatch`), and GNU stow / symlink managers (settings file is a symlink,
  or its parent dir is — the stow tree-folded layout), plus a fingerprint fallback
  (`.chezmoiroot`, `~/.local/share/chezmoi`, `~/.local/share/yadm`, `.stow-global-ignore`,
  `~/.dotbot`) that reports "manager fingerprint
  present but unconfirmed" instead of silently concluding the file is unmanaged when a
  manager's artifacts exist without its binary on PATH. Backfill routing now names each
  manager's own flow and warns against any `apply`/`restow` from the live session. (#980)

## [0.3.4]

### Added

- **`stateless` purge: opt-in backup-before-purge escape hatch.** The confirmation gate now
  offers to snapshot the manifest's exact files to a sibling `<memory_dir>.bak-<UTC>/`
  directory before deleting ("yes, with backup"). The copy follows the same
  manifest-exact/no-re-glob discipline as the delete, verifies the copy count before any
  deletion, and Step 5 reports the snapshot path. (#979)

### Changed

- **`stateless` purge: bundled-consent does not satisfy the confirmation gate.** Step 3 now
  states explicitly that consent gathered earlier via a bundled or multi-option answer — an
  upstream `/interview` round, a numbered menu selection whose option happened to include the
  purge, or a "purge" given before the manifest was known — does not satisfy the gate; it must
  restate the concrete now-known scope (file count, directories) and receive a fresh,
  scope-referencing confirmation. A worked anti-pattern example is included. (#979)

## [0.3.3]

### Fixed

- **Non-repo memory-dir resolution implemented (the documented fallback).** The shared
  `resolve-memory-dir.sh` hard-required a git repo (`exit 1` when `git rev-parse --show-toplevel`
  was empty) and the `stateless` skill's `scope-report.sh` pre-emptied it with a bail-out telling
  the user to run from within a repo — but the official memory doc (re-verified 2026-07-22)
  says "Outside a git repo, the project root is used instead", so a non-repo directory is a
  fully valid case with a real memory store the skill could neither find nor report. The
  resolver now derives the project slug from the current directory (same Windows-form
  normalization as the repo-root path) when no repo is found, `scope-report.sh` calls it
  unconditionally (with an informational note that the cwd is the project key), and the
  regression test that had locked the bail-out in as a spec now asserts the resolved
  cwd-derived path. The `audit` skill's deterministic M2 checker
  (`memory-index-refs-check.sh`) carried its own now-redundant git-repo guard that would have
  kept the audit from checking a non-repo store's index integrity — the guard is removed
  (the shared resolver owns the non-repo case) with a non-repo regression test added. (#978)

## [0.3.2]

### Added

- **`audit` skill: reciprocal scope-boundary note.** Model-era instruction-content findings
  (prior-model workarounds, over-prescriptive scaffolding, bare prohibitions, reasoning-echo
  directives, stale example scaffolding) now route to the `claude-config` plugin's
  `audit-instructions` skill when that plugin is installed; absent it, such observations stay
  in the audit report criteria-free rather than being judged against this checklist or
  silently dropped. Completes the partition that skill declared toward this one.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- **New `stateless` skill (`/claude-memory:stateless`)** for inspecting and disabling Claude
  Code auto memory — the notes Claude writes for itself per repo under
  `~/.claude/projects/<project>/memory/` (relocatable via `autoMemoryDirectory`). Actions:
  `status` (default, read-only — effective on/off state and store contents across all settings
  scopes), `disable` (sets `autoMemoryEnabled: false` and `CLAUDE_CODE_DISABLE_AUTO_MEMORY` in a
  confirmed scope, and flags a dotfile-manager backfill for a tracked `settings.json`), and
  `purge` (destructive — reads `autoMemoryDirectory` at every scope, shows a deletion manifest,
  and deletes auto-memory `*.md` files only after explicit confirmation). Scope is auto-memory
  only; the instruction layer stays with `audit`, and transcripts/history are out of scope
  (auto-cleaned by `cleanupPeriodDays`). Claude Desktop / claude.ai account memory is a
  server-side store the skill gives direction for rather than deleting locally. Per the
  env-vars doc, `CLAUDE_CODE_DISABLE_AUTO_MEMORY` overrides `autoMemoryEnabled` (the env var is
  authoritative when set); `disable` writes the env var (`1`) plus `autoMemoryEnabled: false`,
  and `status` treats a set env var as authoritative. The bundled `scope-report.sh` reuses the
  plugin's single-source memory-dir resolver rather than re-deriving the path.

### Fixed

- **`resolve-memory-dir.sh` now honors `CLAUDE_CONFIG_DIR`.** The shared resolver (used by both
  the `audit` and `stateless` skills) resolved the config root as `$HOME/.claude`, so a machine
  that relocates its Claude Code config via `CLAUDE_CONFIG_DIR` had its memory directory resolved
  to the wrong path. It now uses `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, per the official
  `.claude-directory` doc, so the relocated `projects/<project>/memory/` tree resolves correctly.

## [0.2.3]

### Fixed

- **`orphan-rule-check` no longer truncates a quoted `memory_dir` at an interior `#`.**
  Seam resolution now routes through the shared `parse-concern-value.sh` helper
  (materialized from `lib/parse-concern-value.sh`), which resolves surrounding quotes
  *before* stripping comments: `memory_dir: ".scratch#dir"` keeps its `#` and the correct
  tier is excluded from the reference search, rather than collapsing to `.scratch` and
  masking an orphan rule. The naive `${seam%%#*}`-first strip is gone; an unquoted
  whitespace-preceded trailing `# comment`, surrounding whitespace, and trailing-slash
  handling are unchanged. As a
  non-interactive detector it still degrades to the documented `.work` default when the
  seam is unset — the contract's inferred/interactive rungs stay the calling skill's job.
- **A comment-only `memory_dir` now resolves to the fallback, not a literal directory.**
  `memory_dir: # use default` is YAML-null; the parser previously kept `# use default`
  as the value (its comment strip only fired on a whitespace-*preceded* `#`), so the
  detector searched `# use default/` and stopped excluding the default `.work/` tier —
  letting a `.work` reference mask an orphan. A `#` that starts the unquoted value is now
  treated as a comment, so resolution falls through to the caller's fallback / documented
  default.

## [0.2.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.1]

### Fixed

- **`orphan-rule-check` now resolves the excluded memory tier from the topic-docs seam**
  instead of hardcoding `.work/`. The reference search reads `memory_dir` from
  `.claude/topic-docs.yaml` (falling back to `.work/` when unset) and excludes that path,
  so a consumer that overrides `memory_dir` no longer has its real memory tier scanned —
  ephemeral files there can no longer register false references that mask an orphan rule.

## [0.2.0]

### Changed

- **BREAKING — the `health` skill renamed to `audit`** (fleet conformance wave, naming grammar):
  `/claude-memory:health` → `/claude-memory:audit`. The old invocation stops resolving; update any
  saved references. Actions (`audit` / `fix` / `update` / `report`) are unchanged.

## [0.1.0]

### Added

- Initial release. The `health` skill was extracted from the `claude-config-audit` plugin — where it
  shipped as the `memory-health` skill — into this standalone plugin, invoked as `/claude-memory:health`.
  It audits the Claude Code instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`,
  and auto-memory) against a checklist derived from official Claude Code documentation, with a
  deterministic script-backed spine (MEMORY.md index integrity, orphan always-loaded rules) and
  `audit` / `fix` / `update` / `report` actions. Audit reports stay contributor-local in the plugin's
  data directory.
