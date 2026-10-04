# Resources Format

`RESOURCES.md` lists the sources a learning workspace trusts. Lesson content comes from these
sources rather than from model recall, and practical judgment comes from the communities the file
names.

## Template

```markdown
# {Topic} Resources

## Knowledge

- [{Type}: _{Title}_, {Author}]({URL})
  {One line: its subject, and the question that should send the learner to it.}

## Wisdom (Communities)

- [{Name}]({URL})
  {One line: what kind of help you get here.}

## Gaps

- {A part of the mission no trusted source covers yet}
```

## Rules

| Concern | Rule |
|---|---|
| Trust | Favor primary sources, recognized experts, peer-reviewed research and tightly moderated communities. Leave out promotional material that poses as teaching |
| Notes | Give each link a one-line note naming its subject and the situation that sends a learner to it; a link with no note is hard to use later |
| Grouping | Sort entries into Knowledge and Wisdom, following the K-S-W framework |
| Gaps | When the mission needs an area no good source covers, list it under `## Gaps`; later searches start from that list |
| Upkeep | A source later found wrong, shallow or off the mission is deleted, not moved down the list. Quality of the list matters more than its length |
| Communities | When the user opts out of joining communities, write that down so later sessions stop proposing them |

## Verification

Resources MUST be verified against the source this turn: fetch and confirm URLs before adding. Training-recall recommendations are unverified synthesis; verify before listing.

**Scope by mode:** the fetch-and-confirm rule applies to EXTERNAL entries. In codebase mode, Repo Sources are the verification. Files Read this turn need no fetch, and a Repo-Sources-only `RESOURCES.md` is compliant; add external Knowledge/Wisdom entries only when the mission needs sources beyond the repo.

RESOURCES entries double as the **rot re-verify anchor**: lessons and references cite them inline, and the Staleness check (SKILL.md "Staleness") re-fetches the cited source to refresh a stale durable artifact.

## Codebase Mode

For `/education:teach codebase`, resources include repo-internal sources discovered per SKILL.md "Codebase mode". Record what discovery located so later sessions reuse it instead of re-deriving the repo's structure:

```markdown
## Repo Sources

- {path to a convention / architecture doc}: {what it establishes}
- {path to a source module / library}: {the pattern it embodies}
- {path to a reference implementation or example}: {why it is exemplary}
- {path to representative tests}: {expected behavior they demonstrate}
```

These are primary sources (files Read this turn), higher trust than any external doc.
