# Skill inventory — what a rightsizing runbook would orchestrate

Enumerated 2026-07-24 from `plugins/*/skills/*/SKILL.md`: **60 plugins, 181 skills, 605 markdown
files and 73,035 markdown lines under `plugins/*/skills/`**. Every skill in the marketplace is a
**target** of the rightsizing pass. This document classifies which are also **instruments** of it.

A tree-wide `find` returns 362 `SKILL.md` files. That figure mixes three populations and must never be
used as the target set:

- **181** top-level plugin skills — `ls plugins/*/skills/*/SKILL.md | wc -l`.
- **187** under `plugins/` including six vendored upstream materializations at
  `plugins/*/skills/*/vendor/SKILL.md`, which are hand-edit-prohibited.
- The remainder live in git worktrees under `.claude/worktrees/` — three exist, and the directory is
  gitignored at `.gitignore:15`, so a git-tracked enumeration excludes them for free where a filesystem
  walk does not.

Doubling is not the invariant and the exclusion path must not be hardcoded: derive it from
`git worktree list` plus gitignore-awareness, plus a `vendor/` rule, plus
`scripts/cross-plugin-source-registry.txt` (13 registered byte-identical `hook-utils.sh` copies and two
registered reference files, each guarded by its own CI drift check). Those are the first concrete
requirements this inventory produced.

Descriptions were read in full for the plugins in the Instruments table. Everything else is
classified from its name and listing description and is marked `candidate` — confirm before wiring
it into a runbook step.

## Precedent: the router already exists

`re-anchor:sweep-all-disciplines` is described as "not a corrector itself, but a router that fans
out an audit-only subagent per in-scope corrector and then applies their corrections on the main
thread in a fixed order," with a cheap posture digest at conversation start. That is structurally
the runbook shape: fan out audit-only lanes, collect, apply in a fixed order. Any runbook built here
should follow that pattern rather than invent a second one, and should state why it is not simply a
new member of that sweep.

## Instruments — verified

| Skill | Contribution to a rightsizing pass | Verified |
|---|---|---|
| `claude-config:audit-instructions` | The core content audit. Checks I1–I11 over CLAUDE.md, rules, skill bodies, agent definitions, prompt hooks, output styles. Report-only, human-gated, fresh-subagent verify pass, ~20-dispatch ceiling. | Read `SKILL.md` + `reference/criteria.md` |
| `claude-memory:audit` | Memory-layer hygiene (I1–I5 on memory surfaces) — the half `audit-instructions` deliberately routes away | Description |
| `claude-memory:stateless` | Auto-memory inspection and disablement | Description |
| `skill-quality:check` | Structural gate: frontmatter, listing-budget cap, line caps, broken refs, markdownlint, evals presence | Description |
| `docs-hygiene:audit-derivability` | Whether a doc earns its existence against a fresh agent re-deriving it — the "obviousness" rule of S12 | Description |
| `docs-hygiene:audit-noise` | Five noise shapes including scope/loading meta-commentary | Description |
| `docs-hygiene:extract-ssot` | Deduplicate repeated content into one named source and migrate call sites | Description |
| `docs-hygiene:compress` | Brevity with a semantic-diff subagent that reverts semantic loss | Description |
| `docs-hygiene:audit-encapsulation` | Citations reaching into a skill's private surface past the slash invocation | Description |
| `docs-hygiene:rename-references` | Stale-reference sweep after any rename the pass causes | Description |
| `plugin-quality:audit` | Post-use behavioral audit of a plugin component | Description |
| `claude-config:audit` | Config-file mechanics: settings, hooks wiring, MCP, drift against current docs | Description |
| `claude-config:audit-automation-gaps` | Hooks / MCP / skills / subagents against the enforcement hierarchy — the "convert a must-always rule to a hook" remediation of check I5 | Description |
| `playbooks:fable-5` | Not an auditor. The model-era doctrine the audit's premises rest on, **and** the structural exemplar: `SKILL.md` plus 13 on-demand chapters under `context/` | Read |
| `playbooks:skill-authoring` | Authoring conventions a rewrite must land inside | `candidate` |

## Instruments — candidates, unconfirmed

| Skill | Why it might belong |
|---|---|
| `re-anchor:sweep-all-disciplines` | The router precedent; possibly the correct home rather than a new runbook |
| `re-anchor:point-dont-copy` | Pointer-over-copy is the S8 placement rule's nearest incumbent |
| `re-anchor:tighten-your-output` | Terseness discipline, adjacent to `docs-hygiene:compress` |
| `re-anchor:recheck-against-upstream` | Existing state is not evidence of its own correctness — the posture the whole pass assumes |
| `re-anchor:reuse-or-replace` | Whether an incumbent should survive at all |
| `re-anchor:reason-dont-recite` | Precedent is descriptive, never justifying — the argument against keeping a rule because it is there |
| `re-anchor:use-your-skills` | Whether available skills actually fire; adjacent to `/doctor`'s unused-skill scoring |
| `code-tidying:audit-comment-residue` | The S5 comment-density rule, applied to code rather than instructions |
| `codebase-health:audit` | Repo-level health framing |
| `mcp-tools:audit` | MCP surface, feeding check I11 (CLI over MCP where equivalent) |
| `naming:name-it-better` | Naming whatever this produces |
| `verification:confirm` / `verification:measure` | The delete-and-watch loop that behavioral findings require |
| `discovery:research` / `research-deep` | The fresh-docs mandate's execution arm |
| `review:fanout` / `review:quality-gate` | Independent review of the pass's own proposals |
| `session-flow:orchestrate` | Multi-phase session mechanics if the pass spans sessions |
| `work-items:track` / `decompose` | Where findings land when they are not applied immediately |
| `planning:audit-answers` | Fresh validators challenging locked answers — the rubric/verifier shape of S10 |

## Targets only — the remaining ~145 skills

Every other skill (`songwriting:*`, `testing:*`, `source-control:*`, `github:*`, `work-items:*`,
`knowledge:*`, the eleven `*-format:setup` skills, and the rest) is subject to the pass but
contributes nothing to running it. Two properties make them the pass's real workload:

- **`setup` skills are a repeated shape.** 30+ plugins ship one. If the rightsizing rules imply a
  change to that shape, it is a 30-file change, not a one-file change — and a strong candidate for
  `docs-hygiene:extract-ssot` before anything else.
- **The `re-anchor` plugin is 15 skills of pure instruction content.** It is the densest
  concentration of exactly the material this pass audits, and the most likely place for
  cross-surface conflict with `~/.claude/CLAUDE.md`, which states many of the same disciplines as
  standing rules.

## Known conflict surface, already visible

The user-scope `~/.claude/CLAUDE.md` is 50 lines / 9,825 characters of near-uniformly absolute
directives ("Never…", "Always…", "never rely solely on…") across nine sections. Independently:

- The memory doc targets **under 200 lines** per `CLAUDE.md` — the file passes on length while
  being extremely dense per line, so a line-count gate alone would clear it.
- The same file already practices progressive disclosure correctly: a "Reference docs (read on
  demand)" block pointing at five files under `~/.claude/docs/` that are not auto-loaded.
- A `SessionStart` hook injects a persistent output-style ruleset on every prompt, which is a
  further always-loaded instruction surface that no incumbent inventories as such.

Whether that file should change is the operator's call, not the pass's. It is named here because it
is the highest-signal dogfood target on this machine.

## Out of this repo's reach

`~/.claude/**` is chezmoi-managed (source `melodic-software/dotfiles`). Any change the pass proposes
to a user-scope surface is backfilled through that repo's own flow, never edited in place from an
agent session. A runbook that proposes user-scope edits must emit them as routed recommendations,
matching how `audit-instructions` already treats upstream-owned surfaces.
