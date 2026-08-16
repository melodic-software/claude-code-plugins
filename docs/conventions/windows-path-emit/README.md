# Windows path emission — convert before a path crosses out of Git Bash

Owner doc for one rule that has already cost this repo real test validity: **a path that originates
in Git Bash and is handed to PowerShell, `cmd`, or a Windows-native interpreter must be converted to
Windows form first.** The [plugin philosophy](../../PLUGIN-PHILOSOPHY.md) owns the
[cross-platform contract](../../PLUGIN-PHILOSOPHY.md#cross-platform-contract) this rests on — "build
paths from documented anchors with platform path APIs"; this doc owns the *emit shape* that keeps it
true at the one boundary where the failure is silent, and names the helper and the detector that back
it.

Scope is every script this repo's authors write on Windows, tracked or not: plugin scripts, repo
tooling under `scripts/`, and — the case that motivated the doc — throwaway verification harnesses,
which are exactly where the trap gets rediscovered because nothing reviews them.

## The mechanism, and why it is silent

Git Bash spells `D:\dir` as `/d/dir`. A Windows-native consumer does not know that mapping: the
leading `/` anchors to the root of the **current drive**, so the literal resolves to
`<current-drive>:\d\dir`. Nothing errors, nothing warns. A native writer creates the phantom chain
and writes there — Python's `shutil.make_archive`, for one, `os.makedirs`-es the destination's parent
before writing rather than failing on it.

The residue at the drive root is the cheap symptom. The expensive one is that **the run measured
something other than what it claims**. In #2834 a harness deleted a real fixture, wrote its
replacement to an MSYS-form absolute path, and so ran two named test cases against a directory that
had no fixture in it at all — mechanically identical to a third case, with two green rows recorded
for scenarios never exercised. Nothing in the run's own output distinguished that from success. The
same mechanism was recorded once before as a machine-level rule in a sibling repo and still recurred
here, which is why it is a repo convention with a detector rather than a note.

## The rules

Four rules, in the order they should be reached for. The first is the one that would have prevented
the motivating incident (#2834) outright; conversion is what to do when it does not apply.

1. **Prefer a path the native side computes itself.** When the consumer is already `cd`-ed into the
   directory it should write to — or can be given a base it owns — pass a *relative* destination and
   let the native runtime join it. A relative path has no drive anchor to get wrong, crosses the
   boundary unchanged, and is shorter than the correct absolute form. In the motivating case the
   harness had already `cd`-ed into the target directory, so `scripts/vendor/bundle` would have been
   both correct and simpler than any absolute path.
2. **Convert an absolute path at the boundary, not at the source.** When an absolute path genuinely
   must cross, convert it in the argument that crosses — keep POSIX form for Bash's own use of the
   same path. Converting early forces every later Bash consumer of the variable to cope with a
   Windows spelling, which is how a half-converted path ends up worse than an unconverted one.
3. **Convert with `cygpath`, and prefer mixed form.** `cygpath -m` yields `C:/dir/file`; `cygpath -w`
   yields `C:\dir\file`. Both are correct to the Win32 API, which accepts either separator. Mixed
   form is the default because backslashes are one escape rule away from becoming something else in
   every layer a path typically crosses — a shell string, a Python or JSON literal (`C:\temp\new`
   carries a newline), a regex. Reach for `-w` only for a consumer that rejects forward slashes.
   [`scripts/emit-windows-path.sh`](../../../scripts/emit-windows-path.sh) is that call, with the
   default and the failure posture already decided.
4. **Fail loud when conversion is unavailable.** An emit path must never fall back to the
   unconverted literal, because the unconverted literal is precisely what writes to the wrong place —
   unobserved. `emit-windows-path.sh` exits non-zero when `cygpath` is missing or fails, and prints
   nothing on stdout for that argument.

## Do not reuse the hook-utils path helpers for this

[`lib/hook-utils.sh`](../../../lib/hook-utils.sh) is the precedent for `OSTYPE`-gated path handling
and is where this repo's `cygpath` dependency was first established, but neither of its path helpers
is an emit helper:

- `hook::normalize_path` folds a leading drive prefix for a **comparison**, using no `cygpath` at
  all. Its own comment is explicit that "the emitted path is always the caller's original." Emitting
  its return value is a misuse of it.
- `hook::expand_8dot3` does call `cygpath -m` / `cygpath -l -m`, but to expand **8.3 short names**,
  and only for a path containing `~`.

Both fail **open** — degrading to the caller's original path — which is right for a comparison and
wrong for an emit. A comparison that degrades answers one question slightly worse; an emitted path
that degrades writes real bytes somewhere nobody looks.

The helper therefore lives at [`scripts/emit-windows-path.sh`](../../../scripts/emit-windows-path.sh)
rather than in `lib/`. `lib/` in this repo means "canonical source of a byte-identical copy synced
into carrying plugins" (see
[`scripts/cross-plugin-source-registry.txt`](../../../scripts/cross-plugin-source-registry.txt)); a
helper with no plugin consumers does not belong there, and adding one to `hook-utils.sh` would put
every carrying plugin through a version bump for a function none of them calls.

## The detection net

[`scripts/check-drive-root-litter.sh`](../../../scripts/check-drive-root-litter.sh) fails a host that
carries the defect's on-disk fingerprint: a directory at a drive root whose name is a single letter
that is **itself a mounted drive** on that host. Requiring the letter to name a real drive is what
keeps it precise — a one-character folder at a drive root is unremarkable on its own (`<drive>:\a` is
the workspace root on a GitHub-hosted Windows runner), and only becomes this defect's signature when
the letter is one an author could have spelled into an MSYS path. It also ignores a candidate that
contains the current working directory, so a checkout that genuinely lives under one is not called
residue.

Run it after any Windows verification pass:

```bash
scripts/check-drive-root-litter.sh    # exit 0 clean, 1 litter found, 2 usage
```

It is a **no-op on non-Windows**: the host gate is the first thing it evaluates, before any
filesystem probing, and the skip is printed rather than silent.

**Advisory, not a required live gate.** CI runs the detector's self-test and asserts the non-Windows
no-op — those are deterministic and fixture-scoped — but does not point the live scan at a runner's
drive roots.
[ADR 0003](../../adr/0003-verification-guards-earn-default-on-by-measured-precision.md) is the
doctrine: a verification guard earns default-on by *measured* precision, and this detector has no
measurements yet. A false positive on a required aggregate blocks every merge in the repo; a missed
one costs a follow-up. Promote it when there is precision to point at.

This is a different concern from
[`plugins/guardrails/hooks/block-windows-drive-tmp.sh`](../../../plugins/guardrails/hooks/block-windows-drive-tmp.sh),
which blocks a *command* aimed at a drive-root temp path before it runs (#2594). That guard reads a
command string ahead of time; this detector reads the filesystem afterwards, and catches the class
where the offending path was never spelled in a command at all — it was computed inside a native
interpreter.

It is also outside the charter of
[`scripts/check-shell-portability.sh`](../../../scripts/check-shell-portability.sh), whose token list
is deliberately scoped to GNU-vs-BSD userland divergence. An MSYS path literal is valid GNU shell on
every platform; nothing about the *shell* is wrong, so a sibling check is the right shape rather than
another token in that list.
