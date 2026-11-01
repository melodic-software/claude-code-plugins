---
max_turns: 10
allowed_tools: [Skill, Read, Glob, Grep]
---

Write the README for loglet from my notes below. Its readers are developers on other teams who have never used loglet and are deciding whether to install it on their hosts. Reply with the README in one ````markdown fenced block (four backticks).

```text
- loglet tails app log files and ships every line to the collector
- on restart it resumes from the last checkpoint, so no line ships twice
- checkpoint = byte offset per file, written to /var/lib/loglet/state.json every 5 s
- a rotated file stays in the tail set until loglet reads it to EOF, then loglet drops it
- when the collector answers 429, loglet buffers up to 64 MiB on disk, then drops the oldest lines
- install: apt install loglet; config is /etc/loglet/loglet.toml, key collector_url
```
