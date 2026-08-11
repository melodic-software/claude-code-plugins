# AGENTS.md

Orientation for a coding agent working in this repository. It complements the
repository's own `README.md`: the README is written for people (what the
project is, how to build and run it, who owns it), while this file is the
agent-facing companion. Read the README first for repository shape and the
commands that validate a change.

## Synced standards are overwritten, not edited here

This repository's lint, formatting, and repository-hygiene configuration is
synchronized from `melodic-software/standards`. Any file that standards marks
as `managed` for this repository is replaced on the next sync, so a local edit
to such a file is silently lost. When one of them is wrong, fix the cause
upstream in `melodic-software/standards` and let the sync carry the correction
back — never patch the materialized copy here.

## Stage explicit paths

Stage the specific files a change touches. Never `git add -A` or `git add .`:
a blanket stage can sweep in synced, generated, or unrelated files you did not
mean to commit.

## Pull requests

- Title pull requests with [Conventional Commits](https://www.conventionalcommits.org/).
- Resolve every review thread before merging; an unresolved thread marks a
  finding that has not yet been addressed.
