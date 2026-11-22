# Changelog for the pr-body-convention contract

Notable changes to the PR-body required-sections contract (SemVer). Changing where the sections
come from, a keyword's meaning, or what the pre-create gate requires is a major bump. Adding a
keyword or a consumer is a minor bump. Docs-only clarification is a patch.

## [1.0.0] - 2026-11-22

First versioned contract. The sections come from an explicit `pr_body_required_sections` value in
any layer, else the `##` headings of the repository's own pull request template (`.github/`, the
root, then `docs/`), else those of the owner's default template in its `.github` repository, else
the `briefing` preset; `create` reports the level that supplied them. The keywords `briefing`,
`summary-test-plan` and `none`, and the pre-create gate's presence and non-empty checks, are
unchanged. The pr-unblock body refresh is a consumer.
