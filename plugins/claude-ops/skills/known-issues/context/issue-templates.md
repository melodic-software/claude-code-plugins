# Anthropic issue templates: where to get them

Template structure is owned upstream and changes without notice, so this repo keeps no copy of it.
The `create` action fetches the live template before drafting and stops when it cannot.

Live source: `anthropics/claude-code/.github/ISSUE_TEMPLATE/`.

```bash
gh api repos/anthropics/claude-code/contents/.github/ISSUE_TEMPLATE/<template>.yml --jq '.content' | base64 -d
```

`context/action-create.md` owns the fetch protocol: the type-to-filename mapping, the rule to stop
and tell the user when the fetch fails, and the auto-detection table for the fields the session can
fill without asking.

## Local to this plugin

The regression field has no upstream answer. When the issue reached `create` through
`/claude-ops:known-issues search`, resolve it from the registry's record of the last known working
state instead of asking the user.
