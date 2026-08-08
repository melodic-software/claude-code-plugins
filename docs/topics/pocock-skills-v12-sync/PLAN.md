# pocock-skills-v12-sync

## Brief

### TLDR

Sync the learnings from mattpocock/skills v1.2 (repo HEAD v1.2.3 @ `84fdeff`) into this marketplace: fix the drift the audit found, consolidate all Pocock provenance into one SSOT outside the skill bodies, land the verified 35-skill upstream↔ours map durably, then work four further lanes (owned-skill deltas, `/wait-what` port, `/wizard` port, infra adoptions) — one feature branch, one PR, a `/session-flow:handoff` at every lane boundary.

### Goal

Every v1.2 change that touches a skill we derived is either adopted, consciously rejected, or tracked; provenance for all Pocock-derived material lives in `docs/upstream/mattpocock-skills.md` (not in installed skill bodies); the map and research summary are committed under `docs/topics/pocock-skills-v12-sync/`; the two new upstream skills (`wait-what`, `wizard`) get an explicit port decision in their own lane sessions.

### Constraints

- ONE PR on `feat/pocock-skills-v12-sync`; squash merge; PR title Conventional Commits; PR body carries closing keyword + `## Related` per repo contract.
- Lane sessions are sequential on this branch; every lane boundary gets a `/session-flow:handoff`; each lane session opens with a lane-scoped `/planning:interview` (agenda = that lane's deferred questions) and `/discipline:use-your-skills`.
- Provenance/attribution never lands in SKILL.md bodies (agent noise); SSOT + plugin CHANGELOGs carry it. Content citations the agent uses (e.g. Fowler in code-reviewer) are not provenance and stay.
- Recheck triggers must name an observable event ("a mattpocock/skills release whose changeset names `<skill>`"); the SSOT stores the last-audited upstream ref, never dates/logs duplicating git history.
- Fresh-docs mandate applies to every contract-surface change in lanes 2–5 (frontmatter, plugin.json, hooks).
- Plugin edits bump semver + CHANGELOG per repo rules; `.work/**` stays uncommitted (gitignored).

### Acceptance criteria

- Lane 1: `docs/upstream/mattpocock-skills.md` exists with per-skill attribution table, recheck trigger, last-audited ref (v1.2.3 @ `84fdeff`), map pointer, and the issue-#693 harness note; `plugins/planning/skills/questionnaire/SKILL.md` and `wayfind/SKILL.md` carry zero Pocock provenance blocks; `docs/topics/ai-adoption-ladder/design/RESEARCH-sandcastle-pocock.md` no longer names `writing-great-skills` as live; map + research summary committed under `docs/topics/pocock-skills-v12-sync/`; planning plugin version bumped + CHANGELOG entry; repo lint/format checks pass.
- Lanes 2–5 (execution contract — per-lane loop): open with lane interview → implement that lane's items → verify (toolchain check + review pass) → commit → `/handoff`. A lane is CLOSED when its menu items are each adopted/rejected/tracked, its SSOT rows updated, and the branch is green.
- PR: all five lanes landed, CI green, PR body linkage contract satisfied.

### Captured assumptions

- Upstream MIT license permits derivation with attribution (his repo: MIT).
- `docs/upstream/` is a new directory; one file per upstream source is the going-forward registry pattern (firecrawl's per-plugin UPSTREAM.md sidecar stays as-is for that plugin's own update skill).
- Menu item ids M1–M20 refer to `.work/youtube-watch/new-skills-v1-2-brings-wait-what-writing-gaDdrDdczO4/recommendations/menu.md` (local slice); the committed map + SSOT carry everything lanes 2–5 need.

### Out-of-scope

- Codex `agents/openai.yaml` sidecars (no Codex target; v1.2.2 hidden-skill gotcha recorded in SSOT notes).
- Beta-channel bucket, docs-site build, `setup-matt-pocock-skills` analog, his personal/TS skills (shoehorn, scaffold-exercises, setup-pre-commit), writing-beats/fragments/shape, teach workspace, ask-matt router-as-skill.
- Changing `work-items` skill *behavior* (lane 1 records provenance only; any behavior sync is a separate effort).

### Deferred questions

- Q9 — `/wait-what` port: house name vs upstream name, plugin home, CONTEXT.md→curate-language seam mapping. Arbiter: USER-RESERVED (lane-3 interview).
- Q10 — `/wizard`: go/no-go, plugin home, security posture (template.sh audit, .env/gh-secret writes, Windows portability). Arbiter: USER-RESERVED (lane-4 interview).
- Q11 — lane-5 subset: which of M10/M13/M14/M15/M16 to adopt vs reject. Arbiter: USER-RESERVED (lane-5 interview).

## Lanes

| # | Lane | Items | Status |
|---|---|---|---|
| 1 | Hygiene + record | M1 M2 M19 M20 + SSOT + map promotion + provenance strip | this session |
| 2 | Owned-skill deltas | M6 M7 M8 M9 M11 M12 | pending |
| 3 | /wait-what port | M4 (Q9) | pending |
| 4 | /wizard port | M5 (Q10) | pending |
| 5 | Infra / P2 | M10 M13 M14 M15 M16 (Q11) | pending |

## Plan

(Filled per-lane by the lane sessions; Lane 1 executes directly off this Brief.)
