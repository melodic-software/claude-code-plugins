```bash
# Tunables (listing description cap; description field cap; SKILL.md line caps;
# vendor sync age).
# DESC_CHAR_CAP restates the harness's documented per-entry listing cap, the
# default of skillListingMaxDescChars ("truncated at 1,536 characters in the
# skill listing"). Basis:
# https://code.claude.com/docs/en/skills#frontmatter-reference and the settings
# page; verified 2026-08-31. Recheck trigger: either page moving the default
# re-derives this constant (a script cannot fetch upstream at runtime, so this
# four-part record is the conforming restatement shape per the marketplace's
# upstream-drift convention).
DESC_CHAR_CAP=1536
```
