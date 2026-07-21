# firecrawl — update procedure

Read when running the update action. The update model, preservation invariants, and safety guarantees stay in `../SKILL.md` "Preservation rules" + "Safety"; this file holds the procedural detail (when to invoke, the modes, the full pipeline). Maintainer-facing: run in a working-tree checkout of this plugin, never against an installed marketplace copy.

## When to invoke

- When a scrape/search call fails with an unexpected flag rejection (command surface drifted)
- On a weekly-ish cadence — the `--check` mode detects drift without side effects
- When the upstream release notes mention a new command you want to use
- When the installed CLI is flagged at an older version by your environment tooling

## Modes

| Invocation | Effect |
|---|---|
| `/firecrawl:update --check` | Read-only drift report. Fetches upstream + npm metadata, compares against `UPSTREAM.md`. Prints CLI version delta, upstream SHA delta. **No mutations.** |
| `/firecrawl:update` | Full update pipeline with two approval gates |

## Pipeline (full update)

```text
1. Gather state    firecrawl --status           → current version, auth, credits
                   npm view firecrawl-cli version → latest published
                   curl upstream SKILL.md → /tmp  → SHA256
                   firecrawl --help → /tmp        → current command surface
2. Compare         version delta, upstream SHA vs UPSTREAM.md record
3. Report          one-pane summary — nothing mutated yet
4. [Gate 1]        prompt to proceed with npm install
5. Execute npm     npm install -g firecrawl-cli@latest
                   firecrawl --status           → verify post-install
                   firecrawl --help → /tmp       → new command surface
                   diff old vs new help
6. [Gate 2]        integrate upstream SKILL.md changes into ours
                   — small delta: inline-edit preserving the Preservation rules
                   — non-trivial delta: drive the rewrite with the
                     /skill-creator:skill-creator plugin skill if installed
                     (passing the Preservation rules), otherwise inline-edit
                   show proposed SKILL.md diff, prompt to apply
7. Finalize        update UPSTREAM.md (date, SHA, version, previous-version for rollback)
                   clean up /tmp/fc-*
                   run the repo's markdown + shell linters over the changed files
```
