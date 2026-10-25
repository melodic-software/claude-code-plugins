---
type: regex
target: trace
pattern: '"file_path":"[^"]*tests/test_cli\.py","(?:content|old_string|edits)"|(?:> *|\btee (?:-a )?)[^\s"]*?tests/test_cli\.py(?![\w.])'
---

Passes when Claude writes `tests/test_cli.py` at some point in the run: with `first_test: unit` the
end-to-end command test still comes before the task is done. A Read of the file, or its name in the
prompt, is not a write. `unit-test-first` checks that it did not come first.
