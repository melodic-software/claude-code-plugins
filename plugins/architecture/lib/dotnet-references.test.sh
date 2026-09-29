#!/usr/bin/env bash
# Self-contained tests for dotnet-references.sh, the reader map-dependencies and
# map-landscape share (assertion primitives are duplicated on purpose, per
# docs/conventions/shell-test-helpers/README.md).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/dotnet-references.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

# shellcheck source=dotnet-references.sh
source "$LIB"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

reads="$TEST_TMPDIR/reads.csproj"
cat >"$reads" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <!-- <ProjectReference Include="Commented.csproj" /> -->
  <!--
    <PackageReference Include="MultiLineCommented" />
  -->
  <ItemGroup>
    <PackageReference Include="Serilog" Version="4.0.0" />
    <ProjectReference Condition="'$(Configuration)'=='Debug'" Include="..\Lib\Lib.csproj" />
    <PackageReference Update="Skipped" Version="1.0.0" />
    <PackageReference Remove="Removed" />
    <PackageReference Include='SingleQuoted' />
    <ProjectReference
        Include="multiline.csproj" />
    <ProjectReference
        Condition="'$(A)' > '1'"
        PrivateAssets="all"
        Include="gt-in-attribute.csproj"
    />
    <PackageReference Include="MediatR" Version="12.0.0" /><ProjectReference Include="Helper.csproj" />
    <PackageReference Include="WithChild">
      <Version>1.0.0</Version>
    </PackageReference>
    <PackageReferenceLookalike Include="Lookalike" />
  </ItemGroup>
</Project>
CSPROJ
shared="$(dotnet_reference_includes "$reads")"
for want in Serilog '..\Lib\Lib.csproj' SingleQuoted multiline.csproj gt-in-attribute.csproj MediatR Helper.csproj WithChild; do
  assert_contains "reads $want" "$shared" "$want"
done
for unwanted in Commented.csproj MultiLineCommented Skipped Removed Lookalike; do
  assert_not_contains "does not read $unwanted" "$shared" "$unwanted"
done
assert_equals "the Include list is in file order" "$(printf '%s\n' "$shared" | head -n 3 | tr '\n' ' ')" 'Serilog ..\Lib\Lib.csproj SingleQuoted '

records="$(dotnet_reference_records "$reads")"
assert_contains "a package record carries its kind" "$records" "package"$'\t'"Serilog"$'\t''<PackageReference Include="Serilog" Version="4.0.0" />'
assert_contains "a project record carries its kind" "$records" "project"$'\t'"Helper.csproj"$'\t''<ProjectReference Include="Helper.csproj" />'
assert_contains "a multi-line tag is one line in its declaration" "$records" '<ProjectReference Include="multiline.csproj" />'
assert_contains "a tag with a child element stops at the end of the start tag" "$records" "package"$'\t'"WithChild"$'\t''<PackageReference Include="WithChild">'
assert_equals "every record is one line" "$(printf '%s\n' "$records" | grep -c .)" "8"

assert_equals "a missing file has no records" "$(dotnet_reference_records "$TEST_TMPDIR/absent.csproj")" ""
assert_equals "a missing file has an unmatched count of 0" "$(dotnet_reference_unmatched_count "$TEST_TMPDIR/absent.csproj")" "0"

assert_equals "a file with only read references has an unmatched count of 0" "$(dotnet_reference_unmatched_count "$reads")" "0"

unread="$TEST_TMPDIR/unread.csproj"
cat >"$unread" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <!-- <FrameworkReference Include="InsideAComment" /> -->
  <ItemGroup>
    <PackageReference Include="Read" />
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
    <PackageReference Version="1.0.0" />
    <ProjectReference Include="" />
    <GlobalPackageReference Include="Global" Version="1.0.0" />
    <PackageReference Update="Modifier" Version="1.0.0" />
    <ReferenceOutputAssembly>false</ReferenceOutputAssembly>
  </ItemGroup>
</Project>
CSPROJ
assert_equals "reference-like tags with no record are counted" "$(dotnet_reference_unmatched_count "$unread")" "4"
assert_equals "the counted file still reads its one reference" "$(dotnet_reference_includes "$unread")" "Read"

crlf="$TEST_TMPDIR/crlf.csproj"
printf '<Project>\r\n  <ProjectReference\r\n    Include="a.csproj"\r\n  />\r\n</Project>\r\n' >"$crlf"
assert_equals "CRLF line endings read the same" "$(dotnet_reference_includes "$crlf")" "a.csproj"

torn="$TEST_TMPDIR/torn.csproj"
printf '<Project>\n<PackageReference Include="Torn />\n<PackageReference Include="After" />\n</Project>\n' >"$torn"
assert_equals "an unterminated quote is counted, not silently dropped" "$(dotnet_reference_unmatched_count "$torn")" "1"

unterminated="$TEST_TMPDIR/unterminated-comment.csproj"
printf '<Project>\n<PackageReference Include="Before" />\n<!-- never closed\n<PackageReference Include="Hidden" />\n' >"$unterminated"
assert_equals "an unterminated comment hides what follows it" "$(dotnet_reference_includes "$unterminated")" "Before"

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
