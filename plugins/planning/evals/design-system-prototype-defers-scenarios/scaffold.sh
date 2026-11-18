#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/orders src/notify .work/order-notifications

cat >src/orders/place-order.js <<'JS'
export async function placeOrder(order, db) {
  await db.insert("orders", order);
  return order.id;
}
JS

cat >src/notify/send-email.js <<'JS'
export async function sendEmail(mailClient, to, subject, body) {
  return mailClient.send({ to, subject, body });
}
JS

printf '{ "name": "shop", "type": "module", "scripts": { "test": "node --test" } }\n' >package.json

cat >.work/order-notifications/PLAN.md <<'MD'
# Order notifications

## Brief

### Goal
A customer gets a confirmation email for every order, sent by a notification worker apart from the order service, as a prototype to show the sales team.

### Constraints
- Mailgun is the only email provider under contract.

### Acceptance criteria
- Placing a demo order produces a confirmation email.

### Captured assumptions
- Quality bar: prototype
- Quality requirements deferred (prototype): revisit if it heads for production
- Variation intent: second variant = speculative; existing structure: the order service writes orders, and nothing sends email yet; upstream: none
MD

git add .
git commit -q -m "feat: order service and email client"
