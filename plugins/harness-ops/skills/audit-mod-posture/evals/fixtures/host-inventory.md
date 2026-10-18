# Fixture: mod-posture.sh output

The script's TSV, shown as a table; the footer lines follow verbatim.

`# mod-posture inventory 2026-10-17`

| id | tier | enabled | can_disable | hooks | calls | source |
|----|------|---------|-------------|-------|-------|--------|
| watcher@example-market | user | on | yes | session.start,prompt.submit,tool.call | $.fs.read,$.process.run,$.ui.log | validate |
| painter@example-market | user | off | yes | ui.render{component=AbovePrompt},tool.check | $.ui.open | validate |
| clock@example-market | user | on | yes | session.start,ui.render{component=AbovePrompt} | $.clock.every,$.ui.invalidate | validate |
| cc-plugin-diff@builtin | builtin | on | yes | session.start,ui.render,tool.call | unknown | builtin-lane |
| cc-plugin-sec-default@builtin | builtin | on | no | tool.check,session.append | unknown | builtin-lane |

```text
# guard: not-seated (no managed settings; plan pro)
# surface: terminal (2.1.302); the Desktop app bundles its own copy, which may differ: check it by running this skill in a Desktop Code-tab session
# not read: built-in enabled: managed settings and --settings are not read, so on/off is partial
```
