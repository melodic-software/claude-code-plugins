# Desktop through the mod test harness

A mod's drawing in Claude Desktop, checked by the mod's own tests instead of by driving the app.

## Parts

- The mod's tests mount its render sites for the Desktop app and press, type and find in them.
- The run names each test and whether it passed.

## Sub-features

none

## Entry points

- `claude plugin test <plugin-dir>`, run in a shell | driven
- Claude Desktop itself | not driven: terms

## Reset

None: the test kit runs no session and keeps no state.

## Drive

1. Check the mod has a test that mounts a render site for the Desktop app; without one, record
   that and stop this feature.
2. Run `claude plugin test <plugin-dir>`, and save its output and exit status to
   `<run-dir>/desktop-mod-harness.txt`.

## Gotchas

- A drawing test checks the tree the mod returns for the Desktop app, not how Desktop paints it;
  the evidence is the test output, never a Desktop screenshot.
- What the test kit runs and what a drawing test covers:
  <https://code.claude.com/docs/en/plugins/mods/test#test-a-drawing> (as of 2026-10-26; recheck
  when that section changes what `$.ui.mount` checks or which apps a test can draw for).
