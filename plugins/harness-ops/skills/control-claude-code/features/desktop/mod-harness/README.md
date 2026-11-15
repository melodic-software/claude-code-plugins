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

First check the mod has a test that mounts a render site for the Desktop app; without one, record
that and stop this feature.

1. Run `claude plugin test <plugin-dir>`, and save its output and exit status to
   `<run-dir>/desktop-mod-harness.txt`. Result: a line per test naming it and whether it passed,
   such as `(pass) <name>`, then `<n> pass` and `<n> fail`; exit 0 when every test passes, 1 when one fails or the shell cannot load
   mods (a line starting `claude plugin test: hooks modules are turned off`).
2. **Proof.** Result: `<run-dir>/desktop-mod-harness.txt` lists the Desktop render-site test as
   `(pass)`, `0 fail` and exit status 0. Captures: none of `## Capture`'s kinds; the saved test
   output is the evidence

## Gotchas

- A drawing test checks the tree the mod returns for the Desktop app, not how Desktop paints it;
  the evidence is the test output, never a Desktop screenshot.
- What the test kit runs and what a drawing test covers:
  <https://code.claude.com/docs/en/plugins/mods/test#test-a-drawing>.
