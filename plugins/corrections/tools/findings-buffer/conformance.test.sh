#!/usr/bin/env bash
# Tests for conformance.sh: it passes the local-file adapter, fails adapters that
# break the contract, and rejects a bad invocation with exit 2.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/conformance.sh"
LOCAL="$SCRIPT_DIR/adapters/local-file"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  if [[ -n "${2:-}" ]]; then printf '  %s\n' "$2"; fi
}
# expect_exit <want> <got> <name>
expect_exit() {
  if [[ "$2" -eq "$1" ]]; then
    pass "$3"
  else
    fail "$3" "wanted exit $1, got $2"
  fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "1..0 # SKIP git not available"
  exit 0
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# Children that call mktemp land inside the trapped root.
export TMPDIR="$TEST_TMPDIR"

# local-file passes
OUT="$(bash "$CONF" "$LOCAL" 2>&1)"
RC=$?
if [[ $RC -eq 0 ]]; then
  pass "conformance.sh passes the local-file adapter"
else
  fail "conformance.sh passes the local-file adapter" "exit $RC: $OUT"
fi

bash "$CONF" >/dev/null 2>&1
expect_exit 2 $? "no adapter-dir exits 2"

bash "$CONF" "$TEST_TMPDIR/nope" >/dev/null 2>&1
expect_exit 2 $? "a missing adapter-dir exits 2"

# make_broken <name>: a copy of local-file to sabotage; prints its directory.
make_broken() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  cp "$LOCAL/append.sh" "$LOCAL/read.sh" "$LOCAL/capabilities.json" "$d/"
  printf '%s\n' "$d"
}

# an adapter that stores only the first line of each call loses rows
D="$(make_broken drops)"
cat >"$D/append.sh" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)" || exit 3
mkdir -p "$ROOT/.work/buffer"
head -n 1 >>"$ROOT/.work/buffer/findings.jsonl"
EOF
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an adapter that loses a row fails"

# an unsupported schema_version
D="$(make_broken badcaps)"
printf '{"schema_version":"2.0","adapter":"x"}\n' >"$D/capabilities.json"
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an unsupported schema_version fails"

# invalid JSON that still contains the expected text
D="$(make_broken badjson)"
printf '{"schema_version":"1.0","adapter":"x",\n' >"$D/capabilities.json"
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an unparsable capabilities.json fails"

# a reader that ignores its arguments
D="$(make_broken lax)"
cat >"$D/read.sh" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)" || exit 3
cat "$ROOT/.work/buffer/findings.jsonl" 2>/dev/null
exit 0
EOF
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an adapter that accepts a bad argument fails"

# local-file stores under .work/buffer/findings.jsonl
REPO="$TEST_TMPDIR/repo"
git init -q -b main "$REPO" >/dev/null 2>&1
printf '{"obs_id":"x","ts":"2026-10-21T00:00:00Z"}\n' | (cd "$REPO" && bash "$LOCAL/append.sh")
if [[ -s "$REPO/.work/buffer/findings.jsonl" ]]; then
  pass "local-file creates .work/buffer/findings.jsonl on first append"
else
  fail "local-file creates .work/buffer/findings.jsonl on first append"
fi

# a malformed row stores nothing and exits 2
printf '{"obs_id":"y","ts":"2026-10-21T00:00:01Z"}\nnot json\n' | (cd "$REPO" && bash "$LOCAL/append.sh" >/dev/null 2>&1)
expect_exit 2 $? "append.sh with a malformed row exits 2"
if [[ "$(wc -l <"$REPO/.work/buffer/findings.jsonl")" -eq 1 ]]; then
  pass "a malformed row stores nothing from that call"
else
  fail "a malformed row stores nothing from that call"
fi

# {oops} and rows missing obs_id or ts are rejected
for bad in '{oops}' '{}' '{"obs_id":"z"}' '{"obs_id":"z","ts":"2026-10-21T00:00:02Z"}{"x":1}'; do
  printf '%s\n' "$bad" | (cd "$REPO" && bash "$LOCAL/append.sh" >/dev/null 2>&1)
  expect_exit 2 $? "append.sh rejects $bad"
done
if [[ "$(wc -l <"$REPO/.work/buffer/findings.jsonl")" -eq 1 ]]; then
  pass "rejected rows store nothing"
else
  fail "rejected rows store nothing"
fi

# --since keeps a row whose nested ts is older but top-level ts is newer
printf '{"obs_id":"n","ctx":{"ts":"2026-01-01T00:00:00Z"},"ts":"2026-10-21T10:00:00Z"}\n' \
  | (cd "$REPO" && bash "$LOCAL/append.sh")
if grep -q '"obs_id":"n"' <<<"$(cd "$REPO" && bash "$LOCAL/read.sh" --since 2026-10-21T00:00:00Z)"; then
  pass "read.sh --since compares the top-level ts"
else
  fail "read.sh --since compares the top-level ts"
fi

# the mkdir lock (flock and perl hidden from PATH): released after an append and on
# TERM, and a lock left by a dead holder fails fast and stores nothing
NOFLOCK="$TEST_TMPDIR/noflock-bin"
mkdir -p "$NOFLOCK"
for t in bash git jq mkdir rmdir rm mv cat sleep mktemp sync find wc grep; do
  p="$(command -v "$t")" && ln -sf "$p" "$NOFLOCK/$t"
done
nf_append() { (cd "$REPO" && PATH="$NOFLOCK" bash "$LOCAL/append.sh"); }
printf '{"obs_id":"nf1","ts":"2026-10-21T00:00:03Z"}\n' | nf_append
expect_exit 0 $? "append.sh without flock exits 0"
if [[ ! -e "$REPO/.work/buffer/.lockdir" ]]; then
  pass "the mkdir lock is released after an append"
else
  fail "the mkdir lock is released after an append"
fi

# TERM while waiting on a live holder: the waiter never held the lock, so the
# holder's lock stays; TERM to the holder side is the trap path below.
mkdir "$REPO/.work/buffer/.lockdir"
printf '%s\n' "$$" >"$REPO/.work/buffer/.lockdir/pid"
(cd "$REPO" && PATH="$NOFLOCK" exec bash "$LOCAL/append.sh" <<<'{"obs_id":"nf-wait","ts":"2026-10-21T00:00:05Z"}') 2>/dev/null &
waiter=$!
sleep 0.5
kill -TERM "$waiter" 2>/dev/null
wait "$waiter" 2>/dev/null
if [[ "$(cat "$REPO/.work/buffer/.lockdir/pid" 2>/dev/null)" == "$$" ]]; then
  pass "a TERMed waiter leaves another holder's lock in place"
else
  fail "a TERMed waiter leaves another holder's lock in place"
fi
rm -rf "$REPO/.work/buffer/.lockdir"

# TERM to a holder: a slow sync stub keeps the holder inside the lock; bash runs
# the TERM trap once the stub returns, and the EXIT trap releases the lock.
SLOW="$TEST_TMPDIR/slow-bin"
mkdir -p "$SLOW"
cp -P "$NOFLOCK"/* "$SLOW"/
rm -f "$SLOW/sync"
printf '#!%s\nexec %s 2\n' "$(command -v bash)" "$(command -v sleep)" >"$SLOW/sync"
chmod +x "$SLOW/sync"
(cd "$REPO" && PATH="$SLOW" exec bash "$LOCAL/append.sh" <<<'{"obs_id":"nf-term","ts":"2026-10-21T00:00:06Z"}') 2>/dev/null &
holder=$!
for _ in $(seq 1 50); do
  [[ -f "$REPO/.work/buffer/.lockdir/pid" ]] && break
  sleep 0.1
done
kill -TERM "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
if [[ ! -e "$REPO/.work/buffer/.lockdir" ]]; then
  pass "the mkdir lock is released when its holder gets TERM"
else
  fail "the mkdir lock is released when its holder gets TERM"
  rm -rf "$REPO/.work/buffer/.lockdir"
fi

sleep 0 &
dead=$!
wait "$dead"
mkdir "$REPO/.work/buffer/.lockdir"
printf '%s\n' "$dead" >"$REPO/.work/buffer/.lockdir/pid"
before="$(wc -l <"$REPO/.work/buffer/findings.jsonl")"
start=$SECONDS
ERR="$(printf '{"obs_id":"nf2","ts":"2026-10-21T00:00:04Z"}\n' | nf_append 2>&1 >/dev/null)"
RC=$?
if [[ $RC -eq 1 && $((SECONDS - start)) -lt 5 && "$ERR" == *".lockdir is stale"*"remove it"* \
  && "$(wc -l <"$REPO/.work/buffer/findings.jsonl")" -eq "$before" ]]; then
  pass "a dead holder's lock fails fast, names the lock and stores nothing"
else
  fail "a dead holder's lock fails fast, names the lock and stores nothing" "exit $RC after $((SECONDS - start))s: $ERR"
fi
rm -rf "$REPO/.work/buffer/.lockdir"

# perl's flock (flock hidden from PATH, perl present): it locks .lock, an append
# after a SIGKILLed holder succeeds, and parallel appends never share the lock
if perl -MConfig -MFcntl=:flock -e 'exit !$Config{d_flock}' >/dev/null 2>&1; then
  PERLBIN="$TEST_TMPDIR/perl-bin"
  mkdir -p "$PERLBIN"
  cp -P "$NOFLOCK"/* "$PERLBIN"/
  ln -sf "$(command -v perl)" "$PERLBIN/perl"
  PREPO="$TEST_TMPDIR/perl-repo"
  git init -q -b main "$PREPO" >/dev/null 2>&1
  pl_append() { (cd "$PREPO" && PATH="$PERLBIN" bash "$LOCAL/append.sh"); }
  printf '{"obs_id":"pl1","ts":"2026-10-21T00:00:07Z"}\n' | pl_append
  RC=$?
  if [[ $RC -eq 0 && -f "$PREPO/.work/buffer/.lock" ]]; then
    pass "append.sh without flock takes perl's flock on .lock"
  else
    fail "append.sh without flock takes perl's flock on .lock" "exit $RC"
  fi

  # A slow sync stub keeps the holder inside the lock and records the processes
  # holding it: the shell that took the lock (its parent) and itself, as fd 9 is
  # inherited. SIGKILL to all of them is a holder that dies without cleanup.
  SLOWPERL="$TEST_TMPDIR/slow-perl-bin"
  INSIDE="$TEST_TMPDIR/inside"
  mkdir -p "$SLOWPERL"
  cp -P "$PERLBIN"/* "$SLOWPERL"/
  rm -f "$SLOWPERL/sync"
  cat >"$SLOWPERL/sync" <<EOF
#!$(command -v bash)
printf '%s %s\n' "\$PPID" "\$\$" >"$INSIDE"
exec $(command -v sleep) 10
EOF
  chmod +x "$SLOWPERL/sync"
  (cd "$PREPO" && PATH="$SLOWPERL" exec bash "$LOCAL/append.sh" <<<'{"obs_id":"pl-kill","ts":"2026-10-21T00:00:08Z"}') 2>/dev/null &
  holder=$!
  for _ in $(seq 1 50); do
    [[ -s "$INSIDE" ]] && break
    sleep 0.1
  done
  lock_shell="" stub=""
  [[ -s "$INSIDE" ]] && read -r lock_shell stub <"$INSIDE"
  kill -KILL "$holder" "${lock_shell:-$holder}" "${stub:-$holder}" 2>/dev/null
  wait "$holder" 2>/dev/null
  start=$SECONDS
  ERR="$(printf '{"obs_id":"pl2","ts":"2026-10-21T00:00:09Z"}\n' | pl_append 2>&1 >/dev/null)"
  RC=$?
  if [[ $RC -eq 0 && $((SECONDS - start)) -lt 5 \
    && "$(grep -c '"obs_id":"pl2"' "$PREPO/.work/buffer/findings.jsonl")" -eq 1 ]]; then
    pass "without flock, an append after a SIGKILLed holder exits 0 and stores its row"
  else
    fail "without flock, an append after a SIGKILLed holder exits 0 and stores its row" "exit $RC after $((SECONDS - start))s: $ERR"
  fi
  rm -rf "$PREPO/.work/buffer/.lockdir"

  # A sync stub that finds another appender inside the lock records an overlap;
  # each appender stays inside long enough for one to show.
  PARPERL="$TEST_TMPDIR/par-perl-bin"
  MARK="$TEST_TMPDIR/inside-lock"
  OVERLAP="$TEST_TMPDIR/overlap"
  mkdir -p "$PARPERL"
  cp -P "$PERLBIN"/* "$PARPERL"/
  rm -f "$PARPERL/sync"
  cat >"$PARPERL/sync" <<EOF
#!$(command -v bash)
$(command -v mkdir) "$MARK" 2>/dev/null || echo overlap >>"$OVERLAP"
$(command -v sleep) 0.2
$(command -v rmdir) "$MARK" 2>/dev/null
exit 0
EOF
  chmod +x "$PARPERL/sync"
  N=12
  for i in $(seq 1 $N); do
    printf '{"obs_id":"p%d-a","ts":"2026-10-21T00:00:10Z"}\n{"obs_id":"p%d-b","ts":"2026-10-21T00:00:10Z"}\n' \
      "$i" "$i" >"$TEST_TMPDIR/par-$i.jsonl"
  done
  pids=()
  for i in $(seq 1 $N); do
    (cd "$PREPO" && PATH="$PARPERL" bash "$LOCAL/append.sh") <"$TEST_TMPDIR/par-$i.jsonl" 2>/dev/null &
    pids+=($!)
  done
  bad=0
  for p in "${pids[@]}"; do wait "$p" || bad=$((bad + 1)); done
  ids="$(jq -rR 'fromjson | .obs_id' "$PREPO/.work/buffer/findings.jsonl" 2>/dev/null)"
  RC=$?
  off=""
  for i in $(seq 1 $N); do
    for s in a b; do
      cnt="$(grep -cx "p$i-$s" <<<"$ids")"
      [[ "$cnt" == 1 ]] || off="$off p$i-$s(x$cnt)"
    done
  done
  if [[ $bad -eq 0 && $RC -eq 0 && -z "$off" && ! -e "$OVERLAP" ]]; then
    pass "without flock, $N parallel appends never share the lock, and every row is stored once, whole"
  else
    fail "without flock, $N parallel appends never share the lock, and every row is stored once, whole" \
      "$bad call(s) failed, jq exit $RC, off:$off, overlaps: $(wc -l 2>/dev/null <"$OVERLAP" || echo 0)"
  fi
else
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - perl flock checks # SKIP no perl with native flock(2)\n' "$CASE_NUM"
fi

# the buffer is git-ignored, and symlinks never redirect rows or truncate the lock
LREPO="$TEST_TMPDIR/links"
git init -q -b main "$LREPO" >/dev/null 2>&1
la() { (cd "$LREPO" && bash "$LOCAL/append.sh" >/dev/null 2>&1); }
printf '{"obs_id":"g","ts":"2026-10-21T00:00:00Z"}\n' | la
if [[ "$(cat "$LREPO/.work/buffer/.gitignore" 2>/dev/null)" == "*" \
  && -z "$(git -C "$LREPO" status --porcelain --untracked-files=all)" ]]; then
  pass "first append writes .work/buffer/.gitignore with *, so git sees no rows"
else
  fail "first append writes .work/buffer/.gitignore with *, so git sees no rows"
fi
rm -f "$LREPO/.work/buffer/.gitignore"
printf '{"obs_id":"g2","ts":"2026-10-21T00:00:00Z"}\n' | la
if [[ "$(cat "$LREPO/.work/buffer/.gitignore" 2>/dev/null)" == "*" ]]; then
  pass "an append restores a missing .gitignore in an existing buffer directory"
else
  fail "an append restores a missing .gitignore in an existing buffer directory"
fi
GI_OUT="$TEST_TMPDIR/gitignore-target"
rm -f "$LREPO/.work/buffer/.gitignore" "$GI_OUT"
ln -s "$GI_OUT" "$LREPO/.work/buffer/.gitignore"
printf '{"obs_id":"g3","ts":"2026-10-21T00:00:00Z"}\n' | la
RC=$?
if [[ $RC -eq 2 && ! -e "$GI_OUT" ]]; then
  pass "append.sh refuses a symlinked .gitignore and writes nothing through it"
else
  fail "append.sh refuses a symlinked .gitignore and writes nothing through it" "exit $RC"
fi
rm -f "$LREPO/.work/buffer/.gitignore"
if command -v flock >/dev/null 2>&1; then
  printf 'keep\n' >"$LREPO/.work/buffer/.lock"
  printf '{"obs_id":"g2","ts":"2026-10-21T00:00:00Z"}\n' | la
  if [[ "$(cat "$LREPO/.work/buffer/.lock")" == "keep" ]]; then
    pass "the flock path does not truncate .lock"
  else
    fail "the flock path does not truncate .lock"
  fi
fi
OUTSIDE="$TEST_TMPDIR/outside.jsonl"
: >"$OUTSIDE"
mv "$LREPO/.work/buffer/findings.jsonl" "$LREPO/.work/buffer/real.jsonl"
ln -s "$OUTSIDE" "$LREPO/.work/buffer/findings.jsonl"
printf '{"obs_id":"s1","ts":"2026-10-21T00:00:00Z"}\n' | la
RC=$?
if [[ $RC -eq 2 && ! -s "$OUTSIDE" ]]; then
  pass "append.sh refuses a symlinked findings.jsonl and stores nothing"
else
  fail "append.sh refuses a symlinked findings.jsonl and stores nothing" "exit $RC"
fi
(cd "$LREPO" && bash "$LOCAL/read.sh" >/dev/null 2>&1)
expect_exit 2 $? "read.sh refuses a symlinked findings.jsonl"
OUTDIR="$TEST_TMPDIR/outside-dir"
mkdir -p "$OUTDIR"
rm -rf "$LREPO/.work/buffer"
ln -s "$OUTDIR" "$LREPO/.work/buffer"
printf '{"obs_id":"s2","ts":"2026-10-21T00:00:00Z"}\n' | la
RC=$?
if [[ $RC -eq 2 && -z "$(ls -A "$OUTDIR")" ]]; then
  pass "append.sh refuses a symlinked .work/buffer and writes nothing there"
else
  fail "append.sh refuses a symlinked .work/buffer and writes nothing there" "exit $RC"
fi

# outside a repository
NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$LOCAL/read.sh" >/dev/null 2>&1)
expect_exit 3 $? "read.sh outside a repository exits 3"

printf '1..%d\n' "$CASE_NUM"
[[ $FAILED -eq 0 ]]
