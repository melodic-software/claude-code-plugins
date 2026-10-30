---
bump: patch
---

### Fixed

- **A command-file control skill keeps its feature files outside its commands folder** ([#10085](https://github.com/melodic-software/claude-code-plugins/issues/10085)). The control-skill contract's Hub now says where `features/` sits for a control skill shipped as a `control-<app>` command file: in `control-<app>/` beside the top-level commands folder it loads from, `<base>/control-<app>/features/<id>/README.md`, where `<base>` is, for example, `.claude`, a skills-folder plugin's folder or a plugin root. That folder is the command file's base directory, holding its `shared/`, `cli/` and `config/` too. `/app-control:drive` takes that folder as the command file's base directory and resolves features there, never in the commands folder, where every Markdown file loads as a command and several commands would share one `features/` tree.
