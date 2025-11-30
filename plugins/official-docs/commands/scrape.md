---
description: Scrape Claude documentation from official sources, then refresh the local index and metadata.
allowed-tools: Read, Bash, Skill
---

# Scrape Command

Scrape Claude documentation from official sources and run the full post-scrape workflow (index refresh and validation).

## Semantics

- This command **always performs actual scraping** of at least one documentation source.
- Default behavior:
  - Scrape **all configured official sources** (Claude docs, Claude Code docs, Anthropic docs), skipping unchanged documents.
  - Refresh the local index and metadata.
  - Validate that everything looks healthy.

## Default Workflow

When invoked without qualifiers:

1. Invoke the `official-docs` skill.
2. Request scraping with natural language:

   ```text
   Please scrape all configured Claude documentation sources. Skip unchanged documents, then refresh the local index and metadata and validate. Run in foreground so we can see progress.

   IMPORTANT: Use Python 3.12 for validation (py -3.12) due to spaCy compatibility. Python 3.14 works for scraping.
   ```

3. Let the skill decide which scripts to run based on its SKILL.md guidance.

## Scope Flags (Natural Language)

Use natural language to narrow scope:

- **By domain**: "Scrape only docs.claude.com, then refresh the index."
- **By category**: "Scrape only /en/api/ from docs.claude.com."
- **Post-scrape behavior**:
  - `scrape-only`: Skip index refresh and validation.
  - `scrape+refresh`: Scrape and refresh index (default).
  - `scrape+detect-drift`: Scrape and detect drift (404s, missing files).
  - `scrape+auto-cleanup`: Scrape and automatically cleanup drift.

## What This Command Should NOT Do

- Never run validation-only or index-only workflow.
- Never run scrapes in background with polling loops.
- Never make ad-hoc script edits during scrape.

## Accurate Reporting

**Distinguish by domain:**
- `docs.claude.com` and `code.claude.com`: Serve .md URLs successfully
- `anthropic.com`: Does NOT serve .md URLs (expected 404s, falls back to HTML)

Report per-domain statistics accurately.

## Related Commands

- `/official-docs:refresh` - Refresh index without scraping
- `/official-docs:validate` - Validate index without scraping
