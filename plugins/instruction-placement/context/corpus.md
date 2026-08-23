# Corpus — what gets swept, in what order, and what is never touched

Owned by `audit`. Two tiers: the **core** tier is always swept, the **expanded** tier widens the net
so a convention hiding in an ordinary document is not missed. Both run by default; the expanded tier
is what makes the promote lane possible.

## Core tier — the instruction layer

Surfaces Claude Code already loads, or that a consuming repo maintains as agent instructions. Swept
in full, every run.

| Surface | Scope | Lane |
|---|---|---|
| `CLAUDE.md`, `.claude/CLAUDE.md` | Repo root and every tracked subdirectory | demote |
| `CLAUDE.local.md` | Root and subdirectories, when present and readable | demote |
| `AGENTS.md` | Root and every tracked subdirectory | demote |
| `.claude/rules/**/*.md` | Recursive, including subdirectories | demote / re-scope |
| Nested `.claude/rules/` under subdirectories | Recursive | demote / re-scope |

Rules already carrying `paths:` are still swept — a rule can be correctly located and wrongly
scoped, and an over-broad glob is a finding in its own right.

**User-scope surfaces (`~/.claude/CLAUDE.md`, `~/.claude/rules/`) are read-only context, never
candidates.** They load in every project on the machine and belong to the operator personally, not
to the repository being audited. They are read for one purpose: detecting that a repo-scoped
candidate would duplicate something already stated at user scope. Never propose moving, editing, or
deleting one.

## Expanded tier — ordinary documentation

Tracked markdown outside the instruction layer, swept for **normative** content that a coding agent
would benefit from and currently never sees. This is the promote lane's input.

Priority order, highest signal first:

1. **Named contributor surfaces** — `CONTRIBUTING.md`, `STYLE*.md`, `CONVENTIONS.md`,
   `ARCHITECTURE.md`, `SECURITY.md`, and anything matching `*guidelines*`, `*conventions*`,
   `*standards*`, `*style-guide*`.
2. **Documentation trees** — `docs/**/*.md`, `documentation/**/*.md`, `.github/**/*.md`.
3. **Co-located module documentation** — a `README.md` in a source subdirectory, which frequently
   carries the module's real conventions.
4. **Everything else tracked** — swept last, and only for strong normative signal.

**Other agents' instruction formats** are swept as core-tier when present, because they carry the
same content in a form Claude does not read: `.cursor/rules/**`, `.cursorrules`,
`.github/copilot-instructions.md`, `.windsurfrules`, `.windsurf/rules/**`, `.clinerules`,
`.devin/rules/**`. Treat these as **read-only sources** for the promote lane — propose a Claude
destination, never edit or delete another tool's configuration. The consuming repo may still be
using it.

### Normative signal

The expanded tier is noisy by construction, so the bar for promoting is deliberately higher than for
demoting. A section qualifies as a candidate only with a clear normative marker:

- Imperative or deontic phrasing directed at the implementer — must, never, always, do not,
  required, prefer X over Y.
- A stated convention with a scope — a naming pattern, a layout requirement, a mandated library or
  approach.
- A prohibition with a stated reason.

Explicitly **not** normative signal: tutorials and walkthroughs, design rationale and ADR narrative,
changelog and release notes, API reference tables, roadmaps, meeting notes, and anything written in
the past tense about what was done.

## Never swept

Exclusions are absolute and applied before any classification, so nothing below can reach the
candidate set.

- `CHANGELOG.md` and release-note files — historical by nature.
- `**/evals/fixtures/**` and any fixture tree — deliberately malformed content lives there.
- `**/vendor/**`, `**/node_modules/**`, and any vendored or generated tree.
- `**/.git/**`, lockfiles, and binary or generated artifacts.
- Untracked files, unless the operator names one explicitly. What is not tracked is not a shared
  convention.
- Any file the consuming repo excludes via its own configuration, which is honored as authoritative.

Inside a swept file, two regions are never candidate content: **YAML frontmatter** and **fenced code
blocks**. A convention stated inside an example block is illustrating, not instructing.

## Scale posture

A large repository can put thousands of files in the expanded tier. The sweep is bounded by
discipline, not by silent truncation:

- The core tier is never sampled or capped. It is small and it is the point.
- The expanded tier is swept in the priority order above, and whatever bound is applied is
  **reported** — the number of files swept, the number skipped, and the reason. A run that silently
  covered 200 of 2,000 files while reading like a full audit is the failure mode to avoid.
- Findings are ranked before they are presented, so an operator who reads only the top of the report
  still sees the highest-value moves.
