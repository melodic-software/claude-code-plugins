# book-distill — templates

The two fill-in templates the SKILL.md phases point to: the progress file (Phase 1.4) and the cross-session continuation prompt (Phase 2, session end).

## Progress file (Phase 1.4)

Save a progress file under `${CLAUDE_PLUGIN_DATA}/{project-slug}/{target-skill-slug}/` (named by book slug) with this template. Derive `{project-slug}` from the basename of `${CLAUDE_PROJECT_DIR}` and `{target-skill-slug}` from the target skill name, each slugified to lowercase alphanumerics and hyphens:

```markdown
# {Book title} distillation

{Author}'s "{Full Title}" ({Year}) — reading in progress.
Source at `{path}` ({page count} pages, offset {N}).
Target skill: `{skill-name}` ({new | extend}).

## File plan

| File | Chapters | PDF pages | Status |
|------|----------|-----------|--------|
| concept-author.md | Ch 1-2 | 23-59 | PENDING |
| ... | ... | ... | ... |

## Session log

- Session 1 ({date}): {files completed}
```

## Continuation prompt (Phase 2, session end)

When approaching ~3 chapters completed (or when PDF image accumulation degrades quality), stop and generate a **continuation prompt**. Use this template:

```markdown
## Session: {Book title} distillation (continued)

### Context
{Book title} by {Author} distillation into the `{skill-name}` skill.
Progress file: `${CLAUDE_PLUGIN_DATA}/{project-slug}/{target-skill-slug}/{book-slug}-progress.md`

### Completed so far
- `{file1}.md` — Ch {N} ({topic}) — DONE
- `{file2}.md` — Ch {M} ({topic}) — DONE
- ...

### Next up
- `{next-file}.md` — Ch {X} ({topic})
  - PDF pages: {start}-{end}
  - Key sections to capture: {list}

### PDF page map (for reference)
- Ch {X}: pp. {content}, PDF {actual}
- Ch {Y}: pp. {content}, PDF {actual}
- ...

### Instructions
Read the progress file first. Then read PDF pages {start}-{end}
for Ch {X} and write `{next-file}.md`. Continue the read-write pipeline
for remaining chapters in the file plan.
```
