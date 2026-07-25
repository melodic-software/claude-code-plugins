# Shadowed skill renames

## Brief

**TLDR:** Undo the pre-migration shadow-compromise skill names (namespacing removed the constraint), fix audit-surfaced semantic misfits, extract a `domain-driven-design` plugin, and codify the naming grammar + cross-plugin reference rules in `docs/PLUGIN-PHILOSOPHY.md` — as a sequenced set of breaking-change PRs with no renames-map entries.

### Goal

Every skill and plugin name in the marketplace denotes what it actually does, follows one codified grammar, and the conventions that produced this state are written down so future names are predictable.

### Locked decisions

**Naming grammar (codify in PLUGIN-PHILOSOPHY, PR 1):**

- Imperative verbs; namespace supplies the object. Documented deviation from the official gerund preference (cite the page, copy nothing) — rationale: sentence-composability ("/explore X, then /research, then /interview me") and collection-consistency (itself official guidance).
- Verb meanings: `audit`/`scan` = read-only report; `check` = deterministic pass/fail gate; `clean`/`tidy`/`fix` = mutates; `setup` = plugin config; `update` = vendor refresh.
- `audit` mutation: read-only by default; mutation only behind an explicit user override (flag/argument), safety qualifiers permitted. Bare invocation never mutates.
- Sanctioned exceptions: nouns for knowledge routers (`principles`, `methodology`) and lifecycle-object routers (`worktree`, `pull-request`); vendor-wrapper stutter (`firecrawl:firecrawl`); `-deep` suffix = heavier isolated execution tier.
- Cross-plugin references: required-for-contract → declared plugin dependency (native auto-install; link the official doc); optional enhancement → "if installed" soft reference with graceful degradation; bare unguarded references forbidden.

**Skill renames** (dir + frontmatter `name` move together; description sharpened third-person what+when):

| From | To |
|---|---|
| `planning:architect` | `planning:plan` |
| `debugging:diagnose` | `debugging:debug` |
| `docs-hygiene:declutter` | `docs-hygiene:audit-noise` |
| `work-items:scan` | `work-items:scan-todos` |
| `toolchain:build` | `toolchain:check` |
| `machine-health:check` | `machine-health:audit` |
| `claude-ops:troubleshoot` | `claude-ops:known-issues` |
| `knowledge:youtube` | `knowledge:youtube-digest` |
| `playbooks:thariq` | `playbooks:skill-authoring` (vendor/, upstream metadata, and `/playbooks:update` mechanics move intact) |
| `session-flow:orchestration-brief` | `session-flow:orchestrate` (finish mid-flight rename) |

**Plugin changes:**

- New `domain-driven-design` plugin housing `ubiquitous-language` (from `planning:domain-modeling`). `planning` declares a hard dependency on it (auto-install). `ubiquitous-language` soft-routes discovery to `event-storming`.
- `event-storming` stays standalone — multi-purpose per eventstorming.com (business health, startup viability, service design, software architecture; DDD is one application).
- Plugin renames as hard breaks: `markdown-formatter` → `markdown-format`, `bash-lint` → `bash-format`.
- Keep: `testing:e2e` (cover non-UI smoke in description), `verification:confirm`, `discovery:research-deep`/`explore-deep`, `review:quality-gate` (add /code-review boundary note), plugin names `codebase-health`, `tdd`.

**Execution (approved package):**

1. PR 1 — codify conventions in PLUGIN-PHILOSOPHY; no renames.
2. One PR per affected plugin for skill renames; each PR carries ALL repo-wide reference updates for that rename atomically (cross-plugin doc references included); minor version bump per plugin (0.x breaking-by-minor precedent); `/docs-hygiene:rename-references` sweep before merge.
3. PR — domain-driven-design extraction + planning dependency + planning bump.
4. PR — plugin renames (markdown-format, bash-format): marketplace.json entry rename, hard break.
5. PR — finish orchestration-brief → orchestrate.
6. Tier D deferred items filed on the work-item tracker, not executed here.

### Constraints

- NO `renames`-map entries while the marketplace is settling — every rename is a clean breaking change with a version bump.
- Never hand-copy external documentation into convention docs; state the rule, link the source.
- Skill `name` must match its directory (agentskills.io spec); 1–64 chars, lowercase alnum + hyphens.
- Plugin skills have no bare command form — `/planning:plan` is the full command; built-in `/plan` (plan-mode toggle) is unaffected.
- Repo process: PRs required, squash merge, Conventional Commits titles, branch `<type>/<description>`; fresh-docs mandate applies to every manifest/schema edit.

### Acceptance criteria

- PLUGIN-PHILOSOPHY contains grammar, audit-mutation rule, cross-plugin reference rule, and sanctioned exceptions, citing official sources without copying them.
- All renamed skills load under their new names; no file in the repo references a dead skill/plugin name (rename-references sweep clean).
- `claude plugin install planning` auto-installs `domain-driven-design`.
- marketplace.json `renames` map unchanged (no new entries).
- Every touched plugin has a version bump and CHANGELOG note marking the breaking rename.

### Captured assumptions

- planning→domain-driven-design dependency declared as bare name (marketplace-latest), no version constraint / release tags — monorepo marketplace keeps them consistent. Revisit if plugins gain independent release cadence.
- `domain-driven-design` plugin starts at 0.1.0.
- Private-marketplace consumers tolerate hard plugin renames by reinstalling (dev-phase posture).

### Out-of-scope

- Tier D restructurings (filed as tracker items): songwriting split (keep `object-writing`; extract `metaphor`, `cliche`, `point-of-view`), `discovery:explore` blindspot split, `source-control:pull-request` babysit split, `firecrawl` update-pipeline extraction, `codebase-health:audit` fix-phase delegation to implementation/verification lanes, `toolchain:setup` step-6 relocation, `testing:plan` as test-type SSOT, `planning:plan` Step-2 design-axes leak, `review:quality-gate` /code-review boundary note.
- Gerund migration (rejected), plugin renames for `codebase-health`/`tdd` (kept).

### Deferred questions

- [arbiter: implementation] Exact sharpened description wording per renamed skill (third-person, what+when, key triggers preserved — e.g. "troubleshoot" stays a trigger word for `known-issues`).
- [arbiter: USER-RESERVED] Reserved-word exposure: if any skill ever ships to the API Skills surface, `claude-*` plugin names need re-checking against platform-side validation (trigger recorded; no action now).
- [arbiter: USER-RESERVED] Songwriting split details (which content moves to `metaphor`/`cliche`/`point-of-view`) — own interview when picked up.

## Plan

(To be filled by /planning:plan — or proceed directly; the PR sequence above is execution-ready.)
