# Name docs/ files in lower-kebab-case, with conventional exceptions

- Status: accepted
- Date: 2026-09-11

## Context

`docs/` carried three naming forms at once: UPPER-KEBAB (`PLUGIN-PHILOSOPHY.md`,
`MIGRATION-PLAYBOOK.md`, `CATALOG.md`, eleven more at the root), lower-kebab (every
`docs/conventions/*/README.md` neighbour, every ADR, every spec), and the conventional uppercase
names (`README.md`, `CHANGELOG.md`). Every citation had to remember which spelling one file used,
and the thirteen uppercase root files were the most cited: six absolute GitHub URLs in plugin
bodies, fifty-four plugin `setup` skills, two `.claude/rules` files, the top-level `README.md`,
three generators and one validator, and hundreds of relative links.

Two of the thirteen were a URL interface. ADR 0018 has every plugin cite `docs/` doctrine by
absolute raw URL, so `docs/PLUGIN-PHILOSOPHY.md` and `docs/MIGRATION-PLAYBOOK.md` were addresses
that installed plugin copies fetch at run time, and renaming them is a breaking change for any copy
that has not been updated.

No rule stated which form a new file should take, and nothing checked.

## Decision

**Every file under `docs/` is named in lower-kebab-case.** A basename matches
`^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$`: lowercase letters, digits, single hyphens, a
non-empty lowercase extension, dotted stems and multi-part extensions allowed
(`v1.2.schema.json`), and never an empty or trailing segment (`foo..md`, `foo.md.`).

**Three exemptions, and only these.** `README.md`, `CHANGELOG.md`, and `INDEX.md` anywhere under
`docs/`, the conventional uppercase names forges and tooling look for by exact spelling (`INDEX.md`
is the topic-docs convention's reserved index name). Everything under `docs/topics/`, the
branch-only contract slice whose file names belong to the topic-docs convention and are pruned
before merge. Code files by extension (`py`, `sh`, `mjs`, `js`, `ps1`), whose casing is the
language's convention.

**The thirteen root files are renamed in one hard cutover, with no tombstones.** No file is left
at an old uppercase path. Every current-surface citation is repointed in the same pull request,
and every plugin whose body cites a renamed file takes a patch bump with a release entry, so
installed copies receive the corrected citations through the normal update path.

**The historical record is left as written, by tier.** Current surfaces (skills, rules, READMEs,
conventions, generators, the six URL sites) change in every form, bare stems included. ADRs, specs,
and upstream notes change only in markdown links and backtick paths, so the links resolve while the
narrative stays what it was. Plugin `CHANGELOG.md` released entries do not change, except one real
markdown link, corrected under the plugin's own new release entry, which names the correction.

**Enforcement is a checker with a co-located test.** `scripts/check-docs-naming.sh --check`
walks `git ls-files docs/`, applies the rule and the exemptions, and independently fails any two
tracked paths under `docs/` that differ only by case. It runs in the `lint` job as an advisory
step fed to the `ci-status` aggregate, beside the sibling gates. This record is the owner
document a reader consults; a path-scoped `.claude/rules/` file that restates it for `docs/**`
is not added while `main` carries the unhobble bare baseline recorded under `.claude/unhobble/`,
whose method strips pointer rules that have an owner document and a deterministic oracle and
restores a rule only when the stumble ledger defends it. The readd phase recreates such a rule
from this record if the ledger earns it.

**Duplicate ADR numbers stay.** `0018`, `0025`, and `0028` each name two records. This record takes
the next free number and renumbers nothing; a uniqueness gate is a separate change.

## Evidence

**Three published style guides mandate lowercase-hyphenated file names and none prefers
uppercase.** The Google developer documentation style guide's filenames page requires lowercase
letters with hyphens between words. The GitLab documentation style guide requires lowercase
filenames with dashes. Microsoft Learn's contributor guide requires lowercase, hyphen-separated
names for markdown and media. Every naming rule this repository already writes down for its own
files (skill directories, convention directories, ADR filenames, script names) is kebab-case; the
thirteen uppercase files were the outliers, not the rule.

**Tombstones cannot coexist with their lowercase twins.** Microsoft Learn's Azure Repos page on
case sensitivity states that when a repository holds two files whose names differ only by case,
checking out both on a case-insensitive file system results in the second overwriting the first.
Two of this repository's CI jobs check out the tree on `windows-2025`, and contributors work on
macOS. A compatibility file at `docs/PLUGIN-PHILOSOPHY.md` beside `docs/plugin-philosophy.md`
would therefore corrupt every such checkout, and a raw-URL tombstone has to sit at exactly the old
path to serve its purpose. Hard cutover was the only shape that keeps the tree valid everywhere.

**The repository's own posture for a breaking body change is a version bump.** Twelve of the
twelve most recent commits that edited a plugin body bumped that plugin and wrote a changelog
entry, and the plugin cache is version-keyed, so an unbumped edit never reaches an installed copy.
The changelog-parity discipline sanctions a released-entry edit only when the pull request body
and the plugin's new release entry both name it, which is why the one released-entry link
correction is declared in both places.

**`git mv` handles the case-only rename on every platform.** Git's `builtin/mv.c` renames through
the index, so a rename that differs only by case commits correctly from a case-insensitive
checkout as well; no two-step rename through a temporary name was needed.

**A path-scoped rule cannot enforce a naming rule alone.** Rules under `.claude/rules/` with a
`paths:` frontmatter load when a covered file is read, never when one is created, so a new
`docs/NEW-FILE.md` is written without the rule ever entering context. The checker is the gate; the
rule is the explanation a reader finds when they open a covered file.

## Consequences

**A 404 window for stale installed copies.** An installed plugin whose body still cites
`docs/PLUGIN-PHILOSOPHY.md` or `docs/MIGRATION-PLAYBOOK.md` by absolute URL fetches a path that
no longer exists until that plugin is updated to the bumped version. The window closes per plugin
on update and there is no redirect; the raw content host serves none, and a tombstone is ruled out
above.

**Future edits that cite a retired path get an advisory notice.** The `guardrails` plugin's
`stale-path-verify` hook flags a write that names a path no longer in the tree, so a body edit
pasted from an old copy surfaces the uppercase path at write time rather than at review.

**Every future `docs/` file is named without a lookup.** The rule has one form and three listed
exemptions, and the checker reports the offending path and the rule in one line.

**Historical records read slightly differently from the tree.** An ADR or spec that names a
doctrine file by bare stem in its narrative still says `PLUGIN-PHILOSOPHY`; the link beside it
resolves. A reader following the narrative alone resolves the name by case-folding, which is the
cost accepted for leaving accepted records unedited.

**The reference sweep is not reusable as written.** The sed maps and the tier boundary were
specific to these thirteen files. A reusable naming-consistency skill is a separate change with its
own evals and listing budget.
