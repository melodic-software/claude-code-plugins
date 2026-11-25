# Adapter file format

`scripts/adapter-load.awk` loads the test-framework adapter files in `adapters/` for
`cant-fail-scan`, and the testing config layers.

Invocation: `awk -f adapter-load.awk <adapter.yaml>...`

Output, tab-separated, adapters in argument order and keys in file order:
`<id> <tab> <key> <tab> <value>`, one record per scalar and per list item. Nested keys come out
dotted (`detect.any_regex`). An `extends: <id>` adapter inherits every field it does not set from
that adapter.

## The YAML subset

Anything outside the subset exits 2 with `adapter-load: <file>:<line>: <reason>` on stderr.

- `key: value`, `key:` opening a block map or block list, dotted keys
- block list items `- value`, one-line flow lists `[a, 'b']`
- plain or single-quoted scalars (`''` is a literal quote), `#` comments

No double quotes, flow maps, anchors, aliases, tags, block scalars or document markers. A trailing
`\r` is stripped, so CRLF files load, and so is a UTF-8 byte-order mark at the start of a file.

## Fields

Every list field is a list of EREs except `files` and `claim_by_content.files` (basename globs),
`equality.call2` (helper names matched as substrings), `equality.receiver` (`<wrapper>.<matcher>`,
as in `expect.toBe`), `equality.pipeline` (literal matchers after a pipe, as in `Should -Be`; a
space matches any run of blanks) and `rules_off` (rule slugs).

`claim_by_content.files` names more files the adapter claims, each only when its content matches a
`claim_by_content.any_regex`; an adapter sets both or neither.

`language` picks the lexer: `js`, `cs`, `python`, `bash`, `pwsh` or `go`. `block_model` is
`indent` for python, `brace` or `file` for bash (`file`: the whole file is one test, for harnesses
with no per-case marker), and `brace` for the rest. `advisory: true` keeps the adapter's findings
out of the `--check` gate unless `--strict`.

`assertion.calls`, `mock.verify` and `assertion.fail` also count in helpers: a test that calls a
function defined in the same file whose body matches one (or throws, raises or rejects, or calls
such a function) has an assertion. `test_skip` matches the start line (or a decorator or attribute
above it); `body_skip` matches inside the body, as in `t.Skip`. `assertion.idioms` and
`delegation` match raw text, strings and comments included, over a window of three consecutive
body lines, so `echo "FAIL"` then `exit 1` counts.

`assertion.async` matches the start of a statement that asserts nothing unless it is awaited or
returned; `assertion.inert` the start of a statement that looks like an assertion and never
asserts. Both match masked code with its leading blanks removed (for go, an if statement joined
onto one line). `assertion.weak` and `snapshot` match a whole assertion call (strings stand as
`_`), bounded the way `mock.strip` is: a line whose only assertions they cover is a weak or a
snapshot oracle (go: `weak` matches the joined if statement). `assertion.exists` matches, the same
way, a call checking only that one named value exists or has a type; on a value the test
constructed with `new` it checks only that the constructor did not throw. `assertion.count`
matches a length or count check anywhere in a test body, and `assertion.fail` a call that fails
the test outright, which is the assertion of the if or catch around it. `property_markers` match
any raw line of a file whose tests derive expected values on purpose (property-based tests), and
`rules_off` lists rule slugs (`constant-restatement`) the adapter never reports.

Every regex field must use the ERE subset gawk, mawk and BSD awk agree on: no backslash shorthand
classes (s, S, d, D, w, W) or word-boundary escapes (b, B, <, >), no backreferences, and no
`{n,m}` intervals, which mawk 1.3.3 does not implement.

## Extending adapters

`-v EXTEND=<file>` appends `<id> <tab> <field> <tab> <value>` lines to those adapters' list
fields after `extends` is resolved; an unknown id or a field that is not a list exits 2.

## Config mode

`-v MODE=config` parses testing config layers instead, in cascade order, with the same subset
(keys may also hold `-` and `/`) and prints the merged config as `<key> <tab> <value>`: lists
concatenate with the first occurrence kept, and a later layer's scalar overrides.

A layer named `*.md` is a docs convention file: only the body of its one ```` ```yaml ```` config
block is parsed (the opening line is those words at column 0, the body ends at the first line of
three backticks, and lines inside any other fenced block never open one), with errors at the .md
file's own line numbers. Two blocks, or a block never closed, is an error. Before the merged
config it prints `block <tab> <file> <tab> <first body line> <tab> <last body line>` for each .md
layer that holds a block; a .md layer with none contributes nothing.

Keys: `adapters.enable`, `adapters.disable`, `paths.include`, `paths.exclude`, `adapter_dirs`
(lists), `project_kinds` (a list of `<glob>=<kind>`: a C# project whose .csproj path the glob
matches has that kind in `cant-fail-scan.sh`'s findings), `extend.<adapter>.<list field>`
(validated as the adapter field is), and `rules.<rule>: off | warn | error`, where `<rule>` is
`testing/audit/rule-<slug>` or `rule-<slug>` and prints as `rules.<slug>`, or is
`test-weaken-block`, the test-weaken hook's deny switch. A glob starting with `*` must be
single-quoted.

The top-level run-e2e keys `e2e_driver`, `reuse_running_instance`, `browser_driver`, `map_unit`,
`map_entry_points`, `map_report_order`, `file_findings` and `file_findings_floor`, the write keys
`tdd_refactor_step` and `first_test`, and the retired `feature_map_dir` (so a leftover line never
stops a scan) are skipped unread, whatever their value; a nested value skips with its indented
lines and draws one stderr warning naming the file and line. `pixel_tolerance`
(check-visual-parity's map) skips with its indented lines and no warning, since a map is its
expected shape.
