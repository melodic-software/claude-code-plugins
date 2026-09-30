#!/usr/bin/env bash
# Self-contained tests for jvm-references.sh, the Gradle and Maven reader
# map-dependencies uses (assertion primitives are duplicated on purpose, per
# docs/conventions/shell-test-helpers/README.md).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/jvm-references.sh"
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

# shellcheck source=jvm-references.sh
source "$LIB"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

T=$'\t'

# Groovy settings.
groovy="$TEST_TMPDIR/settings.gradle"
cat >"$groovy" <<'EOF'
rootProject.name = "demo" // the name
include ':app', ':core'
include(
  ":lib:util", // nested
  ":lib:net"
)
include 'a',
        'b'
/* include 'commented' */
include 'after'
include "plain"
EOF
records="$(jvm_settings_records "$groovy")"
assert_contains "a Groovy include is read with its declaration" "$records" "include${T}:app${T}include ':app', ':core'"
assert_contains "every argument of one include is read" "$records" "include${T}:core${T}include ':app', ':core'"
assert_contains "a parenthesized include over several lines is one declaration" "$records" "include${T}:lib:util${T}include( \":lib:util\", \":lib:net\" )"
assert_contains "a Groovy include continued after a trailing comma is one declaration" "$records" "include${T}b${T}include 'a', 'b'"
assert_not_contains "an include inside a block comment is skipped" "$records" "commented"
assert_contains "an include after a comment line is read" "$records" "include${T}after${T}"
assert_contains "a double-quoted literal is read" "$records" "include${T}plain${T}"
assert_not_contains "a settings file with only literals has no unread line" "$records" "unread"

# Kotlin DSL settings.
kts="$TEST_TMPDIR/settings.gradle.kts"
cat >"$kts" <<'EOF'
rootProject.name = "demo"
include(":app")
include(":x", ":y") // trailing
val url = "http://example.com//path"; include(":after")
EOF
records="$(jvm_settings_records "$kts")"
assert_contains "a Kotlin include is read" "$records" "include${T}:app${T}include(\":app\")"
assert_contains "a Kotlin include with two arguments reads both" "$records" "include${T}:y${T}include(\":x\", \":y\")"
assert_not_contains "a // inside a string is not a comment" "$records" "include${T}:after${T}"
assert_contains "a statement that shares a line with other code is unread" "$records" "unread${T}val url = \"http://example.com//path\"; include(\":after\")"

# Settings shapes the reader does not read.
odd="$TEST_TMPDIR/odd/settings.gradle"
mkdir -p "$TEST_TMPDIR/odd"
cat >"$odd" <<'EOF'
include(modules)
include(":x$y")
include(*names)
includeBuild("../other")
includeFlat 'flat'
["p", "q"].each { include(":$it") }
for (n in names) { include(n) }
project(':app').projectDir = file('custom/app')
project(":app").name = "renamed"
apply from: 'more-settings.gradle'
if (flag) include 'cond'
include("mixed", other)
include(
  "open"
EOF
records="$(jvm_settings_records "$odd")"
assert_contains "an include of a variable is unread" "$records" "unread${T}include(modules)"
assert_contains "an interpolated string is unread" "$records" "unread${T}include(\":x\$y\")"
assert_contains "a spread is unread" "$records" "unread${T}include(*names)"
assert_contains "includeBuild is unread" "$records" "unread${T}includeBuild(\"../other\")"
assert_contains "includeFlat is unread" "$records" "unread${T}includeFlat 'flat'"
assert_contains "a Groovy each loop is unread" "$records" "unread${T}[\"p\", \"q\"].each { include(\":\$it\") }"
assert_contains "a for loop is unread" "$records" "unread${T}for (n in names) { include(n) }"
assert_contains "a projectDir assignment is unread" "$records" "unread${T}project(':app').projectDir = file('custom/app')"
assert_contains "a project rename is unread" "$records" "unread${T}project(\":app\").name = \"renamed\""
assert_contains "apply from is unread" "$records" "unread${T}apply from: 'more-settings.gradle'"
assert_contains "a conditional include is unread" "$records" "unread${T}if (flag) include 'cond'"
assert_contains "the literal part of a mixed include is still read" "$records" "include${T}mixed${T}include(\"mixed\", other)"
assert_contains "the computed part of a mixed include is unread" "$records" "unread${T}include(\"mixed\", other)"
assert_contains "an unterminated include is unread" "$records" "unread${T}<unterminated include> include( \"open\""
assert_not_contains "an unread include gives no include line for its variable" "$records" "include${T}modules"

# Build files.
build="$TEST_TMPDIR/build.gradle.kts"
cat >"$build" <<'EOF'
dependencies {
    implementation(project(":core"))
    api(project(path = ":lib:util", configuration = "x"))
    testImplementation(project(":a"), project(":b"))
    implementation(libs.junit)
    implementation project('grp')
    implementation(rootProject.project(":r"))
    // implementation(project(":commented"))
}
EOF
records="$(jvm_build_records "$build")"
assert_contains "project(':x') is a project line" "$records" "project${T}:core${T}implementation(project(\":core\"))"
assert_contains "project(path = ':x') is a project line" "$records" "project${T}:lib:util${T}api(project(path = \":lib:util\", configuration = \"x\"))"
assert_contains "two references on one line are both read" "$records" "project${T}:a${T}"
assert_contains "the second reference on the line is read" "$records" "project${T}:b${T}"
assert_contains "a Groovy reference without parentheses is read" "$records" "project${T}grp${T}implementation project('grp')"
assert_contains "a rootProject.project reference is read" "$records" "project${T}:r${T}"
assert_not_contains "a reference in a comment is skipped" "$records" "commented"
assert_not_contains "a version catalog accessor is not a project line" "$records" "junit"

groovy_build="$TEST_TMPDIR/build.gradle"
cat >"$groovy_build" <<'EOF'
dependencies {
    implementation project(':core')
    implementation project(path: ':lib', configuration: 'shadow')
    implementation projects.core
    implementation(projects.commons.utils)
    implementation(project(name))
    implementation(project("$x"))
    implementation(project(':a').sourceSets.main.output)
    project(':app').afterEvaluate { }
    implementation(project(
}
EOF
records="$(jvm_build_records "$groovy_build")"
assert_contains "a Groovy project(':x') is read" "$records" "project${T}:core${T}implementation project(':core')"
assert_contains "a Groovy project(path: ':x') is read" "$records" "project${T}:lib${T}"
assert_contains "a type-safe accessor is unread" "$records" "unread${T}implementation projects.core"
assert_contains "a nested type-safe accessor is unread" "$records" "unread${T}implementation(projects.commons.utils)"
assert_contains "a project() of a variable is unread" "$records" "unread${T}implementation(project(name))"
assert_contains "an interpolated project() is unread" "$records" "unread${T}implementation(project(\"\$x\"))"
assert_contains "project() used as a receiver is unread" "$records" "unread${T}implementation(project(':a').sourceSets.main.output)"
assert_contains "project() used as a receiver in a statement is unread" "$records" "unread${T}project(':app').afterEvaluate { }"
assert_contains "a project( that leaves the line is unread" "$records" "unread${T}implementation(project("
assert_not_contains "an unread receiver reference draws no project line" "$records" "project${T}:a${T}"

# Maven.
pom="$TEST_TMPDIR/pom.xml"
cat >"$pom" <<'EOF'
<?xml version="1.0"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><artifactId>par</artifactId></parent>
  <artifactId>agg</artifactId>
  <!-- <modules><module>commented</module></modules> -->
  <modules>
    <module>core</module><module> api </module>
    <module>${moduleName}</module>
    <module>
      multi
    </module>
    <module>third/pom-example.xml</module>
    <module></module>
  </modules>
  <profiles><profile><id>p</id><modules><module>prof</module></modules></profile></profiles>
  <build><plugins><plugin><configuration><modules><module>nope</module></modules></configuration></plugin></plugins></build>
</project>
EOF
records="$(jvm_pom_records "$pom")"
assert_contains "the project artifactId is the name, not the parent's" "$records" "name${T}agg"
assert_not_contains "the parent artifactId is not read as the name" "$records" "name${T}par"
assert_contains "a module is read with its declaration" "$records" "module${T}core${T}<module>core</module>"
assert_contains "two modules on one line are both read, trimmed" "$records" "module${T}api${T}<module>api</module>"
assert_contains "a module spread over lines is read" "$records" "module${T}multi${T}<module>multi</module>"
assert_contains "a module naming a pom file is read as written" "$records" "module${T}third/pom-example.xml${T}"
assert_contains "a module inside a profile is read" "$records" "module${T}prof${T}"
assert_not_contains "a module inside an XML comment is skipped" "$records" "commented"
assert_not_contains "a module inside a plugin configuration is skipped" "$records" "nope"
assert_contains "a property module is unread" "$records" "unread${T}<module>\${moduleName}</module>"
assert_contains "an empty module is unread" "$records" "unread${T}<module></module>"

printf '<project xmlns:m="x"><m:artifactId>ns</m:artifactId><m:modules><m:module>one</m:module></m:modules></project>\n' >"$TEST_TMPDIR/ns.xml"
assert_contains "a prefixed module element is read" "$(jvm_pom_records "$TEST_TMPDIR/ns.xml")" "module${T}one${T}"

assert_equals "a missing settings file gives nothing" "$(jvm_settings_records "$TEST_TMPDIR/absent")" ""
assert_equals "a missing build file gives nothing" "$(jvm_build_records "$TEST_TMPDIR/absent")" ""
assert_equals "a missing pom gives nothing" "$(jvm_pom_records "$TEST_TMPDIR/absent")" ""

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
