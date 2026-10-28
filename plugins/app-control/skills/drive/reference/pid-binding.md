# Pid binding

A pid-bound capture reaches only the process this run launched: a `threads` capture, and a `cpu` or
`heap` capture whose recorder takes a pid (its command names `<pid>`). The one other route is an
interactive [Attach](../SKILL.md#attach) to a pid the person names, which has no launch record;
an elevated attach binds that pid when its script is shown (below). The other kinds keep the hub's
rules.

- **Linux only.** The binding reads the Linux process table. On any other host, such as macOS or
  Windows, a pid-bound capture or an elevated attach records `blocked: pid binding covers Linux
  only, not <platform>`, naming the host's platform, before anything else, with no attempt.
- **Record at launch.** For each process it launches, one per app, the launch step writes the
  app, pid, owner uid, start time, command line and the command line's sha256 into `report.json`
  (`launch`, [`evidence.md`](evidence.md)). The uid is the one every uid field of the
  process holds (real, effective, saved and filesystem must all be equal). The start time is the
  integer the process table gives (on Linux, the `starttime` field of
  <https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html#DESCRIPTION>), read from the fields
  after the last `)` of `/proc/<pid>/stat`, since the command name before it is one the process
  can write itself (<https://man7.org/linux/man-pages/man5/proc_pid_comm.5.html#DESCRIPTION>),
  spaces and `)` included. The hash is taken over the raw command line bytes, on Linux every byte of
  `/proc/<pid>/cmdline` exactly as read, NUL separators and the trailing NUL included
  (<https://man7.org/linux/man-pages/man5/proc_pid_cmdline.5.html#DESCRIPTION>); the stored
  `command_line` is a display form, never the hash input. The three man pages as of 2026-10-27;
  recheck when one changes the field's form or who may write the command name. A `capture` in a later invocation reads the record
  from the run directory named by `--out`. No launch record means this run launched nothing:
  unattended, `blocked: no process launched by this run`; interactive, only
  [Attach](../SKILL.md#attach).
- **A capture picks its record by app.** The launched pid is that of the one `launch` entry whose
  `app` is the app of the control skill whose `## Capture` row the capture uses; an entry with no
  `app`, as a one-object record from an earlier run holds, takes the report's `app`. No such entry is
  `blocked: no process launched by this run`. More than one, or a row whose owning app is unclear,
  is `blocked: launch record ambiguous: <apps>`, naming the apps, with no attempt.
- **The launch record is data.** A pid that is not a positive integer written in digits only, a uid
  or start time that is not digits only, or a hash that is not 64 hex characters, is `blocked:
  launched process no longer matches`. Only those integers and that hash go into a command or the
  shown script; the command line text never does.
- **Order of the stops.** Platform, then the record (none, ambiguous), then the format check, then
  elevation. So an unattended capture whose picked entry holds an invalid pid records `blocked:
  launched process no longer matches`, never `blocked: capture needs elevation`.
- **Recheck before touching the pid.** Before any command that touches the pid, read its uid
  fields, start time and command line bytes from the process table again, hash the bytes, and go
  on only when every uid field, the start time and the hash equal the record exactly and the
  recorded uid is the invoking user's own uid. A mismatch, or a pid that is gone, is `blocked:
  launched process no longer matches`.
- **The recorder runs only through the built script.** A pid-bound capture never runs its recorder
  directly: build the script with the hub's `build_capture_script.py` command, passing the
  record's pid, uid, start time and hash (`--child` for a wrapper), the artifact path as
  `--capture`, and after `--` the `## Capture` command split into arguments with any elevation
  prefix dropped. Every capture on the elevated route (`threads`, a command that carried a prefix
  or failed for lack of permission, an elevated attach) passes `--elevate sudo` or
  `--elevate doas`, whichever the host has. The builder does the recheck above itself, writes the
  script to a new file, and prints each process it checked (pid, uid, start time, hash, and the
  live command line whose hash just matched, NULs as spaces and control bytes escaped) and then
  the script. Builder exit 3 is `blocked: launched process no longer matches`, exit 4 the
  Linux-only line, exit 2 a usage error, reported as is. An elevated script takes the hub's
  shown-script step: show the builder's full output before asking for the yes, and run the file it
  wrote, unchanged. Only a script built without `--elevate` runs without a yes.
- **What the script does.** It carries as literals only the checked pids, uid, start times, hashes
  and the parent pid of a wrapper's child. Its first lines read each pid's live values and compare
  each with its literal: anything other than an exact match, a failed or empty read, or a missing
  hash tool, exits 3 before the recorder runs. Each live uid field is compared with the uid
  literal, never with the script's own uid. Then it runs the one recorder against the app's pid
  (the child's, when a wrapper resolved), elevated only by `--elevate`, and turns a recorder exit
  of 3 into 4, so 3 always means a recheck. After the recorder exits, an interrupted one included,
  it rechecks every pid again, since the process may change while the recorder runs; a difference
  deletes the capture and exits 3. Exit 3 is `blocked: launched process no longer matches`, with
  no capture; any other non-zero exit is reported with the recorder's output. A script killed
  before its exit leaves an unchecked capture: report it as unchecked. With `--elevate` and a
  `<file>` in the command, the elevated recorder writes into a new directory the elevated user
  makes, never the capture path, so the captured process cannot plant a symlink there; the script
  copies that file to the capture path through its own redirect, as the user running it, and
  removes the directory.
- **A wrapper resolves to its child by parent pid.** When the recorded command line is a shell or
  launcher that started the app, pass `--child`: the builder takes the one process whose parent
  pid is the recorded pid from the live process table in this invocation (never a stored report or
  a name lookup such as `pgrep`, `pidof` or `ps` filtered by name), and the capture step records
  the pid, parent pid, uid, start time, command line and sha256 it printed. Every uid field of the
  child must equal the invoking user's uid; a child owned by anyone else, root included, no child
  or more than one is `blocked: launched process no longer matches`.
- **An elevated attach binds when its script is shown.** Build it with `--attach-pid <pid>` in
  place of the launch record's values: the builder reads that pid's uid, start time and command
  line hash when the script is shown, and the script rechecks them before and after the recorder
  as above. Exit 3 there is `blocked: attached process no longer matches`. The report's process
  carries the uid, start time and hash the builder printed.
