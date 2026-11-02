# Moss documentation: memory

Synthetic source page for the attribution golden set. Moss is a fictional coding assistant
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/moss/docs/memory`.

## Where GUIDE.md differs from MOSS.md

| Behavior | MOSS.md | GUIDE.md read through Project guides |
| :- | :- | :- |
| `GuideLoaded` hooks | Fire | Don't fire, unless a `MOSS.md` imports or links to the file |
| Folders added with `--extra-dir` | Loaded when `MOSS_EXTRA_DIRS_LOAD_GUIDES` is set | Not loaded |
| `@path` imports outside the working folder | Prompt for approval | Load only when external imports were already approved for this project, without asking |

## When Moss reads GUIDE.md

Moss reads the project's top-level `GUIDE.md` at session start. When the Read tool opens a file in a
folder that has its own `GUIDE.md`, that file is attached as well.
