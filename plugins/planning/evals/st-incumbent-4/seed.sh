#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p app/models app/services db docs/vendor .work/review-target/design

cat >Gemfile <<'RUBY'
source "https://gems.example"

ruby "3.3.5"

gem "pg", "1.5.7"
gem "rails", "7.2.1"
gem "sealbox", "5.2.0"
RUBY

cat >app/models/customer.rb <<'RUBY'
class Customer < ApplicationRecord
  has_many :invoices

  validates :email, presence: true, length: { maximum: 254 }
  validates :phone, length: { maximum: 20 }
  validates :tax_id, length: { maximum: 32 }

  def email
    Sealbox.open(email_sealed)
  end

  def email=(value)
    self.email_sealed = Sealbox.seal(value)
    self.email_bidx = Sealbox.blind_index(value.downcase)
  end

  def phone
    phone_sealed && Sealbox.open(phone_sealed)
  end

  def phone=(value)
    self.phone_sealed = value && Sealbox.seal(value)
  end

  def tax_id
    tax_id_sealed && Sealbox.open(tax_id_sealed)
  end

  def tax_id=(value)
    self.tax_id_sealed = value && Sealbox.seal(value)
  end
end
RUBY

cat >app/services/support_lookup.rb <<'RUBY'
class SupportLookup
  def self.by_email(address)
    Customer.find_by(email_bidx: Sealbox.blind_index(address.strip.downcase))
  end

  def self.summary(address)
    customer = by_email(address)
    return nil if customer.nil?

    { id: customer.id, open_invoices: customer.invoices.where(paid_at: nil).count }
  end
end
RUBY

cat >db/schema.rb <<'RUBY'
ActiveRecord::Schema[7.2].define(version: 2026_03_11_090000) do
  create_table "customers", force: :cascade do |t|
    t.text "email_sealed", null: false
    t.string "email_bidx", null: false
    t.text "phone_sealed"
    t.text "tax_id_sealed"
    t.timestamps
    t.index ["email_bidx"], unique: true
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.integer "total_cents", null: false
    t.datetime "paid_at"
    t.timestamps
  end
end
RUBY

cat >docs/vendor/sealbox-changelog.md <<'MD'
# Sealbox changelog

## 5.2.0

- Smaller envelopes for short values.

## 5.0.0

- New `Sealbox.rekey(value, old:, new:)`: re-seals a value under a new master key.
- `Sealbox.configure` accepts a list of master keys, the first of which seals.

## 4.0.0

- `Sealbox.blind_index(value)`: a keyed hash of a value, for equality lookups.

## 3.0.0

- `Sealbox.open` raises `Sealbox::BadEnvelope` on input that is not a Sealbox envelope.
MD

cat >docs/vendor/vaultline-notes.md <<'MD'
# Vaultline notes

Field encryption for Ruby applications.

- `Vaultline.seal(plaintext)` uses a fresh random nonce for each call.
- Equal plaintexts give different outputs.
- `Vaultline.open(value)` reverses `seal`.
- Output starts with `vl1:`.
- Values of up to 4 KB.
- `Vaultline.rotate(value)` re-seals a value under the current master key.
MD

cat >.work/review-target/design/design-resolution.md <<'MD'
---
outcome: early-exit
tier: C
reason: the Brief names the field encryption decision and its options; no type or module design is open
---
MD

cat >.work/review-target/PLAN.md <<'MD'
# Customer field encryption

## Brief

### Problem

Customer email, phone and tax id are sealed at rest with Sealbox. Our new customer contract with a
regional accounting group requires a yearly change of the master key, with evidence. The auditors
will ask for the first change at the renewal in March.

### Goal

Have customer fields sealed under a master key that we can change every year.

### Acceptance criteria

- AC1: The master key for customer fields can be changed with the invoicing app staying up.
- AC2: Support can still look a customer up by their email address, in any letter case.
- AC3: Every existing customer row is readable after the work finishes.

### Out-of-scope

- Encrypting invoice totals.
- Where master keys are stored.
- Changes to the support tool's screens.

### Captured assumptions

- Quality bar: production
- About 1.2 million customer rows.
- The app stays on Rails and Postgres.

## Plan

### Decision

Replace Sealbox with Vaultline for all customer fields.

### Why

- Sealbox ties every value to one master key and gives us no way to change it, so it cannot meet
  AC1.
- Vaultline has `Vaultline.rotate`, which re-seals a value under the current master key, so a
  yearly change becomes a routine job.
- Vaultline's 4 KB value limit is well above our largest field. The model caps email at 254
  characters, phone at 20 and tax id at 32.

### Phase 1: Read both, write Vaultline [STATUS]

**Satisfies:** AC2, AC3

In `app/models/customer.rb`, have the getters call `Vaultline.open` for a value starting `vl1:` and
`Sealbox.open` for any other value. Have the setters write with `Vaultline.seal`, and fill
`email_bidx` with `Vaultline.seal(value.downcase)`. In `app/services/support_lookup.rb`, build the
lookup value the same way.

**Sanity Check:** in staging, create a customer, read them back, and open an older customer.

### Phase 2: Convert existing rows [STATUS]

**Satisfies:** AC3

Add a `customers:reseal` rake task. For each row in `Customer.find_each`, read the three sealed
columns with `Sealbox.open`, write each with `Vaultline.seal`, and refill `email_bidx`, using
`update_columns`. At the roughly 60 rows per second we measured on staging, this takes about six
hours; run it in production overnight.

**Sanity Check:** `Customer.where("email_sealed NOT LIKE 'vl1:%'").count` is zero when it finishes.

### Phase 3: Remove Sealbox and schedule rotation [STATUS]

**Satisfies:** AC1

Drop the `Sealbox` branch from the getters and remove the gem from the `Gemfile`. Add a yearly
`customers:rotate_key` task calling `Vaultline.rotate` on each sealed column.

**Sanity Check:** run the rotate task in staging against a copy of production, with the app up, and
confirm that customers read correctly throughout.

### Load-bearing assumptions

- Staging's rate of 60 rows per second holds in production.
- Nothing outside the model and the support lookup reads the sealed columns.

### Test strategy

- Unit: getters read both formats; setters write `vl1:` values.
- Integration: `customers:reseal` against a staging copy, then the Phase 2 count.
- End to end: a support lookup by email, in mixed case, after the conversion.
MD

# Each phase heading takes its status tag here, outside the heredoc.
plan=.work/review-target/PLAN.md
text="$(cat "$plan")"
printf '%s\n' "${text//'[STATUS]'/[TODO]}" >"$plan"
