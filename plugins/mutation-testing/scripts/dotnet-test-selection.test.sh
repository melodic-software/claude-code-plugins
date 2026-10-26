#!/usr/bin/env bash
# Black-box contract test for dotnet-test-selection.sh.
#
# Self-contained and cwd-independent; works on copies in its own mktemp dir, so
# a dotnet build writes nothing into the plugin. Every expected line below is
# written from the fixture's source, not from running the script. The dotnet
# section runs the printed line through `dotnet test` and skips, printing why,
# when dotnet is not on PATH.
# test-scope: plugins/mutation-testing/scripts/fixtures/dotnet-test-selection/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/dotnet-test-selection.sh"
FIXTURE="$SCRIPT_DIR/fixtures/dotnet-test-selection"

WORK="$(mktemp -d)" || exit 1
WORK="$(cd "$WORK" && pwd -P)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# The fixture: Shop.Tests holds CalculatorTests (2 tests, and 1 in its nested
# Negatives class) and CalculatorTestsExtra (2), whose name extends it;
# Shop.Specs holds DiscountSpecs (2) and RoundingSpecs (1) in one file, and
# OtherSpecs (1).
FX="$WORK/fx"
cp -R "$FIXTURE" "$FX" || exit 1
TESTS="$FX/tests/Shop.Tests"
SPECS="$FX/tests/Shop.Specs"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# run <file>...: run the script from /, so every project path prints absolute.
out=""
code=0
run() {
  out="$(cd / && bash "$SUT" "$@" 2>"$WORK/err")"
  code=$?
}

expect() { # expect <label> <exit> <whole stdout>
  if [[ "$code" -eq "$2" && "$out" == "$3" ]]; then
    pass "$1"
  else
    fail "$1 - want exit $2 and [$3], got exit $code: [$out] $(cat "$WORK/err")"
  fi
}

# One test file from each project.
L1="'$TESTS/Shop.Tests.csproj' --filter 'FullyQualifiedName~Shop.Tests.CalculatorTests.|FullyQualifiedName~Shop.Tests.CalculatorTests+'"
L2="'$SPECS/Shop.Specs.csproj' --filter 'FullyQualifiedName~Shop.Specs.DiscountSpecs.|FullyQualifiedName~Shop.Specs.RoundingSpecs.'"
run "$TESTS/CalculatorTests.cs" "$SPECS/DiscountSpecs.cs"
expect "one file from each project prints one line per project" 0 "$L1"$'\n'"$L2"
shape=0
lines=0
while IFS= read -r l; do
  lines=$((lines + 1))
  [[ "$l" == "'"*".csproj' --filter 'FullyQualifiedName~"* ]] && shape=$((shape + 1))
done <<<"$out"
if ((lines == 2 && shape == 2)); then
  pass "exactly two lines, each a quoted .csproj path and a FullyQualifiedName filter"
else
  fail "want two lines of the project-and-filter shape, got $lines lines, $shape of that shape: $out"
fi

# Two files of one project share a line, in first-seen order; a repeat adds nothing.
run "$TESTS/CalculatorTestsExtra.cs" "$TESTS/CalculatorTests.cs" "$TESTS/CalculatorTestsExtra.cs"
expect "files of one project share one line" 0 \
  "'$TESTS/Shop.Tests.csproj' --filter 'FullyQualifiedName~Shop.Tests.CalculatorTestsExtra.|FullyQualifiedName~Shop.Tests.CalculatorTests.|FullyQualifiedName~Shop.Tests.CalculatorTests+'"

# A project under the working directory prints relative to it.
out="$(cd "$FX" && bash "$SUT" tests/Shop.Specs/OtherSpecs.cs 2>"$WORK/err")"
code=$?
expect "a project under the working directory prints relative" 0 \
  "'tests/Shop.Specs/Shop.Specs.csproj' --filter 'FullyQualifiedName~Shop.Specs.OtherSpecs.'"

# Synthetic sources, in a tree of their own so the dotnet run below sees the
# fixture alone. The script reads a project file's presence, not its content.
SYN="$WORK/syn/App.Tests"
mkdir -p "$SYN/Deep/Er" || exit 1
: >"$SYN/App.Tests.csproj"
P="'$SYN/App.Tests.csproj' --filter"
src() { # src <name> <content>: write a source file and print its path
  printf '%s' "$2" >"$SYN/$1"
  printf '%s' "$SYN/$1"
}

run "$(src Deep/Er/Walk.cs 'namespace App.Deep { public class Walk { } }')"
expect "the nearest project above a nested directory owns the file" 0 "$P 'FullyQualifiedName~App.Deep.Walk.'"

run "$(src Blocks.cs 'namespace A { namespace B { class C { class Inner { } } } class D { } }')"
expect "nested namespace blocks join; a nested class adds its outer class's + term" 0 \
  "$P 'FullyQualifiedName~A.B.C.|FullyQualifiedName~A.B.C+|FullyQualifiedName~A.D.'"

run "$(src Loose.cs 'public class Loose { }')"
expect "a class in no namespace is its bare name" 0 "$P 'FullyQualifiedName~Loose.'"

run "$(src Kinds.cs 'namespace K;
public interface IThing { }
public struct Point { }
public record Rec(int X);
public class Holder<T> where T : class
{
}
public class Pair<T, U> where T : class where U : struct { }')"
expect "only classes count, a generic one takes no trailing dot, a class constraint is no class" 0 \
  "$P 'FullyQualifiedName~K.Holder|FullyQualifiedName~K.Pair'"

run "$(src Literals.cs 'namespace V;
#region Hidden
/* a block comment
   class Hidden { */
public class Visible
{
    private const string A = @"class Fake { ""quoted"" }";
    private const string B = """
        class Raw { {
        """;
    private const char C = '"'"'}'"'"';
    private const string D = @"""";
    private const string E = """"
        has """ inside { class Quad
        """";
}
#endregion
public class Second { }')"
expect "comments, literals and preprocessor lines hide classes and braces" 0 \
  "$P 'FullyQualifiedName~V.Visible.|FullyQualifiedName~V.Second.'"

run "$(src Crlf.cs $'namespace W;\r\npublic class Crlf\r\n{\r\n}\r\npublic sealed partial class After { }\r\n')"
expect "CRLF line endings read the same" 0 "$P 'FullyQualifiedName~W.Crlf.|FullyQualifiedName~W.After.'"

run "$(src Verbatim.cs 'namespace X { public class @Y { } }')"
expect "a verbatim identifier drops its @" 0 "$P 'FullyQualifiedName~X.Y.'"

src Eq=Sign.cs 'namespace E; public class EqTests { }' >/dev/null
out="$(cd "$SYN" && bash "$SUT" Eq=Sign.cs 2>"$WORK/err")"
code=$?
expect "a relative file name with = is read as a file, not an awk assignment" 0 \
  "'App.Tests.csproj' --filter 'FullyQualifiedName~E.EqTests.'"

# A path with a single quote survives the shell: the line evaluates to three words.
Q="$WORK/it's here/Q.Tests"
mkdir -p "$Q" || exit 1
: >"$Q/Q.Tests.csproj"
printf 'namespace Q;\npublic class QTests { }\n' >"$Q/QTests.cs"
run "$Q/QTests.cs"
eval "set -- $out"
if [[ "$code" -eq 0 && $# -eq 3 && "$1" == "$Q/Q.Tests.csproj" && "$2" == --filter && "$3" == 'FullyQualifiedName~Q.QTests.' ]]; then
  pass "a single quote in the project path is quoted"
else
  fail "a single quote in the project path - got exit $code: $out"
fi

# Refusals print nothing.
run
expect "no argument is a usage error" 2 ""
run "$SYN/absent.cs"
expect "a missing file refuses" 1 ""
mkdir -p "$WORK/loose" || exit 1
printf 'namespace L;\npublic class LTests { }\n' >"$WORK/loose/LTests.cs"
run "$TESTS/CalculatorTests.cs" "$WORK/loose/LTests.cs"
expect "a file with no project above it refuses the whole run" 1 ""
mkdir -p "$WORK/two" || exit 1
: >"$WORK/two/A.csproj"
: >"$WORK/two/B.csproj"
printf 'namespace T;\npublic class TTests { }\n' >"$WORK/two/TTests.cs"
run "$WORK/two/TTests.cs"
expect "two projects in the nearest directory refuse" 1 ""
run "$(src NoClass.cs 'namespace N; public interface INothing { }')"
expect "a file with no top-level class refuses" 1 ""

# The dotnet run: line one names Shop.Tests (5 tests) but selects only
# CalculatorTests and its nested class (3); line two names Shop.Specs (4) and
# selects DiscountSpecs and RoundingSpecs (3).
if ! command -v dotnet >/dev/null 2>&1; then
  printf 'skip - dotnet test on the fixture: dotnet is not on PATH\n'
else
  export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 MSBUILDDISABLENODEREUSE=1
  # Read where the tests build, so a global.json above the caller pins nothing.
  version="$(cd "$WORK" && dotnet --version 2>/dev/null)"
  major="${version%%.*}"
  if [[ ! "$major" =~ ^[0-9]+$ ]]; then
    fail "dotnet --version printed no major version: $version"
  else
    # Target the installed SDK's own runtime, which can run the tests.
    for p in "$FX/src/Shop/Shop.csproj" "$TESTS/Shop.Tests.csproj" "$SPECS/Shop.Specs.csproj"; do
      if ! sed "s#<TargetFramework>net8.0</TargetFramework>#<TargetFramework>net$major.0</TargetFramework>#" "$p" >"$p.tmp" ||
        ! mv "$p.tmp" "$p" || ! grep -q "<TargetFramework>net$major.0</TargetFramework>" "$p"; then
        fail "retargeting $p to net$major.0"
      fi
    done
    run "$TESTS/CalculatorTests.cs" "$SPECS/DiscountSpecs.cs"
    n=0
    for want in 3 3; do
      n=$((n + 1))
      line="$(sed -n "${n}p" <<<"$out")"
      res="$WORK/results-$n"
      # The output goes to a file: a build server left running would hold a
      # command substitution's pipe open.
      if ! (cd "$WORK" && eval "dotnet test $line --logger 'trx;LogFileName=line$n.trx' --results-directory '$res'") >"$WORK/dotnet-$n.log" 2>&1; then
        fail "dotnet test on line $n exited non-zero: $(tail -n 20 "$WORK/dotnet-$n.log")"
        continue
      fi
      trx="$(find "$res" -name 'line*.trx' | head -n 1)"
      got=""
      [[ -z "$trx" ]] || got="$(sed -n 's/.*<Counters [^>]*passed="\([0-9][0-9]*\)".*/\1/p' "$trx" | head -n 1)"
      if [[ "$got" == "$want" ]]; then
        pass "dotnet test on line $n passes $want tests, the file's classes, not the whole project"
      else
        fail "dotnet test on line $n - want $want passed, got [$got] from [${trx:-no trx}]"
      fi
    done
    dotnet build-server shutdown >/dev/null 2>&1
  fi
fi

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'all passed\n'
