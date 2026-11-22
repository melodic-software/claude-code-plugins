---
bump: minor
---

### Changed

- `create` takes the PR body's sections from an explicit `pr_body_required_sections` setting, else the `##` headings of the repository's own pull request template (`.github/`, the root, then `docs/`), else the owner's default template in its `.github` repository, else the `briefing` preset, and reports which level supplied them.
- `create` writes every run's section prose in the project's glossary terms, through `/domain-driven-design:ubiquitous-language lookup` when that plugin is enabled, else the glossary file.
