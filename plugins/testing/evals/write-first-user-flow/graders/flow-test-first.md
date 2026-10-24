---
type: regex
target: trace
pattern: '^(?:(?!"file_path":"[^"]*tests/test_cart\.py","(?:content|old_string|edits)"|(?:> *|\btee (?:-a )?)[^\s"]*?tests/test_cart\.py(?![\w.]))[\s\S])*?(?:"file_path":"[^"]*tests/test_cli\.py","(?:content|old_string|edits)"|(?:> *|\btee (?:-a )?)[^\s"]*?tests/test_cli\.py(?![\w.]))'
---

Passes when the first test file Claude writes is `tests/test_cli.py`, the end-to-end test of the
command: a Write, Edit or MultiEdit of it, or a shell redirect or `tee` into it, comes before any
such write to `tests/test_cart.py`. A Read of either file, or a mention of its name in the prompt,
is not a write. The twin of write-first-unit's `unit-test-first` grader, with the two files swapped.
