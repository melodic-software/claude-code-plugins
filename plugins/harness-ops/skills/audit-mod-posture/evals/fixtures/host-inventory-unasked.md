# Fixture: mod-posture.sh output, bypass mode

The script's TSV, shown as a table; the footer lines follow verbatim.

`# mod-posture inventory 2026-11-22`

| id | tier | enabled | can_disable | hooks | calls | source | nouns |
|----|------|---------|-------------|-------|-------|--------|-------|
| runner@example-market | user | on | yes | session.start | $.tool.call,$.mcp.call,$.ui.log | validate | - |
| shaper@example-market | user | on | yes | engine.create | - | validate | add:notes,replace:store |
| idle@example-market | user | off | yes | engine.create | $.mcp.call | validate | withhold:process |

```text
# guard: seated (managed settings present)
# claude-written mods: load-unasked (defaultMode bypassPermissions in user settings; disableSideloadFlags unset)
# surface: terminal (2.1.330); the Desktop app bundles its own copy, which may differ: check it by running this skill in a Desktop Code-tab session
# not read: claude-written mods: --permission-mode, --dangerously-skip-permissions and --settings are not read; managed values come from the managed files only
# not read: built-in tier: built-in mods were not read (no --builtin-json inventory report)
```
