# Verify UI with Linux-side Playwright and attach produced demo evidence to PRs

- Status: accepted
- Date: 2026-10-04

## Context

No record decides how an agent in this repository checks a UI change in a browser, how it judges
what it sees, or how it puts proof on a pull request. The skills disagree and leave gaps:

- `/testing:run-e2e` defaults to the Playwright CLI, while the github plugin's browser-automation
  reference tells the agent to prefer Claude in Chrome first.
- No skill shared across the consuming layer tells the agent to inspect the rendered page; only
  `/playwright:playwright` asks for a targeted screenshot read. Nothing runs an accessibility check,
  and nothing publishes binary media to a PR: `git grep -e '--attach'` over `plugins`, `docs` and
  `.github` finds only an unrelated docker flag list (2026-10-04).
- `/playwright:playwright` vendored `@playwright/cli` 0.1.19 when this record was written; the
  latest release was 0.1.22 (2026-09-28), and agent hosts run whatever is installed (this host:
  0.1.21). The vendor baseline has since moved to 0.1.22 (playwright plugin CHANGELOG, as of
  2026-10-07).

The main development host runs Claude Code in WSL2 with NAT networking. Its `.wslconfig` keeps NAT
on purpose because mirrored networking still has Docker Desktop friction.

A research pass on 2026-10-04 covered tool choice, visual-defect detection, PR media, E2E practice,
Playwright upstream drift and demo-video production. Fresh-context verifiers re-fetched the cited
primaries (except a ytyng.com benchmark left unread and an OpenAI post that returned 403) and corrected the synthesis; this record carries the corrected claims. The facts the
decisions rest on:

- **Claude in Chrome and WSL.** Anthropic's docs state Chrome integration "isn't supported in
  Windows Subsystem for Linux (WSL)" ([chrome](https://code.claude.com/docs/en/chrome), fetched
  2026-10-04; still stated as of 2026-10-11). Two comments on
  [anthropics/claude-code#79655](https://github.com/anthropics/claude-code/issues/79655) report
  `claude --chrome` from WSL pairing with Windows Chrome on 2.1.269 and 2.1.278; both say the
  `/chrome` dialog still refuses under WSL. From Chrome 136 the remote-debugging switches are ignored
  on the default profile ([Chrome blog, 2025-03-17](https://developer.chrome.com/blog/remote-debugging-port)),
  so CDP cannot reach the user's signed-in Windows profile either.
- **Headless Chromium in WSL2.** A probe on 2026-10-04 launched Chromium 154 headless with
  `DISPLAY` and `WAYLAND_DISPLAY` unset and rendered a page. Under NAT, Windows is reached at the
  gateway IP, not `127.0.0.1` (probe; [WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking)).
- **CLI against MCP.** Four dated practitioner articles (Better Stack 2026-02-22, TestCollab
  2026-02-12, bug0 2026-06-26, webfuse 2026-09-16) all recommend the CLI for terminal coding agents
  ("most terminal-based coding agent tasks", Better Stack). MCP for long-running agents that hold
  browser state rests on the Microsoft playwright-cli README, Better Stack and webfuse ("most teams
  end up with both"); TestCollab's MCP case is a sandboxed agent without a shell, and bug0 says
  many teams run both. The size of the token advantage is
  contested between sources.
- **Visual checks.** An aria snapshot was identical for a broken and a correct layout in a local
  probe, while geometry assertions caught both. The best model on the DiffSpot spot-the-difference
  benchmark reached 40.7% recall ([arXiv 2605.29615](https://arxiv.org/abs/2605.29615), Gemini
  3.1 Pro); Opus 5.5 and GPT-5.5 are unmeasured. Pixel diffs depend on the rendering environment and detect change, not
  defects. No source measured any layer's catch rate on agent-changed UI.
- **Accessibility automation.** Any single tool leaves 43-86% of failures to manual review,
  depending on the unit counted (Deque by issue volume, report undated; GDS best tool 40% of
  barriers; Roselli 5 of 37 on one site), and GDS found 29% of barriers missed by all ten tools
  combined.
- **PR media.** gh 2.99.0 added `--attach` to `gh issue/pr create/edit/comment`. A live probe on
  2026-10-04 with gh 2.102.0 under the user's OAuth login attached png and mp4 through
  `gh issue create`, `gh pr create` and `gh pr comment`, and png through `gh pr edit`; the rendered HTML showed
  `<img>` with alt text and `<video controls>` in the body and comment. GitHub's changelog of
  2026-09-01 names the OAuth token from `gh auth login` or a classic PAT, and
  [attaching files with GitHub CLI](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)
  requires push access. The upload endpoint rejects `GITHUB_TOKEN` and App installation
  tokens ([cli/cli#14309](https://github.com/cli/cli/issues/14309): a reporter's 404 probe and a
  maintainer's "intended behavior for now", 2026-09-02). GitHub does not play externally hosted
  video ([anonymized URLs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-anonymized-urls)).
  `actions/upload-artifact` v7 uploads a single non-zipped file with no token input, kept 90 days
  by default.
- **Demo video.** The first recording the user saw was rejected for PRs: 800x450, 40.6 s, about
  1.4 s of visible change, the rest agent think-time. Playwright's default scales the viewport to
  fit 800x800 ([videos](https://playwright.dev/docs/videos)). Playwright and playwright-cli give
  chapter cards, action callouts and an animated pointer, but no zoom and no idle trim; the trace
  carries per-action start and end times, click points and frame timestamps (`traceV10`).
  Playwright's CLI video doc tells agents to explore with the CLI first, then record one scripted
  `run-code` pass. Devin's docs describe auto-zoom to clicks and idle compression
  ([testing and recordings](https://docs.devin.ai/work-with-devin/testing-and-recordings)) without
  saying how; Cursor posts videos to PRs but publishes no method. playwright-recast 0.23.0 (MIT)
  was run on the same flow on 2026-10-04: capture and cursor were good, but the auto-zoom aimed at
  the wrong places, cut the camera hard, froze for about 1 s, and exposes no hook to add effects.
  Our own pipeline has had two independent frame-QC rounds so far, both "ship after fixes"; in
  rounds 2 and 3 the producer's self-checks reported defects fixed that the independent review then
  found (crossfade ghosting, a headline clipped at zoom peak, a stale caption).

## Decision

Agents verify UI changes in a Linux-side Playwright browser, check what they see in layers, and put
produced video and screenshots on the PR from the user's own gh login.

1. **Tool rubric.**

   | Situation | Tool |
   |---|---|
   | Default UI self-check from WSL2 | `/playwright:playwright` (`@playwright/cli`) on Linux-side Chromium, headless by default, headed through WSLg on request; NAT stays |
   | Needs a logged-in session | playwright-cli saved auth state or a persistent profile after one login; for the user's real Windows profile, run Claude Code from a Windows shell with Claude in Chrome, or from WSL start `claude --chrome` (next row) |
   | Claude in Chrome from WSL | Works on 2.1.296 via `claude --chrome` through Anthropic's account bridge to a Windows browser, not via `/chrome`; outside documented support; recheck on each release |
   | Deep performance or network debugging | chrome-devtools-mcp against Chrome inside WSL, when configured; playwright-cli console and network for basics |
   | Durable regression | A committed `@playwright/test` spec run in CI |
   | Long-running autonomous exploration | Playwright MCP holding browser state |

   `/playwright:playwright` keeps its distilled skill and syncs to `@playwright/cli` 0.1.22 now.

   Basis: Claude in Chrome WSL note and Chrome 136 blog (both fetched 2026-10-04); headless and NAT
   probes, 2026-10-04; four practitioner articles for CLI first; the Microsoft README, Better Stack
   and webfuse for MCP in long sessions; the chrome-devtools-mcp README ("Key features") and its
   troubleshooting page's WSL section for the debugging row (fetched 2026-10-04); user decision 8
   and the live test of 2026-10-11 (Findings) for the Claude-in-Chrome-from-WSL row; user decisions
   2, 3 and 7. The real-browser row is an inference from the two primaries; the durable
   regression row is judgment.

2. **Visual verification layers**, cheapest deterministic signal first:
   1. accessibility scan (`@axe-core/playwright` with `withTags`);
   2. geometry and style assertions (`toBeInViewport`, `toHaveCSS`, bounding-box overlap, scroll
      against client size) at several viewport widths;
   3. pixel baselines generated and compared in one environment, for screens the change did not
      target;
   4. model vision review of cropped or element-scoped screenshots against a reference and a defect
      checklist, whose findings are leads that a layer 2 check confirms, and where "no issues found"
      is never a pass;
   5. a fresh-context reviewer subagent reading the screenshots;
   6. the evidence attached to the report.

   An aria snapshot is a role, name and text check, not a visual layer. A small in-repo eval of
   planted defects (overlap, clipping, contrast, misalignment) measures what each layer catches.

   Basis: judgment for the order. DiffSpot recall for treating vision output as leads; a single
   local aria and geometry probe (not re-run); Playwright's snapshot docs for environment sensitivity; Anthropic's
   [best practices](https://code.claude.com/docs/en/best-practices) ("show evidence rather than
   asserting success", a verification subagent that "has a fresh model try to refute the result");
   user decision 6 for the eval.

3. **Accessibility automation is necessary, not sufficient.** The axe scan runs in the regression
   suite and as an optional floor in the UI evidence contract when the project has
   `@axe-core/playwright`. A passing scan never stands in for manual WCAG review, which stays a
   separate human step. Basis: the Deque, GDS and Roselli figures above; Playwright's accessibility
   testing page ("automated testing cannot detect all types of WCAG violations").

4. **PR evidence route.** A local session publishes screenshots and video inline with
   `gh pr comment --attach` or `gh pr edit --attach` under the user's own login, on gh 2.99 or
   later. Posting to a pull request still needs whatever confirmation the project requires before
   commenting on one; this decision picks the route, not the consent. CI uploads a non-zipped Actions artifact and comments a link with `GITHUB_TOKEN`, because
   `GITHUB_TOKEN` cannot upload attachments. No new credential is added: no bot PAT goes into CI
   lanes that read untrusted PR text
   ([ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)).
   Basis: the gh v2.99.0 release notes for `--attach` on `gh pr comment` and `gh pr edit`; the
   live `--attach` probe (gh 2.102.0, 2026-10-04), which covered `gh pr edit` with png only;
   cli/cli#14309; upload-artifact README v7.0.1; user decision 4.

5. **Produced demo videos.** A PR demo is recorded in two passes and produced: the agent explores
   unrecorded, then replays a deterministic script at full resolution, and a post-production stage
   adds eased zoom to each action, a drawn cursor and click ripple, captions and a title card, and
   cuts idle time. The stages hand off through a JSON timeline so narration and new overlays can be
   added later. No transition or camera move spans a navigation or a load. An independent
   fresh-context frame review checks every edge of the frame, ghosting and caption overlap before
   anything is posted; the producer's own checks never clear a video. playwright-recast is not
   adopted. Basis: Playwright's CLI video doc (explore first, then script); the 800x800 default;
   `traceV10` fields; Devin's documented auto-zoom and idle compression; the playwright-recast run
   and the two independent QC rounds above, plus the producer self-checks that missed blend and
   edge defects in rounds 2 and 3; user decision 11.

6. **Style and narration are plugin options.** A shipped userConfig option sets the demo style:
   `produced` by default (zoom, cursor, ripple, captions, title card) or `plain` (the same replay
   and cursor, without zoom, captions or title). Each layer (title, camera and zoom, cursor, ripple,
   captions, narration) can be switched on or off through the
   [plugin option naming](../conventions/plugin-option-naming/README.md) and
   [config cascade](../conventions/config-cascade/README.md) conventions. Narration is off by
   default; with it on, the narration text goes through `/speech:narrate` (kokoro by default,
   ElevenLabs only behind that skill's cost gate), which already writes per-word timings. Basis:
   user decisions 5 and 12; `/speech:narrate`'s current behavior.

## Alternatives considered

- **Claude in Chrome as the default browser tool.** Rejected for WSL2: Anthropic documents it as
  unsupported there. The user's live test on 2026-10-11 showed the bridge working on one version,
  which does not make an undocumented path the default.
- **Playwright MCP as the default.** Rejected for short self-checks: all four practitioner sources
  favor the CLI for terminal agents. MCP keeps the long-running row.
- **vercel-labs/agent-browser as the default self-check and logged-in-session tool.** Not adopted
  after a Linux headless benchmark on 2026-10-07 (agent-browser 0.38.2 against `@playwright/cli`
  0.1.22, one shared Chrome 155): 12 agent tasks drawn from the rows above, 5 reps per tool, and
  every one of the 120 trials passed, so the pre-registered reliability rule found no winner. The
  differences were secondary. agent-browser agents used less context per task but more commands and
  more failed commands, and its `console` and `errors` commands never surfaced an uncaught page
  exception that playwright-cli reported in every rep. The benchmark was a one-off and is not kept
  in the repository; the failures its agents hit are the `## Gotchas` of `/playwright:playwright`.
  The WSL2 rows were not measured for agent-browser and will not be, since it was not adopted; the
  logged-in-session probe of playwright-cli's own `attach --extension` is
  [melodic-software/claude-code-plugins#6475](https://github.com/melodic-software/claude-code-plugins/issues/6475).
  Revisit when agent-browser waits on clicks and reports uncaught page exceptions.
- **Mirrored networking, or an SSH tunnel, to drive Windows Chrome over CDP.** Rejected for now:
  NAT stays for Docker Desktop, mirrored mode has an open WSL issue reaching the Windows host over
  TCP ([microsoft/WSL#40343](https://github.com/microsoft/WSL/issues/40343)), and the tunnel is
  documented for VM-to-host Host-header failures, not for WSL.
- **A bot-user classic PAT in CI for inline media.** Rejected: it puts a write credential in lanes
  that read untrusted text.
- **Recording during exploration with default settings.** Rejected by the user: small, slow, mostly
  idle.
- **playwright-recast as the post-production stage.** Rejected after the run above: wrong zoom
  targets, hard camera cuts, freezes, and no extension hook.
- **A Remotion pipeline.** Not adopted: its license requires a company license for for-profit
  organizations above three employees. The in-repo pipeline gives full control with no license
  term, and independent frame QC gates it before anything is posted.
- **Narration on by default.** Rejected: on-screen chapters and captions carry the walkthrough, and
  narration stays one option away.

## Consequences

- `/testing:run-e2e` becomes the home of the rubric, and the github plugin's browser-automation
  reference is rekeyed on "needs the user's authenticated real browser" with the WSL caveat.
  `/verification:confirm` gains a step to read each screenshot against a named visual question, and
  one skill owns the UI evidence contract that is duplicated today.
- `/source-control:pull-request`'s verification section can attach media, which needs gh 2.99 or
  later on PATH on each agent host; this host's default gh is still 2.98.0.
- The free-plan video limit is 10 MB per file, which bounds a demo's length and bitrate.
- Every produced video costs an independent review pass before posting.
- Vision review stays a source of leads until the planted-defect eval measures it; the layer order
  stays judgment until then.

## Findings, 2026-10-11

Probes of the planted-defect eval on the `eval-browser-dispatch` lane (Claude Code 2.1.296,
GitHub-hosted ubuntu-24.04) leave the decision unchanged but constrain how it is measured. Runs are
in `melodic-software/claude-code-plugins` Actions.

- **The eval hides a case's own files from the agent.** `Read` of the case's canary file is refused
  and the browser cannot load it; the `evals-hidden-from-read` and `evals-hidden-from-browser`
  graders pass (runs 38146517909, 38151389439).
- **Narrow Bash grants match as written.** An `--allow-tools` grant such as
  `Bash(playwright-cli -s=* goto *)` produced no permission refusal (run 38146517909).
- **`playwright-cli` cannot run inside `claude plugin eval` Bash on Linux.** Chromium aborts with
  `FATAL:chrome/browser/process_singleton_posix.cc:297] Check failed: . socket() failed: Operation not permitted (1)`
  (run 38150050988): the sandbox's seccomp filter blocks `socket(AF_UNIX)`, and
  the CLI's own daemon also uses a Unix socket on Linux. The eval writes its own sandbox settings;
  plugin evals expose no case key or CLI flag for sandbox network options (plugin-evals docs, as of
  2026-10-11), and a managed `sandbox.network.allowAllUnixSockets: true` policy did not lift the
  block (run 38151389439). Pointers:
  [plugin evals](https://code.claude.com/docs/en/plugin-evals) and the `allowAllUnixSockets` entry
  in the [settings reference](https://code.claude.com/docs/en/settings-reference). As of:
  2026-10-11. Recheck trigger: a Claude Code release that exposes sandbox network options to eval
  runs.
- **`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` breaks every eval Bash call.** With it set, a one-command
  `echo` case fails with
  `bwrap: Can't create file at <tmp>/home/cwd/.eval-artifacts: Read-only file system`; with it `0`, the same case runs (runs 38114987035 and 38118268413). Observed on the
  versions above and not filed upstream.

Consequences: a measured browser eval needs an MCP-driven harness
([#7137](https://github.com/melodic-software/claude-code-plugins/issues/7137)). The rubric's tool
choices stand, and any catch rate or other measured figure states which path, CLI or MCP, it
covers. These runs did not touch Claude in Chrome; the live test below did.

### Claude in Chrome from WSL, live test

Run with the user present on Claude Code 2.1.296, WSL2 kernel 6.18.33.2-microsoft-standard-WSL2
with NAT networking, and Windows Microsoft Edge with the Claude extension signed in to the same
claude.ai account (extension and Edge versions not recorded). Steps 1-6 passed; steps 7 (reconnect
after restart) and 8 (tools absent without `--chrome`) were not run.

- `/chrome` in a plain `claude` session still refuses: "Claude in Chrome is not supported in WSL at
  this time."
- `claude --chrome` opens the setup dialog with no WSL refusal. Its debug log shows native-messaging
  host manifests installed only into Linux-side browser config directories and "Extension not found
  in any browser": the local native-host path finds nothing on WSL.
- No pairing prompt appeared, yet `list_connected_browsers` returned one browser, platform Windows,
  not local: the session reached it through the account-keyed bridge.
- A new tab opened `https://github.com/notifications` in the user's real Windows profile: first the
  login page, then, after the user signed in and Claude reloaded, the "Notifications" page with the
  signed-in avatar.
- A screenshot saved to disk landed inside WSL under `/tmp/claude-chrome-screenshots-*/`, and the
  files exist. Console messages were read (none logged); recording starts at the first request, so
  load-time messages need a reload.

The rubric row now records the path as working on 2.1.296 outside documented support.

## Open items

- **Claude in Chrome from WSL.** Closed 2026-10-11 by the live test above. A pass shows that one
  version works and does not lift Anthropic's documented block, so the rubric row is rechecked on
  each Claude Code release and when the chrome docs page drops its WSL note.
- **Fine-grained PAT with `--attach`.** Untested. gh's client passes fine-grained PATs through to the
  endpoint, while GitHub's changelog names only the OAuth token and classic PAT. Settle with one
  probe on a scratch repository before recommending any token beyond the user's login.
- **SSH tunnel to Windows Chrome.** Withheld. It needs an OpenSSH server on Windows, a security
  decision, and a probe; the docs cover it for VMs, not WSL.

Recheck this record when cli/cli#14309 closes or gh's attachment token allowlist changes, when
`@playwright/cli` or Playwright releases zoom or idle trimming, when Anthropic's chrome page
changes its WSL note, on each Claude Code release for the Claude-in-Chrome-from-WSL row, or when `claude plugin eval` lets a run open Unix sockets.
