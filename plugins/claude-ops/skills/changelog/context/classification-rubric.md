# Classification rubric for CC changelog items

Five lenses. A `diff` emits one decision row per component effect, never one row per changelog item. `skip` counts toward the read marker and leaves no row.

| Lens | Required sentence | Row |
|---|---|---|
| `correct` | what a component states that is now false, and what is true | Corrected. Cite the changelog for behavior when it and a docs page disagree, and copy that pair into Docs lag |
| `replace` | the component behavior a native surface now covers | Replaced with native. The store cell reads `nominated` until a human writes the verdict. This run never writes `replaced` |
| `adopt` | the problem the component works around or lacks, which the upstream change solves | Adopted. `defer pending probe` when the only evidence is a doc page or a live probe still to run |
| `note` | one line on why it is worth remembering and not acting on | Noted |
| `skip` | none | no row |

P1/P2/P3 are retired names. What used to be P1 is `correct` or `adopt`. What used to be P2 is `adopt` or `note`. What used to be P3 is `skip`.

# Retired item tiers

The notes below are signals for choosing a lens. They are not the output.

## Three-tier classification

### P1: Requires update

Repo already uses this CC feature or surface, and the changelog changes behavior, adds capability, or fixes a bug that affects our configuration/documentation.

**Signals:**

- Grep finds the feature name in repo rules/config (already adopted)
- Behavioral change to something we depend on (hook event schema, permission engine, frontmatter field)
- Bug fix for a field we read (hook stdin fields, transcript tokens, cache metrics)
- Breaking change or deprecation of something we use
- Existing quirks entry becomes stale (bug fixed upstream)
- Existing recheck trigger fires

**Action:** Update affected files. Document behavioral change.

### P2: Worth considering

New capability the repo does NOT currently use but SHOULD evaluate for adoption.

**Signals:**

- New frontmatter field that could enforce existing prose conventions mechanically
- New hook event enabling observability we currently lack
- New CLI flag solving a pain point documented in quirks or rate-limit workflow
- New setting enabling automation we currently do manually
- Platform improvement making a deferred feature tractable

**Action:** Research capability, evaluate fit, recommend adopt/defer with rationale. Do NOT skip because "we don't use it yet". That's exactly why it needs evaluation.

### P3: No action

UI/cosmetic fix, internal refactoring, or feature entirely irrelevant to repo.

**Signals:**

- Purely visual change (spinner text, markdown rendering, table borders)
- Bug fix for feature we don't use and have no plans to use
- Platform-specific fix for OS we don't target
- Internal performance optimization with no user-visible behavior change

**Action:** None. List in summary for completeness.

## Edge cases

| Situation | Classification | Rationale |
|---|---|---|
| Bug fix for feature we don't use but MIGHT adopt | P2 | Fix may unblock adoption |
| New feature behind experimental flag | P2 | Worth tracking even if not adoptable yet |
| Deprecation of something we don't use | P3 | Unless we planned to adopt it |
| Security fix | P1 always | Security fixes affect trust posture regardless of direct usage |
| Model-specific change (e.g., "<model> now...") | P1 if we use that model | Check any model-routing/tiering docs the repo keeps |
| Plugin-system change | P1 if we use plugins | Check `enabledPlugins` in settings.json |

## Item categories

Changelog items fall into categories that predict which surfaces to check:

| Category | Typical surfaces (see `repo-surfaces.md`) | Examples |
|---|---|---|
| **Hook/event** | Hook scripts, hook-related rules/docs | New event types, schema changes, reliability fixes |
| **Skill/frontmatter** | `.claude/skills/**/SKILL.md`, skill-authoring docs | New fields, discovery changes |
| **Settings/permission** | `.claude/settings*.json`, settings-related docs | New keys, permission engine changes |
| **CLI** | `CLAUDE.md` CLI references, command cheat-sheets | New flags, command changes |
| **Model/rate-limit** | Model-routing/usage docs | Pricing, limits, model behavior |
| **Agent/subagent** | `.claude/agents/*.md`, agent conventions docs | Agent frontmatter, isolation changes |
| **UI/cosmetic** | (none usually) | Visual fixes, spinner text |
| **Bug fix** | Depends on affected surface | Fix for reported issue |
