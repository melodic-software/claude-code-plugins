#!/usr/bin/env bash
# Tests for collect-data.sh and render-data.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-data.sh"
RENDER="$SCRIPT_DIR/render-data.sh"
DIALECT="$SCRIPT_DIR/resolve-data-dialect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
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

init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
}

commit_all() {
  local dir="$1"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "fixture"
}

help_out="$(bash "$COLLECT" --help)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: schema_version" "$help_out" "schema_version"
bad="$(bash "$COLLECT" --nope 2>&1)"
assert_equals "usage: unknown argument exits 2" "$?" "2"
assert_contains "usage: names the argument" "$bad" "unknown argument"

# --- Prisma cardinality, no columns in the diagram -------------------------
repo="$TEST_TMPDIR/prisma"
init_repo "$repo"
mkdir -p "$repo/orders"
cat >"$repo/orders/schema.prisma" <<'EOF'
model User {
  id    Int    @id
  email String
  posts Post[]
}

model Post {
  id       Int    @id
  title    String
  author   User   @relation(fields: [authorId], references: [id])
  authorId Int
}
EOF
commit_all "$repo"
out="$TEST_TMPDIR/prisma-out"
bash "$COLLECT" --repo "$repo" --out "$out/data-model.json" --generated-on 2026-09-28
assert_equals "prisma collect exits 0" "$?" "0"
record="$(cat "$out/data-model.json")"
assert_contains "prisma tier" "$record" '"source_tier": "model"'
assert_contains "prisma tool" "$record" '"source_tool": "prisma"'
assert_contains "prisma cardinality" "$record" '"cardinality":"||--o{"'
assert_contains "prisma columns kept in the record" "$record" '"name":"title"'
sum="$(bash "$RENDER" --record "$out/data-model.json" --out "$out" --dialect mermaid)"
assert_equals "prisma render exits 0" "$?" "0"
md="$(cat "$out/data-model.md")"
assert_contains "prisma diagram cardinality" "$md" 'User ||--o{ Post'
assert_not_contains "prisma hides title without the flag" "$md" "title"
assert_contains "prisma names the tier" "$md" "Source tier: model (prisma)."
assert_contains "prisma summary" "$sum" "status=drawn"
assert_contains "prisma summary columns" "$sum" "columns=no"

sumc="$(bash "$RENDER" --record "$out/data-model.json" --out "$TEST_TMPDIR/prisma-cols" --dialect mermaid --include-columns)"
mdc="$(cat "$TEST_TMPDIR/prisma-cols/data-model.md")"
assert_contains "columns flag shows title" "$mdc" "title"
assert_contains "columns summary" "$sumc" "columns=yes"
assert_contains "authorId is a foreign key" "$mdc" "authorId FK"

# --- two modules refuse until scoped ----------------------------------------
repo2="$TEST_TMPDIR/two"
init_repo "$repo2"
mkdir -p "$repo2/orders" "$repo2/billing"
printf 'model Order {\n  id Int @id\n}\n' >"$repo2/orders/schema.prisma"
printf 'model Invoice {\n  id Int @id\n}\n' >"$repo2/billing/schema.prisma"
commit_all "$repo2"
bash "$COLLECT" --repo "$repo2" --out "$TEST_TMPDIR/two.json" --generated-on 2026-09-28
set +e
sum2="$(bash "$RENDER" --record "$TEST_TMPDIR/two.json" --out "$TEST_TMPDIR/two-out" --dialect mermaid)"
rc2=$?
assert_equals "two modules exit 3" "$rc2" "3"
assert_contains "two modules summary" "$sum2" "reason=scope-unresolved"
md2="$(cat "$TEST_TMPDIR/two-out/data-model.md")"
assert_contains "two modules names orders" "$md2" "orders"
assert_contains "two modules names billing" "$md2" "billing"
assert_not_contains "two modules draw no diagram" "$md2" "erDiagram"
assert_contains "two modules reason" "$md2" "scope-unresolved"
bash "$RENDER" --record "$TEST_TMPDIR/two.json" --out "$TEST_TMPDIR/two-one" --dialect mermaid --scope orders >/dev/null
mdone="$(cat "$TEST_TMPDIR/two-one/data-model.md")"
assert_contains "scope orders draws Order" "$mdone" "Order"
assert_not_contains "scope orders hides Invoice" "$mdone" "Invoice"

# --- migration disagrees with prisma ----------------------------------------
repo3="$TEST_TMPDIR/mismatch"
init_repo "$repo3"
mkdir -p "$repo3/shop/prisma/migrations/20240101000000_init"
cat >"$repo3/shop/schema.prisma" <<'EOF'
model User {
  id    Int    @id
  posts Post[]
}

model Post {
  id       Int  @id
  author   User @relation(fields: [authorId], references: [id])
  authorId Int
}
EOF
cat >"$repo3/shop/prisma/migrations/20240101000000_init/migration.sql" <<'EOF'
CREATE TABLE "User" (
    "id" INTEGER NOT NULL PRIMARY KEY
);

CREATE TABLE "Post" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "authorId" INTEGER,
    CONSTRAINT "Post_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id")
);
EOF
commit_all "$repo3"
bash "$COLLECT" --repo "$repo3" --out "$TEST_TMPDIR/record.json" --generated-on 2026-09-28
record="$(cat "$TEST_TMPDIR/record.json")"
assert_contains "mismatch keeps prisma as the winner" "$record" '"source_tool": "prisma"'
assert_contains "mismatch reports optionality" "$record" '"kind":"optionality"'
assert_not_contains "mismatch does not flip the diagram token" "$record" '"tool": "sql-migration"'
bash "$RENDER" --record "$TEST_TMPDIR/record.json" --out "$TEST_TMPDIR/record-out" --dialect mermaid --scope shop >/dev/null
mismd="$(cat "$TEST_TMPDIR/record-out/data-model.md")"
assert_contains "mismatch is on the artifact" "$mismd" "optionality"
assert_contains "diagram follows the model" "$mismd" 'User ||--o{ Post'

# --- SQL only, after a dropped table ----------------------------------------
repo4="$TEST_TMPDIR/sqlonly"
init_repo "$repo4"
mkdir -p "$repo4/db/migrations/001" "$repo4/db/migrations/002"
cat >"$repo4/db/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "Note" (
    "id" INTEGER NOT NULL PRIMARY KEY
);
CREATE TABLE "Gone" (
    "id" INTEGER NOT NULL PRIMARY KEY
);
EOF
cat >"$repo4/db/migrations/002/migration.sql" <<'EOF'
DROP TABLE "Gone";
EOF
commit_all "$repo4"
bash "$COLLECT" --repo "$repo4" --out "$TEST_TMPDIR/sql.json" --generated-on 2026-09-28
sqlrec="$(cat "$TEST_TMPDIR/sql.json")"
assert_contains "sql tier" "$sqlrec" '"source_tier": "migration"'
assert_contains "sql keeps Note" "$sqlrec" '"name":"Note"'
assert_not_contains "sql replays the drop" "$sqlrec" "Gone"

# --- django is a refusal, not a diagram -------------------------------------
repo5="$TEST_TMPDIR/django"
init_repo "$repo5"
mkdir -p "$repo5/app"
cat >"$repo5/app/models.py" <<'EOF'
from django.db import models
class Order(models.Model):
    name = models.CharField(max_length=20)
EOF
commit_all "$repo5"
bash "$COLLECT" --repo "$repo5" --out "$TEST_TMPDIR/dj.json" --generated-on 2026-09-28
dj="$(cat "$TEST_TMPDIR/dj.json")"
assert_contains "django refused" "$dj" '"status": "refused"'
assert_contains "django reason" "$dj" '"reason": "partial-read"'
bash "$RENDER" --record "$TEST_TMPDIR/dj.json" --out "$TEST_TMPDIR/dj-out" --dialect mermaid >/dev/null
djmd="$(cat "$TEST_TMPDIR/dj-out/data-model.md")"
assert_not_contains "django draws nothing" "$djmd" "erDiagram"
assert_contains "django names the mechanism" "$djmd" "django"

# --- prisma plus django is a partial read -----------------------------------
repo6="$TEST_TMPDIR/both"
init_repo "$repo6"
mkdir -p "$repo6/app"
printf 'model User {\n  id Int @id\n}\n' >"$repo6/app/schema.prisma"
printf 'from django.db import models\nclass T(models.Model):\n    pass\n' >"$repo6/app/models.py"
commit_all "$repo6"
bash "$COLLECT" --repo "$repo6" --out "$TEST_TMPDIR/both.json" --generated-on 2026-09-28
both="$(cat "$TEST_TMPDIR/both.json")"
assert_contains "partial read refused" "$both" '"reason": "partial-read"'
assert_not_contains "partial read has no entity" "$both" '"name": "User"'

# --- live never reads the schema --------------------------------------------
bash "$COLLECT" --repo "$repo" --out "$TEST_TMPDIR/live.json" --generated-on 2026-09-28 --live
live="$(cat "$TEST_TMPDIR/live.json")"
assert_contains "live refused" "$live" '"reason": "live-connection-requested"'
assert_not_contains "live did not read prisma" "$live" "Post"

# --- EF fluent --------------------------------------------------------------
repo7="$TEST_TMPDIR/ef"
init_repo "$repo7"
mkdir -p "$repo7/src"
cat >"$repo7/src/OrderMap.cs" <<'EOF'
modelBuilder.Entity<Post>().HasOne<User>().WithMany().HasForeignKey("AuthorId").IsRequired();
EOF
commit_all "$repo7"
bash "$COLLECT" --repo "$repo7" --out "$TEST_TMPDIR/ef.json" --generated-on 2026-09-28
ef="$(cat "$TEST_TMPDIR/ef.json")"
assert_contains "ef tier" "$ef" '"source_tier": "orm"'
assert_contains "ef cardinality" "$ef" '"cardinality":"||--o{"'
bash "$RENDER" --record "$TEST_TMPDIR/ef.json" --out "$TEST_TMPDIR/ef-out" --dialect mermaid >/dev/null
efmd="$(cat "$TEST_TMPDIR/ef-out/data-model.md")"
assert_contains "ef diagram" "$efmd" 'User ||--o{ Post'

# --- dialect resolver -------------------------------------------------------
# shellcheck disable=SC2016 # the fence is literal markdown, not a command substitution
printf '```yaml\ndiagram_dialect:\n  data: dbml\n```\n' >"$TEST_TMPDIR/formats.md"
got="$(bash "$DIALECT" --formats "$TEST_TMPDIR/formats.md")"
assert_equals "dialect dbml" "$got" "dbml"
missing="$(bash "$DIALECT" --formats "$TEST_TMPDIR/missing.md" 2>"$TEST_TMPDIR/dialect-err")"
assert_equals "missing doc defaults" "$missing" "mermaid"
assert_contains "missing doc explains" "$(cat "$TEST_TMPDIR/dialect-err")" "default mermaid"
bash "$RENDER" --record "$out/data-model.json" --out "$TEST_TMPDIR/dbml" --dialect dbml --include-columns >/dev/null
dbml="$(cat "$TEST_TMPDIR/dbml/data-model.dbml")"
assert_contains "dbml ref" "$dbml" 'Ref: "Post"."authorId" > "User"."id"'
assert_contains "dbml column" "$dbml" "title"

# --- reformatted record -----------------------------------------------------
printf '%s\n' '{"schema_version":1,"entities":[]}' >"$TEST_TMPDIR/flat.json"
set +e
bash "$RENDER" --record "$TEST_TMPDIR/flat.json" --out "$TEST_TMPDIR/flat-out" >/dev/null 2>"$TEST_TMPDIR/flat-err"
frc=$?
assert_equals "flat record exits 1" "$frc" "1"
assert_not_contains "flat record writes nothing" "$(ls "$TEST_TMPDIR/flat-out" 2>/dev/null || true)" "data-model.md"

# --- empty tree -------------------------------------------------------------
repo8="$TEST_TMPDIR/empty"
init_repo "$repo8"
printf 'hello\n' >"$repo8/README.md"
commit_all "$repo8"
bash "$COLLECT" --repo "$repo8" --out "$TEST_TMPDIR/empty.json" --generated-on 2026-09-28
empty="$(cat "$TEST_TMPDIR/empty.json")"
assert_contains "empty refuses" "$empty" '"reason": "no-declared-schema"'

if [[ "$FAILED" -eq 0 ]]; then
  printf 'all collect-data tests passed\n'
  exit 0
fi
printf '%d collect-data test(s) failed\n' "$FAILED" >&2
exit 1
