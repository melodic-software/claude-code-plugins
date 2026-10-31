---
type: llm
arm: both
focus: last_message
---

The user asked for a plan to give their release tagging rules one source of truth and suggested a new file, docs/policies/release-tags.md. The rules are written out in exactly two files, CONTRIBUTING.md ("Release tags") and docs/releasing.md ("Tagging"). Judge the reply's final message.

PASS only if all of these hold:

1. The recommended plan creates no new file for the tagging rules: it declines or argues against docs/policies/release-tags.md (or any other new rule, policy or doc file), at least for now. Saying a shared file could be revisited if a third copy appears is fine.
2. It names one of the two existing files, CONTRIBUTING.md or docs/releasing.md, as the single owner of the rules.
3. The other file's copy is replaced by a pointer to the owner (a link, or a citation of the owner's heading), not kept as a second full statement of the rules. A short one-line summary beside the pointer is fine.

Aligning the owner's wording, or merging the two phrasings into the owner, is fine. Which of the two files becomes the owner does not decide the verdict.

FAIL if the plan creates docs/policies/release-tags.md or any other new file, even as one of two equal options or with caveats; if it keeps both full copies and only aligns their wording; or if it offers options without recommending one.
