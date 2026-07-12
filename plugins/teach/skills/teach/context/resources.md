# Resources Format

`RESOURCES.md` is the curated set of trusted sources for a learning workspace. Knowledge for explainers is drawn from here, not from parametric guesses. Wisdom comes from communities listed here.

## Template

```markdown
# {Topic} Resources

## Knowledge

- [{Type}: _{Title}_ — {Author}]({URL})
  {One line: what it covers and when to reach for it.}

## Wisdom (Communities)

- [{Name}]({URL})
  {One line: what kind of help you get here.}

## Gaps

- {Area the mission needs but no good resource exists for yet}
```

## Rules

- **High-trust only.** Prefer primary sources, recognized experts, peer-reviewed work, communities with strong moderation. If a resource is marketing dressed as education, leave it out
- **Annotate every entry.** A bare link is useless in three months. Add one line: what it covers and when to reach for it
- **Group by Knowledge / Wisdom.** Mirrors the K-S-W framework
- **Surface gaps explicitly.** If no good resource exists for an area the mission needs, write a `## Gaps` section. This drives future search
- **Prune ruthlessly.** A resource that turned out to be wrong, shallow, or off-mission should be removed. Better five sharp sources than thirty mediocre ones
- **Record community preferences.** If the user opted out of joining communities, note it

## Verification

Resources MUST be verified against the source this turn — fetch and confirm URLs before adding. Training-recall recommendations are unverified synthesis; verify before listing.

RESOURCES entries double as the **rot re-verify anchor**: lessons and references cite them inline, and the Staleness check (SKILL.md "Staleness") re-fetches the cited source to refresh a stale durable artifact.

## Codebase Mode

For `/teach codebase`, resources include repo-internal sources discovered per SKILL.md "Codebase mode". Record what discovery located so later sessions reuse it instead of re-deriving the repo's structure:

```markdown
## Repo Sources

- {path to a convention / architecture doc} — {what it establishes}
- {path to a source module / library} — {the pattern it embodies}
- {path to a reference implementation or example} — {why it is exemplary}
- {path to representative tests} — {expected behavior they demonstrate}
```

These are primary sources (files Read this turn) — higher trust than any external doc.
