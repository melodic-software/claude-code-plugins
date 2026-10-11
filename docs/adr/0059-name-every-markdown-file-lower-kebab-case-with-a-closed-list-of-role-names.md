# Name every markdown file in lower-kebab-case, with a closed list of role names

- Status: accepted; amended 2026-10-11 (the docs-naming configuration carries the whole scope,
  see the amendment below)
- Date: 2026-10-10
- Extends: [ADR 0034](0034-name-docs-files-lower-kebab-case-with-conventional-exceptions.md)

## Context

[ADR 0034](0034-name-docs-files-lower-kebab-case-with-conventional-exceptions.md) put every file
under `docs/` on one lower-kebab-case rule with three exempt names, and
`scripts/check-docs-naming.sh` enforces it. Outside `docs/` nothing did. Of the 2,705 tracked
markdown files, the ones outside `docs/` carried 35 distinct basenames that fail the rule. Most were
names something looks up by exact spelling (`SKILL.md`, `README.md`, `AGENTS.md`). Seven files
were not: `UPSTREAM.md`, four `NOT_IMPLEMENTED.md` stubs, `DEFERRED.md`, and `TEMPLATE.md`, each
cited by its own spelling and by nothing else. The rest sat in test fixtures, eval workspaces, and
vendored copies, where the name belongs to the case being reproduced.

The question ADR 0034 answered for `docs/` is the same question everywhere: a reader citing a
file should not have to remember which spelling that one file uses.

## Decision

**Every tracked `.md` file in the repository is named in lower-kebab-case**, by ADR 0034's regex,
`^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$`. The `docs/` rule is unchanged: every file there, of any
extension, stays in scope, and code files there stay exempt by extension.

**One closed list of uppercase role names is exempt, anywhere in scope**, `docs/` included. A name
is on the list because a tool, a forge, or a skill looks it up by that exact spelling:

| Name | Exact-name lookup |
|---|---|
| `README.md`, `CHANGELOG.md`, `INDEX.md` | ADR 0034's three, unchanged |
| `LICENSE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` | GitHub's community health files, recognized by name ([GitHub Docs](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)) |
| `CLAUDE.md` | Claude Code's memory file, loaded by name ([Claude Code memory docs](https://code.claude.com/docs/en/memory)) |
| `AGENTS.md` | imported by `CLAUDE.md` (`@AGENTS.md`), and every nested one is a row in the root `AGENTS.md` "Conventions that load on demand" table |
| `SKILL.md` | the file Claude Code reads as a skill's entry point ([Claude Code skills docs](https://code.claude.com/docs/en/skills)); 367 tracked |
| `REVIEW.md` | synced by name from `melodic-software/standards` (`.github/workflows/pr-check-managed-files-hosted.yml`) and cited by the root `AGENTS.md` "Code Review Rules" |
| `CONTRACT.md` | the work-items tracker adapter contract, cited by section from the tracker's scripts and tests (`plugins/work-items/tools/work-item-tracker/work-item-tracker.test.sh`), 93 references |
| `STYLE.md` | the per-style file `/animation:learn-style` writes and names in its file table (`plugins/animation/skills/learn-style/SKILL.md`) |
| `TODO.md` | the machine-health proposals file, named as a one-time migration source in `plugins/machine-health/skills/audit/catalog/schemas/approvals.schema.json` (`migration`, "Removed in next major version"); leaves the list when that migration does |
| `PLAN.md` | the plan artifact `/planning:plan` persists to `<memory_dir>/<topic-slug>/PLAN.md` and checks with `check-plan-outcome.sh`, and the file `/performance:goal` writes its goal into; the tracked `plugins/guardrails/reference/edit-write-guards/PLAN.md` is such a goal record |

A name joins the list only with evidence of an exact-name lookup, recorded in this table.

**Three trees outside `docs/` are out of the basename rule:** any path under a `fixtures/`,
`evals/`, or `vendor/` directory. A fixture reproduces a consumer's tree (an `ADR-007-…` decision
folder, a session-flow handoff stamped `20260901T100000Z`), an eval workspace holds the files a
skill writes there (`MISSION.md`, `NOTES.md`), and a vendored file keeps its upstream name
(`TUNING.md`). Renaming any of them changes what the test or the copy is of. The case-collision
check still covers all three.

**The seven files with no exact-name lookup were renamed** in the same pull request:
`plugins/firecrawl/skills/update/upstream.md`, four
`plugins/machine-health/skills/audit/{reference,scripts}/{linux,macos}/not-implemented.md`,
`plugins/planning/surface/deferred.md`, and `plugins/skill-quality/probes/template.md`. Current
surfaces were repointed and each owning plugin took a patch release; ADR 0034's tiers held for the
historical record (released changelog entries unchanged).

**Enforcement stays one checker.** `scripts/check-docs-naming.sh` walks `git ls-files -- docs/
':(icase)*.md'` (the extension in any case), applies the rule, the list, and the exclusions, and
fails any two paths in that set that differ only by case, folded with Python's Unicode lowercase
so a non-ASCII pair collides as it would on a case-insensitive filesystem. Its `docs/` half still matches the gate `/docs-naming:generate-file-name-gate`
emits from `.claude/docs-naming.json`, whose `exempt_basenames` now carries the same list; the
co-located test compares the two. The markdown scope outside `docs/` lives only in the checker,
because a docs-naming root takes every extension and so cannot express "markdown only".

## Evidence

ADR 0034's evidence carries over unchanged: three published style guides (Google developer
documentation, GitLab documentation, Microsoft Learn contributor guide) require lowercase,
hyphen-separated file names and none prefers uppercase, and every naming rule this repository
already wrote down for its own files is kebab-case. The role names are the exception those guides
also make, for files a tool finds by name; the table above is the per-name lookup.

A survey of the tree before the change found no file outside the list and the excluded trees whose
uppercase name anything resolved by spelling: each of the seven renamed files was cited only by
its own plugin's prose, scripts, and released changelog entries.

## Consequences

**A new markdown file anywhere is named without a lookup**, and the checker reports an offender in
one line with the rule.

**Skill-written artifact names stay off the list until one is tracked.** `EXPLORE.md`,
`RESEARCH.md`, `INTENT.md`, `PRD.md`, and `MEMORY.md` are exact names skills write, but into the
gitignored `.work/` memory tier, so no tracked file carries them. The first one committed outside
an excluded tree fails the checker, and adding it here with its lookup is a one-line change.

**The docs-naming audit still inventories `docs/` only for this repository.** Its roots cannot
filter by extension, so the markdown scope outside `docs/` is checked but not audited; a rename
there is planned by hand with `/docs-hygiene:rename-references`.

## Amendment (2026-10-11): the docs-naming configuration carries the whole scope

A docs-naming root may now be an object, `{"path", "extensions", "exempt_paths"}`: `extensions`
limits the root to those extensions, matched in any case, and `exempt_paths` takes paths out of the
basename rule unless another root claims them, while the case-collision check still covers them
(`plugins/docs-naming/reference/config.md`). A plain string root is unchanged.
`.claude/docs-naming.json` declares this decision's scope with it: the `docs` root, plus the root
`.` limited to `md` and exempting `**/fixtures/**`, `**/evals/**`, and `**/vendor/**`.

Two statements above no longer hold. The co-located test compares the whole of
`scripts/check-docs-naming.sh` with the gate `/docs-naming:generate-file-name-gate` emits, not
only its `docs/` half, and it seeds every name in the script's exempt list as well as the
configuration's, so a name added to either side alone fails it. `/docs-naming:audit-file-names`
inventories the same set the gate enforces, so a rename outside `docs/` is planned by the audit
like any other.
