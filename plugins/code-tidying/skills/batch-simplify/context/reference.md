# batch-simplify — grouping & output reference

Detail the SKILL.md phases point to: how to group changed files for simplification waves (Phase 4), the summary-report template (Phase 8), and generic per-ecosystem verification fallbacks (Phase 7).

## Grouping & dependency order (Phase 4)

Group files by project/ecosystem relatedness. Each group should contain files that share enough context for the simplifier to reason about them together.

**Grouping rules** (in priority order):

1. **Same project directory** — files in the same project (identified by the nearest `*.csproj`, `package.json`, `pyproject.toml`, `Cargo.toml`, or equivalent manifest) go together
2. **Source vs tests** — separate source code from test code within the same project if the combined count exceeds ~15 files
3. **Root config files** — all root-level config files (`.editorconfig`, build-system props, formatter configs) form one group
4. **Standalone scripts** — skill/tool scripts group by parent directory

Agent & enforcement configuration (`.claude/hooks/**`, `.claude/settings*.json`, `.mcp.json`, CI workflows, git-hook manager config) is excluded in Phase 2 — it never forms a simplification group; changed files there surface as read-only deferred items.

**Dependency ordering** — process groups in this order:

1. Root build/tooling config (everything depends on these)
2. Standalone scripts (skills, tools)
3. Shared/platform libraries (other code depends on these)
4. Application code (depends on shared libs)
5. Architecture/cross-cutting tests (depend on libs + apps)
6. Independent polyglot services — by ecosystem, source before tests

## Summary report template (Phase 8)

Present a final report:

```text
## Batch Simplify Results

Scope: {scope}  (e.g., "48h" or "branch chore/misc-maintenance vs main")
Files scanned: {total_files}
Groups processed: {group_count}

| # | Group | Files | Changes | Deferred | Verification |
|---|-------|-------|---------|----------|-------------|
| 1 | Root Config | 13 | 2 files modified | 0 | PASS |
| 2 | Agent Hooks | 13 | 4 files modified | 2 | PASS |
| ... | ... | ... | ... | ... | ... |

Final cross-ecosystem verification: PASS/FAIL

## Deferred items (filed as issues)

- #NNN: refactor(<area>): <what> (High)
- ...

## Deferred items (not filed — judgment calls preserved)

- <site> — rejected as explicit-over-implicit (Group 2)
```

If zero items were deferred across all groups, state explicitly: *"No items deferred. All identified simplifications were applied or determined to be no-ops."*

## Ecosystem verification commands (Phase 7)

Prefer the consuming project's own canonical commands (its `CLAUDE.md` / CI config usually names them — e.g. warnings-as-errors flags, custom test runners). Generic fallbacks when none are declared:

| Group ecosystem | Fallback verification |
|----------------|-----------------------|
| .NET | `dotnet build` + `dotnet test` from the project dir |
| TypeScript/JavaScript | `npx biome check .` (or the project's lint script) + `npm test` from the project dir |
| Python | `ruff check .` + `pytest` from the project dir |
| Bash | `shellcheck <files>` + `shfmt -d <files>` |
| PowerShell | `pwsh -NoProfile -NonInteractive -Command "Invoke-ScriptAnalyzer -Path <files>"` |
| Markdown (docs flag) | `npx markdownlint-cli2 <files>` (with the project's config when present) |
| Mixed/config | the dominant ecosystem's build + `jq . < file` for JSON validity |

Include the group's verification step in each simplifier agent's prompt so the agent self-verifies before returning; Phase 7 re-runs it as the safety net.
