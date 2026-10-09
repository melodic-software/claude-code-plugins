# Browser sessions

Named sessions isolate cookies, storage, cache, history, and tabs. Use `-s=<name>` on every command in a flow.

## Contents

- [Named session flow](#named-session-flow)
- [Session lifecycle](#session-lifecycle)
- [Implicit session via env](#implicit-session-via-env)
- [Persistent profiles](#persistent-profiles)
- [Attach to a running browser (CDP)](#attach-to-a-running-browser-cdp)
- [Patterns](#patterns)
- [Naming discipline](#naming-discipline)

## Named session flow

```bash
playwright-cli -s=auth    open https://app.example.com/login
playwright-cli -s=public  open https://example.com      # separate browser, separate state
playwright-cli -s=auth    fill e1 "user@example.com"
playwright-cli -s=public  snapshot
```

Each `-s=<name>` is its own daemon-managed browser. Default (unnamed) session is fine for one-off commands but hard to isolate in multi-step flows, so use names.

## Session lifecycle

```bash
playwright-cli list                   # show active sessions
playwright-cli -s=<name> close        # stop one
playwright-cli close-all              # stop every session cleanly
playwright-cli kill-all               # force-kill zombie daemons; also the recovery for socket errors
playwright-cli -s=<name> delete-data  # remove persistent profile data
```

`close-all` and `kill-all` act on every playwright-cli browser on the machine, not just yours. When other agents may be driving browsers at the same time, close your own session by name and keep `kill-all` for recovering from a stuck daemon.

**Always `close` when done.** Zombie browsers consume RAM and hold file locks on persistent profile directory.

If a headless session reports the browser is not open after a pause, run `open` again and redo any in-memory setup. Before a long pause mid-flow, raise the idle limit with `open --idle-timeout=<ms>`.

- **Pointer**: when you need the idle-shutdown default or which sessions it applies to, run `playwright-cli open --help` live; for the change, fetch the [v0.1.20 release notes](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.20). **As of**: 2026-10-04. **Recheck trigger**: the frontmatter `upstream-version` moves.

## Implicit session via env

```bash
export PLAYWRIGHT_CLI_SESSION=todo-app
playwright-cli open https://example.com   # implicit -s=todo-app
```

Useful when an outer script pins session name and inner commands shouldn't repeat it.

## Persistent profiles

By default, profile is in-memory and lost on `close`. Use `--persistent` to save to disk (cookies + storage carry across browser restarts):

```bash
playwright-cli -s=auth open https://app.example.com --persistent
playwright-cli -s=auth close
# ... later ...
playwright-cli -s=auth open https://app.example.com    # still logged in
```

For explicit profile location:

```bash
playwright-cli -s=auth open <url> --profile=/path/to/profile
```

A profile directory admits one running browser at a time, so a second session on it fails. For a login several agents need at once, use the [shared login state](storage-and-auth.md#shared-login-state) instead.

## Attach to a running browser (CDP)

For debugging against an already-open Chrome/Edge:

```bash
# By channel — browser must have remote debugging enabled
# (chrome://inspect → "Allow remote debugging for this browser instance")
playwright-cli attach --cdp=chrome
playwright-cli attach --cdp=msedge

# By explicit CDP endpoint
playwright-cli attach --cdp=http://localhost:9222

# Via Playwright browser extension
playwright-cli attach --extension
```

Supported channels: `chrome`, `chrome-beta`, `chrome-dev`, `chrome-canary`, `msedge`, `msedge-beta`, `msedge-dev`, `msedge-canary`.

## Patterns

**Concurrent scraping**: open N browsers in parallel, then collect:

```bash
playwright-cli -s=site1 open https://site1.com &
playwright-cli -s=site2 open https://site2.com &
playwright-cli -s=site3 open https://site3.com &
wait
playwright-cli -s=site1 snapshot
playwright-cli -s=site2 snapshot
playwright-cli -s=site3 snapshot
playwright-cli close-all
```

**A/B comparison**: two sessions, identical flow, diff screenshots:

```bash
playwright-cli -s=variant-a open "https://app.com?variant=a"
playwright-cli -s=variant-b open "https://app.com?variant=b"
playwright-cli -s=variant-a screenshot --filename=variant-a.png
playwright-cli -s=variant-b screenshot --filename=variant-b.png
```

## Naming discipline

Good: `-s=checkout-flow`, `-s=github-auth`, `-s=dashboard-smoke`.
Bad: `-s=s1`, `-s=test`, `-s=temp`. Generic names collide across worktrees and parallel sessions.
