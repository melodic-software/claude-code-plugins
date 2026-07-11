# Snapshots and element refs

The token-efficiency win of the CLI over MCP: snapshots go to disk as YAML, not into context. Read the YAML file directly to locate refs — never dump into context blindly.

## How refs work

After any interaction command, CLI emits a snapshot path:

```bash
$ playwright-cli open https://example.com
### Page
- Page URL: https://example.com/
- Page Title: Example Domain
### Snapshot
- [Snapshot](.playwright-cli/page-2026-04-24T15-39-48-407Z.yml)
```

YAML is an accessibility tree with role-based entries and refs (`e2`, `e37`, `e48`):

```yaml
- generic [ref=e2]:
  - navigation [ref=e3]:
    - link "About" [ref=e4] [cursor=pointer]:
      - /url: https://about.google/
  - search [ref=e26]:
    - combobox "Search" [active] [ref=e37]
    - button "Google Search" [ref=e48] [cursor=pointer]
```

Pass ref to any interaction command: `playwright-cli click e48`, `playwright-cli fill e37 "query"`.

## Snapshot invariants

- **Refs are stable for current snapshot only.** A new navigation or DOM mutation invalidates refs — always take a fresh `snapshot` after anything that changes the page
- **Refs track accessibility roles.** Survives CSS changes, breaks only on semantic HTML changes (which usually indicates a real UI regression)
- **File paths are CWD-relative.** If you `cd` between commands, snapshot dir changes. Prefer running from a stable CWD (worktree root, typically)

## Reading snapshots efficiently

Read the YAML directly with `Read` or `grep`:

```bash
# Find the login button ref
grep -n "Login\|Sign in" .playwright-cli/page-*.yml | tail -3

# Dump just the accessible name of every button
grep -E '^\s*- button "' .playwright-cli/page-*.yml
```

For deep pages, limit snapshot depth:

```bash
playwright-cli snapshot --depth=4            # top-level structure only
playwright-cli snapshot e34                  # partial — subtree under e34
```

## Targeting without refs

CSS selectors and Playwright locators also work when no snapshot is available:

```bash
playwright-cli click "#main > button.submit"
playwright-cli click "getByRole('button', { name: 'Submit' })"
playwright-cli click "getByTestId('submit-button')"
```

**Prefer refs from snapshots** — they're role-based (accessibility-stable) and survive cosmetic CSS changes. CSS selectors are brittle; test-id locators are a middle ground when page has `data-testid` attributes.

## Inspecting attributes not shown in snapshot

`id`, `class`, `data-*`, and computed styles are NOT in the YAML. Use `eval` with a ref:

```bash
playwright-cli eval "el => el.id" e7
playwright-cli eval "el => el.className" e7
playwright-cli eval "el => el.getAttribute('data-testid')" e7
playwright-cli eval "el => el.getAttribute('aria-label')" e7
playwright-cli eval "el => getComputedStyle(el).display" e7
playwright-cli eval "el => el.getBoundingClientRect()" e7
```

## Common pitfall: stale refs

Snapshot, click, interact again without re-snapshotting → old ref may point to a detached element after the click caused a page update:

```bash
playwright-cli snapshot                        # e5 = "Next" button
playwright-cli click e5                        # page advances; DOM updates
playwright-cli click e5   # ❌ may fail or click the wrong thing
playwright-cli snapshot                        # refresh — e5 now means something else
playwright-cli click e5                        # ✓ use the fresh ref
```

**Rule:** re-snapshot after any navigation or state-changing interaction.
