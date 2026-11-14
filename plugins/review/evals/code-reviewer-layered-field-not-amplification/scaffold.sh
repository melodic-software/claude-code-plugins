#!/usr/bin/env bash
# main holds a customers app in layers: the Customer entity, a repository that builds it from a
# database row, the API DTO with its mapper, and SQL migrations. The branch adds one nullable
# phoneNumber field through each layer's own representation: the entity, the row mapping, the DTO,
# the mapper and a new migration. Nothing else changes: no copied logic or constant, no registry.
# The base commit SHA is in .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p src/domain src/db src/api migrations

cat >package.json <<'JSON'
{ "name": "customers", "type": "module", "private": true }
JSON

cat >migrations/001_create_customers.sql <<'SQL'
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP NOT NULL
);
SQL

cat >src/domain/customer.js <<'JS'
export class Customer {
  constructor({ id, name, email, createdAt }) {
    this.id = id;
    this.name = name;
    this.email = email;
    this.createdAt = createdAt;
  }
}
JS

cat >src/db/customer-repository.js <<'JS'
import { Customer } from "../domain/customer.js";

export function customerFromRow(row) {
  return new Customer({
    id: row.id,
    name: row.name,
    email: row.email,
    createdAt: new Date(row.created_at),
  });
}

export async function findCustomer(db, id) {
  const row = await db.get("SELECT * FROM customers WHERE id = ?", id);
  return row ? customerFromRow(row) : null;
}
JS

cat >src/api/customer-dto.js <<'JS'
/**
 * @typedef {object} CustomerDto
 * @property {string} id
 * @property {string} name
 * @property {string} email
 * @property {string} createdAt ISO 8601 timestamp
 */
export {};
JS

cat >src/api/customer-mapper.js <<'JS'
/** @returns {import("./customer-dto.js").CustomerDto} */
export function toCustomerDto(customer) {
  return {
    id: customer.id,
    name: customer.name,
    email: customer.email,
    createdAt: customer.createdAt.toISOString(),
  };
}
JS

git add .
git commit -q -m "feat: customers"
git rev-parse HEAD >.review-base
git checkout -q -b feat/customer-phone-number

cat >migrations/002_add_customer_phone_number.sql <<'SQL'
ALTER TABLE customers ADD COLUMN phone_number TEXT;
SQL

cat >src/domain/customer.js <<'JS'
export class Customer {
  constructor({ id, name, email, createdAt, phoneNumber = null }) {
    this.id = id;
    this.name = name;
    this.email = email;
    this.createdAt = createdAt;
    this.phoneNumber = phoneNumber;
  }
}
JS

cat >src/db/customer-repository.js <<'JS'
import { Customer } from "../domain/customer.js";

export function customerFromRow(row) {
  return new Customer({
    id: row.id,
    name: row.name,
    email: row.email,
    createdAt: new Date(row.created_at),
    phoneNumber: row.phone_number,
  });
}

export async function findCustomer(db, id) {
  const row = await db.get("SELECT * FROM customers WHERE id = ?", id);
  return row ? customerFromRow(row) : null;
}
JS

cat >src/api/customer-dto.js <<'JS'
/**
 * @typedef {object} CustomerDto
 * @property {string} id
 * @property {string} name
 * @property {string} email
 * @property {string} createdAt ISO 8601 timestamp
 * @property {string | null} phoneNumber
 */
export {};
JS

cat >src/api/customer-mapper.js <<'JS'
/** @returns {import("./customer-dto.js").CustomerDto} */
export function toCustomerDto(customer) {
  return {
    id: customer.id,
    name: customer.name,
    email: customer.email,
    createdAt: customer.createdAt.toISOString(),
    phoneNumber: customer.phoneNumber,
  };
}
JS

git add src migrations
git commit -q -m "feat: customer phone number"
