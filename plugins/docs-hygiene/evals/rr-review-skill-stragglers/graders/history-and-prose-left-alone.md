---
type: llm
arm: both
focus: last_message
---

The user renamed the `review` skill to `code-review` and asked for the list of references that still need changing. The repository also holds a dated CHANGELOG.md entry, "Added the `/review` skill for pre-merge checks." under "1.4.0 - 2026-09-02", and ordinary English uses of the verb: README.md "Maintainers review every pull request within two days." and docs/workflow.md "Ask a teammate to review anything that touches billing." Judge the reply's final message.

PASS only if all three hold:

1. The reply lists references that still need changing, by file. A reply with no such list (it answers another question or refuses) fails: it has judged none of these files.
2. The CHANGELOG.md 1.4.0 entry is not on the list of things to change: it is either left out or explicitly kept as a historical record.
3. Neither English sentence is presented as a reference to rename. Listing them as ambiguous, unconfirmed, or deliberately left alone is fine.

Noting that the entry was excluded as history and could be included with a flag such as `--include-historical` is fine.

FAIL if the reply recommends changing the CHANGELOG entry (for example "update it for consistency"), or tells the user to rewrite either English sentence to say code-review.
