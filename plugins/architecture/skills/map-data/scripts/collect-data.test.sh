#!/usr/bin/env bash
# Tests for collect-data.sh and render-data.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-data.sh"
RENDER="$SCRIPT_DIR/render-data.sh"
DIALECT="$SCRIPT_DIR/../../../lib/resolve-diagram-dialect.sh"
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
assert_contains "prisma entity is written in the compact form the negative controls search" "$record" '"name":"User"'
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
assert_not_contains "mismatch does not flip the diagram token" "$record" '"tool":"sql-migration"'
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
assert_not_contains "partial read has no entity" "$both" '"name":"User"'

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

# --- EF docs standard shape: entity classes plus IEntityTypeConfiguration ----
mk_ef_docs_repo() {
  local dir="$1" fk_type="$2" required="$3"
  init_repo "$dir"
  mkdir -p "$dir/src"
  cat >"$dir/src/Blog.cs" <<'CS'
public class Blog
{
    public int BlogId { get; set; }
    public ICollection<Post> Posts { get; set; }
}
CS
  cat >"$dir/src/Post.cs" <<CS
public class Post
{
    public int PostId { get; set; }
    public $fk_type BlogId { get; set; }
    public Blog Blog { get; set; }
}
CS
  cat >"$dir/src/PostConfiguration.cs" <<CS
public class PostConfiguration : IEntityTypeConfiguration<Post>
{
    public void Configure(EntityTypeBuilder<Post> builder)
    {
        builder.HasOne(e => e.Blog).WithMany(e => e.Posts).HasForeignKey(e => e.BlogId)$required;
    }
}
CS
  commit_all "$dir"
}

mk_ef_docs_repo "$TEST_TMPDIR/ef-docs-req" "int" ".IsRequired()"
bash "$COLLECT" --repo "$TEST_TMPDIR/ef-docs-req" --out "$TEST_TMPDIR/ef-docs-req.json" --generated-on 2026-09-28
efreq="$(cat "$TEST_TMPDIR/ef-docs-req.json")"
assert_contains "ef config class tier" "$efreq" '"source_tier": "orm"'
assert_contains "ef config class cardinality" "$efreq" '"cardinality":"||--o{"'
assert_contains "ef config class direction" "$efreq" '"from":"src/Post","to":"src/Blog"'
bash "$RENDER" --record "$TEST_TMPDIR/ef-docs-req.json" --out "$TEST_TMPDIR/ef-docs-req-out" --dialect mermaid >/dev/null
assert_contains "ef config class diagram" "$(cat "$TEST_TMPDIR/ef-docs-req-out/data-model.md")" 'Blog ||--o{ Post'

mk_ef_docs_repo "$TEST_TMPDIR/ef-docs-nullable" "int?" ""
bash "$COLLECT" --repo "$TEST_TMPDIR/ef-docs-nullable" --out "$TEST_TMPDIR/ef-docs-nullable.json" --generated-on 2026-09-28
efnull="$(cat "$TEST_TMPDIR/ef-docs-nullable.json")"
assert_contains "ef nullable fk cardinality" "$efnull" '"cardinality":"|o--o{"'
assert_contains "ef nullable fk optional" "$efnull" '"optional":"yes"'

mk_ef_docs_repo "$TEST_TMPDIR/ef-docs-nonnull" "int" ""
bash "$COLLECT" --repo "$TEST_TMPDIR/ef-docs-nonnull" --out "$TEST_TMPDIR/ef-docs-nonnull.json" --generated-on 2026-09-28
efnn="$(cat "$TEST_TMPDIR/ef-docs-nonnull.json")"
assert_contains "ef non-nullable fk cardinality" "$efnn" '"cardinality":"||--o{"'
assert_contains "ef non-nullable fk optional" "$efnn" '"optional":"no"'

repo_efx="$TEST_TMPDIR/ef-docs-refused"
init_repo "$repo_efx"
mkdir -p "$repo_efx/src"
cat >"$repo_efx/src/PostConfiguration.cs" <<'CS'
public class PostConfiguration : IEntityTypeConfiguration<Post>
{
    public void Configure(EntityTypeBuilder<Post> builder)
    {
        builder.HasOne(e => e.Blog).WithMany(e => e.Posts).HasForeignKey(e => new { e.A, e.B });
        builder.HasOne(e => e.Author).WithMany().HasForeignKey(e => e.AuthorId);
    }
}
CS
commit_all "$repo_efx"
bash "$COLLECT" --repo "$repo_efx" --out "$TEST_TMPDIR/ef-docs-refused.json" --generated-on 2026-09-28
efref="$(cat "$TEST_TMPDIR/ef-docs-refused.json")"
assert_contains "ef unreadable chain refused" "$efref" '"status": "refused"'
assert_contains "ef unreadable chain reason" "$efref" 'ef-fluent-unreadable'
assert_not_contains "ef unreadable chain emits no relationship" "$efref" '"tool":"ef-fluent"'

# --- dialect resolver -------------------------------------------------------
# shellcheck disable=SC2016 # the fence is literal markdown, not a command substitution
printf '```yaml\ndiagram_dialect:\n  data: dbml\n```\n' >"$TEST_TMPDIR/formats.md"
got="$(bash "$DIALECT" --kind data --formats "$TEST_TMPDIR/formats.md")"
assert_equals "dialect dbml" "$got" "dbml"
missing="$(bash "$DIALECT" --kind data --formats "$TEST_TMPDIR/missing.md" 2>"$TEST_TMPDIR/dialect-err")"
assert_equals "missing doc defaults" "$missing" "mermaid"
assert_contains "missing doc explains" "$(cat "$TEST_TMPDIR/dialect-err")" "default mermaid"
bash "$RENDER" --record "$out/data-model.json" --out "$TEST_TMPDIR/dbml" --dialect dbml --include-columns >/dev/null
dbml="$(cat "$TEST_TMPDIR/dbml/data-model.dbml")"
assert_contains "dbml ref" "$dbml" 'Ref: "Post"."authorId" > "User"."id"'
assert_contains "dbml column" "$dbml" "title"

# --- one-to-one and referenced columns, Prisma ------------------------------
repo9="$TEST_TMPDIR/prisma-11"
init_repo "$repo9"
mkdir -p "$repo9/app"
cat >"$repo9/app/schema.prisma" <<'EOF'
model User {
  id      Int      @id
  email   String   @unique
  posts   Post[]
  profile Profile?
  card    Card?
  badge   Badge?
  extra   Extra?
  note    Note[]
}

model Post {
  id          Int    @id
  author      User   @relation(fields: [authorEmail], references: [email])
  authorEmail String
}

model Profile {
  id     Int  @id
  user   User @relation(fields: [userId], references: [id])
  userId Int  @unique
}

model Card {
  id     Int   @id
  user   User? @relation(fields: [userId], references: [id])
  userId Int?

  @@unique([userId])
}

model Badge {
  user   User @relation(fields: [userId], references: [id])
  userId Int  @id
}

model Extra {
  user   User @relation(fields: [userId], references: [id])
  userId Int

  @@id([userId])
}

model Note {
  id     Int    @id
  title  String
  user   User   @relation(fields: [userId], references: [id])
  userId Int

  @@unique([userId, title])
}
EOF
commit_all "$repo9"
bash "$COLLECT" --repo "$repo9" --out "$TEST_TMPDIR/p11.json" --generated-on 2026-09-28
bash "$RENDER" --record "$TEST_TMPDIR/p11.json" --out "$TEST_TMPDIR/p11-out" --dialect mermaid >/dev/null
p11md="$(cat "$TEST_TMPDIR/p11-out/data-model.md")"
assert_contains "prisma required @unique fk is one-to-one" "$p11md" 'User ||--o| Profile'
assert_contains "prisma optional @@unique fk is optional one-to-one" "$p11md" 'User |o--o| Card'
assert_contains "prisma @id fk is one-to-one" "$p11md" 'User ||--o| Badge'
assert_contains "prisma @@id fk is one-to-one" "$p11md" 'User ||--o| Extra'
assert_contains "prisma unique over more than the fk stays one-to-many" "$p11md" 'User ||--o{ Note'
assert_contains "prisma plain fk stays one-to-many" "$p11md" 'User ||--o{ Post'
assert_not_contains "prisma draws no both-sides-required token" "$p11md" '||--||'
bash "$RENDER" --record "$TEST_TMPDIR/p11.json" --out "$TEST_TMPDIR/p11-dbml" --dialect dbml >/dev/null
p11dbml="$(cat "$TEST_TMPDIR/p11-dbml/data-model.dbml")"
assert_contains "dbml names the referenced column" "$p11dbml" 'Ref: "Post"."authorEmail" > "User"."email"'
assert_contains "dbml one-to-one uses the one-to-one operator" "$p11dbml" 'Ref: "Profile"."userId" - "User"."id"'
assert_not_contains "dbml does not hardcode id for a non-id reference" "$p11dbml" '"Post"."authorEmail" > "User"."id"'

repo10="$TEST_TMPDIR/prisma-composite"
init_repo "$repo10"
mkdir -p "$repo10/app"
cat >"$repo10/app/schema.prisma" <<'EOF'
model Parent {
  a        Int
  b        Int
  children Child[]

  @@id([a, b])
}

model Child {
  id      Int    @id
  parent  Parent @relation(fields: [parentA, parentB], references: [a, b])
  parentA Int
  parentB Int
}
EOF
commit_all "$repo10"
bash "$COLLECT" --repo "$repo10" --out "$TEST_TMPDIR/pc.json" --generated-on 2026-09-28
pc="$(cat "$TEST_TMPDIR/pc.json")"
assert_contains "composite fk with no unique set refuses" "$pc" '"reason": "unknown-cardinality"'
assert_not_contains "composite fk draws no relationship" "$pc" '"cardinality"'
cat >"$repo10/app/schema.prisma" <<'EOF'
model Parent {
  a        Int
  b        Int
  children Child[]

  @@id([a, b])
}

model Child {
  id      Int    @id
  parent  Parent @relation(fields: [parentA, parentB], references: [a, b])
  parentA Int
  parentB Int

  @@unique([parentA, parentB])
}
EOF
commit_all "$repo10"
bash "$COLLECT" --repo "$repo10" --out "$TEST_TMPDIR/pc2.json" --generated-on 2026-09-28
assert_contains "composite fk with a unique set is one-to-one" "$(cat "$TEST_TMPDIR/pc2.json")" '"cardinality":"||--o|"'

# --- one-to-one and referenced columns, SQL ---------------------------------
repo11="$TEST_TMPDIR/sql-11"
init_repo "$repo11"
mkdir -p "$repo11/db/migrations/001"
cat >"$repo11/db/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "User" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL UNIQUE
);
CREATE TABLE "Profile" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "userId" INTEGER NOT NULL,
    CONSTRAINT "Profile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id")
);
CREATE UNIQUE INDEX "Profile_userId_key" ON "Profile"("userId");
CREATE TABLE "Card" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "userId" INTEGER,
    CONSTRAINT "Card_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id")
);
CREATE UNIQUE INDEX "Card_userId_key" ON "Card"("userId");
CREATE TABLE "Post" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "authorEmail" TEXT NOT NULL,
    CONSTRAINT "Post_authorEmail_fkey" FOREIGN KEY ("authorEmail") REFERENCES "User"("email")
);
CREATE TABLE "Tag" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "userId" INTEGER NOT NULL,
    "label" TEXT NOT NULL,
    CONSTRAINT "Tag_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id")
);
CREATE UNIQUE INDEX "Tag_userId_label_key" ON "Tag"("userId", "label");
EOF
commit_all "$repo11"
bash "$COLLECT" --repo "$repo11" --out "$TEST_TMPDIR/s11.json" --generated-on 2026-09-28
s11="$(cat "$TEST_TMPDIR/s11.json")"
assert_contains "sql tier wins when alone" "$s11" '"tool":"sql-migration"'
assert_contains "sql references column is recorded" "$s11" '"references":"email"'
bash "$RENDER" --record "$TEST_TMPDIR/s11.json" --out "$TEST_TMPDIR/s11-out" --dialect mermaid >/dev/null
s11md="$(cat "$TEST_TMPDIR/s11-out/data-model.md")"
assert_contains "sql separate unique index makes one-to-one" "$s11md" 'User ||--o| Profile'
assert_contains "sql optional unique fk is optional one-to-one" "$s11md" 'User |o--o| Card'
assert_contains "sql plain fk stays one-to-many" "$s11md" 'User ||--o{ Post'
assert_contains "sql unique over more than the fk stays one-to-many" "$s11md" 'User ||--o{ Tag'
assert_not_contains "sql draws no both-sides-required token" "$s11md" '||--||'
bash "$RENDER" --record "$TEST_TMPDIR/s11.json" --out "$TEST_TMPDIR/s11-dbml" --dialect dbml >/dev/null
assert_contains "sql dbml names the referenced column" "$(cat "$TEST_TMPDIR/s11-dbml/data-model.dbml")" 'Ref: "Post"."authorEmail" > "User"."email"'

repo12="$TEST_TMPDIR/sql-composite"
init_repo "$repo12"
mkdir -p "$repo12/db/migrations/001"
cat >"$repo12/db/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "Parent" (
    "a" INTEGER NOT NULL,
    "b" INTEGER NOT NULL,
    PRIMARY KEY ("a", "b")
);
CREATE TABLE "Child" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "pa" INTEGER NOT NULL,
    "pb" INTEGER NOT NULL,
    FOREIGN KEY ("pa", "pb") REFERENCES "Parent"("a", "b")
);
EOF
commit_all "$repo12"
bash "$COLLECT" --repo "$repo12" --out "$TEST_TMPDIR/sc.json" --generated-on 2026-09-28
sc="$(cat "$TEST_TMPDIR/sc.json")"
assert_contains "sql composite fk with no unique set refuses" "$sc" '"reason": "unknown-cardinality"'
assert_not_contains "sql composite fk draws no relationship" "$sc" '"cardinality"'

# --- one-to-one, EF fluent --------------------------------------------------
repo13="$TEST_TMPDIR/ef-11"
init_repo "$repo13"
mkdir -p "$repo13/src"
cat >"$repo13/src/Map.cs" <<'EOF'
modelBuilder.Entity<Profile>().HasOne<User>().WithOne().HasForeignKey("UserId").IsRequired();
modelBuilder.Entity<Card>().HasOne<User>().WithOne().HasForeignKey("UserId").IsRequired(false);
modelBuilder.Entity<Post>().HasOne<User>().WithMany().HasForeignKey("AuthorCode").HasPrincipalKey("Code").IsRequired();
modelBuilder.Entity<Note>().HasOne<User>().WithMany().HasForeignKey("UserId").IsRequired();
EOF
commit_all "$repo13"
bash "$COLLECT" --repo "$repo13" --out "$TEST_TMPDIR/ef11.json" --generated-on 2026-09-28
bash "$RENDER" --record "$TEST_TMPDIR/ef11.json" --out "$TEST_TMPDIR/ef11-out" --dialect mermaid >/dev/null
ef11md="$(cat "$TEST_TMPDIR/ef11-out/data-model.md")"
assert_contains "ef required one-to-one" "$ef11md" 'User ||--o| Profile'
assert_contains "ef optional one-to-one" "$ef11md" 'User |o--o| Card'
assert_contains "ef one-to-many stays" "$ef11md" 'User ||--o{ Note'
assert_not_contains "ef draws no both-sides-required token" "$ef11md" '||--||'
bash "$RENDER" --record "$TEST_TMPDIR/ef11.json" --out "$TEST_TMPDIR/ef11-dbml" --dialect dbml >/dev/null
ef11dbml="$(cat "$TEST_TMPDIR/ef11-dbml/data-model.dbml")"
assert_contains "ef dbml names a declared principal key" "$ef11dbml" 'Ref: "Post"."AuthorCode" > "User"."Code"'
assert_contains "ef dbml keeps an unknown referenced column as a comment" "$ef11dbml" '// Ref: "Note"."UserId" > "User" (referenced column not declared)'
assert_not_contains "ef dbml does not invent an id column" "$ef11dbml" '"User"."id"'

# --- SQL replay: ALTER TABLE, column-level REFERENCES, root migrations/ -----
repo14="$TEST_TMPDIR/sql-alter"
init_repo "$repo14"
mkdir -p "$repo14/migrations/001" "$repo14/migrations/002" "$repo14/migrations/003"
cat >"$repo14/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "User" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL
);
CREATE TABLE "Post" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "authorId" INTEGER NOT NULL
);
CREATE TABLE "Comment" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "postId" INTEGER NOT NULL REFERENCES "Post"("id") ON DELETE CASCADE
);
CREATE TABLE "Tag" (
    "id" INTEGER NOT NULL PRIMARY KEY
) ENGINE=InnoDB;
CREATE TABLE "Legacy" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "userId" INTEGER NOT NULL,
    CONSTRAINT "Legacy_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id")
);
EOF
cat >"$repo14/migrations/002/migration.sql" <<'EOF'
ALTER TABLE "Post"
    ADD CONSTRAINT "Post_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id");
ALTER TABLE "Tag" ADD COLUMN "postId" INTEGER REFERENCES "Post"("id"), ADD COLUMN "label" TEXT NOT NULL;
ALTER TABLE "Legacy" DROP CONSTRAINT "Legacy_userId_fkey";
ALTER TABLE "Comment" ADD COLUMN "note" TEXT;
EOF
cat >"$repo14/migrations/003/migration.sql" <<'EOF'
ALTER TABLE "Comment" DROP COLUMN "postId";
EOF
commit_all "$repo14"
bash "$COLLECT" --repo "$repo14" --out "$TEST_TMPDIR/s14.json" --generated-on 2026-09-28
s14="$(cat "$TEST_TMPDIR/s14.json")"
assert_contains "root migrations directory is matched" "$s14" '"source_tool": "sql-migration"'
assert_contains "sql tier is drawn" "$s14" '"status": "drawn"'
assert_contains "alter add constraint foreign key is a relationship" "$s14" '"from":"migrations/Post","to":"migrations/User","cardinality":"||--o{","columns":"authorId"'
assert_contains "alter add column with REFERENCES is a relationship" "$s14" '"from":"migrations/Tag","to":"migrations/Post","cardinality":"|o--o{","columns":"postId"'
assert_contains "alter add column is an attribute" "$s14" '"name":"label"'
assert_not_contains "alter drop constraint removes the foreign key" "$s14" '"from":"migrations/Legacy"'
assert_not_contains "alter drop column removes its foreign key" "$s14" '"from":"migrations/Comment"'
assert_not_contains "alter drop column removes the attribute" "$s14" '"name":"postId","type":"INTEGER","nullable":"no"'
assert_contains "a column added later is kept" "$s14" '"name":"note"'
assert_contains "one module, the root directory" "$s14" '{"id":"migrations"}'

repo15="$TEST_TMPDIR/sql-colref"
init_repo "$repo15"
mkdir -p "$repo15/db/migrations/001"
cat >"$repo15/db/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "User" (
    "id" INTEGER NOT NULL PRIMARY KEY
);
CREATE TABLE "Profile" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "userId" INTEGER UNIQUE REFERENCES "User"
);
EOF
commit_all "$repo15"
bash "$COLLECT" --repo "$repo15" --out "$TEST_TMPDIR/s15.json" --generated-on 2026-09-28
s15="$(cat "$TEST_TMPDIR/s15.json")"
assert_contains "column-level unique REFERENCES is an optional one-to-one" "$s15" '"from":"db/Profile","to":"db/User","cardinality":"|o--o|"'
assert_contains "column-level REFERENCES without a column list leaves references empty" "$s15" '"references":""'

repo15b="$TEST_TMPDIR/sql-oneline"
init_repo "$repo15b"
mkdir -p "$repo15b/db/migrations/001"
cat >"$repo15b/db/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "User" ("id" INTEGER NOT NULL PRIMARY KEY, "score" NUMERIC(10,2));
CREATE TABLE "Post" ("id" INTEGER NOT NULL PRIMARY KEY, "authorId" INTEGER NOT NULL, FOREIGN KEY ("authorId") REFERENCES "User"("id"));
CREATE TABLE "Late" (
    "id" INTEGER NOT NULL PRIMARY KEY
);
EOF
commit_all "$repo15b"
bash "$COLLECT" --repo "$repo15b" --out "$TEST_TMPDIR/s15b.json" --generated-on 2026-09-28
s15b="$(cat "$TEST_TMPDIR/s15b.json")"
assert_contains "single-line CREATE TABLE reads its foreign key" "$s15b" '"from":"db/Post","to":"db/User","cardinality":"||--o{","columns":"authorId"'
assert_contains "single-line CREATE TABLE reads its columns" "$s15b" '"name":"score"'
assert_contains "a table after a single-line CREATE TABLE is still read" "$s15b" '"name":"Late"'

for form in 'ALTER TABLE "User" RENAME TO "Account";' 'ALTER TABLE "User" ALTER COLUMN "email" SET NOT NULL;' 'ALTER TABLE "User" DROP CONSTRAINT "unknown_key";'; do
  repo16="$TEST_TMPDIR/sql-unreadable"
  rm -rf "$repo16"
  init_repo "$repo16"
  mkdir -p "$repo16/db/migrations/001" "$repo16/db/migrations/002"
  printf 'CREATE TABLE "User" (\n    "id" INTEGER NOT NULL PRIMARY KEY,\n    "email" TEXT\n);\n' >"$repo16/db/migrations/001/migration.sql"
  printf '%s\n' "$form" >"$repo16/db/migrations/002/migration.sql"
  commit_all "$repo16"
  bash "$COLLECT" --repo "$repo16" --out "$TEST_TMPDIR/s16.json" --generated-on 2026-09-28
  s16="$(cat "$TEST_TMPDIR/s16.json")"
  assert_contains "unreadable ALTER refuses the sql tier: $form" "$s16" '"reason": "sql-alter-unreadable"'
  assert_not_contains "unreadable ALTER draws no entity: $form" "$s16" '"name":"User"'
done

# --- a losing tier does not block or inflate the winner ---------------------
repo17="$TEST_TMPDIR/losers"
init_repo "$repo17"
mkdir -p "$repo17/orders/migrations/001" "$repo17/tests"
cat >"$repo17/orders/schema.prisma" <<'EOF'
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
cat >"$repo17/orders/migrations/001/migration.sql" <<'EOF'
CREATE TABLE "User" (
    "id" INTEGER NOT NULL PRIMARY KEY
);
CREATE TABLE "Post" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "authorId" INTEGER NOT NULL,
    FOREIGN KEY ("authorId") REFERENCES "User"("id")
);
EOF
cat >"$repo17/tests/Sample.cs" <<'EOF'
modelBuilder.Entity<Post>().HasOne(p => p.Author).WithMany().HasForeignKey(p => p.AuthorId);
EOF
commit_all "$repo17"
bash "$COLLECT" --repo "$repo17" --out "$TEST_TMPDIR/s17.json" --generated-on 2026-09-28
s17="$(cat "$TEST_TMPDIR/s17.json")"
assert_contains "prisma wins beside an unreadable EF file" "$s17" '"source_tool": "prisma"'
assert_contains "unreadable EF file is reported as not compared" "$s17" '"kind":"not-compared"'
assert_not_contains "a dropped tier makes no missing-in-other claim" "$s17" 'missing-in-other'
assert_contains "only the winning tier's module is listed" "$s17" '"modules": [
    {"id":"orders"}
  ]'
set +e
sum17="$(bash "$RENDER" --record "$TEST_TMPDIR/s17.json" --out "$TEST_TMPDIR/s17-out" --dialect mermaid)"
rc17=$?
assert_equals "default scope draws the only module, exit 0" "$rc17" "0"
assert_contains "the diagram is drawn" "$sum17" "status=drawn"
assert_contains "the diagram follows prisma" "$(cat "$TEST_TMPDIR/s17-out/data-model.md")" 'User ||--o{ Post'

# The same fixture with a readable migration and an EF file that reads still compares.
printf 'modelBuilder.Entity<Post>().HasOne<User>().WithMany().HasForeignKey("authorId").IsRequired();\n' >"$repo17/tests/Sample.cs"
commit_all "$repo17"
bash "$COLLECT" --repo "$repo17" --out "$TEST_TMPDIR/s17b.json" --generated-on 2026-09-28
s17b="$(cat "$TEST_TMPDIR/s17b.json")"
assert_not_contains "a readable losing tier is compared, not skipped" "$s17b" '"kind":"not-compared"'
assert_contains "the readable EF tier keeps its mechanism row" "$s17b" '"name":"ef-fluent"'

# An unreadable losing SQL migration is reported the same way.
printf 'ALTER TABLE "Post" RENAME TO "Article";\n' >"$repo17/orders/migrations/001/migration.sql"
printf 'model Note {\n  id Int @id\n}\n' >"$repo17/orders/schema.prisma"
commit_all "$repo17"
bash "$COLLECT" --repo "$repo17" --out "$TEST_TMPDIR/s17c.json" --generated-on 2026-09-28
s17c="$(cat "$TEST_TMPDIR/s17c.json")"
assert_contains "prisma still wins beside an unreadable migration" "$s17c" '"source_tool": "prisma"'
assert_contains "the unreadable migration is reported as not compared" "$s17c" 'sql-migration was not compared with prisma'

# EF that would win still refuses.
repo18="$TEST_TMPDIR/ef-wins"
init_repo "$repo18"
mkdir -p "$repo18/src"
printf 'modelBuilder.Entity<Post>().HasOne(p => p.Author).WithMany().HasForeignKey(p => p.AuthorId);\n' >"$repo18/src/Map.cs"
commit_all "$repo18"
bash "$COLLECT" --repo "$repo18" --out "$TEST_TMPDIR/s18.json" --generated-on 2026-09-28
assert_contains "an unreadable EF chain refuses when EF would win" "$(cat "$TEST_TMPDIR/s18.json")" '"reason": "ef-fluent-unreadable"'

# --- the same short name in two modules stays two nodes ---------------------
repo19="$TEST_TMPDIR/same-name"
init_repo "$repo19"
mkdir -p "$repo19/orders" "$repo19/billing"
printf 'model User {\n  id Int @id\n  notes Note[]\n}\nmodel Note {\n  id Int @id\n  user User @relation(fields: [userId], references: [id])\n  userId Int\n}\n' >"$repo19/orders/schema.prisma"
printf 'model User {\n  id Int @id\n  invoices Invoice[]\n}\nmodel Invoice {\n  id Int @id\n  user User @relation(fields: [userId], references: [id])\n  userId Int\n}\n' >"$repo19/billing/schema.prisma"
commit_all "$repo19"
bash "$COLLECT" --repo "$repo19" --out "$TEST_TMPDIR/s19.json" --generated-on 2026-09-28
bash "$RENDER" --record "$TEST_TMPDIR/s19.json" --out "$TEST_TMPDIR/s19-all" --dialect mermaid --scope all >/dev/null
s19md="$(cat "$TEST_TMPDIR/s19-all/data-model.md")"
assert_contains "scope all qualifies the orders node" "$s19md" '"orders/User" ||--o{ "orders/Note"'
assert_contains "scope all qualifies the billing node" "$s19md" '"billing/User" ||--o{ "billing/Invoice"'
bash "$RENDER" --record "$TEST_TMPDIR/s19.json" --out "$TEST_TMPDIR/s19-dbml" --dialect dbml --scope all >/dev/null
s19dbml="$(cat "$TEST_TMPDIR/s19-dbml/data-model.dbml")"
assert_contains "dbml keeps orders/User as its own table" "$s19dbml" 'Table "orders/User"'
assert_contains "dbml keeps billing/User as its own table" "$s19dbml" 'Table "billing/User"'
bash "$RENDER" --record "$TEST_TMPDIR/s19.json" --out "$TEST_TMPDIR/s19-one" --dialect mermaid --scope orders >/dev/null
assert_contains "one module in scope keeps the short name" "$(cat "$TEST_TMPDIR/s19-one/data-model.md")" 'User ||--o{ Note'

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
