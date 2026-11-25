
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
