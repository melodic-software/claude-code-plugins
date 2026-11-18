#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
git checkout -q -b feat/pricing
cat >src/pricing-card.css <<'EOF'
.pricing-card {
  border-radius: 12px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
  padding: 24px;
}
EOF
cat >src/PricingCard.tsx <<'EOF'
import "./pricing-card.css";

export const PricingCard = () => (
  <section className="pricing-card">
    <h2>Pro</h2>
  </section>
);
EOF
git add .
git commit -q -m "feat: add pricing card" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
cat >src/pricing-card.css <<'EOF'
.pricing-card {
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
  padding: 24px;
}
EOF
cat >src/PricingCard.tsx <<'EOF'
import "./pricing-card.css";

export const PricingCard = () => (
  <section className="pricing-card">
    <h2>Professional</h2>
  </section>
);
EOF
git add .
git commit -q -m "style: adjust pricing card"
