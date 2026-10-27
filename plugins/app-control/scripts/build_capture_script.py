#!/usr/bin/env python3
"""Build the shown script that binds one recorder to one checked process.

    python3 -I build_capture_script.py --write <script> --capture <file> [--elevate sudo|doas]
        (--pid N --uid N --start-time N --sha256 HEX [--child] | --attach-pid N)
        -- <recorder> [<arg>...]

Implements the shown script of skills/drive/reference/pid-binding.md; that file is the rule.
Launch mode takes the launch record's values, checks their format, checks them against /proc and
the caller's own uid, and with --child resolves the one process whose parent pid is the recorded
pid. Attach mode reads the named pid's uid, start time and command line hash from /proc. In the
recorder, <pid> becomes the target pid (the child's when one resolved) and <file> the capture path;
with no <file>, the recorder's stdout is the capture. The recorder carries no elevation prefix:
--elevate puts one before it. An elevated recorder never writes the capture path itself: its <file>
is a path in a new directory the elevated user makes, and the script copies that file to the
capture path through its own redirect, as the user running it, then removes the directory.

The script is written with mode 0700 to a new file at --write. Stdout carries one line per process
(pid, uid, start time, live command line with NULs as spaces and control characters escaped) and
then the script, for the person to read before the yes.

The script rechecks every process, runs the recorder once, and rechecks again; a difference after
the recorder deletes the capture. Script exit 3: a process no longer matches. A recorder exit of 3
becomes 4; any other exit is the recorder's.

Exit 0: written. Exit 2: usage. Exit 3: a process does not match, or a launch record value fails
its format check. Exit 4: the host is not Linux, which pid binding does not cover.
"""

import argparse
import hashlib
import os
import re
import shlex
import sys

PID = re.compile(r"[1-9][0-9]*")
INT = re.compile(r"[0-9]+")
SHA = re.compile(r"[0-9a-fA-F]{64}")
CONTROL = re.compile(r"[\x00-\x1f\x7f]")
EMPTY_SHA = hashlib.sha256(b"").hexdigest()
ELEVATION = {"sudo", "doas", "su", "pkexec", "run0", "runas"}
PLACEHOLDER = re.compile(r"@(CAPTURE|EMPTY|CHECKS|RUN|HANDBACK)@")

TEMPLATE = r"""#!/bin/sh
# Built by app-control's build_capture_script.py. Rechecks each process below against the uid,
# start time and command line sha256 read when this script was built, runs the recorder once, then
# rechecks; on a difference after the recorder it deletes the capture. Exit 3: a process no longer
# matches. A recorder exit of 3 becomes 4.
set -u
capture=@CAPTURE@
after=0

no() {
  printf 'process no longer matches: %s\n' "$1" >&2
  if [ "$after" = 1 ]; then
    rm -f -- "$capture" && printf 'capture dropped: %s\n' "$capture" >&2
  fi
  exit 3
}

# fields <pid>: the parent pid and start time from /proc/<pid>/stat, read from the fields after
# the last ')', since the command name before it may hold spaces and ')'.
fields() {
  f_stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  case $f_stat in
    *')'*) ;;
    *) return 1 ;;
  esac
  set -f
  # shellcheck disable=SC2086 # split into fields on purpose
  set -- ${f_stat##*)}
  set +f
  [ "$#" -ge 20 ] || return 1
  printf '%s %s\n' "$2" "${20}"
}

# check <pid> <uid> <start time> <sha256> [<parent pid>]
check() {
  c_fields=$(fields "$1") || no "pid $1 is gone or unreadable"
  [ "${c_fields#* }" = "$3" ] || no "pid $1 start time is ${c_fields#* }, not $3"
  [ -z "${5-}" ] || [ "${c_fields% *}" = "${5-}" ] || no "pid $1 parent is ${c_fields% *}, not ${5-}"
  c_uids=$(sed -n 's/^Uid:[[:space:]]*//p' "/proc/$1/status" 2>/dev/null) || no "pid $1 status is unreadable"
  c_n=0
  set -f
  for c_u in $c_uids; do
    c_n=$((c_n + 1))
    [ "$c_u" = "$2" ] || no "pid $1 uid field is $c_u, not $2"
  done
  set +f
  [ "$c_n" -eq 4 ] || no "pid $1 has $c_n uid fields, not 4"
  command -v sha256sum >/dev/null 2>&1 || no "sha256sum is missing"
  c_sum=$(sha256sum 2>/dev/null <"/proc/$1/cmdline") || no "pid $1 command line is unreadable"
  c_sum=${c_sum%% *}
  [ "$c_sum" != @EMPTY@ ] || no "pid $1 command line is empty"
  [ "$c_sum" = "$4" ] || no "pid $1 command line hash differs"
  [ "$(fields "$1")" = "$c_fields" ] || no "pid $1 changed during the check"
}

recheck() {
@CHECKS@
}

recheck
# An interrupted recorder still reaches the recheck after it.
trap : INT TERM
@RUN@
status=$?
@HANDBACK@after=1
recheck
[ "$status" -ne 3 ] || status=4
exit "$status"
"""


class Usage(Exception):
    pass


class NoMatch(Exception):
    pass


def other_platform():
    if sys.platform.startswith("linux"):
        return None
    if sys.platform == "darwin":
        return "macOS"
    if sys.platform in ("win32", "cygwin", "msys"):
        return "Windows"
    return sys.platform


def read(path):
    with open(path, "rb") as f:
        return f.read()


def stat_fields(pid):
    """The parent pid and start time of pid, from the fields after the last ')' of its stat."""
    raw = read(f"/proc/{pid}/stat")
    rest = raw[raw.rindex(b")") + 1 :].split()
    if len(rest) < 20:
        raise NoMatch(f"pid {pid} stat has too few fields")
    ppid, start = rest[1].decode("ascii", "replace"), rest[19].decode("ascii", "replace")
    if not (INT.fullmatch(ppid) and INT.fullmatch(start)):
        raise NoMatch(f"pid {pid} stat fields are not integers")
    return ppid, start


def live(pid):
    """The live parent pid, uid, start time and command line of pid."""
    try:
        ppid, start = stat_fields(pid)
        uids = []
        for line in read(f"/proc/{pid}/status").splitlines():
            if line.startswith(b"Uid:"):
                uids = [u.decode("ascii", "replace") for u in line.split()[1:]]
        cmdline = read(f"/proc/{pid}/cmdline")
        again = stat_fields(pid)
    except (OSError, ValueError) as e:
        raise NoMatch(f"pid {pid} is gone or unreadable") from e
    if again != (ppid, start):
        raise NoMatch(f"pid {pid} changed while it was read")
    if len(uids) != 4 or len(set(uids)) != 1 or not INT.fullmatch(uids[0]):
        raise NoMatch(f"pid {pid} uid fields are not one uid: {' '.join(uids)}")
    if not cmdline:
        raise NoMatch(f"pid {pid} has an empty command line")
    return {
        "pid": pid,
        "ppid": ppid,
        "uid": uids[0],
        "start": start,
        "sha256": hashlib.sha256(cmdline).hexdigest(),
        "cmdline": cmdline,
    }


def children(pid):
    found = []
    for name in os.listdir("/proc"):
        if not PID.fullmatch(name):
            continue
        try:
            ppid, _ = stat_fields(name)
        except (OSError, ValueError, NoMatch):
            continue
        if ppid == pid:
            found.append(name)
    return found


def display(cmdline):
    text = cmdline.rstrip(b"\0").replace(b"\0", b" ").decode("utf-8", "backslashreplace")
    return "".join(
        c if c.isprintable() else c.encode("unicode_escape").decode("ascii") for c in text
    )


def describe(label, proc):
    return (
        f"{label}: uid {proc['uid']}, start time {proc['start']}, sha256 {proc['sha256']}, "
        f"command line: {display(proc['cmdline'])}"
    )


def parse(argv):
    if "--" not in argv:
        raise Usage("put -- before the recorder command")
    cut = argv.index("--")
    parser = argparse.ArgumentParser(prog="build_capture_script.py", allow_abbrev=False)
    parser.add_argument("--write", required=True)
    parser.add_argument("--capture", required=True)
    parser.add_argument("--elevate", choices=("sudo", "doas"))
    parser.add_argument("--pid")
    parser.add_argument("--uid")
    parser.add_argument("--start-time")
    parser.add_argument("--sha256")
    parser.add_argument("--child", action="store_true")
    parser.add_argument("--attach-pid")
    args = parser.parse_args(argv[:cut])
    recorder = argv[cut + 1 :]
    launch = [args.pid, args.uid, args.start_time, args.sha256]
    if args.attach_pid is not None:
        if any(v is not None for v in launch) or args.child:
            raise Usage("--attach-pid takes no launch record values and no --child")
    elif any(v is None for v in launch):
        raise Usage("give --pid, --uid, --start-time and --sha256, or --attach-pid")
    if not recorder:
        raise Usage("no recorder command after --")
    if any(CONTROL.search(a) for a in recorder):
        raise Usage("a recorder argument holds a control character")
    if os.path.basename(recorder[0]) in ELEVATION:
        raise Usage(f"the recorder starts with {recorder[0]}; drop it and pass --elevate")
    if not any("<pid>" in a for a in recorder):
        raise Usage("the recorder names no <pid>")
    if not os.path.isabs(args.capture) or CONTROL.search(args.capture):
        raise Usage("--capture must be an absolute path with no control character")
    return args, recorder


def bind(args):
    """The checked processes, launched or attached first, and the label of each."""
    if args.attach_pid is not None:
        if not PID.fullmatch(args.attach_pid):
            raise NoMatch(f"attach pid {args.attach_pid!r} fails its format check")
        return [(f"attached process {args.attach_pid}", live(args.attach_pid))]
    for name, value, form in (
        ("pid", args.pid, PID),
        ("uid", args.uid, INT),
        ("start time", args.start_time, INT),
        ("sha256", args.sha256, SHA),
    ):
        if not form.fullmatch(value):
            raise NoMatch(f"launch record {name} {value!r} fails its format check")
    own = str(os.getuid())
    if args.uid != own:
        raise NoMatch(f"recorded uid {args.uid} is not this user's uid {own}")
    proc = live(args.pid)
    for name, want, got in (
        ("uid", args.uid, proc["uid"]),
        ("start time", args.start_time, proc["start"]),
        ("command line sha256", args.sha256.lower(), proc["sha256"]),
    ):
        if want != got:
            raise NoMatch(f"pid {args.pid} {name} is {got}, not {want}")
    bound = [(f"process {args.pid}", proc)]
    if args.child:
        kids = children(args.pid)
        if len(kids) != 1:
            raise NoMatch(f"pid {args.pid} has {len(kids)} child processes, not one")
        kid = live(kids[0])
        if kid["uid"] != own or kid["ppid"] != args.pid:
            raise NoMatch(f"child pid {kid['pid']} is not this user's child of {args.pid}")
        bound.append((f"child {kid['pid']} of {args.pid}", kid))
    return bound


def build(bound, recorder, capture, elevate):
    target = bound[-1][1]["pid"]
    to_file = any("<file>" in a for a in recorder)
    # An elevated recorder writes into a directory only the elevated user can change, so a process
    # of this user cannot plant a symlink where the elevated write lands.
    staged = elevate and to_file

    def word(a):
        a = a.replace("<pid>", target)
        if not staged or "<file>" not in a:
            return shlex.quote(a.replace("<file>", capture))
        return '"$stage/capture"'.join(shlex.quote(p) if p else "" for p in a.split("<file>"))

    run = " ".join(word(a) for a in recorder)
    if elevate:
        run = f"{elevate} {run}"
    if not to_file:
        run += ' >"$capture"'
    elif staged:
        run = (
            f'stage=$({elevate} mktemp -d) || {{ printf \'could not make a stage directory\\n\' >&2; exit 1; }}\n'
            + run
        )
    checks = []
    for i, (_, proc) in enumerate(bound):
        line = f"  check {proc['pid']} {proc['uid']} {proc['start']} {proc['sha256']}"
        if i:
            line += f" {proc['ppid']}"
        checks.append(line)
    hand_back = ""
    if staged:
        hand_back = (
            f'if {elevate} test -e "$stage/capture"; then\n'
            f'  {elevate} cat -- "$stage/capture" >"$capture" ||\n'
            '    printf \'could not hand %s back\\n\' "$capture" >&2\n'
            'fi\n'
            f'{elevate} rm -rf -- "$stage"\n'
        )
    values = {
        "CAPTURE": shlex.quote(capture),
        "EMPTY": EMPTY_SHA,
        "CHECKS": "\n".join(checks),
        "RUN": run,
        "HANDBACK": hand_back,
    }
    # One pass, so a placeholder inside a filled value is never filled again.
    return PLACEHOLDER.sub(lambda m: values[m[1]], TEMPLATE)


def write(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        os.fchmod(f.fileno(), 0o700)
        f.write(text)


def main(argv):
    try:
        args, recorder = parse(argv)
    except Usage as e:
        print(f"usage: {e}", file=sys.stderr)
        return 2
    other = other_platform()
    if other:
        print(f"pid binding covers Linux only, not {other}", file=sys.stderr)
        return 4
    try:
        bound = bind(args)
    except NoMatch as e:
        print(f"process no longer matches: {e}", file=sys.stderr)
        return 3
    text = build(bound, recorder, args.capture, args.elevate)
    try:
        write(args.write, text)
    except OSError as e:
        print(f"usage: cannot write a new script at {args.write}: {e.strerror}", file=sys.stderr)
        return 2
    for label, proc in bound:
        print(describe(label, proc))
    print(f"script {args.write}:")
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
