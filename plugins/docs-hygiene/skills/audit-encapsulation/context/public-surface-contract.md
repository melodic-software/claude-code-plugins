# Skill public-surface contract

The contract this skill audits against, applicable to any repo with `.claude/skills/`. The bundled `scripts/detect.sh` encodes it mechanically; this file is the reasoning source the agent applies when classifying and remediating hits. A consuming repo may layer its own conventions on top, but the surfaces and carve-outs below are what the detector implements.

Upstream anchors (cited by URL, not recapped) — Anthropic publishes no formal public-surface contract for skills; this is a stricter discipline consistent with the documented progressive-disclosure model:

- <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#anti-patterns-to-avoid>
- <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#progressive-disclosure-patterns>
- <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#token-budgets>
- <https://agentskills.io/specification>

## Public surface

The public surface of a skill is ONLY:

1. YAML frontmatter (the documented fields)
2. Documented actions — named action + arg shape + output shape declared in the SKILL.md body
3. Arguments and flags
4. The `/skill-name` slash invocation (`/plugin:skill-name` for plugin-packaged skills)

External consumers — rules, agents, other skills, prose docs, ADRs, READMEs, CI configs — describe WHAT they want done in natural language (`/skill-name <action> <args>`), and the skill body decides HOW: which scripts to call, which schemas to validate against, which reference files to load.

## Private — everything else

Anything inside `.claude/skills/<X>/` beyond the public surface is private: all files, all subdirectories regardless of name (`context/`, `reference/`, `actions/`, `evals/`, `templates/`, or any other author-chosen name), all `*.schema.json` files at any depth, and all heading anchors inside `SKILL.md` or its supporting files. Skill authors may rename, refactor, split, or merge any private surface without breaking external consumers because no external consumer may depend on it.

This guarantees skills are rip-and-paste portable: moving `.claude/skills/<name>/` into another repo carries every implementation detail with it; nothing outside the skill depends on internal layout. Caveat: CI / hook / registry consumers of the entry surface (carve-out below) re-point on rip.

## Carve-out — `scripts/` entry surface

A skill's `scripts/` directory is its declared entry surface. Harness surfaces, CI workflows, git hooks, and automation registries MAY path-cite `scripts/` entry scripts directly. **Sibling skills may NOT** — skill-to-skill stays slash-only. That outbound half of the asymmetry is out of scope for this inbound audit; a consuming repo that wants it enforced wires its own outbound gate.

A skill MAY expose a `scripts/<name>.sh` entry as a declared public facade (delegating to a private backend directory) that hooks/CI invoke directly — the encapsulation-respecting alternative to vendoring a copy of the logic. A meta-tooling consumer that only READS a skill-internal path as data — a version-drift gate reading a pinned-version file, a path-scoped trigger naming the file it watches — cites that path under the KIND-2 forced-cite exemption (see the filter taxonomy in SKILL.md): it names a path structurally, it does not invoke skill logic. Logic invocation goes through the facade; data/path reference is KIND-2.

## Carve-out — data files at skill root

Plain data files at skill root (`<skill>/<name>.json` or a `<skill>/<name>.md` data table, NOT `*.schema.json`) are a documented exception to "everything inside is private": they are legal external cites. The data file is the canonical single source the skill reads at runtime, and a vendored copy would race the skill's writer. Schema files (`*.schema.json`) stay private — route via `/skill-name <action>` or vendor the schema to a shared tooling location the consumer repo owns.

## Cite by slash invocation, never by path or heading anchor

External citations into skill internals fragment the contract — when skill authors refactor, every external citation breaks silently because nothing enforces the link.

| Violation shape | Fix |
|-----------------|-----|
| Cite to any path inside `.claude/skills/<X>/` from a rule / agent / doc / prose | Replace with `/skill-name <action>` natural-language invocation. The skill body chooses which internal file / script / schema to use. Add the action if missing |
| Cite to `.claude/skills/<X>/SKILL.md#some-heading` from outside | Heading anchors are body structure (private). Replace with `/skill-name <action>` invocation |
| Cite to `<skill>/<file>.schema.json` from outside | Replace with `/skill-name <action>` (the action validates internally). Schema location is implementation detail |
| Cite to `<skill>/<subdir>/<topic>.md` where the content is genuinely cross-cutting shared vocabulary or constraint | **Path A — promote.** Move the content to a shared rule or convention doc outside the skill (e.g. `.claude/rules/<topic>.md`); consumers cite the new location |
| Cite to `<skill>/<subdir>/<topic>.md` where the content belongs to the skill | **Path B — route.** Replace the external reference with a `/skill-name` invocation, or `/skill-name <action>` if a matching action exists |

When promoting (Path A), leave the original file in place if the skill still consumes it; the promoted doc becomes the single source of truth and the skill's internals reference it. Don't dual-maintain the same body in both locations.

## CI / git-hook consumption — entry surface, not internals

Workflows and git hooks needing logic that ALSO lives in a skill consume the skill's `scripts/` entry surface directly per the entry-surface carve-out. The registry (workflow YAML, hook config) holds a pointer to the entry script or a thin protocol adapter delegating to it — never a reach into `lib/` or any other private subdirectory.

| Need | Technique |
|---|---|
| Skill logic from CI / hooks / automation registries | **Direct entry-surface consumption** — path-cite the skill's `scripts/` entry script, or a thin protocol adapter delegating to it |
| A few lines, not worth an entry script | **Intentional duplication** — the skill has its version; the hook has its own. Audit alignment via a test; a comment names the duplicate |
| Mature, repo-external reuse | **Plugin packaging** — graduate the skill to a plugin; the manifest declares interfaces |
| LLM-shaped CI work (not a mechanical gate) | **Headless invocation** — CI runs `claude -p '/skill <action>'`. Reserve for non-mechanical work |

The choice is per-cite. Enforcement split: the bundled `scripts/detect.sh` is the detector this plugin ships; any hard gate (pre-commit hook, CI job, drift comparison) is whatever the consuming repo wires around it.

## What this contract does NOT cover

- **Self-citation** inside a skill's own files (`.claude/skills/<X>/SKILL.md` citing `.claude/skills/<X>/context/<topic>.md`) is LEGAL and expected — progressive disclosure depends on it.
- **Plugin-cache citations** (`~/.claude/plugins/cache/<plugin>/...`) — plugin internals are upstream territory; treat by the upstream's contract, not this one.
- **Worktree citations** — worktrees share the same `.claude/skills/` tree as the main checkout; the same rules apply at the root path.
