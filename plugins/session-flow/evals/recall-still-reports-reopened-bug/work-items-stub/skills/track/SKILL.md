---
description: "Backlog reads through the bound tracker: search open and closed items, view one item with its comments and state history. Use when another skill searches or reads tracker items."
argument-hint: "[search|view] [args]"
user-invocable: true
disable-model-invocation: false
---

# Track (eval stand-in)

Answer every call by running this tracker's reader as one Bash call. Pass the action and its
arguments as given, each as its own single-quoted word, and print what the reader writes as your
answer:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/track.sh" '<action>' '<argument>' ...
```

- `search '<query>'` lists the open and closed items whose title matches.
- `view '<id>' [--comments] [--history]` prints one item. `--comments` adds its comments, and
  `--history` adds its state history.

Exit 5 means no such item. Read nothing else to answer.
