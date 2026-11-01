#!/usr/bin/env bash
# PreToolUse hook: block a recursive delete whose TARGET is a filesystem root.
# Triggered on Bash and PowerShell tool calls (a command string).
#
# THE GAP THIS CLOSES. Before 0.36.0 no guard in this plugin inspected the target of
# a delete at all: `rm -rf` appeared only in the suites, as fixture cleanup, and
# `rm -rf "\\"` passed all eight guards of the Bash dispatcher at rc 0. The
# motivating incident is anthropics/claude-code #92593, where a subagent ran
# `rm -rf "\\"` in Git Bash meaning to remove a stray directory named `\`. MSYS
# path translation resolved the bare backslash to the ROOT OF THE CURRENT DRIVE
# and the delete ran for about seven minutes before it was killed by PID.
#
# WHY A HOOK AND NOT A DENY RULE. The quoted-backslash form does not look like
# `rm -rf /*`, so a permission pattern keyed on the obvious spelling never
# matches it. Two harness behaviors the same issue reports make a PRE-execution
# control the only dependable one: a command past the Bash timeout is
# auto-backgrounded and keeps running unsupervised, and stopping the task ends
# the shell without the process tree. Once a runaway recursive delete starts,
# stopping it is not reliable, so the control point is before it runs.
#
# HOW IT DECIDES. Not on the shape of the command text. The command is parsed
# the way the shell builds argv (hook::bash_parse_segments, the same tokenizer
# block-no-verify and block-dangerous-git use), and each simple command is
# judged on three questions: is its COMMAND WORD `rm`, does it carry a
# RECURSIVE flag, and does any OPERAND normalize to a root. Quoting is already
# resolved by the time the matcher sees a word, which is what keeps
# `git commit -m "rm -rf /"` and `echo "rm -rf /"` allowed: there the whole text
# is one argv word of a `git` or `echo` command, and the command word is never
# `rm`. That is a consequence of parsing argv, not a special case for prose.
#
# A COMMAND SUBSTITUTION is the one place that reasoning does not reach, and it
# is handled separately. `echo "$(rm -rf /)"` runs the delete before `echo` is
# ever invoked, while the tokenizer correctly keeps the substitution inside the
# enclosing word, so the segment callback only sees `echo`. Every `$( … )` and
# backtick body is therefore lifted out and parsed on its own. That scan HONORS
# QUOTING, both to find a substitution and to find where it ends: `'$(rm -rf /)'`
# is inert text, `"\$(…)"` is escaped, and a `)` inside a quoted span is not the
# terminator. Nesting is capped at MAX_SUBST_DEPTH and the cap REFUSES.
#
# NOT HOST GATED, deliberately, and this differs from block-windows-drive-tmp.sh
# next to it. That guard exits at once on a non-Windows host because a POSIX
# /tmp is the real temp directory there and it can have no opinion. Here `/`,
# `/*`, `~`, `$HOME` and `--no-preserve-root` are unrecoverable on every host
# this plugin runs on, and CI is Linux, so every arm is active everywhere. The
# drive-root arms simply never match on a host that has no drive letters. Do not
# "fix the inconsistency" by adding an OSTYPE gate.
#
# NARROW TRIGGER, ON PURPOSE. block-exported-msys-pathconv.sh records that a
# guard keyed on PATH SHAPE across every Bash command fired on 45.7% of 14,234
# real commands and was rejected on that measurement. This guard does not
# inherit that objection: it reads a cheap substring first, so a command whose
# text holds none of `rm`, `-delete`, `.delete`, `unlink`, `rsync`,
# `robocopy`, `worktree`, `remove`, `mv`, `truncate`, `shred`, `of=`, the
# decoder names (`base64`, `base32`, `basenc`, `xxd`) and `cmd` followed by
# `rd` never reaches the parse at all. The
# prefilter is a SUBSTRING match, not a token one, so `npm run format` does
# reach the tokenizer and is allowed there on its command word. The path question is
# asked only once a recursive `rm`, a deleting find, a deleting rsync, a
# deleting robocopy, a forced git worktree remove, an interpreter's deleter
# call, a move or a content destroyer, run directly or by xargs or parallel,
# is established. A decoder sink asks no path question: it is refused
# outright.
#
# GIT CLEAN IS NOT JUDGED HERE. block-dangerous-git owns a forced `git clean`
# and blocks it outside the exceptions that guard documents. This guard has no
# `git clean` arm, so one guard decides the command; the name appears below
# only in the refusal messages that tell the agent not to retry a delete with
# it.
#
# FIND DELETES. `find -delete`, and a find whose expression runs `rm`, `rmdir`
# or `unlink` as the command word of an -exec, -execdir, -ok or -okdir action,
# remove what the find's start points hold, so each start point is judged as
# an operand of a recursive rm, through every arm below. A find that does
# neither is not judged, and a word inside an action's command, up to its `;`
# or the `+` after `{}`, is never read as -delete. GNU and BSD find read the
# leading options differently, so the start points of both readings are
# judged. GNU: after -H, -L, -P, -D <debugopts> and -O<level>, the words up to
# the first that begins with `-` or is `(` or `!`, and `.` when there is none
# (find(1), man7.org). BSD: after getopt clusters of -E, -H, -L, -P, -X, -d,
# -s, -x and -f <path>, each -f operand and the words up to the first that
# begins with `-` or is `(` or `!` (FreeBSD usr.bin/find/main.c). Both read
# 2026-10-29; recheck when either changes how start points end. A `--` ends
# the leading options in both readings, which can only add a start point.
# find follows a start point that is a symlink under -H, -L or -follow
# (find(1)), so with any of them, a BSD cluster holding H or L included, each
# start point is judged as `<start point>/`, by where the link points; without
# them it is judged as rm judges a link named last. -delete turns on -depth,
# which leaves -prune ineffective (find(1)), and find descends into `.git`, so
# a find delete started at the git toplevel is refused as a directory holding
# a `.git` whatever its filters.
#
# RSYNC DELETES. `rsync --del`, `--delete` and every `--delete-<mode>` remove
# extraneous files from the destination, the last operand, and
# `--remove-source-files` has the sender remove the files it synchronized from
# the sources, every operand before it (rsync(1), samba.org, read 2026-10-30).
# Those targets are judged as operands of a recursive rm, through every arm
# below; an rsync with neither option, or with one operand (which lists it),
# deletes nothing and is not judged. When an operand holds an unquoted brace
# or glob, which can expand to more words or to none, every operand is judged
# instead, one alone included. Options are read wherever they stand up to a
# `--`, and the word after an option that takes an argument (-e, -f, -T, -B,
# -M, -@ ending a cluster, or a long option of the man page or one of its
# aliases such as --cc, --zl and --time-limit, written without `=`) is not an
# operand. --remove-sent-files and --log-format, spellings the current man
# page does not list, are read as --remove-source-files and --out-format. An
# operand rsync reads as remote (`host:path`, two or more characters before a
# `:` that no `/` precedes, none of them a `$`, a backtick or a `{`, or
# rsync://) names another host and is left alone; a drive path such as `C:/`
# is judged.
#
# ROBOCOPY DELETES. `robocopy <source> <destination> [<file>...] [<options>]`
# with /MIR or /PURGE deletes destination files and directories that no
# longer exist in the source, and with /MOVE or /MOV deletes what it copied
# from the source (robocopy, learn.microsoft.com, read 2026-10-30). That
# destination or source is judged as an operand of a recursive rm, through
# every arm below, from the Bash tool and the PowerShell tool (`cmd /c
# robocopy` included). An option is a documented robocopy option name in any
# case, `/NAME` or `/NAME:value`, and `//NAME` and `-NAME` are read as
# `/NAME` too, except that from the Bash tool a one-letter word with a single
# slash (`/e`) is the drive root MSYS rewrites it to, as the root arm reads it
# elsewhere, and never an option (`robocopy src /e /MIR` mirrors onto `E:\`).
# That rewrite runs only while path conversion is on, so a prefix assignment
# that turns it off for the robocopy (`MSYS_NO_PATHCONV=<any>`, or an
# `MSYS2_ARG_CONV_EXCL` entry that is `*` or a prefix of the word) makes the
# word an option again (`MSYS_NO_PATHCONV=1 robocopy /e empty <dest> /MIR`
# mirrors onto <dest>). When that state is unknown, a suppressor value with a
# `$` or a backtick, or an env option (`env -u`, `env -i`) that can drop the
# suppressor, every operand is judged. An exported suppressor is
# block-exported-msys-pathconv.sh's to refuse; the words after /XF, /XD or /IF up to the next option are its list. Of the
# other words the first is the source and the second the destination. A word that can become several words or none changes which
# word comes first or second, so with one every operand is judged instead:
# from the Bash tool an unquoted brace, glob, `$` or backtick, or a quoted
# "$@" or "${a[@]}"; from the PowerShell tool an expanding `$` or a grouping.
# PowerShell's stop-parsing token `--%` is dropped before the words are read.
#
# GIT WORKTREE REMOVE. `git worktree remove -f <worktree>` (or --force, or any
# prefix of it) deletes the worktree's directory even when it holds changes,
# and with -f twice even when it is locked; without it git refuses a worktree
# with changes or untracked files (git-worktree(1), git-scm.com, read
# 2026-10-31), so the unforced form is not judged, although it still removes
# ignored files. Each <worktree>
# operand is judged as an operand of a recursive rm, through every arm below,
# resolved whole because git looks the path up by its real path. git first
# looks <worktree> up as the trailing path components of a registered worktree,
# from any directory (find_worktree in git's worktree.c, read 2026-10-31), so
# every root in the registry the protected-tree arm reads whose path ends in
# the operand's text (an unquoted glob matched as a pattern), compared in any
# case, is judged too. Each git global option ahead of `worktree` is stepped
# over with its argument. With -C, --git-dir or --work-tree, a GIT_DIR,
# GIT_WORK_TREE or GIT_COMMON_DIR prefix, or after a directory change, an
# operand that is not absolute (a `$` word included) is refused, because it
# may name a worktree of a repository whose registry is not read. A registered worktree
# root stays protected, as for rm, unless it is not the git toplevel and sits
# strictly under a temp root, the scratchpad or an allowed root: then the
# worktree root and its `.git` file pass, and a protected tree inside it does
# not.
#
# INTERPRETER DELETES. A python (python, python3, py, pypy), node, perl or
# ruby is read for the program it runs: each -c (python), -e, -E (perl),
# --eval or --print operand, short clusters (`-Bc`, `-lne`) and an operand
# attached to its letter included, after stepping over the options that take
# an argument; with none of those and no script operand (or the script `-` or
# /dev/stdin), the here-string or heredoc its stdin last redirects from. A
# script file is not read. An option cluster too long to read whole (32
# letters) is refused. A heredoc body is read as bash hands it over (under an
# unquoted delimiter, without its backslash-newlines and with \\, \$ and \`
# unescaped), and judged from the directories the command may run the
# interpreter from, not from where the command ends. The program is lexed for
# string literals and comments, so a name inside a string or a comment is not
# a call; a literal's escapes are decoded (\\, the quotes, \/, \t, \n, \r and
# a line continuation), and one holding any other escape is unreadable. Each call to a deleter of its
# language is established as a delete: python `rmtree` and `os.remove`,
# `os.unlink`, `os.rmdir`, `os.removedirs`; node `rmSync`, `rmdirSync`,
# `unlinkSync`, `.rm`, `.rmdir` and `.unlink`; ruby `rm_rf`, `rm_r`,
# `rmtree`, `remove_dir`, `remove_entry`, `remove_entry_secure`, the
# `FileUtils.` rm, rm_f, remove, rmdir, remove_file and safe_unlink, and
# `File.` or `Dir.` delete, unlink and rmdir; perl `rmtree`, `remove_tree`,
# `unlink` and `rmdir`. Its path arguments (python's and node's first; every
# ruby and perl one but an option) are judged as operands of a recursive rm,
# through every arm below, when each is a plain string literal, and are read
# as no shell expands them (no `~`, glob or brace). A literal holding a `$` or
# a backtick, which the shell may have expanded in the code before the
# interpreter ran, is refused unless it is a leading $HOME or ${HOME} with a
# plain path after it; any other argument (a variable, an expression, an
# interpolated or unreadable string, a list holding one) cannot be placed,
# and the call is refused, as is a perl unlink or rmdir with no argument,
# which deletes `$_`. A ruby keyword or hash option and a perl options hashref
# written last are not paths. A call that runs a command (python os.system, os.popen and the
# subprocess functions; node exec, execSync, spawn, spawnSync, execFile and
# execFileSync; ruby system, exec, spawn, popen and the Open3 functions; perl
# system and exec), a backtick, perl qx and ruby %x are judged as the
# command: a string literal as the text a shell runs, an interpolation in it
# read as a shell expansion and an unreadable one refused, and a list (or
# several arguments in ruby and perl, or node's program and its argument list)
# as the argv a program is handed, where an element that is not a readable
# literal is refused as a target. A command given no literal at all is not
# read. Perl and ruby calls written without parentheses are read up to `;`, a
# newline, `&&`, `||` or a statement modifier. The code's own argv (an xargs
# or parallel item included) is not a target: a deleter given one is refused
# above as a path the code computes.
#
# DECODER SINKS. A decoder feeding an execution sink is refused outright,
# whatever the decoded text targets, because that text never appears in the
# command and no arm can judge it; an attended session is denied too. The
# decoders: base64, base32 and basenc with -d, -D or a prefix of --decode,
# xxd with -r, and PowerShell's [Convert]::FromBase64String. A decoder writes
# decoded text unless its stdout is redirected or it is given an output file
# (-o or --output; xxd's second operand), so `base64 -d x > out.bin`, `xxd -r
# dump.hex out.bin` and `base64 -d x | less` pass. Bash sinks: a shell (bash,
# sh, zsh, dash, ksh, mksh) or a source of /dev/stdin reading its program from
# a pipe a decoder feeds, through any stage but a pager (`echo <b64> | base64
# -d | tr -d '\r' | sh`), the first command of a -c operand or an eval text
# included (`... | sh -c sh`); and, in a parse holding a paren or a backtick,
# a decoder after a command whose program a substitution supplies: eval, a
# shell's -c operand, a shell or source with no operand (`bash <(...)`,
# `source <(...)`), a command word that is itself an unquoted `$(...)`, and a
# backtick where a command starts. The program an eval or a -c operand runs,
# a here-string a stdin shell reads as its program, and a command interpreter
# code runs are parsed as commands, so `eval "$(echo <b64> | base64 -d)"`,
# `bash -c "$(base64 -d <<< <b64>)"` and `bash <<< "$(base64 -d x)"` are
# refused, and so is a decoder piped into a shell inside a substitution body.
# PowerShell: a
# statement is decoded when a word of it is the [Convert]::FromBase64String (or
# [System.Convert]::FromBase64String) call, a grouping or `$( )` inside it is,
# or a decoded stage pipes into it, and Invoke-Expression or iex given one is
# refused (`iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))`,
# `... | iex`). A decoder named inside quoted prose (`git commit -m "base64 -d
# | sh"`) is one argv word, never a command, and stays allowed.
#
# POWERSHELL INDIRECTION AND PIPELINES (#9765). On the PowerShell tool a
# delete run through another command is judged as the delete itself, each
# target through every arm below:
#   * Invoke-Expression (iex): its -Command string, positional or named, is
#     walked as PowerShell, and so is a string a pipe hands it from a stage
#     of one word or a Write-Output, echo or write of one (Invoke-Expression,
#     learn.microsoft.com).
#   * pwsh -Command and powershell -Command: -Command (-c, or a prefix of it)
#     runs every word after it joined by spaces, -CommandWithArgs (-cwa) the
#     word after it, and the first word that is no option starts -Command
#     text too; each is walked as PowerShell. -EncodedCommand (-e, -ec, or a prefix of it) is
#     base64 of UTF-16LE (about_Pwsh, about_PowerShell_exe), decoded with
#     bash builtins and walked; a value that is not literal base64, or that
#     decodes to anything but printable ASCII, tab and line breaks, is denied
#     whether or not the session is attended, as a decoder sink is.
#   * Start-Process (saps, start): -FilePath is the program and -ArgumentList
#     is joined by spaces into the one command line it gets (Start-Process,
#     learn.microsoft.com), split as cmd splits one and judged as that
#     program's statement (cmd /c rd /s, robocopy, rm, pwsh, powershell).
#     A literal -WorkingDirectory on Start-Process, pwsh or powershell adds a
#     directory a relative target may land from, as a literal cd does in the
#     Bash lane; one it cannot place changes nothing.
#   * Pipeline removals (`gci X | Remove-Item`): a Remove-Item stage (any
#     alias) with no path of its own, recursive or not, and a stage whose
#     scriptblock removes the pipeline item (`% { $_.Delete() }`,
#     `$PSItem.Delete()`, Remove-Item of `$_` or `$_.FullName`) remove what
#     the stage before lists. When that
#     stage is a Get-ChildItem or Get-Item (gci, dir, ls, gi), through
#     Where-Object, Sort-Object or a Select-Object that only keeps some items,
#     each path it lists from is judged (each element of a comma list), `.`
#     when it names none and no pipe feeds it. A recursive removal or an item
#     removal fed by anything else, a listing a pipe feeds included, is
#     refused, because its target cannot be named.
#   * .NET deletes: [IO.Directory]::Delete and [IO.File]::Delete (any
#     `[<type>]::Delete(` call) have their first argument judged, and
#     `(Get-Item X).Delete()` its listing's path, with or without the
#     recursive flag (System.IO.Directory.Delete, learn.microsoft.com). A
#     grouping, array, subexpression or call as that argument is refused, and
#     so is .Delete() on a grouping that is not one listing statement; another
#     expression is judged by its first word.
# The nested text counts toward MAX_SEGMENT_DEPTH and toward the
# MAX_COMMAND_LEN total eval text reads, and past either it refuses. Each
# source was read 2026-10-31; recheck when pwsh changes its -Command or
# -EncodedCommand reading. A mechanism named inside quoted prose (`git commit
# -m "Start-Process cmd '/c rd /s /q C:\'"`) is one word of another command
# and stays allowed.
#
# MOVES AND CONTENT DESTROYERS (#9767). A move takes what it names away from
# where it was, and a content destroyer keeps the file but not what it held,
# so each such target is judged as an operand of a recursive rm, through every
# arm below:
#   * mv: each source, which is every operand but the last, or every operand
#     with -t or --target-directory, whose argument is the directory moved
#     into (mv(1)). A move onto /dev/null is judged by its source like any
#     other (`mv ~ /dev/null`). A last word that can become several words (an
#     unquoted brace, glob, `$` or backtick, or a quoted "$@" or "${a[@]}")
#     makes all but its final word sources, so with one every operand is
#     judged.
#   * truncate, which shrinks or extends each file to a size, and shred, which
#     overwrites each file (truncate(1), shred(1)): every operand. The word
#     after -r or -s (truncate), or -n or -s (shred), is that option's
#     argument, and so is the one after its long name written without `=`.
#   * dd: the file each of= names, which dd writes instead of standard output
#     (dd(1)), unless it is /dev/null, /dev/stdout or /dev/stderr.
#   * On the PowerShell tool, Move-Item (mi, move, and mv on Windows),
#     Clear-Content (clc) and a Set-Content that writes several files: each
#     -Path or -LiteralPath (PSPath, LP) element, or the first positional
#     argument when neither is named, every element of a comma list
#     included (Move-Item, Clear-Content, Set-Content, learn.microsoft.com).
#     Set-Content is judged only with more than one element, a -Path holding
#     `*`, `?` or `[`, or the pipeline item as its path, because writing one
#     named file is an ordinary write, as `>` is in Bash. With no path and a
#     pipe into it, the Get-ChildItem or Get-Item stage before it is judged
#     as a pipeline removal's is. Move-Item moves a directory's children with
#     it, so it refuses any other feed, as a recursive Remove-Item does. A
#     grouping as a judged path is refused.
# Options are read as getopt_long reads them, anywhere up to `--`, an
# unambiguous prefix of a long option included; a word an option takes after
# an operand is judged as an operand too, because under POSIXLY_CORRECT options
# end at the first operand. Items xargs or parallel hand one of these commands
# are judged as a recursive rm's are, and there mv's last written word is
# judged too, because the items may follow it; a dd whose every of= names a
# stream writes nothing, so its items are not judged. The coreutils 9.11
# pages (man7.org) and the PowerShell 7.6 pages were read 2026-10-31; recheck
# when mv gains another option that names its destination, or Set-Content or
# Clear-Content gains an alias.
#
# SHELLS AND LAUNCHERS FROM BASH (#9768). On the Bash tool a delete run
# through one of these is judged as the delete itself, each target through
# every arm below, as the `sh -c`, `su -c` and `env -S` unwrapping judges one:
#   * eval: its words joined by spaces, as eval joins them, parsed as shell
#     text.
#   * watch: the words after its options (getopt `+bCcefd::ghq:n:prs:twvx` in
#     procps-ng src/watch.c, where -n, -q and -s take an argument), joined by
#     spaces and parsed as the text it hands `sh -c`, or with -x or --exec
#     read as the argv it runs (watch(1), man7.org).
#   * wsl and wsl.exe: the command line it hands the distribution's shell, or
#     with -e or --exec its argv (hook::wsl_operand). A target is judged as
#     written, against this host's roots and allowed roots.
#   * cmd /c or /k, `cmd //c` included (a switch's leading `//` is read as
#     `/`): one word after the switch is the whole command line, split as cmd
#     splits one; several are its words, which are also judged as that
#     command from the Bash tool (rm, robocopy). Each statement of the line,
#     ended by a word that is `&`, `&&`, `|` or `||`, is judged as the
#     PowerShell lane judges cmd's: rd or rmdir with /s, and robocopy (cmd
#     and rd, learn.microsoft.com).
#   * A code heredoc, and a shell piped its program: a shell or source that
#     reads its program from stdin (no -c and no script operand, or -s, `-` or
#     /dev/stdin) runs the heredoc or here-string its last redirection of fd 0
#     names, or else what the command before it writes into the pipe: the
#     words an echo writes, read once more with the backslash escapes a POSIX
#     echo decodes (echo(1p), man7.org), what a printf writes when its format
#     holds no conversion but %s, %b and %%, and the heredoc or here-string a
#     cat with no operand writes. That program is parsed as shell text, its
#     substitutions included (`bash <<'EOF'`, `echo 'rm -rf /' | sh`, `cat
#     <<'EOF' | sh`). A heredoc program is read once the parse has its body,
#     and its relative targets are judged from every directory the command
#     may run from, the ones its own cd lines reach included.
# The nested text counts toward the MAX_COMMAND_LEN total eval text reads,
# and all of it but a heredoc program toward MAX_SEGMENT_DEPTH too; past
# either it refuses. Each
# source was read 2026-10-31; recheck when watch changes its getopt string or
# cmd how /c reads its string. A mechanism named inside quoted prose (`git
# commit -m "echo 'rm -rf /' | sh"`) is one word of another command and stays
# allowed.
#
# PIPELINE-FED DELETES. `xargs` and `parallel` run a command on the items they
# read, so when that command is a recursive rm or a deleting find (named
# directly, through a launcher, or in a child shell) the items are its targets.
# The command's own operands are judged as written (an -I or `{}` template
# included), and so are parallel's `:::` items, which replace its stdin ("The
# input source is normally stdin", parallel(1)). Items read from a file (xargs
# -a or --arg-file; parallel's `::::` and every option starting -a or --a) or
# from a stdin no confined listing feeds are refused, because they name
# nothing the guard can judge: `cat list | xargs rm -rf`, `xargs rm -rf < list`
# and a lone `xargs rm -rf` alike. Two listings are confined, and their targets
# are judged as a recursive rm's: a find without -printf, -fprintf, -ls, -fls,
# an -exec, -execdir, -ok or -okdir action, or -files0-from, whose start points
# are judged as FIND DELETES judges them; and `git ls-files` with no git option
# before the subcommand and no --format, whose entries are judged as one name
# strictly under the directory it runs from. Between the listing and xargs
# only line filters may stand, which pass on whole lines of their input: grep,
# egrep and fgrep (flags from -vixwEFGPsqz, -e, -f, one pattern), sort (flags
# from -bdfghiMnRrsuVz, -k, -t), uniq (-diuz), head and tail (-n, -<count>,
# -z), each with no file operand. A redirection of stdin replaces the pipe.
# The tokenizer reports no operator between two commands, so the one before
# is read as a pipe into the one after; a parse whose text holds a `(`, `)` or
# backtick that no backslash escapes is read as no pipeline at all, because a
# subshell, a substitution or a process substitution splits into commands that
# are not its stages. In a parse another command feeds (a child shell, eval),
# a command whose feed from the one before differs from the parse's own reads
# as unconfined, since after `;` or `&&` it reads the parse's stdin instead,
# and so does a substitution body's stdin, which is not known. xargs options
# follow GNU findutils' getopt string `+0a:E:e::i::I:l::L:n:oprs:txP:d:` and
# long-option table (xargs/xargs.c) and BSD's -J, -R and -S (FreeBSD
# xargs(1)); the `+` ends options at the first operand, the command. GNU parallel runs "the
# commands run by GNU parallel" through a shell and, "If no command is given,
# the line of input is executed" (parallel(1)), so its options are not
# modeled: each word an option may have taken as its argument is also read as
# the command's first word, the words from there to the first `:::` or `::::`
# are joined and parsed as shell text, and every `:::` item is parsed as a
# command too. All read 2026-10-30; recheck when xargs changes its getopt
# string or parallel how it builds a job.
#
# FOUR MORE TARGET CLASSES, each refused with its own message:
#   * An EMPTY operand (`rm -rf ""`, `rm -rf "" build`): a path that failed to
#     build. `rm -rf` with no operand has nothing to judge and stays allowed.
#   * A BARE VARIABLE operand: after normalization the word is made of
#     expansions and nothing else (`$NAME`, `${...}` in any form, a positional
#     or special parameter, `$X$Y`). Unset or empty, it reaches the working
#     directory or a root. Only `${X:?...}` aborts the command on an empty
#     value too, so an operand of that form alone, such as `"${X:?}/"`, stays
#     allowed. A nested `${...}` is one unit judged by its outermost operator:
#     `${X:-${Y:-/}}` is refused and `${X:?${Y}}` is allowed.
#   * A PROTECTED TREE, judged with the outside-tree arm below (so only when
#     the payload carries an absolute `cwd`) and ahead of every root that arm
#     allows, so it is refused under the git toplevel, a temp root, the
#     scratchpad or a listed root alike. Protected: a `.git` (named last, or
#     globbed straight inside), a directory holding a `.git`, the git toplevel
#     of the payload cwd, every worktree root git has registered for that
#     repository (read from the common git directory's worktrees/*/gitdir
#     files with builtins, at most MAX_WORKTREES), anything under ~/.claude,
#     Claude Code's temp tree, and anything under an entry of the userConfig
#     key block_root_delete_target_protected_trees. That key is read from the
#     hook's own environment like the allowed roots: comma-separated absolute
#     directories, and an entry that is relative, empty, holds a glob
#     character, a line break or a `..` component, or resolves to a
#     filesystem root protects nothing. The temp tree is
#     <temp root>/claude-<uid> (<temp root>/claude on Windows), or the base the
#     payload scratchpad sits in when it reads
#     <base>/<project>/<session>/scratchpad with a base named claude or
#     claude-<suffix>; the base, a project or session directory and another
#     session's scratchpad are refused there, and this session's own
#     scratchpad is judged as before. Inside a temp root that lies in the tree
#     (TMPDIR pointed into it) only another session's scratchpad is refused.
#     A directory holding a protected tree, or a glob whose matches do, is
#     refused too; a glob is read as bash reads it with dotglob off, unless the
#     command names dotglob, GLOBIGNORE or globdots, and on the PowerShell
#     tool, whose `*` matches dot names. A `.git` is matched in any case, and
#     on Windows with a trailing dot or space, which Win32 trims. A path named
#     under a `.git`, the toplevel or a worktree root is not refused
#     (`rm -rf .git/rebase-merge`), and neither is the bash glob of a toplevel
#     or worktree root (`rm -rf *`), which leaves its `.git` in place. By
#     design this also refuses a throwaway clone under temp, and every delete
#     in a working tree under ~/.claude.
#   * A target OUTSIDE THE SESSION'S ALLOWED ROOTS, judged only when the
#     payload carries an absolute `cwd`. A target must resolve under the git
#     toplevel of the payload cwd, or strictly under a temp root or the payload
#     `scratchpad_dir` (honored only when it sits strictly under a temp root);
#     a temp root itself, its glob and the scratchpad itself are refused. The
#     userConfig key block_root_delete_target_allowed_roots, read from the
#     hook's own environment and never from the command text, adds roots on
#     the temp-root rule: comma-separated absolute directories, compared by
#     real path, so a target is allowed only strictly under one, and the root
#     itself and its glob stay refused. An entry ending in one `*` after a
#     literal name (`D:/worktrees/.tmp-*`) is a NAME PREFIX instead: only a
#     direct child of its directory whose name extends the prefix by at least
#     one character passes, and never one that is itself a symlink, ends in
#     a dot or a space (Win32 trims them), or is named with a trailing slash
#     before it exists (a link the same command creates). An entry whose `*`
#     is one whole segment followed by one literal name
#     (`D:/worktrees/*/.work`) is a SEGMENT entry: only a path strictly under
#     that name exactly one directory level below its directory passes, never
#     the name itself, a symlink, a one-level name or a target ending in a
#     dot or a space, or a target named with a trailing slash before it
#     exists. An entry that is relative, empty, UNC, holds any other glob
#     character, a line break or a `..` component, or resolves
#     to a filesystem root or HOME grants nothing, and no listed root lets
#     through a filesystem root, HOME or a directory holding HOME. Every other
#     refusal in this guard runs before this judgment and ignores the key.
#     A directory a literal cd reaches is judged against the cwd's tree, never a
#     tree of its own. Unquoted braces are expanded the way bash expands them
#     and every alternative is judged as its own operand (a sequence, more
#     than 64 alternatives, a word over 4096 bytes or 128 braces, or a partly
#     quoted brace is refused). A glob before the last component is expanded
#     against the filesystem one component at a time and each match judged as
#     a literal path; every glob operand is also judged as its own literal
#     text, which bash passes when nothing matches; a `..` after a glob is
#     refused. An operand ending in `/` is resolved whole, because rm then
#     follows a symlink (a `*/` glob's symlink matches are read and judged by
#     where they point). `~name` and a newline in an operand are refused.
#     Operands are collected while the command is parsed and judged once at
#     the end, with one realpath, (on Windows) one cygpath and one git for the
#     whole command. Past 32 directories (counting the starting one), 512
#     directory-and-target pairs, 256 glob entries in total across the levels
#     of one glob, 25 seconds of wall time from this arm's first work (through
#     the rest of the parse and the judgment), or 50 seconds of the hook's
#     whole run once that work has begun, the guard refuses rather than risk
#     the hook timeout, and an unexpected error while judging refuses too.
#     The batched realpath and cygpath run under `timeout` for the time left
#     where `timeout` exists, and an operand over 4096 bytes or 128
#     separators is refused before any scan. Where `timeout` is absent
#     (stock macOS) a batch call cannot be cut short: the clock is checked
#     on both sides of it, and the operand caps are what keep one call short.
#     An
#     operand this guard cannot place (an expansion other than a leading HOME,
#     a drive-relative path) is left alone rather than guessed. A NUL byte in
#     the payload `cwd` or `scratchpad_dir` refuses a recursive delete this
#     arm must judge and leaves every other command alone; a NUL byte in the
#     command itself still refuses every call.
#
# KNOWN FALSE POSITIVES. These are refused although harmless, because the
# guard cannot tell them apart from a harmful spelling: a single-quoted `'$X'`
# (read as a bare variable), `~-` (read as `~name`), `cd sub && rm -rf ../x`
# and `(cd ..) ; rm -rf build` and `env -C /opt true; rm -rf build` (a
# relative operand must stay inside from every directory the command may run
# it from, because the guard does not assume a cd succeeded or which command a
# directory change applies to), `cd <worktree> && rm -rf .work/x`
# from a different checkout's cwd (every target is judged against the payload
# cwd's tree), a glob over directories of many entries (every entry read at
# every level of the glob counts toward the 256 cap, files included, so
# `rm -rf node_modules/*/` over a large directory and `rm -rf
# src/*/__pycache__` over a large `src` are refused), an operand over 4096
# bytes or 128 path separators, an expansion followed by a segment of
# punctuation alone (`${X:-{a,b}}/*` leaves a literal `}`, which names nothing
# here), a backslash-escaped brace (it reads as partly quoted), a find delete
# started at the git toplevel whose filters match nothing in `.git` (`find .
# -name '*.pyc' -delete`, or `find -name '*.pyc' -delete` run from there), and
# the same find as the listing piped into `xargs rm -rf`, an xargs delete in
# a child shell after a listing of its own and `;` or `&&` (`find build | bash
# -c 'find out; xargs rm -rf'`), any xargs delete inside a command
# substitution (`echo "$(find build | xargs rm -rf)"`), a pipeline whose text
# holds a quoted paren (`find build '(' -name a ')' | xargs rm -rf`), a
# BSD leading option ahead of a start point run from the toplevel (`find -E
# build -regex '.*\.o' -delete`: the GNU reading then has no start point and
# judges `.`), an rsync delete run with -n or --dry-run (judged as if it ran),
# an rsync delete whose sources glob outside the allowed roots (`rsync -a
# --delete /opt/x/* build/`: with a glob every operand is judged), a robocopy
# delete run with /L (judged as if it ran), a robocopy delete with a glob,
# brace or expansion in any operand (`robocopy /opt/x build *.log /MIR`, or
# `robocopy $env:SRC build /MIR` on PowerShell, where `$env:SRC` alone is
# then refused as a bare variable: every operand is judged), an option
# robocopy's page does not list, written ahead of the source (read as the
# source), a forced git worktree remove of a relative name after a cd or
# with git -C (`git -C sub worktree remove -f ../wt`), an interpreter delete
# whose path the code computes even when it lands inside the tree
# (`shutil.rmtree(tempfile.mkdtemp())`, `FileUtils.rm_rf(Dir['build/*'])`,
# perl `unlink glob '*.tmp'`, ruby `%w[...]`), a literal path holding a `$`
# (`rmtree('a$b')`) or an escape this reading does not decode (`'\x2f'`), a
# perl hash key named unlink or rmdir (`$h{unlink}`, read as a call on `$_`),
# a decoder writing to stdout anywhere before a shell on its own across `;`
# or `&&` (`base64 -d x; ls; bash`, read as a pipe), a decoder writing to
# stdout anywhere after an unquoted substitution an eval, a -c, a source or a
# stdin shell runs, or after a substitution in command position (`eval
# $(ssh-agent -s); base64 -d x`, `source <(kubectl completion bash); base64 -d
# x`, `` `npm bin`/x; base64 -d f | less ``) or a backtick after a separator
# inside a quoted string, xargs handing decoded items to a shell (`base64 -d x
# | xargs sh`), a PowerShell listing of the git toplevel piped into a removal
# (`gci -Recurse -Filter *.pyc | Remove-Item`, judged as `.`), an item removal
# fed by anything but a listing (`$files | % { $_.Delete() }`), a .NET delete
# whose path is an expression judged by its first word
# (`[IO.Directory]::Delete($env:TEMP + '\x')` as `$env:TEMP`), .Delete() on
# a grouping that is not one Get-Item or Get-ChildItem statement (a WMI
# object's), an -EncodedCommand holding text outside printable ASCII, a move
# into the tree from outside it (`mv ~/Downloads/x.zip .`, whose source is
# judged as moved away), a bare variable as a move's source or a file a
# content destroyer names (`mv "$f" out/`, refused as `rm -rf "$f"` is), an
# unquoted expansion as mv's last word (`mv out.log $TMPDIR/`: it may split
# into several words, so every operand is judged and `$TMPDIR/` is refused as
# a bare variable), an option's argument written after an operand (`mv a -t
# /opt/x`, judged as an operand too), a truncate that only extends a file
# (`truncate -s +1M /opt/x.img`, judged as if it shrank), an echo, printf or
# cat ahead of a shell that reads stdin across `;` or `&&` (`echo 'rm -rf /';
# bash`, read as a pipe), a relative target in a heredoc a shell reads that a
# later cd in the command moves (`bash <<'EOF'` over `rm -rf build`, then `cd
# /`: build is judged from `/` too), and the three launcher lines decided
# below.
#
# LAUNCHER LINES REFUSED BY DECISION (#4681). Each is refused although the
# launcher does not delete the host root, and each stays refused on purpose:
#   * `chrt -r rm -rf /`, `chrt -f rm -rf /` and a bare `chrt rm -rf /`
#     (round-robin by default). chrt reads the word after a realtime policy
#     as its priority, so it rejects these lines before exec: util-linux
#     2.39.3 through 2.41 exits 1 with "invalid priority argument", 2.42 on
#     with "policy <name> requires a priority argument". The same line
#     under `-o`, `-b`, `-i`, `-d` or `-e` does run `rm` from 2.42, where the
#     priority became optional for those policies, so a non-digit word after
#     chrt is always read as the command. The cost is one retry and never a
#     lost file.
#   * `runuser -u bob rm -rf /` without `--`. runuser's getopt permutes, so
#     `-rf` is read as its own option and the line exits 1 with "invalid
#     option -- 'r'". Under POSIXLY_CORRECT, which a command inherits without
#     showing it, options end at `rm` and the delete runs; the guard cannot
#     see the shell's environment, so it refuses on both readings.
#   * `chroot <dir> rm -rf /` and `rm -rf /*` under it. chroot's `/` is host
#     `<dir>`, so the bare `/` spelling empties `<dir>` and every host
#     directory bind-mounted inside it. An unquoted `/*` is expanded by the
#     invoking shell against the HOST root before chroot runs, so rm receives
#     the host's top-level names and resolves each under `<dir>`: still a
#     recursive delete inside `<dir>`, and still refused. Only GNU rm's
#     default --preserve-root stops the bare `/` spelling, and not those names
#     or `--no-preserve-root`. Not a harmless line, so kept on the refusal
#     side.
#
# SCOPE: this guard is friction against accidental or casual root deletes, not
# a sandbox (see the README Scope notes). The launcher grammar is not widened
# further without a filed bypass. Converging the PowerShell walker with
# lib/powershell/ps-command.sh stays deferred; any future convergence is
# checked against the delete lane in scripts/check-guardrails-ps-differential.sh.
#
# DECLARED GAPS, stated rather than hidden, matching this family's convention:
#   * PowerShell is covered for the same target classes as Bash, with its own
#     tokenizer (not lib/powershell/ps-command.sh, so this guard stays off the
#     classifier's sink-attempt budget). Matched: Remove-Item and its aliases
#     (ri, rm, del, erase, rd, rmdir) with -Recurse on any unambiguous prefix
#     (-r, -rec, -Recurse) or the bash-in-PS cluster -rf; cmd /c (and /k)
#     rd /s and rmdir /s; a pipeline into Remove-Item with no path; the
#     indirection forms POWERSHELL INDIRECTION AND PIPELINES lists; and
#     Move-Item, Clear-Content and a Set-Content of several files (MOVES AND
#     CONTENT DESTROYERS).
#     A statement ends at `; | & && ||` and at an unquoted newline (LF, CRLF or
#     a bare CR) that no backtick continues. An unquoted `(`, `$(` or `{`
#     opens a nested level whose statements are judged on their own, so a
#     delete after a newline or inside a scriptblock, a grouping or `$( )` is
#     caught; the closing `)` or `}` leaves one placeholder word in the
#     statement that was open, so that statement keeps its later arguments. A
#     target that is a `( )`, `$( )` or `@( )` grouping is refused, because its
#     value is not known: as a positional operand even without -Recurse, and
#     as a -Path value with it. So is a `{ }` scriptblock named as a target of
#     a recursive delete; as the value of -Filter, -Include or -Exclude it is
#     stepped over. The
#     operand `$env:NAME` or `${env:NAME}` is judged as the Bash lane judges
#     `$NAME` or `${NAME}`: refused bare or with only nameless segments after
#     it (`$env:TEMP`, `$env:TEMP\`, `$env:TEMP\*`), allowed with a named subpath
#     (`$env:TEMP\build`). A target whose every `$` is literal (single-quoted,
#     or escaped by a backtick) is judged as the path it names, and a Win32
#     stream suffix on it (`::$INDEX_ALLOCATION`, `:$I30:$INDEX_ALLOCATION`) is
#     judged as the file or directory before it. That reading is added to the
#     old one, which still reads every `$` as an expansion, so a literal
#     `'$env:TEMP'` or `'$HOME\x'` is refused as before. A target holding a
#     `$` PowerShell expands is left alone, as in Bash.
#     Still uncovered: a command word supplied only by a variable (`& $cmd
#     -Recurse C:\`), a `$( )` inside a double-quoted string, a command that
#     is not the first word of its statement (`$r = Remove-Item -Recurse
#     C:\`), a comma list of targets (`Remove-Item -Recurse ./x,C:\`), and a
#     here-string, which is read as ordinary quoting: its body is not judged,
#     and a quote character inside it ends the span early, so the code after
#     it is not judged either. Of the indirection forms (#9765): an iex string
#     or a Start-Process program or argument list held in a variable or built
#     by a grouping or `@( )` (one word in a grouping is read as iex's
#     string), a -WorkingDirectory that is not a literal path, whose program's
#     relative targets are judged from the payload cwd, a pipe into iex from
#     any stage but one word or Write-Output of one, `pwsh
#     -Command -` (stdin) and -File, Start-Process of a shell that is not
#     PowerShell (`bash -c`), a .Delete() on an object held in a variable or
#     built another way (`[IO.DirectoryInfo]::new(x).Delete($true)`,
#     `New-Object`), items a ForEach-Object stage changes before a removal, a
#     Set-Location before the delete, and an argument list whose quoted
#     element holds a comma (read as two words).
#   * In a move or content destroyer: the file mv or Move-Item overwrites at
#     its destination (only what it moves away is judged), an output
#     redirection (`> file`), a Set-Content of one file or of a path a
#     variable or grouping holds, an of= a brace builds (`dd {of=x,if=y}`), a
#     find action that runs mv, truncate or shred (`-exec mv {} out \;`), mv,
#     truncate, shred and dd on the PowerShell tool (where `mv` is read as
#     Move-Item), and Move-Item, Clear-Content and Set-Content from the Bash
#     tool.
#   * In a decoder sink: a decoder this guard does not name (openssl base64
#     -d, uudecode, an interpreter's base64 module), one behind a launcher
#     (`sudo base64 -d`), decoded text carried through a variable or a file
#     to the sink (`x=$(base64 -d f); eval "$x"`, `$b = ...; iex $s`), a sink
#     this guard does not name (an interpreter reading stdin, `pwsh -c -`,
#     `[scriptblock]::Create`, `&` or `.` of a decoded scriptblock), a quoted
#     substitution after source or a shell (`source "$(...)"`, read as a file
#     name), and a backtick after a launcher (`sudo` before one). A heredoc or
#     here-string a shell reads as its program is parsed as that program
#     (SHELLS AND LAUNCHERS FROM BASH), so a decoder sink inside it is refused.
#   * In interpreter code: a script file an interpreter runs, and a program
#     piped into its stdin (`cat x.py | python3`) or redirected to it from
#     outside its own command (`{ python3 -; } <<'EOF'`, `0<&3`); an
#     interpreter this guard does not name (deno, bun, php, a pythonw); a
#     deleter reached through an alias, an import under another name (`from
#     os import remove`), a path object's method (`Path(p).unlink()`,
#     `->remove_tree`) or a library outside the standard one; os.exec*,
#     os.spawn*, a perl `open` pipe, the `system { ... }` form and a glob
#     operand (`unlink <*.tmp>`), and a deleter call split across two -e
#     operands; a literal spelled across several (`'a' 'b'`), a quote-like
#     operator this reading does not take (perl `q {...}` with a space, `qx'...'`,
#     ruby `%x!...!`), and code this reading lexes wrong (a regex literal
#     holding a quote, a ruby `?'` character, a perl `s#a#b#` read as a
#     comment, and a comment character in a regex literal no `/` opens, such
#     as ruby `%r{#}` or perl `m{#}`, which hides the rest of its line: one
#     after a `/` on its line, as in `/\//` or `/#/`, is refused when the text
#     it hides names a deleter or a runner, or holds a backtick, a ruby %x
#     or a perl qx); a node option that takes a separate argument and is not
#     listed, written before the code (its argument is read as the script); a
#     heredoc index that both an opener with no body and an opener on a
#     segment with no word shift, under the same delimiter; and interpreter
#     code on the PowerShell tool, which is not read.
#   * In an rsync: a long option written as an abbreviation, a remote operand
#     (`host:/`), the paths a --files-from list names below a source
#     (the source operand itself is judged), and rsync on the PowerShell tool,
#     which is not read.
#   * In a robocopy: the options and paths a /JOB file supplies; a deleting
#     option that an expansion or a brace builds (`robocopy src / {/MIR,}`),
#     which is not seen, so nothing is judged; and an option robocopy's page
#     does not list, written between the source and the destination, which
#     is read as the destination, so the real one is not judged.
#   * In a pipeline-fed delete: a `;`, `&&` or `||` between a listing and
#     xargs, read as a pipe (`find build; xargs rm -rf` reads the shell's own
#     stdin); xargs splitting a listed path at a blank or a quote, so a
#     directory named `a ` holding `etc` lists as `build/a /etc` and xargs
#     hands rm `/etc` (`-0` with `-print0`, or `-d '\n'`, keeps a path whole); a
#     path a listing writes on stderr into the pipe (`2>&1`, `|&`); a symlink
#     below a find start point that -L or -follow makes find list through; and
#     parallel with no command, whose items from stdin or a file are commands
#     this guard never sees.
#   * In a find: an action that runs its deleter through a launcher or a child
#     shell (`-exec sudo rm`, `-exec sh -c 'rm …'`), the action command's own
#     operands (`-exec rm -rf /x \;` is judged by its start points alone),
#     a symlink below a start point that -L or -follow makes find follow, the
#     start points GNU find reads from a file with -files0-from (the BSD
#     reading of the same words is still judged), and find on the PowerShell
#     tool, which is not read.
#   * In a git worktree remove: a git alias that expands to one (`git -c
#     alias.x='worktree remove -f' x y`), one a find action runs (`-exec git
#     worktree remove -f {} \;`), a GIT_DIR exported earlier or inherited,
#     which selects another registry unseen, a worktree registered past
#     MAX_WORKTREES that a trailing-components name selects, and git on the
#     PowerShell tool, which is not read. A `--no-force` after -f is read as
#     forced. Items xargs or parallel hand it are judged as rm operands,
#     without the trailing-components lookup.
#   * From the Bash tool, `powershell -Command Remove-Item -Recurse <dir>`,
#     which is judged in the PowerShell lane only (#6626), and in a cmd /c
#     line: a command other than rd, rmdir and robocopy (`del /s`), a
#     `%NAME%` cmd expands (read as a literal name), a relative target after a
#     `cd` on the line (judged from the payload cwd), and a separator written
#     inside a word (`x&rd`), whose two statements are read as one.
#   * In a shell reading its program from stdin: a file (`sh < x.sh`, `cat
#     x.sh | sh`), text a filter changes on its way (`echo x | tr a b | sh`),
#     a printf conversion other than %s and %b, an echo or cat behind a
#     launcher (`sudo cat <<EOF | sh`), a heredoc a cat pipes to a child
#     shell whose own command reads it (`cat <<EOF | bash -c sh`), and a
#     program eval reads (`eval "$(cat)"`).
#   * Expansion-built targets AND an expansion-built command word. Detection
#     never evaluates a shell expansion. A bare variable operand is refused
#     (above), but `rm -rf "$X/build"` is left alone, and so are an unquoted
#     `$X/{a,b}` (its alternatives `$X/a` and `$X/b` are each left alone the
#     same way; the quoted `"$X"/{a,b}` is refused as a partly quoted brace)
#     and `$(printf 'r%s' 'm') -rf /`, whose substitution body is parsed (its
#     command word is `printf`) but whose RESULT is not. The root arm matches
#     `$HOME` and `${HOME}` as the literal text they are written as; only the
#     outside-tree arm expands them, from the hook's own HOME.
#   * In the Bash lane, a TYPED operand whose real file name holds a literal `$`
#     (`rm -rf 'a$b/'`) is read as an expansion and left alone by the
#     outside-tree arm, because the tokenizer's quoting provenance cannot
#     separate it from `"$X"`; only a name that a glob MATCHED is judged
#     literally.
#   * `~name` is refused by the outside-tree arm and not matched by the root
#     arm, which matches bare `~` only. `~`, `$HOME` and `${HOME}` expand from
#     the hook's own HOME, not from an inline `HOME=` assignment.
#   * Directory changes the outside-tree arm cannot follow. A literal `cd`,
#     `pushd`, `env -C` or `sudo -D` adds a directory the delete may run from,
#     and a cd whose target globs is followed to its one match; `cd "$d"`,
#     `cd -`, `popd`, `pushd +N` and a login shell (`su -`, `su -l`,
#     `runuser -l`, `sudo -i`) are not followed, and a relative operand after
#     one is left alone. A cd the guard can place but not follow, a relative
#     `cd` once CDPATH is set (inherited, assigned, exported or as a prefix)
#     or a glob target with no match or several, makes a relative operand
#     after it refused instead. `builtin cd` is not seen at all, because
#     `builtin` is not in the launcher table. A literal directory is collapsed
#     lexically, so `cd link/..` is read as `cd .`.
#   * A difference from the user-level destructive-removal engine, on purpose:
#     an unresolvable expansion is left alone rather than refused. This was
#     measured (#9770): over one operator's recorded corpus, refusing an
#     operand that still holds an expansion (`rm -rf "$X/build"`) fired on 900
#     of 5,926 delete-shaped commands that this guard otherwise passed, and in
#     at least 145 of them the target, with the value the command itself assigned
#     substituted, sat inside an allowed root. A blocking check ships with zero
#     false positives (ADR 0080), so the refusal stays out. Like the
#     engine, the git toplevel itself, `.git`, another worktree's root and
#     another session's scratchpad are refused even inside an allowed root,
#     and every target is judged against the payload cwd's tree, so an
#     absolute path into another worktree is refused.
#   * Protected trees this guard does not see: a repository nested below a
#     target, other than the toplevel and the registered worktrees (only a
#     `.git` directly inside the target, or matched by its glob, is tested);
#     a directory holding a `.git` that a glob in the last component matches
#     (`rm -rf clones/*`); a worktree registered past MAX_WORKTREES, which is
#     protected only by the `.git` file in its own root; a CLAUDE_CONFIG_DIR
#     outside ~/.claude; a Claude Code temp tree under CLAUDE_CODE_TMPDIR
#     that no payload scratchpad under a temp root names; and a glob shell
#     option (dotglob, globdots) set before the command, such as by a shell
#     snapshot, rather than named in it.
#   * A glob is expanded against the filesystem as it is when the hook runs;
#     a directory the command creates before the delete is not seen.
#   * Where `realpath -m` is absent (BSD, macOS), a target's parent is
#     collapsed lexically before its nearest existing ancestor is resolved, so
#     `link/..` is read as the directory holding `link`.
#   * A child shell this guard does not recognize as one. `bash -c`, `sh -c`,
#     their siblings, `su`'s `-c` / `--command` / `--session-command` operand,
#     GNU `env`'s `-S` / `--split-string` operand, and what eval, watch, wsl
#     and cmd /c run (SHELLS AND LAUNCHERS FROM BASH) ARE unwrapped and
#     re-parsed; an interpreter that is not a shell (`python -c`, `perl -e`)
#     is read by INTERPRETER DELETES instead, for its deleter calls and the
#     commands it runs.
#   * A LAUNCHER that is not in the launcher table in rdt_check_segment. The
#     table is an allow-list of names, so an unlisted launcher ends the walk
#     and its own name is read as the command word. runuser is read by its own
#     helper, because its getopt permutes: its -c operands are commands (su's
#     grammar) and, with -u, its non-option words are the command. `builtin`,
#     `doas`'s short clusters and `systemd-run`'s working directory are not
#     modeled: a service unit runs from `/` (or the user's home) unless
#     `--scope`, `-d` or `--working-directory` says otherwise, and a relative
#     operand under it is judged from the payload cwd.
#   * An operand-taking option of a listed launcher that its table does not
#     carry ends the walk at that option's operand, which is then read as the
#     command word: uutils `env -f FILE` / `--file FILE` (uutils 0.10.0), so
#     `env -f x rm -rf /` is not refused.
#   * sudo's `-R` / `--chroot`, a short cluster ending in an operand-taking
#     letter (`sudo -Eu bob …`), and an abbreviated long option (`sudo --us bob
#     …`) are judged on two readings, blocking if either does: as a flag, so
#     the word after it stays the command word (`sudo -R rm -rf /`), and as
#     taking that word, so the one after is the command (`sudo -R /mnt rm -rf
#     /`) (#4685).
#   * A command word split across quoting so the RAW text never spells it.
#     `\rm` and `RM` are caught, because the cheap substring prefilter below
#     folds case and the raw text still reads `rm`; `r\m`, `r''m` and `"r"m`
#     are not, because the prefilter exits allow before the tokenizer rejoins
#     them, and neither is a find whose `-delete` is split the same way
#     (`-del''ete`). That is the price of not tokenizing every Bash call, and
#     it is the right trade here: this guard's threat model is an agent making
#     the mistake #92593 records, not one deliberately obfuscating a command
#     word.
#
# BLOCKING: on a recursive delete of a root, of an empty or
# bare-variable operand, of a protected tree, of a target outside the allowed
# roots, on items no confined listing produced, or on an interpreter deleter
# whose path is not a plain string literal, asks the user when the session is attended and exits 2
# otherwise (hook::refuse, refuse.sh). A command it cannot finish reading, a
# decoder sink and an -EncodedCommand it cannot decode are denied either way.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED:-true}" == "true" ]] || exit 0

# The hook's own directory, by parameter expansion rather than `dirname`: GNU
# Bash forks a subshell for every command substitution even when the body is a
# builtin (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution), and on Windows Git Bash that
# fork is a process. The fallback covers a bare filename.
_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run"
# notice; 0 (allow) and 2 (block) pass through unchanged.
guard::abort_boundary block-root-delete-target PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
# shellcheck source=refuse.sh
source "$_HOOK_SELF/refuse.sh" || exit 70 # not a chosen status: the boundary reports it

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry. Referencing
# it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) is a skip; rc 2 (text that is not JSON) FAILS CLOSED, because a
# guard that cannot evaluate the tool call must not pass exactly the traffic it
# exists to stop; rc 3 (a payload the pipe cut short) is a loud skip the
# dispatcher takes once and has already reported.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq parses the tool payload, and this guard FAILS CLOSED on its absence, the
# same posture as the other blocking Bash guards.
hook::require_jq_blocking "guardrails-block-root-delete-target" "block_root_delete_target_enabled"

# Two fields, one extraction, primed by the dispatcher. Never
# `.tool_input.content` or any write payload: this guard reads a command and
# where it runs, nothing else. `.cwd` is read after the `rm` prefilter, and
# `.scratchpad_dir` only when a target needs judging, each in its own call so
# a NUL byte in either is judged apart from the command's.
jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
if ((jq_rc == 2)); then
  guard::refuse_unparsable
  exit 2
fi
((jq_rc != 0)) && exit 0

# A NUL byte in the command or the tool name is fail-CLOSED, for every call:
# what a guard can read is then not dependably what would run, and a NUL in
# the command could hide an `rm` from the prefilter below.
if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
PAYLOAD_CWD=""
RDT_CWD_NUL=0

# Bash and PowerShell only. Exiting on every other tool keeps this guard off
# the classifier's load path. The PowerShell lane uses a dedicated tokenizer
# below and does not call the shared classifier.
[[ "$TOOL_NAME" == "Bash" || "$TOOL_NAME" == "PowerShell" ]] || exit 0

# hook::jq_fields drops every CR from a field, but PowerShell ends a statement
# at a bare CR as well as at LF, so `Get-Location<CR>Remove-Item ...` would
# read as one glued word. On the PowerShell tool the command is read again
# from the payload with a JSON CR escape (`\r`, `\u000d`) spelled as an LF and
# a CRLF pair as one LF, which is what the read above already made of it. The
# `\\` pairs are set aside first so an escaped backslash before an `r` (a
# Windows path such as `C:\\repos`) is not taken for a CR escape.
if [[ "$TOOL_NAME" == "PowerShell" && ("$INPUT" == *'\r'* || "$INPUT" == *'\u000'[dD]*) ]]; then
  rdt_bs=$'\\'
  rdt_cr="${rdt_bs}r" rdt_lf="${rdt_bs}n"
  rdt_in="${INPUT//"$rdt_bs$rdt_bs"/$'\001'}"
  rdt_in="${rdt_in//"${rdt_bs}u000d"/"$rdt_cr"}"
  rdt_in="${rdt_in//"${rdt_bs}u000D"/"$rdt_cr"}"
  rdt_in="${rdt_in//"${rdt_bs}u000a"/"$rdt_lf"}"
  rdt_in="${rdt_in//"${rdt_bs}u000A"/"$rdt_lf"}"
  rdt_in="${rdt_in//"$rdt_cr$rdt_lf"/"$rdt_lf"}"
  rdt_in="${rdt_in//"$rdt_cr"/"$rdt_lf"}"
  rdt_in="${rdt_in//$'\001'/"$rdt_bs$rdt_bs"}"
  if [[ "$rdt_in" != "$INPUT" ]] && hook::jq_fields "$rdt_in" '.tool_input.command'; then
    COMMAND="${HOOK_JQ_FIELDS[0]}"
  fi
fi

# Nothing to inspect.
[[ -n "$COMMAND" ]] || exit 0

# Above this length the command is not parsed, and the guard fails closed: the
# same ceiling the other argv-faithful Bash guards carry, and the reason
# require-jq-posture.test.sh classes this guard with them.
MAX_COMMAND_LEN=16384

# Command substitutions may nest, and the scanner descends one level per `$(`.
# A payload well under MAX_COMMAND_LEN can spell thousands of levels, so the
# descent is capped and the cap REFUSES rather than allows: the guard's abort
# boundary is fail-OPEN, so a scanner that ran out of room would hand back an
# allow on exactly the input built to exhaust it.
MAX_SUBST_DEPTH=32

# Launcher, child-shell and eval nesting is recursion in rdt_check_segment,
# capped the same way and for the same reason: past the cap the guard REFUSES.
# 24 is far above any command a person writes and far below the depth where
# bash exhausts its stack (about 100 levels of runuser on Git Bash).
MAX_SEGMENT_DEPTH=24
rdt_depth=0

# The depth cap bounds how deep a reading goes, not how many there are. A
# launcher read two ways (runuser's -s program and its -u argv) doubles the
# segments at every level, so 20 levels are a million walks, and a hook the
# harness cancels on its timeout is cancelled WITHOUT a block. Every NESTED
# segment (one a launcher, child shell, eval or resolved walk re-enters) is
# counted for the whole command, and past the budget the guard REFUSES.
# Top-level segments are left out: the command's own length bounds them, and a
# 16 KB command of substitutions can hold several thousand. 1024 nested
# launcher segments cost about 2 s on Git Bash, well inside the hook timeout,
# and a realistic command nests a handful.
MAX_SEGMENTS=1024
rdt_segments=0

rdt_emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  # Resolved here, not at top level: the subject is a telemetry field, so it is
  # computed only when a sink is wired.
  local SUBJECT data
  hook::extract_bash_subject_to SUBJECT "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$SUBJECT" form "$2"
  hook::emit_telemetry "block-root-delete-target" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# rdt_block <form> [target]: refuse and say why (hook::refuse, or exit 2). The target is echoed
# back as the guard NORMALIZED it, so the operator can see which word was read
# as a root rather than guessing.
rdt_block() {
  local form="$1" target="${2:-}" msg
  case "$form" in
  no-preserve-root)
    printf -v msg '%s\n' \
      'BLOCKED: this is a recursive delete carrying --no-preserve-root.' \
      'Fix: drop --no-preserve-root and name the directory to remove explicitly, under the working tree.'
    ;;
  too-long)
    printf -v msg '%s\n' \
      'BLOCKED: the command is too long to parse, so a recursive delete inside it cannot be ruled out.' \
      'Fix: split it into shorter commands, or write it to a script and run that.'
    ;;
  nesting-too-deep)
    printf -v msg '%s\n' \
      "BLOCKED: substitution nesting deeper than $MAX_SUBST_DEPTH." \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.'
    ;;
  eval-too-long)
    printf -v msg '%s\n' \
      'BLOCKED: eval, parallel, interpreter-spawned and substitution text exceeds MAX_COMMAND_LEN in total.' \
      'Fix: drop the nested evals or parallel options, or run the inner command on its own.'
    ;;
  too-many-readings)
    printf -v msg '%s\n' \
      'BLOCKED: too many launcher readings to judge every one; flatten the command.' \
      'Fix: drop the repeated launchers, or run the inner command on its own.'
    ;;
  nesting-too-deep-launcher)
    printf -v msg '%s\n' \
      "BLOCKED: launcher or eval nesting deeper than $MAX_SEGMENT_DEPTH; flatten the command." \
      'Fix: drop the repeated launchers, or run the inner command on its own.'
    ;;
  too-many-abbreviations)
    printf -v msg '%s\n' \
      'BLOCKED: too many command segments with abbreviated launcher options to judge every reading; spell the options in full.' \
      'Fix: spell the launcher options in full (flock --wait 5), or split the command into shorter ones.'
    ;;
  bodies-too-long)
    printf -v msg '%s\n' \
      'BLOCKED: substitution bodies exceed MAX_COMMAND_LEN in total.' \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.'
    ;;
  empty-operand)
    printf -v msg '%s\n' \
      'BLOCKED: this recursive delete has an empty operand ("").' \
      'Fix: name the directory to remove explicitly, or drop the empty word.'
    ;;
  pipeline-target)
    printf -v msg '%s\n' \
      'BLOCKED: this recursive delete takes its target from the pipeline or a grouping, which this guard cannot name.' \
      'Fix: name the directory to remove as a -Path or -LiteralPath operand, written out literally.'
    ;;
  pipeline-feed)
    printf -v msg '%s\n' \
      'BLOCKED: xargs or parallel runs a recursive delete on items no confined listing produced (read from a file, from the stdin of the shell, or from a command other than find or git ls-files), so this guard cannot name its targets.' \
      'Fix: pipe find <dir> (without -printf, -ls or -exec) or git ls-files into it, through grep, sort, uniq, head or tail at most, or name the targets as operands.'
    ;;
  bare-variable)
    # Single-quoted on purpose: the text shows a literal ${NAME:?}.
    # shellcheck disable=SC2016
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete targets a bare variable ('$target'), whose value is not known until it runs." \
      'Fix: write the path out literally, or use "${NAME:?}/sub" so an unset or empty value aborts the command before rm runs.'
    ;;
  outside-tree)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target, outside the working tree, the temp directories, the session scratchpad and the roots in block_root_delete_target_allowed_roots." \
      'Fix: delete only strictly under one of those (put scratch work under the working tree, for example a gitignored .work/), and do not retry the delete with another tool (find -delete, rmtree, git clean).' \
      'Otherwise the user runs it, or lists its root in block_root_delete_target_allowed_roots (only the user can).'
    ;;
  protected-tree)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target. A protected tree is refused even under the working tree, a temp root or an allowed root." \
      'Fix: name only the paths inside it you mean to remove, and do not retry the delete with another tool (find -delete, rmtree, git clean); remove a worktree with git worktree remove.' \
      'Otherwise the user runs it, or drops it from block_root_delete_target_protected_trees when it is listed there (only the user can).'
    ;;
  too-many-origins)
    printf -v msg '%s\n' \
      "BLOCKED: too many directory changes to judge every place this delete may run from (more than $MAX_ORIGINS)." \
      'Fix: cd once to an absolute directory, or run the delete as its own command.'
    ;;
  too-many-targets)
    printf -v msg '%s\n' \
      "BLOCKED: too many recursive delete targets to judge (more than $MAX_TARGETS directory-and-target pairs)." \
      'Fix: delete a parent directory, or split the delete into shorter commands.'
    ;;
  too-many-glob-entries)
    printf -v msg '%s\n' \
      "BLOCKED: a glob in this recursive delete reads more than $MAX_GLOB directory entries, files included." \
      'Fix: narrow the glob to the names you mean, or delete the parent directory whole.'
    ;;
  operand-too-long)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete names $target." \
      'Fix: check how the command was built; name the directory to remove directly.'
    ;;
  too-slow)
    printf -v msg '%s\n' \
      "BLOCKED: judging where this recursive delete lands ran out of time (a bound of $RDT_DEADLINE seconds for the judgment, $RDT_DEADLINE_ABS for the whole hook)." \
      'Fix: delete fewer targets per command, or cd once to an absolute directory first.'
    ;;
  unplaceable)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target, which cannot be judged (another user's home, a newline, \`..\` after a glob, or a cd CDPATH may redirect)." \
      'Fix: write the target as an absolute or working-tree-relative path.'
    ;;
  interp-unplaceable)
    printf -v msg '%s\n' \
      "BLOCKED: interpreter code deletes or runs $target, which this guard cannot read: only a plain string literal is judged." \
      'Fix: write the path or command in the code as a plain string literal, or delete with rm -rf <path> as its own command.'
    ;;
  brace)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete has a brace expansion ($target) that cannot be judged alternative by alternative." \
      'Fix: write each target out as its own operand.'
    ;;
  brace-too-large)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete has a brace expansion ($target) too large to expand in time." \
      'Fix: write each target out as its own operand.'
    ;;
  nul-field)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete cannot be judged, because the hook payload's $target carries a NUL byte." \
      'Fix: reissue the tool call; if it repeats, report the malformed payload.'
    ;;
  control-bytes)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target, whose \$ signs cannot be read as literal or expanded because the command carries every control byte the guard could mark them with." \
      'Fix: remove the control characters from the command.'
    ;;
  judge-error)
    printf -v msg '%s\n' \
      'BLOCKED: judging where this recursive delete lands failed unexpectedly.' \
      'Fix: simplify the command, or run the delete on its own.'
    ;;
  decoder-sink)
    # Denied in an attended session too: the decoded text never appears in the
    # command, so there is nothing a person could judge from it.
    printf -v msg '%s\n' \
      'BLOCKED: decoded text (base64 -d, base32 -d, basenc -d, xxd -r or [Convert]::FromBase64String) is run as a command, by a shell, eval, source, Invoke-Expression or a substitution in command position, so this guard cannot read what would run.' \
      'Fix: decode to a file, read it, and run the commands it holds as commands of their own.'
    ;;
  encoded-unreadable)
    # Denied in an attended session too, for the reason decoder-sink gives.
    printf -v msg '%s\n' \
      'BLOCKED: this -EncodedCommand is not a literal base64 string of UTF-16LE text this guard can read (printable ASCII, tab and line breaks), so a delete inside it cannot be ruled out.' \
      'Fix: pass the command as -Command text, or run what it holds as a command of its own.'
    ;;
  *)
    # Single-quoted on purpose: the Fix line must show a literal $HOME to the
    # agent rather than expanding it in the hook process.
    # shellcheck disable=SC2016
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of a filesystem root (normalizes to '$target')." \
      'Fix: name the directory to remove, relative to the working tree. $HOME and ~ are matched as written, not expanded.'
    ;;
  esac
  rdt_emit_tel "blocked" "$form"
  case "$form" in
  # The guard read the delete and names what it would remove: the user can
  # judge that, so an attended session asks (refuse.sh).
  no-preserve-root | empty-operand | pipeline-target | pipeline-feed | bare-variable | outside-tree | protected-tree | unplaceable | interp-unplaceable | brace | root-operand)
    # Attended, the reason is recorded and the reading goes on (refuse.sh).
    hook::refuse "${msg%$'\n'}"
    return 0
    ;;
  *) ;;
  esac
  # The guard could not finish reading the command (a budget, a deadline, a
  # malformed payload): nothing names what would run, so it denies either way.
  printf '%s' "$msg" >&2
  exit 2
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  rdt_block "too-long"
fi

# Cheap prefilter ahead of the character walk. A command whose TEXT cannot
# carry a verb this matcher recognizes must not pay for the parse. Folded to
# lower case: on Windows both the filesystem and the PATH lookup are
# case-insensitive, so `RM -rf /` and `REMOVE-ITEM -Recurse C:\` run.
# A case-SENSITIVE prefilter here would have exited allow first, a bypass of
# the whole guard rather than a missed spelling.
#
# Bash: a substring `rm`, `-delete`, `.delete`, `unlink`, `rsync`,
# `robocopy`, `worktree`, `remove`, `mv`, `truncate`, `shred` or `of=`, the
# text a recursive rm, a deleting find, rsync, robocopy, git worktree remove,
# interpreter delete, move or content destroyer must hold (`npm run format`
# still reaches the tokenizer and is allowed on its command word),
# `base64`, `base32`, `basenc` or `xxd`, which a decoder sink holds, or `cmd`
# followed by `rd`, which a `cmd /c rd /s` holds.
# PowerShell: Remove-Item, rmdir, erase, cmd, rd, del (which `.Delete(`
# holds), rm, robocopy, FromBase64, pwsh and powershell (an -EncodedCommand
# hides its text), move, mv, Clear-Content and Set-Content, and `ri`, `mi` or
# `clc` as a command word (not the `ri` inside Write/string). Over-inclusive
# on purpose; the tokenizer decides.
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  rdt_ps_pre="${COMMAND,,}"
  rdt_ps_hit=0
  case "$rdt_ps_pre" in
  *rm* | *remove-item* | *erase* | *cmd* | *rd* | *del* | *robocopy* | *frombase64* | *pwsh* | *powershell* | \
    *move* | *mv* | *clear-content* | *set-content*) rdt_ps_hit=1 ;;
  *) ;;
  esac
  if ((rdt_ps_hit == 0)) && [[ "$rdt_ps_pre" =~ (^|[^[:alnum:]_])(ri|mi|clc)([^[:alnum:]_]|$) ]]; then
    rdt_ps_hit=1
  fi
  ((rdt_ps_hit)) || exit 0
else
  case "${COMMAND,,}" in
  *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
    *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) ;;
  *) exit 0 ;;
  esac
fi

# The payload cwd, for the outside-tree arm. A NUL byte in it does not refuse
# the call here: only a recursive delete this arm must judge is refused
# (rdt_check_operand), and any other command is unaffected.
if hook::jq_fields "$INPUT" '.cwd'; then
  if ((HOOK_JQ_FIELDS_NUL)); then
    RDT_CWD_NUL=1
  else
    PAYLOAD_CWD="${HOOK_JQ_FIELDS[0]:-}"
  fi
fi

# rdt_normalize_to <var> <operand>: the operand as this guard compares it.
# Backslashes become slashes so the Windows and MSYS spellings of one path share
# a matcher, the result is lowercased for a case-insensitive drive compare,
# runs of slashes collapse, ONE trailing glob suffix is dropped, and trailing
# slashes are trimmed unless the whole operand is slashes. Pure shell: a
# `printf | tr` pipeline would be a fork and an exec per operand.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_normalize_to() {
  local __rdt_dest="$1" __rdt_s="$2"
  __rdt_s="${__rdt_s//\\//}"
  __rdt_s="${__rdt_s,,}"
  # A leading EXACTLY-two-slash prefix is preserved through the collapse,
  # because on Windows it introduces a UNC path and `//server/share` is a share
  # root, the same class of unrecoverable loss as a drive root. Every other run
  # of slashes collapses, so `\\` still reduces to `/` and is still refused.
  local __rdt_lead=""
  if [[ "$__rdt_s" == //* && "$__rdt_s" != ///* ]]; then
    __rdt_lead="/"
    __rdt_s="${__rdt_s#/}"
  fi
  while [[ "$__rdt_s" == *//* ]]; do
    __rdt_s="${__rdt_s//\/\//\/}"
  done
  __rdt_s="$__rdt_lead$__rdt_s"
  # Drop trailing path segments that carry no NAME. A segment holding no
  # alphanumeric and no underscore names nothing on its own: it is a glob, a
  # `.`, a `..`, or the empty segment a trailing slash leaves behind, so the
  # operand is still rooted where it started. Stripping ONE glob suffix was not
  # enough, because the residue can be another nameless segment: `/*/` keeps a
  # trailing slash, `/./*` keeps a dot, and `/.[!.]*`, the ordinary dotfile
  # idiom, keeps both. The loop reduces each of those to `/`.
  #
  # The name test is what bounds it. `/tmp*`, `~/proj*` and `/c/dev/*` stop at
  # their first named segment and stay ordinary deletes, and a directory
  # literally named `_` (`/_`) is named, so it is not a root.
  #
  # A slash inside a `${...}` is part of the expansion, not a path separator,
  # so `${X:-/}` and `${X:-${Y:-/}}` are never cut open.
  rdt_strip_nameless_to __rdt_s "$__rdt_s" 0
  printf -v "$__rdt_dest" '%s' "$__rdt_s"
}

# rdt_strip_nameless_to <var> <text> <min cut>: <text> without its trailing
# path segments that carry no name (no letter, digit or underscore), cut only
# at a `/` outside every `${...}` whose index is at least <min cut>. With a min
# cut of 0 a text cut down to nothing becomes `/`. A `${...}` ends where bash
# ends it: only `${` nests, and the first `}` closes the innermost one, so a
# bare `{` inside counts for nothing.
#
# ONE pass over the text finds every outer slash, and the strip walks them
# from the end, so the cost is linear in the operand. Rescanning the text for
# each stripped segment was quadratic, and a 2 KB operand of `/*` segments
# behind a `${X}` took over 30 s: past the hook timeout the harness cancels
# the hook WITHOUT a block, which would fail open for the rest of the command.
# shellcheck disable=SC2016,SC2329  # literal `${` pattern; invoked from rdt_normalize_to and rdt_strip_tail_to
rdt_strip_nameless_to() {
  local __sn_s="$2" __sn_min="$3" __sn_i __sn_d=0 __sn_k __sn_cut __sn_end
  local -a __sn_cuts=()
  # No `%/*` shortcut: bash matches a suffix pattern by trying every start
  # position, so a loop of them over a long operand of short segments is
  # quadratic per strip and took over a minute at 4 KB.
  for ((__sn_i = 0; __sn_i < ${#__sn_s}; __sn_i++)); do
    case "${__sn_s:__sn_i:1}" in
    '$')
      if [[ "${__sn_s:__sn_i+1:1}" == '{' ]]; then
        __sn_d=$((__sn_d + 1))
        __sn_i=$((__sn_i + 1))
      fi
      ;;
    '}') ((__sn_d > 0)) && __sn_d=$((__sn_d - 1)) ;;
    /) ((__sn_d == 0)) && __sn_cuts+=("$__sn_i") ;;
    *) ;;
    esac
  done
  __sn_end=${#__sn_s}
  for ((__sn_k = ${#__sn_cuts[@]} - 1; __sn_k >= 0; __sn_k--)); do
    __sn_cut=${__sn_cuts[__sn_k]}
    ((__sn_cut >= __sn_min)) || break
    [[ "${__sn_s:__sn_cut+1:__sn_end-__sn_cut-1}" == *[[:alnum:]_]* ]] && break
    __sn_end=$__sn_cut
  done
  __sn_s="${__sn_s:0:__sn_end}"
  [[ -z "$__sn_s" && "$__sn_min" == 0 ]] && __sn_s="/"
  printf -v "$1" '%s' "$__sn_s"
}

# rdt_is_root <normalized>: true when the operand names a filesystem root.
# An operand that normalized to the EMPTY string is NOT a root: `rm -rf ""` is
# refused by the empty-operand arm ahead of this one, with its own message,
# while `rm -rf "\\"`, whose single backslash normalizes to `/`, is a root.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_is_root() {
  local s="$1"
  [[ -n "$s" ]] || return 1
  # The two HOME spellings are single-quoted because they are LITERAL TEXT here:
  # the tokenizer hands over the characters the operator wrote, and this guard
  # never evaluates an expansion.
  # shellcheck disable=SC2016  # matching the literal text, not expanding it
  case "$s" in
  '/' | '~' | '$home' | '${home}') return 0 ;;
  *) ;;
  esac
  # Every remaining slash run reduced to one, so a string of slashes alone is
  # the POSIX root however it was spelled (`/`, `\`, `\\`, `///`).
  [[ "$s" =~ ^/+$ ]] && return 0
  # A UNC share root: exactly two leading slashes, a host, a share, nothing more.
  [[ "$s" =~ ^//[^/]+/[^/]+$ ]] && return 0
  [[ "$s" =~ ^[a-z]:$ ]] && return 0
  [[ "$s" =~ ^/[a-z]$ ]] && return 0
  [[ "$s" =~ ^/cygdrive/[a-z]$ ]] && return 0
  [[ "$s" =~ ^/mnt/[a-z]$ ]] && return 0
  return 1
}

# rdt_runuser_argv <offset> <words after runuser>: read runuser's argv the way
# its getopt does. The optstring has no leading `+`, so getopt PERMUTES:
# options are recognized anywhere before the first `--`, and every non-option
# word, wherever it sits, is collected in order. Results, in globals the
# caller copies at once because a nested parse can re-enter this:
#   RDT_RU_CMDS   every -c / --command / --session-command operand (su's grammar)
#   RDT_RU_U      1 when -u / --user was given, which makes it a launcher;
#                 runuser-only (su has no -u)
#   RDT_RU_ARGV   the non-option words, then everything after the first `--`
#   RDT_RU_QUOTED the quoting provenance of each RDT_RU_ARGV word, copied from
#                 HOOK_SEG_WORD_QUOTED at <offset> plus its original position
#   RDT_RU_SHELL  the last -s / --shell operand, empty when none was given
# A short cluster holding a letter runuser rejects, or a long option it does
# not know or cannot resolve, makes runuser refuse the whole invocation. Once
# a non-option has been seen, that word is kept as one rather than read as
# options, so `runuser -u bob rm -rf /` still reads `-rf` as rm's flag.
# Ahead of every non-option it is dropped, so it never becomes the command
# word (`runuser -u root --foo rm -rf /`).
# With RDT_RU_POSIX=1 the words are read the way getopt reads them when
# POSIXLY_CORRECT is set, which no payload shows because it can be inherited:
# the first non-option ends the options and every word from it on is kept, so
# a later `-s env` is an argument, not the shell. Each caller judges both
# readings (#4685).
# su shares this option parser, so its arm reads su's argv here too, to find
# the words that follow a -s program that is not a shell.
RDT_RU_POSIX=0
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_runuser_argv() {
  local off="$1"
  shift
  local -a a=("$@")
  local n=$# k=0 m w name hit hits opt ch val bad
  RDT_RU_CMDS=()
  RDT_RU_ARGV=()
  RDT_RU_QUOTED=()
  RDT_RU_U=0
  RDT_RU_SHELL=""
  while ((k < n)); do
    w="${a[k]}"
    case "$w" in
    --)
      for ((m = k + 1; m < n; m++)); do
        RDT_RU_ARGV+=("${a[m]}")
        RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + m]:-0}")
      done
      return 0
      ;;
    --?*)
      # getopt_long: an exact name wins, otherwise a UNIQUE prefix; an
      # ambiguous or unknown name is an error that consumes nothing more.
      name="${w#--}"
      name="${name%%=*}"
      hit=""
      hits=0
      for opt in command session-command fast login preserve-environment pty no-pty shell group supp-group user whitelist-environment help version; do
        if [[ "$opt" == "$name" ]]; then
          hit="$opt"
          hits=1
          break
        fi
        if [[ -n "$name" && "$opt" == "$name"* ]]; then
          hit="$opt"
          hits=$((hits + 1))
        fi
      done
      ((hits == 1)) || hit=""
      if [[ -z "$hit" ]]; then
        # Never the command word, only an operand after it (see below).
        if ((${#RDT_RU_ARGV[@]} == 0)); then
          k=$((k + 1))
          continue
        fi
        RDT_RU_ARGV+=("$w")
        RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + k]:-0}")
        k=$((k + 1))
        continue
      fi
      k=$((k + 1))
      case "$hit" in
      command | session-command | shell | group | supp-group | user | whitelist-environment)
        if [[ "$w" == *=* ]]; then
          val="${w#*=}"
        else
          val="${a[k]-}"
          ((k < n)) && k=$((k + 1))
        fi
        [[ "$hit" == "command" || "$hit" == "session-command" ]] && RDT_RU_CMDS+=("$val")
        # su builds `sh -c -- CMD` from an operand of `--`, so CMD is the next word.
        [[ ("$hit" == "command" || "$hit" == "session-command") && "$val" == "--" ]] && ((k < n)) && RDT_RU_CMDS+=("${a[k]}")
        [[ "$hit" == "user" ]] && RDT_RU_U=1
        [[ "$hit" == "shell" ]] && RDT_RU_SHELL="$val"
        ;;
      *) ;;
      esac
      continue
      ;;
    -?*)
      # A short cluster: flags, then at most one operand-taking letter, which
      # takes the rest of the word or, when it is last, the next word.
      bad=0
      for ((m = 1; m < ${#w}; m++)); do
        ch="${w:m:1}"
        case "$ch" in
        f | l | m | p | P | T | h | V) ;;
        c | g | G | s | u | w) break ;;
        *)
          bad=1
          break
          ;;
        esac
      done
      if ((bad == 0)); then
        k=$((k + 1))
        if ((m < ${#w})); then
          val="${w:m+1}"
          if [[ -z "$val" ]]; then
            val="${a[k]-}"
            ((k < n)) && k=$((k + 1))
          fi
          [[ "$ch" == "c" ]] && RDT_RU_CMDS+=("$val")
          [[ "$ch" == "c" && "$val" == "--" ]] && ((k < n)) && RDT_RU_CMDS+=("${a[k]}")
          [[ "$ch" == "u" ]] && RDT_RU_U=1
          [[ "$ch" == "s" ]] && RDT_RU_SHELL="$val"
        fi
        continue
      fi
      # A rejected cluster, like an unknown long option, is never the
      # command word.
      if ((${#RDT_RU_ARGV[@]} == 0)); then
        k=$((k + 1))
        continue
      fi
      ;;
    *) ;;
    esac
    if ((RDT_RU_POSIX)); then
      for ((m = k; m < n; m++)); do
        RDT_RU_ARGV+=("${a[m]}")
        RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + m]:-0}")
      done
      return 0
    fi
    RDT_RU_ARGV+=("$w")
    RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + k]:-0}")
    k=$((k + 1))
  done
  return 0
}

# rdt_ru_key_to <var>: one string that differs whenever two rdt_runuser_argv
# results do, so a second reading identical to the first is not walked again.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_ru_key_to() {
  local -n _rk_out="$1"
  printf -v _rk_out '%q ' "$RDT_RU_U" "$RDT_RU_SHELL" "${#RDT_RU_CMDS[@]}" ${RDT_RU_CMDS[@]+"${RDT_RU_CMDS[@]}"} \
    "${#RDT_RU_ARGV[@]}" ${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"} ${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"}
}

# rdt_su_shell_run: su and runuser exec their -s / --shell program with the
# words after the user as its arguments. When that program is not a shell, it
# is the command itself (`su root -s /bin/rm -- -rf /`), so it is judged as
# one. Reads the RDT_RU_* results of the rdt_runuser_argv call just made, and
# must run before any parse re-enters it.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_su_shell_run() {
  local prog="$RDT_RU_SHELL" name
  [[ -n "$prog" ]] || return 0
  name="${prog##*/}"
  name="${name,,}"
  name="${name%.exe}"
  case "$name" in
  bash | sh | zsh | dash | ksh | mksh) return 0 ;;
  *) ;;
  esac
  local -a av=(${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"}) avq=(${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"})
  HOOK_SEG_WORD_QUOTED=(0 ${avq[@]+"${avq[@]:1}"})
  rdt_check_segment "$prog" ${av[@]+"${av[@]:1}"}
}

# rdt_short_cluster_arg <launcher> <cluster>: true when a short cluster such as
# `-nw` holds a letter that takes an operand. getopt walks the letters, and the
# FIRST operand-taking one takes the rest of the cluster, or the next word when
# it is the last letter; RDT_SC_NEXT is 1 in that second case. A letter whose
# operand is OPTIONAL (nsenter's `-m`) takes the rest of the cluster and never
# the next word, so it ends the walk with nothing to report. The letters come
# from each launcher's getopt string; doas is a declared gap, and taskset,
# chroot and setpriv have no operand-taking short option. sudo's `-R`, `-a`
# and `-c` alone are judged here too, because the plain walk steps over them
# (see the sudo row of the launcher table).
# env's `-S` is absent: its operand is a command, re-parsed by env's own arm.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_short_cluster_arg() {
  local w="$2" ops opt="" k ch
  RDT_SC_NEXT=0
  case "$1" in
  sudo)
    ops="aCcDgpRrTtUu"
    opt="h"
    ;;
  env) ops="aCu" ;;
  prlimit)
    ops="po"
    opt="cdefilmnqrstuvxy"
    ;;
  systemd-run) ops="HMCupE" ;;
  chrt) ops="DPTUX" ;;
  flock) ops="wE" ;;
  unshare) ops="RwSGl" ;;
  nsenter)
    ops="tNSG"
    opt="muinpCUTrwW"
    ;;
  numactl) ops="iwpPcNCmSfoLMI" ;;
  *) return 1 ;;
  esac
  for ((k = 1; k < ${#w}; k++)); do
    ch="${w:k:1}"
    if [[ "$ops" == *"$ch"* ]]; then
      ((k == ${#w} - 1)) && RDT_SC_NEXT=1
      return 0
    fi
    [[ -n "$opt" && "$opt" == *"$ch"* ]] && return 1
  done
  return 1
}

# rdt_long_takes_arg <launcher> <name>: true when `--<name>`, written without
# `=`, takes the next word as its operand. getopt_long accepts any unambiguous
# prefix, so `flock --wa 5` is `flock --wait 5`. An ambiguous prefix makes the
# launcher refuse to run, and it is counted as taking one when any candidate
# does (`nsenter --t 1` could mean --target), because the walk judges this
# reading IN ADDITION to the plain one that steps over the word alone, and
# blocks if either does, so resolving a prefix can only add refusals.
# An exact flag name never takes one.
# Each list is the launcher's operand-taking long names, then its flag names.
# The `ops` lists hold every operand-taking long name. The ones missing from a
# launcher's `optarg` (sudo's `chroot`, `auth-type` and `login-class`, env's
# `argv0`, `env0-from` and `quoting-style`) are stepped over by the plain walk
# and taken only here (see the sudo row of the launcher table). doas is
# absent: it has no long options.
# env's names, fetched 2026-09-29. GNU coreutils src/env.c (last change
# f799b2f) lists `argv0`, `env0-from` and `quoting-style` as options taking an
# argument, beside `unset` and `chdir`; its NEWS puts `--argv0` in 9.5,
# `--env0-from` in 9.12 and `--quoting-style` after 9.12; the env manual at
# gnu.org/software/coreutils/manual/html_node/env-invocation.html lists
# `--argv0`, `--unset`, `--env0-from` and `--chdir`. uutils/coreutils
# src/uu/env/src/env.rs (last change b2480b2) implements `argv0`, `unset`,
# `chdir` and `split-string`, not `env0-from` or `quoting-style`. uutils 0.10.0's
# own `env --help` lists those four and also `-f, --file <PATH>`, which neither
# table here carries (see the operand-taking-option gap in the header). So
# `env0-from` and `quoting-style` exist only in newer GNU env, and are kept: a
# name an env lacks only adds a refusal, and removing one would loosen the
# guard. The sudo names above carry no source here. Recheck when a GNU
# coreutils or uutils release adds an `env` option that takes an argument.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_long_takes_arg() {
  local name="$2" ops fls o nop=0
  [[ -n "$name" ]] || return 1
  case "$1" in
  sudo)
    ops="other-user auth-type close-from login-class chdir group host prompt chroot role command-timeout type user"
    fls="background preserve-env edit set-home login remove-timestamp list preserve-groups shell validate askpass bell help reset-timestamp no-update non-interactive stdin version"
    ;;
  env)
    ops="unset chdir argv0 env0-from quoting-style"
    fls="ignore-environment null block-signal default-signal ignore-signal list-signal-handling debug help version"
    ;;
  setpriv)
    ops="inh-caps ambient-caps ruid euid rgid egid reuid regid groups bounding-set securebits pdeathsig ptracer selinux-label apparmor-profile landlock-access landlock-rule list-landlock-rights seccomp-filter" # spellchecker:disable-line
    fls="dump nnp no-new-privs list-caps clear-groups keep-groups init-groups landlock-support list-landlock-access help reset-env version"
    ;;
  prlimit)
    ops="pid output"
    fls="as core cpu data fsize locks memlock msgqueue nice nofile nproc rss rtprio rttime sigpending stack version help noheadings raw verbose"
    ;;
  systemd-run)
    ops="host machine capsule unit property description slice expand-environment service-type uid gid nice working-directory root-directory setenv output json job-mode background path-property socket-property timer-property on-active on-boot on-startup on-unit-active on-unit-inactive on-calendar"
    fls="help version no-ask-password user system scope slice-inherit no-block remain-after-exit wait send-sighup same-dir same-root-dir tty pty pty-late pipe quiet verbose collect shell ignore-failure no-pager on-timezone-change on-clock-change"
    ;;
  timeout)
    ops="signal kill-after"
    fls="foreground preserve-status verbose help version"
    ;;
  nice)
    ops="adjustment"
    fls="help version"
    ;;
  ionice)
    ops="class classdata pid pgid uid"
    fls="ignore help version"
    ;;
  stdbuf)
    ops="input output error"
    fls="help version"
    ;;
  time)
    ops="format output"
    fls="append verbose portability quiet help version"
    ;;
  chrt)
    ops="sched-runtime sched-period sched-deadline clamp-min clamp-max"
    fls="all-tasks batch deadline deadline-overrun ext fifo idle pid help max other rr reset-on-fork reclaim-grub verbose version"
    ;;
  flock)
    ops="timeout wait conflict-exit-code start length fd"
    fls="shared exclusive unlock nonblocking nb close no-fork verbose fcntl help version"
    ;;
  unshare)
    ops="map-user map-users map-group map-groups owner propagation setgroups setuid setgid root wd monotonic boottime load-interp whitelist-env"
    fls="help version mount uts ipc net pid user cgroup time fork kill-child forward-signals mount-proc mount-binfmt map-root-user map-current-user map-auto map-subids keep-caps clear-env"
    ;;
  nsenter)
    ops="target net-socket setuid setgid"
    fls="all help version mount uts ipc net pid user cgroup time root wd wdns env no-fork join-cgroup preserve-credentials keep-caps user-parent follow-context"
    ;;
  numactl)
    ops="interleave weighted-interleave preferred preferred-many cpubind cpunodebind physcpubind membind shm file offset length shmmode shmid"
    fls="all show localalloc balancing hardware strict dump dump-nodes huge touch cpu-compress verify version"
    ;;
  chroot)
    ops="userspec groups"
    fls="skip-chdir help version"
    ;;
  *) return 1 ;;
  esac
  for o in $ops; do
    [[ "$o" == "$name" ]] && return 0
    [[ "$o" == "$name"* ]] && nop=$((nop + 1))
  done
  for o in $fls; do
    [[ "$o" == "$name" ]] && return 1
  done
  ((nop > 0))
}

# rdt_abbr is 1 inside a RESOLVED walk, where an abbreviated launcher long
# option takes its operand; see that arm in rdt_check_segment. rdt_resolved
# counts those walks for the whole command, and past the cap the guard
# REFUSES rather than judging one reading only.
rdt_abbr=0
rdt_resolved=0
MAX_RESOLVED_WALKS=256

# rdt_resolved_walk <argv word>...: judge one segment with every abbreviated
# launcher long option taking its operand. The provenance array is restored
# afterwards, because a nested parse inside the walk rebuilds it.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_resolved_walk() {
  rdt_resolved=$((rdt_resolved + 1))
  ((rdt_resolved > MAX_RESOLVED_WALKS)) && rdt_block "too-many-abbreviations"
  local rdt_abbr=1
  local -a saved_q=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  rdt_check_segment "$@"
  HOOK_SEG_WORD_QUOTED=(${saved_q[@]+"${saved_q[@]}"})
}

# --- Empty, bare-variable and outside-tree targets ---------------------------
#
# rdt_bare_var <normalized operand>: true when the operand is made of
# expansions and nothing else, matched on the NORMALIZED form (lower case,
# trailing nameless segments dropped, so `"$X/"`, `"$X/*"` and `"$X"/*` all
# reduce to `$x`). The units are `$NAME`, a positional or special parameter,
# and any `${...}`. Only `${NAME:?...}` aborts the command on an empty value as
# well as an unset one, so an operand whose every unit is that form passes;
# `${NAME?}`, `${NAME%/}`, `${!NAME}` and a substring do not, and neither does
# `$X$Y`. A `${...}` unit ends where bash ends it: only `${` nests and the first
# `}` closes the innermost one, so `${X:-${Y:-/}}` is one unit, judged by its
# outermost operator. A `${` that never closes is refused: bash rejects it, and
# nothing here can say what it would expand to.
# shellcheck disable=SC2016,SC2329  # literal `$` patterns; called from the operand loop
rdt_bare_var() {
  local s="$1" safe=1 unit inner i d n
  local re_plain='^\$([a-z_][a-z0-9_]*|[0-9]|[@*#?$!-])' re_safe='^[a-z_][a-z0-9_]*:\?'
  [[ "$s" == '$'* ]] || return 1
  while [[ -n "$s" ]]; do
    if [[ "$s" == '${'* ]]; then
      d=1
      n=${#s}
      for ((i = 2; i < n; i++)); do
        case "${s:i:1}" in
        '$')
          if [[ "${s:i+1:1}" == '{' ]]; then
            d=$((d + 1))
            i=$((i + 1))
          fi
          ;;
        '}')
          d=$((d - 1))
          ((d == 0)) && break
          ;;
        *) ;;
        esac
      done
      ((i < n)) || return 0
      unit="${s:0:i+1}"
      inner="${s:2:i-2}"
      [[ "$inner" =~ $re_safe ]] || safe=0
    elif [[ "$s" =~ $re_plain ]]; then
      unit="${BASH_REMATCH[0]}"
      safe=0
    else
      # What follows the expansions names nothing when it holds no letter,
      # digit or underscore outside a bracket expression: a glob (`*`, `?*`,
      # `[a-z]*`) or dots. `"${X:-/}"*` with X unset is `/*`, so such a
      # remainder leaves the operand bare. Anything that names something
      # (`$X-build`, `${X}_old`) is a path that goes on past the expansion.
      local rem="$s" re_br='\[[^]]*\]'
      while [[ "$rem" =~ $re_br ]]; do rem="${rem/"${BASH_REMATCH[0]}"/}"; done
      [[ "$rem" == *[[:alnum:]_]* ]] && return 1
      break
    fi
    s="${s:${#unit}}"
  done
  ((safe == 0))
}

# The outside-tree arm. RDT_ARM is 1 when the payload carries an absolute cwd;
# without one the arm is skipped. Operands are recorded while the command is
# parsed and judged once, after both passes, by rdt_judge_pending.
#   RDT_ORIGINS    every directory the command may run a delete from: the
#                  payload cwd, then each literal cd / pushd / env -C / sudo -D
#                  target, lexically collapsed. Global, never saved or restored
#                  by the recursion, because a later segment runs where an
#                  earlier one left the shell.
#   rdt_cd_unknown 1 once a directory change this guard cannot follow is seen;
#                  a relative operand recorded after it is left alone.
#   rdt_in_subst   1 while the substitution scan runs. That scan precedes the
#                  main parse, so an operand it records is judged against every
#                  origin the whole command visits.
#   rdt_cdpath     1 once CDPATH is set (inherited, assigned or exported).
#   rdt_cd_refuse  1 once a cd is seen that the guard can read but not follow
#                  to one directory: a relative cd while CDPATH is set, which
#                  may land in any CDPATH entry the command itself chose, or a
#                  glob target with no match or several. A relative operand
#                  recorded after it is REFUSED rather than left alone.
# MAX_ORIGINS counts the starting directory among its 32. MAX_TARGETS bounds
# directory-and-target pairs, MAX_GLOB the entries one glob reads across all
# its levels. RDT_DEADLINE bounds the wall time (bash's SECONDS) of this arm's
# own work, from the moment it first has work to do (an operand to record, a
# brace or glob to expand) through the parse that follows and the judgment,
# and RDT_DEADLINE_ABS bounds the hook's whole run once that work has begun:
# the harness cancels a hook past its timeout WITHOUT a block, so running long
# would fail open, and the dispatcher shares one 60 s timeout across every
# guard it runs. A command this arm has nothing to do for is never timed, so a
# slow but harmless parse behaves as it did before the arm existed. Past any
# of them the guard refuses. 25 s and 50 s are sized for a busy host: under
# heavy load an everyday `rm -rf ./build` took 4 to 8 s end to end on Windows
# Git Bash, and a 12 s bound refused ordinary deletes; 50 s leaves 10 s of the
# shared 60 s timeout, with this guard last in the dispatcher chain.
# MAX_WORKTREES bounds the registered worktrees read for the protected trees;
# one past it is protected only by the .git file in its own root.
MAX_ORIGINS=32
MAX_TARGETS=512
MAX_GLOB=256
MAX_WORKTREES=256
RDT_DEADLINE=25
RDT_DEADLINE_ABS=50
RDT_T0=-1
rdt_cdpath=0
[[ -n "${CDPATH:-}" ]] && rdt_cdpath=1
rdt_cd_refuse=0
RDT_ARM=0
RDT_ORIGINS=()
RDT_ORIGIN_OVERFLOW=0
rdt_cd_unknown=0
rdt_in_subst=0
RDT_P_TEXT=()
RDT_P_Q=()
RDT_P_NORIG=()
RDT_P_UNK=()
RDT_P_REF=()
RDT_P_SUB=()
RDT_P_WT=()
RDT_WTRM=0
RDT_WIN=0
case "${OSTYPE:-}" in
msys* | cygwin* | win32) RDT_WIN=1 ;;
*) ;;
esac
RDT_DOTS=0
RDT_HOME="${HOME:-}"
RDT_HOME="${RDT_HOME//\\//}"

# rdt_deadline: start this arm's clock on the first call, and refuse once its
# work has run past RDT_DEADLINE seconds, or the hook past RDT_DEADLINE_ABS.
rdt_deadline() {
  ((RDT_T0 >= 0)) || RDT_T0=$SECONDS
  ((SECONDS - RDT_T0 < RDT_DEADLINE && SECONDS < RDT_DEADLINE_ABS)) || rdt_block "too-slow"
}

# rdt_remaining_to <var>: whole seconds left before rdt_deadline would refuse,
# at least 1. A batch process (realpath, cygpath) runs under `timeout` with
# this bound, because the deadline is otherwise checked only between steps and
# one slow process could carry the hook past the harness timeout.
rdt_remaining_to() {
  rdt_deadline
  local __rr_a=$((RDT_DEADLINE - (SECONDS - RDT_T0))) __rr_b=$((RDT_DEADLINE_ABS - SECONDS))
  ((__rr_b < __rr_a)) && __rr_a=$__rr_b
  ((__rr_a < 1)) && __rr_a=1
  printf -v "$1" '%s' "$__rr_a"
}

# rdt_is_unc <path>: a `//host/...` path, which is never touched on disk, so
# no lookup can wait on the network.
rdt_is_unc() {
  [[ "$1" == //* && "$1" != ///* ]]
}

# rdt_parent_to <var> <path>: <path> without its last component, kept a root:
# `/` rather than empty, `C:/` rather than `C:`.
rdt_parent_to() {
  local __rpt_p="${2%/*}"
  [[ -z "$__rpt_p" ]] && __rpt_p=/
  [[ "$__rpt_p" =~ ^[A-Za-z]:$ ]] && __rpt_p="$__rpt_p/"
  printf -v "$1" '%s' "$__rpt_p"
}

# rdt_nearest_to <var> <test> <path>: the nearest ancestor of <path> (itself
# included) for which `[[ <test> ]]` holds, `-e` or `-d`; empty when none. The
# walk stops at a root, because an unmapped drive (`Q:/`) never exists and
# stripping it again would give `Q:` back forever.
rdt_nearest_to() {
  local __rn_a="$3"
  while [[ -n "$__rn_a" && "$__rn_a" == */* && "$__rn_a" != / && ! "$__rn_a" =~ ^[A-Za-z]:/$ ]]; do
    rdt_deadline
    if [[ "$2" == -d ]]; then [[ -d "$__rn_a" ]] && break; else [[ -e "$__rn_a" ]] && break; fi
    rdt_parent_to __rn_a "$__rn_a"
  done
  if [[ "$2" == -d ]]; then [[ -d "$__rn_a" ]] || __rn_a=""; fi
  printf -v "$1" '%s' "$__rn_a"
}

# rdt_lines_to <array var> <want count> <command...>: run a batch command,
# strip CRs, and split its output into lines. Returns 1 when it fails or the
# line count differs from <want count>, so the caller keeps its own answer.
# Where `timeout` exists the command is bounded by the time left, and running
# out refuses: realpath took 90 s over one path of 2,000 missing components.
rdt_lines_to() {
  local __rb_dest="$1" __rb_want="$2" __rb_out __rb_left __rb_rc=0
  shift 2
  if command -v timeout >/dev/null 2>&1; then
    rdt_remaining_to __rb_left
    __rb_out=$(timeout "$__rb_left" "$@" 2>/dev/null) || __rb_rc=$?
    ((__rb_rc == 124)) && rdt_block "too-slow"
    ((__rb_rc == 0)) || return 1
  else
    # No `timeout` (stock macOS): the call cannot be cut short, so the clock
    # is checked on both sides of it and a slow call refuses once it returns.
    # The operand length and depth caps are what keep one call short here.
    rdt_deadline
    __rb_out=$("$@" 2>/dev/null) || __rb_rc=$?
    rdt_deadline
    ((__rb_rc == 0)) || return 1
  fi
  __rb_out="${__rb_out//$'\r'/}"
  mapfile -t "$__rb_dest" <<<"$__rb_out"
  local -n __rb_ref="$__rb_dest"
  ((${#__rb_ref[@]} == __rb_want))
}

# rdt_glob_on / rdt_glob_off: nullglob on for a glob read, and the caller's
# setting restored after it.
rdt_glob_on() {
  RDT_NG_WAS=0
  shopt -q nullglob && RDT_NG_WAS=1
  shopt -s nullglob
}
rdt_glob_off() {
  ((RDT_NG_WAS)) || shopt -u nullglob
}

# rdt_note_cdpath <word>: a `CDPATH=` assignment, as a prefix, a segment of
# its own or an argument of export and its kin, sets rdt_cdpath.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_cdpath() {
  [[ "$1" == CDPATH=* ]] && rdt_cdpath=1
  return 0
}

# rdt_is_abs <path>: absolute after backslashes became slashes: `/…`, `//…`,
# or a drive followed by a slash. A drive-relative `C:foo` is not.
rdt_is_abs() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:/ ]]
}

# rdt_lex_to <var> <absolute path>: `.` and `..` collapsed, slashes squeezed.
# A drive prefix and a UNC `//` lead are kept, and `..` stops at the top.
rdt_lex_to() {
  local __rl_p="$2" __rl_pre="" __rl_c __rl_out=""
  local -a __rl_st=()
  if [[ "$__rl_p" =~ ^([A-Za-z]:)(.*)$ ]]; then
    __rl_pre="${BASH_REMATCH[1]}"
    __rl_p="${BASH_REMATCH[2]}"
  elif rdt_is_unc "$__rl_p"; then
    __rl_pre="/"
  fi
  while :; do
    __rl_c="${__rl_p%%/*}"
    case "$__rl_c" in
    '' | .) ;;
    ..) ((${#__rl_st[@]})) && __rl_st=("${__rl_st[@]:0:${#__rl_st[@]}-1}") ;;
    *) __rl_st+=("$__rl_c") ;;
    esac
    [[ "$__rl_p" == */* ]] || break
    __rl_p="${__rl_p#*/}"
  done
  for __rl_c in ${__rl_st[@]+"${__rl_st[@]}"}; do __rl_out+="/$__rl_c"; done
  printf -v "$1" '%s' "$__rl_pre${__rl_out:-/}"
}

# rdt_join_to <var> <dir> <rest>: one slash between them, whatever <dir> ends
# with.
rdt_join_to() {
  if [[ -z "$3" ]]; then
    printf -v "$1" '%s' "$2"
  elif [[ "$2" == */ ]]; then
    printf -v "$1" '%s' "$2${3#/}"
  else
    printf -v "$1" '%s' "$2/${3#/}"
  fi
}

# rdt_canon_to <var> <path>: the spelling two paths are COMPARED in. Slashes
# squeezed, no trailing slash, a drive folded by hook::normalize_path_to, and
# on Windows the whole path lower-cased, since that filesystem folds case.
rdt_canon_to() {
  local __rc_p="${2//\\//}" __rc_lead=""
  if rdt_is_unc "$__rc_p"; then
    __rc_lead=/
    __rc_p="${__rc_p#/}"
  fi
  while [[ "$__rc_p" == *//* ]]; do __rc_p="${__rc_p//\/\//\/}"; done
  __rc_p="$__rc_lead$__rc_p"
  [[ "$__rc_p" == ?*/ && ! "$__rc_p" =~ ^[A-Za-z]:/$ ]] && __rc_p="${__rc_p%/}"
  hook::normalize_path_to __rc_p "$__rc_p"
  ((RDT_WIN)) && __rc_p="${__rc_p,,}"
  printf -v "$1" '%s' "$__rc_p"
}

# rdt_root_like <canonical>: a filesystem root, which is never accepted as an
# allowed root: a tree, temp root or scratchpad there would allow everything.
rdt_root_like() {
  [[ "$1" == / || "$1" =~ ^[A-Za-z]:/?$ || "$1" =~ ^/[A-Za-z]$ ]]
}

# rdt_place_to <var> <operand> <provenance>: the operand as a path this arm
# can judge. Returns 0 when placed, 1 to leave it alone (an expansion other
# than a leading HOME, a drive-relative path), and 2 when it must be refused
# because it cannot be judged faithfully (`~name`, a newline). A leading `~`,
# `$HOME` or `${HOME}` expands from the hook's HOME and `~+` is the working
# directory; a fully quoted `~` is a literal name. A `\\?\` or `\\.\` device
# prefix on a drive path is read as the drive path. Sets:
#   RDT_PL_ABS   1 for an absolute path
#   RDT_PL_MODE  leaf: the parent is resolved and the name is appended as is,
#                because rm removes a symlink named last rather than following
#                it. whole: the path is resolved entirely, for a trailing slash
#                (rm then follows a symlink), a trailing `.` or `..`, and the
#                directory in front of a glob in the last component.
#                deep: a glob sits before the last component; the judgment
#                expands its directory part with real globbing and judges each
#                match, or, with no match, the literal directory in front of
#                the glob, below which the targets lie at least two levels.
#   RDT_PL_GLOB  1 when a glob was present
#   RDT_PL_FULL  the whole path text, after HOME expansion, with no trailing
#                slash; RDT_PL_SLASH 1 when one was stripped
#   RDT_PL_ENUM  the last-component glob of an operand ending in `/`, whose
#                matches are read so that a symlink among them is judged by
#                where it points
# Braces are expanded before this (rdt_brace_expand), so a `{` here is a
# literal character. A `..` after the first glob component returns 2.
# Provenance 3 is LITERAL mode, for a path the filesystem produced (a glob
# match) or one bash passes through unchanged (an unmatched glob): no `~`,
# HOME, `$` or glob is read in it. Provenance 4 is a PowerShell operand whose
# every `$` and backtick is literal (single-quoted or backtick-escaped): read
# as provenance 0, except that no `$`, HOME or backtick is read in it.
# shellcheck disable=SC2016  # `$HOME` here is the literal text of the operand
rdt_place_to() {
  local __rp_t="${2//\\//}" __rp_q="$3" __rp_dir="" __rp_last __rp_pre __rp_rest __rp_slash=0
  RDT_PL_ABS=0
  RDT_PL_GLOB=0
  RDT_PL_MODE=leaf
  RDT_PL_ENUM=""
  RDT_PL_FULL=""
  RDT_PL_SLASH=0
  [[ -n "$__rp_t" ]] || return 1
  [[ "$__rp_t" == *$'\n'* ]] && return 2
  [[ "$__rp_t" =~ ^//[?.]/([A-Za-z]:/.*)$ ]] && __rp_t="${BASH_REMATCH[1]}"
  if ((__rp_q < 2 || __rp_q == 4)); then
    # shellcheck disable=SC2088  # matching the literal text, expanded by hand below
    case "$__rp_t" in
    '~' | '~/'*)
      [[ -n "$RDT_HOME" ]] || return 1
      __rp_t="$RDT_HOME${__rp_t#\~}"
      ;;
    '~+' | '~+/'*) __rp_t=".${__rp_t#\~+}" ;;
    '~'*) return 2 ;;
    *) ;;
    esac
  fi
  if ((__rp_q < 3)); then
    case "$__rp_t" in
    '$HOME' | '$HOME/'*)
      [[ -n "$RDT_HOME" ]] || return 1
      __rp_t="$RDT_HOME${__rp_t#\$HOME}"
      ;;
    '${HOME}' | '${HOME}/'*)
      [[ -n "$RDT_HOME" ]] || return 1
      __rp_t="$RDT_HOME${__rp_t#\$\{HOME\}}"
      ;;
    *) ;;
    esac
    case "$__rp_t" in
    *'$'* | *'`'*) return 1 ;;
    *) ;;
    esac
  fi
  if rdt_is_abs "$__rp_t"; then
    RDT_PL_ABS=1
  elif [[ "$__rp_t" =~ ^[A-Za-z]: ]]; then
    return 1
  fi
  while [[ "$__rp_t" == ?*/ ]]; do
    __rp_t="${__rp_t%/}"
    __rp_slash=1
  done
  RDT_PL_FULL="$__rp_t"
  RDT_PL_SLASH=$__rp_slash
  if ((__rp_q != 3)) && [[ "$__rp_t" == *[*?[]* ]]; then
    # A `..` after the first glob component climbs out of whatever the glob
    # matched, so the directory in front of the glob says nothing about it.
    local __rp_c __rp_seen=0 __rp_ifs="$IFS"
    local -a __rp_cs=()
    IFS=/ read -r -a __rp_cs <<<"$__rp_t"
    IFS="$__rp_ifs"
    for __rp_c in ${__rp_cs[@]+"${__rp_cs[@]}"}; do
      [[ "$__rp_c" == *[*?[]* ]] && __rp_seen=1
      ((__rp_seen)) && [[ "$__rp_c" == .. ]] && return 2
    done
    # Judged by the literal directory in front of the first glob.
    RDT_PL_GLOB=1
    __rp_pre="${__rp_t%%[*?[]*}"
    [[ "$__rp_pre" == */* ]] && __rp_dir="${__rp_pre%/*}"
    __rp_rest="${__rp_t:${#__rp_dir}}"
    __rp_rest="${__rp_rest#/}"
    if [[ -z "$__rp_dir" ]]; then
      if ((RDT_PL_ABS)); then __rp_dir=/; else __rp_dir=.; fi
    fi
    [[ "$__rp_dir" =~ ^[A-Za-z]:$ ]] && __rp_dir="$__rp_dir/"
    if [[ "$__rp_rest" == */* ]]; then
      RDT_PL_MODE=deep
    else
      RDT_PL_MODE=whole
      ((__rp_slash)) && RDT_PL_ENUM="$__rp_rest"
    fi
    __rp_t="$__rp_dir"
  else
    __rp_last="${__rp_t##*/}"
    if ((__rp_slash)) || [[ "$__rp_last" == . || "$__rp_last" == .. ]]; then
      RDT_PL_MODE=whole
    fi
  fi
  printf -v "$1" '%s' "$__rp_t"
}

# rdt_add_origin <directory operand> <provenance>: a directory a later delete
# may run from. A relative one is joined to every origin known so far. A
# fully quoted target is literal. An unquoted glob target is expanded with the
# bounded per-component glob from each origin, and followed when it matches
# exactly one directory there; with no match or several, and for a target the
# guard must refuse (`~name`, a `..` after a glob), a relative operand after
# it is refused. An expansion is not followed and leaves it alone.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_add_origin() {
  local t o c k have rc=0 q="$2"
  local -a add=() bases=()
  if [[ "$1" == *'{'* ]] && ((q != 2)); then
    rdt_cd_unknown=1
    return 0
  fi
  # A quoted target is literal, unless it carries a `$` or a backtick: the
  # tokenizer's provenance cannot tell "$d" from '$d', so that one is still
  # read as an expansion and left alone.
  if ((q == 2)) && [[ "$1" != *'$'* && "$1" != *'`'* ]]; then q=3; fi
  rdt_place_to t "$1" "$q" || rc=$?
  if ((rc == 2)); then
    rdt_cd_refuse=1
    return 0
  fi
  if ((rc != 0)); then
    rdt_cd_unknown=1
    return 0
  fi
  if ((RDT_PL_GLOB)); then
    local full="$RDT_PL_FULL"
    if ((RDT_PL_ABS)); then bases=(""); else bases=(${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"}); fi
    for o in ${bases[@]+"${bases[@]}"}; do
      rdt_glob_dirs "$o" "$full"
      if ((${#RDT_GLOB[@]} != 1)); then
        rdt_cd_refuse=1
        return 0
      fi
      rdt_lex_to c "${RDT_GLOB[0]}"
      add+=("$c")
    done
  elif ((RDT_PL_ABS)); then
    rdt_lex_to c "$t"
    add=("$c")
  else
    for o in ${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"}; do
      rdt_lex_to c "$o/$t"
      add+=("$c")
    done
  fi
  for c in ${add[@]+"${add[@]}"}; do
    have=0
    for k in ${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"}; do
      [[ "$k" == "$c" ]] && have=1 && break
    done
    ((have)) && continue
    if ((${#RDT_ORIGINS[@]} >= MAX_ORIGINS)); then
      RDT_ORIGIN_OVERFLOW=1
      return 0
    fi
    RDT_ORIGINS+=("$c")
  done
}

# rdt_note_cd <cd|pushd|popd> <offset> <words after it>: follow a directory
# change. Its options (`-L`, `-P`, `-e`, `-@`, pushd's `-n`) are stepped over;
# a bare `cd` goes home; `cd -`, `popd`, `pushd` alone and `pushd +N` are
# not followed.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_cd() {
  local verb="$1" off="$2"
  shift 2
  local -a a=("$@")
  local n=$# k=0 w
  if [[ "$verb" == popd ]]; then
    rdt_cd_unknown=1
    return 0
  fi
  while ((k < n)); do
    w="${a[k]}"
    if [[ "$w" == -- ]]; then
      k=$((k + 1))
      break
    fi
    [[ "$w" == -?* && ! "$w" =~ ^-[0-9]+$ ]] || break
    k=$((k + 1))
  done
  if ((k >= n)); then
    if [[ "$verb" == cd ]]; then
      rdt_add_origin '~' 0
    else
      rdt_cd_unknown=1
    fi
    return 0
  fi
  w="${a[k]}"
  case "$w" in
  - | [+-][0-9]*)
    rdt_cd_unknown=1
    return 0
    ;;
  *) ;;
  esac
  # With CDPATH set, a relative target that does not start with `.` or `..`
  # may land in any CDPATH entry, so it is not followed, and a relative
  # operand after it is refused.
  if ((rdt_cdpath)); then
    # shellcheck disable=SC2088  # matching the literal text of the operand
    case "${w//\\//}" in
    / | /* | [A-Za-z]:/* | . | .. | ./* | ../* | '~' | '~/'*) ;;
    *)
      rdt_cd_refuse=1
      return 0
      ;;
    esac
  fi
  rdt_add_origin "$w" "${HOOK_SEG_WORD_QUOTED[off + k]:-0}"
}

# rdt_note_login <words after su or runuser>: a login shell starts in the
# target user's home, so a relative operand inside it is not followed.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_login() {
  local w
  for w in "$@"; do
    [[ "$w" == -- ]] && break
    if [[ "$w" == - || ("$w" == --l* && "login" == "${w#--}"*) ]] ||
      [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *l* ]]; then
      rdt_cd_unknown=1
      return 0
    fi
  done
}

# rdt_note_launcher_dir <launcher> <word> <has next> <next> <q word> <q next>:
# env -C / --chdir and sudo -D / --chdir run the command from a directory; an
# abbreviated env --ch is read the same way. sudo -i / --login runs it from the
# target user's home.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_launcher_dir() {
  case "$1" in
  env)
    case "$2" in
    -C | --c | --ch | --chd | --chdi | --chdir) (($3)) && rdt_add_origin "$4" "$6" ;;
    --c=* | --ch=* | --chd=* | --chdi=* | --chdir=*) rdt_add_origin "${2#*=}" "$5" ;;
    -C?*) rdt_add_origin "${2#-C}" "$5" ;;
    *) ;;
    esac
    ;;
  sudo)
    case "$2" in
    -D | --chdir) (($3)) && rdt_add_origin "$4" "$6" ;;
    --chdir=*) rdt_add_origin "${2#*=}" "$5" ;;
    -D?*) rdt_add_origin "${2#-D}" "$5" ;;
    --login) rdt_cd_unknown=1 ;;
    *) [[ "$2" =~ ^-[A-Za-z]+$ && "$2" == *i* ]] && rdt_cd_unknown=1 ;;
    esac
    ;;
  *) ;;
  esac
  return 0
}

# RDT_RES maps a path to its resolved spelling for the whole judgment.
declare -A RDT_RES=()

# rdt_resolve_all <path>...: resolve every path physically in one process
# where the host allows, into RDT_RES. One `realpath -m` for all of them,
# which follows a symlink or `..` whether or not the tail exists. Without it
# (BSD, macOS), each is collapsed lexically and its nearest existing ancestor
# resolved through hook::physical_path_to. A UNC path, and a drive path on a
# host with no drives, is never touched on disk: it is collapsed lexically, so
# no lookup can wait on the network.
rdt_resolve_all() {
  local p i a rem r
  local -a todo=() res=() lines=()
  local -A seen=()
  for p in "$@"; do
    [[ -n "$p" && -z "${RDT_RES[$p]+x}" && -z "${seen[$p]+x}" ]] || continue
    seen[$p]=1
    if rdt_is_unc "$p" || { ((!RDT_WIN)) && [[ "$p" =~ ^[A-Za-z]: ]]; }; then
      rdt_lex_to r "$p"
      RDT_RES[$p]="$r"
      continue
    fi
    todo+=("$p")
  done
  ((${#todo[@]})) || return 0
  local ok=0
  if [[ "${todo[*]}" != *$'\n'* ]] && rdt_lines_to lines "${#todo[@]}" realpath -m -- "${todo[@]}"; then
    ok=1
  fi
  for ((i = 0; i < ${#todo[@]}; i++)); do
    if ((ok)) && [[ -n "${lines[i]}" ]]; then
      res[i]="${lines[i]}"
      continue
    fi
    rdt_deadline
    rdt_lex_to a "${todo[i]}"
    rem=""
    rdt_split_existing a rem "$a"
    if hook::_physical_cached_to r "$a"; then
      rdt_join_to r "$r" "$rem"
    else
      rdt_join_to r "$a" "$rem"
    fi
    res[i]="$r"
  done
  for ((i = 0; i < ${#todo[@]}; i++)); do RDT_RES[${todo[i]}]="${res[i]}"; done
}

# RDT_WMAP maps a resolved path to its one Windows long form.
declare -A RDT_WMAP=()

# rdt_winmap_all <path>...: on Windows, one `cygpath -l -m` over each path's
# nearest existing ancestor maps the /tmp mount, the /c/... and C:/...
# spellings and 8.3 short names onto one long form, into RDT_WMAP. The
# nearest EXISTING ancestor, because cygpath leaves a path whose tail is
# missing unexpanded. A path it cannot map keeps its own spelling. Elsewhere
# every path maps to itself.
rdt_winmap_all() {
  local p i a rem r
  local -a todo=() ancestors=() rems=() uniq=() lines=()
  local -A seen=() amap=()
  for p in "$@"; do
    [[ -n "$p" && -z "${RDT_WMAP[$p]+x}" && -z "${seen[$p]+x}" ]] || continue
    seen[$p]=1
    RDT_WMAP[$p]="$p"
    ((RDT_WIN)) || continue
    rdt_is_unc "$p" && continue
    todo+=("$p")
  done
  ((${#todo[@]})) || return 0
  # silent-skip-ok: cygpath is part of the Git Bash, MSYS2 and Cygwin runtime
  # this branch runs under, so its absence is not a real install. Without it
  # every path keeps the spelling realpath gave it, which refuses more (a short
  # or drive spelling no longer matches the tree); the one allow it can add is
  # the scratchpad itself named through the /tmp mount, which then reads as a
  # path strictly under /tmp.
  command -v cygpath >/dev/null 2>&1 || return 0
  for ((i = 0; i < ${#todo[@]}; i++)); do
    rdt_deadline
    rdt_split_existing a rem "${todo[i]}"
    # A leaf target that is itself a symlink is mapped by its parent, because
    # cygpath follows the link and rm removes the link, not what it points
    # at. Every other link on the path was already resolved by realpath.
    if [[ -z "$rem" && -L "$a" && "$a" == */?* ]]; then
      rem="/${a##*/}"
      rdt_parent_to a "$a"
    fi
    ancestors[i]="$a"
    rems[i]="$rem"
    if [[ -z "${amap[$a]+x}" ]]; then
      amap[$a]=""
      uniq+=("$a")
    fi
  done
  [[ "${uniq[*]}" != *$'\n'* ]] || return 0
  rdt_lines_to lines "${#uniq[@]}" cygpath -l -m -- "${uniq[@]}" || return 0
  for ((i = 0; i < ${#uniq[@]}; i++)); do amap[${uniq[i]}]="${lines[i]}"; done
  for ((i = 0; i < ${#todo[@]}; i++)); do
    a="${amap[${ancestors[i]}]}"
    [[ -n "$a" ]] || continue
    rdt_join_to r "$a" "${rems[i]}"
    RDT_WMAP[${todo[i]}]="$r"
  done
}

# rdt_split_existing <ancestor var> <rest var> <path>: the nearest existing
# ancestor of <path>, and the tail below it.
rdt_split_existing() {
  local __rs_a __rs_r
  rdt_nearest_to __rs_a -e "$3"
  __rs_r="${3:${#__rs_a}}"
  [[ -n "$__rs_r" && "$__rs_r" != /* ]] && __rs_r="/$__rs_r"
  printf -v "$1" '%s' "$__rs_a"
  printf -v "$2" '%s' "$__rs_r"
}

# rdt_tree_to <var> <directory>: the git toplevel of a directory, or empty.
# Asked once, for the payload cwd, from its nearest existing directory, with
# the variables that redirect discovery unset. A git that fails, or is absent,
# gives no tree, so the failure lands on the refusal side.
declare -A RDT_TREE=()
rdt_tree_to() {
  local o="$2" d out rc=0
  if [[ -n "${RDT_TREE[$o]+x}" ]]; then
    printf -v "$1" '%s' "${RDT_TREE[$o]}"
    return 0
  fi
  d=""
  rdt_is_unc "$o" || rdt_nearest_to d -d "$o"
  out=""
  if [[ -n "$d" ]]; then
    # Bounded like the batch resolvers: a git that stalls (a slow network
    # mount, a locked repository) would otherwise carry the hook past the
    # harness timeout, which fails open. Running out of time refuses.
    local left="" tcmd=()
    if command -v timeout >/dev/null 2>&1; then
      rdt_remaining_to left
      tcmd=(timeout "$left")
    else
      rdt_deadline
    fi
    out=$(
      unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM
      ${tcmd[@]+"${tcmd[@]}"} git -C "$d" rev-parse --show-toplevel 2>/dev/null
    ) || rc=$?
    ((rc == 124 && ${#tcmd[@]} > 0)) && rdt_block "too-slow"
    ((${#tcmd[@]} > 0)) || rdt_deadline
    out="${out//$'\r'/}"
    ((rc == 0)) || out=""
  fi
  RDT_TREE[$o]="$out"
  printf -v "$1" '%s' "$out"
}

# rdt_allowed <canonical target> <deep> <link>: the order the destructive-removal
# engine uses. The scratchpad itself, then a temp root itself, are refused
# first; then strictly under the scratchpad or a temp root, or under (or equal
# to) the payload cwd's tree, is allowed. With <deep> 1 the target is the
# literal directory in front of a glob before the last component, so what is
# deleted lies at least two levels below it, and equal to the scratchpad or a
# temp root is enough. Last, strictly under a user-listed allowed root (the
# same rule as a temp root), or a direct child of a name-prefix entry's
# directory whose name extends the prefix by at least one character and that
# is not itself a symlink (<link> 1), or strictly under <dir>/<one name>/<name>
# for a segment entry when the target is not a symlink, but never a root,
# HOME, or a directory holding HOME, whatever is listed.
rdt_allowed() {
  local t="$1" deep="$2" link="${3:-0}" c i rest seg
  if ((deep == 0)); then
    [[ -n "$RDT_SPC" && "$t" == "$RDT_SPC" ]] && return 1
    for c in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      [[ "$t" == "$c" ]] && return 1
    done
  fi
  [[ -n "$RDT_SPC" && ("$t" == "$RDT_SPC"/* || (deep -eq 1 && "$t" == "$RDT_SPC")) ]] && return 0
  for c in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
    [[ "$t" == "$c"/* || (deep -eq 1 && "$t" == "$c") ]] && return 0
  done
  [[ -n "$RDT_TREEC" && ("$t" == "$RDT_TREEC" || "$t" == "$RDT_TREEC"/*) ]] && return 0
  ((${#RDT_ALLOWC[@]} + ${#RDT_PDIRC[@]} + ${#RDT_SDIRC[@]})) || return 1
  { rdt_root_like "$t" || rdt_is_root "${t,,}"; } && return 1
  [[ "$t" == "$RDT_HOMEC" || "$RDT_HOMEC" == "$t"/* ]] && return 1
  for c in ${RDT_ALLOWC[@]+"${RDT_ALLOWC[@]}"}; do
    [[ "$t" == "$c"/* || (deep -eq 1 && "$t" == "$c") ]] && return 0
  done
  ((link)) && return 1
  for ((i = 0; i < ${#RDT_PDIRC[@]}; i++)); do
    c="${RDT_PDIRC[i]}"
    [[ "$t" == "$c"/* ]] || continue
    rest="${t#"$c"/}"
    # Win32 trims a trailing dot or space, so `.tmp-.` names `.tmp-` and
    # `.tmp-n.` names `.tmp-n` past the symlink test: such a name is refused.
    [[ "$rest" != */* && "$rest" != *[.\ ] && "$rest" == "${RDT_PNAME[i]}"?* ]] && return 0
  done
  for ((i = 0; i < ${#RDT_SDIRC[@]}; i++)); do
    c="${RDT_SDIRC[i]}"
    [[ "$t" == "$c"/?*/* ]] || continue
    rest="${t#"$c"/}"
    seg="${rest%%/*}"
    rest="${rest#*/}"
    # The one-level segment may not end in a dot or a space, which Win32
    # trims (`...` would name the directory before the `*`).
    [[ "$seg" != *[.\ ] ]] || continue
    # So may the leaf, or `.work/...` would name `.work` itself.
    [[ "$rest" == "${RDT_SNAME[i]}"/* && "${rest##*/}" != *[.\ ] ]] && return 0
    [[ deep -eq 1 && "$rest" == "${RDT_SNAME[i]}" ]] && return 0
  done
  return 1
}

# rdt_allowed_beside_tree <canonical target> <link>: rdt_allowed with the
# payload cwd's tree granting nothing, so only a temp root, the scratchpad or
# a listed root can allow the target.
rdt_allowed_beside_tree() {
  local RDT_TREEC=""
  rdt_allowed "$1" 0 "$2"
}

# rdt_within <path> <directory>: true when <path> is <directory> or lies under
# it. Both canonical; a root keeps its trailing slash.
rdt_within() {
  [[ "$1" == "$2" ]] && return 0
  if [[ "$2" == */ ]]; then [[ "$1" == "$2"?* ]]; else [[ "$1" == "$2"/* ]]; fi
}

# rdt_pat_hits <name> <pattern>: true when globbing <pattern> in a directory
# would match the entry <name>. A leading `.` is matched only by a pattern that
# starts with one, as bash and zsh glob by default, unless RDT_DOTS is 1 (the
# PowerShell tool, whose `*` matches dot names, or a command that names
# dotglob, GLOBIGNORE or zsh's globdots). On Windows both are folded to lower
# case, so a pattern bash would match case-sensitively can match more here,
# never less.
rdt_pat_hits() {
  local n="$1" p="$2"
  if ((RDT_WIN)); then
    n="${n,,}"
    p="${p,,}"
  fi
  ((RDT_DOTS == 0)) && [[ "$n" == .* && "$p" != .* ]] && return 1
  # shellcheck disable=SC2053  # the pattern is meant to glob
  [[ "$n" == $p ]]
}

# rdt_reaches <target> <path> <deep> <glob>: true when <path> lies strictly
# under the canonical target and the delete removes it. A target with a <glob>
# removes the children the glob matches, so <path> is reached when its first
# component below the target matches. A <deep> target is the directory in front
# of a glob that matched nothing, so it reaches nothing that exists.
rdt_reaches() {
  local c="$1" p="$2" first
  ((${3:-0})) && return 1
  [[ "$p" != "$c" ]] || return 1
  rdt_within "$p" "$c" || return 1
  [[ -n "$4" ]] || return 0
  first="${p:${#c}}"
  first="${first#/}"
  rdt_pat_hits "${first%%/*}" "$4"
}

# rdt_read_line_to <var> <file>: the first line of a small file, read with a
# builtin, at most 4096 bytes, its CR dropped and backslashes read as slashes.
# Returns 1 when the file is missing, unreadable or empty.
rdt_read_line_to() {
  local __rd_l=""
  [[ -f "$2" && -r "$2" ]] || return 1
  IFS= read -r -n 4096 __rd_l 2>/dev/null <"$2" || [[ -n "$__rd_l" ]] || return 1
  __rd_l="${__rd_l%$'\r'}"
  __rd_l="${__rd_l//\\//}"
  [[ -n "$__rd_l" ]] || return 1
  printf -v "$1" '%s' "$__rd_l"
}

# rdt_worktrees <toplevel>: the worktree roots git keeps for the repository of
# <toplevel>, unresolved, into RDT_WT. The main worktree root, when the common
# git directory is named .git, and each linked worktree's root, read from
# <common>/worktrees/<name>/gitdir, which names that worktree's .git file. A
# path such a file holds relative to itself (git's worktree.useRelativePaths)
# is joined to it. Read from the files git writes, with builtins, so no process
# starts; at most MAX_WORKTREES linked worktrees are read.
rdt_worktrees() {
  local top="$1" line gd com f
  local -a regs=()
  RDT_WT=()
  [[ -n "$top" ]] || return 0
  if [[ -d "$top/.git" ]]; then
    com="$top/.git"
  elif rdt_read_line_to line "$top/.git" && [[ "$line" == "gitdir: "?* ]]; then
    gd="${line#gitdir: }"
    rdt_is_abs "$gd" || gd="$top/$gd"
    com="$gd"
    if rdt_read_line_to line "$gd/commondir"; then
      if rdt_is_abs "$line"; then com="$line"; else com="$gd/$line"; fi
    fi
  else
    return 0
  fi
  rdt_lex_to com "$com"
  [[ "$com" == ?*/.git ]] && RDT_WT+=("${com%/*}")
  # Names first, dot names too: a worktree's name is its directory's.
  rdt_glob_on
  regs=("$com"/worktrees/* "$com"/worktrees/.[!.]* "$com"/worktrees/..?*)
  rdt_glob_off
  for f in ${regs[@]+"${regs[@]:0:MAX_WORKTREES}"}; do
    rdt_deadline
    rdt_read_line_to line "$f/gitdir" || continue
    rdt_is_abs "$line" || line="$f/$line"
    rdt_lex_to line "$line"
    [[ "$line" == ?*/.git ]] && RDT_WT+=("${line%/*}")
  done
  return 0
}

# rdt_protected <target> <real target> <deep> <glob> <link> [wt]: true when the
# delete removes a protected tree, with what it is in RDT_PROT. Judged ahead of
# every allowed root, the working tree included. <target> is canonical, <real
# target> the resolved path tested on disk, and <deep> and <glob> say what the
# delete reaches (rdt_reaches); any other target goes whole. Protected:
#   * a `.git`, named last or globbed straight inside, and a directory holding
#     a `.git`, unless the target is a symlink (<link> 1) that rm unlinks;
#   * the payload cwd's git toplevel and every registered worktree root
#     (RDT_PROT_B), and a directory holding one;
#   * ~/.claude and each block_root_delete_target_protected_trees entry
#     (RDT_PROT_A): the tree, anything under it, and a directory holding it;
#   * Claude Code's temp tree (RDT_CLAUDEC), laid out
#     <base>/<project>/<session>/scratchpad: the base, a project or session
#     directory, another session's scratchpad and anything under it, and a
#     directory holding the base. This session's own scratchpad is left to
#     rdt_allowed, which refuses it and its glob and allows what is under it.
#     Inside a temp root that lies in the base (TMPDIR pointed into the tree),
#     where the caller's own files sit at any level, only another session's
#     scratchpad is refused.
# Each list is screened with one string test before any call, so a delete of
# many targets in a repository of many worktrees stays inside the deadline.
rdt_protected() {
  local c="$1" real="$2" deep="$3" pat="$4" link="$5" p rest i t intmp free=0
  RDT_PROT=""
  # Win32 trims a trailing dot or space from a name: `.git.` names `.git`.
  if ((RDT_WIN)); then
    while [[ "$c" == */*[.\ ] && "${c##*/}" != . && "${c##*/}" != .. ]]; do c="${c%?}"; done
    while [[ "$real" == */*[.\ ] && "${real##*/}" != . && "${real##*/}" != .. ]]; do real="${real%?}"; done
  fi
  # A git worktree remove (<wt> 1) of a registered worktree root other than
  # the toplevel, strictly under a root rdt_allowed grants without the tree,
  # is what the command exists to delete: its root and its .git file are not
  # protected then.
  if ((${6:-0} && deep == 0)) && [[ -z "$pat" && "$c" != "$RDT_TREEC" ]]; then
    for p in ${RDT_PROT_B[@]+"${RDT_PROT_B[@]}"}; do
      [[ "$p" == "$c" ]] && rdt_allowed_beside_tree "$c" "$link" && free=1 && break
    done
  fi
  # Folded to lower case: a case-insensitive filesystem (the macOS default)
  # removes `.git` through `.GIT`.
  p="${c##*/}"
  if [[ "${p,,}" == .git ]]; then
    RDT_PROT="a .git"
    return 0
  fi
  if ((deep == 0 && link == 0 && free == 0)) && [[ -e "$real/.git" || -L "$real/.git" ]]; then
    if [[ -z "$pat" ]]; then
      RDT_PROT="a directory holding a .git"
      return 0
    fi
    if rdt_pat_hits .git "$pat"; then
      RDT_PROT="the .git inside it"
      return 0
    fi
  fi
  for ((i = 0; i < ${#RDT_PROT_B[@]}; i++)); do
    p="${RDT_PROT_B[i]}"
    [[ "$p" == "$c"* ]] || continue
    if [[ "$p" == "$c" ]]; then
      if [[ -z "$pat" ]] && ((deep == 0 && free == 0)); then
        RDT_PROT="${RDT_PROT_BW[i]}"
        return 0
      fi
      continue
    fi
    if rdt_reaches "$c" "$p" "$deep" "$pat"; then
      RDT_PROT="a directory holding ${RDT_PROT_BW[i]}"
      return 0
    fi
  done
  for ((i = 0; i < ${#RDT_PROT_A[@]}; i++)); do
    p="${RDT_PROT_A[i]}"
    if [[ "$c" == "$p" || "$c" == "$p"/* ]]; then
      RDT_PROT="${RDT_PROT_AW[i]}"
      return 0
    fi
    if [[ "$p" == "$c"* ]] && rdt_reaches "$c" "$p" "$deep" "$pat"; then
      RDT_PROT="a directory holding ${RDT_PROT_AW[i]}"
      return 0
    fi
  done
  for p in ${RDT_CLAUDEC[@]+"${RDT_CLAUDEC[@]}"}; do
    if [[ "$p" == "$c"* ]] && rdt_reaches "$c" "$p" "$deep" "$pat"; then
      RDT_PROT="a directory holding Claude Code's temp tree, where other sessions keep their scratchpads"
      return 0
    fi
    [[ "$c" == "$p" || "$c" == "$p"/* ]] || continue
    [[ -n "$RDT_SPC" ]] && rdt_within "$c" "$RDT_SPC" && continue
    intmp=0
    for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      if rdt_within "$t" "$p" && rdt_within "$c" "$t"; then
        intmp=1
        break
      fi
    done
    # <project>/<session>/<third>/... below the base.
    rest="${c:${#p}}"
    rest="${rest#/}"
    if ((intmp == 0)) && { [[ "$rest" != */* ]] ||
      { [[ "$rest" != */*/* ]] && { [[ -z "$pat" ]] || rdt_pat_hits scratchpad "$pat"; }; }; }; then
      RDT_PROT="Claude Code's temp tree, where sessions keep their scratchpads"
      return 0
    fi
    [[ "$rest" == */*/* ]] || continue
    rest="${rest#*/}"
    rest="${rest#*/}"
    if [[ "${rest%%/*}" == scratchpad ]]; then
      RDT_PROT="another session's scratchpad"
      return 0
    fi
  done
  return 1
}

# rdt_enum_links <directory> <pattern>: the matches of `<pattern>/` in
# <directory> that are symlinks, into RDT_LINKS. `rm -rf */` follows a symlink
# to a directory, so each such match is judged by where it points. Reads the
# directory only; nothing is expanded but the glob.
#
# Names first, with no trailing slash, and capped at MAX_GLOB before any entry
# is tested: a pattern ending in `/` makes bash stat every entry, and over a
# temp directory of 50,000 entries that ran past the hook timeout, which the
# harness answers WITHOUT a block. Past the cap the guard refuses.
# shellcheck disable=SC2206  # the pattern is meant to glob; IFS is empty so it cannot split
rdt_enum_links() {
  local dir="$1" pat="$2" m IFS=
  local -a all=()
  RDT_LINKS=()
  rdt_glob_on
  all=("$dir"/$pat)
  rdt_glob_off
  ((${#all[@]} > MAX_GLOB)) && rdt_block "too-many-glob-entries"
  for m in ${all[@]+"${all[@]}"}; do
    [[ -L "$m" && -d "$m" ]] && RDT_LINKS+=("$m")
  done
  return 0
}

# rdt_glob_dirs <base> <pattern>: the directories `<pattern>` matches, read
# from <base> (empty for an absolute pattern), into RDT_GLOB. Expanded ONE
# component at a time, each match a quoted literal for the next level, and
# every entry read, file or directory, counts toward one running total across
# all the levels: past MAX_GLOB the guard refuses at once instead of listing a
# whole tree, and the deadline is checked before every directory read.
# nullglob is on and dotglob off, as in a default bash; a literal component
# keeps only the directories that exist.
# shellcheck disable=SC2206  # the component is meant to glob; IFS is empty so it cannot split
rdt_glob_dirs() {
  local pat="$2" c d m total=0 IFS=
  local -a cur=() next=() comps=() hits=()
  RDT_GLOB=()
  if [[ -n "$1" ]]; then
    cur=("${1%/}")
  elif [[ "$pat" =~ ^([A-Za-z]:)/(.*)$ ]]; then
    cur=("${BASH_REMATCH[1]}")
    pat="${BASH_REMATCH[2]}"
  else
    cur=("")
  fi
  IFS=/ read -r -a comps <<<"$pat"
  IFS=
  rdt_glob_on
  for c in ${comps[@]+"${comps[@]}"}; do
    [[ -n "$c" ]] || continue
    next=()
    for d in ${cur[@]+"${cur[@]}"}; do
      rdt_deadline
      if [[ "$c" == *[*?[]* ]]; then
        # Names first, with no trailing slash, so the directory is read
        # without a stat per entry; the count is capped before any match is
        # tested for being a directory.
        hits=("$d"/$c)
        total=$((total + ${#hits[@]}))
        ((total > MAX_GLOB)) && rdt_block "too-many-glob-entries"
        for m in ${hits[@]+"${hits[@]}"}; do
          [[ -d "$m" ]] && next+=("$m")
        done
      elif [[ -d "$d/$c" ]]; then
        next+=("$d/$c")
      fi
    done
    cur=(${next[@]+"${next[@]}"})
    ((${#cur[@]})) || break
  done
  rdt_glob_off
  RDT_GLOB=(${cur[@]+"${cur[@]}"})
  return 0
}

# rdt_add_pair <path> <mode> <enum> <operand> [glob]: one target for the
# judgment, appended to rdt_judge_pending's arrays (tp tn td te tw tg,
# deduplicated through tseen), which this reads through bash's dynamic scope.
# [glob] is the last-component pattern of a whole target named by the
# directory in front of it, whose matches are what the delete removes.
# shellcheck disable=SC2034  # the arrays belong to the caller
rdt_add_pair() {
  local p="$1" mode="$2" last="" key
  # git resolves a worktree-remove word through every symlink (wtm, set by
  # rdt_judge_pending), so it is never judged as a leaf rm would unlink.
  [[ "$mode" == leaf && "${wtm:-0}" == 1 ]] && mode=whole
  if [[ "$mode" == leaf ]]; then
    last="${p##*/}"
    rdt_parent_to p "$p"
  else
    [[ -z "$p" ]] && p=/
    [[ "$p" =~ ^[A-Za-z]:$ ]] && p="$p/"
  fi
  key="$mode|$p|$last|$3|${5:-}|${wtm:-0}"
  [[ -n "${tseen[$key]+x}" ]] && return 0
  tseen[$key]=1
  tp+=("$p")
  tn+=("$last")
  if [[ "$mode" == deep ]]; then td+=(1); else td+=(0); fi
  te+=("$3")
  tw+=("$4")
  tg+=("${5:-}")
  tx+=("${wtm:-0}")
  ((${#tp[@]} > MAX_TARGETS)) && rdt_block "too-many-targets"
  return 0
}

# rdt_add_literal <path> <operand>: <path> placed in LITERAL mode (no `~`,
# HOME, `$` or glob read in it) and added as a target. Clobbers RDT_PL_*.
rdt_add_literal() {
  local t rc=0
  rdt_place_to t "$1" 3 || rc=$?
  ((rc == 2)) && rdt_block "unplaceable" "'$2'"
  ((rc == 0)) || return 0
  rdt_add_pair "$t" "$RDT_PL_MODE" "" "$2"
}

# rdt_judge_pending: the outside-tree judgment, once, after both passes.
rdt_judge_pending() {
  local np=${#RDT_P_TEXT[@]}
  ((np)) || return 0
  ((RDT_ORIGIN_OVERFLOW)) && rdt_block "too-many-origins"
  local k m no unk cdp t p sp c rc mode enum full slash abs glob base g t2 word lastc e gp wtm wtany=0
  local -a tp=() tn=() td=() te=() tw=() tg=() tx=() gl=()
  local -A tseen=()
  # Every target from every directory it may run from, each distinct one
  # once. In leaf mode the parent is resolved and the name appended as is;
  # otherwise the whole path is resolved (see rdt_place_to).
  for ((k = 0; k < np; k++)); do
    rdt_deadline
    word="${RDT_P_TEXT[k]}"
    wtm="${RDT_P_WT[k]:-0}"
    ((wtm)) && wtany=1
    rc=0
    rdt_place_to t "$word" "${RDT_P_Q[k]}" || rc=$?
    ((rc == 2)) && rdt_block "unplaceable" "'$word'"
    ((rc == 0)) || continue
    if ((RDT_P_SUB[k])); then
      no=${#RDT_ORIGINS[@]}
      unk=$rdt_cd_unknown
      cdp=$rdt_cd_refuse
    else
      no=${RDT_P_NORIG[k]}
      unk=${RDT_P_UNK[k]}
      cdp=${RDT_P_REF[k]}
    fi
    if ((RDT_PL_ABS == 0)); then
      ((cdp)) && rdt_block "unplaceable" "'$word' (after a cd that CDPATH may send anywhere)"
      ((unk)) && continue
    fi
    mode="$RDT_PL_MODE"
    enum="$RDT_PL_ENUM"
    full="$RDT_PL_FULL"
    slash="$RDT_PL_SLASH"
    abs="$RDT_PL_ABS"
    glob="$RDT_PL_GLOB"
    for ((m = 0; m < no; m++)); do
      if ((abs)); then p="$t"; else rdt_join_to p "${RDT_ORIGINS[m]}" "$t"; fi
      # A glob that matches nothing reaches rm as its own text, so every
      # glob operand is also judged as that literal path.
      if ((glob)); then
        if ((abs)); then t2="$full"; else rdt_join_to t2 "${RDT_ORIGINS[m]}" "$full"; fi
        ((slash)) && t2+=/
        rdt_add_literal "$t2" "$word"
      fi
      if [[ "$mode" != deep ]]; then
        gp=""
        ((glob)) && gp="${full##*/}"
        rdt_add_pair "$p" "$mode" "$enum" "$word" "$gp"
        continue
      fi
      # A glob before the last component: its directory part is expanded
      # with real globbing from this directory, and each match is judged as
      # a concrete, LITERAL path, so a link it passes through is followed and
      # a `$` or bracket in a matched name is never read again. With no
      # match, the literal directory in front of the glob is judged.
      base=""
      ((abs)) || base="${RDT_ORIGINS[m]}"
      rdt_glob_dirs "$base" "${full%/*}"
      gl=(${RDT_GLOB[@]+"${RDT_GLOB[@]}"})
      if ((${#gl[@]} == 0)); then
        rdt_add_pair "$p" deep "" "$word"
        continue
      fi
      lastc="${full##*/}"
      for g in "${gl[@]}"; do
        if [[ "$lastc" == *[*?[]* ]]; then
          # The last component globs too: its matches are children of g, and
          # with a trailing slash the links among them are read.
          e=""
          ((slash)) && e="$lastc"
          rdt_add_pair "$g" whole "$e" "$word" "$lastc"
        else
          t2="$g/$lastc"
          ((slash)) && t2+=/
          rdt_add_literal "$t2" "$word"
        fi
      done
    done
  done
  ((${#tp[@]} || wtany)) || return 0

  # The scratchpad, read only now so the dispatcher cache answers every other
  # call. A NUL byte in it refuses: there is a target to judge, and the
  # scratchpad it would be judged against cannot be read faithfully.
  sp=""
  if hook::jq_fields "$INPUT" '.scratchpad_dir'; then
    ((HOOK_JQ_FIELDS_NUL)) && rdt_block "nul-field" "scratchpad_dir"
    sp="${HOOK_JQ_FIELDS[0]:-}"
    sp="${sp//\\//}"
  fi
  rdt_is_abs "$sp" || sp=""
  hook::_temp_root_candidates
  local -a temps=()
  for c in ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}; do temps+=("${c//\\//}"); done
  # ONE tree: the payload cwd's. A directory a cd reaches is judged against
  # it too, never against a tree of its own, so `cd <other checkout> && rm -rf
  # x` is outside.
  local tree=""
  rdt_tree_to tree "${RDT_ORIGINS[0]}"
  rdt_deadline
  # The user's allowed roots, from this hook's own environment (userConfig),
  # never from the command text. An entry that is empty, relative, UNC, a
  # drive path on a host without drives, over the operand bounds, or holds a
  # glob character, a line break or a `..` component grants nothing. One
  # trailing `*` after a literal name makes a NAME-PREFIX entry instead
  # (`D:/worktrees/.tmp-*`): its directory follows the same rules, and the name
  # before the `*` may hold no glob character. A `*` that is one whole
  # segment followed by one literal name makes a SEGMENT entry
  # (`D:/worktrees/*/.work`): its directory follows the same rules, and the
  # name may hold no glob character and is not `.` or `..`. HOME is resolved
  # with them, and an unusable HOME leaves the whole list unused.
  local -a allow=() pdir=() pname=() sdir=() sname=()
  local home="${HOME:-}" roots="${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS:-}" x pfx sfx
  home="${home//\\//}"
  if ! rdt_is_abs "$home" || rdt_is_unc "$home"; then roots=""; fi
  while [[ -n "$roots" ]]; do
    c="${roots%%,*}"
    if [[ "$c" == "$roots" ]]; then roots=""; else roots="${roots#*,}"; fi
    [[ "$c" != *[$'\n\r']* ]] || continue
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"
    c="${c//\\//}"
    pfx=""
    sfx=""
    if [[ "$c" == */?*'*' ]]; then
      pfx="${c##*/}"
      pfx="${pfx%'*'}"
      c="${c%/*}"
      [[ -n "$pfx" && "$pfx" != *[*?[]* ]] || continue
    elif [[ "$c" == */'*'/?* ]]; then
      sfx="${c##*/}"
      c="${c%/*}"
      c="${c%/'*'}"
      [[ "$sfx" != *[*?[]* && "$sfx" != . && "$sfx" != .. ]] || continue
    fi
    x="${c//[^\/]/}"
    [[ -n "$c" && "$c" != *[$'\n\r*?[']* && "/$c/" != */../* ]] || continue
    ((${#c} + ${#pfx} + ${#sfx} <= MAX_OPERAND_LEN && ${#x} <= MAX_OPERAND_DEPTH)) || continue
    if ! rdt_is_abs "$c" || rdt_is_unc "$c"; then continue; fi
    ((RDT_WIN)) || [[ ! "$c" =~ ^[A-Za-z]: ]] || continue
    if [[ -n "$pfx" ]]; then
      ((RDT_WIN)) && pfx="${pfx,,}"
      pdir+=("$c")
      pname+=("$pfx")
    elif [[ -n "$sfx" ]]; then
      ((RDT_WIN)) && sfx="${sfx,,}"
      sdir+=("$c")
      sname+=("$sfx")
    else
      allow+=("$c")
    fi
  done
  local hcl=""
  if rdt_is_abs "$home" && ! rdt_is_unc "$home"; then hcl="${home%/}/.claude"; fi
  ((${#allow[@]} + ${#pdir[@]} + ${#sdir[@]})) || home=""

  # The protected trees, judged ahead of every allowed root (rdt_protected):
  # the worktrees git keeps for the cwd's repository, ~/.claude, and the
  # user's block_root_delete_target_protected_trees, read like the allowed
  # roots, from this hook's own environment and never from the command text.
  # An entry that is empty, relative, a drive path on a host without drives,
  # over the operand bounds, or holds a glob character, a line break or a `..`
  # component protects nothing.
  rdt_worktrees "$tree"
  local -a wts=(${RDT_WT[@]+"${RDT_WT[@]}"}) prot=()
  # git worktree remove looks its <worktree> up as the trailing path
  # components of a registered worktree first, from any directory, so every
  # registered root a worktree-remove word ends is a target too, compared in
  # any case.
  if ((wtany)); then
    wtm=1
    for ((k = 0; k < np; k++)); do
      ((${RDT_P_WT[k]:-0})) || continue
      word="${RDT_P_TEXT[k]//\\//}"
      while [[ "$word" == ?*/ ]]; do word="${word%/}"; done
      [[ -n "$word" ]] || continue
      # An unquoted glob reaches git as its matches, so it is matched as a
      # pattern, which only adds roots.
      g=0
      ((${RDT_P_Q[k]:-0} != 2)) && [[ "$word" == *[*?[]* ]] && g=1
      for c in ${wts[@]+"${wts[@]}"}; do
        # shellcheck disable=SC2053  # the operand is meant to glob when g is 1
        if [[ "${c,,}" == "${word,,}" || "${c,,}" == */"${word,,}" ]] ||
          { ((g)) && [[ "${c,,}" == ${word,,} || "${c,,}" == */${word,,} ]]; }; then
          rdt_add_pair "$c" whole "" "${RDT_P_TEXT[k]}"
        fi
      done
    done
  fi
  ((${#tp[@]})) || return 0
  local trees="${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_PROTECTED_TREES:-}"
  while [[ -n "$trees" ]]; do
    c="${trees%%,*}"
    if [[ "$c" == "$trees" ]]; then trees=""; else trees="${trees#*,}"; fi
    [[ "$c" != *[$'\n\r']* ]] || continue
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"
    c="${c//\\//}"
    x="${c//[^\/]/}"
    [[ -n "$c" && "$c" != *[*?[]* && "/$c/" != */../* ]] || continue
    ((${#c} <= MAX_OPERAND_LEN && ${#x} <= MAX_OPERAND_DEPTH)) || continue
    rdt_is_abs "$c" || continue
    ((RDT_WIN)) || [[ ! "$c" =~ ^[A-Za-z]: ]] || continue
    prot+=("$c")
  done

  # One realpath over the parents, the tree, the temp roots, the scratchpad,
  # the allowed roots, HOME and the protected trees. A `*/` operand then has
  # its symlink matches added, each resolved whole, and on Windows one cygpath
  # maps every full target and root onto one spelling.
  rdt_resolve_all ${tp[@]+"${tp[@]}"} ${temps[@]+"${temps[@]}"} "$sp" "$tree" ${allow[@]+"${allow[@]}"} ${pdir[@]+"${pdir[@]}"} \
    ${sdir[@]+"${sdir[@]}"} "$home" \
    ${wts[@]+"${wts[@]}"} "$hcl" ${prot[@]+"${prot[@]}"}
  local n0=${#tp[@]} l
  for ((k = 0; k < n0; k++)); do
    [[ -n "${te[k]}" ]] || continue
    rdt_deadline
    rdt_enum_links "${RDT_RES[${tp[k]}]}" "${te[k]}"
    for l in ${RDT_LINKS[@]+"${RDT_LINKS[@]}"}; do
      tp+=("$l")
      tn+=("")
      td+=(0)
      tw+=("${tw[k]}")
      tg+=("")
      tx+=("${tx[k]}")
      ((${#tp[@]} > MAX_TARGETS)) && rdt_block "too-many-targets"
    done
  done
  ((${#tp[@]} > n0)) && rdt_resolve_all "${tp[@]:n0}"
  rdt_deadline
  local -a targets=()
  for ((k = 0; k < ${#tp[@]}; k++)); do
    rdt_join_to p "${RDT_RES[${tp[k]}]}" "${tn[k]}"
    targets[k]="$p"
  done
  local -a others=()
  for c in ${temps[@]+"${temps[@]}"} "$sp" "$tree" ${allow[@]+"${allow[@]}"} ${pdir[@]+"${pdir[@]}"} \
    ${sdir[@]+"${sdir[@]}"} "$home" ${wts[@]+"${wts[@]}"} "$hcl" ${prot[@]+"${prot[@]}"}; do
    [[ -n "$c" ]] && others+=("${RDT_RES[$c]}")
  done
  rdt_winmap_all ${targets[@]+"${targets[@]}"} ${others[@]+"${others[@]}"}
  rdt_deadline
  RDT_TEMPC=()
  for c in ${temps[@]+"${temps[@]}"}; do
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$c]}]}"
    rdt_root_like "$t" || RDT_TEMPC+=("$t")
  done
  # The scratchpad counts only strictly under a temp root, where a harness
  # puts it; a payload naming anywhere else as its scratchpad is ignored.
  RDT_SPC=""
  if [[ -n "$sp" ]]; then
    rdt_canon_to c "${RDT_WMAP[${RDT_RES[$sp]}]}"
    for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      [[ "$c" == "$t"/* ]] && RDT_SPC="$c" && break
    done
  fi
  RDT_TREEC=""
  if [[ -n "$tree" ]]; then
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$tree]}]}"
    rdt_root_like "$t" || RDT_TREEC="$t"
  fi
  # An allowed root, or a name-prefix or segment entry's directory, that is a
  # filesystem root or HOME itself is dropped. A `/` entry is dropped on every
  # host, even where `/` maps to the Git install directory, so it is judged
  # before the mapping as well as after it.
  RDT_ALLOWC=()
  RDT_PDIRC=()
  RDT_PNAME=()
  RDT_SDIRC=()
  RDT_SNAME=()
  RDT_HOMEC=""
  if [[ -n "$home" ]]; then
    rdt_canon_to RDT_HOMEC "${RDT_WMAP[${RDT_RES[$home]}]}"
    for c in ${allow[@]+"${allow[@]}"}; do
      [[ "${RDT_RES[$c]}" == / ]] && continue
      rdt_canon_to t "${RDT_WMAP[${RDT_RES[$c]}]}"
      rdt_root_like "$t" || rdt_is_root "${t,,}" || [[ "$t" == "$RDT_HOMEC" ]] || RDT_ALLOWC+=("$t")
    done
    for ((k = 0; k < ${#pdir[@]}; k++)); do
      [[ "${RDT_RES[${pdir[k]}]}" == / ]] && continue
      rdt_canon_to t "${RDT_WMAP[${RDT_RES[${pdir[k]}]}]}"
      { rdt_root_like "$t" || rdt_is_root "${t,,}" || [[ "$t" == "$RDT_HOMEC" ]]; } && continue
      RDT_PDIRC+=("$t")
      RDT_PNAME+=("${pname[k]}")
    done
    for ((k = 0; k < ${#sdir[@]}; k++)); do
      [[ "${RDT_RES[${sdir[k]}]}" == / ]] && continue
      rdt_canon_to t "${RDT_WMAP[${RDT_RES[${sdir[k]}]}]}"
      { rdt_root_like "$t" || rdt_is_root "${t,,}" || [[ "$t" == "$RDT_HOMEC" ]]; } && continue
      RDT_SDIRC+=("$t")
      RDT_SNAME+=("${sname[k]}")
    done
  fi
  # The protected trees in the compared spelling. A toplevel or worktree root
  # that is a filesystem root is dropped, as the tree arm drops it.
  RDT_PROT_B=()
  RDT_PROT_BW=()
  if [[ -n "$RDT_TREEC" ]]; then
    RDT_PROT_B+=("$RDT_TREEC")
    RDT_PROT_BW+=("the git toplevel of the working directory")
  fi
  for c in ${wts[@]+"${wts[@]}"}; do
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$c]}]}"
    rdt_root_like "$t" && continue
    RDT_PROT_B+=("$t")
    RDT_PROT_BW+=("a worktree root git has registered")
  done
  RDT_PROT_A=()
  RDT_PROT_AW=()
  if [[ -n "$hcl" ]]; then
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$hcl]}]}"
    RDT_PROT_A+=("$t")
    # shellcheck disable=SC2088  # the label names the directory, nothing expands it
    RDT_PROT_AW+=("~/.claude")
  fi
  # A listed tree that is a filesystem root is dropped, as an allowed root is.
  for c in ${prot[@]+"${prot[@]}"}; do
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$c]}]}"
    { rdt_root_like "$t" || rdt_is_root "${t,,}"; } && continue
    RDT_PROT_A+=("$t")
    RDT_PROT_AW+=("a tree in block_root_delete_target_protected_trees")
  done
  # A glob matches dot names on the PowerShell tool, and in bash or zsh once
  # the command turns on dotglob, GLOBIGNORE or globdots.
  RDT_DOTS=0
  [[ "$TOOL_NAME" == PowerShell ]] && RDT_DOTS=1
  case "${COMMAND,,}" in
  *dotglob* | *globignore* | *globdots* | *glob_dots*) RDT_DOTS=1 ;;
  *) ;;
  esac
  # Claude Code's temp tree: the base the payload scratchpad sits in, when the
  # scratchpad has the documented <base>/<project>/<session>/scratchpad shape
  # and the base is named claude or claude-<suffix>, and, under every temp
  # root, claude-<uid> (POSIX) or claude (Windows).
  RDT_CLAUDEC=()
  if [[ "$RDT_SPC" == */scratchpad ]]; then
    t="${RDT_SPC%/*}"
    t="${t%/*}"
    t="${t%/*}"
    [[ "${t##*/}" == claude || "${t##*/}" == claude-?* ]] && RDT_CLAUDEC+=("$t")
  fi
  for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
    if ((RDT_WIN)); then RDT_CLAUDEC+=("${t%/}/claude"); else RDT_CLAUDEC+=("${t%/}/claude-$UID"); fi
  done
  for ((k = 0; k < ${#tp[@]}; k++)); do
    rdt_deadline
    p="${RDT_WMAP[${targets[k]}]}"
    rdt_canon_to c "$p"
    # A symlink, or a leaf rm would follow through a trailing slash that does
    # not exist yet (a link the same command may create), never passes a
    # name-prefix or segment entry.
    l=0
    [[ -L "${targets[k]}" ]] && l=1
    [[ ! -e "${targets[k]}" && "${tw[k]}" =~ [/\\]\.?$ ]] && l=1
    if rdt_protected "$c" "${targets[k]}" "${td[k]}" "${tg[k]}" "$l" "${tx[k]}"; then
      rdt_block "protected-tree" "'$p' (the operand '${tw[k]}'), $RDT_PROT"
      continue
    fi
    rdt_allowed "$c" "${td[k]}" "$l" || rdt_block "outside-tree" "'$p' (the operand '${tw[k]}')"
  done
  return 0
}

# rdt_sink_check <index of the command word>: DECODER SINKS for one command. A
# shell reading its program from stdin (no -c and no script operand, -s, or
# /dev/stdin) and a source or `.` of /dev/stdin are refused when a decoder
# feeds them (rdt_dec_feed), and a here-string they read as their program that
# holds a substitution is parsed as that program. In a parse holding a paren
# or a backtick, a command whose program a substitution the tokenizer split
# off may supply opens the sink for the rest of the parse (rdt_sink): a shell
# or source with no operand (`bash <(...)`), eval with none (`eval` before a
# backtick), and eval, a -c operand or the command word itself ending in an
# unquoted `$` (`eval $(...)`, `$(...)`). Reads words, n and HOOK_SEG_* from
# rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_sink_check() {
  local k=$(($1 + 1)) b w c=0 s=0 stdin=0 last=$((n - 1)) split=0 open=0
  local -a herestr=() q0=()
  ((${rdt_flat:-1})) || open=1
  [[ "${words[last]}" == *'$' && "${HOOK_SEG_WORD_QUOTED[last]:-0}" == 0 ]] && split=$open
  if (($1 == last && split)); then
    rdt_sink=1
    return 0
  fi
  b="${words[$1]##*/}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  eval)
    ((open && (k >= n || split))) && rdt_sink=1
    return 0
    ;;
  source | .)
    ((k >= n)) || [[ "${words[k]}" == /dev/stdin || "${words[k]}" == /dev/fd/0 || "${words[k]}" == /proc/self/fd/0 ]] && stdin=1
    ;;
  bash | sh | zsh | dash | ksh | mksh)
    while ((k < n)); do
      w="${words[k]}"
      case "$w" in
      -- | -)
        k=$((k + 1))
        break
        ;;
      -o | +o | -O | +O | --rcfile | --init-file) k=$((k + 2)) ;;
      [-+]?*)
        if [[ "$w" =~ ^-[A-Za-z]+$ ]]; then
          [[ "$w" == *c* ]] && c=1
          [[ "$w" == *s* ]] && s=1
        fi
        k=$((k + 1))
        ;;
      *) break ;;
      esac
    done
    if ((c)); then
      ((open && (k >= n || (split && k == last)))) && rdt_sink=1
      return 0
    fi
    ((s || k >= n)) || [[ "${words[k]}" == /dev/stdin || "${words[k]}" == /dev/fd/0 || "${words[k]}" == /proc/self/fd/0 ]] && stdin=1
    ;;
  *) return 0 ;;
  esac
  ((stdin)) || return 0
  ((${rdt_dec_feed:-0})) && rdt_block "decoder-sink"
  ((open && k >= n)) && rdt_sink=1
  # The program it reads (SHELLS AND LAUNCHERS FROM BASH in the header): the
  # last redirection of fd 0, else the text the command before writes into the
  # pipe. A heredoc body is judged once the parse has it (rdt_ix_heredocs).
  local r=-1 nh=0 hd=0 prog="" has=0 dec=0
  for ((c = 0; c < ${#HOOK_SEG_REDIR_OP[@]}; c++)); do
    [[ "${HOOK_SEG_REDIR_OP[c]}" == '<<' || "${HOOK_SEG_REDIR_OP[c]}" == '<<-' ]] && nh=$((nh + 1))
    [[ "${HOOK_SEG_REDIR_OP[c]}" == '<'* && "${HOOK_SEG_REDIR_FD[c]:-0}" == 0 ]] || continue
    r=$c
    hd=$((nh - 1))
  done
  if ((r >= 0)); then
    case "${HOOK_SEG_REDIR_OP[r]}" in
    '<<' | '<<-') [[ -n "${rdt_hd_at-}" ]] && rdt_hd_shell "$((rdt_hd_at + hd))" "${HOOK_SEG_REDIR_TARGET[r]-}" ;;
    '<<<')
      prog="${HOOK_SEG_REDIR_TARGET[r]-}"
      has=1
      ;;
    *) ;;
    esac
  else
    case "${rdt_text_feed:-}" in
    [et]*)
      prog="${rdt_text_feed:1}"
      has=1
      [[ "$rdt_text_feed" == e* ]] && dec=1
      ;;
    h*)
      w="${rdt_text_feed:1}"
      rdt_hd_shell "${w%%:*}" "${w#*:}"
      ;;
    x) rdt_block "eval-too-long" ;;
    *) ;;
    esac
  fi
  for ((c = 0; c < ${#HOOK_SEG_REDIR_OP[@]}; c++)); do
    ((c == r && has)) && continue
    [[ "${HOOK_SEG_REDIR_OP[c]}" == '<<<' && "${HOOK_SEG_REDIR_FD[c]:-0}" == 0 ]] || continue
    # shellcheck disable=SC2016  # a literal `$(` and backtick, not an expansion
    case "${HOOK_SEG_REDIR_TARGET[c]}" in
    *'$('* | *'`'*) herestr+=("${HOOK_SEG_REDIR_TARGET[c]}") ;;
    *) ;;
    esac
  done
  ((${#herestr[@]} || has)) || return 0
  q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  for w in ${herestr[@]+"${herestr[@]}"}; do
    rdt_scanned=$((rdt_scanned + ${#w}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    rdt_parse "$w"
  done
  ((has)) && rdt_shell_prog "$prog" "$dec"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# rdt_hd_shell <heredoc index> <delimiter>: the heredoc a shell reads as its
# program, judged as shell text once the parse has its body, under the
# directory-change state of the shell that reads it (rdt_ix_heredocs).
# shellcheck disable=SC2329  # invoked from rdt_sink_check
rdt_hd_shell() {
  rdt_hd_lang[$1]='sh'
  rdt_hd_st[$1]="${#RDT_ORIGINS[@]} $rdt_cd_unknown $rdt_cd_refuse $2"
}

# rdt_shell_prog <text> <decode>: judge a program a shell reads on its stdin,
# its substitutions included, charged to the eval budget. The shell has read
# its stdin as the program, so its first command's feed is `none`, as the
# top-level parse's is. With <decode> 1 (an echo wrote it), also the text its
# backslash escapes stand for, which a POSIX echo writes.
# shellcheck disable=SC2329  # invoked from rdt_sink_check and rdt_ix_heredocs
rdt_shell_prog() {
  local rdt_text_feed="" rdt_seg_feed=none rdt_dec_feed=0 t="$1" d
  rdt_scanned=$((rdt_scanned + ${#t}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_scan_substitutions "$t" nested
  rdt_parse "$t"
  if (($2)) && [[ "$t" == *\\* ]]; then
    printf -v d '%b' "$t"
    [[ "$d" == "$t" ]] || rdt_shell_prog "$d" 0
  fi
  return 0
}

# rdt_check_segment <argv word>...: one simple command, as the shell would build
# it. Prefixed because guards share one process under run-guards.sh and two
# siblings already define a function named check_segment.
# shellcheck disable=SC2329  # invoked from rdt_segment, the hook::bash_parse_segments callback
rdt_check_segment() {
  # Every launcher, child shell and eval re-enters this function, so nesting
  # is bash recursion; deep enough, bash exhausts its stack and dies before a
  # block's `exit 2`. The depth is a dynamic local, so every return restores
  # the caller's count with no bookkeeping, and past MAX_SEGMENT_DEPTH the
  # guard REFUSES.
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  # Once this arm has work, the rest of the parse counts against its deadline.
  ((RDT_T0 >= 0)) && rdt_deadline
  if ((rdt_depth > 1)); then
    rdt_segments=$((rdt_segments + 1))
    ((rdt_segments > MAX_SEGMENTS)) && rdt_block "too-many-readings"
  fi
  local -a words=("$@")
  local n=$# i=0 j w base sval optarg consume_bare
  local abbr_forked=0

  # Command word: step over leading NAME=value assignments and over a launcher
  # that takes the real command as its argument. A launcher's own options are
  # skipped, and the ones that CONSUME AN OPERAND are skipped with it: without
  # that, `sudo -u bob rm -rf /` reads `bob` as the command word and the whole
  # segment is waved through.
  while ((i < n)); do
    w="${words[i]}"
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      # A CDPATH assignment, as a prefix or a segment of its own, lets a later
      # relative cd land anywhere.
      rdt_note_cdpath "$w"
      i=$((i + 1))
      continue
    fi
    # A RESERVED WORD ahead of the command is not the command. The tokenizer
    # splits on `;`, `&`, `|`, `(` and `)`, so a compound command hands over
    # segments that OPEN with one of these: `{ rm -rf /; }` arrives as `{ rm
    # -rf /`, `if true; then rm -rf /; fi` as `then rm -rf /`, and every loop
    # body as `do rm -rf /`. Without this arm the reserved word IS read as the
    # command word and the whole segment is waved through. `function` also
    # names the definition that follows, so its name word is stepped over with
    # it; a `name()` opener needs no arm, because `(` is a segment separator
    # and the name has already closed its own segment by then.
    case "$w" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until)
      i=$((i + 1))
      continue
      ;;
    function)
      i=$((i + 2))
      continue
      ;;
    coproc)
      # `coproc [NAME] command`. Bash accepts the NAME only ahead of a COMPOUND
      # command; ahead of a SIMPLE one the first word IS the command, so
      # `coproc shredder rm -rf /` runs a command named `shredder` and
      # `coproc bash -c '…'` runs bash. Stepping over any identifier followed
      # by a word therefore swallowed the real command word. The NAME is now
      # stepped over only when a compound opener follows it.
      i=$((i + 1))
      if ((i + 1 < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        case "${words[i + 1]}" in
        '{' | if | while | until | for | case | select | '[[') i=$((i + 1)) ;;
        *) ;;
        esac
      fi
      continue
      ;;
    *) ;;
    esac
    base="${w##*/}"
    # Lowercased BEFORE the suffix strip: `.exe` is spelled in any case on a
    # case-insensitive filesystem, and stripping first left `rm.EXE` reading as
    # `rm.exe` rather than `rm`.
    base="${base,,}"
    base="${base%.exe}"
    # optarg lists the launcher's operand-taking options, space-delimited on
    # both sides so a prefix cannot match. Every short form carries its LONG
    # alias beside it: the separate-operand spelling is the one that moves the
    # command word, and listing `-u` alone read `sudo --user root rm -rf /` as a
    # command named `root`. The `--opt=value` spelling is deliberately absent,
    # because it carries its own operand and consumes no following word.
    # consume_bare marks a launcher whose first bare word is its own argument
    # rather than the command (`timeout` takes a duration).
    consume_bare=0
    case "$base" in
    # sudo's -R / --chroot, -a and -c take an operand too, and are absent on
    # purpose: reading `sudo -R rm -rf /` as chroot `rm` would drop a refusal.
    # The plain walk steps over them alone, and the resolved walk takes the
    # operand (rdt_short_cluster_arg, rdt_long_takes_arg), so both are judged.
    sudo | doas) optarg=" -u --user -g --group -p --prompt -C --close-from -D --chdir -r --role -t --type -T --command-timeout -U --other-user -h --host " ;;
    # The util-linux launchers. Each operand list is read from the tool's own
    # getopt string; an option whose argument is OPTIONAL (nsenter's `-m`,
    # unshare's `--mount`) takes it only when attached, so it consumes no word.
    # taskset's mask, flock's lock file and chroot's NEWROOT always precede the
    # command, and chrt's priority does when it is all digits.
    taskset)
      optarg=""
      consume_bare=1
      ;;
    chrt)
      optarg=" -D --sched-deadline -P --sched-period -T --sched-runtime -U --clamp-min -X --clamp-max "
      consume_bare=1
      ;;
    flock)
      optarg=" -w --wait --timeout -E --conflict-exit-code --start --length --fd "
      consume_bare=1
      ;;
    unshare) optarg=" -R --root -w --wd -S --setuid -G --setgid -l --load-interp --map-user --map-users --map-group --map-groups --owner --propagation --setgroups --monotonic --boottime --whitelist-env " ;;
    nsenter) optarg=" -t --target -N --net-socket -S --setuid -G --setgid " ;;
    numactl) optarg=" -i --interleave -w --weighted-interleave -p --preferred -P --preferred-many -c --cpubind -N --cpunodebind -C --physcpubind -m --membind -S --shm -f --file -o --offset -L --length -M --shmmode -I --shmid " ;;
    chroot)
      optarg=" --userspec --groups "
      consume_bare=1
      ;;
    # setpriv's, prlimit's and systemd-run's getopt strings start with `+`, so
    # the first non-option is the command. setpriv's operand-taking options are
    # all long; prlimit's resource options (`--nofile=10`) take their limit
    # only when attached, so only -p and -o consume a word.
    setpriv) optarg=" --inh-caps --ambient-caps --ruid --euid --rgid --egid --reuid --regid --groups --bounding-set --securebits --pdeathsig --ptracer --selinux-label --apparmor-profile --landlock-access --landlock-rule --list-landlock-rights --seccomp-filter " ;; # spellchecker:disable-line
    prlimit) optarg=" -p --pid -o --output " ;;
    systemd-run) optarg=" -H --host -M --machine -C --capsule -u --unit -p --property --description --slice --expand-environment --service-type --uid --gid --nice --working-directory --root-directory -E --setenv --output --json --job-mode --background --path-property --socket-property --timer-property --on-active --on-boot --on-startup --on-unit-active --on-unit-inactive --on-calendar " ;;
    # shadow's `sg [-|-l] group [[-c] command]` runs exactly one word through
    # `sh -c`: the one after the group, or after a `-c` that has a word after
    # it. Later words are ignored, so that one word is re-parsed like su's -c
    # operand. Source: shadow-maint/shadow src/newgrp.c (sg is newgrp run under
    # that name; last change 10c5a20, fetched 2026-09-29): it reads `-` or `-l`
    # first, then the group (a word not starting with `-`), takes `command =
    # argv[1]` when `argv[0]` is `-c` and another word follows and `argv[0]`
    # otherwise, and runs `execl(SHELL, "sh", "-c", command)`; sg(1) on
    # man7.org says "The command will be executed with the /bin/sh shell". In
    # that source `-` and `-l` set initflag, whose chdir to the home directory
    # comes AFTER that execl, so a command runs from the current directory. The
    # guard still treats the directory as unknown, which only adds refusals.
    # Recheck when shadow's newgrp.c changes how `sg` builds its `sh -c`
    # command, or moves the home-directory chdir ahead of the execl.
    sg)
      j=$((i + 1))
      if ((j < n)) && [[ "${words[j]}" == - || "${words[j]}" == -l ]]; then
        ((RDT_ARM)) && rdt_cd_unknown=1
        j=$((j + 1))
      fi
      ((j < n)) && [[ "${words[j]}" != -* ]] || return 0
      j=$((j + 1))
      ((j + 1 < n)) && [[ "${words[j]}" == -c ]] && j=$((j + 1))
      ((j < n)) && rdt_parse "${words[j]}"
      return 0
      ;;
    # runuser has two grammars and both are judged, blocking if either does:
    # every -c / --command / --session-command operand is a command, and with
    # -u its non-option words are the command. Without -u the first non-option
    # is the user and the rest go to the shell, so they get su's scan. The
    # remapped provenance is saved first, because each parse rebuilds it.
    # Both getopt readings are judged (see rdt_runuser_argv), the second only
    # when it differs from the first.
    runuser)
      ((RDT_ARM)) && rdt_note_login ${words[@]+"${words[@]:i+1}"}
      local -a ru_cmds=() ru_argv=() ru_quoted=() ru_q0=()
      local ru_u ru_cmd ru_posix ru_key ru_seen=""
      ru_q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
      for ru_posix in 0 1; do
        HOOK_SEG_WORD_QUOTED=(${ru_q0[@]+"${ru_q0[@]}"})
        RDT_RU_POSIX=$ru_posix
        rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
        RDT_RU_POSIX=0
        rdt_ru_key_to ru_key
        [[ "$ru_key" == "$ru_seen" ]] && break
        ru_seen=$ru_key
        ru_u="$RDT_RU_U"
        ru_cmds=(${RDT_RU_CMDS[@]+"${RDT_RU_CMDS[@]}"})
        ru_argv=(${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"})
        ru_quoted=(${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"})
        rdt_su_shell_run
        for ru_cmd in ${ru_cmds[@]+"${ru_cmds[@]}"}; do
          rdt_parse "$ru_cmd"
        done
        if ((ru_u)); then
          HOOK_SEG_WORD_QUOTED=(${ru_quoted[@]+"${ru_quoted[@]}"})
          ((${#ru_argv[@]})) && rdt_check_segment "${ru_argv[@]}"
        elif ((${#ru_argv[@]} > 1)); then
          HOOK_SEG_WORD_QUOTED=()
          rdt_check_segment su "${ru_argv[@]:1}"
        fi
      done
      return 0
      ;;
    # `-S` / `--split-string` is absent on purpose: it is not an opaque option
    # argument but a COMMAND, and the arm below re-parses it.
    env) optarg=" -u --unset -C --chdir " ;;
    timeout)
      optarg=" -s --signal -k --kill-after "
      consume_bare=1
      ;;
    nice | ionice) optarg=" -n --adjustment -c --class --classdata -p --pid " ;;
    stdbuf) optarg=" -i -o -e --input --output --error " ;;
    # /usr/bin/time, not the bash keyword, takes a format and an output file.
    time) optarg=" -f --format -o --output " ;;
    exec) optarg=" -a " ;;
    # busybox is a multi-call binary: `busybox rm -rf /` runs its own rm.
    command | nohup | setsid | busybox) optarg="" ;;
    *) break ;;
    esac
    i=$((i + 1))
    while ((i < n)); do
      w="${words[i]}"
      case "$w" in
      --)
        i=$((i + 1))
        # `--` ends the options but not the positional: `taskset -- 1 rm` still
        # reads `1` as the mask. chrt's priority must be all digits, and
        # timeout's duration must start like a number, so `timeout -- rm -rf /`
        # keeps `rm` as the command word rather than reading it as a duration.
        # timeout's test follows strtod: leading space, a sign, then a digit,
        # a `.`, inf or nan in any case.
        if ((consume_bare && i < n)); then
          case "$base" in
          chrt) [[ "${words[i]}" =~ ^[0-9]+$ ]] && i=$((i + 1)) ;;
          timeout) [[ "${words[i]}" =~ ^[[:space:]]*[+-]?([0-9.]|[iI][nN][fF]|[nN][aA][nN]) ]] && i=$((i + 1)) ;;
          *) i=$((i + 1)) ;;
          esac
          # flock takes -c / --command right after its lock file, `--` or not.
          if [[ "$base" == "flock" ]] && ((i < n)) && [[ "${words[i]}" == "-c" || "${words[i]}" == "--command" ]]; then
            ((i + 1 < n)) && rdt_parse "${words[i + 1]}"
            return 0
          fi
        fi
        break
        ;;
      -*)
        # env -C and sudo -D run the command from another directory, and
        # sudo -i from the target user's home.
        if ((RDT_ARM)); then
          rdt_note_launcher_dir "$base" "$w" "$((i + 1 < n))" "${words[i + 1]-}" \
            "${HOOK_SEG_WORD_QUOTED[i]:-0}" "${HOOK_SEG_WORD_QUOTED[i + 1]:-0}"
        fi
        # flock runs a -c / --command operand through a shell, and demands it
        # be the last word, so the operand is the whole command.
        if [[ "$base" == "flock" && ("$w" == "-c" || "$w" == "--command") ]]; then
          ((i + 1 < n)) && rdt_parse "${words[i + 1]}"
          return 0
        fi
        # With --fd the lock is an already-open descriptor, so there is no lock
        # file and flock's first positional is the command itself.
        [[ "$base" == "flock" && ("$w" == "--fd" || "$w" == --fd=*) ]] && consume_bare=0
        # GNU env's `-S` SPLITS its operand and RUNS the result, so the operand
        # is a command and not an option argument to step over. The split words
        # are spliced back in ahead of whatever followed, exactly as
        # block-no-verify's git resolver does, and the segment is judged again.
        # Bounded: the splice replaces the `-S` word AND its operand with the
        # operand's own words, so the argv's byte count strictly decreases.
        if [[ "$base" == "env" ]]; then
          case "$w" in
          -S | --split-string)
            sval=""
            ((i + 1 < n)) && sval="${words[i + 1]}"
            hook::env_s_split "$sval"
            # Cleared because the provenance array belongs to the OUTER parse
            # and its indices do not describe these words; a stale 1 here would
            # read an empty word as a dropped backslash.
            HOOK_SEG_WORD_QUOTED=()
            rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
              ${words[@]+"${words[@]:i+2}"}
            return 0
            ;;
          -S* | --split-string=*)
            sval="${w#-S}"
            sval="${sval#--split-string=}"
            hook::env_s_split "$sval"
            HOOK_SEG_WORD_QUOTED=()
            rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
              ${words[@]+"${words[@]:i+1}"}
            return 0
            ;;
          --s*)
            # No other env long option starts with `s`, so every prefix is
            # --split-string (`env --spl='rm -rf /'`). The split is judged as
            # an extra reading and the plain walk goes on, so reading the
            # prefix can only add refusals.
            sval="${w#--}"
            if [[ "split-string" == "${sval%%=*}"* ]]; then
              local -a env_q=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
              if [[ "$w" == *=* ]]; then
                hook::env_s_split "${w#*=}"
                HOOK_SEG_WORD_QUOTED=()
                rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
                  ${words[@]+"${words[@]:i+1}"}
              elif ((i + 1 < n)); then
                hook::env_s_split "${words[i + 1]}"
                HOOK_SEG_WORD_QUOTED=()
                rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
                  ${words[@]+"${words[@]:i+2}"}
              fi
              HOOK_SEG_WORD_QUOTED=(${env_q[@]+"${env_q[@]}"})
            fi
            ;;
          *) ;;
          esac
        fi
        # An abbreviated long option takes its operand exactly as the full name
        # does. Two readings are judged, and a block from either stands: the
        # PLAIN one, which steps over the word alone,
        # and the RESOLVED one, which takes the operand at every abbreviation.
        # The first abbreviation in a plain walk starts one resolved walk of the
        # whole segment; a resolved walk consumes and never starts another, so
        # the work is two walks per segment, not one per combination.
        if ((i + 1 < n)) && [[ "$w" == --?* && "$w" != *=* && "$optarg" != *" $w "* ]] &&
          rdt_long_takes_arg "$base" "${w#--}"; then
          if ((rdt_abbr)); then
            i=$((i + 2))
            continue
          fi
          if ((abbr_forked == 0)); then
            abbr_forked=1
            rdt_resolved_walk ${words[@]+"${words[@]}"}
          fi
        fi
        # A short cluster ending in an operand-taking letter (`flock -nw 1`)
        # takes the next word as that letter's operand. It is judged on the
        # same two readings, through the same one resolved walk per segment.
        if [[ "$w" =~ ^-[A-Za-z]+$ && "$optarg" != *" $w "* ]] && rdt_short_cluster_arg "$base" "$w"; then
          if ((rdt_abbr)); then
            i=$((i + 1 + RDT_SC_NEXT))
            continue
          fi
          if ((abbr_forked == 0)); then
            abbr_forked=1
            rdt_resolved_walk ${words[@]+"${words[@]}"}
          fi
        fi
        if [[ -n "$optarg" && "$optarg" == *" $w "* ]]; then
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      *)
        ((consume_bare)) || break
        # chrt reads a priority only when the word is all digits; otherwise
        # that word is already the command.
        [[ "$base" == "chrt" && ! "$w" =~ ^[0-9]+$ ]] && break
        consume_bare=0
        i=$((i + 1))
        ;;
      esac
    done
  done
  ((i < n)) || return 0

  rdt_sink_check "$i"

  # A child shell runs its operand as a full command, so one process is every
  # command inside it. Re-parse that operand with the same tokenizer, which is
  # what block-no-verify.sh does for `git`. Asked AFTER the launcher walk, from
  # the resolved command word on, so `sudo bash -c '...'` is unwrapped too.
  # Re-entering the parser from its own callback is safe: its state is
  # dynamically scoped locals plus HOOK_SEG_* globals it rebuilds before every
  # call, and the only one this guard reads is rebuilt with them.
  if hook::shell_c_operand "${words[@]:i}"; then
    rdt_parse "$HOOK_SHELL_C_OPERAND"
    return 0
  fi

  base="${words[i]##*/}"
  # Lowercased before the suffix strip, for the reason given at the walk above.
  base="${base,,}"
  base="${base%.exe}"

  # A directory change moves where a later relative operand lands. Followed
  # only for the outside-tree arm, which is off without a payload cwd.
  if ((RDT_ARM)); then
    case "$base" in
    cd | pushd | popd)
      rdt_note_cd "$base" "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
      return 0
      ;;
    export | declare | typeset | readonly | local)
      for w in ${words[@]+"${words[@]:i+1}"}; do
        rdt_note_cdpath "$w"
      done
      return 0
      ;;
    su) rdt_note_login ${words[@]+"${words[@]:i+1}"} ;;
    *) ;;
    esac
  fi

  # `su` runs its `-c` operand through the target user's shell, so one process
  # is every command inside it, exactly as `bash -c` is. Resolved here rather
  # than in the shared hook::shell_c_operand because su's grammar differs: the
  # operand follows the FLAG, and a user name may sit ahead of it
  # (`su bob -c '…'`), where a shell takes its first bare word.
  #
  # FAIL-CLOSED rather than exact: EVERY word that follows a -c-like word is
  # parsed, not only the first. su takes the LAST -c it sees, and a word that
  # looks like -c may really be another option's operand (`su -w -c -c '…'`),
  # so parsing every candidate is what keeps both readings covered.
  if [[ "$base" == "su" ]]; then
    local k
    local sulong su_key su_q0=()
    su_q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
    rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
    rdt_ru_key_to su_key
    rdt_su_shell_run
    HOOK_SEG_WORD_QUOTED=(${su_q0[@]+"${su_q0[@]}"})
    RDT_RU_POSIX=1
    rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
    RDT_RU_POSIX=0
    rdt_ru_key_to sulong
    [[ "$sulong" != "$su_key" ]] && rdt_su_shell_run
    for ((k = i + 1; k < n; k++)); do
      case "${words[k]}" in
      --?*)
        # getopt_long takes any unambiguous prefix. No other su option starts
        # with `c`, and `se` is the shortest prefix that separates
        # session-command from shell and supp-group.
        sulong="${words[k]#--}"
        sulong="${sulong%%=*}"
        if [[ -n "$sulong" && ("command" == "$sulong"* || ("${#sulong}" -ge 2 && "session-command" == "$sulong"*)) ]]; then
          if [[ "${words[k]}" == *=* ]]; then
            rdt_parse "${words[k]#*=}"
            # su builds `sh -c -- CMD` from an operand of `--`, so CMD is next.
            ((k + 1 < n)) && [[ "${words[k]#*=}" == "--" ]] && rdt_parse "${words[k + 1]}"
          else
            ((k + 1 < n)) && rdt_parse "${words[k + 1]}"
            # A shell reads `-c -- '…'` as `-c '…'`, so the word after `--` too.
            ((k + 2 < n)) && [[ "${words[k + 1]}" == "--" ]] && rdt_parse "${words[k + 2]}"
          fi
        fi
        ;;
      -*)
        if [[ "${words[k]}" =~ ^-[A-Za-z]+$ && "${words[k]}" == *c* ]]; then
          ((k + 1 < n)) && rdt_parse "${words[k + 1]}"
          ((k + 2 < n)) && [[ "${words[k + 1]}" == "--" ]] && rdt_parse "${words[k + 2]}"
        fi
        # An operand ATTACHED to the -c is the text after the first `c` that
        # only letters precede: `su -c'rm -rf /'` is the one word `-crm -rf /`.
        if [[ "${words[k]}" =~ ^-[A-Zabd-z]*c. ]]; then
          sulong="${words[k]#-}"
          rdt_parse "${sulong#*c}"
          ((k + 1 < n)) && [[ "${sulong#*c}" == "--" ]] && rdt_parse "${words[k + 1]}"
        fi
        ;;
      *) ;;
      esac
    done
    return 0
  fi

  # `eval` runs its arguments as a command in THIS shell, so the child-shell
  # unwrap above never applies to it: there is no `-c` and no new process. Its
  # arguments are joined with a space, exactly as eval joins them, and parsed.
  # Bounded because each level drops at least the `eval` word itself.
  #
  # An operand a trailing backslash produced arrives EMPTY (the tokenizer has
  # no character left to emit), so a join by text would hand the re-parse
  # `rm -rf ` with no operand at all and `eval rm -rf \` would pass. The
  # literal `\` is restored first, by the same provenance test the operand loop
  # below uses, and `HOOK_SEG_WORD_QUOTED` is read HERE because the re-parse
  # rebuilds it.
  if [[ "$base" == "eval" ]] && ((i + 1 < n)); then
    local -a ev=()
    for ((j = i + 1; j < n; j++)); do
      if [[ -z "${words[j]}" ]] && ((${HOOK_SEG_WORD_QUOTED[j]:-0} == 1)); then
        # shellcheck disable=SC1003  # a literal backslash character, not a quote escape
        ev+=('\')
      else
        ev+=("${words[j]}")
      fi
    done
    # The joined text is charged to the same tokenizing budget as a
    # substitution body: nested evals re-tokenize nearly the whole command at
    # every level, which is the same multiplication the budget exists to stop.
    local evtext="${ev[*]}"
    rdt_scanned=$((rdt_scanned + ${#evtext}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    rdt_parse "$evtext"
    return 0
  fi

  # A find whose expression deletes removes what its start points hold (FIND
  # DELETES in the header), an rsync or a robocopy removes from its
  # destination or its sources (RSYNC DELETES, ROBOCOPY DELETES), xargs and
  # parallel run their command on the items they read (PIPELINE-FED DELETES),
  # an interpreter runs the code it is given (INTERPRETER DELETES), mv,
  # truncate, shred and dd move away or destroy what they name (MOVES AND
  # CONTENT DESTROYERS), and watch and cmd /c run the command they are given
  # (SHELLS AND LAUNCHERS FROM BASH).
  case "$base" in
  mv | truncate | shred | dd)
    rdt_content_check "$i" "$base"
    return 0
    ;;
  watch)
    rdt_watch_check "$i"
    return 0
    ;;
  cmd)
    rdt_cmd_check "$i"
    return 0
    ;;
  python | python[0-9]* | py | pypy | pypy[0-9]* | node | nodejs | perl | perl[0-9]* | ruby | ruby[0-9]*)
    rdt_interp_check "$i" "$base"
    return 0
    ;;
  find)
    rdt_find_check "$i"
    return 0
    ;;
  rsync)
    rdt_rsync_check "$i"
    return 0
    ;;
  robocopy)
    rdt_robocopy_check "$i"
    return 0
    ;;
  git)
    rdt_git_worktree_check "$i"
    return 0
    ;;
  xargs)
    rdt_xargs_check "$i"
    return 0
    ;;
  parallel)
    rdt_parallel_check "$i"
    return 0
    ;;
  *) ;;
  esac

  [[ "$base" == "rm" ]] || return 0

  # Flags and operands. `--` ends option parsing, exactly as rm reads it.
  # Operands are kept as INDICES, not values, because the decision below needs
  # each one's quoting provenance as well as its text.
  local recursive=0 no_preserve=0 end_of_opts=0 long
  local -a operand_idx=()
  for ((j = i + 1; j < n; j++)); do
    w="${words[j]}"
    if ((end_of_opts == 0)); then
      case "$w" in
      --)
        end_of_opts=1
        continue
        ;;
      --?*)
        # coreutils parses long options with getopt_long, which accepts any
        # UNAMBIGUOUS prefix, so `rm --r -f /` and `rm --no-p /` are the real
        # options spelled short. Of rm's long options only `--recursive` starts
        # with `r` and only `--no-preserve-root` starts with `n`, so every
        # non-empty prefix of either name is unambiguous and is treated as that
        # option. Matching the exact spelling alone left both a bypass.
        long="${w#--}"
        if [[ "recursive" == "$long"* ]]; then
          recursive=1
        elif [[ "no-preserve-root" == "$long"* ]]; then
          no_preserve=1
        fi
        continue
        ;;
      -?*)
        # A short cluster is letters only; anything else is not a flag rm reads.
        if [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *[rR]* ]]; then
          recursive=1
        fi
        continue
        ;;
      *) ;;
      esac
    fi
    operand_idx+=("$j")
  done

  # Every arm below needs recursion. A non-recursive `rm /` is refused by rm
  # itself and is not this guard's business.
  ((recursive)) || return 0
  rdt_deleter=1
  ((no_preserve)) && rdt_block "no-preserve-root"

  for j in ${operand_idx[@]+"${operand_idx[@]}"}; do
    rdt_delete_operand "${words[j]}" "${HOOK_SEG_WORD_QUOTED[j]:-0}"
  done
  return 0
}

# rdt_delete_operand <word> <provenance>: one target of a recursive delete, an
# rm operand or a find start point, as its argv word, through every arm.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_delete_operand() {
  local w="$1" q="$2" x rc
  local -a bx=()
  if [[ "$w" == "$RDT_IX_HOLE" ]]; then
    rdt_block "interp-unplaceable" "a path the code computes"
    return 0
  fi
  # An EMPTY operand that a BACKSLASH ESCAPE produced is a dropped trailing
  # backslash: bash passes a literal `\` when one ends the input, and MSYS
  # resolves that to the current drive root, which is the #92593 incident
  # minus its quotes. The tokenizer cannot represent it (it has no character
  # left to emit), so provenance is what separates it from `rm -rf ""`, whose
  # empty operand comes wholly from a quoted span (provenance 2) and is
  # refused as an empty operand instead.
  if [[ -z "$w" ]]; then
    ((q == 1)) && rdt_block "root-operand" "/"
    rdt_block "empty-operand"
  fi
  # No path a filesystem accepts is longer than PATH_MAX (4096 on Linux, and
  # far less on Windows), so a longer operand names nothing rm could delete.
  # It is refused before any per-operand scan: the tail strip and the
  # normalization walk an operand's segments, and a 16 KB operand of `/*`
  # segments took 17 s on a Linux runner, near the hook timeout the harness
  # answers WITHOUT a block.
  ((${#w} > MAX_OPERAND_LEN)) && rdt_block "operand-too-long" "an operand of ${#w} bytes"
  # Resolving a path costs one lookup per component, and on Windows about
  # 10 ms each: 2,000 missing components took realpath 90 s. No path in real
  # use is this deep, so a deeper operand is refused unscanned.
  x="${w//[^\/\\]/}"
  ((${#x} > MAX_OPERAND_DEPTH)) && rdt_block "operand-too-long" "an operand with ${#x} path separators"
  # Brace expansion runs before rm sees its argv, so every alternative is
  # judged as an operand of its own. A fully quoted brace is literal, and so
  # is one in a path no shell expands (provenance 3); a partly quoted one that
  # would expand cannot be told apart from a literal one by the tokenizer's
  # provenance, so it is refused.
  if [[ "$w" == *'{'* ]] && ((q != 2 && q != 3)); then
    # Bounded before the walk: a word of thousands of braces makes the
    # expander's scan quadratic.
    x="${w//[^\{]/}"
    ((${#w} > MAX_BRACE_WORD || ${#x} > MAX_BRACE_OPEN)) && rdt_block "brace-too-large" "of ${#w} bytes with ${#x} braces"
    rc=0
    rdt_brace_expand "$w" || rc=$?
    if ((rc != 0)); then
      rdt_block "brace" "'$w'"
      return 0
    fi
    if ((${#RDT_BX[@]} != 1)) || [[ "${RDT_BX[0]}" != "$w" ]]; then
      ((q == 1)) && rdt_block "brace" "'$w'"
      bx=(${RDT_BX[@]+"${RDT_BX[@]}"})
      # An empty alternative is dropped, exactly as bash drops it.
      for x in ${bx[@]+"${bx[@]}"}; do
        [[ -n "$x" ]] && rdt_check_operand "$x" 0
      done
      return 0
    fi
  fi
  rdt_check_operand "$w" "$q"
}

# rdt_watch_check <index of the watch word>: the command watch runs (SHELLS AND
# LAUNCHERS FROM BASH in the header). Its options end at the first word that
# is not one (getopt `+bCcefd::ghq:n:prs:twvx` and the long options, any
# unambiguous prefix included): -n, -q and -s (--interval, --equexit,
# --shotsdir) take an argument, and -d one attached to it. The rest is joined
# by spaces and run through `sh -c`, so it is parsed as shell text, a dropped
# trailing backslash restored as for eval; with -x or --exec it is the argv
# itself. Reads words, n and HOOK_SEG_WORD_QUOTED from rdt_check_segment
# through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_watch_check() {
  local k=$(($1 + 1)) x=0 w j c l hit text
  local -a q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"}) ev=()
  while ((k < n)); do
    w="${words[k]}"
    case "$w" in
    --)
      k=$((k + 1))
      break
      ;;
    --?*)
      l="${w#--}"
      if [[ "$l" != *=* ]]; then
        hit=""
        for c in beep color no-color differences errexit follow chgexit equexit exec help interval precise \
          no-rerun shotsdir no-title no-wrap version; do
          if [[ "$c" == "$l" ]]; then
            hit=$c
            break
          fi
          [[ "$c" == "$l"* ]] && hit+="$c "
        done
        case "${hit% }" in
        exec) x=1 ;;
        interval | equexit | shotsdir) k=$((k + 1)) ;;
        *) ;;
        esac
      fi
      ;;
    -?*)
      for ((j = 1; j < ${#w}; j++)); do
        c="${w:j:1}"
        case "$c" in
        x) x=1 ;;
        d) break ;;
        n | q | s)
          ((j + 1 < ${#w})) || k=$((k + 1))
          break
          ;;
        *) ;;
        esac
      done
      ;;
    *) break ;;
    esac
    k=$((k + 1))
  done
  ((k < n)) || return 0
  if ((x)); then
    HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]:k}"})
    rdt_check_segment "${words[@]:k}"
  else
    for ((j = k; j < n; j++)); do
      if [[ -z "${words[j]}" ]] && ((${q0[j]:-0} == 1)); then
        # shellcheck disable=SC1003  # a literal backslash character, not a quote escape
        ev+=('\')
      else
        ev+=("${words[j]}")
      fi
    done
    text="${ev[*]}"
    rdt_scanned=$((rdt_scanned + ${#text}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    rdt_parse "$text"
  fi
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# rdt_cmd_check <index of the cmd word>: from the Bash tool, the command line
# cmd runs after /c or /k (SHELLS AND LAUNCHERS FROM BASH in the header), a
# switch's leading `//` read as `/` (`cmd //c`). Each statement of the line
# ends at a word that is `&`, `&&`, `|` or `||`. One word after the switch
# (or a command attached to it, `/crd`) is the whole line, split as cmd
# splits one, and each statement is judged as the PowerShell lane judges
# cmd's (rdt_ps_cmd_rd: rd and rmdir with /s, robocopy). Several are its
# words, and each statement is judged as that command is from the Bash tool
# (rm, robocopy) and, when it is rd or rmdir, by rdt_cmd_rd_bash. Reads words, n and
# HOOK_SEG_WORD_QUOTED from rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_cmd_check() {
  local k o w j s
  local -a cw=() st=() q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  for ((k = $1 + 1; k < n; k++)); do
    o="${words[k]}"
    [[ "$o" =~ ^//[^/] ]] && o="${o:1}"
    case "${o,,}" in
    /c | /k) break ;;
    /c?* | /k?*)
      rdt_ps_cmd_split_to cw "${o:2}"
      break
      ;;
    *) ;;
    esac
  done
  k=$((k + 1))
  if ((${#cw[@]} == 0 && k < n - 1)); then
    s=$k
    for ((j = k; j <= n; j++)); do
      w='&'
      ((j < n)) && w="${words[j]}"
      case "$w" in
      '&' | '&&' | '|' | '||')
        if ((j > s)); then
          HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]:s:j-s}"})
          rdt_check_segment "${words[@]:s:j-s}"
          HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
          rdt_cmd_rd_bash "$s" "$j"
        fi
        s=$((j + 1))
        ;;
      *) ;;
      esac
    done
    return 0
  fi
  if ((${#cw[@]} == 0 && k == n - 1)); then
    rdt_ps_cmd_split_to cw "${words[k]}"
  elif ((${#cw[@]} && k < n)); then
    for w in "${words[@]:k}"; do
      [[ "$w" =~ ^//[^/]+$ ]] && w="${w:1}"
      cw+=("$w")
    done
  fi
  for w in ${cw[@]+"${cw[@]}"} '&'; do
    case "$w" in
    '&' | '&&' | '|' | '||')
      ((${#st[@]})) && rdt_ps_cmd_rd "${st[@]}"
      st=()
      ;;
    *) st+=("$w") ;;
    esac
  done
  return 0
}

# rdt_cmd_rd_bash <first index> <index past the last>: one statement of the
# words cmd /c runs from the Bash tool, when it is rd or rmdir. Its switches
# are /s and /q, alone or run together (`/s/q`), and any word with two leading
# slashes; every other word is a path, a POSIX one included, which MSYS
# converts before cmd reads it. With a switch holding `s`, each path is
# judged as an operand of a recursive rm, and none at all is an empty
# operand. Reads words and q0 from rdt_cmd_check through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_cmd_check
rdt_cmd_rd_bash() {
  local j b lw rec=0
  local -a pi=()
  b="${words[$1]##*[\\/]}"
  b="${b,,}"
  case "${b%.exe}" in
  rd | rmdir) ;;
  *) return 0 ;;
  esac
  for ((j = $1 + 1; j < $2; j++)); do
    lw="${words[j],,}"
    if [[ "$lw" =~ ^//[^/]+$ || "$lw" =~ ^(/[sq?]+)+$ ]]; then
      [[ "${lw//\//}" == *s* ]] && rec=1
    else
      pi+=("$j")
    fi
  done
  ((rec)) || return 0
  ((${#pi[@]})) || rdt_block "empty-operand"
  for j in ${pi[@]+"${pi[@]}"}; do
    rdt_delete_operand "${words[j]}" "${q0[j]:-0}"
  done
  return 0
}

# rdt_find_check <index of the find word>: a find whose expression deletes has
# each start point of either reading judged once, as an operand of a recursive
# rm (FIND DELETES in the header).
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_find_check() {
  local k
  rdt_find_scan "$1"
  ((RDT_FIND_DEL)) || return 0
  rdt_deleter=1
  local -a sw=(${RDT_FIND_SW[@]+"${RDT_FIND_SW[@]}"}) sq=(${RDT_FIND_SQ[@]+"${RDT_FIND_SQ[@]}"})
  for ((k = 0; k < ${#sw[@]}; k++)); do
    rdt_delete_operand "${sw[k]}" "${sq[k]}"
  done
  return 0
}

# rdt_rsync_check <index of the rsync word>: an rsync carrying --del, --delete
# or a --delete-<mode> has its destination, the last operand, judged as an
# operand of a recursive rm, and one carrying --remove-source-files has each
# operand before it judged so (RSYNC DELETES in the header). An operand rsync
# reads as remote is left alone. Reads words, n and HOOK_SEG_WORD_QUOTED from
# rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_rsync_check() {
  local k c w pre del=0 rsf=0 eoo=0 last
  local -a op=() tg=()
  for ((k = $1 + 1; k < n; k++)); do
    w="${words[k]}"
    if ((eoo == 0)); then
      case "$w" in
      --)
        eoo=1
        continue
        ;;
      --del | --delete | --delete-*)
        del=1
        continue
        ;;
      --remove-source-files | --remove-sent-files)
        rsf=1
        continue
        ;;
      --*=*) continue ;;
      --?*)
        case "${w#--}" in
        info | debug | stderr | checksum-choice | chmod | chown | rsh | rsync-path | backup-dir | suffix | \
          partial-dir | temp-dir | compare-dest | copy-dest | link-dest | filter | exclude | exclude-from | \
          include | include-from | files-from | log-file | log-file-format | password-file | early-input | \
          max-delete | max-size | min-size | max-alloc | usermap | groupmap | timeout | contimeout | \
          compress-choice | compress-level | compress-threads | skip-compress | copy-as | address | port | \
          sockopts | outbuf | out-format | bwlimit | stop-after | stop-at | write-batch | only-write-batch | \
          read-batch | protocol | iconv | checksum-seed | block-size | remote-option | modify-window | \
          config | dparam | log-format | time-limit | cc | zc | zl | zt)
          k=$((k + 1))
          ;;
        *) ;;
        esac
        continue
        ;;
      -?*)
        # A cluster letter that takes an argument takes the rest of the word,
        # or the next word when it ends the cluster.
        for ((c = 1; c < ${#w}; c++)); do
          case "${w:c:1}" in
          [efTBM@])
            ((c + 1 < ${#w})) || k=$((k + 1))
            break
            ;;
          *) ;;
          esac
        done
        continue
        ;;
      *) ;;
      esac
    fi
    op+=("$k")
  done
  ((del || rsf)) || return 0
  # Under xargs or parallel the items read are appended as operands, so they
  # are judged as this rsync's targets whatever it names itself.
  rdt_deleter=1
  # A brace or a glob can expand to more words or to none, so which word is
  # last is not known: every operand is then judged, the one-operand listing
  # included.
  for k in ${op[@]+"${op[@]}"}; do
    w="${words[k]}"
    ((${HOOK_SEG_WORD_QUOTED[k]:-0} == 2)) && continue
    if [[ "$w" == *['{*?[']* ]]; then
      tg=("${op[@]}")
      break
    fi
  done
  if ((${#tg[@]} == 0)); then
    # One operand only lists it; nothing is copied or removed.
    ((${#op[@]} > 1)) || return 0
    last="${op[${#op[@]} - 1]}"
    ((del)) && tg+=("$last")
    if ((rsf)); then
      for k in "${op[@]}"; do
        ((k == last)) || tg+=("$k")
      done
    fi
  fi
  for k in "${tg[@]}"; do
    w="${words[k]}"
    # rsync reads a `:` after a host as a remote shell path and rsync:// as a
    # daemon, so the delete runs on another machine. One letter before the
    # `:` is judged as a drive path, as block-cross-domain reads it, and so is
    # a host spelled with an expansion or a brace (`"${HOME:-/}"`).
    pre="${w%%:*}"
    if [[ "$w" == rsync://* ]] ||
      [[ "$pre" != "$w" && "$pre" != */* && ${#pre} -ge 2 &&
        "$pre" != *'$'* && "$pre" != *'`'* && "$pre" != *'{'* ]]; then
      continue
    fi
    rdt_delete_operand "$w" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  return 0
}

# rdt_msys_excluded <word> <list>: status 0 when the MSYS2_ARG_CONV_EXCL value
# <list> leaves <word> unconverted, that is when one of its `;`-separated
# entries is `*` or a non-empty prefix of <word>. An empty <list> excludes
# nothing.
rdt_msys_excluded() {
  local e rest="$2;"
  while [[ -n "$rest" ]]; do
    e="${rest%%;*}"
    rest="${rest#*;}"
    [[ "$e" == '*' || (-n "$e" && "$1" == "$e"*) ]] && return 0
  done
  return 1
}

# rdt_robocopy_scan <msys> <excl> <word> ...: read the words after a robocopy
# command word into RDT_RC_DEST (it purges its destination: /MIR or /PURGE),
# RDT_RC_SRC (it deletes from its source: /MOVE or /MOV) and RDT_RC_OP (the
# 0-based index among the words of each word that is neither an option nor in
# a /XF, /XD or /IF list), the first of which is the source and the second the
# destination (ROBOCOPY DELETES in the header). Shared by the Bash and
# PowerShell lanes. <msys> is 1 for the Bash lane, where MSYS rewrites a
# single-slash one-letter word (`/e`) to that drive's root before robocopy
# sees it, so that word is an operand and never an option, unless the
# MSYS2_ARG_CONV_EXCL value <excl> leaves it unconverted. It is 0 for the
# PowerShell lane and for a Bash robocopy whose prefix sets MSYS_NO_PATHCONV.
rdt_robocopy_scan() {
  local k w msys="$1" excl="$2" list=0
  shift 2
  RDT_RC_DEST=0 RDT_RC_SRC=0
  RDT_RC_OP=()
  for ((k = 1; k <= $#; k++)); do
    w="${!k}"
    if ((msys)) && [[ "$w" =~ ^/[A-Za-z]$ ]] && ! rdt_msys_excluded "$w" "$excl"; then
      ((list)) || RDT_RC_OP+=("$((k - 1))")
      continue
    fi
    w="${w,,}"
    [[ "$w" == //* ]] && w="${w#/}"
    [[ "$w" == -?* ]] && w="/${w#-}"
    case "${w%%:*}" in
    /mir | /purge) RDT_RC_DEST=1 list=0 ;;
    /move | /mov) RDT_RC_SRC=1 list=0 ;;
    /xf | /xd | /if) list=1 ;;
    /s | /e | /lev | /z | /b | /zb | /j | /efsraw | /copy | /dcopy | /sec | /copyall | /nocopy | \
      /secfix | /timfix | /a+ | /a- | /create | /fat | /256 | /mon | /mot | /rh | /pf | /ipg | /sj | \
      /sl | /mt | /nodcopy | /nooffload | /compress | /sparse | /noclone | /iomaxsize | /iorate | \
      /threshold | /a | /m | /ia | /xa | /xc | /xn | /xo | /xx | /xl | /im | /is | /it | /max | /min | \
      /maxage | /minage | /maxlad | /minlad | /xj | /fft | /dst | /xjd | /xjf | /r | /w | /reg | /tbd | \
      /lfsm | /l | /x | /v | /ts | /fp | /bytes | /ns | /nc | /nfl | /ndl | /np | /eta | /log | /log+ | \
      /unilog | /unilog+ | /tee | /njh | /njs | /unicode | /job | /save | /quit | /nosd | /nodd)
      list=0
      ;;
    *) ((list)) || RDT_RC_OP+=("$((k - 1))") ;;
    esac
  done
  return 0
}

# rdt_robocopy_check <index of the robocopy word>: a robocopy carrying /MIR,
# /PURGE, /MOVE or /MOV has the destination or the source it deletes from
# judged as an operand of a recursive rm (ROBOCOPY DELETES in the header).
# Reads words, n and HOOK_SEG_WORD_QUOTED from rdt_check_segment through
# bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_robocopy_check() {
  local k w msys=1 excl='' unknown=0 envw=0
  local -a op=() tg=()
  # A prefix assignment is in the environment the MSYS runtime spawns
  # robocopy from: MSYS_NO_PATHCONV, set to anything, turns path conversion
  # off, and MSYS2_ARG_CONV_EXCL lists the words it leaves alone. The last
  # assignment of a name is the one robocopy gets. An assignment whose value
  # holds a `$` or a backtick is not known until it runs, and an env option
  # (`env -u NAME`, `env -i`) can drop an assignment made before it, so with
  # either the conversion state is unknown: every operand is then judged, each
  # single-slash one-letter word included.
  for ((k = 0; k < $1; k++)); do
    w="${words[k]}"
    case "$w" in
    MSYS_NO_PATHCONV=* | MSYS2_ARG_CONV_EXCL=*)
      [[ "${w#*=}" == *['$`']* ]] && unknown=1
      if [[ "$w" == MSYS_NO_PATHCONV=* ]]; then
        msys=0
      else
        excl="${w#*=}"
      fi
      ;;
    *)
      w="${w##*/}"
      w="${w,,}"
      if [[ "${w%.exe}" == env ]]; then
        envw=1
      elif ((envw)) && [[ "${words[k]}" == -* ]]; then
        unknown=1
      fi
      ;;
    esac
  done
  if ((unknown)); then
    msys=1 excl=''
  fi
  rdt_robocopy_scan "$msys" "$excl" ${words[@]+"${words[@]:$1+1}"}
  ((RDT_RC_DEST || RDT_RC_SRC)) || return 0
  rdt_deleter=1
  for k in ${RDT_RC_OP[@]+"${RDT_RC_OP[@]}"}; do
    op+=("$((k + $1 + 1))")
  done
  # A brace, a glob or an unquoted expansion can become more words or none,
  # and so can a quoted "$@" or "${a[@]}", so which word is the source or the
  # destination is not known: every operand is then judged. So it is when the
  # conversion state is unknown.
  ((unknown)) && tg=(${op[@]+"${op[@]}"})
  for k in ${op[@]+"${op[@]}"}; do
    if [[ "${words[k]}" == *'$@'* || "${words[k]}" == *'[@]}'* ]] ||
      { ((${HOOK_SEG_WORD_QUOTED[k]:-0} != 2)) && [[ "${words[k]}" == *['{*?[$`']* ]]; }; then
      tg=("${op[@]}")
      break
    fi
  done
  if ((${#tg[@]} == 0)); then
    ((RDT_RC_SRC && ${#op[@]} > 0)) && tg+=("${op[0]}")
    ((RDT_RC_DEST && ${#op[@]} > 1)) && tg+=("${op[1]}")
  fi
  for k in ${tg[@]+"${tg[@]}"}; do
    rdt_delete_operand "${words[k]}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  return 0
}

# rdt_git_worktree_check <index of the git word>: a `git worktree remove` with
# -f or --force has each <worktree> operand judged as an operand of a recursive
# rm, marked so the judgment also reads it as a worktree name (GIT WORKTREE
# REMOVE in the header). Reads words, n and HOOK_SEG_WORD_QUOTED from
# rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_git_worktree_check() {
  local k w force=0 eoo=0 rel=0
  local -a op=()
  # A prefix assignment (`GIT_DIR=… git`, `env GIT_DIR=… git`) selects a
  # repository the same way the options below do.
  for ((k = 0; k < $1; k++)); do
    case "${words[k]}" in
    GIT_DIR=* | GIT_WORK_TREE=* | GIT_COMMON_DIR=*) rel=1 ;;
    *) ;;
    esac
  done
  for ((k = $1 + 1; k < n; k++)); do
    w="${words[k]}"
    case "$w" in
    -C | --git-dir | --work-tree) rel=1 k=$((k + 1)) ;;
    --git-dir=* | --work-tree=*) rel=1 ;;
    -c | --namespace | --config-env | --super-prefix | --attr-source) k=$((k + 1)) ;;
    -*) ;;
    *) break ;;
    esac
  done
  [[ "${words[k]-}" == worktree && "${words[k + 1]-}" == remove ]] || return 0
  for ((k = k + 2; k < n; k++)); do
    w="${words[k]}"
    if ((eoo == 0)); then
      case "$w" in
      --)
        eoo=1
        continue
        ;;
      --?*)
        [[ "force" == "${w#--}"* ]] && force=1
        continue
        ;;
      -?*)
        [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *f* ]] && force=1
        continue
        ;;
      *) ;;
      esac
    fi
    op+=("$k")
  done
  ((force)) || return 0
  rdt_deleter=1
  RDT_WTRM=1
  # After a directory change the trailing-components lookup may read another
  # repository's registry too.
  ((RDT_ARM && (${#RDT_ORIGINS[@]} > 1 || rdt_cd_unknown || rdt_cd_refuse))) && rel=1
  for k in ${op[@]+"${op[@]}"}; do
    # A name that is not absolute may match a worktree of a repository whose
    # registry this guard does not read. A `$` word may expand to one.
    w="${words[k]//\\//}"
    if ((rel && RDT_ARM)); then
      # shellcheck disable=SC2016,SC2088  # matching the literal text of the operand
      case "$w" in
      '~' | '~/'* | '$HOME' | '$HOME/'* | '${HOME}' | '${HOME}/'*) ;;
      *) rdt_is_abs "$w" || rdt_block "unplaceable" "'${words[k]}' (a worktree named relative to a repository the command selects)" ;;
      esac
    fi
    rdt_delete_operand "${words[k]}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  RDT_WTRM=0
  return 0
}

# rdt_gnu_scan <index of the command word> <letters> <letter:long name>...: the
# words after a coreutils command word, read as getopt_long reads them, into
# RDT_GNU_OP (the index of each operand) and RDT_GNU_SEEN (the letter of each
# option met that takes an argument). Options stand anywhere up to `--`. A
# short cluster letter in <letters> takes the rest of the word, or the next
# word when it ends the cluster; a long option that is a prefix of a listed
# name takes the next word unless written with `=`. Under POSIXLY_CORRECT,
# which a command inherits unseen, options end at the first operand, so a word
# an option takes after an operand is an operand too. Reads words and n from
# rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_content_check, under a parser callback
rdt_gnu_scan() {
  local k=$1 c w x long letters="$2" eoo=0 take
  shift 2
  RDT_GNU_OP=()
  RDT_GNU_SEEN=""
  for ((k = k + 1; k < n; k++)); do
    w="${words[k]}"
    if ((eoo == 0)); then
      take=0
      case "$w" in
      --)
        eoo=1
        continue
        ;;
      --?*)
        long="${w#--}"
        long="${long%%=*}"
        for x in "$@"; do
          if [[ "${x#?:}" == "$long"* ]]; then
            RDT_GNU_SEEN+="${x%%:*}"
            [[ "$w" == *=* ]] || take=1
            break
          fi
        done
        ;;
      -?*)
        for ((c = 1; c < ${#w}; c++)); do
          x="${w:c:1}"
          if [[ "$letters" == *"$x"* ]]; then
            RDT_GNU_SEEN+="$x"
            ((c + 1 < ${#w})) || take=1
            break
          fi
        done
        ;;
      *)
        RDT_GNU_OP+=("$k")
        continue
        ;;
      esac
      if ((take)); then
        k=$((k + 1))
        ((k < n && ${#RDT_GNU_OP[@]})) && RDT_GNU_OP+=("$k")
      fi
      continue
    fi
    RDT_GNU_OP+=("$k")
  done
  return 0
}

# rdt_content_check <index of the command word> <its name>: each source an mv
# moves away, and each file a truncate, shred or dd `of=` destroys the content
# of, is judged as an operand of a recursive rm (MOVES AND CONTENT DESTROYERS
# in the header). Reads words, n and HOOK_SEG_WORD_QUOTED from
# rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_content_check() {
  local k w every=0 of=0
  local -a tg=()
  # Under xargs or parallel the items read are appended as operands, so they
  # are judged as this command's targets whatever it names itself. A dd whose
  # every of= names a stream writes nothing the items could change.
  if [[ "$2" == dd ]]; then
    for ((k = $1 + 1; k < n; k++)); do
      w="${words[k]}"
      [[ "$w" == of=* ]] || continue
      of=1
      # The null and standard streams hold no content to lose.
      case "${w#of=}" in
      /dev/null | /dev/stdout | /dev/stderr) continue ;;
      '')
        rdt_block "empty-operand"
        continue
        ;;
      *) ;;
      esac
      rdt_deleter=1
      rdt_delete_operand "${w#of=}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
    done
    ((of)) || rdt_deleter=1
    return 0
  fi
  rdt_deleter=1
  case "$2" in
  mv) rdt_gnu_scan "$1" tS t:target-directory S:suffix ;;
  truncate) rdt_gnu_scan "$1" rs r:reference s:size ;;
  *) rdt_gnu_scan "$1" ns n:iterations _:random-source s:size ;;
  esac
  tg=(${RDT_GNU_OP[@]+"${RDT_GNU_OP[@]}"})
  # mv moves into its last operand unless -t names the directory. A last word
  # that can become several words makes all but its final word sources, and so
  # do the items xargs or parallel may append after it, so with either every
  # operand is judged.
  if [[ "$2" == mv && "$RDT_GNU_SEEN" != *t* ]] && ((${#tg[@]} > 1 && rdt_fed == 0)); then
    k="${tg[${#tg[@]} - 1]}"
    w="${words[k]}"
    if [[ "$w" == *'$@'* || "$w" == *'[@]}'* ]] ||
      { ((${HOOK_SEG_WORD_QUOTED[k]:-0} != 2)) && [[ "$w" == *['{*?[$`']* ]]; }; then
      every=1
    fi
    ((every)) || unset "tg[$((${#tg[@]} - 1))]"
  fi
  for k in ${tg[@]+"${tg[@]}"}; do
    rdt_delete_operand "${words[k]}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  return 0
}

# --- Interpreter deletes (INTERPRETER DELETES in the header) -----------------
#
# The code is read as masked text: each string literal is replaced by \001,
# its kind, its index and \002, and its value is kept aside. A kind is s, a
# plain literal; x, one with an interpolation; u, one with an escape this
# reading does not decode; c, a command the language runs through a shell;
# and d, such a command with an escape this reading does not decode.
# RDT_IX_HOLE stands for an argv word the code builds from something other
# than a readable literal, and rdt_delete_operand refuses it as a target. The
# lexer strips \001 and \002 from the code, so no literal spells a placeholder
# or the hole.
RDT_IX_HOLE=$'\001hole\002'
RDT_IX_PH_RE=$'^\001([scxud])([0-9]+)\002$'
RDT_IX_PH_ANY=$'\001([scxud])([0-9]+)\002'
# A ruby keyword option (`secure: true`) or hash pair whose key is a symbol or
# a literal (`:noop => true`), written as the whole argument.
RDT_IX_KWARG_RE=$'^([A-Za-z_][A-Za-z0-9_]*:([^:]|$)|:[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=>|\001[sx][0-9]+\002[[:space:]]*=>)'

# rdt_interp_check <index of the interpreter word> <its name>: the program a
# python, node, perl or ruby runs, from each -c, -e, --eval or --print option,
# from a here-string, or from a heredoc it reads as its program, judged by
# rdt_ix_code. A script file is not read. Reads words, n, HOOK_SEG_* and
# rdt_hd_at from rdt_check_segment and rdt_segment through bash's dynamic
# scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_interp_check() {
  local lang k j w c rest stdin=1 stop=0 last=-1 hd=-1 nh=0 rop
  local -a code=() q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  case "$2" in
  py | python* | pypy*) lang=py ;;
  node | nodejs) lang=js ;;
  perl*) lang=pl ;;
  *) lang=rb ;;
  esac
  for ((k = $1 + 1; k < n && stop == 0; k++)); do
    w="${words[k]}"
    case "$w" in
    -) break ;;
    --)
      ((k + 1 < n)) && stdin=0
      break
      ;;
    --?*)
      case "$lang:$w" in
      js:--eval | js:--print)
        code+=("${words[k + 1]-}")
        k=$((k + 1))
        stdin=0
        ;;
      js:--eval=* | js:--print=*)
        code+=("${w#*=}")
        stdin=0
        ;;
      py:--check-hash-based-pycs | js:--require | js:--import | js:--loader | js:--experimental-loader | js:--conditions | js:--input-type | js:--env-file | js:--title | rb:--encoding | rb:--external-encoding | rb:--internal-encoding)
        k=$((k + 1))
        ;;
      *) ;;
      esac
      ;;
    -?*)
      if [[ "$lang" == js ]]; then
        case "$w" in
        -e | -p | -pe | -ep)
          code+=("${words[k + 1]-}")
          k=$((k + 1))
          stdin=0
          ;;
        -r | -C) k=$((k + 1)) ;;
        *) ;;
        esac
        continue
      fi
      # A short cluster: flags, then at most one letter that takes the rest of
      # the word or, with nothing after it, the next word. Python's -c and -m
      # end its options.
      for ((j = 1; j < ${#w} && j < 32; j++)); do
        c="${w:j:1}"
        rest="${w:j+1}"
        case "$lang:$c" in
        py:c | pl:e | pl:E | rb:e)
          if [[ -n "$rest" ]]; then
            code+=("$rest")
          else
            code+=("${words[k + 1]-}")
            k=$((k + 1))
          fi
          stdin=0
          [[ "$lang" == py ]] && stop=1
          break
          ;;
        py:m)
          stdin=0
          stop=1
          break
          ;;
        py:W | py:X | pl:I | pl:M | pl:m | rb:r | rb:I | rb:C | rb:E)
          [[ -z "$rest" ]] && k=$((k + 1))
          break
          ;;
        pl:l | pl:0)
          [[ "$rest" =~ ^(x[0-9A-Fa-f]*|[0-7]*) ]]
          j=$((j + ${#BASH_REMATCH[0]}))
          ;;
        pl:[ixdDCVF] | rb:[xiWKTF0]) break ;;
        *) ;;
        esac
      done
      # A cluster longer than the cap is not read to its end, so a letter
      # past it that takes the code would be missed.
      ((j >= 32 && j < ${#w})) && rdt_block "interp-unplaceable" "code after an option cluster too long to read (${w:0:40}...)"
      ;;
    *)
      # The script, or the first argument of code already given. A script
      # named /dev/stdin is the program on stdin, as `-` is.
      if ((${#code[@]} == 0)) && [[ "$w" != /dev/stdin ]]; then stdin=0; fi
      break
      ;;
    esac
  done
  # With no code option and no script, the program is stdin: the last
  # redirection of fd 0 says what that is.
  if ((stdin && ${#code[@]} == 0)); then
    for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
      rop="${HOOK_SEG_REDIR_OP[j]}"
      [[ "$rop" == '<<' || "$rop" == '<<-' ]] && nh=$((nh + 1))
      [[ "$rop" == '<'* && "${HOOK_SEG_REDIR_FD[j]:-0}" == 0 ]] || continue
      last=$j
      hd=$((nh - 1))
    done
    if ((last >= 0)); then
      case "${HOOK_SEG_REDIR_OP[last]}" in
      '<<<') code+=("${HOOK_SEG_REDIR_TARGET[last]-}") ;;
      '<<' | '<<-')
        # The body is read once the parse has it, as if from here: its
        # delimiter, to check the index, and the directory-change state.
        if [[ -n "${rdt_hd_at-}" ]]; then
          rdt_hd_lang[rdt_hd_at + hd]="$lang"
          rdt_hd_st[rdt_hd_at + hd]="${#RDT_ORIGINS[@]} $rdt_cd_unknown $rdt_cd_refuse ${HOOK_SEG_REDIR_TARGET[last]-}"
        fi
        ;;
      *) ;;
      esac
    fi
  fi
  # The code's own argv are not targets: a deleter's literal path is judged
  # below, and any other is refused, so xargs does not judge its items here.
  local d0="$rdt_deleter"
  for c in ${code[@]+"${code[@]}"}; do
    rdt_ix_code "$lang" "$c"
  done
  rdt_deleter="$d0"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# rdt_ix_heredocs <text>: after the parse of <text>, judge each heredoc body an
# interpreter or a shell reads as its program, in the language rdt_hd_lang
# records for its index (sh for a shell, read by rdt_shell_prog), under the
# directory-change state rdt_hd_st recorded where the interpreter ran. The
# index is trusted only when the parse reports as many bodies as the segments
# carried openers and each recorded index holds a body with the recorded
# delimiter; otherwise (an opener on a segment with no word, or one with no
# body) every body is judged in each recorded language. A directory change an
# interpreter's code makes is dropped afterwards: it ran in the interpreter's
# child. A shell body is judged from every origin the command has, and the
# ones its cd lines add are kept, since its targets index them.
# shellcheck disable=SC2329  # invoked from rdt_parse
rdt_ix_heredocs() {
  local k m every=0 st e no d0="$rdt_deleter" unk0="$rdt_cd_unknown" ref0="$rdt_cd_refuse"
  local -a hdb=(${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}) ix=() lg=() sts=() bodies=() orig=()
  ((${#hdb[@]} == rdt_hd_n)) || every=1
  for k in "${!rdt_hd_lang[@]}"; do
    st="${rdt_hd_st[k]-}"
    e="${hdb[k]-}"
    [[ -n "$e" && "${e#* * * * }" == "${st#* * * }" ]] || every=1
  done
  for k in "${!rdt_hd_lang[@]}"; do
    for ((m = 0; m < ${#hdb[@]}; m++)); do
      ((every || m == k)) || continue
      ix+=("$m")
      lg+=("${rdt_hd_lang[k]}")
      sts+=("${rdt_hd_st[k]-}")
    done
  done
  ((${#ix[@]})) || return 0
  RDT_IX_BODIES=()
  hook::_c_locale rdt_ix_slice "$1" "${ix[@]}"
  bodies=(${RDT_IX_BODIES[@]+"${RDT_IX_BODIES[@]}"})
  orig=(${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"})
  for ((k = 0; k < ${#lg[@]}; k++)); do
    st="${sts[k]}"
    no="${st%% *}"
    st="${st#* }"
    rdt_cd_unknown="${st%% *}"
    st="${st#* }"
    rdt_cd_refuse="${st%% *}"
    [[ "$no" =~ ^[0-9]+$ ]] || no=${#orig[@]}
    [[ "$rdt_cd_unknown" =~ ^[01]$ ]] || rdt_cd_unknown="$unk0"
    [[ "$rdt_cd_refuse" =~ ^[01]$ ]] || rdt_cd_refuse="$ref0"
    if [[ "${lg[k]}" == sh ]]; then
      # A shell's own cd lines add origins its later targets are judged
      # from, by index, so the list is not cut here: they land after every
      # origin the command has, and the body is judged from all of them.
      rdt_shell_prog "${bodies[k]-}" 0
      orig=(${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"})
      continue
    fi
    RDT_ORIGINS=(${orig[@]+"${orig[@]:0:no}"})
    rdt_ix_code "${lg[k]}" "${bodies[k]-}"
    RDT_ORIGINS=(${orig[@]+"${orig[@]}"})
  done
  rdt_cd_unknown="$unk0"
  rdt_cd_refuse="$ref0"
  rdt_deleter="$d0"
  return 0
}

# rdt_ix_slice <text> <body index>...: each body rdt_ix_heredocs's hdb names,
# cut from <text> by its byte offsets (so under LC_ALL=C) without its
# delimiter line, into RDT_IX_BODIES. Under an unquoted delimiter bash drops
# each backslash-newline and unescapes \\, \$ and \` before the program reads
# the body, and so does this.
# shellcheck disable=SC1003,SC2329  # '\' is a literal backslash; invoked through hook::_c_locale
rdt_ix_slice() {
  local t="$1" e s u q c b m bs='\' dl='$' bt='`'
  shift
  for m in "$@"; do
    e="${hdb[m]}"
    s="${e%% *}"
    e="${e#* }"
    u="${e%% *}"
    e="${e#* }"
    q="${e%% *}"
    e="${e#* }"
    c="${e%% *}"
    b="${t:s:u-s}"
    if [[ "$c" == 1 ]]; then
      b="${b%$'\n'}"
      if [[ "$b" == *$'\n'* ]]; then b="${b%$'\n'*}"$'\n'; else b=""; fi
    fi
    if [[ "$q" == 0 ]]; then
      b="${b//"$bs$bs"/$'\001'}"
      b="${b//"$bs"$'\n'/}"
      b="${b//"$bs$dl"/"$dl"}"
      b="${b//"$bs$bt"/"$bt"}"
      b="${b//$'\001'/"$bs"}"
    fi
    RDT_IX_BODIES+=("$b")
  done
}

# rdt_ix_code <lang> <code>: judge one program, its lang py, js, pl or rb
# (INTERPRETER DELETES in the header). Each call the code makes to a deleter
# of its language has its path arguments judged as operands of a recursive
# rm, each call that runs a command has that command judged as a shell or the
# program would receive it, and so does each backtick, perl qx and ruby %x.
# shellcheck disable=SC2016,SC2329  # literal regex text; invoked from rdt_interp_check
rdt_ix_code() {
  local lang="$1" ix_m="" ix_cm="" ix_ri k
  local -a ix_v=() ix_k=() ix_re=()
  case "${2,,}" in
  *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
    *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) ;;
  *) return 0 ;;
  esac
  rdt_ix_lex "$2"
  # Each pair is a call kind for rdt_ix_calls and the regex of its names.
  case "$lang" in
  py)
    ix_re=(del '(^|[^A-Za-z0-9_])(rmtree|os\.remove|os\.unlink|os\.rmdir|os\.removedirs)'
      run '(^|[^A-Za-z0-9_])(system|popen|run|call|check_call|check_output|Popen|getoutput|getstatusoutput)')
    ;;
  js)
    ix_re=(del '(^|[^A-Za-z0-9_$])(rmSync|rmdirSync|unlinkSync)'
      del '(\.)(rm|rmdir|unlink)'
      run '(^|[^A-Za-z0-9_$])(exec|execSync|spawn|spawnSync|execFile|execFileSync)')
    ;;
  rb)
    # The receiver is part of each alternative, so the longest name at the
    # leftmost match wins: `FileUtils.rm_rf`, never `FileUtils.rm`.
    ix_re=(del '(^|[^A-Za-z0-9_])((FileUtils\.)?(rm_rf|rm_r|rmtree|remove_dir|remove_entry|remove_entry_secure)|FileUtils\.(rm|rm_f|remove|rmdir|remove_file|safe_unlink)|(File|Dir)\.(delete|unlink|rmdir))'
      run '(^|[^A-Za-z0-9_])(system|exec|spawn|popen|popen2|popen2e|popen3|capture2|capture2e|capture3)')
    ;;
  *)
    ix_re=(del '(^|[^A-Za-z0-9_$@%>])(rmtree|remove_tree|unlink|rmdir)'
      run '(^|[^A-Za-z0-9_$@%>])(system|exec)')
    ;;
  esac
  for ((ix_ri = 0; ix_ri < ${#ix_re[@]}; ix_ri += 2)); do
    rdt_ix_calls "${ix_re[ix_ri]}" "${ix_re[ix_ri + 1]}"
  done
  # A comment rdt_ix_lex dropped after a `/` on its line may be a regex
  # literal's text (`/\//`, `/#/`), and the code after it is then unread: one
  # that names a deleter or a runner is refused. So is one holding a ruby or
  # perl backtick, a ruby %x or a perl qx, each of which runs a shell command
  # no name regex sees.
  if [[ -n "$ix_cm" ]]; then
    for ((ix_ri = 1; ix_ri < ${#ix_re[@]}; ix_ri += 2)); do
      if [[ "$ix_cm" =~ ${ix_re[ix_ri]} ]]; then
        rdt_ix_unplaceable "${BASH_REMATCH[2]}" "a call after a comment character that may sit in a regex literal, to"
        break
      fi
    done
    case "$lang" in
    rb) ix_ri='(`)|(%x)([^A-Za-z0-9]|$)' ;;
    pl) ix_ri='(`)|(^|[^A-Za-z0-9_$@%>])(qx)([^A-Za-z0-9_]|$)' ;;
    *) ix_ri="" ;;
    esac
    if [[ -n "$ix_ri" && "$ix_cm" =~ $ix_ri ]]; then
      if [[ -n "${BASH_REMATCH[1]}" ]]; then
        ix_ri='`'
      elif [[ "$lang" == rb ]]; then
        ix_ri='%x'
      else
        ix_ri='qx'
      fi
      rdt_ix_unplaceable "$ix_ri" "a shell command after a comment character that may sit in a regex literal, run by"
    fi
  fi
  for ((k = 0; k < ${#ix_k[@]}; k++)); do
    case "${ix_k[k]}" in
    c) rdt_ix_shell "${ix_v[k]}" ;;
    d) rdt_ix_unplaceable $'\001'"d$k"$'\002' "the command given as" ;;
    *) ;;
    esac
  done
  return 0
}

# rdt_ix_lex <code>: <code> masked into ix_m, comments dropped and each string
# literal replaced by a placeholder whose value goes to ix_v and kind to ix_k
# (rdt_ix_code's, through bash's dynamic scope). A kind is s, a plain literal;
# x, one with an interpolation or an escape this reading does not decode; or
# c, a command the language runs through a shell. Read: python quotes with
# their prefixes and triple quotes; node quotes and template literals; perl
# and ruby quotes and backticks, perl q, qq, qw and qx, and ruby percent
# literals opened by a bracket. Comments: `#` (a perl `$#` aside), and node's
# `//` and `/* */`. A node, perl or ruby comment opened after a `/` on its
# line may be a regex literal's text, so its text also goes to ix_cm.
# shellcheck disable=SC2329  # invoked from rdt_ix_code
rdt_ix_lex() {
  local r="$1" out="" ch re pfx raw kind mode ip tq cl apos="'" dq='"' bt='`' ce='*/'
  local re_pct='^([xqQwWiI]?)([([{<])' re_q='^([qwx]?)([([{</|!~])'
  r="${r//$'\001'/}"
  r="${r//$'\002'/}"
  case "$lang" in
  py) re="^([^${dq}${apos}#]*)([${dq}${apos}#])" ;;
  js) re="^([^${dq}${apos}${bt}/]*)([${dq}${apos}${bt}/])" ;;
  rb) re="^([^${dq}${apos}${bt}#%]*)([${dq}${apos}${bt}#%])" ;;
  *) re="^([^${dq}${apos}${bt}#q]*)([${dq}${apos}${bt}#q])" ;;
  esac
  while [[ "$r" =~ $re ]]; do
    # Each step re-slices the rest of the code, so a program of many literals
    # is slow on Git Bash: past this arm's deadline the guard refuses.
    rdt_deadline
    out+="${BASH_REMATCH[1]}"
    ch="${BASH_REMATCH[2]}"
    r="${r:${#BASH_REMATCH[0]}}"
    kind=s mode=2 ip=n raw="" cl="$ch"
    case "$ch" in
    '#')
      if [[ "$lang" == pl && "$out" == *'$' ]]; then
        out+='#'
        continue
      fi
      [[ "$lang" != py && "${out##*$'\n'}" == */* ]] && ix_cm+="${r%%$'\n'*}"$'\n'
      if [[ "$r" == *$'\n'* ]]; then r="${r#*$'\n'}"; else r=""; fi
      out+=$'\n'
      continue
      ;;
    /)
      if [[ "$r" == /* ]]; then
        [[ "${out##*$'\n'}" == */* ]] && ix_cm+="${r%%$'\n'*}"$'\n'
        if [[ "$r" == *$'\n'* ]]; then r="${r#*$'\n'}"; else r=""; fi
        out+=$'\n'
      elif [[ "$r" == '*'* ]]; then
        r="${r:1}"
        [[ "${out##*$'\n'}" == */* ]] && ix_cm+="${r%%"$ce"*}"$'\n'
        if [[ "$r" == *"$ce"* ]]; then r="${r#*"$ce"}"; else r=""; fi
        out+=' '
      else
        out+=/
      fi
      continue
      ;;
    %)
      if ! [[ "$r" =~ $re_pct ]]; then
        out+=%
        continue
      fi
      pfx="${BASH_REMATCH[1]}"
      cl="${BASH_REMATCH[2]}"
      r="${r:${#BASH_REMATCH[0]}}"
      case "$pfx" in
      x) kind=c ip=h ;;
      q) mode=1 ;;
      Q | '') ip=h ;;
      *) kind=x ;;
      esac
      ;;
    q)
      if [[ -n "$out" && "${out: -1}" == [A-Za-z0-9_\$@%\&\>:] ]] || ! [[ "$r" =~ $re_q ]]; then # portability-ok: a bash pattern bracket holding an escaped >, not a GNU grep word boundary
        out+=q
        continue
      fi
      pfx="${BASH_REMATCH[1]}"
      cl="${BASH_REMATCH[2]}"
      r="${r:${#BASH_REMATCH[0]}}"
      case "$pfx" in
      x) kind=c ip=p ;;
      '') mode=1 ;;
      q) ip=p ;;
      *) kind=x ;;
      esac
      ;;
    *)
      case "$lang:$ch" in
      py:*)
        tq="${out: -3}"
        ((${#out} < 3)) && tq="$out"
        if [[ "$tq" =~ (^|[^A-Za-z0-9_])([rRbBuUfF]{1,2})$ ]]; then
          pfx="${BASH_REMATCH[2]}"
          out="${out%"$pfx"}"
          [[ "$pfx" == *[rR]* ]] && mode=r
          [[ "$pfx" == *[fF]* ]] && ip=f
        fi
        if [[ "$r" == "$ch$ch"* ]]; then
          r="${r:2}"
          tq="$ch$ch$ch"
          raw="${r%%"$tq"*}"
          if [[ "$raw" == "$r" ]]; then r=""; else r="${r:${#raw}+3}"; fi
          cl=""
        fi
        ;;
      js:"$bt") ip=t ;;
      rb:"$apos" | pl:"$apos") mode=1 ;;
      rb:"$bt") kind=c ip=h ;;
      pl:"$bt") kind=c ip=p ;;
      rb:*) ip=h ;;
      pl:*) ip=p ;;
      *) ;;
      esac
      ;;
    esac
    case "$cl" in
    '(') cl=')' ;;
    '[') cl=']' ;;
    '{') cl='}' ;;
    '<') cl='>' ;;
    *) ;;
    esac
    if [[ -n "$cl" ]]; then
      rdt_ix_until "$cl"
      raw="$RDT_IX_S"
    fi
    rdt_ix_decode "$mode" "$ip" "$raw"
    case "$kind:$RDT_IX_DK" in
    s:*) kind="$RDT_IX_DK" ;;
    c:u) kind=d ;;
    *) ;;
    esac
    out+=$'\001'"$kind${#ix_v[@]}"$'\002'
    ix_v+=("$RDT_IX_DV")
    ix_k+=("$kind")
  done
  ix_m="$out$r"
}

# rdt_ix_until <close>: consume r (rdt_ix_lex's) through the first <close> no
# backslash escapes, keeping the text before it, escapes and all, in
# RDT_IX_S. With no such <close>, all of r.
# shellcheck disable=SC1003,SC2329  # '\' is a literal backslash; invoked from rdt_ix_lex
rdt_ix_until() {
  local seg esc bs='\'
  RDT_IX_S=""
  while [[ -n "$r" ]]; do
    # The text before the first <close> or the first backslash, whichever
    # comes first, each found with a quoted, so literal, pattern.
    seg="${r%%"$1"*}"
    esc="${r%%"$bs"*}"
    ((${#esc} < ${#seg})) && seg="$esc"
    RDT_IX_S+="$seg"
    r="${r:${#seg}}"
    [[ -n "$r" ]] || return 0
    if [[ "$r" == "$bs"* ]]; then
      RDT_IX_S+="${r:0:2}"
      r="${r:2}"
    else
      r="${r:1}"
      return 0
    fi
  done
  return 0
}

# rdt_ix_decode <mode> <interpolation> <raw body>: a literal's value into
# RDT_IX_DV and its kind, s, x or u, into RDT_IX_DK. Mode r is raw (a python
# r prefix), 1 the single-quote rules (only \\ and an escaped quote), 2 the
# rest, which decodes \\, \', \", \`, \/, \t, \n, \r and a line continuation;
# any other escape leaves the value unreadable (u). An interpolation (python
# f'{...}', node `${...}`, ruby #{...}, #@ and #$, perl $ and @) makes a
# readable value x, spelled as a shell `${` or `$`, so a shell reading of the
# value meets an expansion.
# shellcheck disable=SC1003,SC2016,SC2329  # literal text and backslash; invoked from rdt_ix_lex
rdt_ix_decode() {
  local v="$3" bs='\' apos="'" dq='"' bt='`' sl='/' dl='$' ob='{' hs='#' k=s
  case "$1" in
  r) ;;
  1)
    v="${v//"$bs$bs"/$'\001'}"
    v="${v//"$bs$apos"/"$apos"}"
    v="${v//$'\001'/"$bs"}"
    ;;
  *)
    v="${v//"$bs$bs"/$'\001'}"
    v="${v//"$bs$apos"/"$apos"}"
    v="${v//"$bs$dq"/"$dq"}"
    v="${v//"$bs$bt"/"$bt"}"
    v="${v//"$bs$sl"/"$sl"}"
    v="${v//"$bs"$'\n'/}"
    v="${v//"${bs}t"/$'\t'}"
    v="${v//"${bs}n"/$'\n'}"
    v="${v//"${bs}r"/$'\r'}"
    [[ "$v" == *"$bs"* ]] && k=u
    v="${v//$'\001'/"$bs"}"
    ;;
  esac
  case "$2" in
  f)
    if [[ "$v" == *"$ob"* ]]; then
      [[ "$k" == u ]] || k=x
      v="${v//"$ob"/"$dl$ob"}"
    fi
    ;;
  t) [[ "$v" == *"$dl$ob"* && "$k" != u ]] && k=x ;;
  h)
    if [[ "$v" == *"$hs$ob"* || "$v" == *"$hs@"* || "$v" == *"$hs$dl"* ]]; then
      [[ "$k" == u ]] || k=x
      v="${v//"$hs$ob"/"$dl$ob"}"
      v="${v//"$hs@"/"$dl"}"
      v="${v//"$hs$dl"/"$dl"}"
    fi
    ;;
  p)
    if [[ "$v" == *[\$@]* ]]; then
      [[ "$k" == u ]] || k=x
      v="${v//@/"$dl"}"
    fi
    ;;
  *) ;;
  esac
  RDT_IX_DV="$v"
  RDT_IX_DK="$k"
}

# rdt_ix_calls <del|run> <regex>: each call ix_m makes to a name <regex>
# matches as its second group, its arguments in parentheses or, for perl and
# ruby, after a blank with none. A deleter's arguments go to rdt_ix_del, a
# runner's to rdt_ix_run. A perl unlink or rmdir given no argument (bare, or
# only a statement modifier) deletes `$_`, which is refused.
# shellcheck disable=SC2016,SC2329  # `$_` is literal text; invoked from rdt_ix_code
rdt_ix_calls() {
  local re="$2" m="$ix_m" name t pl imp
  local re_open='^[[:space:]]*\(' re_bare='^[[:blank:]]+[^][:space:]=,.;)}|&?+*/<>!~{-]'
  local re_end=$'^[[:blank:]]*([;}\n]|$)'
  local -a cargs=()
  while [[ "$m" =~ $re ]]; do
    rdt_deadline
    name="${BASH_REMATCH[2]}"
    m="${m#*"${BASH_REMATCH[0]}"}"
    imp=0
    [[ "$lang:$1:$name" == pl:del:unlink || "$lang:$1:$name" == pl:del:rmdir ]] && imp=1
    if [[ "$m" =~ $re_open ]]; then
      t="${m#*"("}"
      pl=0
    elif [[ "$lang" == rb || "$lang" == pl ]] && [[ "$m" =~ $re_bare ]]; then
      t="$m"
      pl=1
    elif ((imp)) && [[ "$m" =~ $re_end ]]; then
      t=""
      pl=1
    else
      continue
    fi
    rdt_ix_split "$t" "$pl"
    cargs=(${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"})
    if ((imp && ${#cargs[@]} == 0)); then
      rdt_ix_unplaceable '$_'
    elif [[ "$1" == del ]]; then
      rdt_ix_del ${cargs[@]+"${cargs[@]}"}
    else
      rdt_ix_run "$name" ${cargs[@]+"${cargs[@]}"}
    fi
  done
  return 0
}

# rdt_ix_split <masked text> <paren-less>: a call's arguments, read from just
# after its `(` (or its name, paren-less), split at the commas outside
# brackets, trimmed, empty ones dropped, into RDT_IX_ARGS. The list ends at
# the bracket that closes it; a paren-less one also at a `;`, a newline, `&&`,
# `||` or a statement modifier (if, unless, or, and, while, until, for,
# foreach, do).
# shellcheck disable=SC2329  # invoked from rdt_ix_calls
rdt_ix_split() {
  local r="$1" pl="$2" d=0 argbuf="" ch re a kw
  local -a pieces=()
  if ((pl)); then re=$'^([^][(){},;\n]*)([][(){},;\n])'; else re='^([^][(){},]*)([][(){},])'; fi
  while [[ "$r" =~ $re ]]; do
    argbuf+="${BASH_REMATCH[1]}"
    ch="${BASH_REMATCH[2]}"
    r="${r:${#BASH_REMATCH[0]}}"
    case "$ch" in
    '(' | '[' | '{')
      d=$((d + 1))
      argbuf+="$ch"
      ;;
    ',')
      if ((d)); then
        argbuf+="$ch"
      else
        pieces+=("$argbuf")
        argbuf=""
      fi
      ;;
    *)
      if ((d == 0)); then
        r=""
        break
      fi
      if [[ "$ch" != ';' && "$ch" != $'\n' ]]; then d=$((d - 1)); fi
      argbuf+="$ch"
      ;;
    esac
  done
  pieces+=("$argbuf$r")
  RDT_IX_ARGS=()
  for a in "${pieces[@]}"; do
    a="${a#"${a%%[![:space:]]*}"}"
    if ((pl)); then
      a="${a%%&&*}"
      a="${a%%||*}"
      for kw in 'if' 'unless' 'or' 'and' 'while' 'until' 'for' 'foreach' 'do'; do
        [[ "$a" == "$kw" || "$a" == "$kw"[[:blank:]]* ]] && a=""
        a="${a%%[[:blank:]]"$kw"[[:blank:]]*}"
        a="${a%[[:blank:]]"$kw"}"
      done
    fi
    a="${a%"${a##*[![:space:]]}"}"
    [[ -n "$a" ]] && RDT_IX_ARGS+=("$a")
  done
  return 0
}

# rdt_ix_del <argument>...: a deleter's path arguments, each through
# rdt_ix_target: python's and node's first, and every ruby and perl one but a
# ruby keyword or hash option, a perl options hashref written last
# (`{...}`, `\%opts`) and a bare number.
# shellcheck disable=SC2329  # invoked from rdt_ix_calls
rdt_ix_del() {
  local a k=0
  for a in "$@"; do
    k=$((k + 1))
    case "$lang" in
    py | js) ((k > 1)) && break ;;
    rb) [[ "$a" =~ $RDT_IX_KWARG_RE ]] && continue ;;
    *)
      [[ "$a" =~ ^[0-9]+$ ]] && continue
      ((k == $#)) && [[ "$a" == '{'*'}' || "$a" =~ ^\\%[A-Za-z_][A-Za-z0-9_]*$ ]] && continue
      ;;
    esac
    rdt_ix_target "$a"
  done
  return 0
}

# rdt_ix_target <argument>: one path argument. A plain string literal is
# judged by rdt_ix_path, and so is each one in a [...] list; anything else
# names a path this guard cannot read, and is refused.
# shellcheck disable=SC2329  # invoked from rdt_ix_del
rdt_ix_target() {
  local e
  local -a el=()
  if [[ "$1" =~ $RDT_IX_PH_RE ]]; then
    if [[ "${BASH_REMATCH[1]}" == s ]]; then
      rdt_ix_path "${ix_v[BASH_REMATCH[2]]}"
    else
      rdt_ix_unplaceable "$1"
    fi
    return 0
  fi
  if [[ "$1" == '['*']' ]]; then
    rdt_ix_split "${1:1:${#1}-2}" 0
    el=(${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"})
    for e in ${el[@]+"${el[@]}"}; do
      if [[ "$e" =~ $RDT_IX_PH_RE ]] && [[ "${BASH_REMATCH[1]}" == s ]]; then
        rdt_ix_path "${ix_v[BASH_REMATCH[2]]}"
      else
        rdt_ix_unplaceable "$e"
      fi
    done
    return 0
  fi
  rdt_ix_unplaceable "$1"
}

# rdt_ix_path <value>: a literal path a deleter is given, judged as an
# operand of a recursive rm that no shell expands (provenance 3). A `$` or a
# backtick in it may be an expansion the shell made of the code before the
# interpreter ran, so the value is refused, unless it is a leading $HOME or
# ${HOME} with a plain path after it, judged as the shell expands it.
# shellcheck disable=SC2016,SC2329  # literal text; invoked from rdt_ix_target
rdt_ix_path() {
  local v="$1" h
  case "$v" in
  *'$'* | *'`'*)
    h="${v#\$HOME}"
    [[ "$h" == "$v" ]] && h="${v#\$\{HOME\}}"
    if [[ "$h" != "$v" && (-z "$h" || "$h" == /*) && "$h" != *[\$\`]* ]]; then
      rdt_delete_operand "$v" 2
    else
      rdt_ix_unplaceable "'$v'"
    fi
    ;;
  *) rdt_delete_operand "$v" 3 ;;
  esac
}

# rdt_ix_unplaceable <masked text> [<what>]: refuse an argument this guard
# cannot read, a deleter's path unless <what> says otherwise, named with each
# literal put back in quotes.
# shellcheck disable=SC2329  # invoked from rdt_ix_target, rdt_ix_path, rdt_ix_code and rdt_ix_run
rdt_ix_unplaceable() {
  local s="$1" what="${2:-the path given as}" apos="'"
  while [[ "$s" =~ $RDT_IX_PH_ANY ]]; do
    s="${s/"${BASH_REMATCH[0]}"/"$apos${ix_v[BASH_REMATCH[2]]}$apos"}"
  done
  ((${#s} > 120)) && s="${s:0:120}..."
  rdt_block "interp-unplaceable" "$what $s"
}

# rdt_ix_run <name> <argument>...: a call that runs a command. A literal is
# judged as the text a shell runs, and a [...] list as the argv a program is
# handed; node's spawn and execFile take the program, then a list of its
# arguments, and a ruby or perl call with several arguments hands them over as
# the argv. A word built from anything but a literal is RDT_IX_HOLE, and a
# command given no literal at all is not read. A ruby environment hash ahead
# of the command and ruby keyword options are dropped first.
# shellcheck disable=SC2329  # invoked from rdt_ix_calls
rdt_ix_run() {
  local name="$1" a w rc
  shift
  local -a ra=() argv=()
  for a in "$@"; do
    if [[ "$lang" == rb ]]; then
      [[ "$a" == '{'*'}' && ${#ra[@]} -eq 0 ]] && continue
      [[ "$a" =~ $RDT_IX_KWARG_RE ]] && continue
    fi
    ra+=("$a")
  done
  ((${#ra[@]})) || return 0
  case "$lang:$name" in
  js:spawn* | js:execFile*)
    rc=0
    rdt_ix_word_to w "${ra[0]}" || rc=$?
    if ((rc == 2)); then
      rdt_ix_unplaceable "${ra[0]}" "the command given as"
      return 0
    fi
    ((rc == 0)) || return 0
    rdt_ix_shell "$w"
    argv=("$w")
    if ((${#ra[@]} > 1)) && [[ "${ra[1]}" == '['*']' ]]; then
      rdt_ix_list "${ra[1]}"
      argv+=(${RDT_IX_L[@]+"${RDT_IX_L[@]}"})
    fi
    rdt_ix_argv "${argv[@]}"
    return 0
    ;;
  rb:* | pl:*)
    if ((${#ra[@]} > 1)); then
      for a in "${ra[@]}"; do
        if rdt_ix_word_to w "$a"; then
          argv+=("$w")
        elif [[ "$a" == '['*']' ]]; then
          rdt_ix_list "$a"
          argv+=(${RDT_IX_L[@]+"${RDT_IX_L[@]}"})
        else
          argv+=("$RDT_IX_HOLE")
        fi
      done
      rdt_ix_argv "${argv[@]}"
      return 0
    fi
    ;;
  *) ;;
  esac
  a="${ra[0]}"
  rc=0
  rdt_ix_word_to w "$a" || rc=$?
  if ((rc == 0)); then
    rdt_ix_shell "$w"
  elif ((rc == 2)); then
    rdt_ix_unplaceable "$a" "the command given as"
  elif [[ "$a" == '['*']' ]]; then
    rdt_ix_list "$a"
    rdt_ix_argv ${RDT_IX_L[@]+"${RDT_IX_L[@]}"}
  fi
  return 0
}

# rdt_ix_word_to <var> <argument>: the value of an argument that is one
# readable literal, into <var>. Returns 2 for one literal this reading cannot
# decode (kind u or d), 1 for anything else.
# shellcheck disable=SC2329  # invoked from rdt_ix_run and rdt_ix_list
rdt_ix_word_to() {
  [[ "$2" =~ $RDT_IX_PH_RE ]] || return 1
  [[ "${BASH_REMATCH[1]}" == [ud] ]] && return 2
  printf -v "$1" '%s' "${ix_v[BASH_REMATCH[2]]}"
}

# rdt_ix_list <[...] argument>: its elements as argv words into RDT_IX_L, a
# literal as its value and anything else as RDT_IX_HOLE.
# shellcheck disable=SC2329  # invoked from rdt_ix_run
rdt_ix_list() {
  local e w
  local -a el=()
  rdt_ix_split "${1:1:${#1}-2}" 0
  el=(${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"})
  RDT_IX_L=()
  for e in ${el[@]+"${el[@]}"}; do
    if rdt_ix_word_to w "$e"; then RDT_IX_L+=("$w"); else RDT_IX_L+=("$RDT_IX_HOLE"); fi
  done
}

# rdt_ix_argv <word>...: judge an argv a program is handed directly, as a
# command whose every word is quoted and which has no redirection.
# shellcheck disable=SC2329  # invoked from rdt_ix_run
rdt_ix_argv() {
  (($#)) || return 0
  local k
  local -a q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"}) op=(${HOOK_SEG_REDIR_OP[@]+"${HOOK_SEG_REDIR_OP[@]}"})
  HOOK_SEG_WORD_QUOTED=()
  for ((k = 0; k < $#; k++)); do HOOK_SEG_WORD_QUOTED+=(2); done
  HOOK_SEG_REDIR_OP=()
  rdt_check_segment "$@"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  HOOK_SEG_REDIR_OP=(${op[@]+"${op[@]}"})
}

# rdt_ix_shell <text>: judge the text a shell is handed to run, charged to the
# eval budget. Its stdin is not known.
# shellcheck disable=SC2329  # invoked from rdt_ix_code and rdt_ix_run
rdt_ix_shell() {
  local rdt_seg_feed=open
  rdt_scanned=$((rdt_scanned + ${#1}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_parse "$1"
}

# rdt_find_scan <index of the find word>: read one find into RDT_FIND_DEL (its
# expression deletes), RDT_FIND_OUT (it writes only the paths it finds: no
# -printf, -fprintf, -ls, -fls, -exec, -execdir, -ok, -okdir or -files0-from),
# and RDT_FIND_SW / RDT_FIND_SQ (each start point of either reading once, as a
# recursive rm is handed it, with its provenance). Reads words, n and
# HOOK_SEG_WORD_QUOTED from its caller through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_find_check and rdt_feed_class
rdt_find_scan() {
  local k w c key del=0 files0=0 gnu=0 follow=0
  local -a sw=() sq=()
  local -A seen=()
  RDT_FIND_OUT=1
  for ((k = $1 + 1; k < n; k++)); do
    case "${words[k]}" in
    -delete) del=1 ;;
    -files0-from) files0=1 RDT_FIND_OUT=0 ;;
    -printf | -fprintf | -ls | -fls) RDT_FIND_OUT=0 ;;
    -H | -L | -follow) follow=1 ;;
    -exec | -execdir | -ok | -okdir)
      RDT_FIND_OUT=0
      k=$((k + 1))
      c="${words[k]-}"
      c="${c##*/}"
      c="${c,,}"
      case "${c%.exe}" in
      rm | rmdir | unlink) del=1 ;;
      *) ;;
      esac
      # The action's command runs to its `;`, or to a `+` right after `{}`.
      while ((k < n)) && [[ "${words[k]}" != ';' ]] &&
        [[ "${words[k]}" != '+' || "${words[k - 1]}" != '{}' ]]; do
        k=$((k + 1))
      done
      ;;
    *) [[ "${words[k]}" =~ ^-[EHLPXdsx]*[HL] ]] && follow=1 ;;
    esac
  done
  RDT_FIND_DEL=$del

  # GNU: the leading options, then the start points; `.` when there is none,
  # unless -files0-from reads them from a file, which is left alone.
  k=$(($1 + 1))
  while ((k < n)); do
    case "${words[k]}" in
    -H | -L | -P | -O*) k=$((k + 1)) ;;
    -D) k=$((k + 2)) ;;
    --)
      k=$((k + 1))
      break
      ;;
    *) break ;;
    esac
  done
  while ((k < n)); do
    w="${words[k]}"
    [[ "$w" == -* || "$w" == '(' || "$w" == '!' ]] && break
    sw+=("$w")
    sq+=("${HOOK_SEG_WORD_QUOTED[k]:-0}")
    gnu=1
    k=$((k + 1))
  done
  if ((gnu == 0 && files0 == 0)); then
    sw+=(.)
    sq+=(0)
  fi

  # BSD: getopt clusters whose -f takes a start point, attached or as the next
  # word, then the start points.
  k=$(($1 + 1))
  while ((k < n)); do
    w="${words[k]}"
    if [[ "$w" == -- ]]; then
      k=$((k + 1))
      break
    elif [[ "$w" =~ ^-[EHLPXdsx]*f(.*)$ ]]; then
      if [[ -n "${BASH_REMATCH[1]}" ]]; then
        sw+=("${BASH_REMATCH[1]}")
        sq+=("${HOOK_SEG_WORD_QUOTED[k]:-0}")
        k=$((k + 1))
      else
        if ((k + 1 < n)); then
          sw+=("${words[k + 1]}")
          sq+=("${HOOK_SEG_WORD_QUOTED[k + 1]:-0}")
        fi
        k=$((k + 2))
      fi
    elif [[ "$w" =~ ^-[EHLPXdsx]+$ ]]; then
      k=$((k + 1))
    else
      break
    fi
  done
  while ((k < n)); do
    w="${words[k]}"
    [[ "$w" == -* || "$w" == '(' || "$w" == '!' ]] && break
    sw+=("$w")
    sq+=("${HOOK_SEG_WORD_QUOTED[k]:-0}")
    k=$((k + 1))
  done

  RDT_FIND_SW=()
  RDT_FIND_SQ=()
  for ((k = 0; k < ${#sw[@]}; k++)); do
    w="${sw[k]}"
    # Under -H, -L or -follow find follows a start point that is a symlink, so
    # it is judged by where the link points, as rm judges `link/`.
    ((follow)) && [[ -n "$w" && "$w" != */ ]] && w+=/
    key="${sq[k]}|$w"
    [[ -n "${seen[$key]+x}" ]] && continue
    seen[$key]=1
    RDT_FIND_SW+=("$w")
    RDT_FIND_SQ+=("${sq[k]}")
  done
  return 0
}

# --- Pipeline-fed deletes (PIPELINE-FED DELETES in the header) ----------------
#
# A FEED is where a command reads its items from: `none`, the shell's own stdin
# (the first command of the top-level parse); `open`, anything this guard
# cannot name; `f<offset>:<count>`, a confined find, whose start points sit at
# that offset in RDT_FW and RDT_FQ; and `g`, a confined git ls-files, whose
# entries are judged as RDT_LS_ENTRY under the directory it runs from.
RDT_FW=()
RDT_FQ=()
RDT_LS_ENTRY='(a file git ls-files lists)'
rdt_seg_feed=none
rdt_feed_in=none
rdt_prev=""
rdt_flat=1
rdt_deleter=0
# 1 while xargs or parallel runs the command being judged, which may append
# the items it reads after the words written (rdt_content_check).
rdt_fed=0

# rdt_parse <text>: judge each simple command of <text> through rdt_segment,
# with this parse's own pipe state: the feed of the command that runs it
# (rdt_feed_in) and what the command before the current one writes
# (rdt_prev). A text holding a `(`, `)` or backtick that no backslash escapes
# is read as no pipeline (rdt_flat 0), because the tokenizer splits a
# subshell, a substitution or a process substitution into commands that are
# not its stages. rdt_hd_n counts the heredoc openers the segments carried,
# and rdt_hd_lang maps the index of each heredoc an interpreter reads as its
# program to that interpreter's language, and rdt_hd_st to the state it is
# read in, judged once the parse has the bodies (rdt_ix_heredocs). The first
# command inherits the program text its parse is fed (rdt_text_feed), unless
# that text is a heredoc of another parse, whose index means nothing here.
rdt_parse() {
  local rdt_feed_in="$rdt_seg_feed" rdt_prev="" rdt_flat=1 b=$'\\' t="$1" rdt_hd_n=0
  local rdt_dec_prev="${rdt_dec_feed:-0}" rdt_sink=0 rdt_text_prev="${rdt_text_feed:-}"
  [[ "$rdt_text_prev" == h* ]] && rdt_text_prev=""
  local rdt_bq=$'(^|[;&|(\n])[[:space:]]*((then|do|else|elif|if|while|until|!|\\{)[[:space:]]+)*`'
  local -a rdt_hd_lang=() rdt_hd_st=()
  # The first command of a text another command feeds (a -c operand, eval)
  # reads that command's stdin, and a backtick where a command starts runs
  # its body's output as that command (DECODER SINKS).
  [[ "$1" =~ $rdt_bq ]] && rdt_sink=1
  if [[ "$t" == *"$b"* ]]; then
    t="${t//"$b$b"/}"
    t="${t//"$b("/}"
    t="${t//"$b)"/}"
  fi
  case "$t" in
  *[\(\)\`]*)
    rdt_flat=0
    rdt_feed_in=open
    ;;
  *) ;;
  esac
  hook::bash_parse_segments "$1" rdt_segment
  ((${#rdt_hd_lang[@]} == 0)) || rdt_ix_heredocs "$1"
  return 0
}

# rdt_segment <argv word>...: the parse callback. The tokenizer reports no
# operator between two commands, so the command before is read as a pipe into
# this one. In a parse another command feeds (a child shell, eval), a feed from
# the command before that differs from the parse's own is open, because after
# `;` or `&&` this command reads the parse's stdin instead. A redirection of
# fd 0 replaces the pipe. This command's own output is recorded for the next
# one before it is judged. rdt_hd_at is the parse-wide index of this
# command's first heredoc opener.
# shellcheck disable=SC2329  # invoked as the hook::bash_parse_segments callback
rdt_segment() {
  local rdt_seg_feed="$rdt_feed_in" j rdt_hd_at="$rdt_hd_n" rdt_dec_feed="$rdt_dec_prev" rdt_dec_out=0
  local rdt_text_feed="$rdt_text_prev" rdt_text_out=""
  if ((rdt_flat == 0)); then
    rdt_seg_feed=open
  elif [[ -n "$rdt_prev" ]]; then
    rdt_seg_feed="$rdt_prev"
    [[ "$rdt_feed_in" == none || "$rdt_feed_in" == "$rdt_prev" ]] || rdt_seg_feed=open
  fi
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    [[ "${HOOK_SEG_REDIR_OP[j]}" == '<<' || "${HOOK_SEG_REDIR_OP[j]}" == '<<-' ]] && rdt_hd_n=$((rdt_hd_n + 1))
    if [[ "${HOOK_SEG_REDIR_OP[j]}" == '<'* && "${HOOK_SEG_REDIR_FD[j]:-0}" == 0 ]]; then
      rdt_seg_feed=open
      rdt_dec_feed=0
      rdt_text_feed=""
    fi
  done
  # Read before rdt_check_segment, whose re-parse rebuilds HOOK_SEG_REDIR_*.
  rdt_dec_class "$@"
  ((rdt_dec_out && rdt_sink)) && rdt_block "decoder-sink"
  rdt_feed_class "$@"
  rdt_text_class "$@"
  rdt_check_segment "$@"
  rdt_dec_prev=$rdt_dec_out
  rdt_text_prev=$rdt_text_out
}

# rdt_text_class <argv word>...: rdt_text_out is the program text this command
# writes into a pipe, for a shell after it that reads its program from stdin
# (SHELLS AND LAUNCHERS FROM BASH in the header): `e` and the words an echo
# writes, whose backslash escapes a POSIX echo reads, `t` and what a printf
# writes when its format holds no conversion but %s, %b and %%, or what a cat
# with no operand writes from a here-string, `h`, the index of the heredoc
# that cat writes, `:` and its delimiter, or `x` for a printf whose output
# could pass MAX_COMMAND_LEN. Empty for any other command and for one whose
# stdout is redirected. Reads rdt_hd_at from rdt_segment.
# shellcheck disable=SC2329  # invoked from rdt_segment
rdt_text_class() {
  rdt_text_out=""
  case "${*,,}" in
  *echo* | *printf* | *cat*) ;;
  *) return 0 ;;
  esac
  local -a words=("$@")
  local n=$# i=0 b k w out nh=0 hd=0 r=-1
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  ((i < n)) || return 0
  b="${words[i]##*/}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  echo | printf | cat) ;;
  *) return 0 ;;
  esac
  for ((k = 0; k < ${#HOOK_SEG_REDIR_OP[@]}; k++)); do
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '>'* && "${HOOK_SEG_REDIR_FD[k]:-1}" == 1 ]] && return 0
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '<<' || "${HOOK_SEG_REDIR_OP[k]}" == '<<-' ]] && nh=$((nh + 1))
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '<'* && "${HOOK_SEG_REDIR_FD[k]:-0}" == 0 ]] || continue
    r=$k
    hd=$((nh - 1))
  done
  i=$((i + 1))
  case "$b" in
  echo)
    while ((i < n)) && [[ "${words[i]}" =~ ^-[neE]+$ ]]; do
      i=$((i + 1))
    done
    rdt_text_out="e${words[*]:i}"
    ;;
  printf)
    [[ "${words[i]-}" == -- ]] && i=$((i + 1))
    ((i < n)) || return 0
    w="${words[i]}"
    # `-v NAME` writes a variable, not stdout. A conversion other than %s and
    # %b (a width, a number, a time) is not emulated. The format repeats once
    # per argument at most, so past MAX_COMMAND_LEN the output is not built
    # and a shell reading it refuses (`x`).
    [[ "$w" == -* || "$w" =~ %[^sb%] || "$w" =~ %$ ]] && return 0
    if ((${#w} * (n - i) + ${#*} > MAX_COMMAND_LEN)); then
      rdt_text_out=x
      return 0
    fi
    # shellcheck disable=SC2059  # the command's own format, written out as that printf would
    printf -v out -- "$w" ${words[@]+"${words[@]:i+1}"} 2>/dev/null || return 0
    rdt_text_out="t$out"
    ;;
  *)
    for ((; i < n; i++)); do
      [[ "${words[i]}" == - ]] || return 0
    done
    ((r >= 0)) || return 0
    case "${HOOK_SEG_REDIR_OP[r]}" in
    '<<' | '<<-') [[ -n "${rdt_hd_at-}" ]] && rdt_text_out="h$((rdt_hd_at + hd)):${HOOK_SEG_REDIR_TARGET[r]-}" ;;
    '<<<') rdt_text_out="t${HOOK_SEG_REDIR_TARGET[r]-}" ;;
    *) ;;
    esac
    ;;
  esac
  return 0
}

# rdt_dec_class <argv word>...: rdt_dec_out is 1 when the command writes
# decoded text to its stdout (DECODER SINKS): base64, base32 or basenc with
# -d, -D or a prefix of --decode, or xxd with -r, given no output file (-o or
# --output; xxd's second operand) and no redirection of stdout. Any other
# command but a pager (less, more, most) passes on what it reads
# (rdt_dec_feed), since a filter of decoded text is decoded text still.
# shellcheck disable=SC2329  # invoked from rdt_segment
rdt_dec_class() {
  # Most commands neither decode nor read decoded text: skip the copy below.
  if ((rdt_dec_feed == 0)); then
    case "${*,,}" in
    *base64* | *base32* | *basenc* | *xxd*) ;;
    *) return 0 ;;
    esac
  fi
  local -a words=("$@")
  local n=$# i=0 b k w c dec=0 ops=0
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  ((i < n)) || return 0
  for ((k = 0; k < ${#HOOK_SEG_REDIR_OP[@]}; k++)); do
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '>'* && "${HOOK_SEG_REDIR_FD[k]:-1}" == 1 ]] && return 0
  done
  b="${words[i]##*/}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  base64 | base32 | basenc)
    for ((k = i + 1; k < n; k++)); do
      w="${words[k]}"
      case "$w" in
      --) break ;;
      --d*) dec=1 ;;
      --o*) return 0 ;;
      --*) ;;
      -?*)
        for ((c = 1; c < ${#w}; c++)); do
          case "${w:c:1}" in
          [dD]) dec=1 ;;
          o) return 0 ;;
          [bw]) break ;;
          *) ;;
          esac
        done
        ;;
      *) ;;
      esac
    done
    ;;
  xxd)
    for ((k = i + 1; k < n; k++)); do
      w="${words[k]}"
      if ((ops == 0)) && [[ "$w" == -?* ]]; then
        case "$w" in
        -r*) dec=1 ;;
        -[cglosnR] | -cols | -groupsize | -len | -offset | -seek | -name) k=$((k + 1)) ;;
        *) ;;
        esac
      else
        ops=$((ops + 1))
        ((ops == 2)) && [[ "$w" != - ]] && return 0
      fi
    done
    ;;
  less | more | most) ;;
  *) dec="$rdt_dec_feed" ;;
  esac
  rdt_dec_out=$dec
  return 0
}

# rdt_feed_class <argv word>...: what this command writes to a pipe after it,
# into rdt_prev: a find whose output names only paths under its start points
# (rdt_find_scan), saved in RDT_FW and RDT_FQ; git ls-files with no git option
# before the subcommand and no --format (git takes an unambiguous prefix of a
# long option, and only --format starts with --f[o], the bracket keeping the
# spell-checker from reading the prefix as a word); a line filter passes on its
# own feed; anything else, a launcher in front included, is open.
# shellcheck disable=SC2329  # invoked from rdt_segment
rdt_feed_class() {
  rdt_prev=open
  ((rdt_flat)) || return 0
  local -a words=("$@")
  local n=$# i=0 base w
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  ((i < n)) || return 0
  base="${words[i]##*/}"
  base="${base,,}"
  base="${base%.exe}"
  case "$base" in
  find)
    rdt_find_scan "$i"
    ((RDT_FIND_OUT)) || return 0
    rdt_prev="f${#RDT_FW[@]}:${#RDT_FIND_SW[@]}"
    RDT_FW+=(${RDT_FIND_SW[@]+"${RDT_FIND_SW[@]}"})
    RDT_FQ+=(${RDT_FIND_SQ[@]+"${RDT_FIND_SQ[@]}"})
    ;;
  git)
    [[ "${words[i + 1]-}" == ls-files ]] || return 0
    for ((i = i + 2; i < n; i++)); do
      [[ "${words[i]}" == --f[o]* ]] && return 0
    done
    rdt_prev=g
    ;;
  *) rdt_line_filter "${words[@]:i}" && rdt_prev="$rdt_seg_feed" ;;
  esac
  return 0
}

# rdt_line_filter <argv word>...: true when the command passes on only whole
# lines of what it reads: grep, egrep or fgrep with flags from -vixwEFGPsqz,
# -e or -f, and one pattern when neither gave one; sort with flags from
# -bdfghiMnRrsuVz, -k or -t; uniq with flags from -diuz; head or tail with -n,
# -<count> or -z. Options come first and no operand follows, since an operand
# is a file it reads.
# shellcheck disable=SC2329  # invoked from rdt_feed_class
rdt_line_filter() {
  local c="${1##*/}" f="" a="" w k=2 e=0 max=0
  c="${c,,}"
  c="${c%.exe}"
  case "$c" in
  grep | egrep | fgrep) f=vixwEFGPsqz a=ef max=1 ;;
  sort) f=bdfghiMnRrsuVz a=kt ;;
  uniq) f=diuz ;;
  head | tail) f=z a=n ;;
  *) return 1 ;;
  esac
  while ((k <= $#)); do
    w="${!k}"
    if [[ "$w" == -- ]]; then
      k=$((k + 1))
      break
    elif [[ "$w" =~ ^-[$f]+$ ]]; then
      :
    elif [[ -n "$a" && "$w" =~ ^-[$f]*[$a](.*)$ ]]; then
      e=1
      [[ -n "${BASH_REMATCH[1]}" ]] || k=$((k + 1))
    elif [[ "$c" == head || "$c" == tail ]] && [[ "$w" =~ ^-[0-9]+$ ]]; then
      :
    elif [[ "$w" == -* ]]; then
      return 1
    else
      break
    fi
    k=$((k + 1))
  done
  ((e)) && max=0
  (($# - k + 1 <= max))
}

# rdt_feed_judge <feed>: the targets a recursive delete takes from <feed>. A
# confined find's start points and a confined git ls-files' entry are judged
# as operands; any other feed is refused, because no target can be named.
# shellcheck disable=SC2329  # invoked from rdt_xargs_check and rdt_parallel_check
rdt_feed_judge() {
  local o l k
  case "$1" in
  f*:*)
    o="${1#f}"
    l="${o#*:}"
    o="${o%%:*}"
    for ((k = o; k < o + l; k++)); do
      rdt_delete_operand "${RDT_FW[k]}" "${RDT_FQ[k]}"
    done
    ;;
  g) rdt_delete_operand "$RDT_LS_ENTRY" 2 ;;
  *) rdt_block "pipeline-feed" ;;
  esac
  return 0
}

# rdt_xargs_check <index of the xargs word>: xargs runs its command on the
# items it reads, so when that command deletes recursively its feed is judged;
# -a or --arg-file reads them from a file, which is open. The options are GNU
# xargs' `+0a:E:e::i::I:l::L:n:oprs:txP:d:` and long options with BSD's -J, -R
# and -S, and both stop at the first operand, the command. An unknown or
# ambiguous option ends xargs before it runs anything. Reads words, n and
# HOOK_SEG_WORD_QUOTED from rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_xargs_check() {
  local k=$(($1 + 1)) c w x name hit src="$rdt_seg_feed" rdt_deleter=0 rdt_fed=1
  local -a q0=()
  while ((k < n)); do
    w="${words[k]}"
    case "$w" in
    --)
      k=$((k + 1))
      break
      ;;
    --?*)
      name="${w#--}"
      name="${name%%=*}"
      hit=""
      for x in arg-file delimiter max-args max-chars max-procs process-slot-var eof replace max-lines null open-tty interactive no-run-if-empty verbose show-limits exit version help; do
        if [[ "$x" == "$name" ]]; then
          hit="$x"
          break
        fi
        if [[ "$x" == "$name"* ]]; then
          [[ -z "$hit" ]] || return 0
          hit="$x"
        fi
      done
      [[ -n "$hit" ]] || return 0
      [[ "$hit" == arg-file ]] && src=open
      case "$hit" in
      arg-file | delimiter | max-args | max-chars | max-procs | process-slot-var)
        [[ "$w" == *=* ]] || k=$((k + 1))
        ;;
      *) ;;
      esac
      ;;
    -?*)
      for ((c = 1; c < ${#w}; c++)); do
        x="${w:c:1}"
        case "$x" in
        [0oprtx]) ;;
        [eil]) break ;;
        [adEIJLnPRSs])
          [[ "$x" == a ]] && src=open
          ((c + 1 < ${#w})) || k=$((k + 1))
          break
          ;;
        *) return 0 ;;
        esac
      done
      ;;
    *) break ;;
    esac
    k=$((k + 1))
  done
  ((k < n)) || return 0
  q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]:k}"})
  rdt_check_segment "${words[@]:k}"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  ((rdt_deleter)) && rdt_feed_judge "$src"
  return 0
}

# rdt_parallel_check <index of the parallel word>: GNU parallel runs its
# command line through a shell on each item, and with no command runs each item
# as a command. Its options are not modeled: each word an option may have taken
# as its argument is read as the first word of the command too, and from there
# to the first `:::`, `:::+`, `::::` or `::::+` the words are joined and parsed
# as shell text. When a reading deletes recursively its items are judged:
# `:::` items as operands, and items from a file (`::::`, an option starting -a
# or --a) or from the feed through rdt_feed_judge. Every `:::` item is also
# parsed as a command. Reads words, n and HOOK_SEG_WORD_QUOTED from
# rdt_check_segment through bash's dynamic scope.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_parallel_check() {
  local k j e=$n w pk=p text args=0 files=0 rdt_deleter=0 rdt_fed=1
  local -a starts=() q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  for ((k = $1 + 1; k < n; k++)); do
    case "${words[k]}" in
    ::: | :::+)
      ((k < e)) && e=$k
      args=1
      ;;
    :::: | ::::+)
      ((k < e)) && e=$k
      files=1
      ;;
    *) ;;
    esac
  done
  for ((k = $1 + 1; k < e; k++)); do
    w="${words[k]}"
    if [[ "$w" == -- ]]; then
      pk=p
    elif [[ "$w" == -?* ]]; then
      [[ "$w" == --a* || "$w" =~ ^-[^-]*a ]] && files=1
      pk=o
    else
      starts+=("$k")
      [[ "$pk" == o ]] || break
      pk=a
    fi
  done
  for k in ${starts[@]+"${starts[@]}"}; do
    text="${words[k]}"
    for ((j = k + 1; j < e; j++)); do
      text+=" ${words[j]}"
    done
    rdt_scanned=$((rdt_scanned + ${#text}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    rdt_parse "$text"
  done
  # A file source is open. Items given on the line replace stdin, which
  # parallel then reads only when a file source names `-`.
  if ((rdt_deleter)); then
    if ((files)); then
      rdt_feed_judge open
    elif ((args)); then
      for ((k = e + 1; k < n; k++)); do
        case "${words[k]}" in
        ::: | :::+) ;;
        *) rdt_delete_operand "${words[k]}" "${q0[k]:-0}" ;;
        esac
      done
    else
      rdt_feed_judge "$rdt_seg_feed"
    fi
  fi
  for ((k = e + 1; k < n; k++)); do
    case "${words[k],,}" in
    ::: | :::+ | :::: | ::::+) ;;
    *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
      *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) rdt_parse "${words[k]}" ;;
    *) ;;
    esac
  done
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# rdt_strip_tail_to <var> <word>: <word> without its trailing path segments
# that carry no name (empty, `*`, `.`, and anything else holding no letter,
# digit or underscore), cut only at a slash that sits outside every `${...}`.
# shellcheck disable=SC2329  # invoked from rdt_check_operand
rdt_strip_tail_to() {
  rdt_strip_nameless_to "$1" "$2" 1
}

# --- A variable the command itself sets to a literal --------------------------
#
# `S=/tmp/x; mkdir -p "$S/a"; rm -rf "$S"` deletes `/tmp/x`, so its operand is
# judged as `/tmp/x` through every arm below (`X=/ && rm -rf "$X"` is still a
# root). The binding is read only when the command, blanks trimmed, OPENS with
#   NAME=LITERAL SEP
# with SEP one `&&`, `;` or newline, so the assignment runs first, in this
# shell, every time; LITERAL is plain characters (RDT_LIT_CH), bare or wholly
# quoted, not led by `-`. Nothing after it may change NAME: the rest of the
# command holds no other `NAME=`, `NAME+=`, `NAME:=` or `NAME[`, and the command
# holds no word or syntax that can set a variable out of sight
# (RDT_LIT_FORBID_RE: a builtin that assigns by name, bash's or zsh's
# (`foreach`, `vared`, `print -v`, `zparseopts`, `integer`, ...), a function
# definition, arithmetic, a `{NAME}>` redirection). Every `$NAME` in the command is a whole
# double-quoted word, `"$NAME"` or `"$NAME/..."` with a plain suffix inside the
# quotes: an unquoted `$NAME` binds nothing, since an inherited IFS can split
# it, and neither does `${NAME}`. Those words aside, the rest of the command
# holds no quote, backslash, `$`, backtick, glob or brace character, so a
# builtin can only be spelled the way RDT_LIT_FORBID_RE reads it. NAME is no
# name the shell gives a meaning (RDT_LIT_SPECIAL_RE). Anything else binds
# nothing, and the variable blocks as a bare variable (#9779).
# rdt_check_operand substitutes the literal only in the top-level parse, never
# in a child shell's operand or a substitution body. Residual: a shell function
# or alias the session defined before this command could still set NAME.
RDT_LIT_CH='[A-Za-z0-9_.@%+,:/-]'
RDT_LIT_FORBID_RE='(^|[^A-Za-z0-9_])(declare|typeset|local|readonly|export|set|shopt|setopt|alias|trap|printf|read|mapfile|readarray|eval|source|function|IFS|unset|for|select|getopts|let|wait|coproc|enable|compgen|foreach|vared|zparseopts|zstat|stat|integer|float|private|print|sysread|sysopen|strftime|zstyle|zformat|zregexparse|zselect|getln|zmodload|autoload)([^A-Za-z0-9_]|$)|(^|[;&|({[:space:]])\.([[:space:]]|$)|\(\)|\$\{!|<<<|\(\(|\$\[|\{[A-Za-z_][A-Za-z0-9_]*\}[<>]'
RDT_LIT_SPECIAL_RE='^(_.*|.*PATH|.*path|BASH.*|ZSH.*|zsh.*|LC_.*|COMP.*|READLINE.*|HIST.*|hist.*|PROMPT.*|prompt|R?PS[0-9]|dis_.*|IFS|HOME|PWD|OLDPWD|ENV|SHELL|SHELLOPTS|SHLVL|POSIXLY_CORRECT|GLOBIGNORE|EXECIGNORE|FIGNORE|fignore|TMPDIR|TMPPREFIX|DIRSTACK|dirstack|FUNCNAME|FUNCNEST|GROUPS|UID|EUID|GID|EGID|PPID|RANDOM|SRANDOM|SECONDS|LINENO|EPOCHSECONDS|EPOCHREALTIME|epochtime|OPTARG|OPTIND|REPLY|reply|MAPFILE|mapfile|PIPESTATUS|pipestatus|status|argv|ARGC|ARGV0|ERRNO|errnos|signals|options|parameters|commands|functions|aliases|builtins|modules|history|historywords|jobstates|jobtexts|jobdirs|nameddirs|userdirs|funcstack|funcfiletrace|funcsourcetrace|functrace|match|mbegin|mend|MATCH|MBEGIN|MEND|psvar|watch|sysparams|langinfo|terminfo|termcap|widgets|keymaps|patchars|reswords|USERNAME|LOGNAME|TTY|HOST|HOSTNAME|NULLCMD|READNULLCMD|TRY_BLOCK_ERROR|TRY_BLOCK_INTERRUPT|WORDCHARS|ZDOTDIR|LANG|TERM|TMOUT)$'
RDT_LIT_NAME=""
RDT_LIT_VAL=""
rdt_lit_shape() {
  local c="$COMMAND" ch="$RDT_LIT_CH" lit n t re
  lit="(${ch}+|'${ch}+'|\"${ch}+\")"
  re="^([A-Za-z_][A-Za-z0-9_]*)=${lit}[[:blank:]]*(&&|;|"$'\n'")"
  c="${c#"${c%%[![:space:]]*}"}"
  c="${c%"${c##*[![:space:]]}"}"
  [[ "$TOOL_NAME" != "PowerShell" && ! "$c" =~ $RDT_LIT_FORBID_RE && "$c" =~ $re ]] || return 0
  n="${BASH_REMATCH[1]}"
  lit="${BASH_REMATCH[2]}"
  t="${c#"${BASH_REMATCH[0]}"}"
  [[ "$n" =~ $RDT_LIT_SPECIAL_RE ]] && return 0
  # The opening assignment is the only one.
  re="(^|[^A-Za-z0-9_])${n}(\\[|\\+?=|:=)"
  [[ "$t" =~ $re ]] && return 0
  # Every `$NAME` is a whole double-quoted word. Each one found is replaced by
  # a blank, keeping the characters around it, so a neighbor still matches.
  re="(^|[[:space:];&|(])\"\\\$${n}(/${ch}*)?\"([[:space:];&|)]|\$)"
  while [[ "$t" =~ $re ]]; do
    t="${t/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]} ${BASH_REMATCH[3]}"}"
  done
  # What is left reads as bash reads it: no quote, escape, expansion, glob or
  # brace that could spell a builtin RDT_LIT_FORBID_RE names some other way
  # (`pri''ntf`, `rea\d`, `${P}ntf`, `builtin pri?tf`) or write NAME inside an
  # array subscript or `[[ ]]`. A `$NAME` this loop did not take is caught too.
  [[ "$t" == *[\\\'\"\$\`*?[{}]* ]] && return 0
  [[ "$lit" == [\'\"]* ]] && lit="${lit:1:${#lit}-2}"
  # A value rm would read as an option is not a path.
  [[ "$lit" == -* ]] && return 0
  RDT_LIT_NAME="$n"
  RDT_LIT_VAL="$lit"
}
rdt_lit_shape

# rdt_check_operand <text> <provenance>: one operand through the root and
# bare-variable arms, then recorded BY VALUE for the outside-tree judgment at
# the end, with the directory-change state as it stands here.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_check_operand() {
  local w="$1" norm raw
  if [[ -n "$RDT_LIT_NAME" ]] && ((rdt_depth == 1 && rdt_in_subst == 0)); then
    case "$w" in
    "\$$RDT_LIT_NAME" | "\$$RDT_LIT_NAME"/*) w="$RDT_LIT_VAL${w#"\$$RDT_LIT_NAME"}" ;;
    *) ;;
    esac
  fi
  rdt_normalize_to norm "$w"
  if rdt_is_root "$norm"; then
    rdt_block "root-operand" "$norm"
  fi
  # The raw word too, before backslashes turn into slashes and slash runs
  # collapse, with its trailing nameless segments stripped OUTSIDE any `${...}`.
  rdt_strip_tail_to raw "${w,,}"
  if rdt_bare_var "$norm" || rdt_bare_var "$raw"; then
    rdt_block "bare-variable" "$w"
  fi
  if ((RDT_ARM)); then
    # A NUL byte in the payload cwd leaves nothing faithful to judge with.
    ((RDT_CWD_NUL)) && rdt_block "nul-field" "cwd"
    rdt_deadline
    RDT_P_TEXT+=("$w")
    RDT_P_Q+=("$2")
    RDT_P_NORIG+=("${#RDT_ORIGINS[@]}")
    RDT_P_UNK+=("$rdt_cd_unknown")
    RDT_P_REF+=("$rdt_cd_refuse")
    RDT_P_SUB+=("$rdt_in_subst")
    RDT_P_WT+=("$RDT_WTRM")
  fi
  return 0
}

# Brace bounds: MAX_BRACE results per operand, and a word over MAX_BRACE_WORD
# bytes or with more than MAX_BRACE_OPEN braces is refused before the walk.
MAX_BRACE=64
MAX_BRACE_WORD=4096
MAX_BRACE_OPEN=128
# One operand longer than PATH_MAX names no path, and one deeper than
# MAX_OPERAND_DEPTH components names none in real use; both are refused
# unscanned.
MAX_OPERAND_LEN=4096
MAX_OPERAND_DEPTH=128

# rdt_brace_expand <word>: the word's brace expansion into RDT_BX, the way
# bash performs it: the first `{...}` holding a top-level comma is expanded,
# each alternative spliced between the text before and after it, and the
# result expanded again, so nesting and `a{b,c}d` concatenation both work. A
# `{` that opens no such expression stays literal, and `${...}` is a parameter
# expansion, never a brace. Returns 2 for a sequence (`{1..3}`, `{a..c}`),
# which is refused rather than expanded, and past MAX_BRACE results.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_brace_expand() {
  RDT_BX=()
  rdt_brace_rec "$1"
}
# shellcheck disable=SC2329  # invoked from rdt_brace_expand and itself
rdt_brace_rec() {
  local s="$1" n=${#1} i=0 j d st c pre post
  local -a parts=()
  local re_seq='^(-?[0-9]+\.\.-?[0-9]+|[A-Za-z]\.\.[A-Za-z])(\.\.-?[0-9]+)?$'
  while ((i < n)); do
    c="${s:i:1}"
    if [[ "$c" == '$' && "${s:i+1:1}" == '{' ]]; then
      # Bash passes a `${...}` through whole, and finds its end by counting
      # every brace, bare ones included; one that never closes leaves the
      # rest of the word unexpanded.
      d=0
      for ((j = i + 1; j < n; j++)); do
        case "${s:j:1}" in
        '{') d=$((d + 1)) ;;
        '}')
          d=$((d - 1))
          ((d == 0)) && break
          ;;
        *) ;;
        esac
      done
      ((j < n)) || break
      i=$j
    elif [[ "$c" == '{' ]]; then
      rdt_deadline
      d=0
      parts=()
      st=$((i + 1))
      for ((j = i; j < n; j++)); do
        case "${s:j:1}" in
        '{') d=$((d + 1)) ;;
        '}')
          d=$((d - 1))
          if ((d == 0)); then
            parts+=("${s:st:j-st}")
            break
          fi
          ;;
        ,)
          if ((d == 1)); then
            parts+=("${s:st:j-st}")
            st=$((j + 1))
          fi
          ;;
        *) ;;
        esac
      done
      if ((j < n)); then
        if ((${#parts[@]} > 1)); then
          pre="${s:0:i}"
          post="${s:j+1}"
          for c in "${parts[@]}"; do
            rdt_brace_rec "$pre$c$post" || return 2
          done
          return 0
        fi
        [[ "${parts[0]}" =~ $re_seq ]] && return 2
      fi
    fi
    i=$((i + 1))
  done
  RDT_BX+=("$s")
  ((${#RDT_BX[@]} <= MAX_BRACE)) || return 2
  return 0
}

# rdt_scan_substitutions <text>: check the body of every command substitution.
#
# A substitution RUNS before the word it builds is used, so the shell executes
# the inner command whatever the outer one is: `echo "$(rm -rf /)"` deletes the
# root and then echoes nothing. The shared tokenizer keeps a substitution INSIDE
# the enclosing argv word, which is correct for its own purpose and means the
# segment callback only ever sees `echo`. So each body is lifted out here and
# parsed on its own, and the stack below covers a body that holds another.
#
# QUOTING IS HONORED, because the shell honors it. A `$(` inside a SINGLE-quoted
# span is inert (`echo '$(rm -rf /)'` prints the text and runs nothing), and so
# is a `\$(` inside a double-quoted one; reading the raw characters called both
# a substitution and refused a command that deletes nothing. The same machine
# locates the CLOSE: a `)` inside a quoted span is not the terminator, so
# `echo "$(printf '%s\n' ')'; rm -rf /)"` ends where bash ends it rather than at
# the quoted paren, which had been cutting the body off before the delete.
#
# ONE LINEAR PASS, not a descent. Parens are tracked on a stack, and a body is
# parsed when its own `)` pops it, so a substitution inside another is reached
# by the same walk that reached the outer one. Each entry remembers the quoting
# state it interrupted, because a substitution body starts a FRESH quoting
# context (`"$(echo "x")"` has two independent double-quoted spans). `$((` is
# arithmetic: its `$` is stepped over and its two parens ride the stack as
# ordinary ones, so its `))` balances them instead of closing a substitution.
#
# A HEREDOC BODY whose delimiter is quoted (`<<'EOF'`, `<<"EOF"`, `<<\EOF`,
# `<<-'EOF'`) gets no expansion from the shell that reads the command, but it
# is still the stdin of the command it feeds, and `bash <<'EOF'`, `cat <<'EOF' |
# sh` or `bash -c "$(cat <<'EOF' …)"` run it. So it is skipped (#6625) only
# where it is plainly data: the whole command is one `cat`,
# `gh pr|issue|api|release` or `git commit|tag -F -` line with no pipe, list
# operator, redirection, substitution or grouping (rdt_hd_plain,
# rdt_hd_reader), its opener at top
# level with a plain word in quotes, and nothing but the body after it. Every
# other body is scanned on its own, with bodies taken in
# the order their openers appear, as bash reads them. An opener is recognized
# only outside quotes and outside any ordinary paren or backtick body, so
# `$((1<<2))` stays arithmetic.
#
# The stack depth is capped, and past the cap the guard REFUSES; see
# MAX_SUBST_DEPTH. An unterminated substitution is parsed to end of text rather
# than dropped, so a payload that never closes still fails closed.

# rdt_scan_body <body>: tokenize one substitution body, under two budgets.
#
# A body whose TEXT holds none of the prefilter's words cannot carry a delete
# or a decoder sink the matcher recognizes, so it is not tokenized at all: the
# same reasoning as the prefilter in front of the whole guard.
#
# The rest are charged against ONE MAX_COMMAND_LEN budget, because the depth cap
# bounds the nesting and not the WORK. Nesting multiplies the text to tokenize,
# so a command at the 16 KB ceiling nested 32 deep is half a megabyte of
# tokenizing, and a hook the harness cancels on its own timeout is cancelled
# WITHOUT a block. Running past the budget would therefore fail OPEN on exactly
# the input built to reach it, so the budget REFUSES instead.
#
# The budget counts SUBSTITUTION BODIES ONLY, and starts at zero. Charging the
# command's own length against it as well refused any command past about half
# the ceiling that carried one ordinary substitution, while leaving a flat
# command just under the ceiling alone: a size limit on the wrong thing.
# SIBLING bodies cannot exhaust this budget, because each one's text sits in
# the command and the command has its own ceiling. NESTING can, because a
# nested body's text is charged once per level enclosing it, and nesting is the
# shape that made the scan slow enough to reach the harness timeout.
#
# A body is lifted out of the command it runs in, so its stdin is not known:
# its feed is open (PIPELINE-FED DELETES in the header).
rdt_scanned=0
rdt_scan_body() {
  local b="$1" rdt_seg_feed=open rdt_dec_feed=0 rdt_text_feed=""
  [[ -n "$b" ]] || return 0
  case "${b,,}" in
  *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
    *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) ;;
  *) return 0 ;;
  esac
  rdt_scanned=$((rdt_scanned + ${#b}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "bodies-too-long"
  rdt_parse "$b"
}

# rdt_hd_plain <text>: true when the text around a heredoc opener holds no
# character that could start another command, a pipe, a redirection, a
# substitution or a grouping, so the opener's command is the line's only one.
rdt_hd_plain() {
  case "$1" in
  *[\;\&\|\(\)\`\$\<\>]*) return 1 ;; # portability-ok: a bash case-pattern bracket of escaped operators, not a GNU grep word boundary
  *) return 0 ;;
  esac
}

# rdt_hd_reader <prefix>: true when the command ahead of a heredoc opener only
# reads its stdin as data: `cat`, a `gh` command that takes a body, or
# `git commit` or `git tag` with `-F -`. A shell, an interpreter, any other
# `git` word (an alias can be `!sh`), a git global option ahead of the
# subcommand, `tee` (it writes a file) and every launcher stay out. `commit`
# and `tag` are exempt because git ignores an alias that hides a built-in
# command (git-config(1), `alias.*`).
rdt_hd_reader() {
  local -a hr_words
  local -i j
  read -r -a hr_words <<<"$1"
  case "${hr_words[0]:-}" in
  cat) return 0 ;;
  gh)
    case "${hr_words[1]:-}" in
    pr | issue | api | release) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  git)
    # The words are split on blanks alone, so a quote or backslash could join
    # `-F -` into one argument; past `--` both are paths.
    [[ "$1" == *[\'\"\\]* ]] && return 1
    case "${hr_words[1]:-}" in
    commit | tag)
      for ((j = 2; j + 1 < ${#hr_words[@]}; j++)); do
        [[ "${hr_words[j]}" == -- ]] && return 1
        [[ "${hr_words[j]}" == -F && "${hr_words[j + 1]}" == - ]] && return 0
      done
      return 1
      ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
rdt_scan_substitutions() {
  local s="$1" q="" c nx
  # Each open paren rides the stack with its KIND: 0 an ordinary paren that
  # only balances, 1 a `$( )` substitution, 2 a backtick one. Only 1 and 2
  # carry a body to parse, and only they count toward the depth cap.
  local -i len=${#s} i=0 pd=0 sd=0 k st ansi=0 hok hs hq
  local -a st_start=() st_q=() st_kind=() hd_delim=() hd_strip=() hd_quoted=() hd_sfx=()
  local hd line lc body pre hfull nested="${2:-}"
  local hd_word_re="^('[A-Za-z0-9_]+'|\"[A-Za-z0-9_]+\"|\\\\[A-Za-z0-9_]+)$"
  local -i hstart hend hcmt=-1
  local -a hd_body=()
  while ((i < len)); do
    c="${s:i:1}"
    # The unquoted newline that ends a line with heredoc openers on it starts
    # their bodies. Each runs to a line that is exactly its delimiter (after
    # leading tabs, for `<<-`), or to the end of the text.
    if [[ -z "$q" && "$c" == $'\n' ]] && ((${#hd_delim[@]})); then
      for ((k = 0; k < ${#hd_delim[@]}; k++)); do
        hend=$i
        ((hcmt >= hd_sfx[k])) && hend=$hcmt
        rdt_hd_plain "${s:hd_sfx[k]:hend - hd_sfx[k]}" || hd_quoted[k]=0
      done
      i=$((i + 1))
      hd_body=()
      for ((k = 0; k < ${#hd_delim[@]}; k++)); do
        body=""
        while ((i < len)); do
          line="${s:i}"
          line="${line%%$'\n'*}"
          i=$((i + ${#line} + 1))
          lc="$line"
          if ((hd_strip[k])); then
            while [[ "$lc" == $'\t'* ]]; do lc="${lc#?}"; done
          fi
          [[ "$lc" == "${hd_delim[k]}" ]] && break
          body+="$line"$'\n'
        done
        hd_body+=("$body")
      done
      # Inert only when nothing follows the body: a later line could pipe it,
      # run what it wrote, or close a compound command around it.
      [[ "${s:i}" == *[![:space:]]* ]] && hd_quoted=()
      for ((k = 0; k < ${#hd_body[@]}; k++)); do
        ((${hd_quoted[k]:-0})) || rdt_scan_substitutions "${hd_body[k]}" nested
      done
      hd_delim=()
      hd_strip=()
      hd_quoted=()
      hd_sfx=()
      hcmt=-1
      continue
    fi
    # A heredoc opener `<<` or `<<-`, never the here-string `<<<`. The delimiter
    # is quoted when any part of it is quoted or backslashed, as in bash.
    if [[ -z "$q" && "$c" == '<' && "${s:i+1:1}" == '<' && "${s:i+2:1}" != '<' ]] &&
      { ((i == 0)) || [[ "${s:i-1:1}" != '<' ]]; }; then
      hok=1
      for ((k = 0; k < pd; k++)); do
        ((st_kind[k] == 1)) || {
          hok=0
          break
        }
      done
      if ((hok)); then
        hfull="${s:0:i}"
        pre="${hfull##*$'\n'}"
        i=$((i + 2))
        hs=0
        hq=0
        hd=""
        if [[ "${s:i:1}" == '-' ]]; then
          hs=1
          i=$((i + 1))
        fi
        while [[ "${s:i:1}" == ' ' || "${s:i:1}" == $'\t' ]]; do i=$((i + 1)); done
        hstart=$i
        while ((i < len)); do
          c="${s:i:1}"
          case "$c" in
          ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '<' | '>' | '(' | ')' | '`') break ;;
          "'" | '"')
            hq=1
            i=$((i + 1))
            while ((i < len)) && [[ "${s:i:1}" != "$c" ]]; do
              hd+="${s:i:1}"
              i=$((i + 1))
            done
            i=$((i + 1))
            ;;
          '\')
            hq=1
            hd+="${s:i+1:1}"
            i=$((i + 2))
            ;;
          *)
            hd+="$c"
            i=$((i + 1))
            ;;
          esac
        done
        # Only the first line of the whole command, at top level, handing the
        # body to a reader of data under a plain quoted word, makes it inert;
        # see rdt_hd_plain. A word with `$` or `\` inside quotes is one this
        # parser could end in the wrong place, so its body is scanned.
        if ! [[ -z "$nested" && hcmt -lt 0 && "$pre" == "$hfull" && "${s:hstart:i-hstart}" =~ $hd_word_re ]] ||
          ! { ((pd == 0)) && rdt_hd_plain "$pre" && rdt_hd_reader "$pre"; }; then
          hq=0
        fi
        hd_delim+=("$hd")
        hd_strip+=("$hs")
        hd_quoted+=("$hq")
        hd_sfx+=("$i")
        continue
      fi
    fi
    # A single-quoted span performs no expansion at all; only its own closing
    # quote ends it. `$'…'` is the one spelling where a backslash still escapes.
    if [[ "$q" == "'" ]]; then
      if ((ansi)) && [[ "$c" == '\' ]]; then
        i=$((i + 2))
        continue
      fi
      if [[ "$c" == "'" ]]; then
        q=""
        ansi=0
      fi
      i=$((i + 1))
      continue
    fi
    # Unquoted, a backslash escapes whatever follows. Inside double quotes it
    # escapes only the four characters bash lets it, and is literal otherwise.
    if [[ "$c" == '\' ]]; then
      if [[ "$q" == '"' ]]; then
        nx="${s:i+1:1}"
        case "$nx" in
        '"' | '$' | '`' | '\') i=$((i + 2)) ;;
        *) i=$((i + 1)) ;;
        esac
      else
        i=$((i + 2))
      fi
      continue
    fi
    # An unquoted `#` that starts a word starts a comment to the end of the
    # line: no heredoc opener after it is real, and the text after it cannot
    # pipe or redirect a body.
    if [[ -z "$q" ]]; then
      if [[ "$c" == '#' ]] && ((hcmt < 0)) &&
        { ((i == 0)) || [[ "${s:i-1:1}" == [[:space:]\;\&\|\(\)] ]]; }; then
        hcmt=$i
      elif [[ "$c" == $'\n' ]]; then
        hcmt=-1
      fi
    fi
    case "$c" in
    '"')
      if [[ "$q" == '"' ]]; then q=""; else q='"'; fi
      ;;
    "'")
      # Literal inside double quotes; an opener outside them.
      if [[ "$q" != '"' ]]; then
        q="'"
        ((i > 0)) && [[ "${s:i-1:1}" == '$' ]] && ansi=1
      fi
      ;;
    '$')
      if [[ "${s:i+1:1}" == '(' ]]; then
        if [[ "${s:i+2:1}" == '(' ]]; then
          i=$((i + 1))
          continue
        fi
        sd=$((sd + 1))
        ((sd > MAX_SUBST_DEPTH)) && rdt_block "nesting-too-deep"
        st_kind[pd]=1
        st_start[pd]=$((i + 2))
        st_q[pd]="$q"
        pd=$((pd + 1))
        q=""
        i=$((i + 2))
        continue
      fi
      ;;
    '(')
      # An ordinary paren (a subshell, one half of an arithmetic pair) only
      # balances, so its `)` cannot be mistaken for a substitution's.
      if [[ "$q" != '"' ]]; then
        st_kind[pd]=0
        st_start[pd]=-1
        st_q[pd]="$q"
        pd=$((pd + 1))
      fi
      ;;
    ')')
      # Inside a backtick body a stray `)` closes nothing, so it is left alone.
      if [[ "$q" != '"' ]] && ((pd > 0)) && ((st_kind[pd - 1] != 2)); then
        pd=$((pd - 1))
        q="${st_q[pd]}"
        if ((st_kind[pd] == 1)); then
          sd=$((sd - 1))
          st=${st_start[pd]}
          rdt_scan_body "${s:st:i - st}"
        fi
      fi
      ;;
    '`')
      # Backticks do not nest, so the top of the stack is either this one's
      # opener or something it encloses.
      if ((pd > 0)) && ((st_kind[pd - 1] == 2)); then
        pd=$((pd - 1))
        q="${st_q[pd]}"
        sd=$((sd - 1))
        st=${st_start[pd]}
        rdt_scan_body "${s:st:i - st}"
      else
        sd=$((sd + 1))
        ((sd > MAX_SUBST_DEPTH)) && rdt_block "nesting-too-deep"
        st_kind[pd]=2
        st_start[pd]=$((i + 1))
        st_q[pd]="$q"
        pd=$((pd + 1))
        q=""
      fi
      ;;
    *) ;;
    esac
    i=$((i + 1))
  done
  # A substitution that never closed is parsed to the end of the text: the
  # command would not run as written, but a guard that silently dropped it
  # would be answering a different question than the one it was asked.
  for ((k = 0; k < pd; k++)); do
    ((st_kind[k] == 0)) && continue
    st=${st_start[k]}
    rdt_scan_body "${s:st}"
  done
}

# --- PowerShell Remove-Item / rd /s (#4516) ---------------------------------
# Own tokenizer, not lib/powershell/ps-command.sh: that classifier spends a
# shared sink-attempt budget this guard must not touch. Backslash is literal;
# backtick is the escape. Parameters match on any unambiguous prefix of
# Remove-Item's names. cmd /c rd /s and rmdir /s are judged as cmd grammar.
# A pipeline into Remove-Item with no path judges what the stage before lists
# (#9765), and with -Recurse is refused when that stage is no listing: the
# target arrived through the pipe and cannot be named. So is a target that is a
# `( )`, `$( )` or `@( )` grouping: its value is not known. A statement ends
# at `;`, `|`, `&`, `&&`, `||` and an unquoted newline (LF, CR or CRLF, unless a
# backtick continues the line). An unquoted `(`, `$(` or `{` opens a nested
# level: what is inside is judged as statements of its own, and the closing `)`
# or `}` puts one placeholder word (`(` or `{`) back into the statement that
# was open, so the arguments after a grouping still belong to their command
# (`Remove-Item -Path (Join-Path $a b) -Recurse`). A `}` after an if, foreach,
# try, function or similar keyword also ends that statement. `${name}` is one
# variable word.

rdt_ps_piped=0
# The walker writes a literal `$` (single-quoted, or escaped by a backtick) as
# this byte, so rdt_ps_operand can tell it from one PowerShell expands: the
# first control byte the command does not carry (\001 is taken above; tab, LF
# and CR are skipped). Empty only when the command carries all of them; then
# rdt_ps_operand refuses any target holding a `$`, since a literal one cannot
# be told from an expansion.
RDT_PS_LIT=""
for rdt_b in $'\002' $'\003' $'\004' $'\005' $'\006' $'\007' $'\010' $'\013' \
  $'\014' $'\016' $'\017' $'\020' $'\021' $'\022' $'\023' $'\024' $'\025' \
  $'\026' $'\027' $'\030' $'\031' $'\032' $'\033' $'\034' $'\035' $'\036' $'\037'; do
  if [[ "$COMMAND" != *"$rdt_b"* ]]; then
    RDT_PS_LIT="$rdt_b"
    break
  fi
done
# 1 while a literal `$` reaches the command as written; 0 inside text that an
# expanding outer string handed to rdt_ps_nested, where `"... '$env:TEMP'"`
# expanded `$env:TEMP` before the inner single quotes were read. 0 throughout
# when the command holds a quoting form rdt_ps_walk does not read (a `<#` block
# comment, an `@"` or `@'` here-string, a byte outside ASCII, which may be a
# quote character, or a `$(` or `${` alongside a `"`, since a `$( ... )` inside
# a double-quoted string is a full script whose own quotes do not close the
# string, and a `${name}` inside one reads its name to the first `}`, past any
# `"`, while the walk closes the string at the next `"`): the walk can then be
# out of step with PowerShell's, and a `$` it marks literal may sit inside a
# string PowerShell expands.
rdt_ps_lit_kept=1
# shellcheck disable=SC2329  # invoked through hook::_c_locale
rdt_ps_quote_gap() {
  [[ "$COMMAND" == *'<#'* || "$COMMAND" == *'@"'* || "$COMMAND" == *"@'"* || "$COMMAND" == *[![:ascii:]]* ]] ||
    [[ ( "$COMMAND" == *\$\(* || "$COMMAND" == *\$\{* ) && "$COMMAND" == *'"'* ]]
}
hook::_c_locale rdt_ps_quote_gap && rdt_ps_lit_kept=0

# rdt_ps_param_to <var> <token>: canonical Remove-Item parameter name, empty
# when the token is not a unique prefix of one. Token includes the leading
# dash; a :value suffix is ignored for the name.
rdt_ps_param_to() {
  local __name="${2#-}"
  __name="${__name%%:*}"
  __name="${__name,,}"
  local __hit="" __hits=0 __p
  for __p in confirm credential debug erroraction errorvariable exclude filter \
    force include informationaction informationvariable literalpath outbuffer \
    outvariable pipelinevariable path recurse stream usetransaction verbose \
    warningaction warningvariable whatif; do
    if [[ "$__p" == "$__name" ]]; then
      printf -v "$1" '%s' "$__p"
      return 0
    fi
    if [[ -n "$__name" && "$__p" == "$__name"* ]]; then
      __hit="$__p"
      __hits=$((__hits + 1))
    fi
  done
  if ((__hits == 1)); then
    printf -v "$1" '%s' "$__hit"
  else
    printf -v "$1" '%s' ""
  fi
}

# rdt_ps_cmd_split_to <nameref> <text>: cmd.exe-ish whitespace split of one /c
# operand. Double quotes group; a backslash is literal; an empty quoted span
# is an empty word.
rdt_ps_cmd_split_to() {
  local -n __cs_out="$1"
  local __s="$2" __n=${#2} __i=0 __w="" __q=0 __in=0 __c
  __cs_out=()
  while ((__i < __n)); do
    __c="${__s:__i:1}"
    if ((__q)); then
      if [[ "$__c" == '"' ]]; then
        __q=0
      else
        __w+="$__c"
      fi
      __in=1
    else
      case "$__c" in
      '"')
        __q=1
        __in=1
        ;;
      [[:space:]])
        if ((__in)); then
          __cs_out+=("$__w")
          __w=""
          __in=0
        fi
        ;;
      *)
        __w+="$__c"
        __in=1
        ;;
      esac
    fi
    __i=$((__i + 1))
  done
  if ((__in)); then
    __cs_out+=("$__w")
  fi
}

# rdt_ps_operand <word>: one PowerShell / cmd target through the same root,
# empty, bare-variable and outside-tree arms as Bash. `$env:NAME` and
# `${env:NAME}` are read as `$NAME` and `${NAME}`, so each spelling gets the
# answer the Bash lane gives: `$env:TEMP`, `$env:TEMP\` and `$env:TEMP\*` are
# refused as bare variables, and `$env:TEMP\build` is not.
#
# A `$` the walker read as literal (single-quoted or backtick-escaped) arrives
# as RDT_PS_LIT (#6626). A word whose every `$` is literal is judged as the
# path it names (provenance 4), after a trailing Win32 stream suffix
# (`::$INDEX_ALLOCATION`, `:$I30:$INDEX_ALLOCATION`) is dropped, because that
# suffix names the file or directory before it. Such a word is read only that
# way, so `'$env:TEMP'` and `'$HOME\x'` name the paths they spell, unless an
# expanding outer string held it (rdt_ps_lit_kept is 0): then it is also judged
# with every `$` read as an expansion, since the outer string expanded them
# before the inner single quotes were read. A word holding any `$` PowerShell
# expands is read only as an expansion.
rdt_ps_operand() {
  local w="$1" lit="" re_stream
  [[ -z "$RDT_PS_LIT" && "$w" == *'$'* ]] && rdt_block "control-bytes" "$w"
  if [[ -n "$RDT_PS_LIT" && "$w" == *"$RDT_PS_LIT"* ]]; then
    if [[ "$w" != *'$'* ]]; then
      lit="$w"
      re_stream='^(.+):[^:/\\]*:'"$RDT_PS_LIT"'[A-Za-z0-9_]+$'
      if [[ "$lit" =~ $re_stream ]]; then
        lit="${BASH_REMATCH[1]}"
        # `C::$INDEX_ALLOCATION` is read as the drive, which the root arm refuses.
        [[ "$lit" =~ ^[A-Za-z]$ ]] && lit+=":"
      fi
      lit="${lit//"$RDT_PS_LIT"/\$}"
      if ((rdt_ps_lit_kept)); then
        rdt_check_operand "$lit" 4
        return 0
      fi
    fi
    w="${w//"$RDT_PS_LIT"/\$}"
  fi
  [[ -n "$lit" ]] && rdt_check_operand "$lit" 4
  w="${w//\$\{[eE][nN][vV]:/\$\{}"
  w="${w//\$[eE][nN][vV]:/\$}"
  rdt_check_operand "$w" 0
}

# rdt_ps_robocopy_check <word> ...: the words after a robocopy command word,
# with the stop-parsing token `--%` dropped, as PowerShell drops it. The first
# operand is the source and the second the destination (ROBOCOPY DELETES in
# the header), unless an operand holds an expanding `$` or is a grouping: an
# array, an unset variable or a command's output can become several
# arguments or none, so every operand is then judged.
rdt_ps_robocopy_check() {
  local -a __w=() __tg=()
  local __p __k
  for __p in "$@"; do
    [[ "$__p" == "--%" ]] || __w+=("$__p")
  done
  rdt_robocopy_scan 0 '' ${__w[@]+"${__w[@]}"}
  ((RDT_RC_DEST || RDT_RC_SRC)) || return 0
  for __k in ${RDT_RC_OP[@]+"${RDT_RC_OP[@]}"}; do
    case "${__w[__k]}" in
    *'$'* | '(' | '{' | '('* | '@('*)
      for __p in "${RDT_RC_OP[@]}"; do
        __tg+=("${__w[__p]}")
      done
      break
      ;;
    *) ;;
    esac
  done
  if ((${#__tg[@]} == 0)); then
    ((RDT_RC_SRC && ${#RDT_RC_OP[@]} > 0)) && __tg+=("${__w[RDT_RC_OP[0]]}")
    ((RDT_RC_DEST && ${#RDT_RC_OP[@]} > 1)) && __tg+=("${__w[RDT_RC_OP[1]]}")
  fi
  for __p in ${__tg[@]+"${__tg[@]}"}; do
    [[ -z "$__p" ]] && rdt_block "empty-operand"
    # The walker's placeholder for a `( )` grouping or a `{ }` scriptblock,
    # or a grouping it kept in the word: what it evaluates to is not known.
    # shellcheck disable=SC2016  # a literal `$(` grouping
    case "$__p" in
    '(' | '{' | '('* | '$('* | '@('*) rdt_block "pipeline-target" "$__p" ;;
    *) ;;
    esac
    rdt_ps_operand "$__p"
  done
  return 0
}

# rdt_ps_cmd_rd: recursive cmd rd/rmdir, and a robocopy cmd runs. Remaining
# words are the command line.
rdt_ps_cmd_rd() {
  local -a __cw=("$@")
  ((${#__cw[@]})) || return 0
  local __base="${__cw[0],,}" __i __rec=0
  __base="${__base##*[\\/]}"
  __base="${__base%.exe}"
  case "$__base" in
  rd | rmdir) ;;
  robocopy)
    rdt_ps_robocopy_check "${__cw[@]:1}"
    return 0
    ;;
  *) return 0 ;;
  esac
  local -a __paths=()
  for ((__i = 1; __i < ${#__cw[@]}; __i++)); do
    case "${__cw[__i],,}" in
    /s | /s/q | /q/s | /sq | /qs) __rec=1 ;;
    /q | /f) ;;
    /*)
      [[ "${__cw[__i],,}" == /s* ]] && __rec=1
      ;;
    *) __paths+=("${__cw[__i]}") ;;
    esac
  done
  ((__rec)) || return 0
  if ((${#__paths[@]} == 0)); then
    rdt_block "empty-operand"
  fi
  local __p
  for __p in "${__paths[@]}"; do
    if [[ -z "$__p" ]]; then
      rdt_block "empty-operand"
    fi
    rdt_ps_operand "$__p"
  done
}

# rdt_ps_cmd_from: argv after a cmd/cmd.exe command word.
rdt_ps_cmd_from() {
  local -a __a=("$@")
  local __i=0 __t
  local -a __parts=()
  while ((__i < ${#__a[@]})); do
    __t="${__a[__i],,}"
    case "$__t" in
    /c | /k)
      __i=$((__i + 1))
      ((__i < ${#__a[@]})) || return 0
      if ((__i == ${#__a[@]} - 1)); then
        rdt_ps_cmd_split_to __parts "${__a[__i]}"
        rdt_ps_cmd_rd ${__parts[@]+"${__parts[@]}"}
      else
        rdt_ps_cmd_rd "${__a[@]:__i}"
      fi
      return 0
      ;;
    /c?* | /k?*)
      rdt_ps_cmd_split_to __parts "${__a[__i]:2}"
      rdt_ps_cmd_rd ${__parts[@]+"${__parts[@]}"}
      return 0
      ;;
    *) ;;
    esac
    __i=$((__i + 1))
  done
}

# rdt_ps_ri_args <start-index>: argv after a Remove-Item family command word,
# passed as the remainder of the statement array in "$@".
# shellcheck disable=SC2016,SC2329  # literal `$(` grouping; invoked from rdt_ps_statement
rdt_ps_ri_check() {
  local -a __w=("$@")
  local __i=0 __rec=0 __param __raw __att __vm
  local -a __paths=()
  while ((__i < ${#__w[@]})); do
    local __v="${__w[__i]}"
    if [[ "$__v" == -* && "$__v" != - ]]; then
      rdt_ps_param_to __param "$__v"
      __raw="${__v#-}"
      __raw="${__raw%%:*}"
      __raw="${__raw,,}"
      if [[ "$__raw" == "rf" || "$__raw" == "fr" ]]; then
        __rec=1
      fi
      case "$__param" in
      recurse)
        if [[ "$__v" == *:* ]]; then
          __att="${__v#*:}"
          [[ -n "$RDT_PS_LIT" ]] && __att="${__att//"$RDT_PS_LIT"/\$}"
          __att="${__att,,}"
          __att="${__att#\$}"
          if [[ "$__att" != "false" && "$__att" != "0" ]]; then
            __rec=1
          fi
        else
          __rec=1
        fi
        ;;
      path | literalpath)
        if [[ "$__v" == *:* && "$__v" != *: ]]; then
          __paths+=("${__v#*:}")
        else
          __i=$((__i + 1))
          while ((__i < ${#__w[@]})) && { [[ "${__w[__i]}" != -* ]] || [[ "${__w[__i]}" == - ]]; }; do
            __paths+=("${__w[__i]}")
            __i=$((__i + 1))
          done
          __i=$((__i - 1))
        fi
        ;;
      filter | include | exclude | credential | stream | erroraction | warningaction | \
        informationaction | errorvariable | warningvariable | informationvariable | \
        outvariable | outbuffer | pipelinevariable)
        [[ "$__v" == *:* ]] || __i=$((__i + 1))
        ;;
      *) ;;
      esac
    else
      # A literal `$(` (`'$(x)'`) names a path, not a subexpression, unless an
      # expanding outer string held it (rdt_ps_operand).
      __vm="$__v"
      [[ -n "$RDT_PS_LIT" ]] && ((!rdt_ps_lit_kept)) && __vm="${__v//"$RDT_PS_LIT"/\$}"
      case "$__vm" in
      /s | /s/q | /q/s | /sq | /qs) ;;
      '('* | '$('*) rdt_block "pipeline-target" "$__vm" ;;
      *) __paths+=("$__v") ;;
      esac
    fi
    __i=$((__i + 1))
  done
  local __p
  # A target that is the pipeline item (`$_`, `$PSItem`, or a property of
  # either) makes the scriptblock it sits in a pipeline removal (#9765).
  for __p in ${__paths[@]+"${__paths[@]}"}; do
    case "${__p,,}" in
    '$_' | '$_.'* | '$psitem' | '$psitem.'*) rdt_ps_lvl_item=1 ;;
    *) ;;
    esac
  done
  # Fed by a pipe with no path of its own, it removes what the stage before
  # lists, recursive or not; a feed that is no listing names nothing.
  if ((${#__paths[@]} == 0 && rdt_ps_piped)); then
    rdt_ps_list_judge "$rdt_ps_feed_in" ${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"} && return 0
    ((__rec)) && rdt_block "pipeline-target"
    return 0
  fi
  ((__rec)) || return 0
  if ((${#__paths[@]} == 0)); then
    rdt_block "empty-operand"
  fi
  for __p in "${__paths[@]}"; do
    if [[ -z "$__p" ]]; then
      rdt_block "empty-operand"
    fi
    # The walker's placeholder for a `( )` grouping or a `{ }` scriptblock
    # named as a target: what it evaluates to is not known.
    [[ "$__p" == "(" || "$__p" == "{" ]] && rdt_block "pipeline-target" "$__p"
    rdt_ps_operand "$__p"
  done
}

# rdt_ps_rest <i>: remaining words of "$@" from index <i>, possibly empty.
rdt_ps_rest() {
  local __off="$1"
  shift
  if ((__off < $#)); then
    rdt_ps_ri_check "${@:__off+1}"
  else
    rdt_ps_ri_check
  fi
}

# rdt_ps_take: the argument that starts at __w[__i] in the caller, joined
# across the words a comma or an `@` carries it on to, into RDT_PS_ARG; __i is
# left on its last word. Reads and moves __w and __i through bash's dynamic
# scope.
rdt_ps_take() {
  RDT_PS_ARG="${__w[__i]}"
  while ((__i + 1 < ${#__w[@]})) && [[ "$RDT_PS_ARG" == *, || "$RDT_PS_ARG" == @ || "${__w[__i + 1]}" == ,* ]]; do
    __i=$((__i + 1))
    RDT_PS_ARG+="${__w[__i]}"
  done
}

# rdt_ps_move_check <kind> <word>...: the words after a Move-Item (move),
# Clear-Content (clear) or Set-Content (set) command word (MOVES AND CONTENT
# DESTROYERS in the header). Each -Path or -LiteralPath element, or the first
# positional argument when neither is named, is judged as a recursive
# Remove-Item target, every element of a comma list included. Set-Content is
# judged only when it writes several files: more than one element, a -Path
# holding a wildcard, or the pipeline item. With no path and a pipe into it,
# the listing before it is judged; Move-Item, which moves a directory's
# children with it, refuses any other feed, as a recursive removal does.
# shellcheck disable=SC2016  # a literal `$(` grouping
rdt_ps_move_check() {
  local __kind="$1" __i __n __v __e __fp="" __pos=0 __multi=0
  shift
  local -a __w=("$@") __names=() __pv=() __pw=()
  case "$__kind" in
  move) __names=(path literalpath pspath lp destination force filter include exclude passthru credential whatif confirm) ;;
  clear) __names=(path literalpath pspath lp filter include exclude force credential whatif confirm stream) ;;
  *) __names=(path literalpath pspath lp value passthru filter include exclude force credential whatif confirm nonewline encoding asbytestream stream) ;;
  esac
  for ((__i = 0; __i < ${#__w[@]}; __i++)); do
    if [[ "${__w[__i]}" == -?* ]]; then
      __v="${__w[__i]}"
      rdt_ps_pick_to __n "$__v" "${__names[@]}" "${RDT_PS_COMMON[@]}"
      case "$__n" in
      path | literalpath | pspath | lp | destination | value | filter | include | exclude | credential | stream | encoding) ;;
      *) rdt_ps_common_val "$__n" || continue ;;
      esac
      if [[ "$__v" == *:?* ]]; then
        RDT_PS_ARG="${__v#*:}"
      elif ((__i + 1 < ${#__w[@]})); then
        __i=$((__i + 1))
        rdt_ps_take
      else
        continue
      fi
      case "$__n" in
      path) __pv+=("$RDT_PS_ARG") __pw+=(1) ;;
      literalpath | pspath | lp) __pv+=("$RDT_PS_ARG") __pw+=(0) ;;
      *) ;;
      esac
      continue
    fi
    rdt_ps_take
    __pos=$((__pos + 1))
    ((__pos == 1)) && __fp="$RDT_PS_ARG"
  done
  if ((${#__pv[@]} == 0 && __pos > 0)); then
    __pv=("$__fp")
    __pw=(1)
  fi
  if ((${#__pv[@]} == 0)); then
    ((rdt_ps_piped)) || return 0
    rdt_ps_list_judge "$rdt_ps_feed_in" ${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"} && return 0
    [[ "$__kind" == move ]] && rdt_block "pipeline-target"
    return 0
  fi
  local -a __el=()
  for ((__i = 0; __i < ${#__pv[@]}; __i++)); do
    __v="${__pv[__i]}"
    if [[ -z "$__v" ]]; then
      __el+=("")
      continue
    fi
    while [[ -n "$__v" ]]; do
      __e="${__v%%,*}"
      if [[ "$__v" == *,* ]]; then
        __v="${__v#*,}"
      else
        __v=""
      fi
      [[ -n "$__e" ]] || continue
      ((__pw[__i])) && [[ "$__e" == *['*?[']* ]] && __multi=1
      __el+=("$__e")
    done
  done
  ((${#__el[@]} > 1)) && __multi=1
  for __e in ${__el[@]+"${__el[@]}"}; do
    # The pipeline item makes the scriptblock it sits in a pipeline removal
    # (#9765), and a write to it writes each item the listing before lists.
    case "${__e,,}" in
    '$_' | '$_.'* | '$psitem' | '$psitem.'*) __multi=2 ;;
    *) ;;
    esac
  done
  [[ "$__kind" == set ]] && ((__multi == 0)) && return 0
  ((__multi == 2)) && rdt_ps_lvl_item=1
  for __e in ${__el[@]+"${__el[@]}"}; do
    if [[ -z "$__e" ]]; then
      rdt_block "empty-operand"
      continue
    fi
    case "$__e" in
    '(' | '{' | '@' | '('* | '$('* | '@('*) rdt_block "pipeline-target" "$__e" ;;
    *) ;;
    esac
    rdt_ps_operand "$__e"
  done
  return 0
}

# --- PowerShell deletes behind indirection and pipelines (#9765) -------------
# The common parameters every cmdlet takes, so a prefix is matched against them
# too; rdt_ps_common_val says which take a value.
RDT_PS_COMMON=(debug verbose erroraction warningaction informationaction progressaction
  errorvariable warningvariable informationvariable outvariable outbuffer pipelinevariable
  db vb ea wa infa proga ev wv iv ov ob pv)
rdt_ps_common_val() {
  case "$1" in
  erroraction | warningaction | informationaction | progressaction | errorvariable | \
    warningvariable | informationvariable | outvariable | outbuffer | pipelinevariable | \
    ea | wa | infa | proga | ev | wv | iv | ov | ob | pv) return 0 ;;
  *) return 1 ;;
  esac
}

# rdt_ps_pick_to <var> <token> <name>...: the name a parameter token binds,
# exactly or as a unique prefix, the way PowerShell binds one; empty when it
# names none or several. The token keeps its dash; a :value suffix is ignored.
rdt_ps_pick_to() {
  local __pk_dest="$1" __pk_t="${2#-}" __pk_hit="" __pk_hits=0 __pk_n
  __pk_t="${__pk_t%%:*}"
  __pk_t="${__pk_t,,}"
  shift 2
  for __pk_n in "$@"; do
    if [[ "$__pk_n" == "$__pk_t" ]]; then
      printf -v "$__pk_dest" '%s' "$__pk_n"
      return 0
    fi
    if [[ -n "$__pk_t" && "$__pk_n" == "$__pk_t"* ]]; then
      __pk_hit="$__pk_n"
      __pk_hits=$((__pk_hits + 1))
    fi
  done
  ((__pk_hits == 1)) || __pk_hit=""
  printf -v "$__pk_dest" '%s' "$__pk_hit"
}

# rdt_ps_list_judge <piped> <word>...: when the words are a Get-ChildItem or
# Get-Item stage (gci, dir, ls, gi), each path it lists from is judged as a
# recursive delete operand, because a removal it feeds deletes there. With no
# path it lists `.`, unless <piped> is 1: then its paths are what a pipe hands
# it, which name nothing. Get-ChildItem's second positional argument is its
# -Filter. A comma, or an `@` before its grouping, carries one argument on to
# the next word, and each comma-separated element is judged. Returns 1 when
# the words are no such listing.
rdt_ps_list_judge() {
  local __lin="$1"
  shift
  local -a __lw=("$@") __lp=()
  local __i=0 __c __v __e __n="" __pos=0 __gci=0 __join=0 __dest=0
  while ((__i < ${#__lw[@]})) && [[ "${__lw[__i]}" == "&" ]]; do
    __i=$((__i + 1))
  done
  ((__i < ${#__lw[@]})) || return 1
  __c="${__lw[__i],,}"
  __c="${__c##*[\\/]}"
  __c="${__c%.exe}"
  case "$__c" in
  get-childitem | gci | dir | ls) __gci=1 ;;
  get-item | gi) ;;
  *) return 1 ;;
  esac
  for ((__i = __i + 1; __i < ${#__lw[@]}; __i++)); do
    __v="${__lw[__i]}"
    if ((__join == 0)) && [[ "$__v" == -?* ]]; then
      rdt_ps_pick_to __n "$__v" path literalpath lp pspath filter include exclude depth \
        attributes stream credential recurse force name directory file hidden readonly system \
        followsymlink "${RDT_PS_COMMON[@]}"
      case "$__n" in
      path | literalpath | lp | pspath) __dest=1 ;;
      filter | include | exclude | depth | attributes | stream | credential) __dest=0 ;;
      *)
        rdt_ps_common_val "$__n" || continue
        __dest=0
        ;;
      esac
      if [[ "$__v" == *:?* ]]; then
        __v="${__v#*:}"
      elif ((__i + 1 < ${#__lw[@]})); then
        __i=$((__i + 1))
        __v="${__lw[__i]}"
      else
        continue
      fi
    elif ((__join == 0)); then
      __pos=$((__pos + 1))
      __dest=0
      ((__pos == 1 || __gci == 0)) && __dest=1
    fi
    __join=0
    [[ "$__v" == *, || "$__v" == @ || "${__lw[__i + 1]-}" == ,* ]] && __join=1
    ((__dest)) && __lp+=("$__v")
  done
  if ((${#__lp[@]} == 0)); then
    ((__lin)) && return 1
    __lp=(".")
  fi
  for __v in "${__lp[@]}"; do
    if [[ -z "$__v" ]]; then
      rdt_block "empty-operand"
      continue
    fi
    while [[ -n "$__v" ]]; do
      __e="${__v%%,*}"
      if [[ "$__v" == *,* ]]; then
        __v="${__v#*,}"
      else
        __v=""
      fi
      [[ -n "$__e" ]] || continue
      # shellcheck disable=SC2016  # a literal `$(` grouping
      case "$__e" in
      '(' | '{' | '@' | '('* | '$('* | '@('*) rdt_block "pipeline-target" "$__e" ;;
      *) rdt_ps_operand "$__e" ;;
      esac
    done
  done
  return 0
}

# rdt_ps_wd <dir>: a -WorkingDirectory value, added as a directory a relative
# target may land from, as a literal cd adds one. One this reading cannot
# place leaves the directories as they were, so it never stops a later
# relative target from being judged.
rdt_ps_wd() {
  ((RDT_ARM)) || return 0
  local __wd_u=$rdt_cd_unknown
  rdt_add_origin "$1" 0
  rdt_cd_unknown=$__wd_u
}

# rdt_ps_select <word>...: true when a Select-Object stage only keeps some of
# the items piped to it (-First, -Last, -Skip, -SkipLast, -Unique, -Index), so
# what it passes on still comes from the stage before.
rdt_ps_select() {
  local __v __n="" __re='^[0-9,]+$'
  for __v in "$@"; do
    [[ "$__v" =~ $__re ]] && continue
    [[ "$__v" == -?* ]] || return 1
    rdt_ps_pick_to __n "$__v" first last skip skiplast unique index wait
    [[ -n "$__n" ]] || return 1
  done
  return 0
}

# rdt_ps_call_arg <word> [next word]: the first argument of a .NET delete call
# ([IO.Directory]::Delete, [IO.File]::Delete), the path it deletes, judged as a
# recursive delete operand up to the comma that ends it. A grouping, an array,
# a subexpression or a call there (`[Environment]::GetFolderPath(...)`, a word
# a grouping follows) is refused, because its value is not known; another
# expression is judged by its first word.
rdt_ps_call_arg() {
  local __ca="$1"
  # shellcheck disable=SC2016  # a literal `$(` grouping
  case "$__ca" in
  '(' | '{' | '@' | '('* | '$('* | '@('*)
    rdt_block "pipeline-target" "$__ca"
    return 0
    ;;
  *) ;;
  esac
  if [[ "$__ca" != *,* && "${2-}" == "(" ]]; then
    rdt_block "pipeline-target" "$__ca"
    return 0
  fi
  __ca="${__ca%%,*}"
  if [[ -z "$__ca" ]]; then
    rdt_block "empty-operand"
    return 0
  fi
  rdt_ps_operand "$__ca"
}

# rdt_ps_nested <text>: PowerShell text a statement runs (an Invoke-Expression
# string, a pwsh -Command, a decoded -EncodedCommand), walked as statements of
# its own. A `$` the outer walk read as literal is a `$` again here, because the
# text expands it when it runs. Nested text is always also read as an expansion
# (rdt_ps_lit_kept is 0 for its walk): it may come from an expanding string,
# which expanded a `$` single-quoted inside it already, and the outer string's
# escapes are gone from it, so it can hold a quoting form rdt_ps_quote_gap never
# saw in the command (`` <`# `` becomes `<#`, `` @`" `` becomes `@"`). Decoded
# -EncodedCommand text is read the same way, which only refuses more. Nesting depth
# and the text read in total are bounded as eval and child shells are in the
# Bash lane, and the bound refuses.
rdt_ps_nested() {
  local __t="$1" rdt_ps_lit_kept=0
  [[ -n "$RDT_PS_LIT" ]] && __t="${__t//"$RDT_PS_LIT"/\$}"
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  rdt_scanned=$((rdt_scanned + ${#__t}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_ps_walk "$__t"
}

# rdt_ps_b64_utf16_to <var> <text>: an -EncodedCommand value decoded as pwsh
# reads it, base64 of UTF-16LE (about_Pwsh), with bash builtins only. Returns 1
# for a value that is not literal base64, or one that decodes to anything but
# printable ASCII, tab, LF and CR, which the walk cannot read faithfully.
rdt_ps_b64_utf16_to() {
  local __bd_dest="$1" __bd_in="${2//[[:space:]]/}" __bd_out="" __bd_c __bd_pre __bd_x
  local __bd_al='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local __bd_re='^[A-Za-z0-9+/]+={0,2}$'
  local -i __bd_acc=0 __bd_bits=0 __bd_lo=-1 __bd_b=0 __bd_i
  [[ "$__bd_in" =~ $__bd_re ]] || return 1
  __bd_in="${__bd_in%%=*}"
  for ((__bd_i = 0; __bd_i < ${#__bd_in}; __bd_i++)); do
    __bd_c="${__bd_in:__bd_i:1}"
    __bd_pre="${__bd_al%%"$__bd_c"*}"
    ((${#__bd_pre} < 64)) || return 1
    __bd_acc=$(((__bd_acc << 6) | ${#__bd_pre}))
    __bd_bits=$((__bd_bits + 6))
    ((__bd_bits >= 8)) || continue
    __bd_bits=$((__bd_bits - 8))
    __bd_b=$(((__bd_acc >> __bd_bits) & 255))
    __bd_acc=$((__bd_acc & ((1 << __bd_bits) - 1)))
    if ((__bd_lo < 0)); then
      __bd_lo=$__bd_b
      continue
    fi
    # One UTF-16LE code unit: the low byte, then a high byte of 0 for ASCII.
    ((__bd_b == 0 && ((__bd_lo >= 32 && __bd_lo < 127) || __bd_lo == 9 || __bd_lo == 10 || __bd_lo == 13))) || return 1
    printf -v __bd_x '%02x' "$__bd_lo"
    # shellcheck disable=SC2059  # the format is the one byte's \x escape
    printf -v __bd_c "\\x$__bd_x"
    __bd_out+="$__bd_c"
    __bd_lo=-1
  done
  ((__bd_lo < 0)) || return 1
  printf -v "$__bd_dest" '%s' "$__bd_out"
}

# rdt_ps_shell_from <word>...: the words after a pwsh or powershell command
# word (about_Pwsh, about_PowerShell_exe). -Command (-c, or a prefix of it)
# runs every word after it joined by spaces, -CommandWithArgs (-cwa) runs the
# word after it, and -EncodedCommand (-e, -ec, or a prefix of it) runs the word
# after it decoded; each is walked as PowerShell, and an -EncodedCommand this
# walk cannot decode is refused. A word before any of them that is no option
# starts -Command text too: powershell.exe's default, and for pwsh, whose
# default is -File, a script name and its arguments read as harmless text.
# -File (-f) runs a script, which is not read. -WorkingDirectory adds the
# directory a relative target may land from.
rdt_ps_shell_from() {
  local -a __sa=("$@")
  local __k=0 __v __n __t="" __full __pos=0
  while ((__k < ${#__sa[@]})); do
    __v="${__sa[__k]}"
    # The first word that is no option starts the text; the scan goes on, so
    # a -Command after an option this reading does not know is read as well.
    if [[ "$__v" != -* && "$__v" != /?* ]]; then
      if ((__pos == 0)); then
        __pos=1
        __t=""
        for __full in "${__sa[@]:__k}"; do
          __t+="${__t:+ }$__full"
        done
        rdt_ps_nested "$__t"
      fi
      __k=$((__k + 1))
      continue
    fi
    __n="${__v#/}"
    __n="${__n#-}"
    __n="${__n#-}"
    __n="${__n%%:*}"
    __n="${__n,,}"
    __k=$((__k + 1))
    [[ -z "$__n" || "$__n" == "%" ]] && continue
    if [[ "$__n" == cwa || ("$__n" == commandw* && "commandwithargs" == "$__n"*) ]]; then
      ((__k < ${#__sa[@]})) && rdt_ps_nested "${__sa[__k]}"
      return 0
    fi
    if [[ "command" == "$__n"* ]]; then
      __t=""
      for __full in ${__sa[@]+"${__sa[@]:__k}"}; do
        __t+="${__t:+ }$__full"
      done
      [[ -n "$__t" ]] && rdt_ps_nested "$__t"
      return 0
    fi
    if [[ "$__n" == ec || "encodedcommand" == "$__n"* ]]; then
      ((__k < ${#__sa[@]})) || return 0
      rdt_ps_b64_utf16_to __t "${__sa[__k]}" || rdt_block "encoded-unreadable"
      rdt_ps_nested "$__t"
      return 0
    fi
    [[ "file" == "$__n"* ]] && return 0
    if [[ "$__n" == wd || ("$__n" == wo* && "workingdirectory" == "$__n"*) ]]; then
      if ((__k < ${#__sa[@]})); then
        rdt_ps_wd "${__sa[__k]}"
        __k=$((__k + 1))
      fi
      continue
    fi
    case "$__n" in
    ex | ep | w | o | of | inp | if | config | settings | v) __k=$((__k + 1)) ;;
    *)
      for __full in executionpolicy windowstyle outputformat inputformat configurationname \
        configurationfile custompipename settingsfile psconsolefile version encodedarguments; do
        if ((${#__n} >= 3)) && [[ "$__full" == "$__n"* ]]; then
          __k=$((__k + 1))
          break
        fi
      done
      ;;
    esac
  done
  return 0
}

# rdt_ps_iex <word>...: the words after Invoke-Expression or iex. Its -Command
# (position 0, or a prefix of the name) is walked as PowerShell. Without one,
# the string a pipe hands it (Invoke-Expression, learn.microsoft.com) is walked
# when the stage before is one word or a Write-Output, echo or write of one; a
# feed of any other shape, like a variable it is given, names nothing. A
# grouping given as the string is read when it holds one word (`iex ('...')`),
# the grouping that closed last in the statement.
rdt_ps_iex_run() {
  if [[ "$1" != "(" ]]; then
    rdt_ps_nested "$1"
  elif ((${#rdt_ps_grp[@]} == 1)); then
    rdt_ps_nested "${rdt_ps_grp[0]}"
  fi
  return 0
}
rdt_ps_iex() {
  local -a __ia=("$@") __f=()
  local __k=0 __v __n=""
  while ((__k < ${#__ia[@]})); do
    __v="${__ia[__k]}"
    __k=$((__k + 1))
    if [[ "$__v" != -?* ]]; then
      rdt_ps_iex_run "$__v"
      return 0
    fi
    rdt_ps_pick_to __n "$__v" command "${RDT_PS_COMMON[@]}"
    if [[ "$__n" == command ]]; then
      if [[ "$__v" == *:?* ]]; then
        rdt_ps_iex_run "${__v#*:}"
      elif ((__k < ${#__ia[@]})); then
        rdt_ps_iex_run "${__ia[__k]}"
      fi
      return 0
    fi
    rdt_ps_common_val "$__n" && [[ "$__v" != *:* ]] && __k=$((__k + 1))
  done
  ((rdt_ps_piped)) || return 0
  __f=(${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"})
  if ((${#__f[@]} == 1)); then
    rdt_ps_nested "${__f[0]}"
  elif ((${#__f[@]} == 2)); then
    case "${__f[0],,}" in
    write-output | echo | write) rdt_ps_nested "${__f[1]}" ;;
    *) ;;
    esac
  fi
  return 0
}

# rdt_ps_start <word>...: the words after Start-Process, saps or start. Its
# -FilePath (position 0) is the program, and its -ArgumentList (position 1, an
# array its commas join) is joined by spaces into the one command line the
# program gets (Start-Process, learn.microsoft.com). That line is split as cmd
# splits one and judged as the program's statement: cmd /c rd /s, robocopy, a
# Remove-Item spelling such as rm, or pwsh and powershell. -WorkingDirectory
# adds the directory a relative target may land from. A program or argument
# list held in a variable names nothing.
rdt_ps_start() {
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  local -a __pa=("$@") __pr=() __pp=()
  local __k=0 __v __n __fp=0 __al=0 __prog="" __line="" rdt_ps_piped=0 rdt_ps_item=0
  local __re='^-[A-Za-z][A-Za-z0-9]*(:|$)'
  while ((__k < ${#__pa[@]})); do
    __v="${__pa[__k]}"
    __k=$((__k + 1))
    __n=""
    # A parameter is a dash and a name; a word holding a blank or a comma is a
    # quoted string even when it starts with a dash (`'-c','...'`).
    if [[ "$__v" =~ $__re ]]; then
      rdt_ps_pick_to __n "$__v" filepath path pspath argumentlist args workingdirectory \
        credential redirectstandarderror redirectstandardinput redirectstandardoutput rse rsi rso \
        windowstyle verb environment wait nonewwindow nnw passthru loaduserprofile lup \
        usenewenvironment whatif wi confirm cf "${RDT_PS_COMMON[@]}"
      case "$__n" in
      filepath | path | pspath | argumentlist | args | workingdirectory) ;;
      credential | redirectstandard* | rse | rsi | rso | windowstyle | verb | environment)
        [[ "$__v" == *:* ]] || __k=$((__k + 1))
        continue
        ;;
      *)
        rdt_ps_common_val "$__n" && [[ "$__v" != *:* ]] && __k=$((__k + 1))
        continue
        ;;
      esac
      if [[ "$__v" == *:?* ]]; then
        __v="${__v#*:}"
      elif ((__k < ${#__pa[@]})); then
        __v="${__pa[__k]}"
        __k=$((__k + 1))
      else
        continue
      fi
    else
      # A positional word binds the first of the two not yet named.
      if ((!__fp)); then
        __n=filepath
      elif ((!__al)); then
        __n=argumentlist
      fi
    fi
    case "$__n" in
    filepath | path | pspath)
      __prog="$__v"
      __fp=1
      ;;
    workingdirectory) rdt_ps_wd "$__v" ;;
    argumentlist | args)
      __al=1
      __pr+=("$__v")
      # An array goes on across the commas that join its elements.
      while ((__k < ${#__pa[@]})) && [[ "${__pr[${#__pr[@]} - 1]}" == *, || "${__pa[__k]}" == ,* ]]; do
        __pr+=("${__pa[__k]}")
        __k=$((__k + 1))
      done
      ;;
    *) ;;
    esac
  done
  [[ -n "$__prog" ]] || return 0
  for __v in ${__pr[@]+"${__pr[@]}"}; do
    __line+="${__line:+ }${__v//,/ }"
  done
  rdt_ps_cmd_split_to __pp "$__line"
  rdt_ps_statement "$__prog" ${__pp[@]+"${__pp[@]}"}
}

# rdt_ps_statement: one pipeline stage's words. A scriptblock in the stage that
# removes the pipeline item (rdt_ps_item) removes what the stage before lists,
# and a feed that is no listing names nothing, so it is refused.
rdt_ps_statement() {
  local -a __w=("$@")
  ((${#__w[@]})) || return 0
  if ((rdt_ps_item && rdt_ps_piped)); then
    rdt_ps_list_judge "$rdt_ps_feed_in" ${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"} || rdt_block "pipeline-target"
  fi
  local __i=0 __cmd
  while ((__i < ${#__w[@]})) && [[ "${__w[__i]}" == "&" ]]; do
    __i=$((__i + 1))
  done
  ((__i < ${#__w[@]})) || return 0
  __cmd="${__w[__i]}"
  __cmd="${__cmd##*\\}"
  __cmd="${__cmd##*/}"
  __cmd="${__cmd,,}"
  __cmd="${__cmd%.exe}"
  __i=$((__i + 1))
  case "$__cmd" in
  remove-item | ri | rm | del | erase)
    rdt_ps_rest "$__i" ${__w[@]+"${__w[@]}"}
    ;;
  rd | rmdir)
    rdt_ps_rest "$__i" ${__w[@]+"${__w[@]}"}
    if ((__i < ${#__w[@]})); then
      rdt_ps_cmd_rd "$__cmd" "${__w[@]:__i}"
    else
      rdt_ps_cmd_rd "$__cmd"
    fi
    ;;
  cmd)
    if ((__i < ${#__w[@]})); then
      rdt_ps_cmd_from "${__w[@]:__i}"
    fi
    ;;
  robocopy)
    if ((__i < ${#__w[@]})); then
      rdt_ps_robocopy_check "${__w[@]:__i}"
    fi
    ;;
  move-item | mi | move | mv) rdt_ps_move_check move "${__w[@]:__i}" ;;
  clear-content | clc) rdt_ps_move_check clear "${__w[@]:__i}" ;;
  set-content) rdt_ps_move_check set "${__w[@]:__i}" ;;
  invoke-expression | iex) rdt_ps_iex "${__w[@]:__i}" ;;
  start-process | saps | start) rdt_ps_start "${__w[@]:__i}" ;;
  pwsh | powershell) rdt_ps_shell_from "${__w[@]:__i}" ;;
  # A filter passes on items of the stage before, so what a removal after it
  # deletes is still what that stage lists (rdt_ps_feed is kept).
  where-object | where | '?' | sort-object | sort) ((rdt_ps_piped)) && rdt_ps_pass=1 ;;
  select-object | select) ((rdt_ps_piped)) && rdt_ps_select "${__w[@]:__i}" && rdt_ps_pass=1 ;;
  *) ;;
  esac
  return 0
}

# rdt_ps_decoded <word>...: one pipeline stage, for DECODER SINKS. The stage is
# decoded when a word of it is [Convert]::FromBase64String (the `(` of the call
# ends the word, so a quoted string that names it is never that whole word), a
# level closed inside it was (rdt_ps_dec), or a decoded stage pipes into it
# (rdt_ps_pipe_dec). A decoded stage taints its level (rdt_ps_lvl_dec), and
# Invoke-Expression or iex given decoded text is refused.
rdt_ps_decoded() {
  local d=$rdt_ps_dec w c=""
  rdt_ps_dec=0
  ((rdt_ps_after_pipe && rdt_ps_pipe_dec)) && d=1
  rdt_ps_after_pipe=0
  for w in "$@"; do
    case "${w,,}" in
    '[convert]::frombase64string' | '[system.convert]::frombase64string') d=1 ;;
    *) ;;
    esac
    [[ -z "$c" && "$w" != "&" ]] && c="$w"
  done
  rdt_ps_pipe_dec=$d
  ((d)) || return 0
  rdt_ps_lvl_dec=1
  c="${c##*\\}"
  c="${c##*/}"
  c="${c,,}"
  c="${c%.exe}"
  [[ "$c" == iex || "$c" == invoke-expression ]] && rdt_block "decoder-sink"
  return 0
}

# rdt_ps_walk <command>: PowerShell quoting (backtick escape, backslash
# literal) into statements split on the boundaries listed above, then judged.
# Judging a statement resets the pipeline state, so the stage right after a `|`
# keeps it across an empty boundary (a newline after the pipe). A newline after
# an unquoted comma does not end the statement: the array continues on the next
# line. The nested levels are parked in __sv (their words, flat), __svn (how
# many words each holds) and __svp (their pipeline state).
rdt_ps_walk() {
  local __s="$1" __n=${#1} __i=0
  local -a __words=() __sv=() __svn=() __svp=() __svk=() __svd=() __sf=() __sfn=()
  local __word="" __in=0 __q="" __c __nxt __cont=0
  # Local, so a walk of nested text (rdt_ps_nested) keeps the outer state.
  # rdt_ps_feed is the stage that last ended, which feeds the next one after a
  # `|`, and rdt_ps_feed_in says a pipe fed that stage too; rdt_ps_item marks a stage whose scriptblock removes the pipeline item
  # and rdt_ps_lvl_item a level holding such a removal; rdt_ps_call a level
  # that is a .NET delete call's arguments; rdt_ps_nst counts the statements
  # of a level (two means more), and rdt_ps_grp holds the one statement of the
  # grouping that closed last.
  local rdt_ps_piped=0 rdt_ps_dec=0 rdt_ps_lvl_dec=0 rdt_ps_pipe_dec=0 rdt_ps_after_pipe=0
  local rdt_ps_item=0 rdt_ps_lvl_item=0 rdt_ps_call=0 rdt_ps_nst=0 rdt_ps_pass=0 rdt_ps_feed_in=0
  local -a rdt_ps_feed=() rdt_ps_grp=()

  rdt_ps_flush_word() {
    if ((__in)); then
      __words+=("$__word")
    fi
    __word=""
    __in=0
  }
  rdt_ps_end_stmt() {
    rdt_ps_flush_word
    if ((${#__words[@]})); then
      if ((rdt_ps_call)); then
        rdt_ps_call=0
        rdt_ps_call_arg "${__words[0]}" "${__words[1]-}"
      fi
      rdt_ps_decoded "${__words[@]}"
      rdt_ps_statement "${__words[@]}"
      if ((!rdt_ps_pass)); then
        rdt_ps_feed=("${__words[@]}")
        rdt_ps_feed_in=$rdt_ps_piped
      fi
      ((rdt_ps_item && !rdt_ps_piped)) && rdt_ps_lvl_item=1
      ((rdt_ps_nst < 2)) && rdt_ps_nst=$((rdt_ps_nst + 1))
      __words=()
      rdt_ps_piped=0 rdt_ps_item=0 rdt_ps_pass=0
    fi
  }
  # A `(`, `$(` or `{` (its kind is the argument) opens a level: the statement
  # so far is parked and what follows is judged on its own. A `(` right after
  # a word is a call, and three calls delete: [<type>]::Delete( makes the
  # level a .NET delete's arguments, $_.Delete( or $PSItem.Delete( removes the
  # pipeline item, and .Delete( after a grouping removes what the grouping
  # lists.
  rdt_ps_open() {
    rdt_ps_flush_word
    ((${#__svn[@]} < MAX_SUBST_DEPTH)) || rdt_block "nesting-too-deep"
    local __call=0 __nw=${#__words[@]}
    if [[ "$1" == "(" ]] && ((__nw)); then
      # shellcheck disable=SC2016  # literal `$_` and `$PSItem` member calls
      case "${__words[__nw - 1],,}" in
      *']::delete') __call=1 ;;
      '$_.delete' | '$psitem.delete') rdt_ps_lvl_item=1 ;;
      .delete)
        # A grouping that is not one listing statement names nothing.
        if ((__nw > 1)) && [[ "${__words[__nw - 2]}" == "(" ]]; then
          rdt_ps_list_judge 0 ${rdt_ps_grp[@]+"${rdt_ps_grp[@]}"} || rdt_block "pipeline-target"
        fi
        ;;
      *) ;;
      esac
    fi
    if ((__nw)); then
      __sv+=("${__words[@]}")
    fi
    __svn+=("$__nw")
    __svp+=("$rdt_ps_piped")
    __svk+=("$1")
    __svd+=("$rdt_ps_dec$rdt_ps_lvl_dec$rdt_ps_pipe_dec$rdt_ps_after_pipe$rdt_ps_item$rdt_ps_lvl_item$rdt_ps_call$rdt_ps_nst$rdt_ps_feed_in")
    __sfn+=("${#rdt_ps_feed[@]}")
    if ((${#rdt_ps_feed[@]})); then
      __sf+=("${rdt_ps_feed[@]}")
    fi
    __words=()
    rdt_ps_feed=()
    rdt_ps_piped=0
    rdt_ps_dec=0 rdt_ps_lvl_dec=0 rdt_ps_pipe_dec=0 rdt_ps_after_pipe=0
    rdt_ps_item=0 rdt_ps_lvl_item=0 rdt_ps_call=$__call rdt_ps_nst=0 rdt_ps_feed_in=0
  }
  # A `)` or `}` judges the innermost level and hands its parked statement back
  # with one placeholder word, the kind the level was opened with (`(` or
  # `{`), whichever closer ended it. Without an open level it only ends the
  # statement.
  rdt_ps_close() {
    rdt_ps_end_stmt
    local __k=${#__svn[@]} __cnt __tot __kind __d
    ((__k)) || return 0
    rdt_ps_grp=()
    ((rdt_ps_nst == 1)) && rdt_ps_grp=(${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"})
    __cnt=${__svn[__k - 1]}
    __kind=${__svk[__k - 1]}
    __tot=${#__sv[@]}
    if ((__cnt)); then
      __words=("${__sv[@]:__tot-__cnt:__cnt}")
      __sv=("${__sv[@]:0:__tot-__cnt}")
    else
      __words=()
    fi
    __cnt=${__sfn[__k - 1]}
    __tot=${#__sf[@]}
    if ((__cnt)); then
      rdt_ps_feed=("${__sf[@]:__tot-__cnt:__cnt}")
      __sf=("${__sf[@]:0:__tot-__cnt}")
    else
      rdt_ps_feed=()
    fi
    rdt_ps_piped=${__svp[__k - 1]}
    # A level that held decoded text, or removed the pipeline item, marks the
    # statement it hands back to.
    __d=${__svd[__k - 1]}
    rdt_ps_dec=$((${__d:0:1} | rdt_ps_lvl_dec))
    rdt_ps_item=$((${__d:4:1} | rdt_ps_lvl_item))
    rdt_ps_lvl_dec=${__d:1:1}
    rdt_ps_pipe_dec=${__d:2:1}
    rdt_ps_after_pipe=${__d:3:1}
    rdt_ps_lvl_item=${__d:5:1}
    rdt_ps_call=${__d:6:1}
    rdt_ps_nst=${__d:7:1}
    rdt_ps_feed_in=${__d:8:1}
    unset "__svn[__k - 1]" "__svp[__k - 1]" "__svk[__k - 1]" "__svd[__k - 1]" "__sfn[__k - 1]"
    __words+=("$__kind")
    if [[ "$__kind" == "{" ]]; then
      case "${__words[0],,}" in
      if | elseif | else | foreach | for | while | do | until | switch | try | catch | finally | \
        trap | function | filter | workflow | param | begin | process | end | dynamicparam)
        rdt_ps_end_stmt
        ;;
      *) ;;
      esac
    fi
  }

  while ((__i < __n)); do
    __c="${__s:__i:1}"
    if ((__i + 1 < __n)); then
      __nxt="${__s:__i+1:1}"
    else
      __nxt=""
    fi
    if [[ -n "$__q" ]]; then
      if [[ "$__q" == "'" ]]; then
        if [[ "$__c" == "'" ]]; then
          if [[ "$__nxt" == "'" ]]; then
            __word+="'"
            __i=$((__i + 1))
          else
            __q=""
          fi
        elif [[ "$__c" == '$' && -n "$RDT_PS_LIT" ]]; then
          __word+="$RDT_PS_LIT"
        else
          __word+="$__c"
        fi
      elif [[ "$__q" == '}' ]]; then
        # `${name}`: the name runs to the first unescaped `}` and stays in the
        # word, so `${env:ProgramFiles(x86)}` is one word and its `(` no boundary.
        if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
          __word+="$__nxt"
          __i=$((__i + 1))
        else
          __word+="$__c"
          [[ "$__c" == '}' ]] && __q=""
        fi
      else
        if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
          if [[ "$__nxt" == '$' && -n "$RDT_PS_LIT" ]]; then
            __word+="$RDT_PS_LIT"
          else
            __word+="$__nxt"
          fi
          __i=$((__i + 1))
        elif [[ "$__c" == '"' ]]; then
          __q=""
        else
          __word+="$__c"
        fi
      fi
      __in=1
      __i=$((__i + 1))
      continue
    fi
    if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
      # A backtick before a line break (LF, CR or CRLF) continues the line.
      if [[ "$__nxt" == $'\n' || "$__nxt" == $'\r' ]]; then
        __i=$((__i + 2))
        [[ "$__nxt" == $'\r' && "${__s:__i:1}" == $'\n' ]] && __i=$((__i + 1))
        continue
      fi
      if [[ "$__nxt" == '$' && -n "$RDT_PS_LIT" ]]; then
        __word+="$RDT_PS_LIT"
      else
        __word+="$__nxt"
      fi
      __in=1
      __cont=0
      __i=$((__i + 2))
      continue
    fi
    [[ "$__c" == [[:space:]] ]] || __cont=0
    case "$__c" in
    "'")
      __q="'"
      __in=1
      ;;
    '"')
      __q='"'
      __in=1
      ;;
    '#')
      if ((__in == 0)); then
        while ((__i < __n)) && [[ "${__s:__i:1}" != $'\n' && "${__s:__i:1}" != $'\r' ]]; do
          __i=$((__i + 1))
        done
        continue
      else
        __word+="#"
      fi
      ;;
    '$')
      # `$(` opens a subexpression: its `(` below opens the level and the `$`
      # is not a word. `${` opens a braced variable name.
      if [[ "$__nxt" != '(' ]]; then
        __in=1
        if [[ "$__nxt" == '{' ]]; then
          __word+="\${"
          __q='}'
          __i=$((__i + 1))
        else
          __word+='$'
        fi
      fi
      ;;
    ',')
      __word+=","
      __in=1
      __cont=1
      ;;
    '(' | '{')
      rdt_ps_open "$__c"
      ;;
    ')' | '}')
      rdt_ps_close
      ;;
    $'\n' | $'\r')
      if ((__cont)); then
        rdt_ps_flush_word
      else
        rdt_ps_end_stmt
      fi
      ;;
    # A separator ends the stage first, so a stage a pipe feeds is judged as
    # piped whatever ends it, and then clears the pipe for what follows.
    '|')
      if [[ "$__nxt" == '|' ]]; then
        rdt_ps_end_stmt
        rdt_ps_piped=0
        __i=$((__i + 1))
      else
        rdt_ps_end_stmt
        rdt_ps_piped=1
        rdt_ps_after_pipe=1
      fi
      ;;
    '&')
      if ((__in == 0)) && { [[ -z "$__nxt" ]] || [[ "$__nxt" == [[:space:]] ]] || [[ "$__nxt" == "'" ]] || [[ "$__nxt" == '"' ]]; }; then
        rdt_ps_flush_word
        __words+=("&")
      elif [[ "$__nxt" == '&' ]]; then
        rdt_ps_end_stmt
        rdt_ps_piped=0
        __i=$((__i + 1))
      else
        rdt_ps_end_stmt
        rdt_ps_piped=0
      fi
      ;;
    ';')
      rdt_ps_end_stmt
      rdt_ps_piped=0
      ;;
    [[:space:]])
      rdt_ps_flush_word
      ;;
    *)
      __word+="$__c"
      __in=1
      ;;
    esac
    __i=$((__i + 1))
  done
  rdt_ps_end_stmt
  # A level the text never closes is judged too.
  while ((${#__svn[@]})); do
    rdt_ps_close
    rdt_ps_end_stmt
  done
}

# rdt_ps_run: PowerShell lane. Does not load the classifier.
rdt_ps_run() {
  rdt_ps_walk "$COMMAND"
}

# The substitution scan runs FIRST, and the order is load-bearing rather than
# arbitrary. The tokenizer splits on unquoted `(`, `)` and `;`, so a deeply
# nested payload yields as many segments as a flat one of the same length and
# the top-level parse pays for every one of them. Scanning first lets the
# tokenizing budget refuse such a payload after the cheap character walk alone,
# instead of after the parse it was built to make expensive.
#
# The outside-tree arm starts from the payload cwd, and only an absolute one:
# a relative cwd names no place this hook can resolve. A cwd carrying a NUL
# byte arms it too, so that the first operand it would record is refused.
PAYLOAD_CWD="${PAYLOAD_CWD//\\//}"
if ((RDT_CWD_NUL)); then
  RDT_ARM=1
  RDT_ORIGINS=("/")
elif rdt_is_abs "$PAYLOAD_CWD"; then
  RDT_ARM=1
  _rdt_origin=""
  rdt_lex_to _rdt_origin "$PAYLOAD_CWD"
  RDT_ORIGINS=("$_rdt_origin")
fi
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  rdt_ps_run
else
  rdt_in_subst=1
  rdt_scan_substitutions "$COMMAND"
  rdt_in_subst=0
  rdt_parse "$COMMAND"
fi
# The judgment runs in a subshell, so an error nobody anticipated inside it (an
# unset variable under `set -u`, say) ends the subshell with a status other
# than 0 or 2, and that status is refused here. Run in place, the same error
# would end the hook with 1, which the fail-open abort boundary passes.
# Status 3 means the judgment finished with attended asks recorded, which the
# subshell hands up on stdout, one per RS (0x1e) field, to join this shell's.
if ((${#RDT_P_TEXT[@]})); then
  rdt_judge_rc=0
  rdt_judge_ask=$(
    HOOK_REFUSE_PENDING=()
    rdt_judge_pending || exit
    ((${#HOOK_REFUSE_PENDING[@]})) || exit 0
    printf '%s\x1e' "${HOOK_REFUSE_PENDING[@]}"
    exit 3
  ) || rdt_judge_rc=$?
  ((rdt_judge_rc == 2)) && exit 2
  if ((rdt_judge_rc == 3)) && [[ -n "$rdt_judge_ask" ]]; then
    while [[ "$rdt_judge_ask" == *$'\x1e'* ]]; do
      hook::refuse "${rdt_judge_ask%%$'\x1e'*}"
      rdt_judge_ask="${rdt_judge_ask#*$'\x1e'}"
    done
    rdt_judge_rc=0
  fi
  ((rdt_judge_rc == 0)) || rdt_block "judge-error"
fi

# The whole command was read and nothing in it denies: ask, if any segment asked.
hook::refuse_flush
rdt_emit_tel "ok" ""
exit 0
