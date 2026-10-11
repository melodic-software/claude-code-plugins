# Review mode

Review reads and reports. It edits no file, proposes no rewritten file as done, and says it changed
nothing.

## Order

1. Run detect with `--config` and find the project's written CSS conventions (stack-discovery.md,
   step 1).
2. Run the bundled linter, `<skill-dir>/scripts/review.mjs`, over the paths under review, unless
   `--no-lint`. Pass the rule ids from `config.values.css.rules.disable` as
   `--config '{"css":{"rules":{"disable":[...]}}}'`; with no ids, `--config '{}'`. Paths and globs
   both work.
3. Read the files for what no linter checks.
4. Report.

## The script's contract

- Output: three sections, `## Findings`, `## Suppressed` and `## Judgment`. Findings and
  Suppressed lines have the shape `path:line [rule-id] message`, and a suppressed line ends with
  its reason. Judgment lines are plain checklist items, plus a `path: not checked` line for each
  file with nothing to lint.
- Exit: 0 no findings, 1 findings, 2 a usage error or a crash. On 2, quote its stderr, say the
  linter did not run, and review by reading.
- It lints `.css` files whole and other files by their `<style>` blocks. A file with neither lands
  under Judgment as not checked.
- It never runs detect: the config it gets is the one you pass.

## The report

Keep the script's three sections in its order, findings before any judgment of your own.

- **Findings**: every finding the linter or your reading found that no project convention
  overrides, as `path:line [rule-id] message`. Name the always-on rule id where one applies.
- **Suppressed**: always present. List each finding a project convention contradicts, as
  `path:line [rule-id] message — reason (project convention: <file>)`; a convention never makes a
  finding disappear. Findings from rules `css.rules.disable` turns off are one line with their
  count, and listed in full with `--show-suppressed`.
- **Judgment**: what no linter checks: `:active` states, sizes that belong in one `clamp()` token,
  `overflow: hidden` on something a script scrolls, scoping problems, invented values where tokens
  exist, and the techniques in the topic references the code could use.

When `project.lint` shows a Stylelint or `@eslint/css` config, name it and the rules that bear on
the findings, and leave its checks to it: never restate its findings as this skill's.

## Without `node`

The script cannot run. Say so, then review by reading against the always-on rules and the topic
references, in the same three sections.
