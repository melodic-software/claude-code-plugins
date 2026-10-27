# Pid binding

A `threads` capture reaches only the process this run launched. The one other route is an
interactive [Attach](../SKILL.md#attach) to a pid the person names, which has no launch record and
so no recheck. The other kinds keep the hub's rules.

- **Record at launch.** For each process it launches, one per app, the launch step writes the
  app, pid, owner uid, start time, command line and the command line's sha256 into `report.json`
  (`launch`, [`evidence.md`](evidence.md)). The uid is the one every uid field of the
  process holds (real, effective, saved and filesystem must all be equal). The start time is the
  integer the process table gives (on Linux, the `starttime` field of
  <https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html#DESCRIPTION>). The hash is taken
  over the raw command line bytes, on Linux every byte of `/proc/<pid>/cmdline` exactly as read,
  NUL separators and the trailing NUL included
  (<https://man7.org/linux/man-pages/man5/proc_pid_cmdline.5.html#DESCRIPTION>); the stored
  `command_line` is a display form, never the hash input. Both man pages as of 2026-10-23; recheck
  when either page changes the field's form. A `capture` in a later invocation reads the record
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
- **Recheck before touching the pid.** Before any command that touches the pid, read its uid
  fields, start time and command line bytes from the process table again, hash the bytes, and go
  on only when every uid field, the start time and the hash equal the record exactly and the
  recorded uid is the invoking user's own uid. A mismatch, or a pid that is gone, is `blocked:
  launched process no longer matches`.
- **The shown script rechecks too, with its own exit code.** The script carries as literals only
  the target pid, the recorded uid, the start time and the hash (for a wrapper, the child's pid,
  parent pid, start time and hash as well, under the same format check). Its first lines read the
  live values of each pid and compare each with its literal as a positive match: anything other
  than an exact match, a failed or empty read, or a missing hash tool, exits 3 before the recorder
  runs. Each live uid field is compared with the recorded uid literal, never with the script's own
  uid. Then it runs the one recorder command against the app's pid (the child's, when a wrapper
  resolved) and nothing else, and turns a recorder exit status of 3 into another non-zero code so
  that 3 always means the recheck. Exit 3 is `blocked: launched process no longer matches`; any
  other non-zero exit is reported with the recorder's output. Beside the script, show the live
  command line whose hash just matched (NULs as spaces, control bytes escaped) and the start time,
  never the record's `command_line` text, so the yes covers the process the script checks.
- **A wrapper resolves to its child by parent pid.** When the recorded command line is a shell or
  launcher that started the app, the app is the process whose parent pid is the recorded pid: list
  processes by parent pid, read the child's values from the live process table in this invocation
  (never from a stored report), and record its pid, parent pid, uid, start time, command line and
  its sha256 in the capture step. Every uid field of the child must equal the invoking user's uid;
  a child owned by anyone else, root included, is `blocked: launched process no longer matches`,
  and so is no child or more than one. Never find the app by a name lookup (`pgrep`, `pidof`, `ps`
  filtered by name).
