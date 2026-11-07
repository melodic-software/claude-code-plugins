#!/usr/bin/env bash
# A Ruby service: a Gemfile and its source, no .NET project and no dependency-graph.json. The
# convention home declares architecture_dir docs/architecture and diagram_dialect.system c4-plantuml.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs Gemfile app
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh" --dialect c4-plantuml
mkdir -p app/models app/services

cat >Gemfile <<'RUBY'
source "https://rubygems.org"

gem "rails", "~> 7.1"
gem "pg", "~> 1.5"
gem "sidekiq", "~> 7.2"
RUBY

cat >app/models/invoice.rb <<'RUBY'
class Invoice < ApplicationRecord
  has_many :line_items
end
RUBY

cat >app/services/invoice_mailer.rb <<'RUBY'
class InvoiceMailer
  def deliver(invoice)
    InvoiceJob.perform_async(invoice.id)
  end
end
RUBY

git add -A
git commit -q -m "Ruby invoicing service"
mkdir -p docs/architecture
