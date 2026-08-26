# L1-derivability — `C-vcs-repo`

93 files. `disk-hygiene`, `github`, `repo-fleet-hygiene`, `repo-hygiene`, `source-control`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 82 |
| `out-of-scope: functional artifact` | 10 |
| `delete` | 1 |

Roll-up for the 82 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
`CHANGELOG.md` files, and plugin READMEs across the five plugins. Each is authored doctrine,
release history, or a contract that no code in this repo states; none restates a primary source that
a fresh agent could re-derive. Ten files are functional artifacts (`**/evals/fixtures/**`,
`plugins/source-control/skills/worktree/fixtures/README.md`, and the five
`plugins/source-control/skills/*/.claude/source-control*.md` config fixtures) and take no verdict.

## `plugins/repo-hygiene/skills/clean/reference/ecosystems.md` — verdict: `delete` (PROVISIONAL) [audience: agent]

| Factor | Reading |
|--------|---------|
| Derivable? | yes — the file's entire body is four pointers to files sitting in the same skill, each with a self-describing name: `reference/cleanup-config.md`, `../scripts/clean-caches.sh`, `../scripts/clean-build.sh`, `../scripts/git-prune.sh` and siblings |
| Re-derivation cost | cheap — one `ls plugins/repo-hygiene/skills/clean/{reference,scripts}/` |
| Drift risk | moderate — it hard-codes six script filenames plus a section reference (`§1–§5 in SKILL.md`) that nothing verifies |
| Fact ownership | none — the file states no claim of its own. Its own first line of body is `The per-ecosystem cleanup surface is owned elsewhere — read it at the source:` |

Verdict rationale: this is the residue of a pointer conversion, not a document. It was reduced to
pointers by the #2695 pass and nothing since has given it content. It is also effectively
unreachable: `plugins/repo-hygiene/skills/clean/SKILL.md` cites `reference/invocation-forms.md`
(line 45) and `reference/cleanup-config.md` (lines 84, 102) but never `reference/ecosystems.md`. Its
one inbound citation across the whole repo is a back-reference from the file it points at,
`plugins/repo-hygiene/skills/clean/reference/cleanup-config.md:3`:

> The Workflow (§1–§5 in `SKILL.md`) iterates these lists; `reference/ecosystems.md` points here and
> at the action scripts.

A pointer file whose only reader is its own target is a closed loop that no session enters. Deleting
it removes an unreachable indirection layer; the two real destinations (`cleanup-config.md` and the
`scripts/` tree) stay reachable from `SKILL.md` directly.

Required companion edit: drop the clause `; \`reference/ecosystems.md\` points here and at the
action scripts` from `plugins/repo-hygiene/skills/clean/reference/cleanup-config.md:3`, so the
deletion leaves no dangling citation.

Spot-test: **not run — no fresh-context subagent tool exists in this session** (see the README's
spot-test section). Verdict stays provisional. If wave 2 cannot run the spot-test, downgrade this to
`convert-to-pointer` (a one-line redirect to `cleanup-config.md`, target verified present) rather
than applying the delete unconfirmed.

## Cross-lane observations

- L5-noise: `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md:3-8` keeps a
  paragraph its own successor paragraph marks "Superseded by the 2026-08-14 re-check below".
- L3-ssot: `plugins/repo-hygiene/skills/clean/context/preflight.md:24-26` reproduces the output
  contract verbatim from `plugins/repo-hygiene/skills/clean/scripts/preflight.sh:4-7`.
