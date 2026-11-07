#!/usr/bin/env bash
# Seeds proof.md: a jargon-dense proof sketch whose steps cannot all be put in plain words honestly.
set -euo pipefail

cat >proof.md <<'EOF'
# Proof sketch: the Atiyah-Singer index theorem via the heat equation

1. For an elliptic operator D on a closed manifold M, ind D = Tr(exp(-tD*D)) - Tr(exp(-tDD*)) for
   every t > 0 (McKean-Singer), because the nonzero eigenvalues of D*D and DD* pair up and cancel.
2. As t -> 0 the heat kernel has an asymptotic expansion whose coefficients are local invariants
   built from the curvature of M and of the bundle E.
3. Getzler rescaling shows that for a twisted Dirac operator the constant term of the supertrace
   is the degree-n part of A-hat(M) ch(E).
4. Hence ind D = integral over M of A-hat(M) ch(E), and the general case follows by K-theory.
EOF
