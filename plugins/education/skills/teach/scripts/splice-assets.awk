# splice-assets.awk: the build half of splice-assets.sh, which validates everything first and then
# runs this program over the lesson. A marker line is replaced by the matching asset file's content
# and every other line passes through unchanged. Nothing here opens the lesson for writing: the
# caller owns the redirect into its temp file and the overwrite. Detection is fixed-string, through
# index(), because the marker text is not a valid regular expression.
#
# The assets directory arrives in the environment as `A` rather than through awk's own variable
# assignment flag, which interprets backslash escapes: a Windows assets path carries backslashes
# and would otherwise be mangled before the program ever saw it. `BINMODE=3`, which the caller does
# pass with `-v`, stops gawk on Windows from stripping and re-adding carriage returns; a POSIX awk
# reads it as an ordinary variable assignment and ignores it.
#
# A getline returning -1 is a read error, not end of input. Treating it as the end would print a
# truncated asset and let the caller copy that over the lesson, so a failed read exits 1 naming the
# file instead, and the caller's nonzero-awk branch leaves the lesson unchanged.

function splice(f,  r, line) {
  while ((r = (getline line < f)) > 0) print line
  if (r < 0) {
    print "splice-assets.sh: reading " f " failed" > "/dev/stderr"
    exit 1
  }
  close(f)
}

index($0, "/* SPLICE:STYLE */") { splice(ENVIRON["A"] "/lesson.css"); next }
index($0, "/* SPLICE:QUIZ */")  { splice(ENVIRON["A"] "/quiz.js");   next }
{ print }
