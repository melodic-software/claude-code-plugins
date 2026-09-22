# Known Claude Code performance issues and fixes

Distilled evidence base for the four-suspect model this skill's report is read against.
Compiled 2026-08-12 from the upstream issue tracker, release notes, and a source-level analysis
of Claude Code v2.1.228. Per the upstream-drift convention: re-verify a row against the linked
source before resting a conclusion on it. The platform moves, and absence from this file is not
evidence of absence. `/claude-ops:known-issues` is the live-search complement.

## Version regressions fixed in 2.1.2xx (suspect 2)

An installation running a version below these carries known, fixed slowness. Capture the version
before any reinstall.

| Fixed in | What it fixed | Why it matters |
|---|---|---|
| v2.1.216 (2026-07-20) | Message-normalization cost grew **quadratically** with conversation turns, causing multi-second stalls in long sessions and slow resumes | The single strongest alternative explanation for "it got slower over weeks" |
| v2.1.208 (2026-07-14) | Per-tool-call CPU with many MCP tools (up to 7x), transcript size (up to 79x in edit-heavy sessions), unbounded file-edit read cache (now 16 MB) | Couples suspect 2 to suspect 3: big fleets hurt far more on older versions |
| v2.1.207 (2026-07-11) | Terminal freezing / keystroke lag while streaming long output; Windows process creation via kernel32 instead of PowerShell | Direct keystroke-lag fix; also removed a per-spawn security-tool trigger on Windows |
| v2.1.203 (2026-07-07) | Per-turn CPU/memory regression (context indicator re-analyzed the whole transcript every turn) | n/a |
| v2.1.221 (2026-08-10) | Fewer event-loop stalls; Windows startup improvement | n/a |

- **The probed binary may not be your daily `claude`.** `cli.version` is whatever
  `shutil.which("claude")` found on the ENGINE PROCESS PATH, which is not the operator's login
  shell PATH, so a version captured here can belong to a binary the operator never runs: a
  project-local `node_modules/.bin/claude`, a second install earlier on PATH, or a leftover under
  `~/.claude/local/`. The report names `probe_path`, `resolved_path`, the containment base it
  tested against, and every `claude` it found on PATH, and raises `cli-probe-project-local` and
  `cli-multiple-on-path` so the ambiguity is visible rather than averaged into a version claim.
  Multiple installs cause version mismatches and unexpected behavior and the install docs say to
  keep exactly one; `which -a claude` (or `where.exe claude`) lists them, and `claude doctor` is
  the first-party authority on which to keep, so both findings route there rather than convicting
  a layout this engine cannot classify.
  ([troubleshoot-install](https://code.claude.com/docs/en/troubleshoot-install), fetched
  2026-09-11; recheck when the install docs publish a binary path for a second install method.)

## Accumulated-state mechanisms confirmed at source level, v2.1.228 (suspect 1)

- **Retention sweep cost is a daily stat-walk of the whole tree.** Fires ~5 s after the first
  launch of the day (24 h sentinel: `.last-cleanup`; defers 10 min while the user was active in
  the last 60 s), then runs ~30 sequential sub-sweeps doing a stat (and past the window, an
  unlink) per file. Async and yielding, so the harm mode is sustained background I/O, amplified
  per-operation by antivirus filter drivers, not a blocked event loop.
- **An unparsable `settings.json` silently pauses the entire sweep.** Nothing is cleaned for as
  long as the error persists; the only surfaces are `/doctor`, `/status`, and this skill's
  `sweep_health`. The tree then grows without bound while looking normal.
- **Never swept, grow forever:** `history.jsonl` (every prompt ever typed) and the home-root
  `~/.claude.json`. The supported shrink lever for the latter is `claude project purge <path>`;
  a community report (Medium, 2026-07) confirmed surgically pruning one project's metadata from
  `~/.claude.json` fully cured an input-lag case.
- **`cleanupPeriodDays` default 30** (minimum 1). Raising it far preserves transcripts by growing
  the live tree, which is the wrong lever for preservation.
- **Resumed mega-sessions:** `--continue`/`--resume` loads the full transcript with no cap, and
  Windows builds force a full-viewport repaint per frame, so per-keystroke render cost scales
  with mounted transcript size. Session hygiene (fresh sessions, `/clear`) bounds it.

## The "nuke ~/.claude" folk remedy: evidence status

Weakly supported. The strongest public testimonial actually pruned `~/.claude.json`, not the
directory; the one tracker report of deleting `projects/` got partial, temporary relief
(anthropics/claude-code#50713). A delete-and-reinstall additionally crosses the version fixes
above, permanently confounding what fixed what. This skill exists so the next incident produces
evidence instead of a ritual.

## Fan-out layer mechanisms (suspect 4)

The layer a slowness audit most often clears every other suspect and then fails to reach. What
follows is measured behavior from one full manual audit on a 24-core Windows 11 workstation
running 10 to 13 concurrent sessions, plus the documented product behavior it rests on. Treat the
absolute numbers as one machine's readings and the SHAPES as the transferable part.

### Per-spawn cost is the denominator, and it moves with load

The same commands, on the same machine, drained and then under a storm of concurrent sessions:

| probe | drained | under storm |
|---|---|---|
| `bash -c 'exit 0'` | 123 ms | 1,144 ms |
| full statusline render | 657 ms | 18,445 to 41,818 ms |
| one `PreToolUse` hook | not sampled | 5,891 to 33,381 ms |

The floors move by roughly an order of magnitude. Any single-state measurement is therefore
misleading, and the wrong conclusion is easy to reach from storm-state numbers alone. The
bimodal signature, a fast mode around 120 to 430 ms alternating with a slow mode around 950 to
1,200 ms across identical no-op spawns, is itself the contention diagnosis rather than noise
around a mean. This is why `fan_out.spawn_cost` reports min, median, and max with the concurrent
process count at sample time, and never a single number.

### Hooks fire in parallel, so their cost is not additive

Eight `PreToolUse` hooks matching `Bash|PowerShell` fired on every Bash or PowerShell tool call,
each invoked as a 3-deep bash chain worth about 24 spawns per tool call. One measured 5,891 to
33,381 ms. Because hooks on an event run in parallel, 51 to 64 were alive simultaneously and
wall-clock cost was roughly the slowest hook plus contention, which matched the observed 60 to
70 s stalls. A naive 8 x 24 s sum predicts about 200 s and is wrong by a factor of three, which
is worse than useless: it fails to match the symptom and discredits the report.

`invocation_shape` detects three shapes. Two cost extra process creations before the hook's own
work begins:

- `Git/bin/bash.exe -c "bash script.sh"`. The `Git/bin/bash.exe` launcher re-execs
  `Git/usr/bin/bash.exe`, so pointing at `usr/bin/bash.exe` directly removes one spawn per hook.
  The re-exec is Git for Windows' own launcher behavior, observed on one Windows host by a
  `Win32_Process` census; Claude Code documents nothing about it and the engine measures nothing.
- Any command line naming two shells. De-forking the hook chain on the audited machine moved the
  median from 10,850 ms to 2,777 ms, roughly 4x, measured back to back at the same load.

The third names a shell the command string cannot show. Claude Code passes a shell-form
`command` (one that OMITS `args`; an explicit `"args": []` is exec form) to a shell before its
first word runs, `sh -c` on macOS and Linux,
Git Bash on Windows, PowerShell when Git Bash is absent, and it runs the statusline command in a
shell the same way ([hooks](https://code.claude.com/docs/en/hooks.md) and
[statusline](https://code.claude.com/docs/en/statusline.md), verified 2026-09-20; recheck when
hooks.md's shell-form paragraph changes, or when either of that statusline page's shell sentences
changes). A shell-form command that then spells a shell of its
own therefore puts at least two shells in the chain, which is
`shell-form-hook-names-a-second-shell`. Exec form, with `args` present, is spawned directly and
has no shell. Two consequences for reading the report: an empty finding list means no row named a
SECOND shell, never that the rows run unwrapped; and the documented floor is a count of shells in
the chain, not of surviving processes, which the engine does not run anything to measure. Which
bash the wrapping shell is on Windows is `fan_out.shell_resolution`.

Per-turn hooks (`Stop`, `SubagentStop`, `UserPromptSubmit`, `Notification`) deserve separate
attention from per-tool-call hooks: 5 of 15 configured hooks were per-turn on the audited
machine, and per-turn cost is what makes a long conversation degrade rather than a single tool
call stall.

### A registered hook row is a ceiling, and three levels decide whether it fires

Counting registered rows answers "how many handlers could fire", which is the number a fleet
audit reaches for and the number that misleads. On the audited fleet, 29 of 33 `PostToolUse`
rows carried an `if` gate, so a write of one file kind spawned a handful of processes rather
than 33. Three independent levels stand between a row and a spawn, and only the first is visible
in a bucket count.

**Level 1, the event key.** The `if` field is documented as
"Only evaluated on tool events: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`,
`PermissionRequest`, and `PermissionDenied`. On other events, a hook with `if` set never runs"
([hooks](https://code.claude.com/docs/en/hooks), common fields, `if`). Those five events are
therefore what per-tool-call means, and a handler carrying an `if` on any other event is dead
configuration rather than a cost. The engine reports those as `if_on_non_tool_event` and counts
them as never firing.

**Level 2, the group matcher**, which is a character class before it is a regex:

| matcher | evaluated as |
|---|---|
| `"*"`, `""`, or omitted | "Match all" |
| only letters, digits, `_`, `-`, spaces, `,`, and `\|` | "Exact string, or list of exact strings separated by `\|` or `,` with optional surrounding whitespace" |
| contains any other character | "JavaScript regular expression, unanchored" |

Source: [hooks](https://code.claude.com/docs/en/hooks), matcher table. Two consequences carry
real fan-out weight. An unanchored regex catches more than it looks like it does, so `Edit.*`
also selects `NotebookEdit`. And an exact string is compared whole, so a bare `mcp__memory`
selects nothing at all: the tool names are `mcp__memory__<tool>`, and server-wide matching needs
`mcp__memory__.*`. The engine's `matcher_matches` uses Python's `re.search` in place of
JavaScript's `RegExp.prototype.test`; both are unanchored, and the substitution is stated in the
report because a JavaScript-only regex construct would evaluate differently here. A matcher
Python cannot compile at all is counted as selecting every tool and listed in
`unclassified_rows` with the compile error, so an unknown selection over-counts where an operator
can see it rather than vanishing.

**Level 3, the handler `if`**, the only level that sees the call's arguments. It "holds exactly
one permission rule. There is no `&&`, `||`, or list syntax for combining rules; to apply
multiple conditions, define a separate hook handler for each" (same page), which is why a
formatter that covers six extensions carries six rows rather than one. A non-match costs nothing
at all: "the hook process only spawns when the tool call matches"
([hooks-guide](https://code.claude.com/docs/en/hooks-guide)).

The engine classifies exactly one `if` shape, `Edit(*.<ext>)`, and reports every other shape in
`unclassified_rows` with the reason, counting it as firing. That direction is deliberate: an
unmodelled rule inflates the projection, which an operator can investigate, where the opposite
would hide a spawn nobody goes looking for. The file kinds projected are a fixed baseline plus
every extension a classified gate names, so a gate on a kind outside the baseline gets its own
row and `other` means a file no gate names.

**Drift record.** *Claim:* an `Edit(*.<ext>)` `if` rule is evaluated by file extension for all
three file-writing tools, `Write`, `Edit`, and `NotebookEdit`, so a `Write` of `notes.md` fires a
handler gated `Edit(*.md)`. *Basis:* the hooks reference documents `"Edit(*.ts)"` as an example
`if` value and points at permission-rule syntax, but never names the input field the pattern is
tested against nor the tool set it covers; the permissions reference resolves the tool set from
the other side, "Claude Code checks file permissions against `Edit(path)` and `Read(path)` rules
only. If you write a path rule for `Write`, `NotebookEdit`, `Glob`, or the legacy `MultiEdit`
tool instead, Claude Code accepts the rule but never consults it ... Use `Edit(docs/**)` in place
of `Write(docs/**)`" ([permissions](https://code.claude.com/docs/en/permissions), file-path
rules); the [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) at
2.1.176 records "Fixed hook `if` conditions for Read/Edit/Write tool paths: documented patterns
like `Edit(src/**)`, `Read(~/.ssh/**)`, and `Read(.env)` now match correctly", which is the
closest upstream statement that a file-tool path is what the rule sees; and this repository's own
hook-budget convention already rests on the premise, since the formatter plugins carry one
`if: Edit(*.ext)` row per extension so that a `Write` to any other file spawns nothing.
*As of:* 2026-09-11. *Recheck trigger:* a hooks-reference revision that names the input field or
the tool set for file-tool `if` rules, which would make the premise citable directly instead of
assembled from three pages.

Two things the projection cannot model, both over-counts rather than hidden spawns. An `if` rule
matches only under its anchor, so an edit to a file outside the project directory never matches
one and every gated row there is counted as firing when none of them is. And dedup is modeled
nowhere: "If you define the same handler in more than one settings file, it runs once. A plugin's
or skill's copy of the same handler stays separate" (hooks), so rows that collapse upstream are
counted twice here.

### Configuration on disk is not configuration in force

Plugin enablement is read AT STARTUP. On the audited machine a plugin was disabled in
`settings.json` at 13:53:02 while the newest of 13 running sessions had started at 13:44:59, so
no running session had picked the toggle up and 51 of that plugin's hook processes were still
live. Reading config off disk and describing it as the running state produces a confidently
incorrect report, in this case "that plugin is disabled, so it is not the cause" while it was
exactly the cause. This generalizes to every settings change, which is why `fan_out.config_liveness`
compares the settings mtime against each session process's start time and says plainly when a
restart is required.

### Concurrency ceilings multiply

| variable | documented default | note |
|---|---|---|
| [`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`](https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit) | 20 per session | at 10 sessions that is a 200-subagent ceiling, each carrying the same statusline and hook fan-out |
| [`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents) | 3 | depth multiplies against the concurrency ceiling |
| `CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS` | undocumented | absent from [env-vars.md](https://code.claude.com/docs/en/env-vars) but present in the shipped binary, gating background observer agents and a per-subagent observer fan-out |

**The truthiness trap.** These flags are gated by a JavaScript truthiness test on the raw string
(`if (!process.env.CLAUDE_CODE_...) return false`), and in JavaScript the string `"0"` is TRUTHY.
Setting one to `0` reads like a disable in a settings file and is a silent no-op; only removing
the variable disables it. Any advisory that says "set it to 0" is actively wrong. Re-verify the
gating shape against the shipped binary before resting a conclusion on it.

The engine reports these three against their documented defaults and flags one that is set but
undocumented upstream. It deliberately does NOT cross-check env keys against a strings scan of
the shipped binary: that capability lives in `/claude-ops:inventory`'s extractor, and reaching
into another skill's private surface to borrow it would breach the encapsulation convention. An
operator who wants that check runs that skill.

### Orphan attribution needs parent liveness, not age

Of 14 `conhost.exe` processes over 24 h old on the audited machine, 12 had LIVE parents (device
managers, a console host chain, a monitoring service); killing them would have broken running
software. Exactly one was a true orphan, alongside one 6.2-day `bash.exe` still running a
statusline script from a plugin version that had since been replaced. Age alone would have
convicted all 14.

Population trend matters as much as population size, and needs two samples: `conhost` went 34 to
44 to 49 (mild accumulation) while `bash` went 153 to 137 to 93 to 134 to 112, which is CHURN,
not accumulation. A single sample cannot tell the two apart, and the first reading of that bash
series was written up as accumulation and had to be retracted.

### Kernel threads are not workload, and only PF_KTHREAD identifies them

`ps -e` lists the kernel's own threads alongside user processes, and a kworker renames its `comm`
as it moves between queues, so a population keyed on name sees the same worker arrive under a new
name every few seconds and reads it as accumulation. On Linux the engine classifies the
shortlist's processes and drops a row whose every process, all of them examined, is a kernel thread, walking the ranked rows until ten survive so kernel threads at the top never crowd out user-space rows.

The classifier is the kernel's own predicate, `PF_KTHREAD`, read two ways: the `Kthread:` line of
`/proc/<pid>/status` where the kernel publishes one, else bit `0x00200000` of the task flags word,
field 9 of `/proc/<pid>/stat`. Field 2 of `stat` is the command in parentheses and may itself
contain spaces and `)`, so the split runs from the LAST `)`.

Three classifiers that look equivalent and are not:

- **Parent pid 2.** The kernel reparents user-space helpers (modprobe, coredump helpers, udev
  helpers) onto kthreadd with `CLONE_PARENT`, and those helpers carry no `PF_KTHREAD`, so the test
  convicts user processes. kthreadd itself has parent pid 0, so the test also misses the one
  process it most obviously should catch.
- **An empty `cmdline`.** A zombie reads zero bytes, and a process can rewrite or relocate its own
  argument region, so absence proves nothing about who created the task.
- **Bracketed names in `ps` output.** Brackets mean only that arguments were unavailable, which is
  the same empty-`cmdline` signal one layer up.

The accepted failure mode is under-exclusion, never over-exclusion. A reparented helper counts as
a user process, which is correct by definition, and a renumbered flag bit would classify every
kernel thread as user-space and raise the accumulation verdict spuriously. Both surface as an
investigable false alarm rather than hiding a real user-space leak, which is why an unparsable or
vanished process classifies as user-space too.

**Drift record.** *Claim:* `PF_KTHREAD` is `0x00200000` and is exposed unmasked as field 9 of
`/proc/<pid>/stat`; `/proc/<pid>/status` carries a derived `Kthread:` line on kernels that publish
one. *Basis:* [proc_pid_stat(5)](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html) for
the flags field and the parenthesized `comm` hazard,
[Documentation/filesystems/proc.rst](https://www.kernel.org/doc/html/latest/filesystems/proc.html)
for the `Kthread:` line, `include/linux/sched.h` for the bit value, and `kernel/umh.c`
(`call_usermodehelper_exec_work`) for the `CLONE_PARENT` reparenting that refutes the ppid test.
*As of:* 2026-09-11. *Recheck trigger:* a kernel release that renumbers `PF_KTHREAD`, or man-pages
documenting `Kthread:` in `proc_pid_status(5)`, which would make the status line the citable
primary and retire the stat fallback's role as the documented path.

## The host-level floor: a kernel Token-object leak (suspect 5, Windows)

Beneath the four suspects sits the floor the host itself imposes on every process creation, and
one mechanism moves it by an order of magnitude while staying invisible to everything above: a
leaked kernel reference to Token objects. Measured once, on a 24-core Windows 11 workstation
(Intel Core Ultra 9 285K, 64 GB) at two days' uptime with 6 to 7% CPU and 26 to 30 GB free, then
again two hours after a reboot (capture record: melodic-software/claude-code-plugins#3715):

| probe | leaking (2 d uptime) | after reboot (1 h 57 min uptime) |
|---|---|---|
| `cmd /c exit 0`, absolute path, no window | 1,339 to 1,573 ms | 14 ms |
| `bash -c true` (Git Bash) | 3,555 to 4,347 ms | not re-sampled |
| kernel-side half of one `cmd.exe` creation (`CREATE_SUSPENDED`, then resume) | 668 ms | |
| Token objects alive (`NtQueryObject`, `ObjectTypesInformation`) | 3,811,482 (high-water equal, 1,739 handles) | 25,623 (1,373 handles) |
| paged pool | 9,894 MB | 1,092 MB |
| `claude --version` | 4,113 ms | |

The shape, not the numbers, is the transferable part:

- **The cost is inside process creation itself.** Splitting one creation with `CREATE_SUSPENDED`
  put 668 ms in the kernel-side create and 683 ms in resume-to-exit; the kernel half alone was
  three times the whole healthy spawn. DLL loading, PATH search (36 entries, longest probe 14 ms),
  the console layer, and desktop-heap limits were all measured and cleared.
- **Millions of Token objects against a few thousand handles is the signature.** A Token object
  that outlives every handle to it is alive only through a kernel reference, so `objects` minus
  `handles` in the millions with high-water equal to current means references are taken and never
  released. The type's default paged-pool charge is 88 bytes, but a live token carries its groups,
  privileges, and SIDs, and at a realistic 2 to 3 KB each 3.8M of them account for the 10 GB.
  Paged-pool pressure is what every creation then pays.
- **The minter is process creation, and only for some binaries.** Twenty back-to-back
  `cmd /c exit` spawns did not raise the rate above background, which reads as a continuous minter
  until the same test is run against other binaries. A census-burst-census probe on the reference
  host on 2026-09-14 (the engine's `kernel_objects` count before and after N spawns through
  `subprocess.run`, quiet host, background near 0/s) found the leak tracks process creation, per
  binary, in leaked Token objects per spawn: `pwsh.exe` (PowerShell 7.6, Microsoft Store package)
  at 10.2 (n=60), Git `usr\bin\bash.exe` at 1.5 (n=200), Windows PowerShell 5 at 0.5 (n=60),
  `node.exe` at 0.3 (n=100), `python3.exe` and `cmd.exe` at about 0 (n=100, n=300). A 1-per-minute
  sampler tracked it live: 3 to 7/s during the bursts, about 0 when the host was idle. So the
  `cmd` result was a null on a non-minting binary,
  not evidence of a continuous minter, and the consequence for a Claude Code host is that the leak
  is proportional to how many shell processes its hooks and tools spawn. Every spawn-reduction
  measure in this reference also reduces the leak rate.
- **The per-package pwsh ordering is NOT established, and swapping PowerShell packages is not a
  recommendation.** A later background-corrected A/B on the same host (150 spawns per arm, two
  rounds, other sessions active, background 1.5 to 7.1/s) put the portable-zip pwsh at 7.1 per
  spawn and the Store-package pwsh at 0.84, the reverse of the quiet-window ordering above. At
  that noise level the per-package figure is not separable from background, so the 10.2-per-spawn
  pwsh number above is an ordering the second run contradicts. What both runs agree on is the coarse
  split: creating bash or pwsh processes mints leaked tokens, creating cmd or python processes
  does not. Do not act on the per-package difference.
- **Reboot restores the floor; the leak re-arms immediately.** The table's sample is the
  calibration basis (25,623 live Token objects at 1 h 57 min, 3.65 per uptime second). Four
  minutes later, at 2 h 01 min, the count was 37,144, 11,500 more, and the ratio 5.1/s; at 2 h
  10 min it was 70,380 at 8.9/s. A 60 s window in the same span read 15/s and a 3 s window read
  0/s: minting is bursty, so a short window under-reads it. At those ratios the count re-crosses
  the engine's 250,000 threshold in well under a day and the two-day level returns in days, not
  weeks. A reboot buys time; only attribution ends it. Note one gap this bullet and the per-binary
  result above do not close between them: these post-reboot samples do not record what the host
  was doing, so whether the 15/s window was spawn-driven or genuinely bursty at rest is unknown,
  and the two explanations are not reconciled here.

### Who has attributed this, and on what evidence

Three public attributions for this signature exist and none of them is settled. They are recorded
with their provenance rather than adopted, because the reader's host may match any of them or
none.

- **Host NTFS, stated by a Microsoft maintainer, on a WSL2 host.** On
  [microsoft/WSL#40804](https://github.com/microsoft/WSL/issues/40804), an `ntfs.sys` `NtFC`
  non-paged pool leak reported at about 21 GB/hr under WSL2 on Windows 11 26200.x, `benhillis`
  (author association MEMBER) wrote on 2026-06-17 that "This is definitively a host-NTFS kernel
  bug, not a WSL issue", and closed the issue as `not_planned` after routing it to the NTFS owner.
  Note the tag: that thread measures `NtFC`, not `Toke`. It is evidence about the same family of
  retention bug, not a statement about Token objects.
- **A filter above NTFS, contested in that thread by a non-maintainer.** On 2026-09-02 `Silex`
  (author association NONE) argued in the same thread that `wcifs.sys` sits above NTFS at altitude
  189900, so a minifilter holding a stream context prevents NTFS freeing the FCB and the `NtFC`
  growth is a consequence rather than a failure in the NTFS free path. No maintainer has replied
  to that contest. The supporting numbers are on
  [anthropics/claude-code#91265](https://github.com/anthropics/claude-code/issues/91265), whose
  reporter runs Claude Desktop v1.40609.0.0 and measured `Toke` at 2,719,886 live objects and
  4,975 MB beside `File` at 6,644,575 and `SeAt` at 10,855,380. `Silex` posted the supporting
  table there: at 7 minutes of cold-boot uptime `WCsc` and `WCfc` at 0.0% freed, `WCse` and
  `WCss` at 3.2%, while
  `WCfn` was 100.0% freed and `WCce` and `WCrb` 99.8%. A cold-boot A/B on the Cowork VM service
  put it at roughly an 8x amplifier rather than the cause: 6,822 leaked `WCsc` contexts in the
  first four minutes with the service on Automatic against 874 with it Disabled.
- **A win32k foreground-launch check, traced on one machine.** On 2026-09-08 `bentoner` wrote on
  [openai/codex#30926](https://github.com/openai/codex/issues/30926#issuecomment-5588760289) that
  "`win32kfull!CForegroundLaunch::_CheckAllowForeground` references the parent's primary token and
  never releases it, so each process that creates a process leaves a `Toke` object behind", from
  "kernel object reference tracing on one box" on build 26200.9106. The write-up at
  [bentoner/windows-token-leak](https://github.com/bentoner/windows-token-leak) says on its face
  "Everything here was measured on one machine", reports "1,644 tokens over 3,542 iterations" in
  two MSYS loops against a delta of 7 in two native `cmd` loops, and names the precondition: the
  check reaches the token only while the foreground lock is armed, which is while input arrived
  within the last `ForegroundLockTimeout` ms (Windows default 200000). Its reported workaround is
  `ForegroundLockTimeout` = 0, per-user, no elevation, with the documented side effect that any
  application may take the foreground. Its author's association on that comment is NONE, the same
  as `Silex`'s; neither is a maintainer of the repository they posted in.

  This is the only one of the three that is per-spawn at all, which is the shape the reference
  host measured. Do not read that as a match. The same write-up says native creators such as
  `cmd.exe` also leak while the lock is armed, and that at a timeout of 2147483647 or with input
  arriving, every creator it tested leaks at about one token each; the reference host's own top
  minter was `pwsh.exe`, which is not MSYS. It also says plainly that `Toke` growth driven by
  `wcifs.sys` file contexts under WSL2 is **a different leak**, not a rival explanation of this
  one. So these are two candidate leaks that can both be present, and the runbook samples for
  each rather than choosing between them.

**What the reference host measured against those.** The per-binary spawn numbers above are one
host's, dated, unreplicated. A livekd `!poolused 2` dump there on 2026-09-14 at 2 d 20 h uptime
and 1.54M live Token objects put `Toke` at 2,850 MB paged, `SeAt` 592 MB, `SeTd` 221 MB, `SeTl`
197 MB nonpaged at the same 1,535,735 allocation count as `Toke`, `FMfn` (fltmgr name cache)
1,286 MB, Defender `MPsc` and `MPhc` 318 MB, and **every `WC*` (wcifs) tag under 1 KB**. So the
wcifs attribution does not hold on that host, although it runs WSL2 and loads the same filter.
Separately, on the host of the 2026-09-18 attribution runs, `SPI_GETFOREGROUNDLOCKTIMEOUT` read
2,147,483,647 ms live while `HKCU\Control Panel\Desktop\ForegroundLockTimeout` held the 200,000
default, which is the always-armed precondition the foreground-lock write-up names. What set it is
unknown, and the A/B that would confirm the mechanism there is written and has not been run.

**Four service arms came back NO CANDIDATE.** On 2026-09-18 the elevated runbook below was run
four times over the NVIDIA display container, Razer Game Manager, THX spatial audio and Wispr
Flow, covering them singly and in combination. Every arm read 16.8 to 18.7 tokens/s and 0.46 to
0.49 Token objects per shell spawn at flat driver-only load. A bare `bash -c true` loop with no
Claude Code activity leaked at that rate and an idle host leaked nothing. No candidate dropped the
rate, so the elevated sweep is not where the cheap answer lives. Worth noting against the public
reports: `bentoner`'s reference run works out to 0.464 leaked tokens per creator, which lands
inside that 0.46 to 0.49 band on a different machine. That is a cross-host agreement on the
per-spawn constant, not a confirmation of the mechanism.

**The ASUS raw-I/O drivers are cleared on the reference host by falsification, not by stopping a
service.** Three raw-I/O drivers polled continuously by Armoury Crate and lighting services
(`AsIO3.sys`, `IOMap64.sys`, `MsIo64.sys`) fit the profile of a continuous minter and are the
obvious suspects on an ASUS workstation. Nobody stopped them. What clears them is the spawn census
above: an idle host leaks about nothing and the rate follows spawn count, which is not the shape a
continuously polled driver produces. The list is recorded so nobody re-derives it.

**Drift record.** *Claim:* three public attributions exist for this signature and none is settled:
a Microsoft MEMBER's host-NTFS statement on `microsoft/WSL#40804` (measuring `NtFC`), a
non-maintainer's `wcifs.sys` contest in that same thread with supporting `WC*` freed-rate numbers
on `anthropics/claude-code#91265` (a Claude Desktop host), and `bentoner`'s
`win32kfull!CForegroundLaunch::_CheckAllowForeground` trace on one machine at build 26200.9106.
*Basis:* read through the GitHub REST API on 2026-09-22, untruncated: full issue bodies and
complete comment lists for `microsoft/WSL#40804` and `anthropics/claude-code#91265`, the single
cited comment (id 5588760289) for `openai/codex#30926` rather than that whole thread, plus the
`bentoner/windows-token-leak` README. Quoted spans are verbatim from those bodies except where a
quotation is visibly clipped to its first clause. *As of:* 2026-09-22. *Recheck
trigger:* `microsoft/WSL#40804` reopens or a maintainer answers the `wcifs.sys` contest (it is
closed `not_planned` and both threads were last active 2026-09-02); `anthropics/claude-code#91265`
gains a maintainer verdict; a second machine reproduces or refutes the foreground-lock trace; or a
Windows build later than 26200.9106 changes the per-spawn rate.

**Drift record.** *Claim:* on the reference host the leak is minted per process creation and only
by some binaries (bash and pwsh mint, cmd and python do not), and every `WC*` tag there sits under
1 KB; on the host of the 2026-09-18 runs four service arms came back NO CANDIDATE and the live
foreground-lock timeout read 2,147,483,647 ms. *Basis:* the engine's `kernel_objects` census taken
before and after N `subprocess.run` spawns per binary plus a 1-per-minute sampler (2026-09-14), a
livekd `!poolused 2` dump at 2 d 20 h uptime (2026-09-14), and four elevated stop-and-resample
runs plus one `SPI_GETFOREGROUNDLOCKTIMEOUT` read (2026-09-18). One host each, unreplicated, and
the two dates are not established to be the same machine. The two per-spawn rates are also not
reconciled: bash read 1.5 per spawn on 2026-09-14 and 0.46 to 0.49 on 2026-09-18, and nothing here
explains the gap. *As of:* 2026-09-18. *Recheck trigger:* a second host runs the same per-binary
census, or the foreground-lock A/B named in step 2 of the runbook is run on either host. Either
replaces a one-host number with a comparison.

The engine reports this as `kernel_objects`: live and high-water counts per type, paged and
nonpaged pool, system handle/process/thread totals, `token.objects_per_uptime_second`,
`token.hours_to_leak_threshold_at_uptime_ratio`, and the findings `token-objects-leaked` (at or
above 250,000 live Token objects) and `paged-pool-high` (at or above 4,096 MB). The ratio is live
objects divided by uptime, not a measured mint rate: it includes whatever population the boot
started with, so it overstates the rate early in a boot and the projection errs short, and it
cannot see tokens created and destroyed in between; it is reported anyway because it needs no
sleep and, per the bullet above, any in-run delta short enough for an engine pass under-reads.
Its error shrinks as uptime grows, and the 60 s sample in the runbook below is the mint-rate
measurement, which the runbook takes under a fixed spawn load rather than at rest. The two findings are not one verdict: `token-objects-leaked` alone carries
`state_label: token-leak`, while `paged-pool-high` alone labels `paged-pool-high`, because
`GetPerformanceInfo` reports aggregate pool with no attribution and only `poolmon` can say what
charged it. Both thresholds are calibrated on this one host's two states, ten times its
clean-boot count and a fifteenth of its leaking count. A second host's readings, healthy or
leaking, are the recheck trigger for them.

### Attribution runbook (the engine never does this)

The capture a reboot destroys comes first; after that the order is by cost, not by likelihood.

1. **Before any reboot of a leaking host, capture the pool tag.** It is the one measurement a
   reboot destroys, and it was missed on this host. `poolmon` runs elevated and its switches are
   slash-prefixed; no dash-prefixed form is documented, so `poolmon -b` is not an invocation.
   Start it with the tag table, so each allocation carries an owner:

   ```
   poolmon /g "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\triage\pooltag.txt"
   ```

   `/g [PoolTagFile]` "Adds a column to the display (Mapped_Driver) listing Windows components and
   commonly used drivers that assign each tag". While it runs, `p` "Toggles
   the display through nonpaged allocations, paged allocations, and both" and `b` "Sorts by bytes
   used"; `/b` does the same sort from the command line. `/i` "Displays only the allocations with
   the specified pool tag", with no space between the `i` and the tag and wildcards allowed, so
   `poolmon /iWC*` and `poolmon /iToke` narrow the capture. **Sample the `WC*` tags alongside
   `Toke` first**: the wcifs retention and the foreground-launch leak are two different leaks that
   a host can carry at once, and only that pairing tells you which one you have. It is what the
   reference host's dump did to rule wcifs out there. Snapshot, repeat every 30 minutes,
   and diff. A tag whose allocation count climbs while its free count does not is the leak; expect
   `Toke` to dominate paged pool. Process Explorer's kernel-memory view is the fallback when
   poolmon is unavailable, but it carries no `Mapped_Driver` column.
2. **Unelevated: the foreground-lock check.** Minutes, no elevation, no service stopped. Read the
   live timeout with `SystemParametersInfo(SPI_GETFOREGROUNDLOCKTIMEOUT)` rather than the
   registry: the two disagreed on the 2026-09-18 host, where the live value was 2,147,483,647 ms
   against a registry holding the 200,000 default, and only the live value says whether the lock
   is armed. Then run a spawn loop of an MSYS `bash` with a Token census before and after, once at
   the current value and once at 0, restoring the original afterwards. A rate that collapses at 0
   is the signature the published trace predicts.

   Two preconditions from the same write-up, and skipping either makes the arm unreadable. First,
   **the set call is refused while the lock is armed**: win32k returns Win32 error 87
   (`ERROR_INVALID_PARAMETER`) unless the caller may force the foreground, so the write-up says to
   run it on an idle box, from an existing console, and not within 200 s of any input. A host
   reading a live timeout of 2,147,483,647 ms stays armed about 24.9 days after any input, which
   is very likely why the A/B on the 2026-09-18 host is written and has never been run. Second,
   **take a settled delta**: wait about 60 s after the burst for the kernel's deferred reclaim and
   subtract an idle baseline, or the before/after census over-reads.

   **This is one machine's trace pending a second host**: `bentoner`'s write-up states its own
   single-machine scope. Ranked above the service arms because it is cheap, not because it is the
   likeliest answer.
3. **Elevated: the service arms.** Sample the Token count over 60 s, and sample it **under a fixed
   spawn load, never idle**. The per-binary result above says an idle host leaks about nothing, so
   an idle 60 s window reads near zero with nothing stopped and discriminates nothing; an arm run
   that way clears every candidate for free. Drive a steady loop of MSYS `bash -c true` spawns for
   the whole window, then stop one candidate service at a time and re-sample the same loop at the
   same spawn count; the arm that drops the rate toward zero is the minter, and every stopped
   service is restarted afterwards. That loaded 60 s window is the manual mint-rate measurement
   the engine's `kernel_objects` basis string points at. Candidates on the audited host, in order:
   `ArmouryCrateService`, `LightingService` (Aura), `ROG Live Service`, `AsusFanControlService`,
   `AsusUpdateCheck`, `asComSvc`, then the Razer Chroma SDK services, NVIDIA's
   `NvContainerLocalSystem`, and Wispr Flow. The four arms named above came back NO CANDIDATE, but
   only two of them, `NvContainerLocalSystem` and Wispr Flow, are on this list: Razer Game Manager
   is not the Chroma SDK services, and THX spatial audio does not appear here at all. Budget
   accordingly.
   Add the components that load `wcifs.sys`, since that filter is what the
   public reports implicate: **WSL2, Docker Desktop and Windows Sandbox**, alongside Claude
   Desktop's Cowork VM. Growth that persists with all of them stopped points at a Windows
   component; on an Entra-joined account the CloudAP token path is the next suspect.

**Drift record.** *Claim:* every documented `poolmon` switch is slash-prefixed and none is
dash-prefixed; `/g [PoolTagFile]` adds the `Mapped_Driver` column, `/i` filters to a tag with no
intervening space, and `/b` sorts tags by bytes used; at run time `p` toggles pool type and `b`
sorts by bytes used. *Basis:* Microsoft Learn
[PoolMon Startup Command](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/poolmon-startup-command)
for the syntax line and the `/g`, `/i` and `/b` rows,
[PoolMon Run-time Commands](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/poolmon-run-time-commands)
for `p` and `b`, and
[PoolMon Examples](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/poolmon-examples)
for the wildcard form (`poolmon /iAfd*` there); all three fetched live on 2026-09-22, each
arriving whole with its own first heading checked, and the quoted spans copied from them. *As of:* 2026-09-22. *Recheck trigger:* either
page adds or removes a switch or run-time key this step names, or a dash-prefixed form appears in
the documented syntax. Only the `devtest` pages are cited: Learn also carries a condensed poolmon
key table under `debugger/` that was not read for this record, so nothing here rests on it.

Also cleared on that host, recorded so nobody re-derives them: session churn (suspending the four
busiest orphaned shells moved the floor 15%, so they were victims, not cause); an unrelated
174,378-handle registry-key leak in ASUS `ADU.exe` (suspending it changed nothing); antivirus and
EDR (Defender stopped, `WdFilter` not loaded, no third-party minifilter); WDAC, Smart App Control,
AppLocker, and AppInit DLLs (all off or empty); and tracing sessions (none running).

## Tested and cleared (record the negatives)

A plausible cause ruled out by measurement is a finding. All four of these looked right on the
audited machine and all four were wrong; without the record, the next operator re-derives them.

- **Antivirus.** The `WdFilter` minifilter was Stopped, `WinDefend` and `Sense` were stopped,
  `MsMpEng` was not running, and `DisableAntiVirus` was 1. The Windows Defender guidance this
  skill emits would have pointed at a cause that did not exist. Note that `Get-MpComputerStatus`
  throwing *Provider load failure* is a symptom of Defender being DISABLED, not evidence of it
  scanning.
- **Third-party EDR.** None present; only stock minifilters (`bindflt`, `CldFlt`, `FileInfo`,
  `luafv`, `storqosflt`, `wcifs`).
- **Filesystem.** The repository volume was ReFS on a VHDX and measured FASTER per file than the
  NTFS system drive (`git status` floor 1,955 ms over 7,238 files versus 1,105 ms over 2,055;
  enumeration 50 ms versus 57 ms). This was asserted as a cause before it was tested, and the
  test refuted it.
- **MSYS and Git Bash.** `bash.exe` floored at 123 ms, faster than `cmd.exe` at 206 ms and
  `pwsh.exe` at 267 ms. Another hypothesis that looked right and was false.

## Measurement method

1. **Use a monotonic in-process clock.** The engine's `perf_counter` is correct. Do NOT shell out
   to `date` around a command: `s=$(date +%s%N); cmd; e=$(date +%s%N)` puts a fork INSIDE the
   measured interval and inflated readings by 1 to 3 s on the loaded machine.
2. **Bracket, never single-sample.** Report min, median, and max with the concurrent process load
   at sample time.
3. **Verify config is live before attributing cost to it.**
4. **Rule out by test, then record the negative.**
5. **Prove a fix with a before and after under identical load.**
6. **Take the host floor before attributing anything to Claude Code.** On Windows read
   `kernel_objects` first; a leak there makes every fan-out number a multiple of a broken
   denominator, and suspending the busiest shells moved that host's floor by 15%, not 90%.

## Surface scope: CLI versus desktop

On the audited machine the four heavy sessions were all `WindowsTerminal.exe` to `pwsh.exe`,
which is the CLI, at 595 to 686 MB working set and 155 to 338 s CPU. The eight `sihost.exe` to
`claude.exe` desktop-app children were near idle at 0 to 5 s CPU and 28 to 118 MB.
`settings.json`, hooks, statusline, and the env vars are a SHARED config surface, so those
findings apply to both. **Every timing number in this section is CLI-only**, and desktop coverage
is unmeasured until someone takes readings there. See [desktop.md](https://code.claude.com/docs/en/desktop).

## Reference links

- [statusline](https://code.claude.com/docs/en/statusline): `refreshInterval` is in SECONDS
  (minimum 1), renders are debounced 300 ms, and an in-flight render is cancelled on a new trigger
- [sub-agents](https://code.claude.com/docs/en/sub-agents): concurrency limit and spawn depth
- [agent-teams](https://code.claude.com/docs/en/agent-teams)
- [env-vars](https://code.claude.com/docs/en/env-vars)
- [hooks](https://code.claude.com/docs/en/hooks)
- [debug-your-config](https://code.claude.com/docs/en/debug-your-config): `/doctor`, `/hooks`,
  `/context`, the cheap first pass worth taking before this engine
- [desktop](https://code.claude.com/docs/en/desktop)
- [llms.txt](https://code.claude.com/docs/llms.txt): the index; resolve doc URLs from here rather
  than guessing them

## Windows-specific amplifiers

- Defender real-time scanning taxes every stat/unlink/spawn under the tree; the sweep and
  file-history churn pay it per file (handle-hold EPERM during plugin install:
  anthropics/claude-code#54053; installer false positive: #36796). Exclusions are hidden from
  non-elevated `Get-MpPreference` on Windows 11, so an empty non-admin read proves nothing.
- Every running session polls `~/.claude.json` at 1 Hz (cheap stat; a full main-thread re-parse
  only when another process writes it), and concurrent sessions multiply all watcher/poll load.
- A leaked kernel reference to Token objects, from a driver or service path, fills paged pool and
  taxes every process creation system-wide at idle CPU; see "The host-level floor" above. A
  reboot restores the floor, and only attribution of the minter ends the leak.
- Claude **Desktop** (Electron) has its own distinct lag bugs (unbounded LocalStorage sync,
  #55149; idle disk-write churn, #58799). Do not import Desktop evidence into a CLI diagnosis
  or vice versa; say which surface the symptom was observed on.
