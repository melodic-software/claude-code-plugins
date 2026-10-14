#!/usr/bin/env bash
# A Prisma schema says one User has many Posts; the SQL migration beside it puts a UNIQUE
# constraint on Post.authorId, which makes the same relationship one-to-one.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p db/migrations

cat >db/schema.prisma <<'PRISMA'
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id    Int    @id @default(autoincrement())
  email String @unique
  posts Post[]
}

model Post {
  id       Int    @id @default(autoincrement())
  title    String
  authorId Int
  author   User   @relation(fields: [authorId], references: [id])
}
PRISMA

cat >db/migrations/001_init.sql <<'SQL'
CREATE TABLE "User" (
  "id" SERIAL PRIMARY KEY,
  "email" TEXT NOT NULL UNIQUE
);

CREATE TABLE "Post" (
  "id" SERIAL PRIMARY KEY,
  "title" TEXT NOT NULL,
  "authorId" INTEGER NOT NULL UNIQUE REFERENCES "User"("id")
);
SQL

git add -A
git commit -q -m "Blog schema and first migration"
mkdir -p docs/architecture
